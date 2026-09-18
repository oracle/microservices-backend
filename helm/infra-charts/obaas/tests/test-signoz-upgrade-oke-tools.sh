#!/usr/bin/env bash
# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at http://oss.oracle.com/licenses/upl.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="${CHART_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
TOOLS_DIR="${CHART_DIR}/../tools"
PREPARE="${TOOLS_DIR}/prepare-oke-volume-snapshots.sh"
DIAGNOSE="${TOOLS_DIR}/diagnose-signoz-upgrade.sh"
RESTORE="${TOOLS_DIR}/validate-signoz-snapshot-restore.sh"
MOCK="${SCRIPT_DIR}/fixtures/signoz-upgrade/mock-oke-preflight-kubectl.sh"
OKE_VALUES="${CHART_DIR}/examples/values-signoz-0.142.1-stage1-oke.yaml"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

assert_contains() {
  grep -Fq -- "$2" "$1" || {
    echo "Expected $1 to contain: $2" >&2
    exit 1
  }
}

chmod +x "${MOCK}"
bash -n "${PREPARE}"
bash -n "${DIAGNOSE}"
bash -n "${RESTORE}"

env KUBECTL="${MOCK}" MOCK_STATE_DIR="${TMP}" \
  "${PREPARE}" >"${TMP}/prepare.log"

assert_contains "${TMP}/kubectl.log" \
  'external-snapshotter/v8.2.0/client/config/crd/snapshot.storage.k8s.io_volumesnapshots.yaml'
assert_contains "${TMP}/class.yaml" 'name: obaas-oci-bv-snapshot'
assert_contains "${TMP}/class.yaml" 'driver: blockvolume.csi.oraclecloud.com'
assert_contains "${TMP}/class.yaml" 'backupType: full'
assert_contains "${TMP}/class.yaml" 'deletionPolicy: Retain'
assert_contains "${TMP}/prepare.log" 'Validated signoz'
assert_contains "${TMP}/prepare.log" 'OKE snapshot prerequisites are ready.'

env KUBECTL="${MOCK}" MOCK_STATE_DIR="${TMP}" \
  "${PREPARE}" --check-only >"${TMP}/check.log"
assert_contains "${TMP}/check.log" "Existing VolumeSnapshotClass 'obaas-oci-bv-snapshot' is compatible."

if env KUBECTL="${MOCK}" MOCK_STATE_DIR="${TMP}" MOCK_SCENARIO=wrong-driver \
  "${PREPARE}" --check-only >"${TMP}/wrong-driver.log" 2>&1; then
  echo "Expected OKE preparation to reject a mismatched PV driver" >&2
  exit 1
fi
assert_contains "${TMP}/wrong-driver.log" "does not match StorageClass provisioner"

assert_contains "${OKE_VALUES}" 'volumeSnapshotClassName: obaas-oci-bv-snapshot'
assert_contains "${DIAGNOSE}" 'Snapshot contents and OCI backup handles'
assert_contains "${DIAGNOSE}" 'Stage 1 completion marker'
assert_contains "${DIAGNOSE}" 'obaas.oracle.com/signoz-upgrade-marker=true'
assert_contains "${RESTORE}" 'Snapshot restore validation passed.'
assert_contains "${RESTORE}" 'dataSource:'
assert_contains "${RESTORE}" 'kind: VolumeSnapshot'
assert_contains "${RESTORE}" ".status.restoreSize"
assert_contains "${RESTORE}" 'shasum -a 256'

echo "SigNoZ OKE snapshot tooling regression test passed"
