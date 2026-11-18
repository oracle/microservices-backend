#!/usr/bin/env python3
# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at https://oss.oracle.com/licenses/upl.
"""Regression tests for 6-smoke_test_secure_services.sh.
Protects automatic service-token discovery and prevents requests with missing IDs.
Runs the real shell script with mocked curl and kubectl commands.
Simulates client-credentials tokens, account discovery, and API responses.
Checks failed discovery, explicit account IDs, and read-only behavior.
Verifies private temporary files, port-forward cleanup, and secret concealment.
Uses synthetic credentials and responses; requires no cluster or network access.
Run: python3 tests/test_secure_services_smoke.py [-v]
Requires Python's standard library, bash, and jq.
Live authorization, database, and deposit behavior still need cluster verification.
"""

import base64
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import time
import unittest
from urllib.parse import parse_qs, urlsplit


SCRIPT = Path(__file__).resolve().parents[1] / "6-smoke_test_secure_services.sh"
ACCOUNTS = [
    {"accountId": 11, "accountBalance": -20},
    {"accountId": 12, "accountBalance": 1035},
    {"accountId": 13, "accountBalance": 500},
]


def trace(entry):
    """Record a synthetic tool call for later request and cleanup assertions."""
    with open(os.environ["SMOKE_TRACE"], "a") as stream:
        stream.write(json.dumps(entry) + "\n")


def mock_kubectl(args):
    """Stand in for cluster reads and a terminable port-forward process."""
    trace({"tool": "kubectl", "args": args, "pid": os.getpid()})
    if "port-forward" in args:
        if os.environ.get("SMOKE_SCENARIO") == "forward-failure":
            return 1
        print(f"Forwarding from 127.0.0.1:{args[-1].split(':')[0]} -> 8080", flush=True)
        while True:
            time.sleep(60)
    if args[:2] == ["config", "current-context"]:
        print("mock-cluster")
    elif args[:2] == ["get", "secret"]:
        if os.environ.get("SMOKE_SCENARIO") == "missing-secret" and "service-client-secret" in args[-1]:
            return 0
        print(base64.b64encode(b"mock-client-secret").decode(), end="")
    elif args[0] not in ("cluster-info", "get"):
        raise AssertionError(f"Unexpected Kubernetes operation: {args}")
    return 0


def mock_curl(args):
    """Emulate curl's response files, headers, and status output for each scenario."""
    def option(name):
        return args[args.index(name) + 1] if name in args else None

    url = next(arg for arg in args if arg.startswith(("http://", "https://")))
    parsed = urlsplit(url)
    query = parse_qs(parsed.query)
    scenario = os.environ.get("SMOKE_SCENARIO", "success")
    data = "&".join(args[i + 1] for i, arg in enumerate(args) if arg == "-d")
    headers = [args[i + 1] for i, arg in enumerate(args) if arg == "-H"]
    trace({"tool": "curl", "url": url, "headers": headers, "data": data})
    status, body = 200, {}
    if "Authorization: Bearer internal-token" in headers:
        assert parsed.hostname == "127.0.0.1" and parsed.path == "/api/v1/accounts"

    if parsed.path == "/oauth2/token":
        fields = parse_qs(data)
        assert fields["grant_type"] == ["client_credentials"]
        scope = fields["scope"][0].split(".")[-1]
        if scope == "internal":
            assert option("-u") == "cloudbank-service-client:mock-client-secret"
        body = {"access_token": f"{scope}-token"}
        if scope == "internal" and scenario == "token-failure":
            status, body = 400, {"error": "invalid_scope"}
    elif parsed.path == "/actuator/health":
        assert parsed.hostname == "127.0.0.1"
        body = {"status": "UP"}
    elif parsed.path == "/oauth2/jwks":
        body = {"keys": [{"kid": "mock-signing-key"}]}
    elif parsed.path == "/api/v1/creditscore":
        status = 200 if "Authorization: Bearer read-token" in headers else 401
    elif parsed.path == "/user/api/v1/ping":
        status = 404
    elif parsed.path == "/api/v1/account/journal":
        status = 403
    elif parsed.path == "/api/v1/accounts":
        if parsed.hostname == "mock-gateway.invalid":
            assert "Authorization: Bearer read-token" in headers
            body = []  # Ownership filtering is valid for the public client.
        else:
            assert parsed.hostname == "127.0.0.1"
            assert "Authorization: Bearer internal-token" in headers
            body = ACCOUNTS
            if scenario == "empty-accounts":
                body = []
            elif scenario == "invalid-accounts":
                body = {"error": "unexpected payload"}
            elif scenario == "no-funded-account":
                body = [{"accountId": 11, "accountBalance": 0}, {"accountId": 12, "accountBalance": 1}]
            elif scenario == "account-error":
                status = 500
    elif parsed.path == "/api/v1/testrunner/deposit":
        payload = json.loads(data)
        assert payload["accountId"] in (11, 12, 13)
        assert payload["amount"] == 1
        status = 201 if "Authorization: Bearer test-token" in headers else 403
    elif parsed.path == "/transfer":
        assert "Authorization: Bearer transfer-token" in headers
        assert int(query["fromAccount"][0]) != int(query["toAccount"][0])
        status = 403
    elif parsed.path != "/.well-known/oauth-authorization-server":
        raise AssertionError(f"Unexpected HTTP request: {url}")

    output = body if isinstance(body, str) else json.dumps(body)
    if option("-o"):
        assert Path(option("-o")).parent.stat().st_mode & 0o077 == 0
        Path(option("-o")).write_text(output)
    elif "-w" not in args:
        print(output, end="")
    if "-w" in args:
        print(status, end="")
    return 0


class SecureServicesSmokeTest(unittest.TestCase):
    """Run the actual shell script with isolated, deterministic tool replacements."""

    def run_smoke(self, scenario="success", options=()):
        """Execute one scenario, verify cleanup, and return its output and call trace."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            binaries = root / "bin"
            binaries.mkdir()
            for name in ("curl", "kubectl"):
                wrapper = binaries / name
                wrapper.write_text(f"#!/bin/sh\nexec {shlex.quote(sys.executable)} {shlex.quote(str(Path(__file__).resolve()))} --mock-{name} \"$@\"\n")
                wrapper.chmod(0o700)
            env = os.environ.copy()
            env.update(PATH=f"{binaries}:{env['PATH']}", TMPDIR=str(root),
                       SMOKE_TRACE=str(root / "trace.jsonl"),
                       SMOKE_SCENARIO=scenario)
            env.pop("CLOUDBANK_OWNER_PASSWORD", None)
            result = subprocess.run(["bash", str(SCRIPT), "-n", "mock", "-d", "demo", "-o", "obaas",
                                     "--gateway-url", "http://mock-gateway.invalid", *options],
                                    env=env, input="", text=True, capture_output=True, timeout=20)
            events = [json.loads(line) for line in (root / "trace.jsonl").read_text().splitlines()] if (root / "trace.jsonl").exists() else []
            self.assertEqual(list(root.glob("cloudbank-smoke.*")), [], "temporary response files were not cleaned")
            for event in events:
                if event["tool"] == "kubectl" and "port-forward" in event["args"]:
                    with self.assertRaises(ProcessLookupError, msg="discovery port-forward survived cleanup"):
                        os.kill(event["pid"], 0)
                if event["tool"] == "kubectl":
                    self.assertNotIn(event["args"][0], ("apply", "patch", "delete", "create"))
            self.assertNotIn("mock-client-secret", result.stdout + result.stderr)
            self.assertNotIn("Password for", result.stdout + result.stderr)
            return result, events

    @staticmethod
    def workflow_requests(events):
        return [e for e in events if e["tool"] == "curl" and urlsplit(e["url"]).path in ("/api/v1/testrunner/deposit", "/transfer")]

    def test_service_discovery_and_original_authorization_checks(self):
        result, events = self.run_smoke()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("from=12 to=11", result.stdout)
        self.assertEqual(len(self.workflow_requests(events)), 3)

    def test_discovery_failures_skip_dependent_requests(self):
        for scenario in ("missing-secret", "forward-failure", "token-failure", "empty-accounts", "invalid-accounts", "no-funded-account", "account-error"):
            with self.subTest(scenario=scenario):
                result, events = self.run_smoke(scenario)
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn("1 failure(s)", result.stdout)
                self.assertEqual(self.workflow_requests(events), [])
                self.assertIn("Skipping deposit and transfer checks", result.stdout)

    def test_explicit_ids_bypass_service_discovery(self):
        result, events = self.run_smoke("missing-secret", options=("--from-account", "12", "--to-account", "11"))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(any(e["tool"] == "kubectl" and ("port-forward" in e["args"] or "service-client-secret" in e["args"][-1]) for e in events))
        self.assertFalse(any(e["tool"] == "curl" and "cloudbank.internal" in e["data"] for e in events))

    def test_internal_token_is_only_used_for_direct_lookup(self):
        result, events = self.run_smoke()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        internal = [e for e in events if e["tool"] == "curl" and "Authorization: Bearer internal-token" in e["headers"]]
        self.assertEqual(len(internal), 1)
        self.assertEqual(internal[0]["url"], "http://127.0.0.1:9081/api/v1/accounts")
        public = [e for e in events if e["tool"] == "curl" and e["url"] == "http://mock-gateway.invalid/api/v1/accounts"]
        self.assertEqual(len(public), 1)
        self.assertIn("Authorization: Bearer read-token", public[0]["headers"])

    def test_partial_id_selection_and_validation(self):
        result, _ = self.run_smoke(options=("--to-account", "12"))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("from=13 to=12", result.stdout)
        for option, value in (("--from-account", "999"), ("--from-account", "11"), ("--to-account", "999")):
            with self.subTest(option=option, value=value):
                result, events = self.run_smoke(options=(option, value))
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertEqual(self.workflow_requests(events), [])

    def test_invalid_ids_fail_before_network_requests(self):
        for options in (("--from-account", "abc"), ("--to-account", "0"), ("--from-account", "12", "--to-account", "12"), ("--discovery-local-port",)):
            with self.subTest(options=options):
                result, events = self.run_smoke(options=options)
                self.assertEqual(result.returncode, 1)
                self.assertEqual(events, [])

    def test_read_only_still_discovers_accounts(self):
        result, events = self.run_smoke(options=("--read-only",))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("from=12 to=11", result.stdout)
        self.assertEqual(self.workflow_requests(events), [])

    def test_keep_gateway_forward_does_not_keep_discovery_forward(self):
        result, _ = self.run_smoke(options=("--keep-port-forward", "--read-only"))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--mock-curl":
        sys.exit(mock_curl(sys.argv[2:]))
    if len(sys.argv) > 1 and sys.argv[1] == "--mock-kubectl":
        sys.exit(mock_kubectl(sys.argv[2:]))
    unittest.main()
