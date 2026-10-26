#!/usr/bin/env bash

# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at
# https://oss.oracle.com/licenses/upl.

set -uo pipefail
set +x

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly SCHEMA_DIR="$REPOSITORY_ROOT/src/schema"
readonly ACCOUNT_PREPARE_SQL="$SCHEMA_DIR/admin/001-loan-application-accounts.sql"
readonly ACCOUNT_FINALIZE_SQL="$SCHEMA_DIR/admin/002-loan-application-finalize.sql"
readonly VERIFY_SQL="$SCHEMA_DIR/verify/005-loan-application-runtime.sql"
readonly FULL_DEMO_CAPABILITIES_SQL="$SCHEMA_DIR/verify/000-full-demo-capabilities.sql"
readonly FULL_DEMO_VERIFY_SQL="$SCHEMA_DIR/verify/006-full-demo.sql"
readonly CHANGELOG_FILE="$SCHEMA_DIR/changelog-root.xml"
readonly CHANGELOG_NAME="changelog-root.xml"
readonly ORACLE_USERNAME_PATTERN='^[A-Z][A-Z0-9_$#]{0,127}$'

LOAN_DB_ADMIN_USERNAME="${LOAN_DB_ADMIN_USERNAME:-SYSTEM}"
LOAN_DB_ADMIN_PASSWORD="${LOAN_DB_ADMIN_PASSWORD:-}"
LOAN_SCHEMA_OWNER_PASSWORD="${LOAN_SCHEMA_OWNER_PASSWORD:-}"
LOAN_DATASOURCE_PASSWORD="${LOAN_DATASOURCE_PASSWORD:-}"
DOCUMENT_INGEST_DATASOURCE_PASSWORD="${DOCUMENT_INGEST_DATASOURCE_PASSWORD:-}"
DOCUMENT_REVIEW_DATASOURCE_PASSWORD="${DOCUMENT_REVIEW_DATASOURCE_PASSWORD:-}"
DECISION_DATASOURCE_PASSWORD="${DECISION_DATASOURCE_PASSWORD:-}"
AI_DATASOURCE_PASSWORD="${AI_DATASOURCE_PASSWORD:-}"
GEOGRAPHIC_RISK_DATASOURCE_PASSWORD="${GEOGRAPHIC_RISK_DATASOURCE_PASSWORD:-}"
POLICY_RETRIEVAL_DATASOURCE_PASSWORD="${POLICY_RETRIEVAL_DATASOURCE_PASSWORD:-}"
POLICY_LOADER_DATASOURCE_PASSWORD="${POLICY_LOADER_DATASOURCE_PASSWORD:-}"
LOAN_SQLCL_CONNECT="${LOAN_SQLCL_CONNECT:-//localhost:1521/freepdb1}"
SCHEMA_PROFILE="${SCHEMA_PROFILE:-runtime}"
LIQUIBASE_LABEL=""
OWNER_PREPARED=false
TEMP_DIR=""

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

validate_admin_password() {
    case "$LOAN_DB_ADMIN_PASSWORD" in
        *$'\n'* | *$'\r'* | *'"'*)
            die "LOAN_DB_ADMIN_PASSWORD cannot contain a quote or newline when used by this SQLcl helper"
            ;;
    esac
}

validate_schema_password() {
    local variable_name="$1"
    local label="$2"
    local value="${!variable_name}"

    if [[ ${#value} -lt 12 || ${#value} -gt 128 ||
          ! "$value" =~ ^[A-Za-z0-9#!?$%\^*_-]+$ ||
          ! "$value" =~ [A-Z] || ! "$value" =~ [a-z] ||
          ! "$value" =~ [0-9] || ! "$value" =~ [#!?$%\^*_-] ]]; then
        die "$label must be 12-128 characters with upper, lower, number, and one of # ! ? $ % ^ * _ -"
    fi
}

report_sqlcl_result() {
    local exit_status="$1"
    local output="$2"

    printf '%s\n' "$output"
    [[ "$exit_status" -eq 0 ]] || return 1
    if printf '%s\n' "$output" | grep -Eq \
        'Connection failed|Not connected|(^|[[:space:]])(ORA|SP2)-[0-9]+|(^|[[:space:]])ERROR:|Unexpected error|Validation Failed|Error running Liquibase|Processing has failed|liquibase\.exception'; then
        return 1
    fi
}

run_account_prepare() {
    local output
    local exit_status
    local geographic_password_arg="$GEOGRAPHIC_RISK_DATASOURCE_PASSWORD"
    local policy_password_arg="$POLICY_RETRIEVAL_DATASOURCE_PASSWORD"
    local policy_loader_password_arg="$POLICY_LOADER_DATASOURCE_PASSWORD"

    if [[ "$SCHEMA_PROFILE" != "full-demo" ]]; then
        geographic_password_arg="not_applicable"
        policy_password_arg="not_applicable"
        policy_loader_password_arg="not_applicable"
    fi

    output="$(sql -S /nolog 2>&1 <<SQL
WHENEVER OSERROR EXIT FAILURE
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET ECHO OFF
SET VERIFY OFF
SET HEADING OFF
CONNECT ${LOAN_DB_ADMIN_USERNAME}/"${LOAN_DB_ADMIN_PASSWORD}"@${LOAN_SQLCL_CONNECT}
@"${ACCOUNT_PREPARE_SQL}" ${LOAN_SCHEMA_OWNER_PASSWORD} ${LOAN_DATASOURCE_PASSWORD} ${DOCUMENT_INGEST_DATASOURCE_PASSWORD} ${SCHEMA_PROFILE} ${geographic_password_arg} ${DOCUMENT_REVIEW_DATASOURCE_PASSWORD} ${policy_password_arg} ${policy_loader_password_arg} ${DECISION_DATASOURCE_PASSWORD} ${AI_DATASOURCE_PASSWORD}
EXIT SUCCESS
SQL
    )"
    exit_status=$?
    report_sqlcl_result "$exit_status" "$output"
}

run_liquibase_update() {
    local output
    local exit_status

    output="$(
        cd "$TEMP_DIR" || exit 2
        sql -S /nolog 2>&1 <<SQL
WHENEVER OSERROR EXIT FAILURE
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET ECHO OFF
SET VERIFY OFF
CONNECT CLOUDBANK/"${LOAN_SCHEMA_OWNER_PASSWORD}"@${LOAN_SQLCL_CONNECT}
LB UPDATE -CHANGELOG-FILE ${CHANGELOG_NAME} -SEARCH-PATH "${SCHEMA_DIR}" -LABELS "${LIQUIBASE_LABEL}"
EXIT SUCCESS
SQL
    )"
    exit_status=$?
    report_sqlcl_result "$exit_status" "$output"
}

run_full_demo_capability_check() {
    local output
    local exit_status

    output="$(sql -S /nolog 2>&1 <<SQL
WHENEVER OSERROR EXIT FAILURE
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET ECHO OFF
SET VERIFY OFF
CONNECT ${LOAN_DB_ADMIN_USERNAME}/"${LOAN_DB_ADMIN_PASSWORD}"@${LOAN_SQLCL_CONNECT}
@"${FULL_DEMO_CAPABILITIES_SQL}"
EXIT SUCCESS
SQL
    )"
    exit_status=$?
    report_sqlcl_result "$exit_status" "$output"
}

run_full_demo_verification() {
    local output
    local exit_status

    output="$(sql -S /nolog 2>&1 <<SQL
WHENEVER OSERROR EXIT FAILURE
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET ECHO OFF
SET VERIFY OFF
CONNECT CLOUDBANK/"${LOAN_SCHEMA_OWNER_PASSWORD}"@${LOAN_SQLCL_CONNECT}
@"${FULL_DEMO_VERIFY_SQL}"
EXIT SUCCESS
SQL
    )"
    exit_status=$?
    report_sqlcl_result "$exit_status" "$output"
}

run_account_finalize() {
    local mode="$1"
    local output
    local exit_status

    output="$(sql -S /nolog 2>&1 <<SQL
WHENEVER OSERROR EXIT FAILURE
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET ECHO OFF
SET VERIFY OFF
SET HEADING OFF
CONNECT ${LOAN_DB_ADMIN_USERNAME}/"${LOAN_DB_ADMIN_PASSWORD}"@${LOAN_SQLCL_CONNECT}
@"${ACCOUNT_FINALIZE_SQL}" ${mode}
EXIT SUCCESS
SQL
    )"
    exit_status=$?
    report_sqlcl_result "$exit_status" "$output"
}

run_contract_verification() {
    local output
    local exit_status

    output="$(sql -S /nolog 2>&1 <<SQL
WHENEVER OSERROR EXIT FAILURE
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET ECHO OFF
SET VERIFY OFF
CONNECT ${LOAN_DB_ADMIN_USERNAME}/"${LOAN_DB_ADMIN_PASSWORD}"@${LOAN_SQLCL_CONNECT}
@"${VERIFY_SQL}"
EXIT SUCCESS
SQL
    )"
    exit_status=$?
    report_sqlcl_result "$exit_status" "$output"
}

run_runtime_credential_verification() {
    local username="$1"
    local password="$2"
    local output
    local exit_status

    output="$(sql -S /nolog 2>&1 <<SQL
WHENEVER OSERROR EXIT FAILURE
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET ECHO OFF
SET VERIFY OFF
SET HEADING OFF
SET FEEDBACK OFF
CONNECT ${username}/"${password}"@${LOAN_SQLCL_CONNECT}
SELECT 1 FROM dual;
EXIT SUCCESS
SQL
    )"
    exit_status=$?
    report_sqlcl_result "$exit_status" "$output"
}

clear_secrets() {
    LOAN_DB_ADMIN_PASSWORD=""
    LOAN_SCHEMA_OWNER_PASSWORD=""
    LOAN_DATASOURCE_PASSWORD=""
    DOCUMENT_INGEST_DATASOURCE_PASSWORD=""
    DOCUMENT_REVIEW_DATASOURCE_PASSWORD=""
    DECISION_DATASOURCE_PASSWORD=""
    AI_DATASOURCE_PASSWORD=""
    GEOGRAPHIC_RISK_DATASOURCE_PASSWORD=""
    POLICY_RETRIEVAL_DATASOURCE_PASSWORD=""
    POLICY_LOADER_DATASOURCE_PASSWORD=""
    unset LOAN_DB_ADMIN_PASSWORD LOAN_SCHEMA_OWNER_PASSWORD LOAN_DATASOURCE_PASSWORD DOCUMENT_INGEST_DATASOURCE_PASSWORD DOCUMENT_REVIEW_DATASOURCE_PASSWORD DECISION_DATASOURCE_PASSWORD AI_DATASOURCE_PASSWORD GEOGRAPHIC_RISK_DATASOURCE_PASSWORD POLICY_RETRIEVAL_DATASOURCE_PASSWORD POLICY_LOADER_DATASOURCE_PASSWORD
}

on_exit() {
    local status=$?
    trap - EXIT

    if [[ "$OWNER_PREPARED" == "true" ]]; then
        printf '\nSecuring the CLOUDBANK owner after an interrupted or failed schema update...\n' >&2
        if ! run_account_finalize CLEANUP; then
            printf 'WARNING: automatic owner cleanup failed; verify that CLOUDBANK is locked.\n' >&2
        fi
    fi

    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf -- "$TEMP_DIR"
    fi

    clear_secrets
    exit "$status"
}

trap on_exit EXIT

command -v sql >/dev/null 2>&1 || die "Oracle SQLcl is required (command: sql)"
command -v mktemp >/dev/null 2>&1 || die "mktemp is required"
command -v rm >/dev/null 2>&1 || die "rm is required"
for required_file in "$ACCOUNT_PREPARE_SQL" "$ACCOUNT_FINALIZE_SQL" "$VERIFY_SQL" "$CHANGELOG_FILE"; do
    [[ -r "$required_file" ]] || die "Required schema asset is missing: $required_file"
done

case "$SCHEMA_PROFILE" in
    runtime)
        LIQUIBASE_LABEL="loan-application-runtime"
        ;;
    full-demo)
        LIQUIBASE_LABEL="loan-application-runtime or full-demo"
        for required_file in "$FULL_DEMO_CAPABILITIES_SQL" "$FULL_DEMO_VERIFY_SQL"; do
            [[ -r "$required_file" ]] || die "Required full-demo asset is missing: $required_file"
        done
        ;;
    *) die "SCHEMA_PROFILE must be runtime or full-demo" ;;
esac

LOAN_DB_ADMIN_USERNAME="$(printf '%s' "$LOAN_DB_ADMIN_USERNAME" | tr '[:lower:]' '[:upper:]')"
[[ "$LOAN_DB_ADMIN_USERNAME" =~ $ORACLE_USERNAME_PATTERN ]] ||
    die "LOAN_DB_ADMIN_USERNAME must be a valid Oracle username"
case "$LOAN_SQLCL_CONNECT" in
    *$'\n'* | *$'\r'* | *' '*) die "LOAN_SQLCL_CONNECT cannot contain whitespace" ;;
esac
for command_name in tr; do
    command -v "$command_name" >/dev/null 2>&1 || die "$command_name is required"
done

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cloudbank-loan-db-setup.XXXXXX")" ||
    die "Unable to create a private temporary working directory"
chmod 700 "$TEMP_DIR"

NEEDS_SECRET_PROMPT=false
if [[ -z "$LOAN_DB_ADMIN_PASSWORD" ||
      -z "$LOAN_SCHEMA_OWNER_PASSWORD" ||
      -z "$LOAN_DATASOURCE_PASSWORD" ||
      -z "$DOCUMENT_INGEST_DATASOURCE_PASSWORD" ||
      -z "$DOCUMENT_REVIEW_DATASOURCE_PASSWORD" ||
      -z "$DECISION_DATASOURCE_PASSWORD" ||
      -z "$AI_DATASOURCE_PASSWORD" ]]; then
    NEEDS_SECRET_PROMPT=true
fi
if [[ "$SCHEMA_PROFILE" == "full-demo" && -z "$GEOGRAPHIC_RISK_DATASOURCE_PASSWORD" ]]; then
    NEEDS_SECRET_PROMPT=true
fi
if [[ "$SCHEMA_PROFILE" == "full-demo" && -z "$POLICY_RETRIEVAL_DATASOURCE_PASSWORD" ]]; then
    NEEDS_SECRET_PROMPT=true
fi
if [[ "$SCHEMA_PROFILE" == "full-demo" && -z "$POLICY_LOADER_DATASOURCE_PASSWORD" &&
      -n "$POLICY_RETRIEVAL_DATASOURCE_PASSWORD" ]]; then
    POLICY_LOADER_DATASOURCE_PASSWORD="$POLICY_RETRIEVAL_DATASOURCE_PASSWORD"
fi

if [[ -t 0 && "$NEEDS_SECRET_PROMPT" == "true" ]]; then
    printf '%s\n' \
        'CloudBank database setup uses these credentials:' \
        '  1. Database administrator: the existing SYSTEM password used only to create accounts and grants.' \
        '  2. CLOUDBANK owner: temporarily unlocked to run Liquibase, then stripped of migration privileges and locked.' \
        '  3. Loan runtime account: used by loan-application-service.' \
        '  4. Ingest runtime account: used only to persist extraction results.' \
        '  5. Document-review runtime account: used only by document-review-service.' \
        '  6. Decision runtime account: used only by decision-service.' \
        '  7. Geographic-risk runtime account: used by geographic-risk-service when SCHEMA_PROFILE=full-demo.' \
        '  8. Policy-retrieval runtime account: used by policy-retrieval-service when SCHEMA_PROFILE=full-demo.' \
        '  9. Policy-loader runtime account: used by the one-shot loader when SCHEMA_PROFILE=full-demo.' \
        'The CLOUDBANK owner password must differ from every runtime password.' \
        'Runtime accounts may share a password only for local development.' \
        'Use distinct service credentials in deployed environments.' \
        'Input is hidden and is not saved by this script.'
fi

prompt_secret_if_missing LOAN_DB_ADMIN_PASSWORD "$LOAN_DB_ADMIN_USERNAME database administrator password"
prompt_secret_if_missing LOAN_SCHEMA_OWNER_PASSWORD "CLOUDBANK schema-owner password"
prompt_secret_if_missing LOAN_DATASOURCE_PASSWORD "CB_LOAN_APPLICATION_APP runtime password"
prompt_secret_if_missing DOCUMENT_INGEST_DATASOURCE_PASSWORD "CB_DOCUMENT_INGEST_APP runtime password"
prompt_secret_if_missing DOCUMENT_REVIEW_DATASOURCE_PASSWORD "CB_DOCUMENT_REVIEW_APP runtime password"
prompt_secret_if_missing DECISION_DATASOURCE_PASSWORD "CB_DECISION_APP runtime password"
prompt_secret_if_missing AI_DATASOURCE_PASSWORD "CB_AI_AGENT_APP runtime password"
if [[ "$SCHEMA_PROFILE" == "full-demo" ]]; then
    prompt_secret_if_missing GEOGRAPHIC_RISK_DATASOURCE_PASSWORD "CB_GEOGRAPHIC_RISK_APP runtime password"
    prompt_secret_if_missing POLICY_RETRIEVAL_DATASOURCE_PASSWORD "CB_POLICY_APPLICATION_APP runtime password"
    prompt_secret_if_missing POLICY_LOADER_DATASOURCE_PASSWORD "CB_POLICY_LOADER_APP runtime password"
fi

validate_admin_password
validate_schema_password LOAN_SCHEMA_OWNER_PASSWORD "CLOUDBANK schema-owner password"
validate_schema_password LOAN_DATASOURCE_PASSWORD "CB_LOAN_APPLICATION_APP runtime password"
validate_schema_password DOCUMENT_INGEST_DATASOURCE_PASSWORD "CB_DOCUMENT_INGEST_APP runtime password"
validate_schema_password DOCUMENT_REVIEW_DATASOURCE_PASSWORD "CB_DOCUMENT_REVIEW_APP runtime password"
validate_schema_password DECISION_DATASOURCE_PASSWORD "CB_DECISION_APP runtime password"
validate_schema_password AI_DATASOURCE_PASSWORD "CB_AI_AGENT_APP runtime password"
if [[ "$SCHEMA_PROFILE" == "full-demo" ]]; then
    validate_schema_password GEOGRAPHIC_RISK_DATASOURCE_PASSWORD "CB_GEOGRAPHIC_RISK_APP runtime password"
    validate_schema_password POLICY_RETRIEVAL_DATASOURCE_PASSWORD "CB_POLICY_APPLICATION_APP runtime password"
    validate_schema_password POLICY_LOADER_DATASOURCE_PASSWORD "CB_POLICY_LOADER_APP runtime password"
fi
OWNER_PASSWORD_REUSED=false
if [[ "$LOAN_SCHEMA_OWNER_PASSWORD" == "$LOAN_DATASOURCE_PASSWORD" ||
      "$LOAN_SCHEMA_OWNER_PASSWORD" == "$DOCUMENT_INGEST_DATASOURCE_PASSWORD" ]]; then
    OWNER_PASSWORD_REUSED=true
fi
if [[ "$LOAN_SCHEMA_OWNER_PASSWORD" == "$DOCUMENT_REVIEW_DATASOURCE_PASSWORD" ]]; then
    OWNER_PASSWORD_REUSED=true
fi
if [[ "$LOAN_SCHEMA_OWNER_PASSWORD" == "$DECISION_DATASOURCE_PASSWORD" ||
      "$LOAN_SCHEMA_OWNER_PASSWORD" == "$AI_DATASOURCE_PASSWORD" ]]; then
    OWNER_PASSWORD_REUSED=true
fi
if [[ "$SCHEMA_PROFILE" == "full-demo" &&
      "$LOAN_SCHEMA_OWNER_PASSWORD" == "$GEOGRAPHIC_RISK_DATASOURCE_PASSWORD" ]]; then
    OWNER_PASSWORD_REUSED=true
fi
if [[ "$SCHEMA_PROFILE" == "full-demo" &&
      "$LOAN_SCHEMA_OWNER_PASSWORD" == "$POLICY_RETRIEVAL_DATASOURCE_PASSWORD" ]]; then
    OWNER_PASSWORD_REUSED=true
fi
if [[ "$SCHEMA_PROFILE" == "full-demo" &&
      "$LOAN_SCHEMA_OWNER_PASSWORD" == "$POLICY_LOADER_DATASOURCE_PASSWORD" ]]; then
    OWNER_PASSWORD_REUSED=true
fi
if [[ "$OWNER_PASSWORD_REUSED" == "true" ]]; then
    die "The CLOUDBANK owner password must differ from every runtime password"
fi

printf '\nPreparing CLOUDBANK owner and runtime accounts...\n'
OWNER_PREPARED=true
run_account_prepare || die "Database account preparation failed"

if [[ "$SCHEMA_PROFILE" == "full-demo" ]]; then
    printf 'Checking full-demo Oracle Spatial and Text capabilities...\n'
    run_full_demo_capability_check || die "Full-demo database capability check failed"
fi

printf 'Applying pending %s Liquibase changes from src/schema...\n' "$LIQUIBASE_LABEL"
run_liquibase_update || die "Liquibase migration failed"

if [[ "$SCHEMA_PROFILE" == "full-demo" ]]; then
    printf 'Verifying full-demo feature objects...\n'
    run_full_demo_verification || die "Full-demo contract verification failed"
fi

printf 'Granting the runtime role, removing temporary privileges, and locking CLOUDBANK...\n'
run_account_finalize SUCCESS || die "Database account finalization failed"
OWNER_PREPARED=false

printf 'Verifying the loan application database contract...\n'
run_contract_verification || die "Database contract verification failed"

printf 'Verifying runtime database credentials...\n'
run_runtime_credential_verification CB_LOAN_APPLICATION_APP "$LOAN_DATASOURCE_PASSWORD" ||
    die "CB_LOAN_APPLICATION_APP credential verification failed"
run_runtime_credential_verification CB_DOCUMENT_INGEST_APP "$DOCUMENT_INGEST_DATASOURCE_PASSWORD" ||
    die "CB_DOCUMENT_INGEST_APP credential verification failed"
run_runtime_credential_verification CB_DOCUMENT_REVIEW_APP "$DOCUMENT_REVIEW_DATASOURCE_PASSWORD" ||
    die "CB_DOCUMENT_REVIEW_APP credential verification failed"
run_runtime_credential_verification CB_DECISION_APP "$DECISION_DATASOURCE_PASSWORD" ||
    die "CB_DECISION_APP credential verification failed"
run_runtime_credential_verification CB_AI_AGENT_APP "$AI_DATASOURCE_PASSWORD" ||
    die "CB_AI_AGENT_APP credential verification failed"
if [[ "$SCHEMA_PROFILE" == "full-demo" ]]; then
    run_runtime_credential_verification CB_GEOGRAPHIC_RISK_APP "$GEOGRAPHIC_RISK_DATASOURCE_PASSWORD" ||
        die "CB_GEOGRAPHIC_RISK_APP credential verification failed"
    run_runtime_credential_verification CB_POLICY_APPLICATION_APP "$POLICY_RETRIEVAL_DATASOURCE_PASSWORD" ||
        die "CB_POLICY_APPLICATION_APP credential verification failed"
    run_runtime_credential_verification CB_POLICY_LOADER_APP "$POLICY_LOADER_DATASOURCE_PASSWORD" ||
        die "CB_POLICY_LOADER_APP credential verification failed"
fi

printf '\nDatabase setup complete. CLOUDBANK is locked and runtime accounts are ready.\n'
