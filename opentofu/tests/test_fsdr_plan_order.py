# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at https://oss.oracle.com/licenses/upl

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


SOURCE = Path(__file__).resolve().parents[1]
KEYS = ("failover", "switchover", "start_drill", "stop_drill")


class PlanOrderTests(unittest.TestCase):
    """Inspect real provider plans with synthetic state, dummy keys, and refresh disabled."""

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="fsdr-plan-order-")
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name)
        for source in (SOURCE / "modules/fsdr/region").glob("*.tf"):
            shutil.copyfile(source, self.path / source.name)
        shutil.copyfile(SOURCE / ".terraform.lock.hcl", self.path / ".terraform.lock.hcl")
        (self.path / ".terraform").mkdir()
        (self.path / ".terraform/providers").symlink_to(SOURCE / ".terraform/providers", target_is_directory=True)
        subprocess.run(["openssl", "genrsa", "-out", str(self.path / "test.pem"), "2048"], check=True, capture_output=True)
        self.write_json("provider.tf.json", {"provider": {"oci": {
            "auth": "APIKey", "region": "uk-london-1",
            "tenancy_ocid": "ocid1.tenancy.oc1..test", "user_ocid": "ocid1.user.oc1..test",
            "fingerprint": ":".join(["00"] * 16), "private_key_path": str(self.path / "test.pem"),
        }}, "resource": {"terraform_data": {"unrelated": {"input": "parallel"}}}})
        self.plans = {key: {
            "display_name": key, "type": key.upper(),
            "dr_protection_group_id": "ocid1.drprotectiongroup.oc1.uk-london-1.test",
        } for key in KEYS}

    def write_json(self, name, value):
        (self.path / name).write_text(json.dumps(value))

    def tofu(self, *arguments):
        environment = {key: value for key, value in os.environ.items()
                       if not key.startswith(("OCI_", "TF_VAR_", "TF_CLI_ARGS"))
                       and key not in ("TF_DATA_DIR", "TF_WORKSPACE")}
        result = subprocess.run(
            ["tofu", f"-chdir={self.path}", *arguments], env=environment,
            capture_output=True, text=True, timeout=60,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout

    def plan(self):
        self.write_json("test.auto.tfvars.json", {
            "compartment_id": "ocid1.compartment.oc1..test", "display_name": "test-group",
            "log_location": {"bucket": "logs", "namespace": "test"}, "plans": self.plans,
        })
        self.tofu("plan", "-refresh=false", "-input=false", "-lock=false", "-out=test.tfplan", "-no-color")
        return json.loads(self.tofu("show", "-json", "test.tfplan"))

    def legacy_state(self):
        self.write_json("terraform.tfstate", {
            "version": 4, "terraform_version": "1.5.7", "serial": 0, "lineage": "fsdr-test", "outputs": {},
            "resources": [{
                "mode": "managed", "type": "oci_disaster_recovery_dr_plan", "name": "dr_plan",
                "provider": 'provider["registry.opentofu.org/oracle/oci"]',
                "instances": [{"schema_version": 0, "index_key": key, "attributes": {
                    **value, "id": f"ocid1.drplan.oc1.uk-london-1.{key}", "state": "ACTIVE",
                    "defined_tags": {}, "freeform_tags": {}, "system_tags": {}, "plan_groups": [],
                    "timeouts": {operation: "20m" for operation in ("create", "update", "delete")},
                    "refresh_trigger": None, "verify_trigger": None, "source_plan_id": None,
                }} for key, value in self.plans.items()],
            }],
        })

    def assert_order(self, keys):
        graph = self.tofu("graph", "-type=apply", "-plan=test.tfplan")
        edges = {}
        for source, target in re.findall(r'"((?:\\.|[^"\\])*)" -> "((?:\\.|[^"\\])*)"', graph):
            edges.setdefault(source, set()).add(target)

        def reaches(source, target):
            pending, visited = [source], set()
            while pending:
                node = pending.pop()
                if node == target:
                    return True
                if node not in visited:
                    visited.add(node)
                    pending.extend(edges.get(node, ()))
            return False

        nodes = []
        for key in keys:
            resource = "dr_plan" if key == "failover" else key
            matches = [node for node in edges if f'oci_disaster_recovery_dr_plan.{resource}[\\"{key}\\"]' in node and not node.endswith("(expand)")]
            self.assertEqual(len(matches), 1, matches)
            nodes.append(matches[0])
        for earlier, later in zip(nodes, nodes[1:]):
            self.assertTrue(reaches(later, earlier), f"{later} must wait for {earlier}")
        self.assertIn("[root] terraform_data.unrelated", edges)
        for node in nodes:
            self.assertFalse(reaches(node, "[root] terraform_data.unrelated"))
            self.assertFalse(reaches("[root] terraform_data.unrelated", node))

    def test_upgrade_preserves_standard_and_custom_plans(self):
        self.plans["custom"] = {**self.plans["failover"], "display_name": "custom"}
        self.legacy_state()
        changes = [change for change in self.plan()["resource_changes"] if change["type"] == "oci_disaster_recovery_dr_plan"]
        self.assertEqual(len(changes), 5)
        for resource in changes:
            self.assertEqual(resource["change"]["actions"], ["no-op"])
            self.assertEqual(resource["change"]["before"]["id"], resource["change"]["after"]["id"])
        self.assertEqual(sum("previous_address" in change for change in changes), 3)

    def test_creation_and_refresh_are_ordered(self):
        self.plan()
        self.assert_order(KEYS)
        self.legacy_state()
        for plan in self.plans.values():
            plan["refresh_trigger"] = 1
        self.plan()
        self.assert_order(KEYS)

    def test_order_survives_missing_intermediate_plans(self):
        self.plans = {key: self.plans[key] for key in ("failover", "stop_drill")}
        self.plan()
        self.assert_order(("failover", "stop_drill"))


if __name__ == "__main__":
    unittest.main()
