# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at http://oss.oracle.com/licenses/upl.
"""Install bundled dashboards and alert rules through the SigNoz API."""

import json
import os
import re
from pathlib import Path
import sys
import time
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlencode
from urllib.request import Request, urlopen
from uuid import UUID


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


def wait_until_ready(url):
    while True:
        try:
            request(f"{url}/api/v1/health?live=1")
            print("SigNoz ready", flush=True)
            return
        except (URLError, TimeoutError, DashboardAPIUnavailable):
            print("Waiting for SigNoz...", flush=True)
            time.sleep(5)


def login(url, auth):
    email = (auth / "email").read_text().strip()
    password = (auth / "password").read_text().rstrip("\r\n")
    org_path = auth / "orgID"
    org_id = org_path.read_text().strip() if org_path.exists() else ""
    if not org_id:
        context = request(f"{url}/api/v2/sessions/context?" + urlencode({"email": email}))
        orgs = context["data"]["orgs"]
        if len(orgs) != 1:
            raise ValueError(
                f"Expected one organization for the configured email; found {len(orgs)}. "
                "Set orgID in the credential secret to select one explicitly."
            )
        org_id = orgs[0]["id"]
    UUID(org_id)
    response = request(f"{url}/api/v2/sessions/email_password", method="POST", payload={
        "email": email, "password": password, "orgID": org_id,
    })
    token = response.get("data", response).get("accessToken")
    if not isinstance(token, str) or not token:
        raise ValueError("SigNoz login returned no access token")
    print("Login successful", flush=True)
    return token


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
    return dashboards


ALERT_OWNER_LABEL = "obaas_helm_owner"


def inventory_rule(entry):
    """Convert the supported schemaVersion 1 PromQL inventory into a v2 rule."""
    condition = entry["condition"]
    evaluation = entry["evaluation"]
    notification = entry["notification"]
    # These inventory settings lack the extra parameters required by the API
    # when enabled. Reject them rather than silently choose new alert behavior.
    if (entry["queryType"] != "promql" or condition["windowType"] != "Rolling"
            or condition["operator"] != "ABOVE" or condition["occurrence"] != "AT LEAST ONCE"
            or evaluation["unit"] != "Minutes"
            or evaluation["alertOnNoData"] is not False
            or evaluation["minimumDataRequired"] is not False
            or notification["repeat"] is not False):
        raise ValueError("Unsupported inventory settings; use a native SigNoz API rule for this alert")
    window = re.fullmatch(r"Last ([1-9][0-9]*) minutes?", condition["window"], re.IGNORECASE)
    if (not window or type(evaluation["every"]) is not int or evaluation["every"] <= 0
            or type(entry["enabled"]) is not bool
            or not isinstance(entry["query"], str) or not entry["query"].strip()
            or not isinstance(condition["query"], str) or not condition["query"].strip()
            or not isinstance(condition["thresholdName"], str) or not condition["thresholdName"].strip()
            or type(condition["thresholdValue"]) not in (int, float)
            or not isinstance(notification["channel"], str) or not notification["channel"].strip()
            or not isinstance(notification["message"], str)
            or not isinstance(notification["groupBy"], list)
            or not all(isinstance(label, str) for label in notification["groupBy"])):
        raise ValueError("Invalid inventory query, threshold, timing, enabled state, or notification settings")
    return {
        "alert": entry["name"], "disabled": not entry["enabled"],
        "schemaVersion": "v2alpha1", "version": "v5",
        "alertType": "METRIC_BASED_ALERT", "ruleType": "promql_rule",
        "labels": entry.get("labels", {}),
        "annotations": {"description": notification["message"]},
        "condition": {
            "compositeQuery": {
                "queryType": "promql", "panelType": "graph",
                "queries": [{"type": "promql", "spec": {
                    "name": condition["query"], "query": entry["query"],
                }}],
            },
            "selectedQueryName": condition["query"],
            "alertOnAbsent": False, "requireMinPoints": False,
            "thresholds": {"kind": "basic", "spec": [{
                "name": condition["thresholdName"], "op": "above",
                "matchType": "at_least_once", "target": condition["thresholdValue"],
                "channels": [notification["channel"]],
            }]},
        },
        "evaluation": {"kind": "rolling", "spec": {
            "evalWindow": f"{window[1]}m", "frequency": f"{evaluation['every']}m",
        }},
        "notificationSettings": {
            "groupBy": notification["groupBy"], "renotify": {"enabled": False}, "usePolicy": False,
        },
    }


def load_alerts(directory, owner):
    alerts = {}
    for path in sorted(directory.glob("*.json")):
        document = json.loads(path.read_text())
        if not isinstance(document, dict):
            raise ValueError(f"{path.name}: expected a SigNoz rule or schemaVersion 1 inventory")
        if "alerts" in document:
            if type(document.get("schemaVersion")) is not int or document["schemaVersion"] != 1:
                raise ValueError(f"{path.name}: unsupported inventory schemaVersion")
            entries = document["alerts"]
            if not isinstance(entries, list) or not entries or not all(isinstance(e, dict) for e in entries):
                raise ValueError(f"{path.name}: alerts must be a non-empty array of objects")
            try:
                rules = [inventory_rule(entry) for entry in entries]
            except (KeyError, TypeError, ValueError) as error:
                raise ValueError(f"{path.name}: invalid or unsupported alert inventory: {error}") from error
        else:
            rules = [document]
        for rule in rules:
            name = rule.get("alert")
            if not isinstance(name, str) or not name.strip() or not isinstance(rule.get("condition"), dict):
                raise ValueError(f"{path.name}: expected a SigNoz rule with alert and condition fields")
            if name in alerts:
                raise ValueError(f"Duplicate alert name: {name}")
            labels = rule.setdefault("labels", {})
            if not isinstance(labels, dict):
                raise ValueError(f"{path.name}: labels must be an object")
            if labels.get(ALERT_OWNER_LABEL, owner) != owner:
                raise ValueError(f"{path.name}: reserved ownership label conflicts with this release")
            labels[ALERT_OWNER_LABEL] = owner
            # API read responses include server-managed fields that are not write input.
            for field in ("id", "state", "createdAt", "updatedAt", "createdBy", "updatedBy"):
                rule.pop(field, None)
            alerts[name] = rule
    return alerts


def reconcile_alerts(url, token, alerts, owner):
    existing = request(f"{url}/api/v2/rules", token=token)["data"]
    if not isinstance(existing, list):
        raise ValueError("Invalid alert rule list response; expected SigNoz v0.142.1 API")
    matches = {}
    # Check every match before changing any rule. Never adopt an unrelated rule.
    for rule in existing:
        name = rule["alert"]
        if name not in alerts:
            continue
        if name in matches or rule.get("labels", {}).get(ALERT_OWNER_LABEL) != owner:
            raise ValueError(f"Ambiguous or unmanaged existing alert: {name}")
        matches[name] = quote(rule["id"], safe="")
    for name, rule in alerts.items():
        rule_id = matches.get(name)
        endpoint = f"{url}/api/v2/rules" + (f"/{rule_id}" if rule_id else "")
        print(f"{'Updating' if rule_id else 'Creating'} alert: {name}", flush=True)
        request(endpoint, method="PUT" if rule_id else "POST", payload=rule, token=token)


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
        if not isinstance(records, list) or type(page["total"]) is not int or page["total"] < 0:
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
            dashboard_id = quote(dashboard["id"], safe="")
            print(f"Deleting existing dashboard: {title} ({dashboard_id})", flush=True)
            request(f"{url}/api/{api_version}/dashboards/{dashboard_id}", method="DELETE", token=token)
    for title, dashboard in dashboards.items():
        print(f"Creating dashboard: {title}", flush=True)
        # Newer SigNoz accepts V1 exports on V2 POST and converts them server-side.
        request(f"{url}/api/{api_version}/dashboards", method="POST", payload=dashboard, token=token)
    print("SigNoz dashboard setup complete", flush=True)


def main():
    # Validate every local file before changing anything in SigNoz.
    dashboards = load_dashboards(Path("/dashboards"))
    owner = os.environ["SIGNOZ_IMPORT_OWNER"]
    alerts = load_alerts(Path("/alerts"), owner)
    if not dashboards and not alerts:
        raise ValueError("No dashboard or alert JSON files found")
    url = os.environ["SIGNOZ_URL"].rstrip("/")
    wait_until_ready(url)
    token = login(url, Path("/signoz-authn"))
    if alerts:
        reconcile_alerts(url, token, alerts, owner)
    if dashboards:
        reconcile(url, token, dashboards)


if __name__ == "__main__":
    try:
        main()
    except HTTPError as error:
        # Do not print response bodies that could contain authentication data.
        print(f"SigNoz API request failed: HTTP {error.code}", file=sys.stderr)
        sys.exit(1)

    except ValueError as error:
        print(f"SigNoz setup failed: {error}", file=sys.stderr)
        sys.exit(1)

    except (KeyError, TypeError, OSError, DashboardAPIUnavailable):
        print("SigNoz setup failed: invalid setup input, API response, or connection", file=sys.stderr)
        sys.exit(1)
