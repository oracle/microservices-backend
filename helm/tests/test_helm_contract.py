"""Contract tests for the repository's OBaaS Helm charts."""

import shutil
import subprocess
from pathlib import Path

import pytest
import yaml

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
CHART_DIR = REPOSITORY_ROOT / "helm" / "infra-charts" / "obaas"
PREREQS_CHART_DIR = REPOSITORY_ROOT / "helm" / "infra-charts" / "obaas-prereqs"
OPERATOR_ARCHIVE = PREREQS_CHART_DIR / "charts" / "oracle-database-operator-0.2.0.tgz"

helm_bin = shutil.which("helm")
pytestmark = pytest.mark.skipif(helm_bin is None, reason="helm binary not available on PATH")


def _render(*sets: str, upgrade: bool = False) -> subprocess.CompletedProcess[str]:
    command = [
        "helm",
        "template",
        "contract",
        str(CHART_DIR),
        "--namespace",
        "contract",
        "--set",
        "global.api.apiKey=contract-api-key",
    ]
    if upgrade:
        command.append("--is-upgrade")
    for value in sets:
        command.extend(["--set", value])
    return subprocess.run(command, capture_output=True, text=True, check=False)


def _docs(rendered: str) -> list[dict]:
    return [document for document in yaml.safe_load_all(rendered) if isinstance(document, dict)]


def _resource_names(rendered: str, kind: str) -> set[str]:
    return {
        document["metadata"]["name"]
        for document in _docs(rendered)
        if document.get("kind") == kind and document.get("metadata", {}).get("name")
    }


def test_default_chart_renders_core_resources():
    result = _render()

    assert result.returncode == 0, result.stderr[:500]
    assert {"contract-admin-server", "contract-config-server", "contract-obaas-sidb"}.issubset(
        _resource_names(result.stdout, "Service")
    )
    assert "contract-eureka" in _resource_names(result.stdout, "StatefulSet")


def test_invalid_database_type_is_rejected():
    result = _render("database.type=invalid")

    assert result.returncode != 0
    assert "database.type must be one of" in result.stderr


def test_invalid_signoz_upgrade_stage_is_rejected():
    result = _render("signozUpgrade.stage=invalid")

    assert result.returncode != 0
    assert "/signozUpgrade/stage" in result.stderr


def test_other_database_requires_privileged_secret():
    result = _render("database.type=OTHER", "database.other.dsn=db.example:1521/service")

    assert result.returncode != 0
    assert "privAuthN.secretName is REQUIRED" in result.stderr


def test_oci_existing_config_cannot_mix_inline_values():
    result = _render(
        "database.oci_config.configMapName=oci-config",
        "database.oci_config.tenancy=ocid1.tenancy.test",
    )

    assert result.returncode != 0
    assert "cannot also provide tenancy" in result.stderr


def test_signoz_stage1_upgrade_hooks_render_only_for_upgrade():
    install = _render("signozUpgrade.stage=stage1", "signoz.enabled=true")
    upgrade = _render("signozUpgrade.stage=stage1", "signoz.enabled=true", upgrade=True)

    assert install.returncode == 0, install.stderr[:500]
    assert upgrade.returncode == 0, upgrade.stderr[:500]
    assert "helm.sh/hook: post-upgrade" not in install.stdout
    assert "helm.sh/hook: post-upgrade" in upgrade.stdout


def test_operator_dependency_archive_is_locked_to_0_2_0():
    assert OPERATOR_ARCHIVE.is_file()
    result = subprocess.run(
        ["helm", "show", "chart", str(OPERATOR_ARCHIVE)],
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    assert "version: 0.2.0" in result.stdout
