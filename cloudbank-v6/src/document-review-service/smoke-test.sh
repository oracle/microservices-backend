#!/usr/bin/env bash
set -euo pipefail
BASE_URL="${DOCUMENT_REVIEW_BASE_URL:-http://127.0.0.1:8084}"
AZN_BASE_URL="${AZN_BASE_URL:-http://127.0.0.1:8080}"
CLIENT_ID="${SERVICE_CLIENT_ID:-cloudbank-service-client}"
CLIENT_SECRET="${SERVICE_CLIENT_SECRET:?Set SERVICE_CLIENT_SECRET}"
token="$(curl --silent --show-error --fail --user "$CLIENT_ID:$CLIENT_SECRET" --data-urlencode grant_type=client_credentials --data-urlencode scope=cloudbank.internal "$AZN_BASE_URL/oauth2/token" | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')"
[[ -n "$token" ]]
curl --silent --show-error --fail "$BASE_URL/actuator/health" >/dev/null
anonymous_status="$(curl --silent --output /dev/null --write-out '%{http_code}' \
  "$BASE_URL/internal/api/v1/document-reviews/DREV-00000000000000000000000000000000")"
[[ "$anonymous_status" == "401" ]]
authorized_status="$(curl --silent --output /dev/null --write-out '%{http_code}' \
  --header "Authorization: Bearer $token" \
  "$BASE_URL/internal/api/v1/document-reviews/DREV-00000000000000000000000000000000")"
[[ "$authorized_status" == "404" ]]
printf 'PASS: document-review-service accepts the azn-server signed service token and rejects anonymous access.\n'
