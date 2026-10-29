#!/usr/bin/env python3
# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at http://oss.oracle.com/licenses/upl.
"""Reconcile bundled OBaaS system dashboards through the SigNoz V2 API."""

import json
import os
from pathlib import Path
import sys
import time
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlencode
from urllib.request import Request, urlopen
from uuid import UUID


class SigNoz:
    def __init__(self, url):
        self.url = url.rstrip("/")
        self.token = None

    def request(self, method, path, payload=None):
        headers = {}
        if self.token:
            headers["Authorization"] = "Bearer " + self.token
        body = None
        if payload is not None:
            headers["Content-Type"] = "application/json"
            body = json.dumps(payload).encode("utf-8")
        request = Request(self.url + path, data=body, headers=headers, method=method)
        try:
            with urlopen(request, timeout=30) as response:
                content = response.read()
        except HTTPError as error:
            # Error bodies may contain credentials or tokens; do not log them.
            raise RuntimeError(f"SigNoz {method} {path.split('?')[0]}: HTTP {error.code}") from None
        except (URLError, TimeoutError) as error:
            raise RuntimeError(f"SigNoz {method} {path.split('?')[0]}: connection failed") from error
        return json.loads(content) if content else None

    def wait_until_ready(self):
        while True:
            try:
                self.request("GET", "/api/v1/health?live=1")
                print("query-service ready.", flush=True)
                return
            except (RuntimeError, ValueError):
                print("Waiting for query-service...", flush=True)
                time.sleep(5)

    def login(self, auth_directory):
        email = (auth_directory / "email").read_text().strip()
        password = (auth_directory / "password").read_text().rstrip("\r\n")
        org_file = auth_directory / "orgID"
        org_id = org_file.read_text().strip() if org_file.exists() else ""
        if not org_id:
            context = self.request("GET", "/api/v2/sessions/context?" + urlencode({"email": email}))
            orgs = context["data"]["orgs"]
            if len(orgs) != 1:
                raise ValueError(
                    f"Expected one organization for the configured email; found {len(orgs)}. "
                    "Set orgID in the credential secret to select one explicitly."
                )
            org_id = orgs[0]["id"]
        UUID(org_id)
        response = self.request("POST", "/api/v2/sessions/email_password", {
            "email": email, "password": password, "orgID": org_id,
        })
        token = response["data"]["accessToken"]
        if not isinstance(token, str) or not token:
            raise ValueError("SigNoz login returned no access token")
        self.token = token
        print("Login successful", flush=True)

    def dashboards(self):
        dashboards = []
        offset = 0
        while True:
            data = self.request("GET", f"/api/v2/dashboards?limit=200&offset={offset}")["data"]
            page, total = data["dashboards"], data["total"]
            if not isinstance(page, list) or type(total) is not int or total < 0:
                raise ValueError("Invalid SigNoz dashboard list response")
            dashboards.extend(page)
            offset += len(page)
            if offset >= total:
                return dashboards
            if not page:
                raise ValueError("SigNoz dashboard pagination stopped before reaching total")


def load_dashboards(directories):
    dashboards = []
    for directory in directories:
        for path in sorted(directory.glob("*.json")):
            dashboard = json.loads(path.read_text())
            if "schemaVersion" not in dashboard and dashboard.get("version") in ("v4", "v5"):
                # The shell importer also skipped bundled legacy payloads.
                print(f"Skipping legacy dashboard: {path.name}", flush=True)
                continue
            if dashboard.get("schemaVersion") != "v6":
                raise ValueError(f"Expected a V2/Perses dashboard in {path}")
            title = dashboard["spec"]["display"]["name"]
            if not isinstance(title, str) or not title:
                raise ValueError(f"Missing dashboard name in {path}")
            dashboards.append(dashboard)
    if not dashboards:
        raise ValueError("No bundled dashboards found")
    return dashboards


def reconcile(client, dashboards):
    titles = {dashboard["spec"]["display"]["name"] for dashboard in dashboards}
    # Fetch every page before deleting, so deletions cannot shift pagination.
    existing = client.dashboards()
    for dashboard in existing:
        title = dashboard.get("spec", {}).get("display", {}).get("name")
        if title in titles:
            # V2 also lists unmigratable V1 dashboards as legacy records.
            client.request("DELETE", "/api/v2/dashboards/" + quote(dashboard["id"], safe=""))
    for dashboard in dashboards:
        print("Creating dashboard: " + dashboard["spec"]["display"]["name"], flush=True)
        client.request("POST", "/api/v2/dashboards", dashboard)
    print("SigNoz setup complete", flush=True)


def main():
    dashboards = load_dashboards([Path("/signoz-dashboards-1"), Path("/signoz-dashboards-2")])
    client = SigNoz(os.environ["SIGNOZ_URL"])
    client.wait_until_ready()
    client.login(Path("/signoz-authn"))
    reconcile(client, dashboards)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, ValueError, KeyError, TypeError, OSError) as error:
        # Malformed API responses and secret files must not leak their contents.
        message = str(error) if isinstance(error, RuntimeError) else "Invalid setup input or API response"
        print("ERROR: " + message, file=sys.stderr)
        sys.exit(1)
