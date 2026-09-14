#!/usr/bin/env bash
# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at http://oss.oracle.com/licenses/upl.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="${CHART_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
DEFAULT_VALUES="${CHART_DIR}/examples/values-default.yaml"
STAGE1_VALUES="${CHART_DIR}/examples/values-signoz-0.141.1-stage1.yaml"
STAGE2_VALUES="${CHART_DIR}/examples/values-signoz-0.141.1-stage2.yaml"
STANDARD_RENDER="$(mktemp)"
STAGE1_RENDER="$(mktemp)"
STAGE2_INSTALL_RENDER="$(mktemp)"
STAGE2_UPGRADE_RENDER="$(mktemp)"
ERROR_OUTPUT="$(mktemp)"

cleanup() {
  rm -f \
    "${STANDARD_RENDER}" \
    "${STAGE1_RENDER}" \
    "${STAGE2_INSTALL_RENDER}" \
    "${STAGE2_UPGRADE_RENDER}" \
    "${ERROR_OUTPUT}"
}
trap cleanup EXIT

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

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

assert_template_fails() {
  local expected="$1"
  shift

  if helm template signoz-phase1 "${CHART_DIR}" \
    --namespace signoz-phase1 \
    -f "${DEFAULT_VALUES}" \
    "$@" >"${ERROR_OUTPUT}" 2>&1; then
    echo "Expected Helm rendering to fail: $*" >&2
    exit 1
  fi
  assert_contains "${ERROR_OUTPUT}" "${expected}"
}

require_command helm
require_command grep

helm lint "${CHART_DIR}" -f "${DEFAULT_VALUES}"
helm lint "${CHART_DIR}" -f "${DEFAULT_VALUES}" -f "${STAGE1_VALUES}"
helm lint "${CHART_DIR}" -f "${DEFAULT_VALUES}" -f "${STAGE2_VALUES}"

helm template signoz-phase1 "${CHART_DIR}" \
  --namespace signoz-phase1 \
  -f "${DEFAULT_VALUES}" >"${STANDARD_RENDER}"
helm template signoz-phase1 "${CHART_DIR}" \
  --namespace signoz-phase1 \
  -f "${DEFAULT_VALUES}" \
  -f "${STAGE1_VALUES}" >"${STAGE1_RENDER}"
helm template signoz-phase1 "${CHART_DIR}" \
  --namespace signoz-phase1 \
  -f "${DEFAULT_VALUES}" \
  -f "${STAGE2_VALUES}" >"${STAGE2_INSTALL_RENDER}"
helm template signoz-phase1 "${CHART_DIR}" \
  --namespace signoz-phase1 \
  --is-upgrade \
  -f "${DEFAULT_VALUES}" \
  -f "${STAGE2_VALUES}" >"${STAGE2_UPGRADE_RENDER}"

# Standard/fresh installs and Stage 2 render the final SigNoz stack.
for render in \
  "${STANDARD_RENDER}" \
  "${STAGE2_INSTALL_RENDER}" \
  "${STAGE2_UPGRADE_RENDER}"; do
  assert_contains "${render}" 'image: docker.io/signoz/signoz:v0.141.1'
  assert_contains "${render}" 'image: docker.io/signoz/signoz-otel-collector:v0.144.9'
  assert_contains "${render}" 'image: docker.io/clickhouse/clickhouse-server:25.12.5'
  assert_not_contains "${render}" 'kind: VolumeSnapshot'
done

  assert_not_contains "${STANDARD_RENDER}" 'signoz-upgrade-0-141-1-stage1'
  assert_not_contains "${STAGE2_INSTALL_RENDER}" 'signoz-upgrade-0-141-1-stage1'
assert_contains "${STAGE2_UPGRADE_RENDER}" 'app.kubernetes.io/name: signoz-stage2-gate'

# Stage 1 keeps SigNoz and its collector fixed while upgrading only ClickHouse.
assert_contains "${STAGE1_RENDER}" 'image: docker.io/signoz/signoz:v0.113.0'
assert_contains "${STAGE1_RENDER}" 'image: docker.io/signoz/signoz-otel-collector:v0.144.1'
assert_contains "${STAGE1_RENDER}" 'image: docker.io/clickhouse/clickhouse-server:25.12.5'
assert_not_contains "${STAGE1_RENDER}" 'image: docker.io/signoz/signoz:v0.141.1'
assert_not_contains "${STAGE1_RENDER}" 'image: docker.io/signoz/signoz-otel-collector:v0.144.9'
assert_not_contains "${STAGE1_RENDER}" 'kind: VolumeSnapshot'
assert_not_contains "${STAGE1_RENDER}" 'signoz-upgrade-0-141-1-stage1'

# Schema validation rejects malformed workflow configuration.
assert_template_fails "at '/signozUpgrade/stage': value must be one of 'standard', 'stage1', 'stage2'" \
  --set signozUpgrade.stage=invalid
assert_template_fails "at '/signozUpgrade/backup/provider': value must be 'csi'" \
  --set signozUpgrade.backup.provider=filesystem
assert_template_fails "at '/signozUpgrade/backup/timeout': 'forever' does not match pattern" \
  --set signozUpgrade.backup.timeout=forever
assert_template_fails "at '/signozUpgrade/target/chartVersion': value must be '0.141.1'" \
  --set signozUpgrade.target.chartVersion=0.133.0
assert_template_fails "at '/signozUpgrade/target/signozVersion': value must be 'v0.141.1'" \
  --set signozUpgrade.target.signozVersion=v0.133.0

# Cross-field validation prevents selecting an upgrade stage without SigNoz.
assert_template_fails 'signozUpgrade.stage=stage1 requires signoz.enabled=true' \
  -f "${STAGE1_VALUES}" \
  --set signoz.enabled=false
assert_template_fails 'signozUpgrade.stage=stage2 requires signoz.enabled=true' \
  -f "${STAGE2_VALUES}" \
  --set signoz.enabled=false

echo "SigNoz upgrade Phase 1 regression test passed"
