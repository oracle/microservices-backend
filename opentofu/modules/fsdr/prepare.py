# Copyright (c) 2026, Oracle and/or its affiliates.
# All rights reserved. The Universal Permissive License (UPL), Version 1.0 as shown at http://oss.oracle.com/licenses/upl

"""Disassociate an existing FSDR pair before Terraform deletes its groups."""

import argparse
import json
import math
import re
import shutil
import subprocess
import sys
import time


def timeout_seconds(value):
    parts = re.findall(r"(\d+(?:\.\d+)?)(h|m|s)", value)
    if not parts or "".join(number + unit for number, unit in parts) != value:
        raise ValueError("FSDR update timeout must use hours, minutes or seconds.")
    seconds = sum(float(number) * {"h": 3600, "m": 60, "s": 1}[unit] for number, unit in parts)
    if seconds <= 0:
        raise ValueError("FSDR update timeout must be positive.")
    return seconds


def prepare(configuration):
    executable = shutil.which("oci")
    if executable is None:
        raise RuntimeError("FSDR destroy preparation requires the OCI CLI on the Terraform runner.")
    groups = configuration["groups"]
    if len(groups) != 2 or len(set(groups.values())) != 2 or not all(groups.values()):
        raise ValueError("FSDR destroy preparation requires two existing regional protection groups.")
    deadline = time.monotonic() + timeout_seconds(configuration["timeout"])

    def remaining():
        seconds = deadline - time.monotonic()
        if seconds <= 0:
            raise TimeoutError("Timed out waiting for both FSDR protection groups to be disassociated.")
        return seconds

    def command(region, operation, group_id, *arguments):
        result = subprocess.run(
            [executable, "--region", region, "--output", "json", "disaster-recovery",
             "dr-protection-group", operation, "--dr-protection-group-id", group_id, *arguments],
            capture_output=True,
            text=True,
            timeout=remaining(),
            check=False,
        )
        if result.returncode:
            raise RuntimeError(result.stderr.strip() or f"OCI FSDR {operation} failed in {region}.")
        return json.loads(result.stdout)["data"]

    live_groups = {region: command(region, "get", group_id) for region, group_id in groups.items()}
    for region, group in live_groups.items():
        if group["role"] == "UNCONFIGURED":
            continue
        if group["role"] not in ("PRIMARY", "STANDBY"):
            raise RuntimeError(f"Unexpected FSDR protection-group role in {region}: {group['role']}.")
        if groups.get(group.get("peer-region")) != group.get("peer-id"):
            raise RuntimeError(f"FSDR protection group in {region} has an unexpected peer.")
        response = command(
            region, "disassociate", groups[region], "--type", "DEFAULT",
            "--wait-for-state", "SUCCEEDED", "--wait-for-state", "FAILED",
            "--wait-for-state", "CANCELED", "--max-wait-seconds", str(math.ceil(remaining())),
        )
        if response["status"] != "SUCCEEDED":
            raise RuntimeError(f"FSDR disassociation work request ended with {response['status']}.")
        live_groups = {region: command(region, "get", group_id) for region, group_id in groups.items()}
        break

    while not all(group["role"] == "UNCONFIGURED" for group in live_groups.values()):
        time.sleep(min(5, remaining()))
        live_groups = {region: command(region, "get", group_id) for region, group_id in groups.items()}
    print("Both FSDR protection groups are disassociated.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--group", nargs=2, action="append", required=True, metavar=("REGION", "OCID"))
    parser.add_argument("--timeout", required=True)
    args = parser.parse_args()
    try:
        prepare({"groups": dict(args.group), "timeout": args.timeout})
    except (KeyError, ValueError, OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"FSDR destroy preparation failed: {error}", file=sys.stderr)
        raise SystemExit(1) from None
