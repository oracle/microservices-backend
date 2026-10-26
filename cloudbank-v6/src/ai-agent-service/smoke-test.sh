#!/usr/bin/env bash
set -euo pipefail
set +x

BASE_URL="${AI_AGENT_BASE_URL:-http://127.0.0.1:8085}"
AZN_BASE_URL="${AZN_BASE_URL:-http://127.0.0.1:8080}"
CLIENT_ID="${SERVICE_CLIENT_ID:-cloudbank-service-client}"
CLIENT_SECRET="${SERVICE_CLIENT_SECRET:?Set SERVICE_CLIENT_SECRET}"
SUMMARY_ENDPOINT="$BASE_URL/internal/api/v1/ai/document-evidence-summaries"
POLICY_ENDPOINT="$BASE_URL/internal/api/v1/ai/policy-evidence-summaries"
ASSISTANCE_ENDPOINT="$BASE_URL/internal/api/v1/ai/manual-review-assistances"
SUMMARY_REQUEST='{"applicationId":"APP-SMOKE-AI","workflowId":"WF-SMOKE-AI","taskReference":"ai_document_evidence_summary","traceId":"0123456789abcdef0123456789abcdef","reviewId":"DREV-00000000000000000000000000000000","audience":"UNDERWRITER"}'

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

anonymous_status="$(curl --silent --output /dev/null --write-out '%{http_code}' --request POST \
    --header 'Content-Type: application/json' --header 'Idempotency-Key: ai-summary:APP-SMOKE-AI:WF-SMOKE-AI' \
    --data "$SUMMARY_REQUEST" "$SUMMARY_ENDPOINT")"
[[ "$anonymous_status" == "401" ]] || { printf 'FAIL: anonymous request returned HTTP %s.\n' "$anonymous_status" >&2; exit 1; }

summary_output="$(mktemp)"
trap 'rm -f -- "$summary_output"' EXIT
summary_status="$(curl --silent --show-error --output "$summary_output" --write-out '%{http_code}' --request POST \
    --header "Authorization: Bearer $token" --header 'Content-Type: application/json' \
    --header 'Idempotency-Key: ai-summary:APP-SMOKE-AI:WF-SMOKE-AI' \
    --header 'X-Trace-Id: 0123456789abcdef0123456789abcdef' --data "$SUMMARY_REQUEST" "$SUMMARY_ENDPOINT")"
[[ "$summary_status" == 404 ]] || {
    printf 'FAIL: missing document-summary evidence returned HTTP %s.\n' "$summary_status" >&2
    exit 1
}
grep -q '"code"[[:space:]]*:[[:space:]]*"DOCUMENT_REVIEW_NOT_FOUND"' "$summary_output" || {
    printf 'FAIL: document summary did not retrieve its own review evidence.\n' >&2
    exit 1
}
# No summary reference exists when evidence is unavailable. Downstream support
# still works with an explicitly empty reference, as in the workflow fallback.
summary_id=""

policy_request="$(printf '{"applicationId":"APP-SMOKE-AI","workflowId":"WF-SMOKE-AI","taskReference":"ai_policy_evidence_support","traceId":"0123456789abcdef0123456789abcdef","reviewId":"DREV-00000000000000000000000000000000","documentSummaryId":"%s","audience":"UNDERWRITER","policyEvidence":[{"policyDocumentId":"POLICY-DOC-001","policyCode":"CB-PL-001","policyVersion":"2026.0","chunkId":"CHUNK-INCOME-1","sectionRef":"SEC-INCOME","heading":"Verified income","content":"Use verified income evidence for affordability checks.","vectorScore":0.93}]}' "$summary_id")"
policy_response="$(curl --silent --show-error --fail --request POST \
    --header "Authorization: Bearer $token" --header 'Content-Type: application/json' \
    --header 'Idempotency-Key: ai-policy:APP-SMOKE-AI:WF-SMOKE-AI' \
    --header 'X-Trace-Id: 0123456789abcdef0123456789abcdef' \
    --data "$policy_request" "$POLICY_ENDPOINT")"
printf '%s' "$policy_response" | grep -q '"status"[[:space:]]*:[[:space:]]*"COMPLETED"' || {
    printf 'FAIL: policy-evidence support was not completed.\n' >&2
    exit 1
}
printf '%s' "$policy_response" | grep -q '"policySupportId"[[:space:]]*:[[:space:]]*"AIPOL-' || {
    printf 'FAIL: policy-evidence support did not contain a support ID.\n' >&2
    exit 1
}
printf '%s' "$policy_response" | grep -q '"evidenceStatus"[[:space:]]*:[[:space:]]*"GROUNDED"' || {
    printf 'FAIL: policy-evidence support was not grounded in the supplied citation.\n' >&2
    exit 1
}

assistance_request="$(printf '{"applicationId":"APP-SMOKE-AI","workflowId":"WF-SMOKE-AI","taskReference":"ai_manual_review_assistant","traceId":"0123456789abcdef0123456789abcdef","reviewId":"DREV-00000000000000000000000000000000","documentSummaryId":"%s","audience":"UNDERWRITER"}' "$summary_id")"
assistance_output="$summary_output"
assistance_status="$(curl --silent --show-error --output "$assistance_output" --write-out '%{http_code}' --request POST \
    --header "Authorization: Bearer $token" --header 'Content-Type: application/json' \
    --header 'Idempotency-Key: ai-manual-review:APP-SMOKE-AI:WF-SMOKE-AI' \
    --header 'X-Trace-Id: 0123456789abcdef0123456789abcdef' \
    --data "$assistance_request" "$ASSISTANCE_ENDPOINT")"
[[ "$assistance_status" == 404 ]] || {
    printf 'FAIL: missing document-review evidence returned HTTP %s.\n' "$assistance_status" >&2
    exit 1
}
grep -q '"code"[[:space:]]*:[[:space:]]*"DOCUMENT_REVIEW_NOT_FOUND"' "$assistance_output" || {
    printf 'FAIL: manual-review assistance did not retrieve its document-review evidence.\n' >&2
    exit 1
}
token=""
policy_response=""
printf 'PASS: ai-agent-service returned protected policy support and used its own downstream identity for document-summary and manual-review evidence.\n'
