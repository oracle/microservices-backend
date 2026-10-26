#!/usr/bin/env bash

# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at
# https://oss.oracle.com/licenses/upl.

set -euo pipefail
set +x

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly ENV_FILE="$REPOSITORY_ROOT/.env"
readonly LOCAL_WALLET_ROOT="$REPOSITORY_ROOT/.cloudbank-local/adb-wallets"

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 2
}

set_value_source() {
    local variable_name="$1"
    local source="$2"

    printf -v "CONFIG_SOURCE_$variable_name" '%s' "$source"
}

value_source() {
    local variable_name="$1"
    local source_variable="CONFIG_SOURCE_$variable_name"

    printf '%s' "${!source_variable-unknown}"
}

validate_env_file() {
    [[ -f "$ENV_FILE" ]] || return 0

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
    local variable_name="$1"
    local count
    local value

    if [[ -n "${!variable_name-}" ]]; then
        set_value_source "$variable_name" environment
        return
    fi

    [[ -f "$ENV_FILE" ]] || return
    count="$(env_file_count "$variable_name")"
    [[ "$count" -le 1 ]] || die "$ENV_FILE must contain at most one $variable_name entry"
    [[ "$count" -eq 1 ]] || return 0

    value="$(env_file_value "$variable_name")"
    [[ "$value" != *$'\r'* ]] || die "$ENV_FILE variable $variable_name contains a carriage return"
    printf -v "$variable_name" '%s' "$value"
    export "$variable_name"
    set_value_source "$variable_name" .env
}

prompt_value() {
    local variable_name="$1"
    local label="$2"
    local value="${!variable_name-}"

    [[ -n "$value" ]] && return
    [[ -t 0 ]] || die "Set $variable_name or run this script interactively"
    printf '%s: ' "$label" >&2
    IFS= read -r value
    [[ -n "$value" ]] || die "$variable_name must not be empty"
    printf -v "$variable_name" '%s' "$value"
    export "$variable_name"
    set_value_source "$variable_name" interactive-input
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
    [[ -n "$value" ]] || die "$variable_name must not be empty"
    printf -v "$variable_name" '%s' "$value"
    export "$variable_name"
    set_value_source "$variable_name" interactive-input
}

expand_home_directory() {
    local path="$1"

    if [[ "$path" == '~/'* ]]; then
        printf '%s/%s\n' "$HOME" "${path:2}"
    else
        printf '%s\n' "$path"
    fi
}

validate_wallet_archive() {
    local archive="$1"

    unzip -Z1 "$archive" | awk '
        /^\// || /(^|\/)\.\.?(\/|$)/ { exit 1 }
    ' || die "Wallet archive contains an unsafe path"
}

resolve_wallet_directory() {
    local wallet_source="$1"
    local wallet_name
    local extracted_wallet_directory

    wallet_source="$(expand_home_directory "$wallet_source")"
    if [[ -d "$wallet_source" ]]; then
        cd "$wallet_source" && pwd
        return
    fi

    [[ -f "$wallet_source" ]] || die "Wallet path does not exist: $wallet_source"
    [[ "$wallet_source" == *.zip ]] || die "Wallet path must be a directory or a .zip archive"
    command -v unzip >/dev/null 2>&1 || die "unzip is required for a wallet archive"
    validate_wallet_archive "$wallet_source"

    wallet_name="$(basename "${wallet_source%.zip}")"
    wallet_name="${wallet_name//[^A-Za-z0-9._-]/_}"
    umask 077
    mkdir -p "$LOCAL_WALLET_ROOT"
    extracted_wallet_directory="$(mktemp -d "$LOCAL_WALLET_ROOT/${wallet_name}.XXXXXX")"
    unzip -qq "$wallet_source" -d "$extracted_wallet_directory"
    find "$extracted_wallet_directory" -type d -exec chmod 700 {} +
    find "$extracted_wallet_directory" -type f -exec chmod 600 {} +
    printf '%s\n' "$extracted_wallet_directory"
}

validate_wallet_directory() {
    local wallet_directory="$1"
    local required_file

    [[ "$wallet_directory" != *[[:space:]]* ]] ||
        die "Wallet directory must not contain whitespace for the JDBC URL"
    for required_file in tnsnames.ora sqlnet.ora cwallet.sso; do
        [[ -r "$wallet_directory/$required_file" ]] ||
            die "Wallet directory is missing readable $required_file"
    done
}

list_tns_aliases() {
    local wallet_directory="$1"

    awk -F= '
        /^[[:space:]]*[A-Za-z0-9_]+[[:space:]]*=/ {
            alias = $1
            gsub(/[[:space:]]/, "", alias)
            print alias
        }
    ' "$wallet_directory/tnsnames.ora"
}

validate_adb_password() {
    local variable_name="$1"
    local value="${!variable_name}"

    [[ ${#value} -ge 12 && ${#value} -le 30 ]] ||
        die "$variable_name must be 12 to 30 characters for Autonomous Database"
}

print_secret_status() {
    local variable_name="$1"

    printf '  %-33s %s (%s)\n' "$variable_name:" '<set; value masked>' "$(value_source "$variable_name")"
}

confirm_launch() {
    local confirmation

    [[ -t 0 ]] || return
    printf 'Start azn-server with this configuration? [y/N]: ' >&2
    IFS= read -r confirmation
    case "$confirmation" in
        y|Y|yes|YES|Yes) ;;
        *) die "Launch cancelled" ;;
    esac
}

validate_env_file
for config_variable in \
    AZN_ADB_WALLET_PATH \
    AZN_ADB_TNS_ALIAS \
    AZN_LIQUIBASE_PASSWORD \
    AZN_USER_REPO_OWNER_PASSWORD \
    AZN_USER_REPO_PASSWORD; do
    load_env_file_value "$config_variable"
done

prompt_value AZN_ADB_WALLET_PATH "Wallet ZIP or extracted wallet directory"
wallet_directory="$(resolve_wallet_directory "$AZN_ADB_WALLET_PATH")"
export AZN_ADB_WALLET_PATH="$wallet_directory"
validate_wallet_directory "$wallet_directory"

tns_aliases=()
while IFS= read -r tns_alias; do
    tns_aliases+=("$tns_alias")
done < <(list_tns_aliases "$wallet_directory")
[[ ${#tns_aliases[@]} -gt 0 ]] || die "No TNS aliases found in $wallet_directory/tnsnames.ora"
printf 'Available ADB service aliases:\n' >&2
printf '  %s\n' "${tns_aliases[@]}" >&2
prompt_value AZN_ADB_TNS_ALIAS "ADB service alias"
printf '%s\n' "${tns_aliases[@]}" | grep -Fqx "$AZN_ADB_TNS_ALIAS" ||
    die "ADB service alias is not present in this wallet: $AZN_ADB_TNS_ALIAS"

prompt_secret_if_missing AZN_LIQUIBASE_PASSWORD "ADB ADMIN password"
prompt_secret_if_missing AZN_USER_REPO_OWNER_PASSWORD "USER_REPO owner password"
prompt_secret_if_missing AZN_USER_REPO_PASSWORD "USER_REPO_APP runtime password"
validate_adb_password AZN_USER_REPO_OWNER_PASSWORD
validate_adb_password AZN_USER_REPO_PASSWORD
[[ "$AZN_USER_REPO_OWNER_PASSWORD" != "$AZN_USER_REPO_PASSWORD" ]] ||
    die "AZN_USER_REPO_OWNER_PASSWORD must differ from AZN_USER_REPO_PASSWORD"

export AZN_DATASOURCE_URL="jdbc:oracle:thin:@${AZN_ADB_TNS_ALIAS}?TNS_ADMIN=${wallet_directory}"
export AZN_LIQUIBASE_URL="$AZN_DATASOURCE_URL"
export AZN_LIQUIBASE_USERNAME=ADMIN

printf '%s\n' \
    'ADB launch configuration:' \
    "  Wallet directory: $wallet_directory ($(value_source AZN_ADB_WALLET_PATH))" \
    "  Service alias: $AZN_ADB_TNS_ALIAS ($(value_source AZN_ADB_TNS_ALIAS))" \
    "  Datasource URL: $AZN_DATASOURCE_URL" \
    "  Liquibase URL: $AZN_LIQUIBASE_URL" \
    '  Liquibase user: ADMIN' \
    '  Runtime user: USER_REPO_APP'
print_secret_status AZN_LIQUIBASE_PASSWORD
print_secret_status AZN_USER_REPO_OWNER_PASSWORD
print_secret_status AZN_USER_REPO_PASSWORD
confirm_launch

exec "$SCRIPT_DIR/run-locally.sh"
