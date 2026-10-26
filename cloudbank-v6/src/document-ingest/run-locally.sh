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
    [[ -n "$value" ]] && return
    [[ -t 0 ]] || die "Set $variable_name or run this script interactively"
    printf '%s: ' "$label" >&2
    IFS= read -r -s value
    printf '\n' >&2
    [[ -n "$value" ]] || die "$label must not be empty"
    printf -v "$variable_name" '%s' "$value"
    export "$variable_name"
}

check_url() {
    local label="$1"
    local url="$2"
    curl --silent --show-error --fail --connect-timeout 3 --max-time 10 "$url" >/dev/null ||
        die "$label is unavailable at $url"
}

validate_http_url() {
    local variable_name="$1"
    local value="${!variable_name}"
    case "$value" in
        http://* | https://*) ;;
        *) die "$variable_name must start with http:// or https://" ;;
    esac
}

command -v curl >/dev/null 2>&1 || die "curl is required"
command -v mvn >/dev/null 2>&1 || die "Maven is required (command: mvn)"

export PORT="${PORT:-8082}"
[[ "$PORT" =~ ^[0-9]+$ ]] && [[ "$PORT" -ge 1 && "$PORT" -le 65535 ]] ||
    die "PORT must be an integer from 1 to 65535"

export DOCUMENT_INGEST_DATASOURCE_URL="${DOCUMENT_INGEST_DATASOURCE_URL:-jdbc:oracle:thin:@//localhost:1521/freepdb1}"
export DOCUMENT_INGEST_DATASOURCE_USERNAME="${DOCUMENT_INGEST_DATASOURCE_USERNAME:-CB_DOCUMENT_INGEST_APP}"
export DOCUMENT_INGEST_SCHEMA="${DOCUMENT_INGEST_SCHEMA:-CLOUDBANK}"
export AZN_ISSUER_URI="${AZN_ISSUER_URI:-http://127.0.0.1:8080}"
AZN_ISSUER_URI="${AZN_ISSUER_URI%/}"
export AZN_ISSUER_URI
export AZN_JWK_SET_URI="${AZN_JWK_SET_URI:-$AZN_ISSUER_URI/oauth2/jwks}"
export DOCUMENT_INGEST_TOKEN_URI="${DOCUMENT_INGEST_TOKEN_URI:-$AZN_ISSUER_URI/oauth2/token}"
export DOCUMENT_INGEST_CLIENT_ID="${DOCUMENT_INGEST_CLIENT_ID:-cloudbank-document-ingest-client}"
export DOCUMENT_INGEST_CALLER_CLIENT_IDS="${DOCUMENT_INGEST_CALLER_CLIENT_IDS:-cloudbank-service-client}"
export LOAN_APPLICATION_BASE_URL="${LOAN_APPLICATION_BASE_URL:-http://127.0.0.1:8081}"
LOAN_APPLICATION_BASE_URL="${LOAN_APPLICATION_BASE_URL%/}"
export LOAN_APPLICATION_BASE_URL

[[ "$DOCUMENT_INGEST_DATASOURCE_USERNAME" =~ $ORACLE_USERNAME_PATTERN ]] ||
    die "DOCUMENT_INGEST_DATASOURCE_USERNAME must be a valid Oracle username"
[[ "$DOCUMENT_INGEST_SCHEMA" =~ $ORACLE_USERNAME_PATTERN ]] ||
    die "DOCUMENT_INGEST_SCHEMA must be a valid Oracle schema name"
validate_http_url AZN_ISSUER_URI
validate_http_url AZN_JWK_SET_URI
validate_http_url DOCUMENT_INGEST_TOKEN_URI
validate_http_url LOAN_APPLICATION_BASE_URL

if [[ -t 0 ]] && { [[ -z "${DOCUMENT_INGEST_DATASOURCE_PASSWORD-}" ]] ||
                    [[ -z "${DOCUMENT_INGEST_CLIENT_SECRET-}" ]]; }; then
    printf '%s\n' \
        'document-ingest-service uses a least-privilege Oracle account for extraction results' \
        'and a separate OAuth client to retrieve authorized PDFs from loan-application-service.' \
        'Input is hidden and is not saved by this script.'
fi
prompt_secret_if_missing DOCUMENT_INGEST_DATASOURCE_PASSWORD \
    "$DOCUMENT_INGEST_DATASOURCE_USERNAME runtime password"
prompt_secret_if_missing DOCUMENT_INGEST_CLIENT_SECRET \
    "$DOCUMENT_INGEST_CLIENT_ID OAuth client secret"

printf 'Checking azn-server and loan-application-service...\n'
check_url "azn-server metadata" "$AZN_ISSUER_URI/.well-known/openid-configuration"
check_url "azn-server JWKS" "$AZN_JWK_SET_URI"
check_url "loan-application-service health" "$LOAN_APPLICATION_BASE_URL/actuator/health"

printf '%s\n' \
    "Starting document-ingest-service on port $PORT" \
    "  Database identity: $DOCUMENT_INGEST_DATASOURCE_USERNAME" \
    "  Authorization issuer: $AZN_ISSUER_URI" \
    "  Loan application service: $LOAN_APPLICATION_BASE_URL"

cd "$SCRIPT_DIR"
exec mvn spring-boot:run
