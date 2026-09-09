#!/usr/bin/env bash
# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at http://oss.oracle.com/licenses/upl.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="${CHART_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
ARCHIVE="${CHART_DIR}/charts/kube-state-metrics-8.4.2.tgz"
RENDERED="$(mktemp /private/tmp/obaas-prereqs-kube-state-metrics-test.XXXXXX.yaml)"
METRICS="$(mktemp /private/tmp/obaas-prereqs-kube-state-metrics-metrics.XXXXXX.txt)"
DASHBOARD="${CHART_DIR}/../obaas/dashboards/2/kube-state-metrics-v2.json"
trap 'rm -f "${RENDERED}" "${METRICS}"' EXIT

fail() {
  echo "Kube State Metrics upgrade regression test failed: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

require_command helm
require_command jq
require_command rg

rg -q 'version: "8\.4\.2"' "${CHART_DIR}/Chart.yaml" \
  || fail "Chart.yaml does not pin chart 8.4.2"
rg -q 'version: 8\.4\.2' "${CHART_DIR}/Chart.lock" \
  || fail "Chart.lock does not pin chart 8.4.2"
[[ -f "${ARCHIVE}" ]] || fail "vendored chart archive is missing: ${ARCHIVE}"

[[ "$(helm show chart "${ARCHIVE}" | awk '$1 == "version:" {print $2}')" == "8.4.2" ]] \
  || fail "vendored archive metadata is not chart 8.4.2"
[[ "$(helm show chart "${ARCHIVE}" | awk '$1 == "appVersion:" {print $2}')" == "2.20.0" ]] \
  || fail "vendored archive metadata is not KSM 2.20.0"

helm lint "${CHART_DIR}" >/dev/null
helm template obaas-prereqs "${CHART_DIR}" -n obaas-system >"${RENDERED}"

rg -q 'image: registry\.k8s\.io/kube-state-metrics/kube-state-metrics:v2\.20\.0' "${RENDERED}" \
  || fail "rendered kube-state-metrics image is not v2.20.0"
rg -q 'app\.kubernetes\.io/version: "2\.20\.0"' "${RENDERED}" \
  || fail "rendered kube-state-metrics version is not 2.20.0"
rg -q -- '--resources=.*endpointslices' "${RENDERED}" \
  || fail "rendered kube-state-metrics collectors do not include EndpointSlices"
! rg -q -- '--resources=.*(^|,)endpoints(,|$)' "${RENDERED}" \
  || fail "rendered kube-state-metrics collectors still include deprecated Endpoints"
rg -q 'name: obaas-prereqs-kube-state-metrics' "${RENDERED}" \
  || fail "kube-state-metrics Service name changed unexpectedly"
rg -q 'app\.kubernetes\.io/name: kube-state-metrics' "${RENDERED}" \
  || fail "kube-state-metrics selector label is missing"

jq empty "${DASHBOARD}" >/dev/null
jq -r '.. | strings | select(contains("kube_"))' "${DASHBOARD}" \
  | rg -o 'kube_[A-Za-z0-9_]+' | sort -u >"${METRICS}"
[[ "$(wc -l <"${METRICS}" | tr -d ' ')" == "29" ]] \
  || fail "unexpected kube-state-metrics dashboard metric count"
! rg -q 'kube_endpoint' "${METRICS}" \
  || fail "dashboard still references removed endpoint metrics"

rg -q 'resources: \["endpointslices"\]' "${CHART_DIR}/../obaas/values.yaml" \
  || fail "the observability collector is not authorized to watch EndpointSlices"
rg -q 'role: endpointslice' "${CHART_DIR}/../obaas/values.yaml" \
  || fail "the observability collector is not discovering EndpointSlices"

echo "Kube State Metrics 8.4.2 / 2.20.0 regression test passed"
