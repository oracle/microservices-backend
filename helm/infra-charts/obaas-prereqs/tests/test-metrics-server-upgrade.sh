#!/usr/bin/env bash
# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at http://oss.oracle.com/licenses/upl.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="${CHART_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
ARCHIVE="${CHART_DIR}/charts/metrics-server-3.14.0.tgz"
RENDERED="$(mktemp /private/tmp/obaas-prereqs-metrics-test.XXXXXX.yaml)"
trap 'rm -f "${RENDERED}"' EXIT

fail() {
  echo "Metrics Server upgrade regression test failed: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

require_command helm
require_command rg

rg -q 'version: "3\.14\.0"' "${CHART_DIR}/Chart.yaml" \
  || fail "Chart.yaml does not pin chart 3.14.0"
rg -q 'version: 3\.14\.0' "${CHART_DIR}/Chart.lock" \
  || fail "Chart.lock does not pin chart 3.14.0"
[[ -f "${ARCHIVE}" ]] || fail "vendored chart archive is missing: ${ARCHIVE}"

[[ "$(helm show chart "${ARCHIVE}" | awk '$1 == "version:" {print $2}')" == "3.14.0" ]] \
  || fail "vendored archive metadata is not chart 3.14.0"
[[ "$(helm show chart "${ARCHIVE}" | awk '$1 == "appVersion:" {print $2}')" == "0.9.0" ]] \
  || fail "vendored archive metadata is not Metrics Server 0.9.0"

helm lint "${CHART_DIR}" >/dev/null
helm template obaas-prereqs "${CHART_DIR}" -n obaas-system >"${RENDERED}"

rg -q 'image: registry\.k8s\.io/metrics-server/metrics-server:v0\.9\.0' "${RENDERED}" \
  || fail "rendered Metrics Server image is not v0.9.0"
rg -q 'name: v1beta1\.metrics\.k8s\.io' "${RENDERED}" \
  || fail "rendered metrics APIService is missing"
rg -q 'app\.kubernetes\.io/version: "0\.9\.0"' "${RENDERED}" \
  || fail "rendered Metrics Server version is not 0.9.0"
! rg -q 'metrics-server-3\.13\.1|metrics-server/metrics-server:v0\.8\.1' "${RENDERED}" \
  || fail "rendered output contains stale Metrics Server versions"

echo "Metrics Server 3.14.0 / 0.9.0 regression test passed"
