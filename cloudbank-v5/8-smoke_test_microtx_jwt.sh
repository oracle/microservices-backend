#!/bin/bash
# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at http://oss.oracle.com/licenses/upl.

# Validates azn-server JWT authentication to the MicroTx Workflow API and
# records evidence that the workflow server can retrieve azn-server JWKS.

set -euo pipefail

NAMESPACE="obaas"
AZN_PORT="18080"
WORKFLOW_PORT="19010"
CLIENT_ID="microtx-workflow-client"
CLIENT_SECRET_KEY="microtx-client-secret"
SECRET_NAME="obaas-azn-server-auth"
WORKFLOW_PATH="/workflow-server/api/metadata/workflow"

usage() {
    cat <<'EOF'
MicroTx JWT smoke test

Usage:
  ./8-smoke_test_microtx_jwt.sh [-n namespace] [--secret-name name] [--azn-port port] [--workflow-port port]

  --secret-name NAME  OAuth client secret resource (default: obaas-azn-server-auth).
                      Must contain the microtx-client-secret key.

Example (replace placeholders with your configuration):
  ./8-smoke_test_microtx_jwt.sh -n <namespace> --secret-name <oauth-secret-name>
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--namespace) NAMESPACE="$2"; shift 2 ;;
        --secret-name)
            if [[ $# -lt 2 || -z "$2" || "$2" == -* ]]; then
                echo "Option --secret-name requires a nonempty secret name." >&2
                usage >&2
                exit 1
            fi
            SECRET_NAME="$2"; shift 2 ;;
        --azn-port) AZN_PORT="$2"; shift 2 ;;
        --workflow-port) WORKFLOW_PORT="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
done

AZN_PF_PID=""
WORKFLOW_PF_PID=""
TMP_DIR=""
STAGE="initializing"
PASSED=false
progress() { printf '> %s\n' "$*"; }
success() { printf '+ %s\n' "$*"; }
fail() { printf 'x %s\n' "$*" >&2; exit 1; }
show_forward_logs() {
    printf '\nAuthorization server port-forward log:\n' >&2
    tail -20 "$TMP_DIR/azn-port-forward.log" >&2 || true
    printf '\nWorkflow server port-forward log:\n' >&2
    tail -20 "$TMP_DIR/workflow-port-forward.log" >&2 || true
}
cleanup() {
    local exit_status=$?
    if [[ "$PASSED" == true ]]; then
        success "MicroTx JWT smoke test passed."
    else
        printf 'x MicroTx JWT smoke test failed during %s (exit %s).\n' "$STAGE" "$exit_status" >&2
    fi
    if [[ -n "$AZN_PF_PID" || -n "$WORKFLOW_PF_PID" ]]; then
        progress "Stopping temporary port-forwards..."
        [[ -n "$AZN_PF_PID" ]] && kill "$AZN_PF_PID" 2>/dev/null || true
        [[ -n "$WORKFLOW_PF_PID" ]] && kill "$WORKFLOW_PF_PID" 2>/dev/null || true
        [[ -n "$AZN_PF_PID" ]] && wait "$AZN_PF_PID" 2>/dev/null || true
        [[ -n "$WORKFLOW_PF_PID" ]] && wait "$WORKFLOW_PF_PID" 2>/dev/null || true
        success "Port-forwards stopped."
    fi
    [[ -n "$TMP_DIR" ]] && rm -rf "$TMP_DIR"
    return "$exit_status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

printf '\n==============================================================================\n'
printf '  MicroTx JWT Smoke Test\n'
printf '==============================================================================\n'
printf 'Namespace: %s | Authorization port: %s | Workflow port: %s\n' "$NAMESPACE" "$AZN_PORT" "$WORKFLOW_PORT"
STAGE="prerequisite checks"
progress "Checking required tools..."
for tool in kubectl curl jq base64 awk; do
    command -v "$tool" >/dev/null || fail "Required tool '$tool' is unavailable."
done
TMP_DIR=$(umask 077; mktemp -d "${TMPDIR:-/tmp}/microtx-jwt.XXXXXX")
success "Required tools are available."

STAGE="port-forward startup"
progress "Starting svc/azn-server port-forward on localhost:${AZN_PORT}..."
kubectl port-forward -n "$NAMESPACE" svc/azn-server "${AZN_PORT}:8080" >"$TMP_DIR/azn-port-forward.log" 2>&1 &
AZN_PF_PID=$!
progress "Starting svc/obaas-otmm-workflow-server port-forward on localhost:${WORKFLOW_PORT}..."
kubectl port-forward -n "$NAMESPACE" svc/obaas-otmm-workflow-server "${WORKFLOW_PORT}:9010" \
    >"$TMP_DIR/workflow-port-forward.log" 2>&1 &
WORKFLOW_PF_PID=$!

STAGE="service readiness checks"
progress "Waiting for authorization and workflow health endpoints..."
READY=false
for attempt in {1..30}; do
    if ! kill -0 "$AZN_PF_PID" 2>/dev/null || ! kill -0 "$WORKFLOW_PF_PID" 2>/dev/null; then
        show_forward_logs
        fail "A port-forward exited before the services became ready."
    fi
    if curl --noproxy '*' --silent --fail --max-time 2 "http://127.0.0.1:${AZN_PORT}/actuator/health" >/dev/null \
        && curl --noproxy '*' --silent --fail --max-time 2 "http://127.0.0.1:${WORKFLOW_PORT}/workflow-server/health" >/dev/null; then
        READY=true
        break
    fi
    if (( attempt % 5 == 0 )); then
        progress "Still waiting for healthy services (attempt ${attempt}/30)..."
    fi
    sleep 2
done
if [[ "$READY" != true ]]; then
    show_forward_logs
    fail "Services did not become healthy after 30 readiness attempts."
fi
success "Authorization and workflow services are reachable."

STAGE="OAuth client secret lookup"
progress "Reading '${CLIENT_SECRET_KEY}' from ${SECRET_NAME}..."
if ! CLIENT_SECRET=$(kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" \
    -o "jsonpath={.data.${CLIENT_SECRET_KEY}}" | base64 -d); then
    fail "Could not read '${CLIENT_SECRET_KEY}' from secret '${SECRET_NAME}' in namespace '${NAMESPACE}'."
fi
[[ -n "$CLIENT_SECRET" ]] || fail "Secret ${SECRET_NAME} has no '${CLIENT_SECRET_KEY}' value."
success "OAuth client secret is available."
STAGE="OAuth token request"
progress "Requesting a ${CLIENT_ID} token with microtx.workflow scope..."
curl --noproxy '*' --silent --show-error --fail \
    -u "${CLIENT_ID}:${CLIENT_SECRET}" \
    -d grant_type=client_credentials \
    -d scope=microtx.workflow \
    "http://127.0.0.1:${AZN_PORT}/oauth2/token" >"$TMP_DIR/token.json"

TOKEN=$(jq -r .access_token "$TMP_DIR/token.json")
[[ -n "$TOKEN" && "$TOKEN" != null ]] || fail "Token response did not contain an access token."
success "Scoped OAuth token issued."

STAGE="JWT claims inspection"
echo "JWT claims:"
printf '%s' "$TOKEN" | awk -F. '{print $2}' | base64 -d 2>/dev/null \
    | jq '{iss,aud,scope,roles}'

STAGE="JWKS retrieval"
progress "Retrieving the authorization server signing keys..."
echo "JWKS:"
curl --noproxy '*' --silent --show-error --fail \
    "http://127.0.0.1:${AZN_PORT}/oauth2/jwks" | jq '{keyCount:(.keys|length),kids:[.keys[].kid]}'

STAGE="Workflow API checks"
progress "Checking Workflow API without a JWT (expected HTTP 401)..."
NO_TOKEN_STATUS=$(curl --noproxy '*' --silent --show-error --output "$TMP_DIR/no-token.json" \
    --write-out '%{http_code}' "http://127.0.0.1:${WORKFLOW_PORT}${WORKFLOW_PATH}")
echo "Workflow API without JWT: HTTP ${NO_TOKEN_STATUS}"
[[ "$NO_TOKEN_STATUS" == "401" ]] || fail "Workflow API without JWT returned HTTP ${NO_TOKEN_STATUS}, expected 401."
progress "Checking Workflow API with azn-server JWT (expected HTTP 200)..."
TOKEN_STATUS=$(curl --noproxy '*' --silent --show-error --output "$TMP_DIR/with-token.json" \
    --write-out '%{http_code}' -H "Authorization: Bearer ${TOKEN}" \
    "http://127.0.0.1:${WORKFLOW_PORT}${WORKFLOW_PATH}")

echo "Workflow API with azn-server JWT: HTTP ${TOKEN_STATUS}"
[[ "$TOKEN_STATUS" == "200" ]] || fail "Workflow API with azn-server JWT returned HTTP ${TOKEN_STATUS}, expected 200."

STAGE="JWKS callback evidence collection"
progress "Locating the authorization server pod and collecting JWKS access-log evidence..."
AZN_POD=$(kubectl get pod -n "$NAMESPACE" -l app.kubernetes.io/name=azn-server \
    -o jsonpath='{.items[0].metadata.name}')
[[ -n "$AZN_POD" ]] || fail "No authorization server pod was found."
echo "JWKS callback evidence:"
kubectl exec -n "$NAMESPACE" "$AZN_POD" -- sh -c \
    'tail -200 /tmp/tomcat.8080.*/logs/access_log.*' \
    | grep 'GET /oauth2/jwks HTTP/1.1" 200' | tail -5 \
    || fail "Could not collect successful JWKS requests from the authorization server access log."

PASSED=true
