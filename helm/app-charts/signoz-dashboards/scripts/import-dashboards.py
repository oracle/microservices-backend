# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at http://oss.oracle.com/licenses/upl.
"""Reconcile dashboard titles through the deployed SigNoz dashboard API."""

import json
import os
from contextlib import closing
from pathlib import Path
import sqlite3
import sys
import time
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


class DashboardAPIUnavailable(Exception):
    """Older SigNoz serves the frontend HTML for unknown API routes."""


def request(url, method="GET", payload=None, token=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    body = None if payload is None else json.dumps(payload).encode()
    with urlopen(Request(url, data=body, headers=headers, method=method), timeout=30) as response:
        content = response.read()
        if response.headers.get_content_type() == "text/html":
            raise DashboardAPIUnavailable("Endpoint returned frontend HTML instead of API JSON")
        return json.loads(content) if content else None


def discover_org_id(database, output):
    # Read the live SQLite database without writing to SigNoz's PVC.
    with closing(sqlite3.connect(f"{database.as_uri()}?mode=ro", uri=True)) as connection:
        organization = connection.execute("SELECT id FROM organizations LIMIT 1").fetchone()
    if not organization or not organization[0]:
        raise ValueError("No organization ID found in SigNoz database")
    output.write_text(str(organization[0]))
    print("SigNoz organization ID discovered", flush=True)


def load_dashboards(directory):
    dashboards = {}
    for path in sorted(directory.glob("*.json")):
        dashboard = json.loads(path.read_text())
        if dashboard.get("schemaVersion") == "v6":
            title = dashboard.get("spec", {}).get("display", {}).get("name")
        elif "schemaVersion" not in dashboard and dashboard.get("version") in ("v4", "v5"):
            title = dashboard.get("title")
        else:
            raise ValueError(f"{path.name}: expected a V1 (v4/v5) or V2 (v6) dashboard export")
        if not isinstance(title, str) or not title.strip():
            raise ValueError(f"{path.name}: missing dashboard title")
        if title in dashboards:
            raise ValueError(f"Duplicate dashboard title: {title}")
        dashboards[title] = dashboard
    if not dashboards:
        raise ValueError("No dashboard JSON files found")
    return dashboards


def list_dashboards(url, token):
    # OBaaS 2.1.0 / SigNoz v0.113 serves HTML, not 404, for the unknown V2 route.
    try:
        page = request(f"{url}/api/v2/dashboards?limit=200&offset=0", token=token)["data"]
    except (DashboardAPIUnavailable, HTTPError) as error:
        if isinstance(error, HTTPError) and error.code not in (404, 405, 501):
            raise
        records = request(f"{url}/api/v1/dashboards", token=token)["data"]
        if not isinstance(records, list):
            raise ValueError("Invalid V1 dashboard list response")
        return "v1", records

    # Fetch all pages before changing the collection, so deletes cannot shift offsets.
    existing = []
    offset = 0
    while True:
        records = page["dashboards"]
        if not isinstance(records, list) or not isinstance(page["total"], int):
            raise ValueError("Invalid V2 dashboard list response")
        existing.extend(records)
        offset += len(records)
        if offset >= page["total"]:
            break
        if not records:
            raise ValueError("Dashboard listing ended before its reported total")
        page = request(f"{url}/api/v2/dashboards?limit=200&offset={offset}", token=token)["data"]
    return "v2", existing


def reconcile(url, token, dashboards):
    api_version, existing = list_dashboards(url, token)
    print(f"Using SigNoz dashboards API {api_version}", flush=True)
    if api_version == "v1" and any("schemaVersion" in dashboard for dashboard in dashboards.values()):
        raise ValueError("This SigNoz instance requires V1 exports (version v4/v5); V2/v6 files cannot be imported")

    # Match exact titles, including legacy records, as in the OBaaS setup Job.
    # V1 summaries nest titles in data; V2 summaries use spec.display.name.
    for dashboard in existing:
        if api_version == "v1":
            title = dashboard.get("data", {}).get("title")
        else:
            title = dashboard.get("spec", {}).get("display", {}).get("name")
        if title in dashboards:
            dashboard_id = dashboard["id"]
            print(f"Deleting existing dashboard: {title} ({dashboard_id})", flush=True)
            request(f"{url}/api/{api_version}/dashboards/{dashboard_id}", method="DELETE", token=token)
    for title, dashboard in dashboards.items():
        print(f"Creating dashboard: {title}", flush=True)
        # Newer SigNoz accepts V1 exports on V2 POST and converts them server-side.
        request(f"{url}/api/{api_version}/dashboards", method="POST", payload=dashboard, token=token)
    print("SigNoz dashboard setup complete", flush=True)


def main():
    if sys.argv[1:] == ["--discover-org"]:
        discover_org_id(Path("/signoz-db/signoz.db"), Path("/shared/orgID"))
        return
    url = os.environ["SIGNOZ_URL"].rstrip("/")
    if sys.argv[1:] == ["--wait"]:
        while True:
            try:
                request(f"{url}/api/v1/health?live=1")
                return
            except (URLError, TimeoutError):
                print("Waiting for SigNoz...", flush=True)
                time.sleep(5)

    # Validate every local file before deleting any existing dashboards.
    dashboards = load_dashboards(Path("/dashboards"))
    auth = Path("/signoz-authn")
    org_path = Path("/shared/orgID")
    if not org_path.is_file():
        org_path = auth / "orgID"
    credentials = {
        "email": (auth / "email").read_text().strip(),
        "password": (auth / "password").read_text(),
        "orgID": org_path.read_text().strip(),
    }
    login = request(f"{url}/api/v2/sessions/email_password", method="POST", payload=credentials)
    token = login.get("data", login).get("accessToken")
    if not token:
        raise ValueError("SigNoz login returned no access token")
    reconcile(url, token, dashboards)


if __name__ == "__main__":
    try:
        main()
    except HTTPError as error:
        # Do not print response bodies that could contain authentication data.
        print(f"SigNoz API request failed: HTTP {error.code}", file=sys.stderr)
        sys.exit(1)

