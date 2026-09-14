#!/usr/bin/env bash
# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at http://oss.oracle.com/licenses/upl.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="${CHART_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
SNAPSHOT_SCRIPT="${CHART_DIR}/files/signoz-upgrade/create-snapshots.sh"
MOCK_KUBECTL="${SCRIPT_DIR}/fixtures/signoz-upgrade/mock-kubectl.sh"
DEFAULT_VALUES="${CHART_DIR}/examples/values-default.yaml"
STAGE1_VALUES="${CHART_DIR}/examples/values-signoz-0.141.1-stage1.yaml"
STAGE2_VALUES="${CHART_DIR}/examples/values-signoz-0.141.1-stage2.yaml"
TEST_ROOT="$(mktemp -d)"

cleanup() {
  rm -rf "${TEST_ROOT}"
}
trap cleanup EXIT

assert_contains() {
  local file="$1"
  local expected="$2"
  grep -Fq -- "${expected}" "${file}" || {
    echo "Expected ${file} to contain: ${expected}" >&2
    exit 1
  }
}

assert_not_contains() {
  local file="$1"
  local unexpected="$2"
  if grep -Fq -- "${unexpected}" "${file}"; then
    echo "Unexpected value in ${file}: ${unexpected}" >&2
    exit 1
  fi
}

render_chart() {
  local output="$1"
  shift
  helm template signoz-phase2 "${CHART_DIR}" \
    --namespace signoz-phase2 \
    -f "${DEFAULT_VALUES}" \
    "$@" >"${output}"
}

run_snapshot_script() {
  local scenario="$1"
  local case_name="$2"
  local explicit_class="${3:-}"
  local mappings="${4:-}"
  local case_dir="${TEST_ROOT}/${case_name}"
  mkdir -p "${case_dir}"

  env \
    KUBECTL="${MOCK_KUBECTL}" \
    MOCK_SCENARIO="${scenario}" \
    MOCK_OUTPUT_DIR="${case_dir}" \
    NAMESPACE="obaas-test" \
    RELEASE_NAME="obaas" \
    RELEASE_REVISION="7" \
    TARGET_VERSION="0.141.1" \
    SNAPSHOT_TIMEOUT="20m" \
    MARKER_SECRET_NAME="obaas-signoz-upgrade-0-141-1-stage1" \
    SNAPSHOT_CLASS_NAME="${explicit_class}" \
    SNAPSHOT_CLASS_MAPPINGS="${mappings}" \
    /bin/sh "${SNAPSHOT_SCRIPT}" >"${case_dir}/output.log" 2>&1
}

assert_snapshot_script_fails() {
  local scenario="$1"
  local case_name="$2"
  local expected="$3"
  local explicit_class="${4:-}"
  local case_dir="${TEST_ROOT}/${case_name}"

  if run_snapshot_script "${scenario}" "${case_name}" "${explicit_class}"; then
    echo "Expected snapshot scenario '${scenario}' to fail" >&2
    exit 1
  fi
  assert_contains "${case_dir}/output.log" "${expected}"
}

for command in helm grep find wc; do
  command -v "${command}" >/dev/null 2>&1 || {
    echo "Missing required command: ${command}" >&2
    exit 1
  }
done

standard_upgrade="${TEST_ROOT}/standard-upgrade.yaml"
stage1_install="${TEST_ROOT}/stage1-install.yaml"
stage1_upgrade="${TEST_ROOT}/stage1-upgrade.yaml"
stage1_mapped="${TEST_ROOT}/stage1-mapped.yaml"
stage2_upgrade="${TEST_ROOT}/stage2-upgrade.yaml"

render_chart "${standard_upgrade}" --is-upgrade
render_chart "${stage1_install}" -f "${STAGE1_VALUES}"
render_chart "${stage1_upgrade}" --is-upgrade -f "${STAGE1_VALUES}"
render_chart "${stage1_mapped}" --is-upgrade -f "${STAGE1_VALUES}" \
  --set signozUpgrade.backup.volumeSnapshotClassByStorageClass.oci-bv=oci-bv-snap
render_chart "${stage2_upgrade}" --is-upgrade -f "${STAGE2_VALUES}"

if render_chart "${TEST_ROOT}/invalid-class.yaml" --is-upgrade -f "${STAGE1_VALUES}" \
  --set signozUpgrade.backup.volumeSnapshotClassName=Invalid_Class \
  >"${TEST_ROOT}/invalid-class.log" 2>&1; then
  echo "Expected an invalid VolumeSnapshotClass name to fail Helm validation" >&2
  exit 1
fi
assert_contains "${TEST_ROOT}/invalid-class.log" "does not match pattern"

# The hook is limited to an existing release explicitly selecting Stage 1.
for render in "${standard_upgrade}" "${stage1_install}" "${stage2_upgrade}"; do
  assert_not_contains "${render}" 'app.kubernetes.io/name: signoz-upgrade-snapshot'
done
assert_contains "${stage1_upgrade}" 'app.kubernetes.io/name: signoz-upgrade-snapshot'
assert_contains "${stage1_upgrade}" '"helm.sh/hook": pre-upgrade'
assert_contains "${stage1_upgrade}" 'resources: ["pods", "persistentvolumeclaims"]'
assert_contains "${stage1_upgrade}" 'resources: ["persistentvolumes"]'
assert_contains "${stage1_upgrade}" 'resources: ["storageclasses"]'
assert_not_contains "${stage1_upgrade}" 'resources: ["storageclasses", "csidrivers"]'
assert_contains "${stage1_upgrade}" 'resources: ["volumesnapshotclasses"]'
assert_contains "${stage1_upgrade}" 'resources: ["volumesnapshots"]'
assert_contains "${stage1_upgrade}" 'Kubernetes snapshot API resource'
assert_contains "${stage1_upgrade}" "--for=jsonpath='{.status.readyToUse}'=true"
assert_contains "${stage1_mapped}" $'oci-bv\toci-bv-snap'

# Stage 1 keeps SigNoz and the collector on their intermediate versions while
# Phase 3 changes only ClickHouse.
assert_contains "${stage1_upgrade}" 'image: docker.io/signoz/signoz:v0.113.0'
assert_contains "${stage1_upgrade}" 'image: docker.io/signoz/signoz-otel-collector:v0.144.1'
assert_contains "${stage1_upgrade}" 'image: docker.io/clickhouse/clickhouse-server:25.12.5'
assert_not_contains "${stage1_upgrade}" 'image: docker.io/signoz/signoz:v0.141.1'

# Exercise the snapshot logic with a mocked Kubernetes API.
run_snapshot_script "success" "success"
snapshot_count="$(find "${TEST_ROOT}/success" -name 'snapshot-*.yaml' | wc -l | tr -d ' ')"
[[ "${snapshot_count}" == "3" ]]
assert_contains "${TEST_ROOT}/success/output.log" 'All SigNoz Stage 1 CSI snapshots are ready.'
assert_contains "${TEST_ROOT}/success/snapshot-1.yaml" 'helm.sh/resource-policy: keep'
assert_contains "${TEST_ROOT}/success/snapshot-1.yaml" 'obaas.oracle.com/source-pvc-uid:'
assert_contains "${TEST_ROOT}/success/snapshot-1.yaml" 'obaas.oracle.com/upgrade-target: "0.141.1"'
assert_contains "${TEST_ROOT}/success/snapshot-1.yaml" 'volumeSnapshotClassName: default-snap'

mappings=$'fast-sc\tfast-snap\nblock-sc\tblock-snap'
run_snapshot_script "mapped-classes" "mapped-classes" "" "${mappings}"
assert_contains "${TEST_ROOT}/mapped-classes/snapshot-1.yaml" 'volumeSnapshotClassName: block-snap'
assert_contains "${TEST_ROOT}/mapped-classes/snapshot-2.yaml" 'volumeSnapshotClassName: fast-snap'

assert_snapshot_script_fails "missing-crd" "missing-crd" \
  "snapshot API resource 'volumesnapshotcontents.snapshot.storage.k8s.io' is not installed"
assert_snapshot_script_fails "missing-class" "missing-class" \
  "No default VolumeSnapshotClass uses CSI driver 'csi.example.com'"
assert_snapshot_script_fails "multiple-defaults" "multiple-defaults" \
  "Multiple default VolumeSnapshotClasses use CSI driver 'csi.example.com'"
assert_snapshot_script_fails "missing-explicit-class" "missing-explicit-class" \
  "VolumeSnapshotClass 'does-not-exist' does not exist" "does-not-exist"
assert_snapshot_script_fails "success" "incompatible-driver" \
  "VolumeSnapshotClass 'wrong-snap' uses driver 'other.csi.example.com'" "wrong-snap"
assert_snapshot_script_fails "non-csi-pv" "non-csi-pv" \
  "is not backed by a CSI driver"
assert_snapshot_script_fails "mismatched-pv-driver" "mismatched-pv-driver" \
  "uses CSI driver 'other.csi.example.com', but StorageClass 'shared-sc' uses 'csi.example.com'"
assert_snapshot_script_fails "missing-pvc" "missing-pvc" \
  "No mounted PVC was found for required SigNoz component 'zookeeper'"
assert_snapshot_script_fails "unbound-pvc" "unbound-pvc" \
  "is not Bound (phase: Pending)"
assert_snapshot_script_fails "timeout" "timeout" \
  "Timed out or failed while waiting for CSI snapshots"

echo "SigNoz upgrade Phase 2 regression test passed"
