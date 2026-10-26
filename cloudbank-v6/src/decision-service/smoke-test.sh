#!/usr/bin/env bash
set -euo pipefail
set +x

BASE_URL="${DECISION_BASE_URL:-http://127.0.0.1:8088}"
AZN_BASE_URL="${AZN_BASE_URL:-http://127.0.0.1:8080}"
CLIENT_ID="${SERVICE_CLIENT_ID:-cloudbank-service-client}"
CLIENT_SECRET="${SERVICE_CLIENT_SECRET:?Set SERVICE_CLIENT_SECRET}"
DECISION_ENDPOINT="$BASE_URL/internal/api/v1/decisions/DEC-00000000000000000000000000000000"

if [[ "${1-}" == "--non-interactive" ]]; then
    shift
fi
[[ $# -eq 0 ]] || { printf 'Usage: %s [--non-interactive]\n' "$0" >&2; exit 2; }

token="$(curl --silent --show-error --fail --user "$CLIENT_ID:$CLIENT_SECRET" \
    --data-urlencode grant_type=client_credentials --data-urlencode scope=cloudbank.internal \
    "$AZN_BASE_URL/oauth2/token" | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')"
[[ -n "$token" ]] || { printf 'FAIL: azn-server did not issue a service token.\n' >&2; exit 1; }

curl --silent --show-error --fail "$BASE_URL/actuator/health" |
    grep -q '"status"[[:space:]]*:[[:space:]]*"UP"'

anonymous_status="$(curl --silent --output /dev/null --write-out '%{http_code}' "$DECISION_ENDPOINT")"
[[ "$anonymous_status" == "401" ]] || {
    printf 'FAIL: anonymous decision lookup returned HTTP %s.\n' "$anonymous_status" >&2
    exit 1
}

response_file="$(mktemp)"
trap 'rm -f -- "$response_file"' EXIT
authorized_status="$(curl --silent --show-error --output "$response_file" --write-out '%{http_code}' \
    --header "Authorization: Bearer $token" \
    --header 'X-Trace-Id: 0123456789abcdef0123456789abcdef' "$DECISION_ENDPOINT")"
[[ "$authorized_status" == "404" ]] || {
    printf 'FAIL: authorized missing-decision lookup returned HTTP %s.\n' "$authorized_status" >&2
    exit 1
}
grep -q '"code"[[:space:]]*:[[:space:]]*"DECISION_NOT_FOUND"' "$response_file" || {
    printf 'FAIL: decision-service did not return its bounded not-found response.\n' >&2
    exit 1
}

token=""
printf 'PASS: decision-service rejects anonymous access and accepts the azn-server signed internal service token.\n'
