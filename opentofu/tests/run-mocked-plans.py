#!/usr/bin/env python3
# Copyright (c) 2024, 2026, Oracle and/or its affiliates.
# All rights reserved. The Universal Permissive License (UPL), Version 1.0 as shown at http://oss.oracle.com/licenses/upl

"""Run mocked IaC suites in temporary copies with isolated inputs and state."""

import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


def copy_configuration(source, destination):
    """Copy configuration, templates, and the root provider lockfile."""
    for path in source.rglob("*"):
        relative = path.relative_to(source)
        if relative.parts[0] == "tests" or any(part.startswith(".") for part in relative.parts):
            continue
        if not path.is_file():
            continue
        if path.suffix != ".tf" and "templates" not in relative.parts and not (path.suffix == ".py" and ("cfgmgt" in relative.parts or "fsdr" in relative.parts)):
            continue
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, target)
    shutil.copyfile(source / ".terraform.lock.hcl", destination / ".terraform.lock.hcl")


def check_suite(path):
    """Require plans except targeted cluster and local label fixtures."""
    content = path.read_text()
    runs = re.findall(r'^\s*run\s+"[^"]+"\s*\{', content, re.MULTILINE)
    plans = re.findall(r"^\s*command\s*=\s*plan\s*$", content, re.MULTILINE)
    fixtures = re.findall(
        r'run "setup_cluster"\s*\{\s*command\s*=\s*apply\s*'
        r'plan_options\s*\{\s*target\s*=\s*\[oci_containerengine_cluster\.default_cluster\]\s*\}\s*\}',
        content,
    )
    label_fixtures = re.findall(
        r'run "persist_generated_label"\s*\{\s*command\s*=\s*apply\s*'
        r'plan_options\s*\{\s*target\s*=\s*\[random_pet\.label\]\s*\}\s*\}',
        content,
    )
    if not runs or len(runs) != len(plans) + len(fixtures) + len(label_fixtures):
        raise ValueError(f"{path}: each run must plan or use a targeted fixture")
    providers = re.findall(r'^\s*provider\s+"([^"]+)"', content, re.MULTILINE)
    if any(provider != "random" or not label_fixtures for provider in providers):
        raise ValueError(f"{path}: only the local label fixture may use a real random provider")
    if not re.search(r'^\s*mock_provider\s+"', content, re.MULTILINE):
        raise ValueError(f"{path}: a mocked provider is required")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tofu", default="tofu", help="OpenTofu executable")
    parser.add_argument("--module", action="append", default=[], help="Run only this module path, such as modules/kubernetes")
    args = parser.parse_args()
    source = Path(__file__).resolve().parent.parent
    tests = source / "tests"
    suites = sorted(tests.rglob("*.tftest.hcl"))
    modules = {suite.parent.relative_to(tests) for suite in suites}
    if args.module:
        selected = {Path(module) for module in args.module}
        if selected - modules:
            parser.error("--module must select a directory containing a test suite")
        modules = selected
    for suite in suites:
        check_suite(suite)

    # Operator overrides and CLI options must stay outside the test configuration.
    environment = {
        key: value for key, value in os.environ.items()
        if not key.startswith(("TF_VAR_", "TF_CLI_ARGS")) and key not in ("TF_DATA_DIR", "TF_WORKSPACE")
    }
    environment["TF_IN_AUTOMATION"] = "1"
    environment["TF_INPUT"] = "0"

    with tempfile.TemporaryDirectory(prefix="obaas-iac-tests-") as directory:
        snapshot = Path(directory)
        copy_configuration(source, snapshot)
        for suite in suites:
            target = snapshot / suite.parent.relative_to(tests) / "tests" / suite.name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(suite, target)
        providers = source / ".terraform" / "providers"
        for relative in sorted(modules):
            module = snapshot / relative
            if module != snapshot:
                shutil.copyfile(snapshot / ".terraform.lock.hcl", module / ".terraform.lock.hcl")
            if providers.is_dir():
                (module / ".terraform").mkdir(exist_ok=True)
                (module / ".terraform" / "providers").symlink_to(providers, target_is_directory=True)
            print(f"Testing {relative}", flush=True)
            initialize = ["init", "-backend=false", "-no-color"]
            if module == snapshot:
                initialize.append("-lockfile=readonly")
            for command in (
                initialize,
                ["test", "-no-color"],
            ):
                subprocess.run([args.tofu, f"-chdir={module}", *command], env=environment, check=True)


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.returncode) from None
