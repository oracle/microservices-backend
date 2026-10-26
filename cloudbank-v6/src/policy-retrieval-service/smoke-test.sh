#!/usr/bin/env bash

# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at
# https://oss.oracle.com/licenses/upl.

set -euo pipefail
set +x

BASE_URL="${POLICY_RETRIEVAL_BASE_URL:-http://127.0.0.1:8086}"
AZN_BASE_URL="${AZN_BASE_URL:-http://127.0.0.1:8080}"
CLIENT_ID="${SERVICE_CLIENT_ID:-cloudbank-service-client}"
CLIENT_SECRET="${SERVICE_CLIENT_SECRET:?Set SERVICE_CLIENT_SECRET}"
ENDPOINT="$BASE_URL/internal/api/v1/policy-evidence"
QUERY='loan underwriting income affordability'

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

anonymous_status="$(curl --silent --output /dev/null --write-out '%{http_code}' \
    --get --data-urlencode "query=$QUERY" "$ENDPOINT")"
[[ "$anonymous_status" == "401" ]] || {
    printf 'FAIL: anonymous policy-evidence request returned HTTP %s.\n' "$anonymous_status" >&2
    exit 1
}

response="$(curl --silent --show-error --fail --get \
    --header "Authorization: Bearer $token" --data-urlencode "query=$QUERY" "$ENDPOINT")"
printf '%s' "$response" | grep -Eq '^\[[[:space:]]*([[:print:]]|[[:space:]])*\]$' || {
    printf 'FAIL: policy-evidence response was not a JSON array.\n' >&2
    exit 1
}
result_count="$(printf '%s' "$response" | { grep -o '"chunkId"[[:space:]]*:' || true; } | wc -l | tr -d '[:space:]')"
[[ "$result_count" -le 3 ]] || {
    printf 'FAIL: policy-evidence returned %s results; expected at most 3.\n' "$result_count" >&2
    exit 1
}

token=""
response=""
printf 'PASS: policy-retrieval-service rejects anonymous access and returns bounded service-token policy evidence.\n'
