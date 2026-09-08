#!/usr/bin/env bash
# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at http://oss.oracle.com/licenses/upl.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="${CHART_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
CLEANUP_SCRIPT="${CHART_DIR}/files/signoz-upgrade/cleanup-signoz-oidc-mock.sh"
MOCK_KUBECTL="${SCRIPT_DIR}/fixtures/signoz-upgrade/mock-phase6-kubectl.sh"
DEFAULT="${CHART_DIR}/examples/values-default.yaml"
PRIVATE="${CHART_DIR}/examples/values-private-registry.yaml"
STAGE1="${CHART_DIR}/examples/values-signoz-0.134-stage1.yaml"
STAGE2="${CHART_DIR}/examples/values-signoz-0.134-stage2.yaml"
IMAGE_LIST="${CHART_DIR}/../tools/image_lists/k8s_images_2.1.2.txt"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

assert_contains() { grep -Fq -- "$2" "$1" || { echo "Expected $1 to contain: $2" >&2; exit 1; }; }
assert_not_contains() { ! grep -Fq -- "$2" "$1" || { echo "Unexpected $2 in $1" >&2; exit 1; }; }

fresh_render="${TMP}/fresh.yaml"
private_render="${TMP}/private.yaml"
stage1_render="${TMP}/stage1.yaml"
stage2_render="${TMP}/stage2.yaml"
helm template phase6 "${CHART_DIR}" -n phase6 -f "${DEFAULT}" >"${fresh_render}"
helm template phase6 "${CHART_DIR}" -n phase6 -f "${PRIVATE}" >"${private_render}"
helm template phase6 "${CHART_DIR}" -n phase6 --is-upgrade -f "${DEFAULT}" -f "${STAGE1}" >"${stage1_render}"
helm template phase6 "${CHART_DIR}" -n phase6 --is-upgrade -f "${DEFAULT}" -f "${STAGE2}" >"${stage2_render}"

# Fresh installs contain only the final stack and do not run upgrade-only hooks.
assert_contains "${fresh_render}" 'image: docker.io/signoz/signoz:v0.134.0'
assert_contains "${fresh_render}" 'image: docker.io/signoz/signoz-otel-collector:v0.144.6'
assert_contains "${fresh_render}" 'image: docker.io/clickhouse/clickhouse-server:25.12.5'
assert_contains "${fresh_render}" 'volumeClaimTemplates:'
assert_contains "${fresh_render}" 'kind: ClickHouseInstallation'
assert_contains "${fresh_render}" 'name: signoz-telemetrystore-migrator'
assert_contains "${fresh_render}" 'name: SIGNOZ_TOKENIZER_JWT_SECRET'
assert_contains "${fresh_render}" 'name: SIGNOZ_USER_ROOT_EMAIL'
assert_not_contains "${fresh_render}" 'image: docker.io/signoz/signoz:v0.113.0'
assert_not_contains "${fresh_render}" 'image: docker.io/signoz/signoz-otel-collector:v0.144.1'
assert_not_contains "${fresh_render}" 'image: docker.io/clickhouse/clickhouse-server:25.5.6'
assert_not_contains "${fresh_render}" 'app.kubernetes.io/name: signoz-upgrade-cleanup'
assert_not_contains "${fresh_render}" 'name: oidc-mock'
assert_not_contains "${fresh_render}" 'name: SSL_CERT_FILE'
assert_not_contains "${fresh_render}" 'name: SIGNOZ_JWT_SECRET'
assert_not_contains "${fresh_render}" 'signoz-schema-migrator'
assert_not_contains "${fresh_render}" 'groundnuty/k8s-wait-for'

# Disconnected/private-registry installs no longer carry the obsolete nginx OIDC mock.
assert_not_contains "${private_render}" 'myregistry.example.com/nginx:alpine'
assert_not_contains "${private_render}" 'name: oidc-mock'
assert_not_contains "${private_render}" 'name: SSL_CERT_FILE'
assert_not_contains "${CHART_DIR}/values.yaml" 'airGapped:'
assert_not_contains "${PRIVATE}" 'airGapped:'
assert_not_contains "${IMAGE_LIST}" 'groundnuty/k8s-wait-for'
assert_not_contains "${IMAGE_LIST}" 'docker.io/nginx:alpine'

# The two-stage path retains intermediate images only in Stage 1, then cleans live leftovers.
assert_contains "${stage1_render}" 'image: docker.io/signoz/signoz:v0.113.0'
assert_contains "${stage1_render}" 'image: docker.io/signoz/signoz-otel-collector:v0.144.1'
assert_contains "${stage1_render}" 'app.kubernetes.io/name: signoz-upgrade-snapshot'
assert_not_contains "${stage1_render}" 'app.kubernetes.io/name: signoz-upgrade-cleanup'
assert_contains "${stage2_render}" 'image: docker.io/signoz/signoz:v0.134.0'
assert_contains "${stage2_render}" 'image: docker.io/signoz/signoz-otel-collector:v0.144.6'
assert_contains "${stage2_render}" 'app.kubernetes.io/name: signoz-upgrade-cleanup'
assert_contains "${stage2_render}" '"helm.sh/hook-weight": "-37"'
assert_contains "${stage2_render}" 'hook-delete-policy: before-hook-creation,hook-succeeded'
assert_contains "${stage2_render}" 'Obsolete SigNoz OIDC mock resources and StatefulSet settings are absent.'
assert_not_contains "${stage2_render}" 'image: docker.io/signoz/signoz:v0.113.0'
assert_not_contains "${stage2_render}" 'image: docker.io/signoz/signoz-otel-collector:v0.144.1'
assert_not_contains "${stage2_render}" '  name: phase6-signoz-airgap-patch'
assert_not_contains "${CLEANUP_SCRIPT}" 'delete pvc'
assert_not_contains "${CLEANUP_SCRIPT}" 'delete persistentvolumeclaim'
assert_not_contains "${CLEANUP_SCRIPT}" 'delete volumesnapshot'

run_cleanup() {
  local scenario="$1"
  local state_dir="${TMP}/${scenario}"
  mkdir -p "${state_dir}"
  env KUBECTL="${MOCK_KUBECTL}" MOCK_SCENARIO="${scenario}" MOCK_STATE_DIR="${state_dir}" \
    MOCK_LOG="${state_dir}/kubectl.log" NAMESPACE=phase6 STATEFULSET_NAME=phase6-signoz \
    OIDC_MOCK_HOOK_NAME=phase6-signoz-airgap-patch \
    /bin/sh "${CLEANUP_SCRIPT}" >"${state_dir}/output.log" 2>&1
}

run_cleanup oidc-mock
assert_contains "${TMP}/oidc-mock/output.log" 'Obsolete SigNoz OIDC mock resources and StatefulSet settings are absent.'
assert_contains "${TMP}/oidc-mock/kubectl.log" 'patch statefulset phase6-signoz'
assert_contains "${TMP}/oidc-mock/kubectl.log" 'delete secret mock-google-cert'
assert_contains "${TMP}/oidc-mock/kubectl.log" 'delete role phase6-signoz-airgap-patch'

run_cleanup clean
assert_not_contains "${TMP}/clean/kubectl.log" 'patch statefulset phase6-signoz'

for scenario in patch-stuck delete-stuck; do
  if run_cleanup "${scenario}"; then
    echo "Expected cleanup scenario ${scenario} to fail" >&2
    exit 1
  fi
done
assert_contains "${TMP}/patch-stuck/output.log" 'still contains the obsolete OIDC mock configuration'
assert_contains "${TMP}/delete-stuck/output.log" "obsolete resource 'configmap/signoz-oidc-mock' still exists"

echo "SigNoz upgrade Phase 6 regression test passed"
