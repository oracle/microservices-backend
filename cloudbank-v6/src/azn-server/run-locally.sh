#!/usr/bin/env bash

# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at
# https://oss.oracle.com/licenses/upl.

set -euo pipefail
set +x

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly ENV_FILE="$REPOSITORY_ROOT/.env"

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

    if [[ ! -t 0 ]]; then
        die "Set $variable_name or run this script interactively"
    fi

    printf '%s: ' "$label" >&2
    IFS= read -r -s value
    printf '\n' >&2

    if [[ -z "$value" ]]; then
        die "$variable_name must not be empty"
    fi

    printf -v "$variable_name" '%s' "$value"
    export "$variable_name"
}

validate_env_file() {
    [[ -f "$ENV_FILE" ]] || return

    awk '
        /^[[:space:]]*($|#)/ { next }
        /^[A-Za-z_][A-Za-z0-9_]*=.*/ { next }
        { exit 1 }
    ' "$ENV_FILE" || die "$ENV_FILE must contain only KEY=value entries or comments"
}

env_file_count() {
    local variable_name="$1"

    awk -F= -v variable_name="$variable_name" \
        '$1 == variable_name { count++ } END { print count + 0 }' "$ENV_FILE"
}

env_file_value() {
    local variable_name="$1"

    awk -F= -v variable_name="$variable_name" \
        '$1 == variable_name { print substr($0, index($0, "=") + 1) }' "$ENV_FILE"
}

load_env_file_value() {
    local source_name="$1"
    local target_name="${2:-$1}"
    local count
    local value

    [[ -n "${!target_name-}" || ! -f "$ENV_FILE" ]] && return

    count="$(env_file_count "$source_name")"
    [[ "$count" -le 1 ]] || die "$ENV_FILE must contain at most one $source_name entry"
    [[ "$count" -eq 1 ]] || return

    value="$(env_file_value "$source_name")"
    [[ "$value" != *$'\r'* ]] || die "$ENV_FILE variable $source_name contains a carriage return"
    printf -v "$target_name" '%s' "$value"
    export "$target_name"
}

command -v mvn >/dev/null 2>&1 || die "Maven is required (command: mvn)"

validate_env_file
load_env_file_value ORACLE_HOST_PORT
load_env_file_value ORACLE_SERVICE_NAME
load_env_file_value ORACLE_ADMIN_USERNAME
load_env_file_value ORACLE_PASSWORD AZN_LIQUIBASE_PASSWORD
load_env_file_value AZN_USER_REPO_PASSWORD
load_env_file_value AZN_USER_REPO_OWNER_PASSWORD
load_env_file_value AZN_BOOTSTRAP_USERS_ADMIN_PASSWORD
load_env_file_value AZN_BOOTSTRAP_USERS_USER_PASSWORD
load_env_file_value AZN_AUTHORIZATION_SERVER_DEFAULT_CLIENT_SECRET
load_env_file_value AZN_AUTHORIZATION_SERVER_SERVICE_CLIENT_SECRET
load_env_file_value AZN_AUTHORIZATION_SERVER_DOCUMENT_INGEST_CLIENT_SECRET
load_env_file_value AZN_AUTHORIZATION_SERVER_DOCUMENT_REVIEW_CLIENT_SECRET
load_env_file_value AZN_AUTHORIZATION_SERVER_AI_AGENT_CLIENT_SECRET
load_env_file_value AZN_AUTHORIZATION_SERVER_MICROTX_CLIENT_SECRET

export AZN_DATASOURCE_URL="${AZN_DATASOURCE_URL:-jdbc:oracle:thin:@//localhost:${ORACLE_HOST_PORT:-1521}/${ORACLE_SERVICE_NAME:-freepdb1}}"

if [[ -t 0 ]] && { [[ -z "${AZN_USER_REPO_PASSWORD-}" ]] || [[ -z "${AZN_USER_REPO_OWNER_PASSWORD-}" ]]; }; then
    printf '%s\n' \
        'Database security uses two accounts: USER_REPO owns the schema and is locked after provisioning;' \
        'USER_REPO_APP is the least-privilege account used while azn-server is running.' \
        'Their passwords must differ. Input is hidden and is not saved by this script.'
fi

prompt_secret_if_missing AZN_USER_REPO_PASSWORD "USER_REPO_APP runtime password"
prompt_secret_if_missing AZN_USER_REPO_OWNER_PASSWORD "Locked USER_REPO owner password (must be different)"

if [[ "$AZN_USER_REPO_PASSWORD" == "$AZN_USER_REPO_OWNER_PASSWORD" ]]; then
    die "AZN_USER_REPO_OWNER_PASSWORD must differ from AZN_USER_REPO_PASSWORD"
fi

export AZN_LIQUIBASE_URL="${AZN_LIQUIBASE_URL:-$AZN_DATASOURCE_URL}"
export AZN_LIQUIBASE_USERNAME="${AZN_LIQUIBASE_USERNAME:-${ORACLE_ADMIN_USERNAME:-SYSTEM}}"
prompt_secret_if_missing AZN_LIQUIBASE_PASSWORD "$AZN_LIQUIBASE_USERNAME database password"

prompt_secret_if_missing AZN_BOOTSTRAP_USERS_ADMIN_PASSWORD "Bootstrap obaas-admin password"
prompt_secret_if_missing AZN_BOOTSTRAP_USERS_USER_PASSWORD "Bootstrap demo-user password"

export AZN_AUTHORIZATION_SERVER_DEFAULT_CLIENT_ENABLED=true
export AZN_AUTHORIZATION_SERVER_DEFAULT_CLIENT_ID="${AZN_AUTHORIZATION_SERVER_DEFAULT_CLIENT_ID:-cloudbank-client}"
prompt_secret_if_missing AZN_AUTHORIZATION_SERVER_DEFAULT_CLIENT_SECRET "Browser/BFF OAuth client secret"
prompt_secret_if_missing AZN_AUTHORIZATION_SERVER_SERVICE_CLIENT_SECRET "Service OAuth client secret"
prompt_secret_if_missing AZN_AUTHORIZATION_SERVER_DOCUMENT_INGEST_CLIENT_SECRET \
    "Document ingest OAuth client secret"
prompt_secret_if_missing AZN_AUTHORIZATION_SERVER_DOCUMENT_REVIEW_CLIENT_SECRET \
    "Document review OAuth client secret"
prompt_secret_if_missing AZN_AUTHORIZATION_SERVER_AI_AGENT_CLIENT_SECRET \
    "AI agent OAuth client secret"
prompt_secret_if_missing AZN_AUTHORIZATION_SERVER_MICROTX_CLIENT_SECRET \
    "MicroTx Workflow OAuth client secret"

cd "$SCRIPT_DIR"
exec mvn spring-boot:run
