#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${GEOGRAPHIC_RISK_BASE_URL:-http://127.0.0.1:8083}"
AZN_BASE_URL="${AZN_BASE_URL:-http://127.0.0.1:8080}"
CLIENT_ID="${SERVICE_CLIENT_ID:-cloudbank-service-client}"
CLIENT_SECRET="${SERVICE_CLIENT_SECRET:?Set SERVICE_CLIENT_SECRET}"

token="$(curl --silent --show-error --fail --user "$CLIENT_ID:$CLIENT_SECRET" \
  --data-urlencode grant_type=client_credentials \
  --data-urlencode scope=cloudbank.internal \
  "$AZN_BASE_URL/oauth2/token" | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')"
[[ -n "$token" ]]

curl --silent --show-error --fail "$BASE_URL/health/ready" >/dev/null

anonymous_status="$(curl --silent --output /dev/null --write-out '%{http_code}' \
  --request POST "$BASE_URL/internal/api/v1/geographic-risk/evaluations" \
  --header 'Content-Type: application/json' \
  --header 'Idempotency-Key: geo-risk-anonymous-001' \
  --data '{"applicationId":"APP-RISK-005","workflowId":"WF-APP-RISK-005","taskReference":"evaluate-geographic-risk","traceId":"0123456789abcdef0123456789abcdef"}')"
[[ "$anonymous_status" == "401" ]]

response="$(curl --silent --show-error --fail \
  --request POST "$BASE_URL/internal/api/v1/geographic-risk/evaluations" \
  --header "Authorization: Bearer $token" \
  --header 'Content-Type: application/json' \
  --header 'Idempotency-Key: geo-risk-APP-RISK-005-WF-APP-RISK-005-001' \
  --data '{"applicationId":"APP-RISK-005","workflowId":"WF-APP-RISK-005","taskReference":"evaluate-geographic-risk","traceId":"0123456789abcdef0123456789abcdef"}')"

printf '%s' "$response" | grep -q '"disposition"[[:space:]]*:[[:space:]]*"MANUAL_REVIEW"'
printf '%s' "$response" | grep -q '"signalCode"[[:space:]]*:[[:space:]]*"BOUNDARY_REVIEW_REQUIRED"'
token=""
response=""
printf 'PASS: geographic-risk-service rejects anonymous access and accepts the azn-server signed service token.\n'
