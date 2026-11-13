#!/usr/bin/env python3
# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at http://oss.oracle.com/licenses/upl.
"""Check API discovery and preserve dashboard format compatibility."""

import importlib.util
import io
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

CHART = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("importer", CHART / "scripts/import-dashboards.py")
importer = importlib.util.module_from_spec(SPEC)
sys.dont_write_bytecode = True
SPEC.loader.exec_module(importer)
ORG_ID = "01a16416-98e2-7709-b4a8-584fddf3a379"
URL = "http://signoz:8080"


class ImporterTest(unittest.TestCase):
    def login(self, orgs, explicit=None):
        with tempfile.TemporaryDirectory() as directory:
            auth = Path(directory)
            (auth / "email").write_text("admin+setup@example.com")
            (auth / "password").write_text('special"\\password\n')
            if explicit is not None:
                (auth / "orgID").write_text(explicit)
            responses = [{"data": {"orgs": orgs}}, {"data": {"accessToken": "jwt"}}]
            if explicit:
                responses.pop(0)
            with patch.object(importer, "request", side_effect=responses) as request:
                token = importer.login(URL, auth)
            return token, request.call_args_list

    def test_api_discovery_and_json_credentials(self):
        token, calls = self.login([{"id": ORG_ID}], explicit="")
        self.assertEqual(token, "jwt")
        self.assertIn("email=admin%2Bsetup%40example.com", calls[0].args[0])
        self.assertEqual(calls[1].kwargs['payload'], {
            "email": "admin+setup@example.com", "password": 'special"\\password', "orgID": ORG_ID,
        })

    def test_explicit_org_skips_discovery(self):
        _, calls = self.login([], explicit=ORG_ID)
        self.assertEqual(len(calls), 1)
        self.assertTrue(calls[0].args[0].endswith("/api/v2/sessions/email_password"))

    def test_invalid_or_ambiguous_discovery_fails(self):
        for orgs in [[], [{"id": ORG_ID}] * 2, [{"id": "invalid"}]]:
            with self.subTest(orgs=orgs), self.assertRaises(ValueError):
                self.login(orgs)

    def test_readiness_retries(self):
        with patch.object(importer, "request", side_effect=[importer.HTTPError(URL, 503, "unready", {}, io.BytesIO()), {}]):
            with patch.object(importer.time, "sleep") as sleep:
                importer.wait_until_ready(URL)
        sleep.assert_called_once_with(5)

    def test_v2_pagination_and_legacy_exact_title_replacement(self):
        def record(title, **fields):
            return dict(spec={"display": {"name": title}}, **fields)
        responses = [
            {"data": {"dashboards": [record("App", id="old", legacy=True)], "total": 2}},
            {"data": {"dashboards": [record("Other", id="user")], "total": 2}},
            None, {},
        ]
        with patch.object(importer, "request", side_effect=responses) as request:
            importer.reconcile(URL, "jwt", {"App": dict(record("App"), schemaVersion="v6")})
        calls = request.call_args_list
        self.assertIn("offset=1", calls[1].args[0])
        self.assertTrue(calls[2].args[0].endswith("/api/v2/dashboards/old"))
        self.assertEqual(calls[2].kwargs['method'], "DELETE")
        self.assertEqual(calls[3].kwargs['method'], "POST")
        self.assertEqual(len(calls), 4)

    def test_v1_fallback_preserved(self):
        with patch.object(importer, "request", side_effect=[
            importer.DashboardAPIUnavailable(), {"data": []}, {},
        ]) as request:
            importer.reconcile(URL, "jwt", {"App": {"version": "v5", "title": "App"}})
        self.assertTrue(request.call_args_list[-1].args[0].endswith("/api/v1/dashboards"))

    def test_v1_rejects_v2_before_deletion(self):
        with patch.object(importer, "list_dashboards", return_value=("v1", [])):
            with patch.object(importer, "request") as request, self.assertRaises(ValueError):
                importer.reconcile(URL, "jwt", {"App": {"schemaVersion": "v6"}})
        request.assert_not_called()

    def test_pagination_failure_stops_reconciliation(self):
        with patch.object(importer, "request", return_value={"data": {"dashboards": [], "total": 1}}) as request:
            with self.assertRaises(ValueError):
                importer.reconcile(URL, "jwt", {"App": {}})
        self.assertEqual(request.call_count, 1)

    def test_bundled_sample(self):
        self.assertTrue(importer.load_dashboards(CHART / "dashboards"))

    @unittest.skipUnless(shutil.which("helm"), "Helm unavailable")
    def test_job_has_no_database_mount_or_init_containers(self):
        result = subprocess.run(["helm", "template", "dashboards-test", str(CHART)],
                                capture_output=True, text=True, check=True)
        job = next(doc for doc in result.stdout.split("\n---") if "kind: Job" in doc)
        self.assertIn("command: [python3, -u, /scripts/import-dashboards.py]", job)
        self.assertIn("os/oraclelinux:9", job)
        for removed in ["signoz-db", "shared-data", "affinity:", "initContainers:"]:
            self.assertNotIn(removed, job)


if __name__ == "__main__":
    unittest.main()
