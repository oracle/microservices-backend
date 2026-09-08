#!/usr/bin/env bash
# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at http://oss.oracle.com/licenses/upl.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="${CHART_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
VALIDATION_SCRIPT="${CHART_DIR}/files/signoz-upgrade/validate-clickhouse.sh"
MOCK_KUBECTL="${SCRIPT_DIR}/fixtures/signoz-upgrade/mock-validation-kubectl.sh"
DEFAULT_VALUES="${CHART_DIR}/examples/values-default.yaml"
STAGE1_VALUES="${CHART_DIR}/examples/values-signoz-0.134-stage1.yaml"
STAGE2_VALUES="${CHART_DIR}/examples/values-signoz-0.134-stage2.yaml"
IMAGE_LIST="${CHART_DIR}/../tools/image_lists/k8s_images_2.1.2.txt"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "${TEST_ROOT}"' EXIT

assert_contains() { grep -Fq -- "$2" "$1" || { echo "Expected $1 to contain: $2" >&2; exit 1; }; }
assert_not_contains() { ! grep -Fq -- "$2" "$1" || { echo "Unexpected value in $1: $2" >&2; exit 1; }; }

render() {
  helm template signoz-phase3 "${CHART_DIR}" --namespace signoz-phase3 \
    -f "${DEFAULT_VALUES}" "$@"
}

run_validation() {
  local scenario="$1"
  local case_dir="${TEST_ROOT}/${scenario}"
  mkdir -p "${case_dir}"
  env KUBECTL="${MOCK_KUBECTL}" MOCK_SCENARIO="${scenario}" MOCK_OUTPUT_DIR="${case_dir}" \
    NAMESPACE=obaas RELEASE_NAME=obaas RELEASE_REVISION=7 TARGET_VERSION=0.134.0 \
    CLICKHOUSE_VERSION=25.12.5 VALIDATION_TIMEOUT=10m \
    MARKER_SECRET_NAME=obaas-signoz-upgrade-0-134-stage1 \
    /bin/sh "${VALIDATION_SCRIPT}" >"${case_dir}/output.log" 2>&1
}

assert_validation_fails() {
  local scenario="$1"
  local expected="$2"
  if run_validation "${scenario}"; then
    echo "Expected validation scenario ${scenario} to fail" >&2
    exit 1
  fi
  assert_contains "${TEST_ROOT}/${scenario}/output.log" "${expected}"
  [[ ! -f "${TEST_ROOT}/${scenario}/marker.yaml" ]]
}

stage1="${TEST_ROOT}/stage1.yaml"
standard="${TEST_ROOT}/standard.yaml"
stage2="${TEST_ROOT}/stage2.yaml"
render --is-upgrade -f "${STAGE1_VALUES}" >"${stage1}"
render --is-upgrade >"${standard}"
render --is-upgrade -f "${STAGE2_VALUES}" >"${stage2}"

assert_contains "${stage1}" 'image: docker.io/clickhouse/clickhouse-server:25.12.5'
assert_contains "${stage1}" 'image: docker.io/signoz/signoz:v0.113.0'
assert_contains "${stage1}" 'image: docker.io/signoz/signoz-otel-collector:v0.144.1'
assert_contains "${stage1}" 'app.kubernetes.io/name: signoz-upgrade-validation'
assert_contains "${stage1}" '"helm.sh/hook": post-upgrade'
assert_contains "${stage1}" 'resources: ["pods/exec"]'
assert_contains "${stage1}" 'resources: ["volumesnapshots"]'
assert_contains "${stage1}" 'resources: ["clickhouseinstallations"]'
assert_contains "${IMAGE_LIST}" 'docker.io/clickhouse/clickhouse-server:25.12.5'
assert_not_contains "${standard}" 'app.kubernetes.io/name: signoz-upgrade-validation'
assert_not_contains "${stage2}" 'app.kubernetes.io/name: signoz-upgrade-validation'

run_validation success
assert_contains "${TEST_ROOT}/success/output.log" 'Stage 1 completion marker'
assert_contains "${TEST_ROOT}/success/marker.yaml" 'status: "complete"'
assert_contains "${TEST_ROOT}/success/marker.yaml" 'clickhouseVersion: "25.12.5.44"'
assert_contains "${TEST_ROOT}/success/marker.yaml" 'telemetryRows: "100"'
assert_contains "${TEST_ROOT}/success/marker.yaml" 'helmRevision: "7"'
assert_contains "${TEST_ROOT}/success/marker.yaml" $'clickhouse\tdata-volumeclaim-template-chi-0-0-0'

assert_validation_fails pods-not-ready 'pods did not become Ready'
assert_validation_fails wrong-image 'does not use target 25.12.5'
assert_validation_fails wrong-version "reported version '25.11.1.1'"
assert_validation_fails query-failed 'clickhouse-client'
assert_validation_fails stale-pvc-uid 'No ready snapshot matches PVC'
assert_validation_fails snapshot-not-ready 'No ready snapshot matches PVC'
assert_validation_fails marker-write-failed 'kubectl'

echo "SigNoz upgrade Phase 3 regression test passed"
