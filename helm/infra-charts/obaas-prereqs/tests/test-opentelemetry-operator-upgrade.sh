#!/usr/bin/env bash
# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at http://oss.oracle.com/licenses/upl.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="${CHART_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
ARCHIVE="${CHART_DIR}/charts/opentelemetry-operator-0.122.0.tgz"
RENDERED="$(mktemp /private/tmp/obaas-prereqs-otel-test.XXXXXX.yaml)"
trap 'rm -f "${RENDERED}"' EXIT

fail() {
  echo "OpenTelemetry Operator upgrade regression test failed: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

require_command helm
require_command rg

rg -q 'version: "0\.122\.0"' "${CHART_DIR}/Chart.yaml" \
  || fail "Chart.yaml does not pin chart 0.122.0"
rg -q 'version: 0\.122\.0' "${CHART_DIR}/Chart.lock" \
  || fail "Chart.lock does not pin chart 0.122.0"
[[ -f "${ARCHIVE}" ]] || fail "vendored chart archive is missing: ${ARCHIVE}"

[[ "$(helm show chart "${ARCHIVE}" | awk '$1 == "version:" {print $2}')" == "0.122.0" ]] \
  || fail "vendored archive metadata is not chart 0.122.0"
[[ "$(helm show chart "${ARCHIVE}" | awk '$1 == "appVersion:" {print $2}')" == "0.158.0" ]] \
  || fail "vendored archive metadata is not operator 0.158.0"

helm lint "${CHART_DIR}" >/dev/null
helm template obaas-prereqs "${CHART_DIR}" -n obaas-system >"${RENDERED}"

rg -q -- '--collector-image=ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-k8s:0\.158\.0' "${RENDERED}" \
  || fail "rendered collector image is not 0.158.0"
rg -q -- '--feature-gates=-operand\.networkpolicy,-operator\.networkpolicy' "${RENDERED}" \
  || fail "rendered network-policy compatibility gates are not disabled"
rg -q 'app\.kubernetes\.io/version: "0\.158\.0"' "${RENDERED}" \
  || fail "rendered operator version is not 0.158.0"
! rg -q 'opentelemetry-operator-0\.119\.0|:0\.154\.0' "${RENDERED}" \
  || fail "rendered output contains stale OpenTelemetry Operator versions"

echo "OpenTelemetry Operator 0.122.0 / 0.158.0 regression test passed"
