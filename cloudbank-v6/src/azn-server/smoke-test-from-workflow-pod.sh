#!/usr/bin/env bash

# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at
# https://oss.oracle.com/licenses/upl.

set -euo pipefail
set +x

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="$REPOSITORY_ROOT/.env"
NAMESPACE="${NAMESPACE:-obaas}"
POD="${WORKFLOW_POD:-obaas-otmm-workflow-server-64655c896-jrsb8}"
CONTAINER="${WORKFLOW_CONTAINER:-server}"
REMOTE_ROOT="/tmp/cloudbank-azn-smoke-test-$$"
LOCAL_ROOT="$(mktemp -d)"

cleanup() {
    kubectl exec -n "$NAMESPACE" "$POD" -c "$CONTAINER" -- rm -rf "$REMOTE_ROOT" >/dev/null 2>&1 || true
    rm -rf "$LOCAL_ROOT"
}
trap cleanup EXIT

[[ -f "$ENV_FILE" ]] || { printf 'ERROR: missing %s\n' "$ENV_FILE" >&2; exit 2; }

awk -F= '
BEGIN {
    split("AZN_BOOTSTRAP_USERS_ADMIN_PASSWORD AZN_BOOTSTRAP_USERS_USER_PASSWORD AZN_AUTHORIZATION_SERVER_SERVICE_CLIENT_SECRET AZN_AUTHORIZATION_SERVER_DOCUMENT_INGEST_CLIENT_SECRET AZN_AUTHORIZATION_SERVER_DOCUMENT_REVIEW_CLIENT_SECRET AZN_AUTHORIZATION_SERVER_AI_AGENT_CLIENT_SECRET AZN_AUTHORIZATION_SERVER_DEFAULT_CLIENT_SECRET AZN_AUTHORIZATION_SERVER_MICROTX_CLIENT_SECRET AZN_AUTHORIZATION_SERVER_MICROTX_CONSOLE_CLIENT_ID AZN_AUTHORIZATION_SERVER_MICROTX_CONSOLE_CLIENT_SECRET AZN_AUTHORIZATION_SERVER_MICROTX_CONSOLE_CLIENT_SCOPES AZN_AUTHORIZATION_SERVER_MICROTX_CONSOLE_CLIENT_REDIRECT_URI AZN_AUTHORIZATION_SERVER_MICROTX_CONSOLE_CLIENT_POST_LOGOUT_REDIRECT_URI", names, " ")
    for (i in names) wanted[names[i]] = 1
}
wanted[$1] { print }
' "$ENV_FILE" > "$LOCAL_ROOT/.env"

kubectl exec -n "$NAMESPACE" "$POD" -c "$CONTAINER" -- mkdir -p "$REMOTE_ROOT/src/azn-server"
kubectl cp "$SCRIPT_DIR/smoke-test.sh" "$NAMESPACE/$POD:$REMOTE_ROOT/src/azn-server/smoke-test.sh" -c "$CONTAINER"
kubectl cp "$LOCAL_ROOT/.env" "$NAMESPACE/$POD:$REMOTE_ROOT/.env" -c "$CONTAINER"
kubectl exec -n "$NAMESPACE" "$POD" -c "$CONTAINER" -- chmod 700 "$REMOTE_ROOT/src/azn-server/smoke-test.sh"
kubectl exec -n "$NAMESPACE" "$POD" -c "$CONTAINER" -- \
    env BASE_URL="http://azn-server.$NAMESPACE.svc.cluster.local:8080" \
    bash "$REMOTE_ROOT/src/azn-server/smoke-test.sh" --non-interactive
