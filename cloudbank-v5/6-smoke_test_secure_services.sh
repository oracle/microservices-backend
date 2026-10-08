#!/bin/bash
# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at http://oss.oracle.com/licenses/upl.

# CloudBank v5 Secure Services Smoke Test Script
# Verifies APISIX routes, OAuth2 token issuance, endpoint authorization, and
# the main secured CloudBank workflows.

set -e

# =============================================================================
# Script Directory and Prerequisites Library
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=check_prereqs.sh
source "${SCRIPT_DIR}/check_prereqs.sh"

# =============================================================================
# Variables
# =============================================================================
NAMESPACE=""
OBAAS_RELEASE=""
DB_NAME=""
GATEWAY_URL=""
LOCAL_PORT="9080"
DISCOVERY_LOCAL_PORT="9081"
DISCOVERY_TOKEN=""
DISCOVERY_PORT_FORWARD_PID=""
TMP_DIR=""
KEEP_PORT_FORWARD=false
READ_ONLY=false
FROM_ACCOUNT_ID=""
TO_ACCOUNT_ID=""
CLIENT_ID="cloudbank-client"
CLIENT_SECRET=""
TEST_CLIENT_ID="cloudbank-test-client"
TEST_CLIENT_SECRET=""
READ_TOKEN=""
TEST_TOKEN=""
TRANSFER_TOKEN=""
PORT_FORWARD_PID=""
FAILURES=0

# =============================================================================
# Parse Arguments
# =============================================================================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--namespace|-o|--obaas-release|-d|--database|--gateway-url|--local-port|--discovery-local-port|--from-account|--to-account)
                if [[ $# -lt 2 || -z "$2" || "$2" == -* ]]; then
                    print_error "Option $1 requires a value"
                    exit 1
                fi
                ;;
        esac
        case $1 in
            -n|--namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            -o|--obaas-release)
                OBAAS_RELEASE="$2"
                shift 2
                ;;
            -d|--database)
                DB_NAME="$2"
                shift 2
                ;;
            --gateway-url)
                GATEWAY_URL="$2"
                shift 2
                ;;
            --local-port)
                LOCAL_PORT="$2"
                shift 2
                ;;
            --discovery-local-port)
                DISCOVERY_LOCAL_PORT="$2"
                shift 2
                ;;
            --from-account)
                FROM_ACCOUNT_ID="$2"
                shift 2
                ;;
            --to-account)
                TO_ACCOUNT_ID="$2"
                shift 2
                ;;
            --read-only)
                READ_ONLY=true
                shift
                ;;
            --keep-port-forward)
                KEEP_PORT_FORWARD=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

show_help() {
    cat << 'EOF'
CloudBank v5 Secure Services Smoke Test Script

Verifies secured CloudBank services through APISIX.

Usage:
  ./6-smoke_test_secure_services.sh [options]

Options:
  -n, --namespace NAMESPACE      Kubernetes namespace (required)
  -o, --obaas-release RELEASE    OBaaS platform release name (auto-detected if not provided)
  -d, --database DBNAME          OBaaS database name/prefix for azn-server auth secret
  --gateway-url URL              Existing APISIX gateway URL, for example http://example.com
  --local-port PORT              Local port for APISIX port-forward (default: 9080)
  --discovery-local-port PORT    Local account discovery port (default: 9081)
  --from-account ACCOUNT_ID      Source account for transfer test
  --to-account ACCOUNT_ID        Destination account for deposit/transfer tests
  --read-only                    Skip mutating deposit and transfer tests
  --keep-port-forward            Leave the temporary port-forward running
  -h, --help                     Show this help message

Examples (replace placeholders with your configuration):
  ./6-smoke_test_secure_services.sh -n <namespace> -o <obaas-release> -d <dbname>
  ./6-smoke_test_secure_services.sh -n <namespace> -d <dbname> --read-only
  ./6-smoke_test_secure_services.sh -n <namespace> -d <dbname> --gateway-url <gateway-url>
  ./6-smoke_test_secure_services.sh -n <namespace> -d <dbname> --discovery-local-port <local-port>
  ./6-smoke_test_secure_services.sh -n <namespace> -d <dbname> --from-account <source-account-id> --to-account <destination-account-id>

Automatic discovery reads service-client-secret from <dbname>-azn-server-auth
and uses cloudbank.internal through a temporary direct account-service
port-forward. No user password is required. Discovery needs two accounts,
including one with a balance greater than 1. Supplying both account IDs bypasses
discovery; IDs must be positive, distinct integers belonging to existing accounts.
The full test publishes a test deposit. Use --read-only to skip workflow checks.
EOF
}

# =============================================================================
# Prompt, Cleanup, and Prerequisites
# =============================================================================
prompt_value() {
    local var_name="$1"
    local prompt="$2"
    local example="$3"
    local current_value="${!var_name}"

    if [[ -n "$current_value" ]]; then
        return 0
    fi

    local full_prompt="$prompt"
    if [[ -n "$example" ]]; then
        full_prompt="$prompt (e.g., $example)"
    fi

    while true; do
        read -p "$full_prompt: " value
        if [[ -n "$value" ]]; then
            printf -v "$var_name" '%s' "$value"
            return 0
        fi
        print_error "Value is required. Please enter a value."
    done
}

cleanup() {
    if [[ -n "$DISCOVERY_PORT_FORWARD_PID" ]]; then
        kill "$DISCOVERY_PORT_FORWARD_PID" 2>/dev/null || true
        wait "$DISCOVERY_PORT_FORWARD_PID" 2>/dev/null || true
    fi
    if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
        rm -rf -- "$TMP_DIR"
    fi
    if [[ -n "$PORT_FORWARD_PID" && "$KEEP_PORT_FORWARD" != true ]]; then
        print_step "Stopping APISIX gateway port-forward..."
        kill "$PORT_FORWARD_PID" 2>/dev/null || true
        wait "$PORT_FORWARD_PID" 2>/dev/null || true
        print_success "Port-forward stopped"
    elif [[ -n "$PORT_FORWARD_PID" ]]; then
        print_warning "Leaving APISIX gateway port-forward running (PID: $PORT_FORWARD_PID)"
    fi
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

check_prerequisites() {
    print_step "Checking prerequisites..."

    local errors=0
    if ! prereq_check_kubectl; then
        ((++errors))
    fi
    if ! prereq_check_namespace "$NAMESPACE"; then
        ((++errors))
    fi
    if ! command -v curl &>/dev/null; then
        print_error "curl is required"
        ((++errors))
    else
        print_success "curl is available"
    fi
    if ! command -v jq &>/dev/null; then
        print_error "jq is required"
        ((++errors))
    else
        print_success "jq is available"
    fi

    return "$errors"
}

# =============================================================================
# Gateway and Token Helpers
# =============================================================================
start_gateway_port_forward() {
    local service_name="${OBAAS_RELEASE}-apisix-gateway"

    print_step "Starting APISIX gateway port-forward to $service_name on localhost:$LOCAL_PORT..."
    kubectl port-forward -n "$NAMESPACE" "svc/$service_name" "${LOCAL_PORT}:80" &>/dev/null &
    PORT_FORWARD_PID=$!

    local attempt_count=0
    while ! curl --noproxy '*' -s "http://127.0.0.1:${LOCAL_PORT}/.well-known/oauth-authorization-server" &>/dev/null; do
        sleep 1
        ((++attempt_count))
        if [[ $attempt_count -ge 60 ]]; then
            print_error "APISIX gateway port-forward did not become ready"
            return 1
        fi
    done

    GATEWAY_URL="http://127.0.0.1:${LOCAL_PORT}"
    print_success "APISIX gateway is reachable at $GATEWAY_URL"
}

get_client_secret() {
    local auth_secret_name="${DB_NAME}-azn-server-auth"

    print_step "Reading OAuth client secrets from $auth_secret_name..."
    CLIENT_SECRET=$(kubectl get secret "$auth_secret_name" -n "$NAMESPACE" \
        -o jsonpath='{.data.client-secret}' 2>/dev/null | base64 -d)
    TEST_CLIENT_SECRET=$(kubectl get secret "$auth_secret_name" -n "$NAMESPACE" \
        -o jsonpath='{.data.test-client-secret}' 2>/dev/null | base64 -d)

    if [[ -z "$CLIENT_SECRET" ]]; then
        print_error "Could not read client-secret from secret $auth_secret_name"
        return 1
    fi
    if [[ -z "$TEST_CLIENT_SECRET" ]]; then
        print_error "Could not read test-client-secret from secret $auth_secret_name"
        return 1
    fi

    print_success "OAuth client secrets are available"
}

get_token() {
    local scope="$1"
    local client_id="${2:-$CLIENT_ID}"
    local client_secret="${3:-$CLIENT_SECRET}"
    local token

    token=$(curl --noproxy '*' -s -u "${client_id}:${client_secret}" \
        -X POST "${GATEWAY_URL}/oauth2/token" \
        -d grant_type=client_credentials \
        -d "scope=${scope}" | jq -r '.access_token // empty')

    if [[ -z "$token" ]]; then
        print_error "Could not get token for scope: $scope" >&2
        return 1
    fi

    echo "$token"
}

get_tokens() {
    print_step "Requesting scoped OAuth tokens..."
    READ_TOKEN=$(get_token "cloudbank.read")
    TEST_TOKEN=$(get_token "cloudbank.test" "$TEST_CLIENT_ID" "$TEST_CLIENT_SECRET")
    TRANSFER_TOKEN=$(get_token "cloudbank.transfer")
    print_success "Scoped OAuth tokens issued"
}

# Service credentials are used only to discover IDs directly from account.
start_account_discovery() {
    local auth_secret_name="${DB_NAME}-azn-server-auth"
    local service_secret attempt
    local discovery_base="http://127.0.0.1:${DISCOVERY_LOCAL_PORT}"

    print_step "Reading service-client credentials for automatic account discovery..."
    service_secret=$(kubectl get secret "$auth_secret_name" -n "$NAMESPACE" \
        -o jsonpath='{.data.service-client-secret}' 2>/dev/null | base64 -d)
    if [[ -z "$service_secret" ]]; then
        print_error "Could not read service-client-secret from $auth_secret_name; provide both account IDs to bypass discovery"
        return 1
    fi
    if ! DISCOVERY_TOKEN=$(get_token "cloudbank.internal" "cloudbank-service-client" "$service_secret"); then
        return 1
    fi

    print_step "Starting account-service port-forward for discovery on localhost:$DISCOVERY_LOCAL_PORT..."
    kubectl port-forward -n "$NAMESPACE" svc/account "${DISCOVERY_LOCAL_PORT}:8080" \
        >"$TMP_DIR/discovery-port-forward.log" 2>&1 &
    DISCOVERY_PORT_FORWARD_PID=$!
    for ((attempt=0; attempt<60; attempt++)); do
        if ! kill -0 "$DISCOVERY_PORT_FORWARD_PID" 2>/dev/null; then
            print_error "Account discovery port-forward exited; check svc/account and local port $DISCOVERY_LOCAL_PORT"
            return 1
        fi
        if grep -Fq "Forwarding from 127.0.0.1:${DISCOVERY_LOCAL_PORT} ->" "$TMP_DIR/discovery-port-forward.log" && \
            curl --noproxy '*' -fsS --max-time 2 "$discovery_base/actuator/health" >/dev/null 2>&1 && \
            kill -0 "$DISCOVERY_PORT_FORWARD_PID" 2>/dev/null; then
            return 0
        fi
        sleep 1
    done
    print_error "Account discovery port-forward did not become ready"
    return 1
}

# =============================================================================
# Test Helpers
# =============================================================================
record_result() {
    local test_name="$1"
    local expected="$2"
    local actual="$3"

    if [[ "$actual" == "$expected" ]]; then
        print_success "$test_name returned $actual"
    else
        print_error "$test_name returned $actual, expected $expected"
        ((++FAILURES))
    fi
}

request_status() {
    local output_file="$1"
    shift
    curl --noproxy '*' -s -o "$output_file" -w '%{http_code}' "$@"
}

discover_account_ids() {
    if [[ -n "$FROM_ACCOUNT_ID" && -n "$TO_ACCOUNT_ID" ]]; then
        print_success "Using provided account IDs: from=$FROM_ACCOUNT_ID to=$TO_ACCOUNT_ID"
        return 0
    fi

    if ! start_account_discovery; then
        print_error "Account discovery failed: service authentication or port-forward unavailable"
        ((++FAILURES))
        return 1
    fi
    print_step "Discovering valid account IDs..."
    local status_code
    local accounts_file="$TMP_DIR/accounts.json"
    status_code=$(request_status "$accounts_file" \
        -H "Authorization: Bearer ${DISCOVERY_TOKEN}" \
        "http://127.0.0.1:${DISCOVERY_LOCAL_PORT}/api/v1/accounts") || status_code="000"
    record_result "Direct account list with internal token" "200" "$status_code"

    if [[ "$status_code" != "200" ]]; then
        return 1
    fi

    if ! jq -e 'type == "array" and all(.[];
        (.accountId | type == "number" and . > 0 and . == floor) and
        (.accountBalance | type == "number"))' "$accounts_file" >/dev/null 2>&1; then
        print_error "Account discovery failed: expected an array of accounts with numeric IDs and balances"
        ((++FAILURES))
        return 1
    fi
    if [[ $(jq 'length' "$accounts_file") -lt 2 ]]; then
        print_error "Account discovery needs at least two existing accounts; verify account data"
        ((++FAILURES))
        return 1
    fi
    if [[ -n "$FROM_ACCOUNT_ID" ]] && ! jq -e --argjson id "$FROM_ACCOUNT_ID" \
        'any(.[]; .accountId == $id and .accountBalance > 1)' "$accounts_file" >/dev/null; then
        print_error "Source account $FROM_ACCOUNT_ID is not available in the account service or its balance is not greater than 1"
        ((++FAILURES))
        return 1
    fi
    if [[ -n "$TO_ACCOUNT_ID" ]] && ! jq -e --argjson id "$TO_ACCOUNT_ID" \
        'any(.[]; .accountId == $id)' "$accounts_file" >/dev/null; then
        print_error "Destination account $TO_ACCOUNT_ID is not available in the account service"
        ((++FAILURES))
        return 1
    fi

    if [[ -z "$FROM_ACCOUNT_ID" ]]; then
        FROM_ACCOUNT_ID=$(jq -r --argjson to "${TO_ACCOUNT_ID:-0}" \
            '[.[] | select(.accountBalance > 1 and .accountId != $to) | .accountId][0] // empty' \
            "$accounts_file")
    fi

    if [[ -z "$TO_ACCOUNT_ID" ]]; then
        TO_ACCOUNT_ID=$(jq -r --argjson from "${FROM_ACCOUNT_ID:-0}" \
            '[.[] | select(.accountId != $from) | .accountId][0] // empty' \
            "$accounts_file")
    fi

    if [[ -z "$FROM_ACCOUNT_ID" || -z "$TO_ACCOUNT_ID" ]]; then
        print_error "Could not discover two distinct accounts, including a source with balance greater than 1"
        ((++FAILURES))
        return 1
    fi

    print_success "Discovered account IDs: from=$FROM_ACCOUNT_ID to=$TO_ACCOUNT_ID"
}

run_smoke_tests() {
    print_header "Running Smoke Tests"

    local status_code

    status_code=$(request_status "$TMP_DIR/metadata.json" \
        "${GATEWAY_URL}/.well-known/oauth-authorization-server")
    record_result "Authorization metadata without token" "200" "$status_code"

    status_code=$(request_status "$TMP_DIR/jwks.json" \
        "${GATEWAY_URL}/oauth2/jwks")
    record_result "Authorization JWK set without token" "200" "$status_code"
    if [[ "$status_code" == "200" ]]; then
        local signing_key_id
        signing_key_id=$(jq -r '.keys[0].kid // empty' "$TMP_DIR/jwks.json")
        if [[ -n "$signing_key_id" ]]; then
            print_success "Authorization JWK set exposes a signing key id"
        else
            print_error "Authorization JWK set did not expose a signing key id"
            ((++FAILURES))
        fi
    fi

    status_code=$(request_status "$TMP_DIR/creditscore-anon.json" \
        "${GATEWAY_URL}/api/v1/creditscore")
    record_result "Creditscore without token" "401" "$status_code"

    status_code=$(request_status "$TMP_DIR/creditscore-read.json" \
        -H "Authorization: Bearer ${READ_TOKEN}" \
        "${GATEWAY_URL}/api/v1/creditscore")
    record_result "Creditscore with read token" "200" "$status_code"

    status_code=$(request_status "$TMP_DIR/user-api.json" \
        "${GATEWAY_URL}/user/api/v1/ping")
    record_result "Azn-server user API not externally routed" "404" "$status_code"

    status_code=$(request_status "$TMP_DIR/internal-journal.json" \
        -X POST \
        -H "Authorization: Bearer ${READ_TOKEN}" \
        -H "Content-Type: application/json" \
        -d '{"journalId":999999999,"accountId":1,"journalType":"DEPOSIT","journalAmount":1}' \
        "${GATEWAY_URL}/api/v1/account/journal")
    record_result "Internal account journal route with read token" "403" "$status_code"

    status_code=$(request_status "$TMP_DIR/accounts-public.json" \
        -H "Authorization: Bearer ${READ_TOKEN}" \
        "${GATEWAY_URL}/api/v1/accounts") || status_code="000"
    record_result "Public account list with read token" "200" "$status_code"

    if ! discover_account_ids; then
        print_warning "Skipping deposit and transfer checks: valid account IDs unavailable"
        return 0
    fi

    if [[ "$READ_ONLY" == true ]]; then
        print_warning "Read-only mode: skipping deposit and transfer workflow tests"
        return 0
    fi

    status_code=$(request_status "$TMP_DIR/deposit-read.json" \
        -X POST \
        -H "Authorization: Bearer ${READ_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{\"accountId\":${TO_ACCOUNT_ID},\"amount\":1}" \
        "${GATEWAY_URL}/api/v1/testrunner/deposit")
    record_result "Testrunner deposit with read token" "403" "$status_code"

    status_code=$(request_status "$TMP_DIR/deposit-test.json" \
        -X POST \
        -H "Authorization: Bearer ${TEST_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{\"accountId\":${TO_ACCOUNT_ID},\"amount\":1}" \
        "${GATEWAY_URL}/api/v1/testrunner/deposit")
    record_result "Testrunner deposit with test token" "201" "$status_code"

    status_code=$(request_status "$TMP_DIR/transfer.json" \
        -X POST \
        -H "Authorization: Bearer ${TRANSFER_TOKEN}" \
        "${GATEWAY_URL}/transfer?fromAccount=${FROM_ACCOUNT_ID}&toAccount=${TO_ACCOUNT_ID}&amount=1")
    record_result "Transfer with client credentials owner-blocked" "403" "$status_code"
}

# =============================================================================
# Main
# =============================================================================
main() {
    print_header "CloudBank v5 Secure Services Smoke Test"

    parse_args "$@"

    local account_id
    for account_id in "$FROM_ACCOUNT_ID" "$TO_ACCOUNT_ID"; do
        if [[ -n "$account_id" && ! "$account_id" =~ ^[1-9][0-9]*$ ]]; then
            print_error "Account IDs must be positive integers"
            exit 1
        fi
    done
    if [[ -n "$FROM_ACCOUNT_ID" && "$FROM_ACCOUNT_ID" == "$TO_ACCOUNT_ID" ]]; then
        print_error "Source and destination account IDs must be distinct"
        exit 1
    fi
    if [[ -z "$FROM_ACCOUNT_ID" || -z "$TO_ACCOUNT_ID" ]]; then
        if [[ ! "$DISCOVERY_LOCAL_PORT" =~ ^[1-9][0-9]{0,4}$ ]] || \
            ((DISCOVERY_LOCAL_PORT > 65535)); then
            print_error "Account discovery local port must be between 1 and 65535"
            exit 1
        fi
        if [[ -z "$GATEWAY_URL" && "$DISCOVERY_LOCAL_PORT" == "$LOCAL_PORT" ]]; then
            print_error "Gateway and account discovery local ports must be different"
            exit 1
        fi
    fi
    TMP_DIR=$(umask 077; mktemp -d "${TMPDIR:-/tmp}/cloudbank-smoke.XXXXXX")

    if [[ -z "$NAMESPACE" || -z "$DB_NAME" ]]; then
        echo "Please provide the following configuration values."
        echo ""
        prompt_value NAMESPACE "Kubernetes namespace" "obaas-dev"
        prompt_value DB_NAME "Database name" "obaas"
    fi

    if ! check_prerequisites; then
        exit 1
    fi

    if [[ -z "$OBAAS_RELEASE" ]]; then
        print_step "Auto-detecting OBaaS release..."
        if prereq_check_obaas_release "$NAMESPACE"; then
            OBAAS_RELEASE="$PREREQ_OBAAS_RELEASE"
        else
            print_error "Could not auto-detect OBaaS release. Use -o/--obaas-release to specify."
            exit 1
        fi
    fi

    if [[ -z "$GATEWAY_URL" ]]; then
        start_gateway_port_forward
    else
        GATEWAY_URL="${GATEWAY_URL%/}"
        print_success "Using gateway URL: $GATEWAY_URL"
    fi

    get_client_secret
    get_tokens
    run_smoke_tests

    print_header "Summary"
    if [[ "$FAILURES" -eq 0 ]]; then
        print_success "Secure services smoke test passed"
    else
        print_error "Secure services smoke test failed: $FAILURES failure(s)"
        exit 1
    fi
}

main "$@"
