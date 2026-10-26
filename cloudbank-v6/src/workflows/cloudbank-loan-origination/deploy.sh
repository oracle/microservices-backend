#!/usr/bin/env bash

# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at
# https://oss.oracle.com/licenses/upl.

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
readonly CLOUDBANK_ENV_FILE="${CLOUDBANK_ENV_FILE:-$REPOSITORY_ROOT/.env}"
readonly DEFAULT_TASK_DEF_FILE="$SCRIPT_DIR/review-documents-task-def.json"
readonly DEFAULT_TOKEN_REFRESH_TASK_DEF_FILE="$SCRIPT_DIR/refresh-workflow-authorization-task-def.json"
readonly MAX_TASK_TYPE_LENGTH=32
readonly EXPECTED_WORKFLOW_NAME="cloudbank-loan-origination"
readonly EXPECTED_WORKFLOW_VERSION="1"

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 2
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "$1 is required"
}

normalize_api_base() {
    local base="${1%/}"
    case "$base" in
        */api) printf '%s\n' "$base" ;;
        *) printf '%s/api\n' "$base" ;;
    esac
}

print_json_or_raw() {
    local body
    body="$(cat)"
    if ! printf '%s' "$body" | jq . 2>/dev/null; then
        printf '%s\n' "$body"
    fi
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

urlencode() {
    jq -nr --arg value "$1" '$value | @uri'
}

obtain_operator_access_token() {
    require_command openssl
    [[ -t 0 ]] || die \
        "Interactive operator login requires a terminal; set MICROTX_BEARER_TOKEN for non-interactive deployment"

    local auth_server_url="${MICROTX_OPERATOR_AUTH_SERVER_URL:-http://127.0.0.1:8080}"
    auth_server_url="${auth_server_url%/}"
    local token_uri="${MICROTX_OPERATOR_TOKEN_URI:-$auth_server_url/oauth2/token}"
    local client_id="${MICROTX_OPERATOR_CLIENT_ID:-cloudbank-client}"
    local redirect_uri="${MICROTX_OPERATOR_REDIRECT_URI:-$auth_server_url/login/oauth2/code/$client_id}"
    local scope="${MICROTX_OPERATOR_SCOPE:-openid cloudbank.read cloudbank.write}"
    local client_secret="${MICROTX_OPERATOR_CLIENT_SECRET:-}"
    local verifier challenge authorization_url authorization_code token_body token_status

    if [[ -z "$client_secret" && "$client_id" == "cloudbank-client" ]]; then
        client_secret="$(read_local_env_value AZN_AUTHORIZATION_SERVER_DEFAULT_CLIENT_SECRET || true)"
    fi
    if [[ -z "$client_secret" ]]; then
        printf 'cloudbank-client secret: ' >&2
        IFS= read -r -s client_secret
        printf '\n' >&2
    fi
    [[ -n "$client_secret" ]] || die \
        "Set MICROTX_OPERATOR_CLIENT_SECRET or AZN_AUTHORIZATION_SERVER_DEFAULT_CLIENT_SECRET in $CLOUDBANK_ENV_FILE"

    verifier="$(openssl rand -base64 64 | tr '+/' '-_' | tr -d '=\n')"
    challenge="$(
        printf '%s' "$verifier" |
            openssl dgst -binary -sha256 |
            openssl base64 |
            tr '+/' '-_' |
            tr -d '=\n'
    )"
    authorization_url="$auth_server_url/oauth2/authorize"
    authorization_url+="?response_type=code"
    authorization_url+="&client_id=$(urlencode "$client_id")"
    authorization_url+="&redirect_uri=$(urlencode "$redirect_uri")"
    authorization_url+="&scope=$(urlencode "$scope")"
    authorization_url+="&code_challenge=$(urlencode "$challenge")"
    authorization_url+="&code_challenge_method=S256"

    printf '\nOperator authorization is required.\n'
    printf 'Open this URL in a private browser window:\n\n%s\n\n' "$authorization_url"
    printf 'Sign in as obaas-admin (or obaas-config), then copy only the code query-parameter value.\n'
    printf 'Authorization code: ' >&2
    IFS= read -r -s authorization_code
    printf '\n' >&2
    [[ -n "$authorization_code" ]] || die "Authorization code is required"

    token_body="$(mktemp "${TMPDIR:-/tmp}/cloudbank-workflow-operator-token.XXXXXX")"
    token_status="$(
        curl --silent --show-error \
            --output "$token_body" \
            --write-out '%{http_code}' \
            --user "$client_id:$client_secret" \
            --request POST "$token_uri" \
            -H 'Content-Type: application/x-www-form-urlencoded' \
            --data-urlencode 'grant_type=authorization_code' \
            --data-urlencode "code=$authorization_code" \
            --data-urlencode "redirect_uri=$redirect_uri" \
            --data-urlencode "code_verifier=$verifier"
    )"

    authorization_code=""
    client_secret=""
    verifier=""
    challenge=""

    if [[ "$token_status" -lt 200 || "$token_status" -ge 300 ]]; then
        printf 'Operator token exchange failed with HTTP %s\n' "$token_status" >&2
        print_json_or_raw < "$token_body" >&2
        rm -f "$token_body"
        die "Start a new PKCE login; authorization codes are short-lived and single-use"
    fi

    MICROTX_ACCESS_TOKEN="$(jq -er '.access_token | strings | select(length > 0)' "$token_body")" || {
        rm -f "$token_body"
        die "Operator token response did not contain an access token"
    }
    rm -f "$token_body"
    AUTH_ARGS=(-H "Authorization: Bearer $MICROTX_ACCESS_TOKEN")
    printf 'Operator token obtained.\n'
}

require_command curl
require_command jq

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    printf 'Usage: %s <workflow-v1.json|workflow-v1-obaas.json>\n' "$0"
    exit 0
fi
[[ $# -eq 1 ]] || die "Provide exactly one version 1 workflow definition"

WORKFLOW_FILE="$1"
case "${WORKFLOW_FILE##*/}" in
    workflow-v1.json | workflow-v1-obaas.json) ;;
    *) die "Workflow definition must be workflow-v1.json or workflow-v1-obaas.json: $WORKFLOW_FILE" ;;
esac
[[ -r "$WORKFLOW_FILE" ]] || die "Workflow file is not readable: $WORKFLOW_FILE"

[[ -n "${MICROTX_WORKFLOW_URL:-}" ]] ||
    die "Set MICROTX_WORKFLOW_URL, for example: http://127.0.0.1/workflow-server"

TASK_DEF_FILE="${MICROTX_TASK_DEFINITION_FILE:-$DEFAULT_TASK_DEF_FILE}"
[[ -r "$TASK_DEF_FILE" ]] || die "Task definition file is not readable: $TASK_DEF_FILE"
TOKEN_REFRESH_TASK_DEF_FILE="${MICROTX_TOKEN_REFRESH_TASK_DEFINITION_FILE:-$DEFAULT_TOKEN_REFRESH_TASK_DEF_FILE}"
[[ -r "$TOKEN_REFRESH_TASK_DEF_FILE" ]] ||
    die "Token-refresh task definition file is not readable: $TOKEN_REFRESH_TASK_DEF_FILE"
TASK_DEF_FILES=("$TASK_DEF_FILE" "$TOKEN_REFRESH_TASK_DEF_FILE")

API_BASE="$(normalize_api_base "$MICROTX_WORKFLOW_URL")"
VALIDATE_URL="$API_BASE/metadata/workflow/validate"
UPSERT_URL="$API_BASE/metadata/workflow"
TASK_DEFS_URL="$API_BASE/metadata/taskdefs"

WORKFLOW_NAME="$(jq -r '.name // empty' "$WORKFLOW_FILE")"
WORKFLOW_VERSION="$(jq -r '.version // empty' "$WORKFLOW_FILE")"
[[ -n "$WORKFLOW_NAME" ]] || die "Workflow JSON must contain .name"
[[ "$WORKFLOW_VERSION" =~ ^[0-9]+$ ]] || die "Workflow JSON must contain numeric .version"
[[ "$WORKFLOW_NAME" == "$EXPECTED_WORKFLOW_NAME" ]] ||
    die "Workflow JSON must define $EXPECTED_WORKFLOW_NAME"
[[ "$WORKFLOW_VERSION" == "$EXPECTED_WORKFLOW_VERSION" ]] ||
    die "Only $EXPECTED_WORKFLOW_NAME version $EXPECTED_WORKFLOW_VERSION may be deployed"
for task_definition_file in "${TASK_DEF_FILES[@]}"; do
    task_definition_name="$(jq -r '.name // empty' "$task_definition_file")"
    [[ -n "$task_definition_name" ]] || die "Task definition JSON must contain .name: $task_definition_file"
    [[ "${#task_definition_name}" -le "$MAX_TASK_TYPE_LENGTH" ]] ||
        die "Task definition name exceeds MicroTx Oracle TASK_TYPE limit of $MAX_TASK_TYPE_LENGTH characters: $task_definition_name"
    [[ "$(jq -r '.retryCount // empty' "$task_definition_file")" =~ ^[1-9][0-9]*$ ]] ||
        die "Task definition JSON must contain a positive .retryCount: $task_definition_file"
done

printf 'Deploying MicroTx workflow definition\n'
printf '  Workflow: %s version %s\n' "$WORKFLOW_NAME" "$WORKFLOW_VERSION"
printf '  Source:   %s\n' "$WORKFLOW_FILE"
for task_definition_file in "${TASK_DEF_FILES[@]}"; do
    printf '  Task def: %s (%s)\n' "$(jq -r '.name' "$task_definition_file")" "$task_definition_file"
done
printf '  API base: %s\n\n' "$API_BASE"

AUTH_ARGS=()
workflow_curl() {
    if [[ "${#AUTH_ARGS[@]}" -gt 0 ]]; then
        curl "${AUTH_ARGS[@]}" "$@"
    else
        curl "$@"
    fi
}

printf 'Checking Workflow Server authentication...\n'
auth_probe_body="$(mktemp "${TMPDIR:-/tmp}/cloudbank-workflow-auth-probe.XXXXXX")"
auth_probe_status="$(
    curl --silent --show-error \
        --output "$auth_probe_body" \
        --write-out '%{http_code}' \
        --request POST "$VALIDATE_URL" \
        -H 'Content-Type: application/json' \
        --data-binary @"$WORKFLOW_FILE"
)"

if [[ "$auth_probe_status" -ge 200 && "$auth_probe_status" -lt 300 ]]; then
    printf 'Workflow Server allows unauthenticated validation; using open deployment.\n'
elif [[ "$auth_probe_status" == "401" || "$auth_probe_status" == "403" ]]; then
    printf 'Workflow Server requires authentication; using authenticated deployment.\n'

    deploy_auth_mode="${MICROTX_DEPLOY_AUTH_MODE:-auto}"
    case "$deploy_auth_mode" in
        auto | operator | client_credentials) ;;
        *) die "MICROTX_DEPLOY_AUTH_MODE must be auto, operator, or client_credentials" ;;
    esac

    if [[ -n "${MICROTX_BEARER_TOKEN:-}" ]]; then
        AUTH_ARGS=(-H "Authorization: Bearer $MICROTX_BEARER_TOKEN")
    elif [[ "$deploy_auth_mode" == "client_credentials" || \
            ( "$deploy_auth_mode" == "auto" && ! -t 0 && \
              -n "${MICROTX_TOKEN_URI:-}" && -n "${MICROTX_CLIENT_SECRET:-}" ) ]]; then
        [[ -n "${MICROTX_TOKEN_URI:-}" ]] ||
            die "MICROTX_TOKEN_URI is required with MICROTX_CLIENT_SECRET"
        [[ -n "${MICROTX_CLIENT_SECRET:-}" ]] ||
            die "MICROTX_CLIENT_SECRET is required with MICROTX_TOKEN_URI"

        readonly MICROTX_CLIENT_ID="${MICROTX_CLIENT_ID:-microtx-workflow-client}"
        readonly MICROTX_SCOPE="${MICROTX_SCOPE:-microtx.workflow}"
        token_body="$(mktemp "${TMPDIR:-/tmp}/cloudbank-workflow-token.XXXXXX")"
        token_status="$(
            curl --silent --show-error \
                --output "$token_body" \
                --write-out '%{http_code}' \
                --request POST "$MICROTX_TOKEN_URI" \
                --user "$MICROTX_CLIENT_ID:$MICROTX_CLIENT_SECRET" \
                -H 'Content-Type: application/x-www-form-urlencoded' \
                --data-urlencode 'grant_type=client_credentials' \
                --data-urlencode "scope=$MICROTX_SCOPE"
        )"

        if [[ "$token_status" -lt 200 || "$token_status" -ge 300 ]]; then
            printf 'MicroTx Workflow API authentication failed with HTTP %s\n' "$token_status" >&2
            print_json_or_raw < "$token_body" >&2
            rm -f "$auth_probe_body" "$token_body"
            exit 1
        fi

        MICROTX_ACCESS_TOKEN="$(jq -er '.access_token | strings | select(length > 0)' "$token_body")" || {
            printf 'MicroTx Workflow API authentication response did not contain an access token\n' >&2
            rm -f "$auth_probe_body" "$token_body"
            exit 1
        }
        rm -f "$token_body"
        AUTH_ARGS=(-H "Authorization: Bearer $MICROTX_ACCESS_TOKEN")
    else
        obtain_operator_access_token
    fi

    authenticated_status="$(
        workflow_curl --silent --show-error \
            --output "$auth_probe_body" \
            --write-out '%{http_code}' \
            --request POST "$VALIDATE_URL" \
            -H 'Content-Type: application/json' \
            --data-binary @"$WORKFLOW_FILE"
    )"
    if [[ "$authenticated_status" -lt 200 || "$authenticated_status" -ge 300 ]]; then
        printf 'Authenticated workflow validation failed with HTTP %s\n' "$authenticated_status" >&2
        print_json_or_raw < "$auth_probe_body" >&2
        rm -f "$auth_probe_body"
        exit 1
    fi
    printf 'Workflow Server authentication succeeded.\n'
else
    printf 'Unable to determine Workflow Server authentication; validation probe returned HTTP %s\n' \
        "$auth_probe_status" >&2
    print_json_or_raw < "$auth_probe_body" >&2
    rm -f "$auth_probe_body"
    exit 1
fi
printf 'Workflow definition validation succeeded.\n'
print_json_or_raw < "$auth_probe_body"
rm -f "$auth_probe_body"

save_task_definition() {
    local task_definition_file="$1"
    local task_definition_name
    local probe_body probe_status payload method response_body response_status

    task_definition_name="$(jq -r '.name' "$task_definition_file")"
    printf '\nSaving task definition %s...\n' "$task_definition_name"
    probe_body="$(mktemp "${TMPDIR:-/tmp}/cloudbank-task-def-probe.XXXXXX")"
    probe_status="$(
        workflow_curl --silent --show-error \
            --output "$probe_body" \
            --write-out '%{http_code}' \
            "$TASK_DEFS_URL/$task_definition_name"
    )"

    payload="$(mktemp "${TMPDIR:-/tmp}/cloudbank-task-def-upsert.XXXXXX")"
    case "$probe_status" in
        200)
            method="PUT"
            jq -c '.' "$task_definition_file" > "$payload"
            ;;
        404)
            method="POST"
            jq -c '[.]' "$task_definition_file" > "$payload"
            ;;
        *)
            printf 'Unable to determine whether task definition exists; lookup returned HTTP %s\n' \
                "$probe_status" >&2
            print_json_or_raw < "$probe_body" >&2
            rm -f "$probe_body" "$payload"
            exit 1
            ;;
    esac
    rm -f "$probe_body"

    response_body="$(mktemp "${TMPDIR:-/tmp}/cloudbank-task-def-upsert-response.XXXXXX")"
    response_status="$(
        workflow_curl --silent --show-error \
            --output "$response_body" \
            --write-out '%{http_code}' \
            --request "$method" "$TASK_DEFS_URL" \
            -H 'Content-Type: application/json' \
            --data-binary @"$payload"
    )"
    rm -f "$payload"

    if [[ "$response_status" -lt 200 || "$response_status" -ge 300 ]]; then
        printf 'Task definition %s save failed with HTTP %s\n' \
            "$task_definition_name" "$response_status" >&2
        print_json_or_raw < "$response_body" >&2
        rm -f "$response_body"
        exit 1
    fi
    print_json_or_raw < "$response_body"
    rm -f "$response_body"
}

for task_definition_file in "${TASK_DEF_FILES[@]}"; do
    save_task_definition "$task_definition_file"
done

printf '\nSaving workflow definition...\n'
upsert_payload="$(mktemp "${TMPDIR:-/tmp}/cloudbank-workflow-upsert.XXXXXX")"
jq -c '[.]' "$WORKFLOW_FILE" > "$upsert_payload"

upsert_body="$(mktemp "${TMPDIR:-/tmp}/cloudbank-workflow-upsert-response.XXXXXX")"
upsert_status="$(
    workflow_curl --silent --show-error \
        --output "$upsert_body" \
        --write-out '%{http_code}' \
        --request PUT "$UPSERT_URL" \
        -H 'Content-Type: application/json' \
        --data-binary @"$upsert_payload"
)"
rm -f "$upsert_payload"

if [[ "$upsert_status" -lt 200 || "$upsert_status" -ge 300 ]]; then
    printf 'Workflow save failed with HTTP %s\n' "$upsert_status" >&2
    print_json_or_raw < "$upsert_body" >&2
    rm -f "$upsert_body"
    exit 1
fi

print_json_or_raw < "$upsert_body"
if jq -e '.bulkErrorResults? | objects | length > 0' "$upsert_body" >/dev/null 2>&1; then
    printf 'Workflow save reported bulk errors\n' >&2
    rm -f "$upsert_body"
    exit 1
fi
rm -f "$upsert_body"

printf '\nVerifying saved workflow definition...\n'
verification_body="$(mktemp "${TMPDIR:-/tmp}/cloudbank-workflow-deploy-verification.XXXXXX")"
verification_status="$(
    workflow_curl --silent --show-error \
        --output "$verification_body" \
        --write-out '%{http_code}' \
        "$UPSERT_URL/$WORKFLOW_NAME"
)"

if [[ "$verification_status" -lt 200 || "$verification_status" -ge 300 ]]; then
    printf 'Workflow verification failed with HTTP %s\n' "$verification_status" >&2
    print_json_or_raw < "$verification_body" >&2
    rm -f "$verification_body"
    exit 1
fi

if ! jq -e --arg name "$WORKFLOW_NAME" --argjson version "$WORKFLOW_VERSION" '
    if type == "array" then
      any(.[]; .name == $name and .version == $version)
    else
      .name == $name and .version == $version
    end
' "$verification_body" >/dev/null; then
    printf 'Workflow %s version %s was not present in the metadata response\n' \
        "$WORKFLOW_NAME" "$WORKFLOW_VERSION" >&2
    print_json_or_raw < "$verification_body" >&2
    rm -f "$verification_body"
    exit 1
fi
rm -f "$verification_body"

printf '\nWorkflow %s version %s deployed successfully.\n' "$WORKFLOW_NAME" "$WORKFLOW_VERSION"
