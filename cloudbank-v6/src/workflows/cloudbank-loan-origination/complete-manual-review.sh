#!/usr/bin/env bash

# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at
# https://oss.oracle.com/licenses/upl.

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
readonly CLOUDBANK_ENV_FILE="${CLOUDBANK_ENV_FILE:-$REPOSITORY_ROOT/.env}"
readonly TASK_REFERENCE="human_task_manual_review"
readonly TASK_NAME="human_task"

WORKFLOW_ID=""
OUTCOME=""
REVIEWER_PRINCIPAL_ID="${REVIEWER_PRINCIPAL_ID:-underwriter-demo}"
REASON_CODE="${MANUAL_REVIEW_REASON_CODE:-DOCUMENT_EXCEPTION_RESOLVED}"
POLICY_SECTION="${MANUAL_REVIEW_POLICY_SECTION:-CBPL-150-S4}"
SERVER_URL="${CONDUCTOR_SERVER_URL:-${MICROTX_WORKFLOW_URL:-http://127.0.0.1:9010/workflow-server/api}}"
TOKEN_URI="${MICROTX_TOKEN_URI:-http://127.0.0.1:8080/oauth2/token}"
CLIENT_ID="${MICROTX_CLIENT_ID:-microtx-workflow-client}"
SCOPE="${MICROTX_SCOPE:-microtx.workflow}"
CLIENT_SECRET="${MICROTX_CLIENT_SECRET:-}"
ACCESS_TOKEN="${MICROTX_BEARER_TOKEN:-}"
WAIT_SECONDS="${MANUAL_REVIEW_WAIT_SECONDS:-120}"
FROM_ENV=false
DRY_RUN=false
ASSUME_YES=false
PAYLOAD_FILE=""

usage() {
    cat <<EOF
Usage: ${0##*/} <workflow-id> --outcome APPROVED|REJECTED [options]

Completes the cloudbank-loan-origination HUMAN task with the bounded payload
required by decision-service, then waits for the workflow's terminal status.
The requested human outcome does not override deterministic hard-reject rules.

Options:
      --outcome VALUE              Required: APPROVED or REJECTED
      --reviewer-principal-id ID   Audit principal (default: underwriter-demo)
      --reason-code CODE           Stable reason code (default: DOCUMENT_EXCEPTION_RESOLVED)
      --policy-section REF         Policy section (default: CBPL-150-S4)
      --server-url URL             MicroTx API base (default: CONDUCTOR_SERVER_URL,
                                   MICROTX_WORKFLOW_URL, or
                                   http://127.0.0.1:9010/workflow-server/api)
      --token-uri URL              OAuth token endpoint (default:
                                   http://127.0.0.1:8080/oauth2/token)
      --from-env                   Read the MicroTx client secret from the root
                                   .env without sourcing it
      --wait-seconds N             Workflow completion wait, 0-900 (default: 120)
      --dry-run                    Validate and show a redacted plan; call no API
  -y, --yes                        Skip the final confirmation prompt
  -h, --help                       Show this help

Authentication priority:
  1. MICROTX_BEARER_TOKEN
  2. MICROTX_CLIENT_SECRET with MICROTX_TOKEN_URI
  3. AZN_AUTHORIZATION_SERVER_MICROTX_CLIENT_SECRET from .env with --from-env
  4. A silent terminal prompt for the MicroTx client secret

The script never prints the bearer token, client secret, or reviewer principal.
EOF
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 2
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "$1 is required"
}

require_option_value() {
    local option="$1"
    local value="${2-}"
    [[ -n "$value" && "$value" != --* ]] || die "$option requires a value"
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

normalize_api_base() {
    local base="${1%/}"
    case "$base" in
        */api) printf '%s\n' "$base" ;;
        *) printf '%s/api\n' "$base" ;;
    esac
}

curl_config_escape() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '%s' "$value"
}

bearer_curl() {
    local escaped_token
    escaped_token="$(curl_config_escape "$ACCESS_TOKEN")"
    printf 'header = "Authorization: Bearer %s"\n' "$escaped_token" |
        curl --silent --show-error --fail-with-body \
            --connect-timeout 5 \
            --max-time 30 \
            --config - \
            "$@"
}

obtain_access_token() {
    local escaped_credentials
    local token_response

    if [[ -n "$ACCESS_TOKEN" ]]; then
        return
    fi

    if [[ -z "$CLIENT_SECRET" && "$FROM_ENV" == true ]]; then
        CLIENT_SECRET="$(read_local_env_value AZN_AUTHORIZATION_SERVER_MICROTX_CLIENT_SECRET || true)"
    fi
    if [[ -z "$CLIENT_SECRET" ]]; then
        [[ -t 0 ]] || die \
            "Set MICROTX_BEARER_TOKEN, MICROTX_CLIENT_SECRET, or use --from-env"
        printf 'MicroTx workflow client secret: ' >&2
        IFS= read -r -s CLIENT_SECRET
        printf '\n' >&2
    fi
    [[ -n "$CLIENT_SECRET" ]] || die "MicroTx workflow client secret must not be empty"

    escaped_credentials="$(curl_config_escape "$CLIENT_ID:$CLIENT_SECRET")"
    token_response="$({
        printf 'user = "%s"\n' "$escaped_credentials"
    } | curl --silent --show-error --fail-with-body \
        --connect-timeout 5 \
        --max-time 30 \
        --config - \
        --request POST \
        --header 'Content-Type: application/x-www-form-urlencoded' \
        --data-urlencode 'grant_type=client_credentials' \
        --data-urlencode "scope=$SCOPE" \
        "$TOKEN_URI")" || die "MicroTx OAuth token request failed"

    ACCESS_TOKEN="$(printf '%s' "$token_response" |
        jq -er '.access_token | strings | select(length > 0)')" ||
        die "MicroTx OAuth response did not contain an access token"
    token_response=""
    CLIENT_SECRET=""
}

cleanup() {
    ACCESS_TOKEN=""
    CLIENT_SECRET=""
    if [[ -n "$PAYLOAD_FILE" && -f "$PAYLOAD_FILE" ]]; then
        rm -f -- "$PAYLOAD_FILE"
    fi
    unset ACCESS_TOKEN CLIENT_SECRET
}

parse_args() {
    [[ $# -ge 1 ]] || {
        usage >&2
        exit 2
    }
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        usage
        exit 0
    fi

    WORKFLOW_ID="$1"
    shift
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --outcome)
                require_option_value "$1" "${2-}"
                OUTCOME="$2"
                shift 2
                ;;
            --reviewer-principal-id)
                require_option_value "$1" "${2-}"
                REVIEWER_PRINCIPAL_ID="$2"
                shift 2
                ;;
            --reason-code)
                require_option_value "$1" "${2-}"
                REASON_CODE="$2"
                shift 2
                ;;
            --policy-section)
                require_option_value "$1" "${2-}"
                POLICY_SECTION="$2"
                shift 2
                ;;
            --server-url)
                require_option_value "$1" "${2-}"
                SERVER_URL="$2"
                shift 2
                ;;
            --token-uri)
                require_option_value "$1" "${2-}"
                TOKEN_URI="$2"
                shift 2
                ;;
            --wait-seconds)
                require_option_value "$1" "${2-}"
                WAIT_SECONDS="$2"
                shift 2
                ;;
            --from-env)
                FROM_ENV=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -y | --yes)
                ASSUME_YES=true
                shift
                ;;
            -h | --help)
                usage
                exit 0
                ;;
            *) die "unknown option: $1" ;;
        esac
    done
}

validate_inputs() {
    [[ "$WORKFLOW_ID" =~ ^[A-Za-z0-9._:-]{1,128}$ ]] || die "invalid workflow ID"
    case "$OUTCOME" in
        APPROVED | REJECTED) ;;
        *) die "--outcome must be APPROVED or REJECTED" ;;
    esac
    [[ "$REVIEWER_PRINCIPAL_ID" =~ ^[A-Za-z0-9._@:-]{1,80}$ ]] ||
        die "reviewer principal must contain 1-80 safe identifier characters"
    [[ "$REASON_CODE" =~ ^[A-Z0-9_:-]{3,120}$ ]] ||
        die "reason code must match [A-Z0-9_:-]{3,120}"
    [[ "$POLICY_SECTION" =~ ^CBPL-[0-9]{3}-S[0-9]+$ ]] ||
        die "policy section must match CBPL-<three digits>-S<section number>"
    [[ "$SERVER_URL" =~ ^https?://[^[:space:]\"]+$ ]] || die "invalid MicroTx server URL"
    [[ "$TOKEN_URI" =~ ^https?://[^[:space:]\"]+$ ]] || die "invalid OAuth token URL"
    [[ "$WAIT_SECONDS" =~ ^[0-9]{1,3}$ && "$WAIT_SECONDS" -le 900 ]] ||
        die "--wait-seconds must be an integer from 0 through 900"
    SERVER_URL="$(normalize_api_base "$SERVER_URL")"
}

write_payload() {
    PAYLOAD_FILE="$(mktemp "${TMPDIR:-/tmp}/cloudbank-manual-review.XXXXXX.json")"
    chmod 600 "$PAYLOAD_FILE"
    jq -n \
        --arg decisionOutcome "$OUTCOME" \
        --arg reviewerRole "UNDERWRITER" \
        --arg reviewerPrincipalId "$REVIEWER_PRINCIPAL_ID" \
        --arg reasonCode "$REASON_CODE" \
        --arg policySection "$POLICY_SECTION" \
        '{decisionOutcome:$decisionOutcome, reviewerRole:$reviewerRole,
          reviewerPrincipalId:$reviewerPrincipalId, reasonCode:$reasonCode,
          policySection:$policySection}' >"$PAYLOAD_FILE"
}

print_plan() {
    printf 'Manual-review completion target\n'
    printf '  workflow:          %s\n' "$WORKFLOW_ID"
    printf '  task:              %s\n' "$TASK_REFERENCE"
    printf '  requested outcome: %s\n' "$OUTCOME"
    printf '  reviewer role:     UNDERWRITER\n'
    printf '  reviewer principal: configured (not displayed)\n'
    printf '  reason code:       %s\n' "$REASON_CODE"
    printf '  policy section:    %s\n' "$POLICY_SECTION"
    printf '  API base:          %s\n' "$SERVER_URL"
}

verify_pending_human_task() {
    local search_response
    local match_count

    search_response="$(bearer_curl \
        --get \
        --data-urlencode 'start=0' \
        --data-urlencode 'size=100' \
        --data-urlencode "freeText=$WORKFLOW_ID" \
        "$SERVER_URL/notifications/human-tasks")" ||
        die "Could not query pending MicroTx HUMAN tasks"

    match_count="$(printf '%s' "$search_response" | jq -er \
        --arg workflowId "$WORKFLOW_ID" \
        --arg taskReference "$TASK_REFERENCE" \
        --arg taskName "$TASK_NAME" \
        '[.results[]? | select(.workflowInstanceId == $workflowId and
          (.taskDefName == $taskReference or .taskDefName == $taskName) and
          (.status == "IN_PROGRESS" or .status == "SCHEDULED"))] | length')" ||
        die "MicroTx HUMAN-task response was not valid JSON"
    search_response=""

    [[ "$match_count" == "1" ]] || die \
        "Expected one pending $TASK_REFERENCE task for workflow $WORKFLOW_ID; found $match_count"
}

confirm_completion() {
    local answer
    if [[ "$ASSUME_YES" == true ]]; then
        return
    fi
    [[ -t 0 ]] || die "Interactive confirmation is required; pass --yes for automation"
    printf 'Complete this HUMAN task with outcome %s? [y/N] ' "$OUTCOME" >&2
    IFS= read -r answer
    case "$answer" in
        y | Y | yes | YES) ;;
        *) die "Manual-review completion cancelled" ;;
    esac
}

complete_human_task() {
    local completion_response
    completion_response="$(bearer_curl \
        --request POST \
        --header 'Content-Type: application/json' \
        --data-binary "@$PAYLOAD_FILE" \
        "$SERVER_URL/tasks/$WORKFLOW_ID/$TASK_REFERENCE/COMPLETED")" ||
        die "MicroTx rejected the HUMAN-task completion"
    completion_response=""
    printf 'HUMAN task completion accepted by MicroTx.\n'
}

wait_for_workflow() {
    local deadline
    local summary
    local status

    [[ "$WAIT_SECONDS" -gt 0 ]] || return
    deadline=$((SECONDS + WAIT_SECONDS))
    while (( SECONDS < deadline )); do
        summary="$(bearer_curl "$SERVER_URL/workflow/$WORKFLOW_ID" |
            jq -cer '{status, decisionOutcome:(.output.decisionOutcome // null),
                      disposition:(.output.disposition // null),
                      riskBand:(.output.riskBand // null)}')" ||
            die "Could not read the workflow after HUMAN completion"
        status="$(printf '%s' "$summary" | jq -r '.status')"
        case "$status" in
            COMPLETED)
                printf 'Workflow completed after the HUMAN task:\n'
                printf '%s\n' "$summary" | jq .
                return
                ;;
            FAILED | TERMINATED | TIMED_OUT)
                printf 'Workflow reached terminal status after the HUMAN task:\n' >&2
                printf '%s\n' "$summary" | jq . >&2
                return 1
                ;;
        esac
        sleep 2
    done

    printf 'HUMAN completion succeeded, but workflow %s is still running after %s seconds.\n' \
        "$WORKFLOW_ID" "$WAIT_SECONDS"
}

main() {
    umask 077
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' HUP TERM

    require_command awk
    require_command curl
    require_command jq
    require_command mktemp
    require_command rm
    require_command sleep

    parse_args "$@"
    validate_inputs
    write_payload
    print_plan

    if [[ "$DRY_RUN" == true ]]; then
        printf 'Dry run: no authentication or MicroTx request was performed.\n'
        return
    fi

    obtain_access_token
    verify_pending_human_task
    confirm_completion
    complete_human_task
    wait_for_workflow
}

main "$@"
