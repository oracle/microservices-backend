#!/usr/bin/env python3
"""
Copyright (c) 2026, Oracle and/or its affiliates.
Licensed under the Universal Permissive License v1.0 as shown at http://oss.oracle.com/licenses/upl.

Build script that packages OCI terraform configuration.

This script:
1. Copies the repository's opentofu configuration to a temporary directory
2. Vendors the local Helm charts where cfgmgt/apply.py expects to find them
3. Creates a zip archive and places it in the infra-charts stage folder
"""
import os
import sys
import argparse
import fnmatch
import shutil
import tempfile
from pathlib import Path

# Patterns to exclude from the build
EXCLUDE_PATTERNS = [
    "terraform.tfstate",
    "terraform.tfstate.backup",
    "*.tfvars",
    "*.pem",
    ".terraform",
    ".terraform.lock.hcl",
    ".terraform.tfstate.lock.info",
    "__pycache__",
    "*.pyc",
    "stage",
    ".gitignore",
]
# Max Stack Size
MAX_STACK_SIZE_MB = 11
LOCAL_CHART_NAMES = ("obaas-prereqs", "obaas")


def ignore_patterns(directory, files):
    """Return list of files to ignore during copytree."""
    ignored = []
    for f in files:
        for pattern in EXCLUDE_PATTERNS:
            if fnmatch.fnmatch(f, pattern):
                ignored.append(f)
                break
    return ignored


def validate_local_charts(helm_src):
    missing_charts = [
        chart_name
        for chart_name in LOCAL_CHART_NAMES
        if not (helm_src / chart_name / "Chart.yaml").exists()
    ]
    if missing_charts:
        missing = ", ".join(missing_charts)
        raise FileNotFoundError(f"Local Helm chart(s) not found under {helm_src}: {missing}")


def copy_local_charts(helm_src, tmp_helm):
    print(f"Copying {helm_src} to {tmp_helm}")
    if tmp_helm.exists():
        shutil.rmtree(tmp_helm)
    shutil.copytree(helm_src, tmp_helm)


def write_local_charts_override(tmp_oci, local_charts):
    local_charts_tfvars = tmp_oci / "local_charts.auto.tfvars"
    print(f"Writing chart source override to {local_charts_tfvars}")
    local_charts_tfvars.write_text(
        f"k8s_use_local_charts = {str(local_charts).lower()}\n",
        encoding="utf-8",
    )


def configure_packaged_chart_path(tmp_oci):
    """Resolve bundled charts relative to the extracted Resource Manager stack."""
    apply_script = tmp_oci / "cfgmgt" / "apply.py"
    source = apply_script.read_text(encoding="utf-8")
    repository_path = 'LOCAL_HELM_DIR = os.path.abspath(os.path.join(SCRIPT_DIR, "..", "..", "helm", "infra-charts"))'
    packaged_path = 'LOCAL_HELM_DIR = os.path.abspath(os.path.join(SCRIPT_DIR, "..", "helm", "infra-charts"))'
    if source.count(repository_path) != 1:
        raise ValueError(f"Cannot configure bundled chart path in {apply_script}: unexpected LOCAL_HELM_DIR definition")
    apply_script.write_text(source.replace(repository_path, packaged_path), encoding="utf-8")


def build_stack(marketplace: bool = False, local_charts: bool = True):
    script_dir = Path(__file__).resolve().parent
    repo_root = script_dir.parents[2]

    # Define source paths
    opentofu_src = repo_root / "opentofu"
    helm_src = repo_root / "helm" / "infra-charts"
    stage_dir = script_dir.parent / "stage"

    # Validate source directories exist
    if not opentofu_src.is_dir():
        raise FileNotFoundError(f"OpenTofu directory not found: {opentofu_src}")
    if local_charts:
        if not helm_src.is_dir():
            raise FileNotFoundError(f"Helm directory not found: {helm_src}")
        validate_local_charts(helm_src)

    # Ensure stage directory exists
    stage_dir.mkdir(parents=True, exist_ok=True)

    # Create temporary directory
    with tempfile.TemporaryDirectory() as tmp_dir:
        tmp_path = Path(tmp_dir)
        tmp_oci = tmp_path / "opentofu"

        print(f"Copying {opentofu_src} to {tmp_oci}")
        shutil.copytree(opentofu_src, tmp_oci, ignore=ignore_patterns)

        if local_charts:
            # Resource Manager extracts the archive as the Terraform root.
            # Keep charts inside that root and adapt the packaged apply script.
            tmp_helm = tmp_oci / "helm" / "infra-charts"
            tmp_helm.mkdir(parents=True, exist_ok=True)
            for chart_name in LOCAL_CHART_NAMES:
                copy_local_charts(helm_src / chart_name, tmp_helm / chart_name)
            configure_packaged_chart_path(tmp_oci)

        write_local_charts_override(tmp_oci, local_charts)

        if marketplace:
            marketplace_tfvars = tmp_oci / "marketplace.auto.tfvars"
            print(f"Writing marketplace overrides to {marketplace_tfvars}")
            marketplace_tfvars.write_text("mktpl_use_image = true\n", encoding="utf-8")

        # Create zip archive
        zip_name = "oci_marketplace_build" if marketplace else "oci_build"
        zip_path = stage_dir / zip_name
        zip_file = Path(f"{zip_path}.zip")

        # Remove existing zip file if it exists
        if zip_file.exists():
            print(f"Removing existing archive: {zip_file}")
            zip_file.unlink()

        print(f"Creating archive at {zip_file}")
        shutil.make_archive(str(zip_path), "zip", tmp_oci)

    zip_file_size =  round(os.path.getsize(zip_file) / 1048576, 2)
    if zip_file_size > MAX_STACK_SIZE_MB:
        sys.exit(f"Stack is too large {zip_file_size}M > {MAX_STACK_SIZE_MB}M")

    print(f"Stack File: {zip_file}")
    print(f"Stack Size: {zip_file_size}M")

    return zip_file

##########################################################################
# MAIN
##########################################################################
def main(args=None):
    parser = argparse.ArgumentParser(
        description="Stack Builder",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument('--marketplace', action='store_true', help="Marketplace Build; Enables Dummy VM")
    chart_source = parser.add_mutually_exclusive_group()
    chart_source.add_argument(
        '--remote-charts',
        dest='remote_charts',
        action='store_true',
        help="Use published Helm charts instead of this checkout's local charts",
    )
    chart_source.add_argument(
        '--local-charts',
        dest='remote_charts',
        action='store_false',
        help=argparse.SUPPRESS,
    )
    parser.set_defaults(remote_charts=False)
    args = parser.parse_args(args)

    return build_stack(args.marketplace, local_charts=not args.remote_charts)

if __name__ == "__main__":
    main(sys.argv[1:])
