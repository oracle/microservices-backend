#!/usr/bin/env bash

# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at
# https://oss.oracle.com/licenses/upl.

set -uo pipefail

readonly DEFAULT_LOAN_BASE_URL="http://127.0.0.1:8081"
readonly DEFAULT_AZN_BASE_URL="http://127.0.0.1:8080"
readonly DEFAULT_USERNAME="obaas-user"
readonly DEFAULT_BROWSER_CLIENT_ID="cloudbank-client"
readonly DEFAULT_SERVICE_CLIENT_ID="cloudbank-service-client"
readonly DEFAULT_SERVICE_SCOPE="cloudbank.internal"
readonly DEFAULT_WORKFLOW_MODE="deferred"
readonly DEFAULT_WORKFLOW_TIMEOUT="30"
readonly DEFAULT_EXPECTED_WORKFLOW_NAME="cloudbank-loan-origination"
readonly EXPECTED_WORKFLOW_VERSION="1"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly CLOUDBANK_ENV_FILE="${CLOUDBANK_ENV_FILE:-$REPOSITORY_ROOT/.env}"
readonly DEFAULT_APPLICATION_JSON_FILE="$REPOSITORY_ROOT/synthetic_data/customer_packets/demo_geocoded_loan/application.json"

PASS_COUNT=0
FAIL_COUNT=0
RESPONSE_BODY=""
RESPONSE_STATUS=""
RESPONSE_LOCATION=""
NON_INTERACTIVE=false
MANUAL_REVIEW_PATH=false
LOAN_BASE_URL="${LOAN_BASE_URL-}"
AZN_BASE_URL="${AZN_BASE_URL-}"
USERNAME="${USERNAME-}"
USER_PASSWORD="${USER_PASSWORD-}"
BROWSER_CLIENT_ID="${BROWSER_CLIENT_ID-}"
BROWSER_CLIENT_SECRET="${BROWSER_CLIENT_SECRET-}"
REDIRECT_URI="${REDIRECT_URI-}"
SERVICE_CLIENT_ID="${SERVICE_CLIENT_ID-}"
SERVICE_CLIENT_SECRET="${SERVICE_CLIENT_SECRET-}"
WORKFLOW_MODE="${WORKFLOW_MODE-}"
WORKFLOW_TIMEOUT="${WORKFLOW_TIMEOUT-}"
EXPECTED_WORKFLOW_NAME="${EXPECTED_WORKFLOW_NAME-}"
LOAN_SMOKE_ADDRESS_JSON_FILE="${LOAN_SMOKE_ADDRESS_JSON_FILE-}"
LOAN_SMOKE_APPLICATION_JSON_FILE="${LOAN_SMOKE_APPLICATION_JSON_FILE:-$DEFAULT_APPLICATION_JSON_FILE}"
LOAN_SMOKE_STOP_AFTER_DISPATCH="${LOAN_SMOKE_STOP_AFTER_DISPATCH-false}"
LOAN_SMOKE_VERIFY_GEO="${LOAN_SMOKE_VERIFY_GEO-false}"
LOAN_SMOKE_GEO_WAIT_SECONDS="${LOAN_SMOKE_GEO_WAIT_SECONDS-180}"
GEO_BASE_URL="${GEO_BASE_URL-}"
USER_ACCESS_TOKEN=""
SERVICE_ACCESS_TOKEN=""
PKCE_VERIFIER=""
AUTHORIZATION_CODE=""
JWT_PAYLOAD=""
TEMP_DIR=""
LOAN_APPLICATION_PDF=""
PAY_STATEMENT_PDF=""

usage() {
    printf 'Usage: %s [--non-interactive] [--manual-review] [--application-file FILE]\n' "${0##*/}"
    printf 'Runs an authenticated smoke test against loan-application-service.\n'
    printf 'Workflow modes: deferred (no backend), fake, or microtx.\n'
    printf 'Expected workflow defaults to cloudbank-loan-origination version 1.\n'
    printf '  --non-interactive  Read the three required secrets from the root .env; explicit environment overrides win.\n'
    printf '  --manual-review    Use the packet manual-review/loan_application.pdf employer-conflict fixture.\n'
    printf '  --application-file FILE  Intake template with two ready PDFs in the same directory.\n'
}

die() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 2
}

read_local_env_value() {
    local name="$1"

    [[ -r "$CLOUDBANK_ENV_FILE" ]] || return 1
    awk -v name="$name" '
        index($0, name "=") == 1 { value = substr($0, length(name) + 2) }
        END {
            if (value == "") exit 1
            print value
        }
    ' "$CLOUDBANK_ENV_FILE"
}

cleanup() {
    USER_PASSWORD=""
    BROWSER_CLIENT_SECRET=""
    SERVICE_CLIENT_SECRET=""
    USER_ACCESS_TOKEN=""
    SERVICE_ACCESS_TOKEN=""
    PKCE_VERIFIER=""
    AUTHORIZATION_CODE=""
    JWT_PAYLOAD=""
    RESPONSE_BODY=""
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf -- "$TEMP_DIR"
    fi
    unset USER_PASSWORD BROWSER_CLIENT_SECRET SERVICE_CLIENT_SECRET
    unset USER_ACCESS_TOKEN SERVICE_ACCESS_TOKEN PKCE_VERIFIER AUTHORIZATION_CODE JWT_PAYLOAD
}

source "$SCRIPT_DIR/lib/demo-intake.sh"

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
    printf '\nSummary: %d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT"
    exit 1
}

finish_api_now() {
    local message="$1"

    fail "$message"
    printf 'HTTP status: %s\n' "${RESPONSE_STATUS:-unavailable}" >&2
    if [[ -n "$RESPONSE_BODY" && -z "$LOAN_SMOKE_ADDRESS_JSON_FILE" ]]; then
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
    RESPONSE_LOCATION="$(printf '%s\n' "$RESPONSE_BODY" |
        sed -n 's/^[Ll]ocation:[[:space:]]*//p' | tr -d '\r' | tail -n 1)"
}

perform_request() {
    local output

    RESPONSE_BODY=""
    RESPONSE_STATUS=""
    RESPONSE_LOCATION=""
    if ! output="$(curl --silent --show-error \
            --connect-timeout 5 \
            --max-time 20 \
            --dump-header - \
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
    RESPONSE_LOCATION=""
    if ! output="$(
        printf 'header = "Authorization: Bearer %s"\n' "$escaped_token" |
            curl --silent --show-error \
                --connect-timeout 5 \
                --max-time 20 \
                --config - \
                --dump-header - \
                --write-out $'\n%{http_code}' \
                "$@"
    )"; then
        return 1
    fi
    capture_response "$output"
}

perform_basic_token_request() {
    local client_id="$1"
    local client_secret="$2"
    local token_url="$3"
    local scope="$4"
    local escaped_user
    local output

    escaped_user="$(curl_config_escape "$client_id:$client_secret")"
    RESPONSE_BODY=""
    RESPONSE_STATUS=""
    RESPONSE_LOCATION=""
    if ! output="$(
        printf 'user = "%s"\n' "$escaped_user" |
            curl --silent --show-error \
                --connect-timeout 5 \
                --max-time 20 \
                --config - \
                --request POST \
                --header 'Content-Type: application/x-www-form-urlencoded' \
                --data-urlencode 'grant_type=client_credentials' \
                --data-urlencode "scope=$scope" \
                --dump-header - \
                --write-out $'\n%{http_code}' \
                "$token_url"
    )"; then
        return 1
    fi
    capture_response "$output"
}

perform_login() {
    local login_url="$1"
    local csrf_token="$2"
    local cookie_file="$3"
    local escaped_username
    local escaped_password
    local escaped_csrf
    local output

    escaped_username="$(curl_config_escape "$USERNAME")"
    escaped_password="$(curl_config_escape "$USER_PASSWORD")"
    escaped_csrf="$(curl_config_escape "$csrf_token")"
    RESPONSE_BODY=""
    RESPONSE_STATUS=""
    RESPONSE_LOCATION=""
    if ! output="$(
        printf 'data-urlencode = "username=%s"\n' "$escaped_username"
        printf 'data-urlencode = "password=%s"\n' "$escaped_password"
        printf 'data-urlencode = "_csrf=%s"\n' "$escaped_csrf"
    )"; then
        return 1
    fi
    if ! output="$(printf '%s\n' "$output" |
            curl --silent --show-error \
                --connect-timeout 5 \
                --max-time 20 \
                --config - \
                --request POST \
                --header 'Content-Type: application/x-www-form-urlencoded' \
                --cookie "$cookie_file" \
                --cookie-jar "$cookie_file" \
                --dump-header - \
                --write-out $'\n%{http_code}' \
                "$login_url")"; then
        return 1
    fi
    capture_response "$output"
}

absolute_url() {
    local location="$1"
    case "$location" in
        http://* | https://*) printf '%s' "$location" ;;
        /*) printf '%s%s' "$AZN_BASE_URL" "$location" ;;
        *) printf '%s/%s' "$AZN_BASE_URL" "$location" ;;
    esac
}

decode_jwt_payload() {
    local token="$1"
    local encoded_payload
    local remainder

    encoded_payload="$(printf '%s' "$token" | cut -d. -f2)"
    [[ -n "$encoded_payload" ]] || return 1
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

extract_json_string() {
    local field="$1"
    printf '%s' "$RESPONSE_BODY" |
        sed -n "s/.*\"$field\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" |
        head -n 1
}

extract_document_id_for_file() {
    local file_name="$1"

    printf '%s' "$RESPONSE_BODY" | tr '{}' '\n\n' |
        awk -F '"' -v file_name="$file_name" '
            index($0, "\"fileName\":\"" file_name "\"") {
                for (field = 1; field <= NF; field++) {
                    if ($field == "documentId") {
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

obtain_user_token() {
    local cookie_file="$TEMP_DIR/cookies"
    local csrf_token
    local next_url
    local token_response
    local escaped_client
    local escaped_code
    local escaped_redirect
    local escaped_verifier
    local redirect_count=0

    : >"$cookie_file"
    chmod 600 "$cookie_file"
    PKCE_VERIFIER="$(openssl rand -base64 48 | tr '+/' '-_' | tr -d '=\n')"
    local pkce_challenge
    pkce_challenge="$(printf '%s' "$PKCE_VERIFIER" |
        openssl dgst -sha256 -binary | openssl base64 -A | tr '+/' '-_' | tr -d '=')"

    if ! perform_request --get \
            --cookie "$cookie_file" --cookie-jar "$cookie_file" \
            --data-urlencode 'response_type=code' \
            --data-urlencode "client_id=$BROWSER_CLIENT_ID" \
            --data-urlencode "redirect_uri=$REDIRECT_URI" \
            --data-urlencode 'scope=openid cloudbank.read cloudbank.write' \
            --data-urlencode "code_challenge=$pkce_challenge" \
            --data-urlencode 'code_challenge_method=S256' \
            "$AZN_BASE_URL/oauth2/authorize"; then
        finish_now "Authorization request failed"
    fi
    [[ "$RESPONSE_STATUS" == "302" && -n "$RESPONSE_LOCATION" ]] ||
        finish_now "Authorization server did not redirect to login"

    next_url="$(absolute_url "$RESPONSE_LOCATION")"
    if ! perform_request --cookie "$cookie_file" --cookie-jar "$cookie_file" "$next_url"; then
        finish_now "Login page request failed"
    fi
    [[ "$RESPONSE_STATUS" == "200" ]] || finish_now "Authorization login page was unavailable"
    csrf_token="$(printf '%s' "$RESPONSE_BODY" |
        sed -n 's/.*name="_csrf"[^>]*value="\([^"]*\)".*/\1/p' | head -n 1)"
    [[ -n "$csrf_token" ]] || finish_now "Authorization login page did not contain a CSRF token"

    if ! perform_login "$AZN_BASE_URL/login" "$csrf_token" "$cookie_file"; then
        finish_now "Authorization login request failed"
    fi
    [[ "$RESPONSE_STATUS" == "302" && -n "$RESPONSE_LOCATION" ]] ||
        finish_now "Authorization login was rejected"
    next_url="$(absolute_url "$RESPONSE_LOCATION")"

    while [[ "$next_url" != "$REDIRECT_URI"* && "$redirect_count" -lt 6 ]]; do
        if ! perform_request --cookie "$cookie_file" --cookie-jar "$cookie_file" "$next_url"; then
            finish_now "Authorization redirect failed"
        fi
        [[ "$RESPONSE_STATUS" == "302" && -n "$RESPONSE_LOCATION" ]] ||
            finish_now "Authorization server did not return an authorization code"
        next_url="$(absolute_url "$RESPONSE_LOCATION")"
        redirect_count=$((redirect_count + 1))
    done
    [[ "$next_url" == "$REDIRECT_URI"* ]] || finish_now "Authorization redirect URI did not match"
    AUTHORIZATION_CODE="${next_url#*code=}"
    AUTHORIZATION_CODE="${AUTHORIZATION_CODE%%&*}"
    [[ -n "$AUTHORIZATION_CODE" && "$AUTHORIZATION_CODE" != "$next_url" ]] ||
        finish_now "Authorization response did not contain a code"

    escaped_client="$(curl_config_escape "$BROWSER_CLIENT_ID:$BROWSER_CLIENT_SECRET")"
    escaped_code="$(curl_config_escape "$AUTHORIZATION_CODE")"
    escaped_redirect="$(curl_config_escape "$REDIRECT_URI")"
    escaped_verifier="$(curl_config_escape "$PKCE_VERIFIER")"
    if ! token_response="$(
        {
            printf 'user = "%s"\n' "$escaped_client"
            printf 'data-urlencode = "grant_type=authorization_code"\n'
            printf 'data-urlencode = "code=%s"\n' "$escaped_code"
            printf 'data-urlencode = "redirect_uri=%s"\n' "$escaped_redirect"
            printf 'data-urlencode = "code_verifier=%s"\n' "$escaped_verifier"
        } |
            curl --silent --show-error \
                --connect-timeout 5 \
                --max-time 20 \
                --config - \
                --request POST \
                --header 'Content-Type: application/x-www-form-urlencoded' \
                --write-out $'\n%{http_code}' \
                "$AZN_BASE_URL/oauth2/token"
    )"; then
        finish_now "Authorization-code token exchange failed"
    fi
    RESPONSE_STATUS="${token_response##*$'\n'}"
    RESPONSE_BODY="${token_response%$'\n'*}"
    [[ "$RESPONSE_STATUS" == "200" ]] || finish_now "Authorization-code token exchange was rejected"
    USER_ACCESS_TOKEN="$(extract_json_string access_token)"
    [[ -n "$USER_ACCESS_TOKEN" ]] || finish_now "Authorization server returned no user access token"

    USER_PASSWORD=""
    BROWSER_CLIENT_SECRET=""
    PKCE_VERIFIER=""
    AUTHORIZATION_CODE=""
    : >"$cookie_file"
}

validate_user_token() {
    if ! JWT_PAYLOAD="$(decode_jwt_payload "$USER_ACCESS_TOKEN")"; then
        finish_now "User access token was not a decodable JWT"
    fi
    printf '%s' "$JWT_PAYLOAD" | grep -Eq '"aud"[^]]*"cloudbank-api"' ||
        finish_now "User token did not contain the CloudBank audience"
    printf '%s' "$JWT_PAYLOAD" | grep -Eq '"scope"[^}]*cloudbank.read' ||
        finish_now "User token did not contain cloudbank.read"
    printf '%s' "$JWT_PAYLOAD" | grep -Eq '"scope"[^}]*cloudbank.write' ||
        finish_now "User token did not contain cloudbank.write"
    printf '%s' "$JWT_PAYLOAD" | grep -Eq '"roles"[^]]*"ROLE_(APPLICANT|LOAN_OFFICER|ADMIN)"' ||
        finish_now "User token did not contain an intake role"
    printf '%s' "$JWT_PAYLOAD" | grep -Eq '"cb_principal_id"[[:space:]]*:[[:space:]]*"[^"]+"' ||
        finish_now "User token did not contain cb_principal_id"
    printf '%s' "$JWT_PAYLOAD" | grep -Eq '"token_kind"[[:space:]]*:[[:space:]]*"user"' ||
        finish_now "User token was not a user token"
    JWT_PAYLOAD=""
    pass "azn-server issued a valid CloudBank user token"
}

obtain_service_token() {
    if ! perform_basic_token_request "$SERVICE_CLIENT_ID" "$SERVICE_CLIENT_SECRET" \
            "$AZN_BASE_URL/oauth2/token" "$DEFAULT_SERVICE_SCOPE"; then
        finish_now "Service-token request failed"
    fi
    [[ "$RESPONSE_STATUS" == "200" ]] || finish_now "Service-token request was rejected"
    SERVICE_ACCESS_TOKEN="$(extract_json_string access_token)"
    [[ -n "$SERVICE_ACCESS_TOKEN" ]] || finish_now "Authorization server returned no service access token"
    if ! JWT_PAYLOAD="$(decode_jwt_payload "$SERVICE_ACCESS_TOKEN")"; then
        finish_now "Service access token was not a decodable JWT"
    fi
    printf '%s' "$JWT_PAYLOAD" | grep -Eq '"scope"[^}]*cloudbank.internal' ||
        finish_now "Service token did not contain cloudbank.internal"
    printf '%s' "$JWT_PAYLOAD" | grep -Eq '"client_id"[[:space:]]*:[[:space:]]*"'"$SERVICE_CLIENT_ID"'"' ||
        finish_now "Service token client ID did not match"
    printf '%s' "$JWT_PAYLOAD" | grep -Eq '"token_kind"[[:space:]]*:[[:space:]]*"service"' ||
        finish_now "Service token was not a service token"
    SERVICE_CLIENT_SECRET=""
    JWT_PAYLOAD=""
    pass "azn-server issued a valid CloudBank service token"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h | --help) usage; exit 0 ;;
        --non-interactive) NON_INTERACTIVE=true ;;
        --manual-review) MANUAL_REVIEW_PATH=true ;;
        --application-file)
            [[ $# -ge 2 && -n "$2" && "$2" != -* ]] || die "--application-file requires a path"
            LOAN_SMOKE_APPLICATION_JSON_FILE="$2"
            shift
            ;;
        *) usage >&2; exit 2 ;;
    esac
    shift
done

for command_name in curl grep sed openssl cut tr mktemp tail head rm chmod date awk jq; do
    command -v "$command_name" >/dev/null 2>&1 || die "$command_name is required"
done
[[ -r "$LOAN_SMOKE_APPLICATION_JSON_FILE" ]] || die "application template is not readable"
validate_demo_application "$LOAN_SMOKE_APPLICATION_JSON_FILE" || die "invalid application template"
PACKET_DIR="$(cd "$(dirname "$LOAN_SMOKE_APPLICATION_JSON_FILE")" && pwd)"
LOAN_FILE_NAME="$(jq -r '.documents[] | select(.documentType == "LOAN_APPLICATION") | .fileName' "$LOAN_SMOKE_APPLICATION_JSON_FILE")"
PAY_FILE_NAME="$(jq -r '.documents[] | select(.documentType == "PAY_STATEMENT") | .fileName' "$LOAN_SMOKE_APPLICATION_JSON_FILE")"
LOAN_APPLICATION_PDF="$PACKET_DIR/$LOAN_FILE_NAME"
PAY_STATEMENT_PDF="$PACKET_DIR/$PAY_FILE_NAME"
if [[ "$MANUAL_REVIEW_PATH" == "true" ]]; then
    LOAN_APPLICATION_PDF="$PACKET_DIR/manual-review/$LOAN_FILE_NAME"
fi
[[ -s "$LOAN_APPLICATION_PDF" && -s "$PAY_STATEMENT_PDF" ]] || die "the application packet is missing a required PDF"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cloudbank-loan-smoke.XXXXXX")" ||
    die "unable to create a private temporary directory"
chmod 700 "$TEMP_DIR"

if [[ "$NON_INTERACTIVE" == "true" ]]; then
    LOAN_BASE_URL="${LOAN_BASE_URL:-$DEFAULT_LOAN_BASE_URL}"
    AZN_BASE_URL="${AZN_BASE_URL:-$DEFAULT_AZN_BASE_URL}"
    USERNAME="${USERNAME:-$DEFAULT_USERNAME}"
    BROWSER_CLIENT_ID="${BROWSER_CLIENT_ID:-$DEFAULT_BROWSER_CLIENT_ID}"
    SERVICE_CLIENT_ID="${SERVICE_CLIENT_ID:-$DEFAULT_SERVICE_CLIENT_ID}"
    WORKFLOW_MODE="${WORKFLOW_MODE:-$DEFAULT_WORKFLOW_MODE}"
    EXPECTED_WORKFLOW_NAME="${EXPECTED_WORKFLOW_NAME:-$DEFAULT_EXPECTED_WORKFLOW_NAME}"
    USER_PASSWORD="${USER_PASSWORD:-$(read_local_env_value AZN_BOOTSTRAP_USERS_USER_PASSWORD || true)}"
    BROWSER_CLIENT_SECRET="${BROWSER_CLIENT_SECRET:-$(read_local_env_value AZN_AUTHORIZATION_SERVER_DEFAULT_CLIENT_SECRET || true)}"
    SERVICE_CLIENT_SECRET="${SERVICE_CLIENT_SECRET:-$(read_local_env_value AZN_AUTHORIZATION_SERVER_SERVICE_CLIENT_SECRET || true)}"
    [[ -n "$USER_PASSWORD" ]] ||
        die "Set USER_PASSWORD or AZN_BOOTSTRAP_USERS_USER_PASSWORD in $CLOUDBANK_ENV_FILE"
    [[ -n "$BROWSER_CLIENT_SECRET" ]] ||
        die "Set BROWSER_CLIENT_SECRET or AZN_AUTHORIZATION_SERVER_DEFAULT_CLIENT_SECRET in $CLOUDBANK_ENV_FILE"
    [[ -n "$SERVICE_CLIENT_SECRET" ]] ||
        die "Set SERVICE_CLIENT_SECRET or AZN_AUTHORIZATION_SERVER_SERVICE_CLIENT_SECRET in $CLOUDBANK_ENV_FILE"
else
    [[ -t 0 ]] || die "interactive input is required for credential prompts"
    prompt_with_default LOAN_BASE_URL "loan-application-service base URL" "$DEFAULT_LOAN_BASE_URL"
    prompt_with_default AZN_BASE_URL "azn-server base URL" "$DEFAULT_AZN_BASE_URL"
fi

EXPECTED_WORKFLOW_NAME="${EXPECTED_WORKFLOW_NAME:-$DEFAULT_EXPECTED_WORKFLOW_NAME}"

LOAN_BASE_URL="${LOAN_BASE_URL%/}"
AZN_BASE_URL="${AZN_BASE_URL%/}"
case "$LOAN_BASE_URL $AZN_BASE_URL" in
    *://*' '*://*) ;;
    *) die "base URLs must start with http:// or https://" ;;
esac

printf '\nUser authorization-code + PKCE login\n'
if [[ "$NON_INTERACTIVE" == "true" ]]; then
    REDIRECT_URI="${REDIRECT_URI:-$AZN_BASE_URL/login/oauth2/code/$BROWSER_CLIENT_ID}"
else
    prompt_with_default USERNAME "Demo username" "$DEFAULT_USERNAME"
    prompt_secret USER_PASSWORD "Demo user password"
    prompt_with_default BROWSER_CLIENT_ID "Browser OAuth client ID" "$DEFAULT_BROWSER_CLIENT_ID"
    prompt_secret BROWSER_CLIENT_SECRET "Browser OAuth client secret"
    prompt_with_default REDIRECT_URI "Registered redirect URI" \
        "$AZN_BASE_URL/login/oauth2/code/$BROWSER_CLIENT_ID"
fi

printf '\nInternal service OAuth client\n'
if [[ "$NON_INTERACTIVE" != "true" ]]; then
    prompt_with_default SERVICE_CLIENT_ID "Service OAuth client ID" "$DEFAULT_SERVICE_CLIENT_ID"
    prompt_secret SERVICE_CLIENT_SECRET "Service OAuth client secret"
fi

printf '\nWorkflow verification\n'
printf '%s\n' \
    '  deferred - create a deferred workflow request; no workflow backend or polling timeout is needed.' \
    '  fake     - exercise the local fake workflow backend and wait for the workflow to start.' \
    '  microtx  - exercise a live MicroTx workflow and wait for the workflow to start.'
if [[ "$NON_INTERACTIVE" != "true" ]]; then
    prompt_with_default WORKFLOW_MODE "Workflow mode" "$DEFAULT_WORKFLOW_MODE"
fi
case "$WORKFLOW_MODE" in
    deferred)
        ;;
    fake | microtx)
        if [[ "$NON_INTERACTIVE" == "true" ]]; then
            WORKFLOW_TIMEOUT="${WORKFLOW_TIMEOUT:-$DEFAULT_WORKFLOW_TIMEOUT}"
        else
            prompt_with_default WORKFLOW_TIMEOUT "Workflow polling timeout in seconds" "$DEFAULT_WORKFLOW_TIMEOUT"
        fi
        [[ "$WORKFLOW_TIMEOUT" =~ ^[1-9][0-9]{0,2}$ ]] || die "workflow timeout must be 1-999 seconds"
        ;;
    *) die "workflow mode must be deferred, fake, or microtx" ;;
esac
if [[ "$LOAN_SMOKE_STOP_AFTER_DISPATCH" == "true" && "$WORKFLOW_MODE" == "deferred" ]]; then
    die "dispatch-only mode requires fake or microtx workflow mode"
fi
if [[ "$LOAN_SMOKE_VERIFY_GEO" == "true" && "$LOAN_SMOKE_STOP_AFTER_DISPATCH" != "true" ]]; then
    die "geographic verification requires dispatch-only mode"
fi

printf '\nAuthenticating through azn-server\n'
obtain_user_token
validate_user_token
obtain_service_token

printf '\nTesting loan-application-service at %s\n\n' "$LOAN_BASE_URL"

if perform_request "$LOAN_BASE_URL/actuator/health" &&
        [[ "$RESPONSE_STATUS" == "200" ]] && body_contains '"status"[[:space:]]*:[[:space:]]*"UP"'; then
    pass "Actuator health"
else
    finish_now "Actuator health"
fi

if perform_request "$LOAN_BASE_URL/api/v1/loan-applications" && [[ "$RESPONSE_STATUS" == "401" ]]; then
    pass "Applicant API rejects anonymous access"
else
    finish_now "Applicant API did not reject anonymous access"
fi

if perform_bearer_request "$SERVICE_ACCESS_TOKEN" "$LOAN_BASE_URL/api/v1/loan-applications" &&
        [[ "$RESPONSE_STATUS" == "403" ]]; then
    pass "Applicant API rejects service tokens"
else
    finish_now "Applicant API did not reject a service token"
fi

RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$-$(openssl rand -hex 4)"
if [[ "$MANUAL_REVIEW_PATH" == "true" ]]; then
    EXPECTED_REVIEW_DISPOSITION="MANUAL_REVIEW"
else
    EXPECTED_REVIEW_DISPOSITION="CLEAR"
fi
INTAKE_KEY="intake:$RUN_ID"
LOAN_UPLOAD_KEY="upload-loan:$RUN_ID"
PAY_UPLOAD_KEY="upload-pay:$RUN_ID"
EVENT_ID="smoke-transition:$RUN_ID"
[[ -r "$PAY_STATEMENT_PDF" ]] || die "Synthetic pay statement PDF is missing: $PAY_STATEMENT_PDF"
if [[ "$WORKFLOW_MODE" == "deferred" ]]; then
    START_MODE="DEFERRED"
else
    START_MODE="AUTO"
fi

CREATE_BODY="$(build_demo_intake "$LOAN_SMOKE_APPLICATION_JSON_FILE" "$RUN_ID" "$START_MODE" "$MANUAL_REVIEW_PATH")" ||
    die "could not build the demo intake request"
SCENARIO_ID="$(printf '%s' "$CREATE_BODY" | jq -r .scenarioId)"
CREATE_DATA_ARGS=(--data "$CREATE_BODY")

if [[ -n "$LOAN_SMOKE_ADDRESS_JSON_FILE" ]]; then
    command -v jq >/dev/null 2>&1 || die "jq is required for an address override"
    [[ -r "$LOAN_SMOKE_ADDRESS_JSON_FILE" ]] || die "address override file is not readable"
    jq -e '
        type == "object" and
        ((keys - ["addressLine", "locality", "jurisdictionCode", "countryCode", "postalCode"]) == []) and
        (.addressLine | type == "string" and length > 0 and length <= 300) and
        (.locality | type == "string" and length > 0 and length <= 120) and
        (.jurisdictionCode | type == "string" and test("^[A-Z0-9_-]{2,20}$")) and
        (.countryCode | type == "string" and test("^[A-Z]{2}$")) and
        (.postalCode | type == "string" and length <= 20)
    ' "$LOAN_SMOKE_ADDRESS_JSON_FILE" >/dev/null || die "invalid address override fields"
    CREATE_BODY="$(printf '%s' "$CREATE_BODY" |
        jq -c --slurpfile address "$LOAN_SMOKE_ADDRESS_JSON_FILE" \
            '.applicant.address += $address[0]')" || die "could not build intake request"
    printf '%s' "$CREATE_BODY" >"$TEMP_DIR/intake.json"
    chmod 600 "$TEMP_DIR/intake.json"
    CREATE_DATA_ARGS=(--data-binary "@$TEMP_DIR/intake.json")
fi

if ! perform_bearer_request "$USER_ACCESS_TOKEN" \
        --request POST \
        --header 'Content-Type: application/json' \
        --header "Idempotency-Key: $INTAKE_KEY" \
        "${CREATE_DATA_ARGS[@]}" \
        "$LOAN_BASE_URL/api/v1/loan-applications"; then
    finish_api_now "Application intake request failed"
fi
[[ "$RESPONSE_STATUS" == "202" ]] || finish_api_now "Application intake did not return HTTP 202"
APPLICATION_ID="$(extract_json_string applicationId)"
[[ "$APPLICATION_ID" == APP-* ]] || finish_now "Application intake returned no canonical application ID"
LOAN_DOCUMENT_ID="$(extract_document_id_for_file "$LOAN_FILE_NAME")"
PAY_DOCUMENT_ID="$(extract_document_id_for_file "$PAY_FILE_NAME")"
[[ "$LOAN_DOCUMENT_ID" == DOC-* ]] || finish_now "Application intake returned no loan application document ID"
[[ "$PAY_DOCUMENT_ID" == DOC-* ]] || finish_now "Application intake returned no pay statement document ID"
body_contains '"status"[[:space:]]*:[[:space:]]*"SUBMITTED"' ||
    finish_now "New application was not SUBMITTED"
body_contains '"workflowName"[[:space:]]*:[[:space:]]*"'"$EXPECTED_WORKFLOW_NAME"'"' ||
    finish_now "Application was not assigned to workflow $EXPECTED_WORKFLOW_NAME"
body_contains '"workflowVersion"[[:space:]]*:[[:space:]]*'"$EXPECTED_WORKFLOW_VERSION"'([,}])' ||
    finish_now "Application was not assigned to the fixed $EXPECTED_WORKFLOW_NAME version $EXPECTED_WORKFLOW_VERSION; rebuild and redeploy loan-application-service"
pass "Create synthetic loan application"
pass "Workflow assignment is $EXPECTED_WORKFLOW_NAME version $EXPECTED_WORKFLOW_VERSION"

if ! perform_bearer_request "$USER_ACCESS_TOKEN" \
        --request POST \
        --header 'Content-Type: application/json' \
        --header "Idempotency-Key: $INTAKE_KEY" \
        "${CREATE_DATA_ARGS[@]}" \
        "$LOAN_BASE_URL/api/v1/loan-applications"; then
    finish_now "Idempotent intake retry failed"
fi
[[ "$RESPONSE_STATUS" == "202" ]] || finish_now "Idempotent intake retry did not return HTTP 202"
[[ "$(extract_json_string applicationId)" == "$APPLICATION_ID" ]] ||
    finish_now "Idempotent intake retry created a different application"
pass "Application intake is idempotent"

if perform_bearer_request "$USER_ACCESS_TOKEN" \
        "$LOAN_BASE_URL/api/v1/loan-applications/$APPLICATION_ID" &&
        [[ "$RESPONSE_STATUS" == "200" ]] && body_contains '"applicationId"[[:space:]]*:[[:space:]]*"'"$APPLICATION_ID"'"'; then
    pass "Read owned application"
else
    finish_now "Owned application could not be read"
fi

if perform_bearer_request "$USER_ACCESS_TOKEN" \
        --get --data-urlencode "scenarioId=$SCENARIO_ID" \
        "$LOAN_BASE_URL/api/v1/loan-applications" &&
        [[ "$RESPONSE_STATUS" == "200" ]] &&
        body_contains '"content"[[:space:]]*:' &&
        body_contains '"page"[[:space:]]*:' &&
        body_contains '"applicationId"[[:space:]]*:[[:space:]]*"'"$APPLICATION_ID"'"'; then
    pass "List includes owned application"
else
    finish_now "Owned application was not returned by list"
fi

if ! perform_bearer_request "$USER_ACCESS_TOKEN" \
        --request PUT \
        --header 'Content-Type: application/pdf' \
        --header "Idempotency-Key: $LOAN_UPLOAD_KEY" \
        --data-binary "@$LOAN_APPLICATION_PDF" \
        "$LOAN_BASE_URL/api/v1/loan-applications/$APPLICATION_ID/documents/$LOAN_DOCUMENT_ID/content"; then
    finish_api_now "Loan application PDF upload failed"
fi
[[ "$RESPONSE_STATUS" == "200" ]] || finish_api_now "Loan application PDF upload did not return HTTP 200"
body_contains '"status"[[:space:]]*:[[:space:]]*"RECEIVED"' ||
    finish_now "Uploaded loan application PDF was not RECEIVED"
pass "Upload synthetic loan application PDF"

if ! perform_bearer_request "$USER_ACCESS_TOKEN" \
        --request PUT \
        --header 'Content-Type: application/pdf' \
        --header "Idempotency-Key: $LOAN_UPLOAD_KEY" \
        --data-binary "@$LOAN_APPLICATION_PDF" \
        "$LOAN_BASE_URL/api/v1/loan-applications/$APPLICATION_ID/documents/$LOAN_DOCUMENT_ID/content"; then
    finish_now "Idempotent PDF upload retry failed"
fi
[[ "$RESPONSE_STATUS" == "200" ]] || finish_now "Idempotent PDF upload retry did not return HTTP 200"
pass "Document content upload is idempotent"

if ! perform_bearer_request "$USER_ACCESS_TOKEN" \
        --request PUT \
        --header 'Content-Type: application/pdf' \
        --header "Idempotency-Key: $PAY_UPLOAD_KEY" \
        --data-binary "@$PAY_STATEMENT_PDF" \
        "$LOAN_BASE_URL/api/v1/loan-applications/$APPLICATION_ID/documents/$PAY_DOCUMENT_ID/content"; then
    finish_api_now "Pay statement PDF upload failed"
fi
[[ "$RESPONSE_STATUS" == "200" ]] || finish_api_now "Pay statement PDF upload did not return HTTP 200"
body_contains '"status"[[:space:]]*:[[:space:]]*"RECEIVED"' ||
    finish_now "Uploaded pay statement PDF was not RECEIVED"
pass "Upload synthetic pay statement PDF"

if [[ "$WORKFLOW_MODE" == "deferred" ]]; then
    perform_bearer_request "$USER_ACCESS_TOKEN" \
        "$LOAN_BASE_URL/api/v1/loan-applications/$APPLICATION_ID" ||
        finish_now "Application could not be read for deferred workflow verification"
    body_contains '"dispatchStatus"[[:space:]]*:[[:space:]]*"DEFERRED"' ||
        finish_now "Deferred workflow was not DEFERRED"
    pass "Deferred workflow requires no MicroTx instance"
else
    deadline=$((SECONDS + WORKFLOW_TIMEOUT))
    workflow_started=false
    while [[ "$SECONDS" -lt "$deadline" ]]; do
        if perform_bearer_request "$USER_ACCESS_TOKEN" \
                "$LOAN_BASE_URL/api/v1/loan-applications/$APPLICATION_ID" &&
                [[ "$RESPONSE_STATUS" == "200" ]] &&
                body_contains '"dispatchStatus"[[:space:]]*:[[:space:]]*"STARTED"'; then
            workflow_started=true
            break
        fi
        if [[ "$RESPONSE_STATUS" == "200" ]] &&
                body_contains '"dispatchStatus"[[:space:]]*:[[:space:]]*"FAILED_FINAL"'; then
            workflow_error_code="$(extract_json_string lastErrorCode)"
            workflow_error_message="$(extract_json_string lastErrorMessage)"
            finish_now "Workflow start failed permanently: ${workflow_error_code:-unknown}${workflow_error_message:+ - $workflow_error_message}"
        fi
        sleep 1
    done
    if [[ "$workflow_started" != "true" ]] && perform_bearer_request "$USER_ACCESS_TOKEN" \
            "$LOAN_BASE_URL/api/v1/loan-applications/$APPLICATION_ID" &&
            [[ "$RESPONSE_STATUS" == "200" ]] &&
            body_contains '"dispatchStatus"[[:space:]]*:[[:space:]]*"FAILED_FINAL"'; then
        workflow_error_code="$(extract_json_string lastErrorCode)"
        workflow_error_message="$(extract_json_string lastErrorMessage)"
        finish_now "Workflow start failed permanently: ${workflow_error_code:-unknown}${workflow_error_message:+ - $workflow_error_message}"
    fi
    if [[ "$workflow_started" != "true" ]]; then
        workflow_dispatch_status="$(extract_json_string dispatchStatus)"
        workflow_error_code="$(extract_json_string lastErrorCode)"
        workflow_error_message="$(extract_json_string lastErrorMessage)"
        finish_now "Workflow did not reach STARTED before timeout: dispatchStatus=${workflow_dispatch_status:-unknown}${workflow_error_code:+, errorCode=$workflow_error_code}${workflow_error_message:+, errorMessage=$workflow_error_message}"
    fi
    WORKFLOW_ID="$(extract_json_string workflowId)"
    [[ -n "$WORKFLOW_ID" ]] || finish_now "Started workflow had no workflow ID"
    if [[ "$WORKFLOW_MODE" == "fake" && "$WORKFLOW_ID" != fake-* ]]; then
        finish_now "Fake workflow did not return a fake workflow ID"
    fi
    if [[ "$WORKFLOW_MODE" == "microtx" && "$WORKFLOW_ID" == fake-* ]]; then
        finish_now "MicroTx workflow returned a fake workflow ID"
    fi
    pass "$WORKFLOW_MODE workflow reached STARTED"
fi

if [[ "$LOAN_SMOKE_STOP_AFTER_DISPATCH" == "true" ]]; then
    printf '\nSynthetic application: %s (%s)\n' "$APPLICATION_ID" "$SCENARIO_ID"
    printf 'Workflow ID: %s\n' "$WORKFLOW_ID"
    if [[ "$LOAN_SMOKE_VERIFY_GEO" == "true" ]]; then
        command -v jq >/dev/null 2>&1 || die "jq is required for geographic verification"
        [[ "$GEO_BASE_URL" == http://* || "$GEO_BASE_URL" == https://* ]] ||
            die "GEO_BASE_URL is required for geographic verification"
        [[ "$LOAN_SMOKE_GEO_WAIT_SECONDS" =~ ^[1-9][0-9]{0,2}$ ]] ||
            die "LOAN_SMOKE_GEO_WAIT_SECONDS must be 1-999 seconds"
        # perform_bearer_request writes HTTP headers to RESPONSE_BODY. Keep the
        # geographic JSON body separate so jq never receives those headers.
        : >"$TEMP_DIR/geographic-response.json"
        chmod 600 "$TEMP_DIR/geographic-response.json"
        deadline=$((SECONDS + LOAN_SMOKE_GEO_WAIT_SECONDS))
        geo_found=false
        while [[ "$SECONDS" -lt "$deadline" ]]; do
            if perform_bearer_request "$SERVICE_ACCESS_TOKEN" \
                    --output "$TEMP_DIR/geographic-response.json" \
                    "$GEO_BASE_URL/internal/api/v1/applications/$APPLICATION_ID/geographic-risk"; then
                if [[ "$RESPONSE_STATUS" == "200" ]]; then
                    GEO_SUMMARY="$(jq -er \
                        --arg applicationId "$APPLICATION_ID" '
                          select(.applicationId == $applicationId and
                                 (.latestEvaluationId | type == "string" and length > 0))
                          | [.disposition, (.signals | map(.signalCode) | join(","))]
                          | @tsv
                        ' "$TEMP_DIR/geographic-response.json" 2>/dev/null)" ||
                        finish_now "Geographic-risk returned HTTP 200 without the expected JSON body"
                    IFS=$'\t' read -r GEO_DISPOSITION GEO_SIGNALS <<<"$GEO_SUMMARY"
                    geo_found=true
                    break
                fi
                [[ "$RESPONSE_STATUS" == "404" ]] ||
                    finish_now "Geographic-risk lookup returned HTTP $RESPONSE_STATUS"
            fi
            sleep 5
        done
        [[ "$geo_found" == "true" ]] ||
            finish_now "Geographic-risk task did not produce an evaluation before timeout; inspect the MicroTx workflow"
        case ",$GEO_SIGNALS," in
            *,ADDRESS_COORDINATES_MISSING,* | *,SPATIAL_EVALUATION_UNAVAILABLE,*)
                finish_now "Geographic-risk evaluation did not resolve coordinates: $GEO_SIGNALS"
                ;;
            *,LOCATION_IN_SERVICE_AREA,* | *,LOCATION_EXCLUDED,* | \
                *,BOUNDARY_REVIEW_REQUIRED,* | *,LOCATION_RISK_REVIEW,*)
                pass "Geographic-risk task evaluated geocoded coordinates"
                printf 'Geographic disposition: %s; signal codes: %s\n' \
                    "$GEO_DISPOSITION" "$GEO_SIGNALS"
                ;;
            *) finish_now "Geographic-risk evaluation had no recognized location signal" ;;
        esac
        printf 'The geographic task follows both AI evidence tasks in workflow version 1.\n'
    else
        printf 'The workflow is asynchronous; dispatch STARTED does not prove that AI or geographic-risk tasks completed.\n'
    fi
    printf 'Summary: %d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT"
    exit 0
fi

TRANSITION_BODY="$(printf '%s' \
    '{"eventId":"'"$EVENT_ID"'","expectedStatus":"SUBMITTED","targetStatus":"PROCESSING","reasonCode":"SMOKE_TEST","traceId":"'"$(openssl rand -hex 16)"'"}')"

if perform_bearer_request "$USER_ACCESS_TOKEN" \
        --request POST --header 'Content-Type: application/json' --data "$TRANSITION_BODY" \
        "$LOAN_BASE_URL/internal/api/v1/loan-applications/$APPLICATION_ID/status-transitions" &&
        [[ "$RESPONSE_STATUS" == "403" ]]; then
    pass "Internal callback rejects user tokens"
else
    finish_now "Internal callback did not reject a user token"
fi

if ! perform_bearer_request "$SERVICE_ACCESS_TOKEN" \
        --request POST --header 'Content-Type: application/json' --data "$TRANSITION_BODY" \
        "$LOAN_BASE_URL/internal/api/v1/loan-applications/$APPLICATION_ID/status-transitions"; then
    finish_now "Internal status transition request failed"
fi
[[ "$RESPONSE_STATUS" == "200" ]] || finish_now "Internal status transition did not return HTTP 200"
body_contains '"status"[[:space:]]*:[[:space:]]*"PROCESSING"' ||
    finish_now "Internal callback did not transition application to PROCESSING"
pass "Service token applies internal status transition"

if ! perform_bearer_request "$SERVICE_ACCESS_TOKEN" \
        --request POST --header 'Content-Type: application/json' --data "$TRANSITION_BODY" \
        "$LOAN_BASE_URL/internal/api/v1/loan-applications/$APPLICATION_ID/status-transitions"; then
    finish_now "Idempotent status transition retry failed"
fi
[[ "$RESPONSE_STATUS" == "200" ]] &&
    body_contains '"status"[[:space:]]*:[[:space:]]*"PROCESSING"' ||
    finish_now "Idempotent status transition retry changed the result"
pass "Internal status transition is idempotent"

RESPONSE_BODY=""
USER_ACCESS_TOKEN=""
SERVICE_ACCESS_TOKEN=""
printf '\nSynthetic application: %s (%s)\n' "$APPLICATION_ID" "$SCENARIO_ID"
printf 'Expected document-review disposition: %s\n' "$EXPECTED_REVIEW_DISPOSITION"
printf 'Summary: %d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[[ "$FAIL_COUNT" -eq 0 ]]
