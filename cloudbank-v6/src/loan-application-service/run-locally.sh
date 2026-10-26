#!/usr/bin/env bash

# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at
# https://oss.oracle.com/licenses/upl.

set -euo pipefail
set +x

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ORACLE_USERNAME_PATTERN='^[A-Za-z][A-Za-z0-9_$#]{0,127}$'

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 2
}

prompt_secret_if_missing() {
    local variable_name="$1"
    local label="$2"
    local value="${!variable_name-}"

    if [[ -n "$value" ]]; then
        return
    fi

    [[ -t 0 ]] || die "Set $variable_name or run this script interactively"
    printf '%s: ' "$label" >&2
    IFS= read -r -s value
    printf '\n' >&2
    [[ -n "$value" ]] || die "$label must not be empty"

    printf -v "$variable_name" '%s' "$value"
    export "$variable_name"
}

require_setting() {
    local variable_name="$1"
    local purpose="$2"
    [[ -n "${!variable_name-}" ]] || die "Set $variable_name for $purpose"
}

validate_http_url() {
    local variable_name="$1"
    local value="${!variable_name}"
    case "$value" in
        http://* | https://*) ;;
        *) die "$variable_name must start with http:// or https://" ;;
    esac
}

check_authorization_server() {
    local metadata
    local jwks

    if ! metadata="$(curl --silent --show-error --fail \
            --connect-timeout 3 --max-time 10 \
            "$AZN_ISSUER_URI/.well-known/openid-configuration")"; then
        die "azn-server metadata is unavailable at $AZN_ISSUER_URI; start azn-server on port 8080 first"
    fi
    printf '%s' "$metadata" | grep -q '"issuer"' ||
        die "azn-server metadata did not contain an issuer"
    printf '%s' "$metadata" | grep -Fq "$AZN_ISSUER_URI" ||
        die "azn-server metadata issuer does not match AZN_ISSUER_URI=$AZN_ISSUER_URI"

    if ! jwks="$(curl --silent --show-error --fail \
            --connect-timeout 3 --max-time 10 "$AZN_JWK_SET_URI")"; then
        die "azn-server JWKS is unavailable at $AZN_JWK_SET_URI"
    fi
    printf '%s' "$jwks" | grep -q '"keys"' ||
        die "azn-server JWKS response did not contain signing keys"
}

command -v curl >/dev/null 2>&1 || die "curl is required"
command -v grep >/dev/null 2>&1 || die "grep is required"
command -v mvn >/dev/null 2>&1 || die "Maven is required (command: mvn)"

export PORT="${PORT:-8081}"
[[ "$PORT" =~ ^[0-9]+$ ]] && [[ "$PORT" -ge 1 && "$PORT" -le 65535 ]] ||
    die "PORT must be an integer from 1 to 65535"

export LOAN_DATASOURCE_URL="${LOAN_DATASOURCE_URL:-jdbc:oracle:thin:@//localhost:1521/freepdb1}"
export LOAN_DATASOURCE_USERNAME="${LOAN_DATASOURCE_USERNAME:-CB_LOAN_APPLICATION_APP}"
export LOAN_SCHEMA="${LOAN_SCHEMA:-CLOUDBANK}"
[[ "$LOAN_DATASOURCE_USERNAME" =~ $ORACLE_USERNAME_PATTERN ]] ||
    die "LOAN_DATASOURCE_USERNAME must be a valid Oracle username"
[[ "$LOAN_SCHEMA" =~ $ORACLE_USERNAME_PATTERN ]] ||
    die "LOAN_SCHEMA must be a valid Oracle schema name"

if [[ -t 0 && -z "${LOAN_DATASOURCE_PASSWORD-}" ]]; then
    printf '%s\n' \
        'loan-application-service connects with the least-privilege CB_LOAN_APPLICATION_APP account.' \
        'The CLOUDBANK schema owner remains locked and is not needed for normal startup.' \
        'Input is hidden and is not saved by this script.'
fi
prompt_secret_if_missing LOAN_DATASOURCE_PASSWORD "$LOAN_DATASOURCE_USERNAME runtime password"

export AZN_ISSUER_URI="${AZN_ISSUER_URI:-http://127.0.0.1:8080}"
AZN_ISSUER_URI="${AZN_ISSUER_URI%/}"
export AZN_ISSUER_URI
export AZN_JWK_SET_URI="${AZN_JWK_SET_URI:-$AZN_ISSUER_URI/oauth2/jwks}"
export AZN_AUDIENCE="${AZN_AUDIENCE:-cloudbank-api}"
export LOAN_INTERNAL_CLIENT_IDS="${LOAN_INTERNAL_CLIENT_IDS:-cloudbank-service-client,cloudbank-document-ingest-client}"
export EUREKA_CLIENT_ENABLED="${EUREKA_CLIENT_ENABLED:-false}"
validate_http_url AZN_ISSUER_URI
validate_http_url AZN_JWK_SET_URI

# This selects the dispatch backend. DEFERRED is an intake request start mode,
# not a service backend; the smoke test uses DEFERRED requests by default.
export WORKFLOW_MODE="${WORKFLOW_MODE:-fake}"
export MICROTX_WORKFLOW_NAME="${MICROTX_WORKFLOW_NAME:-cloudbank-loan-origination}"
case "$WORKFLOW_MODE" in
    fake)
        ;;
    microtx)
        require_setting MICROTX_WORKFLOW_URL "MicroTx workflow dispatch"
        require_setting MICROTX_TOKEN_URI "MicroTx OAuth token acquisition"
        export MICROTX_CLIENT_ID="${MICROTX_CLIENT_ID:-microtx-workflow-client}"
        export MICROTX_SCOPE="${MICROTX_SCOPE:-microtx.workflow}"
        prompt_secret_if_missing MICROTX_CLIENT_SECRET "MicroTx OAuth client secret"
        export WORKFLOW_TASK_TOKEN_URI="${WORKFLOW_TASK_TOKEN_URI:-$MICROTX_TOKEN_URI}"
        export WORKFLOW_TASK_CLIENT_ID="${WORKFLOW_TASK_CLIENT_ID:-cloudbank-service-client}"
        export WORKFLOW_TASK_SCOPE="${WORKFLOW_TASK_SCOPE:-cloudbank.internal}"
        prompt_secret_if_missing WORKFLOW_TASK_CLIENT_SECRET "Workflow task OAuth client secret"
        validate_http_url MICROTX_WORKFLOW_URL
        validate_http_url MICROTX_TOKEN_URI
        validate_http_url WORKFLOW_TASK_TOKEN_URI
        ;;
    deferred)
        die "WORKFLOW_MODE=deferred is not a service backend; use WORKFLOW_MODE=fake and send workflowStartMode=DEFERRED in the intake request"
        ;;
    *)
        die "WORKFLOW_MODE must be fake or microtx"
        ;;
esac

printf 'Checking azn-server metadata and signing keys at %s...\n' "$AZN_ISSUER_URI"
check_authorization_server

printf '%s\n' \
    "Starting loan-application-service on port $PORT" \
    "  Database identity: $LOAN_DATASOURCE_USERNAME" \
    "  Schema: $LOAN_SCHEMA" \
    "  Authorization issuer: $AZN_ISSUER_URI" \
    "  Workflow backend: $WORKFLOW_MODE"
if [[ "$WORKFLOW_MODE" == "microtx" ]]; then
    if [[ -n "${MICROTX_TOKEN_URI-}" ]]; then
        printf '  MicroTx authentication: OAuth client credentials\n'
    else
        printf '  MicroTx authentication: disabled\n'
    fi
fi

cd "$SCRIPT_DIR"
exec mvn spring-boot:run
