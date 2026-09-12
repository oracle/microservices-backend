"""
Copyright (c) 2024, 2026, Oracle and/or its affiliates.
Licensed under the Universal Permissive License v1.0 as shown at http://oss.oracle.com/licenses/upl.

Contract tests for the release-packaged OCI config Secret helper.
"""

import base64
import subprocess
import sys
from pathlib import Path

import yaml

SCRIPT = Path(__file__).resolve().parent.parent.parent / "helm" / "infra-charts" / "tools" / "oci_config.py"

def _run_helper(*args: str) -> subprocess.CompletedProcess[str]:
    """Run the helper without loading any installed site packages."""
    return subprocess.run(
        [sys.executable, "-I", "-S", str(SCRIPT), *args],
        capture_output=True,
        text=True,
        check=False,
    )


def _dry_run(*args: str) -> subprocess.CompletedProcess[str]:
    return _run_helper(*args, "--dry-run")


def test_emits_self_contained_secret_and_configmap_manifests(tmp_path: Path):
    key_path = tmp_path / "oci_api_key.pem"
    key_path.write_text("private-key-data", encoding="utf-8")
    config_path = tmp_path / "config"
    config_path.write_text(
        f"[DEFAULT]\ntenancy=ocid1.tenancy.test\nkey_file={key_path}\n",
        encoding="utf-8",
    )

    result = _dry_run(
        "--config",
        str(config_path),
        "--namespace",
        "ai-optimizer",
    )

    assert result.returncode == 0, result.stderr
    secret, configmap = list(yaml.safe_load_all(result.stdout))
    assert secret["metadata"] == {"name": "oci-privatekey", "namespace": "ai-optimizer"}
    assert secret["type"] == "Opaque"
    assert base64.b64decode(secret["data"]["privatekey"]) == b"private-key-data"
    assert configmap["metadata"] == {"name": "oci-config", "namespace": "ai-optimizer"}
    assert configmap["data"]["tenancy"] == "ocid1.tenancy.test"
    assert "key_file" not in configmap["data"]
    assert result.stderr == ""


def test_missing_config_fails_without_manifest(tmp_path: Path):
    result = _dry_run(
        "--config",
        str(tmp_path / "missing-config"),
        "--namespace",
        "ai-optimizer",
    )

    assert result.returncode != 0
    assert "Config file not found" in result.stderr
    assert result.stdout == ""


def test_missing_key_file_fails_without_manifest(tmp_path: Path):
    missing_key = tmp_path / "missing-key.pem"
    config_path = tmp_path / "config"
    config_path.write_text(f"[DEFAULT]\nkey_file={missing_key}\n", encoding="utf-8")

    result = _dry_run("--config", str(config_path), "--namespace", "ai-optimizer")

    assert result.returncode != 0
    assert str(missing_key) in result.stderr
    assert result.stdout == ""


def test_missing_key_file_setting_fails_without_manifest(tmp_path: Path):
    config_path = tmp_path / "config"
    config_path.write_text("[DEFAULT]\ntenancy=ocid1.tenancy.test\n", encoding="utf-8")

    result = _dry_run("--config", str(config_path), "--namespace", "ai-optimizer")

    assert result.returncode != 0
    assert "No key_file values found" in result.stderr
    assert result.stdout == ""


def test_profile_selects_requested_key_file(tmp_path: Path):
    key_path = tmp_path / "profile-key.pem"
    key_path.write_text("private-key", encoding="utf-8")
    config_path = tmp_path / "config"
    config_path.write_text(
        f"[DEFAULT]\ntenancy=ocid1.default\n\n[DEV]\ntenancy=ocid1.dev\nkey_file={key_path}\n",
        encoding="utf-8",
    )

    result = _dry_run(
        "--config",
        str(config_path),
        "--namespace",
        "ai-optimizer",
        "--profile",
        "DEV",
    )

    assert result.returncode == 0, result.stderr
    _, configmap = list(yaml.safe_load_all(result.stdout))
    assert configmap["data"]["tenancy"] == "ocid1.dev"
