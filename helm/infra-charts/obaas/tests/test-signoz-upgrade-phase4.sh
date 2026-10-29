#!/usr/bin/env bash
# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at http://oss.oracle.com/licenses/upl.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="${CHART_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
GATE_SCRIPT="${CHART_DIR}/files/signoz-upgrade/enforce-stage2.sh"
MOCK="${SCRIPT_DIR}/fixtures/signoz-upgrade/mock-stage2-kubectl.sh"
DEFAULT="${CHART_DIR}/examples/values-default.yaml"
STAGE2="${CHART_DIR}/examples/values-signoz-0.142.1-stage2.yaml"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

assert_contains() { grep -Fq -- "$2" "$1" || { echo "Expected $1 to contain: $2" >&2; exit 1; }; }
assert_not_contains() { ! grep -Fq -- "$2" "$1" || { echo "Unexpected $2 in $1" >&2; exit 1; }; }

run_gate() {
  local scenario="$1"
  env KUBECTL="${MOCK}" MOCK_SCENARIO="${scenario}" NAMESPACE=obaas RELEASE_NAME=obaas \
    RELEASE_REVISION=8 TARGET_VERSION=0.142.1 CLICKHOUSE_VERSION=25.12.5 \
    VALIDATION_TIMEOUT=10m MARKER_SECRET_NAME=obaas-signoz-upgrade-0-142-1-stage1 \
    /bin/sh "${GATE_SCRIPT}" >"${TMP}/${scenario}.log" 2>&1
}

expect_failure() {
  if run_gate "$1"; then echo "Expected $1 to block Stage 2" >&2; exit 1; fi
  assert_contains "${TMP}/$1.log" "$2"
}

upgrade_render="${TMP}/upgrade.yaml"
install_render="${TMP}/install.yaml"
helm template phase4 "${CHART_DIR}" -n obaas --is-upgrade -f "${DEFAULT}" -f "${STAGE2}" >"${upgrade_render}"
helm template phase4 "${CHART_DIR}" -n obaas -f "${DEFAULT}" -f "${STAGE2}" >"${install_render}"
assert_contains "${upgrade_render}" 'app.kubernetes.io/name: signoz-stage2-gate'
assert_contains "${upgrade_render}" '"helm.sh/hook-weight": "-39"'
assert_contains "${upgrade_render}" 'helm.sh/hook-weight: "-40"'
assert_not_contains "${install_render}" 'app.kubernetes.io/name: signoz-stage2-gate'

# The gate is deliberately read-only except for exec used to query ClickHouse.
for mutation in 'kube apply' 'kube create' 'kube delete' 'kube patch' 'kube scale'; do
  assert_not_contains "${GATE_SCRIPT}" "${mutation}"
done

expect_failure no-marker 'completion marker'
expect_failure malformed-marker "missing required field 'status'"
expect_failure stale-marker 'is stale'
expect_failure deleted-snapshot "snapshot 'signoz-snap' no longer exists"
expect_failure mismatched-pvc "PVC 'signoz-pvc' UID changed"
expect_failure wrong-clickhouse 'live ClickHouse image'
run_gate success
assert_contains "${TMP}/success.log" 'Stage 2 prerequisite validation passed'

echo "SigNoz upgrade Phase 4 regression test passed"
