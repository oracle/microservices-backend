# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at https://oss.oracle.com/licenses/upl

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "modules/fsdr/prepare.py"
spec = importlib.util.spec_from_file_location("prepare", SCRIPT)
prepare = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepare)

CONFIGURATION = {"groups": {"uk-london-1": "primary-id", "us-phoenix-1": "standby-id"}, "timeout": "30m"}


def response(data):
    return subprocess.CompletedProcess([], 0, json.dumps({"data": data}), "")


class DestroyPreparationTests(unittest.TestCase):
    def test_script_arguments_and_inherited_cli_environment(self):
        with tempfile.TemporaryDirectory() as directory:
            cli = Path(directory) / "oci"
            cli.write_text(
                f"#!{sys.executable}\n"
                "import json, os, sys\n"
                "with open(os.environ['TEST_CALLS'], 'a') as output:\n"
                "    output.write(json.dumps({'args': sys.argv[1:], 'environment': dict(os.environ)}) + '\\n')\n"
                "print(json.dumps({'data': {'role': 'UNCONFIGURED'}}))\n"
            )
            cli.chmod(0o700)
            calls = Path(directory) / "calls.jsonl"
            for auth in (None, "instance_obo_user", "resource_principal", "api_key"):
                with self.subTest(auth=auth):
                    calls.write_text("")
                    environment = {
                        **{name: value for name, value in os.environ.items() if not name.startswith("OCI_")},
                        "PATH": directory + os.pathsep + os.environ.get("PATH", ""),
                        "TEST_CALLS": str(calls),
                    }
                    if auth is not None:
                        environment.update({
                            "OCI_CLI_AUTH": auth,
                            "OCI_CLI_PROFILE": "runner-profile",
                            "OCI_CLI_CONFIG_FILE": "/runner/config",
                            "OCI_CLI_DELEGATION_TOKEN_FILE": "/runner/delegation-token",
                            "OCI_CLI_KEY_CONTENT": "test-key",
                            "OCI_AUTH": "ResourcePrincipal",
                            "OCI_RESOURCE_PRINCIPAL_VERSION": "2.2",
                        })
                    result = subprocess.run(
                        [sys.executable, str(SCRIPT), "--group", "uk-london-1", "primary-id",
                         "--group", "us-phoenix-1", "standby-id", "--timeout", "30m"],
                        env=environment, capture_output=True, text=True, timeout=10,
                    )
                    self.assertEqual(result.returncode, 0, result.stderr)
                    invocations = [json.loads(line) for line in calls.read_text().splitlines()]
                    self.assertEqual(len(invocations), 2)
                    for invocation, (region, group_id) in zip(invocations, CONFIGURATION["groups"].items()):
                        self.assertEqual(invocation["args"], [
                            "--region", region, "--output", "json", "disaster-recovery",
                            "dr-protection-group", "get", "--dr-protection-group-id", group_id,
                        ])
                        self.assertEqual(
                            {name: value for name, value in invocation["environment"].items() if name.startswith("OCI_")},
                            {name: value for name, value in environment.items() if name.startswith("OCI_")},
                        )

    @patch.object(prepare.shutil, "which", return_value="oci")
    @patch.object(prepare.subprocess, "run")
    def test_disassociates_and_verifies_both_groups(self, run, which):
        run.side_effect = [
            response({"role": "PRIMARY", "peer-region": "us-phoenix-1", "peer-id": "standby-id"}),
            response({"role": "STANDBY", "peer-region": "uk-london-1", "peer-id": "primary-id"}),
            response({"status": "SUCCEEDED"}),
            response({"role": "UNCONFIGURED"}), response({"role": "UNCONFIGURED"}),
        ]
        prepare.prepare(CONFIGURATION)
        self.assertEqual(run.call_count, 5)
        self.assertIn("disassociate", run.call_args_list[2].args[0])
        for call in run.call_args_list:
            self.assertNotIn("env", call.kwargs)

    @patch.object(prepare.shutil, "which", return_value="oci")
    @patch.object(prepare.subprocess, "run")
    def test_authorization_error_stops_preparation(self, run, which):
        run.return_value = subprocess.CompletedProcess([], 1, "", "NotAuthorizedOrNotFound")
        with self.assertRaisesRegex(RuntimeError, "NotAuthorizedOrNotFound"):
            prepare.prepare(CONFIGURATION)
        run.assert_called_once()


if __name__ == "__main__":
    unittest.main()
