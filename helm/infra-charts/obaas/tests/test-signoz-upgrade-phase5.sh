#!/usr/bin/env bash
# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at http://oss.oracle.com/licenses/upl.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="${CHART_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
RESOURCE_SCRIPT="${CHART_DIR}/files/signoz-upgrade/validate-signoz-stage2.sh"
DATA_SCRIPT="${CHART_DIR}/files/signoz-upgrade/validate-signoz-data.sh"
MOCK_KUBECTL="${SCRIPT_DIR}/fixtures/signoz-upgrade/mock-phase5-kubectl.sh"
MOCK_CURL="${SCRIPT_DIR}/fixtures/signoz-upgrade/mock-phase5-curl.sh"
DEFAULT="${CHART_DIR}/examples/values-default.yaml"
STAGE1="${CHART_DIR}/examples/values-signoz-0.134-stage1.yaml"
STAGE2="${CHART_DIR}/examples/values-signoz-0.134-stage2.yaml"
SIGNOZ_ARCHIVE="${CHART_DIR}/charts/signoz-0.134.0.tgz"
OLD_SIGNOZ_ARCHIVE="${CHART_DIR}/charts/signoz-0.133.0.tgz"
IMAGE_LIST="${CHART_DIR}/../tools/image_lists/k8s_images_2.1.2.txt"
TMP="$(mktemp -d)"; trap 'rm -rf "${TMP}"' EXIT
assert_contains() { grep -Fq -- "$2" "$1" || { echo "Expected $1 to contain: $2" >&2; exit 1; }; }
assert_not_contains() { ! grep -Fq -- "$2" "$1" || { echo "Unexpected $2 in $1" >&2; exit 1; }; }

stage1_render="${TMP}/stage1.yaml"; stage2_render="${TMP}/stage2.yaml"
signoz_values="${TMP}/signoz-values.yaml"
helm template phase5 "${CHART_DIR}" -n phase5 --is-upgrade -f "${DEFAULT}" -f "${STAGE1}" >"${stage1_render}"
helm template phase5 "${CHART_DIR}" -n phase5 --is-upgrade -f "${DEFAULT}" -f "${STAGE2}" >"${stage2_render}"
helm show values "${SIGNOZ_ARCHIVE}" >"${signoz_values}"
assert_contains "${CHART_DIR}/Chart.yaml" 'version: "0.134.0"'
assert_contains "${CHART_DIR}/Chart.lock" 'version: 0.134.0'
[ -f "${SIGNOZ_ARCHIVE}" ] || { echo "Missing ${SIGNOZ_ARCHIVE}" >&2; exit 1; }
[ ! -e "${OLD_SIGNOZ_ARCHIVE}" ] || { echo "Obsolete ${OLD_SIGNOZ_ARCHIVE} is still present" >&2; exit 1; }
[ "$(shasum -a 256 "${SIGNOZ_ARCHIVE}" | awk '{print $1}')" = \
  "17a4bee002be12c35cac1a15791911e53cd87f2fb8f3a68df1005f22bb0aa631" ] || {
  echo "SigNoZ 0.134.0 chart digest does not match the official artifact" >&2
  exit 1
}
assert_contains "${signoz_values}" 'tag: v0.134.0'
assert_contains "${signoz_values}" 'tag: v0.144.6'
assert_contains "${signoz_values}" 'tag: 25.12.5'
assert_contains "${signoz_values}" 'postgresql:'
[ "$(awk '/^postgresql:/{found=1; next} found && /^[[:space:]]+enabled:/{print $2; exit}' "${signoz_values}")" = "false" ] || {
  echo "The embedded SigNoZ PostgreSQL metastore must remain disabled by default" >&2
  exit 1
}
assert_contains "${IMAGE_LIST}" 'docker.io/signoz/signoz:v0.134.0'
assert_not_contains "${IMAGE_LIST}" 'docker.io/signoz/signoz:v0.133.0'
assert_contains "${stage1_render}" 'image: docker.io/signoz/signoz:v0.113.0'
assert_contains "${stage1_render}" 'image: docker.io/signoz/signoz-otel-collector:v0.144.1'
assert_contains "${stage2_render}" 'image: docker.io/signoz/signoz:v0.134.0'
assert_contains "${stage2_render}" 'image: docker.io/signoz/signoz-otel-collector:v0.144.6'
assert_contains "${stage2_render}" 'name: signoz-telemetrystore-migrator'
assert_contains "${stage2_render}" 'app.kubernetes.io/name: signoz-stage2-validation'
assert_contains "${stage2_render}" '"helm.sh/hook-weight": "31"'
assert_contains "${stage2_render}" 'job/signoz-telemetrystore-migrator'
assert_contains "${stage2_render}" 'Historical telemetry and new ingestion validated.'

run_resource() {
  env KUBECTL="${MOCK_KUBECTL}" MOCK_SCENARIO="$1" NAMESPACE=obaas RELEASE_NAME=obaas \
    VALIDATION_TIMEOUT=10m SIGNOZ_VERSION=v0.134.0 COLLECTOR_VERSION=v0.144.6 \
    /bin/sh "${RESOURCE_SCRIPT}" >"${TMP}/resource-$1.log" 2>&1
}
run_resource success
assert_contains "${TMP}/resource-success.log" 'migrations, login, and dashboards validated'
for scenario in migration-failed setup-failed wrong-signoz wrong-collector; do
  if run_resource "${scenario}"; then echo "Expected ${scenario} failure" >&2; exit 1; fi
done

run_data() {
  local dir="${TMP}/data-$1"; mkdir -p "${dir}/bin"
  cp "${MOCK_CURL}" "${dir}/bin/curl"
  printf '#!/bin/sh\nexit 0\n' >"${dir}/bin/sleep"; chmod +x "${dir}/bin/curl" "${dir}/bin/sleep"
  env PATH="${dir}/bin:${PATH}" MOCK_SCENARIO="$1" MOCK_STATE_DIR="${dir}" \
    SIGNOZ_URL=http://signoz COLLECTOR_URL=http://collector CLICKHOUSE_URL=http://clickhouse \
    CLICKHOUSE_PASSWORD=password BASELINE_ROWS=100 /bin/sh "${DATA_SCRIPT}" >"${dir}/output.log" 2>&1
}
run_data success
assert_contains "${TMP}/data-success/output.log" 'Historical telemetry and new ingestion validated.'
for scenario in historical-lost no-ingestion; do
  if run_data "${scenario}"; then echo "Expected ${scenario} failure" >&2; exit 1; fi
done

echo "SigNoz upgrade Phase 5 regression test passed"
