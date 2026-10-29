#!/usr/bin/env bash
# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at http://oss.oracle.com/licenses/upl.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="${CHART_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
OUTPUT=$(mktemp)
trap 'rm -f "$OUTPUT"' EXIT

helm template etcd-test "$CHART_DIR" \
  --set otmm.coordinator.storage.type=etcd \
  --set otmm.coordinator.storage.etcd.endpoints=https://etcd:2379 \
  --set otmm.coordinator.storage.etcd.credentialSecretName=etcd-auth \
  --set otmm.coordinator.storage.etcd.caConfigMapName=etcd-ca \
  --show-only templates/otmm/configmap.yaml \
  --show-only templates/otmm/statefulset.yaml > "$OUTPUT"

# MicroTx prefixes these basenames with its fixed certificate directories.
rg -q 'STORAGE_ETCD_CREDENTIAL_SECRET_FILE_NAME: credentials.json' "$OUTPUT"
rg -q 'STORAGE_ETCD_CA_CERT_FILE_NAME: ca.pem' "$OUTPUT"
rg -q 'mountPath: /etcdecert$' "$OUTPUT"
rg -q 'mountPath: /etcdcacert$' "$OUTPUT"
rg -q 'path: credentials.json$' "$OUTPUT"
rg -q 'path: ca.pem$' "$OUTPUT"
if rg -q '/etc/otmm/etcd|initialize-coordinator-schema' "$OUTPUT"; then
  echo 'Unexpected etcd path or database schema initialization' >&2
  exit 1
fi
echo 'MicroTx etcd TLS render checks passed.'
