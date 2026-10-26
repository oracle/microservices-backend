#!/usr/bin/env bash

# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at
# https://oss.oracle.com/licenses/upl.

set -uo pipefail

readonly DEFAULT_INGEST_BASE_URL="http://127.0.0.1:8082"
readonly DEFAULT_AZN_BASE_URL="http://127.0.0.1:8080"
readonly DEFAULT_SERVICE_CLIENT_ID="cloudbank-service-client"
readonly SERVICE_SCOPE="cloudbank.internal"
readonly JSON_EXCERPT_LENGTH=1200
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PACKET_DIR="$SCRIPT_DIR/../../synthetic_data/customer_packets/app_apr_001_elena_parker"
readonly LOAN_APPLICATION_PDF="$PACKET_DIR/loan_application.pdf"
readonly PAY_STATEMENT_PDF="$PACKET_DIR/pay_statement_novereign_systems.pdf"
readonly LIABILITY_SCHEDULE_PDF="$PACKET_DIR/liability_schedule.pdf"

PASS_COUNT=0
FAIL_COUNT=0
RESPONSE_BODY=""
RESPONSE_STATUS=""
ACCESS_TOKEN=""
JWT_PAYLOAD=""
NON_INTERACTIVE=false
INGEST_BASE_URL="${INGEST_BASE_URL-}"
AZN_BASE_URL="${AZN_BASE_URL-}"
SERVICE_CLIENT_ID="${SERVICE_CLIENT_ID-}"
SERVICE_CLIENT_SECRET="${SERVICE_CLIENT_SECRET-}"
FIRST_EXTRACTION_RESPONSE=""
SHOW_JSON=false

usage() {
    printf 'Usage: %s [--show-json] [--non-interactive]\n' "${0##*/}"
    printf 'Runs an authenticated PDF-to-JSON smoke test against document-ingest.\n'
    printf '  --show-json  Display the complete extraction response after the preview.\n'
    printf '  --non-interactive  Read credentials and optional overrides from the environment.\n'
}

die() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 2
}

cleanup() {
    SERVICE_CLIENT_SECRET=""
    ACCESS_TOKEN=""
    JWT_PAYLOAD=""
    RESPONSE_BODY=""
    FIRST_EXTRACTION_RESPONSE=""
    unset SERVICE_CLIENT_SECRET ACCESS_TOKEN JWT_PAYLOAD
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

pass() {
    PASS_COUNT=$((PASS_COUNT + 1))
    printf 'PASS: %s\n' "$1"
}

fail() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    printf 'FAIL: %s\n' "$1" >&2
}

finish_now() {
    fail "$1"
    if [[ -n "$RESPONSE_STATUS" ]]; then
        printf 'HTTP status: %s\n' "$RESPONSE_STATUS" >&2
    fi
    if [[ -n "$RESPONSE_BODY" ]]; then
        printf 'Response body: %.2000s\n' "$RESPONSE_BODY" >&2
    fi
    printf '\nSummary: %d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT"
    exit 1
}

body_contains() {
    local pattern="$1"
    printf '%s' "$RESPONSE_BODY" | grep -Eq -- "$pattern"
}

curl_config_escape() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '%s' "$value"
}

capture_response() {
    local output="$1"
    RESPONSE_STATUS="${output##*$'\n'}"
    RESPONSE_BODY="${output%$'\n'*}"
}

perform_request() {
    local output

    RESPONSE_BODY=""
    RESPONSE_STATUS=""
    if ! output="$(curl --silent --show-error \
            --connect-timeout 5 \
            --max-time 30 \
            --write-out $'\n%{http_code}' \
            "$@")"; then
        return 1
    fi
    capture_response "$output"
}

perform_bearer_request() {
    local token="$1"
    local escaped_token
    local output
    shift

    escaped_token="$(curl_config_escape "$token")"
    RESPONSE_BODY=""
    RESPONSE_STATUS=""
    if ! output="$(
        printf 'header = "Authorization: Bearer %s"\n' "$escaped_token" |
            curl --silent --show-error \
                --connect-timeout 5 \
                --max-time 30 \
                --config - \
                --write-out $'\n%{http_code}' \
                "$@"
    )"; then
        return 1
    fi
    capture_response "$output"
}

perform_token_request() {
    local client_id="$1"
    local client_secret="$2"
    local escaped_credentials
    local output

    escaped_credentials="$(curl_config_escape "$client_id:$client_secret")"
    RESPONSE_BODY=""
    RESPONSE_STATUS=""
    if ! output="$(
        printf 'user = "%s"\n' "$escaped_credentials" |
            curl --silent --show-error \
                --connect-timeout 5 \
                --max-time 20 \
                --config - \
                --request POST \
                --header 'Content-Type: application/x-www-form-urlencoded' \
                --data-urlencode 'grant_type=client_credentials' \
                --data-urlencode "scope=$SERVICE_SCOPE" \
                --write-out $'\n%{http_code}' \
                "$AZN_BASE_URL/oauth2/token"
    )"; then
        return 1
    fi
    capture_response "$output"
}

perform_extraction() {
    perform_bearer_request "$ACCESS_TOKEN" \
        --request POST \
        --form "files=@$LOAN_APPLICATION_PDF;type=application/pdf" \
        --form "files=@$PAY_STATEMENT_PDF;type=application/pdf" \
        --form "files=@$LIABILITY_SCHEDULE_PDF;type=application/pdf" \
        "$INGEST_BASE_URL/internal/api/v1/diagnostic-extractions/file-batches"
}

decode_jwt_payload() {
    local encoded_payload="$1"
    local remainder

    encoded_payload="${encoded_payload//-/+}"
    encoded_payload="${encoded_payload//_/\/}"
    remainder=$((${#encoded_payload} % 4))
    if [[ "$remainder" -eq 2 ]]; then
        encoded_payload="${encoded_payload}=="
    elif [[ "$remainder" -eq 3 ]]; then
        encoded_payload="${encoded_payload}="
    elif [[ "$remainder" -eq 1 ]]; then
        return 1
    fi
    printf '%s' "$encoded_payload" | openssl base64 -d -A 2>/dev/null
}

json_string() {
    local body="$1"
    local field="$2"

    printf '%s' "$body" |
        grep -Eo '"'"$field"'"[[:space:]]*:[[:space:]]*"[^"]*"' |
        head -n 1 |
        sed 's/^[^:]*:[[:space:]]*"//; s/"$//'
}

json_number() {
    local body="$1"
    local field="$2"

    printf '%s' "$body" |
        grep -Eo '"'"$field"'"[[:space:]]*:[[:space:]]*-?[0-9]+([.][0-9]+)?' |
        head -n 1 |
        sed 's/^[^:]*:[[:space:]]*//'
}

document_type_for_file() {
    local body="$1"
    local file_name="$2"

    printf '%s' "$body" | tr '{}' '\n\n' |
        awk -F '"' -v file_name="$file_name" '
            index($0, "\"fileName\":\"" file_name "\"") {
                for (field = 1; field <= NF; field++) {
                    if ($field == "documentType") {
                        print $(field + 2)
                        exit
                    }
                }
            }
        '
}

prompt_with_default() {
    local variable_name="$1"
    local label="$2"
    local default_value="$3"
    local entered_value

    IFS= read -r -p "$label [$default_value]: " entered_value
    if [[ -z "$entered_value" ]]; then
        entered_value="$default_value"
    fi
    printf -v "$variable_name" '%s' "$entered_value"
}

prompt_secret() {
    local variable_name="$1"
    local label="$2"
    local entered_value

    IFS= read -r -s -p "$label: " entered_value
    printf '\n'
    [[ -n "$entered_value" ]] || die "$label must not be empty"
    printf -v "$variable_name" '%s' "$entered_value"
}

validate_url() {
    local label="$1"
    local value="$2"
    case "$value" in
        http://* | https://*) ;;
        *) die "$label must start with http:// or https://" ;;
    esac
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h | --help) usage; exit 0 ;;
        --show-json) SHOW_JSON=true ;;
        --non-interactive) NON_INTERACTIVE=true ;;
        *) usage >&2; exit 2 ;;
    esac
    shift
done

for command in curl grep sed openssl awk tr; do
    command -v "$command" >/dev/null 2>&1 || die "$command is required"
done
for fixture in "$LOAN_APPLICATION_PDF" "$PAY_STATEMENT_PDF" "$LIABILITY_SCHEDULE_PDF"; do
    [[ -r "$fixture" ]] || die "Synthetic PDF fixture is missing: $fixture"
done
if [[ "$NON_INTERACTIVE" == "true" ]]; then
    INGEST_BASE_URL="${INGEST_BASE_URL:-$DEFAULT_INGEST_BASE_URL}"
    AZN_BASE_URL="${AZN_BASE_URL:-$DEFAULT_AZN_BASE_URL}"
    SERVICE_CLIENT_ID="${SERVICE_CLIENT_ID:-$DEFAULT_SERVICE_CLIENT_ID}"
    [[ -n "$SERVICE_CLIENT_SECRET" ]] || die "SERVICE_CLIENT_SECRET is required in non-interactive mode"
else
    [[ -t 0 ]] || die "interactive input is required for credential prompts"
    prompt_with_default INGEST_BASE_URL "document-ingest base URL" "$DEFAULT_INGEST_BASE_URL"
    prompt_with_default AZN_BASE_URL "azn-server base URL" "$DEFAULT_AZN_BASE_URL"

    printf '\nInternal service OAuth client\n'
    prompt_with_default SERVICE_CLIENT_ID "Service OAuth client ID" "$DEFAULT_SERVICE_CLIENT_ID"
    prompt_secret SERVICE_CLIENT_SECRET "Service OAuth client secret"
fi

INGEST_BASE_URL="${INGEST_BASE_URL%/}"
AZN_BASE_URL="${AZN_BASE_URL%/}"
validate_url "document-ingest base URL" "$INGEST_BASE_URL"
validate_url "azn-server base URL" "$AZN_BASE_URL"

printf '\nTesting document-ingest at %s\n\n' "$INGEST_BASE_URL"

if perform_request "$INGEST_BASE_URL/actuator/health" &&
        [[ "$RESPONSE_STATUS" == "200" ]] &&
        body_contains '"status"[[:space:]]*:[[:space:]]*"UP"'; then
    pass "Actuator health"
else
    finish_now "Actuator health"
fi

if perform_request \
        --request POST \
        --form "files=@$LOAN_APPLICATION_PDF;type=application/pdf" \
        "$INGEST_BASE_URL/internal/api/v1/diagnostic-extractions/file-batches" &&
        [[ "$RESPONSE_STATUS" == "401" ]]; then
    pass "Extraction rejects anonymous access"
else
    finish_now "Extraction did not reject anonymous access"
fi

printf '\nAuthenticating through azn-server\n'
if ! perform_token_request "$SERVICE_CLIENT_ID" "$SERVICE_CLIENT_SECRET"; then
    finish_now "Client-credentials token request failed"
fi
[[ "$RESPONSE_STATUS" == "200" ]] || finish_now "Client-credentials token request was rejected"
ACCESS_TOKEN="$(json_string "$RESPONSE_BODY" access_token)"
[[ -n "$ACCESS_TOKEN" && "$ACCESS_TOKEN" == *.*.* ]] ||
    finish_now "azn-server returned no JWT access token"
if ! JWT_PAYLOAD="$(decode_jwt_payload "$(printf '%s' "$ACCESS_TOKEN" | cut -d. -f2)")"; then
    finish_now "Service access token payload could not be decoded"
fi
printf '%s' "$JWT_PAYLOAD" | grep -Eq '"aud"[^]]*"cloudbank-api"' ||
    finish_now "Service token did not contain the CloudBank audience"
printf '%s' "$JWT_PAYLOAD" | grep -Eq '"scope"[^}]*cloudbank.internal' ||
    finish_now "Service token did not contain cloudbank.internal"
printf '%s' "$JWT_PAYLOAD" | grep -Eq '"token_kind"[[:space:]]*:[[:space:]]*"service"' ||
    finish_now "Service token did not have token_kind=service"
[[ "$(json_string "$JWT_PAYLOAD" client_id)" == "$SERVICE_CLIENT_ID" ]] ||
    finish_now "Service token client_id did not match the requested client"
JWT_PAYLOAD=""
SERVICE_CLIENT_SECRET=""
pass "azn-server issued a valid internal service token"

printf '\nConverting three synthetic PDFs to structured JSON\n'
if ! perform_extraction; then
    finish_now "Multipart extraction request failed"
fi
[[ "$RESPONSE_STATUS" == "200" ]] || finish_now "Multipart extraction did not return HTTP 200"
FIRST_EXTRACTION_RESPONSE="$RESPONSE_BODY"

body_contains '"service"[[:space:]]*:[[:space:]]*"cloudbank-document-ingest"' ||
    finish_now "Extraction response contained the wrong service"
body_contains '"provider"[[:space:]]*:[[:space:]]*"local_pdf_text"' ||
    finish_now "Extraction response contained the wrong provider"
body_contains '"packetCount"[[:space:]]*:[[:space:]]*1' ||
    finish_now "Extraction response did not contain one packet"
if body_contains '"applicationId"[[:space:]]*:[[:space:]]*"APP-'; then
    finish_now "Diagnostic extraction must not infer the runtime application ID from PDF text"
fi
body_contains '"name"[[:space:]]*:[[:space:]]*"Elena Parker"' ||
    finish_now "Applicant name was not extracted"
body_contains '"employer"[[:space:]]*:[[:space:]]*"Novereign Systems Cooperative"' ||
    finish_now "Employer was not extracted"
body_contains '"requestedAmount"[[:space:]]*:[[:space:]]*16000([.]0)?' ||
    finish_now "Requested amount was not extracted"

LOAN_TYPE="$(document_type_for_file "$FIRST_EXTRACTION_RESPONSE" loan_application.pdf)"
PAY_TYPE="$(document_type_for_file "$FIRST_EXTRACTION_RESPONSE" pay_statement_novereign_systems.pdf)"
LIABILITY_TYPE="$(document_type_for_file "$FIRST_EXTRACTION_RESPONSE" liability_schedule.pdf)"
[[ "$LOAN_TYPE" == "loan_application" ]] || finish_now "Loan application PDF classification was incorrect"
[[ "$PAY_TYPE" == "pay_statement" ]] || finish_now "Pay statement PDF classification was incorrect"
[[ "$LIABILITY_TYPE" == "liability_schedule" ]] ||
    finish_now "Liability schedule PDF classification was incorrect"
DOCUMENT_COUNT="$(printf '%s' "$FIRST_EXTRACTION_RESPONSE" | grep -o '"fileName"' | wc -l | tr -d '[:space:]')"
[[ "$DOCUMENT_COUNT" == "3" ]] || finish_now "Extraction response did not contain exactly three documents"
pass "Three synthetic PDFs were converted to structured JSON"

if ! perform_extraction; then
    finish_now "Deterministic extraction replay failed"
fi
[[ "$RESPONSE_STATUS" == "200" ]] || finish_now "Extraction replay did not return HTTP 200"
[[ "$RESPONSE_BODY" == "$FIRST_EXTRACTION_RESPONSE" ]] ||
    finish_now "Extraction replay produced different JSON"
pass "Extraction output is deterministic"

APPLICANT_NAME="$(json_string "$FIRST_EXTRACTION_RESPONSE" name)"
EMPLOYER="$(json_string "$FIRST_EXTRACTION_RESPONSE" employer)"
REQUESTED_AMOUNT="$(json_number "$FIRST_EXTRACTION_RESPONSE" requestedAmount)"

printf '\nConversion summary (values parsed from the response)\n'
printf '  Application association: supplied by workflow intake, not PDF text\n'
printf '  Applicant:   %s\n' "$APPLICANT_NAME"
printf '  Employer:    %s\n' "$EMPLOYER"
printf '  Amount:      %s\n' "$REQUESTED_AMOUNT"
printf '  Documents:\n'
printf '    - loan_application.pdf -> %s\n' "$LOAN_TYPE"
printf '    - pay_statement_novereign_systems.pdf -> %s\n' "$PAY_TYPE"
printf '    - liability_schedule.pdf -> %s\n' "$LIABILITY_TYPE"

printf '\nActual JSON response excerpt\n'
printf '%.*s\n' "$JSON_EXCERPT_LENGTH" "$FIRST_EXTRACTION_RESPONSE"
if [[ ${#FIRST_EXTRACTION_RESPONSE} -gt $JSON_EXCERPT_LENGTH ]]; then
    printf '[truncated; run with --show-json to display the complete response]\n'
fi

if [[ "$SHOW_JSON" == "true" ]]; then
    printf '\nComplete JSON response\n'
    if command -v jq >/dev/null 2>&1; then
        printf '%s\n' "$FIRST_EXTRACTION_RESPONSE" | jq .
    else
        printf '%s\n' "$FIRST_EXTRACTION_RESPONSE"
    fi
fi

RESPONSE_BODY=""
FIRST_EXTRACTION_RESPONSE=""
ACCESS_TOKEN=""
printf '\nSummary: %d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[[ "$FAIL_COUNT" -eq 0 ]]
