#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="${CHART_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
IMAGE_LIST="${CHART_DIR}/../tools/image_lists/k8s_images_2.1.2.txt"
RELEASE_NOTES="${CHART_DIR}/../../../docs-source/site/docs/rel_notes/index.mdx"
PUBLIC_RENDER="$(mktemp)"
PRIVATE_RENDER="$(mktemp)"

cleanup() {
  rm -f "${PUBLIC_RENDER}" "${PRIVATE_RENDER}"
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
    echo "Unexpected stale value in ${file}: ${unexpected}" >&2
    exit 1
  fi
}

require_command helm
require_command tar
require_command grep

assert_contains "${CHART_DIR}/Chart.yaml" 'version: "2.16.0"'
assert_contains "${CHART_DIR}/Chart.lock" 'version: 2.16.0'
assert_contains "${CHART_DIR}/values.yaml" 'tag: "3.17.0-ubuntu"'
assert_contains "${CHART_DIR}/examples/values-private-registry.yaml" 'tag: "3.17.0-ubuntu"'
assert_contains "${IMAGE_LIST}" 'docker.io/apache/apisix:3.17.0-ubuntu'
assert_contains "${RELEASE_NOTES}" '| Apache APISIX | `docker.io/apache/apisix` | 3.17.0-ubuntu |'

CHART_METADATA="$(helm show chart "${CHART_DIR}/charts/apisix-2.16.0.tgz")"
grep -Fq -- 'version: 2.16.0' <<<"${CHART_METADATA}"
grep -Fq -- 'appVersion: 3.17.0' <<<"${CHART_METADATA}"

helm lint "${CHART_DIR}" -f "${CHART_DIR}/examples/values-default.yaml"
helm template apisix-upgrade-test "${CHART_DIR}" \
  --namespace apisix-upgrade-test \
  -f "${CHART_DIR}/examples/values-default.yaml" >"${PUBLIC_RENDER}"
helm template apisix-upgrade-test "${CHART_DIR}" \
  --namespace apisix-upgrade-test \
  -f "${CHART_DIR}/examples/values-private-registry.yaml" >"${PRIVATE_RENDER}"

assert_contains "${PUBLIC_RENDER}" 'image: "docker.io/apache/apisix:3.17.0-ubuntu"'
assert_contains "${PRIVATE_RENDER}" 'image: "myregistry.example.com/apache/apisix:3.17.0-ubuntu"'
assert_contains "${PUBLIC_RENDER}" 'kind: Deployment'
assert_contains "${PUBLIC_RENDER}" 'name: apisix-upgrade-test'
assert_not_contains "${PUBLIC_RENDER}" 'apache/apisix:3.16.0-ubuntu'
assert_not_contains "${PRIVATE_RENDER}" 'apache/apisix:3.16.0-ubuntu'

echo "APISIX chart upgrade regression test passed"
