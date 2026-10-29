#!/usr/bin/env bash
# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at http://oss.oracle.com/licenses/upl.

# Authenticated endpoint test for helidon-producer.

set -euo pipefail

NAMESPACE=${1:-obaas}
GATEWAY_URL=${2:-localhost:18080}
AUTH_SECRET_NAME=${3:-}
AZN_LOCAL_PORT=${AZN_LOCAL_PORT:-19081}
PF_PID=""
PROD_PF_PID=""

cleanup() {
    if [[ -n "$PF_PID" ]]; then
        kill "$PF_PID" 2>/dev/null || true
        wait "$PF_PID" 2>/dev/null || true
    fi
    if [[ -n "$PROD_PF_PID" ]]; then
        kill "$PROD_PF_PID" 2>/dev/null || true
        wait "$PROD_PF_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

wait_for_url() {
    local url="$1"
    local attempts=0

    until curl -s -o /dev/null "$url"; do
        attempts=$((attempts + 1))
        if [[ "$attempts" -ge 30 ]]; then
            echo "Timed out waiting for $url" >&2
            return 1
        fi
        sleep 1
    done
}

require_free_port() {
    local port="$1"

    if nc -z localhost "$port" 2>/dev/null; then
        echo "Local port $port is already in use." >&2
        return 1
    fi
}

discover_auth_secret() {
    local matches
    local match_count

    matches=$(kubectl get secrets -n "$NAMESPACE" \
        -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
        | awk '/-azn-server-auth$/')
    match_count=$(printf '%s\n' "$matches" | awk 'NF { count++ } END { print count + 0 }')

    if [[ "$match_count" -eq 1 ]]; then
        printf '%s\n' "$matches"
        return 0
    fi

    if [[ "$match_count" -eq 0 ]]; then
        echo "No *-azn-server-auth secret found in namespace $NAMESPACE." >&2
    else
        echo "Multiple *-azn-server-auth secrets found in namespace $NAMESPACE:" >&2
        printf '%s\n' "$matches" >&2
    fi
    echo "Pass the secret name as the third argument." >&2
    return 1
}

echo "Testing helidon-producer in namespace: $NAMESPACE"

if [[ -z "$AUTH_SECRET_NAME" ]]; then
    AUTH_SECRET_NAME=$(discover_auth_secret)
fi

echo "Fetching service client secret from $AUTH_SECRET_NAME..."
CLIENT_SECRET=$(kubectl get secret "$AUTH_SECRET_NAME" -n "$NAMESPACE" \
    -o jsonpath='{.data.service-client-secret}' | base64 -d)

if [[ -z "$CLIENT_SECRET" ]]; then
    echo "Secret $AUTH_SECRET_NAME does not contain service-client-secret." >&2
    exit 1
fi

echo "Port-forwarding azn-server to get an auth token..."
require_free_port "$AZN_LOCAL_PORT"
kubectl port-forward svc/azn-server "${AZN_LOCAL_PORT}:8080" -n "$NAMESPACE" >/dev/null 2>&1 &
PF_PID=$!
wait_for_url "http://localhost:${AZN_LOCAL_PORT}/.well-known/oauth-authorization-server"

echo "Fetching OAuth2 bearer token..."
TOKEN=$(curl -fsS -X POST "http://localhost:${AZN_LOCAL_PORT}/oauth2/token" \
    -H "Host: azn-server:8080" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -u "cloudbank-service-client:${CLIENT_SECRET}" \
    -d "grant_type=client_credentials&scope=cloudbank.internal" \
    | jq -er '.access_token')

kill "$PF_PID" 2>/dev/null || true
wait "$PF_PID" 2>/dev/null || true
PF_PID=""

case "$GATEWAY_URL" in
    localhost:*|127.0.0.1:*)
        PRODUCER_LOCAL_PORT=${GATEWAY_URL##*:}
        require_free_port "$PRODUCER_LOCAL_PORT"
        echo "Port-forwarding helidon-producer on local port $PRODUCER_LOCAL_PORT..."
        kubectl port-forward svc/helidon-producer "${PRODUCER_LOCAL_PORT}:8080" \
            -n "$NAMESPACE" >/dev/null 2>&1 &
        PROD_PF_PID=$!
        wait_for_url "http://${GATEWAY_URL}/"
        ;;
    *)
        echo "Using caller-provided producer URL: http://${GATEWAY_URL}"
        ;;
esac

echo "Sending message to /post..."
RESPONSE_FILE=$(mktemp)
trap 'rm -f "$RESPONSE_FILE"; cleanup' EXIT
HTTP_STATUS=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
    -X POST \
    -H "Content-Type: text/plain" \
    -H "Authorization: Bearer $TOKEN" \
    -d "Hello from Helidon Producer at $(date)" \
    "http://${GATEWAY_URL}/post")
cat "$RESPONSE_FILE"
echo

if [[ "$HTTP_STATUS" != "200" ]]; then
    echo "helidon-producer returned HTTP $HTTP_STATUS, expected 200." >&2
    exit 1
fi

echo "helidon-producer returned HTTP 200."
echo "Check Kafka delivery with:"
echo "kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=helidon-consumer"
