#!/usr/bin/env bash

# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at
# https://oss.oracle.com/licenses/upl.

set -euo pipefail
set +x

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ENV_FILE="$SCRIPT_DIR/.env"
readonly LOCAL_DIR="$SCRIPT_DIR/.cloudbank-local"
readonly PRIVATE_KEY="$LOCAL_DIR/signing-private.pem"
readonly PUBLIC_KEY="$LOCAL_DIR/signing-public.pem"
readonly ORACLE_VOLUME="cloudbank-ai_oracle-data"
readonly DEFAULT_ORACLE_IMAGE="gvenzl/oracle-free:latest"
readonly LEGACY_ORACLE_IMAGE="gvenzl/oracle-free:23.26.2-slim-faststart"
readonly SQLCL_IMAGE="container-registry.oracle.com/database/sqlcl:26.2.1"
readonly ORACLE_JDK_IMAGE="container-registry.oracle.com/java/jdk-no-fee-term:25-oraclelinux9"
readonly LEGACY_OBAAS_JDK_IMAGE="ghcr.io/oracle/oracle-jdk-image-obaas:25"
readonly MAVEN_BUILDER_IMAGE="maven:3.9.16-eclipse-temurin-25"
readonly -a INIT_PRESERVED_ENV_VARIABLES=(
    OCI_REGION
    OKE_CLUSTER_OCID
    CLOUDBANK_KUBECONFIG_PATH
    OCI_COMPARTMENT_OCID
    OCI_IDENTITY_NAME
    OCI_AUTH_TOKEN
    OBAAS_RELEASE
    MICROTX_NAMESPACE
    MICROTX_PUBLIC_HOST
    MICROTX_PROTOCOL
    MICROTX_PUBLIC_PORT
    IMAGE_PULL_SECRET
    POLICY_SERVICE_ACCOUNT
    POLICY_OCI_GENAI_EMBEDDING_MODEL
    AI_SERVICE_ACCOUNT
    AI_OCI_GENAI_CHAT_MODEL
    OKE_CLUSTER_COMPARTMENT_ID
    GEOGRAPHIC_RISK_LOG_GEOCODING_DETAILS
)

DATABASE_MODE=""
DATABASE_HOST=""
DATABASE_PORT=""
ORACLE_HOST_PORT=""
ORACLE_SERVICE_NAME=""
ORACLE_IMAGE=""
AZN_ISSUER_URI=""
SCHEMA_PROFILE=""
COMPOSE_MANAGED_PROFILE=false
REQUESTED_SCHEMA_PROFILE=""

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 2
}

usage() {
    printf '%s\n' \
        'Usage: ./run-compose.sh <command> [options]' \
        '' \
        'Commands:' \
        '  init [--schema-profile PROFILE]' \
        '                  Create or validate local configuration. When .env contains' \
        '                  deployment inputs, preserve only those inputs and rebuild' \
        '                  the generated CloudBank values.' \
        '  up [--schema-profile PROFILE]' \
        '                  Build, start, wait for readiness, and run non-mutating checks' \
        '  check           Check containers, actuator endpoints, metadata, JWKS, and OAuth' \
        '  verify          Run check followed by component smoke tests' \
        '  status          Show container status' \
        '  logs [service]  Follow logs for the stack or one service' \
        '  down            Stop Compose-managed containers and preserve data/configuration' \
        '  reset [--force] Remove managed data and built app images; preserve .env and keys' \
        '  purge [--force] Remove all stack data, images, configuration, and signing keys' \
        '  help            Show this help' \
        '' \
        'Schema profiles (saved when .env is initialized):' \
        '  full-demo      Runtime schema plus Spatial, Text, Vector, Graph, and' \
        '                 annotations and the geographic-risk smoke fixture (default)' \
        '  runtime        Service-required schema only' \
        '' \
        'Running without a command only shows this help.'
}

require_commands() {
    local command_name
    for command_name in docker openssl curl grep sed awk mktemp chmod; do
        command -v "$command_name" >/dev/null 2>&1 || die "$command_name is required"
    done
    docker compose version >/dev/null 2>&1 || die "Docker Compose is required"
}

random_secret() {
    local random_material

    # Keep generated values valid for Autonomous Database users as well as
    # local Oracle: exactly 30 characters with at least two upper-case,
    # lower-case, numeric, and supported special characters.
    random_material="$(openssl rand -base64 18)"
    random_material="${random_material//+/A}"
    random_material="${random_material//\//B}"
    printf 'Aa1_Aa1_%s' "${random_material:0:22}"
}

env_value() {
    local variable_name="$1"
    awk -F= -v variable_name="$variable_name" \
        '$1 == variable_name { print substr($0, index($0, "=") + 1) }' "$ENV_FILE" | tail -n 1
}

env_count() {
    local variable_name="$1"
    awk -F= -v variable_name="$variable_name" '$1 == variable_name { count++ } END { print count + 0 }' \
        "$ENV_FILE"
}

write_generated_env_values() {
    local schema_profile="$1"
    local configuration_mode="${2:-local}"

    [[ "$configuration_mode" == local || "$configuration_mode" == deployment ]] ||
        die "unsupported configuration generation mode: $configuration_mode"

    printf 'DATABASE_MODE=managed\n'
    printf 'SCHEMA_PROFILE=%s\n' "$schema_profile"
    printf 'ORACLE_IMAGE=%s\n' "$DEFAULT_ORACLE_IMAGE"
    printf 'ORACLE_CONTAINER_NAME=\n'
    printf 'ORACLE_CONTAINER_PORT=1521\n'
    printf 'ORACLE_HOST_PORT=1521\n'
    printf 'ORACLE_ADMIN_USERNAME=SYSTEM\n'
    printf 'ORACLE_SERVICE_NAME=FREEPDB1\n'
    printf 'ORACLE_PASSWORD=%s\n' "$(random_secret)"
    printf 'LOAN_SCHEMA_OWNER_PASSWORD=%s\n' "$(random_secret)"
    printf 'LOAN_DATASOURCE_PASSWORD=%s\n' "$(random_secret)"
    printf 'DOCUMENT_INGEST_DATASOURCE_PASSWORD=%s\n' "$(random_secret)"
    printf 'DOCUMENT_REVIEW_DATASOURCE_PASSWORD=%s\n' "$(random_secret)"
    printf 'DECISION_DATASOURCE_PASSWORD=%s\n' "$(random_secret)"
    printf 'AI_DATASOURCE_PASSWORD=%s\n' "$(random_secret)"
    printf 'GEOGRAPHIC_RISK_DATASOURCE_PASSWORD=%s\n' "$(random_secret)"
    printf 'POLICY_RETRIEVAL_DATASOURCE_PASSWORD=%s\n' "$(random_secret)"
    if [[ "$configuration_mode" == deployment ]]; then
        printf 'POLICY_OCI_GENAI_AUTHENTICATION_TYPE=WORKLOAD_IDENTITY\n'
    else
        printf 'POLICY_OCI_GENAI_AUTHENTICATION_TYPE=FILE\n'
    fi
    printf 'POLICY_OCI_GENAI_CONFIG_DIRECTORY=\n'
    printf 'POLICY_OCI_GENAI_PROFILE=\n'
    printf 'POLICY_OCI_GENAI_REGION=\n'
    if [[ "$configuration_mode" == local ]]; then
        printf 'POLICY_SERVICE_ACCOUNT=policy-retrieval-service\n'
        printf 'POLICY_OCI_GENAI_EMBEDDING_MODEL=\n'
    fi
    printf 'POLICY_OCI_GENAI_EMBEDDING_COMPARTMENT_ID=\n'
    printf 'AI_OCI_GENAI_AUTHENTICATION_TYPE=WORKLOAD_IDENTITY\n'
    printf 'AI_OCI_GENAI_REGION=\n'
    if [[ "$configuration_mode" == local ]]; then
        printf 'AI_OCI_GENAI_CHAT_MODEL=\n'
        printf 'OKE_CLUSTER_COMPARTMENT_ID=\n'
        printf 'AI_SERVICE_ACCOUNT=ai-agent-service\n'
        printf 'GEOGRAPHIC_RISK_LOG_GEOCODING_DETAILS=false\n'
    fi
    printf 'AZN_USER_REPO_OWNER_PASSWORD=%s\n' "$(random_secret)"
    printf 'AZN_USER_REPO_PASSWORD=%s\n' "$(random_secret)"
    printf 'AZN_BOOTSTRAP_USERS_ADMIN_PASSWORD=%s\n' "$(random_secret)"
    printf 'AZN_BOOTSTRAP_USERS_USER_PASSWORD=%s\n' "$(random_secret)"
    printf 'AZN_AUTHORIZATION_SERVER_DEFAULT_CLIENT_SECRET=%s\n' "$(random_secret)"
    printf 'AZN_AUTHORIZATION_SERVER_SERVICE_CLIENT_SECRET=%s\n' "$(random_secret)"
    printf 'AZN_AUTHORIZATION_SERVER_DOCUMENT_INGEST_CLIENT_SECRET=%s\n' "$(random_secret)"
    printf 'AZN_AUTHORIZATION_SERVER_DOCUMENT_REVIEW_CLIENT_SECRET=%s\n' "$(random_secret)"
    printf 'AZN_AUTHORIZATION_SERVER_AI_AGENT_CLIENT_SECRET=%s\n' "$(random_secret)"
    printf 'AZN_AUTHORIZATION_SERVER_MICROTX_CLIENT_SECRET=%s\n' "$(random_secret)"
    printf 'AZN_AUTHORIZATION_SERVER_MICROTX_CONSOLE_CLIENT_SECRET=%s\n' "$(random_secret)"
    printf 'AZN_ISSUER_URI=http://localhost:8080\n'
    if [[ "$configuration_mode" == local ]]; then
        printf 'IMAGE_PULL_SECRET=cloudbank-ai-ocir-pull\n'
    fi
}

generate_env_file() {
    local schema_profile="${1:-full-demo}"
    local temp_env

    if [[ -e "$ENV_FILE" ]]; then
        return 0
    fi
    if docker volume inspect "$ORACLE_VOLUME" >/dev/null 2>&1; then
        die "The managed Oracle volume exists but .env is missing. Restore .env or run './run-compose.sh purge'."
    fi

    umask 077
    temp_env="$(mktemp "$SCRIPT_DIR/.env.tmp.XXXXXX")"
    write_generated_env_values "$schema_profile" local >"$temp_env"
    mv "$temp_env" "$ENV_FILE"
    chmod 600 "$ENV_FILE"
    printf 'Created local configuration in .env.\n'
}

initialize_existing_env_file() {
    local schema_profile="${1:-full-demo}"
    local variable_name
    local value
    local temp_env

    [[ -f "$ENV_FILE" ]] || die \
        ".env is missing; create it with the documented OCI deployment inputs before running init"

    for variable_name in "${INIT_PRESERVED_ENV_VARIABLES[@]}"; do
        [[ "$(env_count "$variable_name")" -eq 1 ]] || die \
            ".env must contain exactly one $variable_name entry before init"
        value="$(env_value "$variable_name")"
        [[ -n "$value" ]] || die ".env variable $variable_name must not be empty before init"
        case "$value" in
            *$'\n'* | *$'\r'*) die ".env variable $variable_name contains a newline" ;;
        esac
    done

    umask 077
    temp_env="$(mktemp "$SCRIPT_DIR/.env.tmp.XXXXXX")"
    {
        for variable_name in "${INIT_PRESERVED_ENV_VARIABLES[@]}"; do
            printf '%s=%s\n' "$variable_name" "$(env_value "$variable_name")"
        done
        write_generated_env_values "$schema_profile" deployment
    } >"$temp_env"
    mv "$temp_env" "$ENV_FILE"
    chmod 600 "$ENV_FILE"
    printf 'Rebuilt CloudBank configuration in .env and preserved the deployment inputs.\n'
}

has_deployment_inputs() {
    local variable_name
    local deployment_input_variables=(
        OCI_REGION
        OKE_CLUSTER_OCID
        CLOUDBANK_KUBECONFIG_PATH
        OCI_COMPARTMENT_OCID
        OCI_IDENTITY_NAME
        OCI_AUTH_TOKEN
    )

    [[ -f "$ENV_FILE" ]] || return 1
    for variable_name in "${deployment_input_variables[@]}"; do
        if [[ "$(env_count "$variable_name")" -gt 0 ]]; then
            return 0
        fi
    done
    return 1
}

ensure_microtx_client_secret() {
    [[ -f "$ENV_FILE" ]] || return 0
    if [[ "$(env_count AZN_AUTHORIZATION_SERVER_MICROTX_CLIENT_SECRET)" -eq 0 ]]; then
        umask 077
        printf 'AZN_AUTHORIZATION_SERVER_MICROTX_CLIENT_SECRET=%s\n' "$(random_secret)" >>"$ENV_FILE"
        chmod 600 "$ENV_FILE"
        printf 'Added the missing MicroTx OAuth client secret to existing local configuration.\n'
    fi
}

ensure_microtx_console_client_secret() {
    [[ -f "$ENV_FILE" ]] || return 0
    if [[ "$(env_count AZN_AUTHORIZATION_SERVER_MICROTX_CONSOLE_CLIENT_SECRET)" -eq 0 ]]; then
        umask 077
        printf 'AZN_AUTHORIZATION_SERVER_MICROTX_CONSOLE_CLIENT_SECRET=%s\n' "$(random_secret)" >>"$ENV_FILE"
        chmod 600 "$ENV_FILE"
        printf 'Added the missing MicroTx Console OAuth client secret to existing local configuration.\n'
    fi
}

ensure_azn_issuer_uri() {
    [[ -f "$ENV_FILE" ]] || return 0
    if [[ "$(env_count AZN_ISSUER_URI)" -eq 0 ]]; then
        umask 077
        printf 'AZN_ISSUER_URI=http://localhost:8080\n' >>"$ENV_FILE"
        chmod 600 "$ENV_FILE"
        printf 'Added the missing Azn issuer URI to existing local configuration.\n'
    fi
}

ensure_geographic_risk_datasource_password() {
    [[ -f "$ENV_FILE" ]] || return 0
    if [[ "$(env_count GEOGRAPHIC_RISK_DATASOURCE_PASSWORD)" -eq 0 ]]; then
        umask 077
        printf 'GEOGRAPHIC_RISK_DATASOURCE_PASSWORD=%s\n' "$(random_secret)" >>"$ENV_FILE"
        chmod 600 "$ENV_FILE"
        printf 'Added the missing geographic-risk datasource password to existing local configuration.\n'
    fi
}

ensure_policy_retrieval_configuration() {
    [[ -f "$ENV_FILE" ]] || return 0
    local variable_name
    for variable_name in \
        POLICY_RETRIEVAL_DATASOURCE_PASSWORD \
        POLICY_OCI_GENAI_AUTHENTICATION_TYPE \
        POLICY_OCI_GENAI_CONFIG_DIRECTORY \
        POLICY_OCI_GENAI_PROFILE \
        POLICY_OCI_GENAI_REGION \
        POLICY_OCI_GENAI_EMBEDDING_MODEL \
        POLICY_OCI_GENAI_EMBEDDING_COMPARTMENT_ID; do
        if [[ "$(env_count "$variable_name")" -eq 0 ]]; then
            umask 077
            case "$variable_name" in
                POLICY_RETRIEVAL_DATASOURCE_PASSWORD)
                    printf '%s=%s\n' "$variable_name" "$(random_secret)" >>"$ENV_FILE"
                    ;;
                POLICY_OCI_GENAI_AUTHENTICATION_TYPE)
                    printf '%s=FILE\n' "$variable_name" >>"$ENV_FILE"
                    ;;
                *)
                    printf '%s=\n' "$variable_name" >>"$ENV_FILE"
                    ;;
            esac
            chmod 600 "$ENV_FILE"
            printf 'Added the missing policy-retrieval configuration to existing local configuration.\n'
        fi
    done
}

ensure_document_review_configuration() {
    [[ -f "$ENV_FILE" ]] || return 0
    local variable_name
    for variable_name in DOCUMENT_REVIEW_DATASOURCE_PASSWORD AZN_AUTHORIZATION_SERVER_DOCUMENT_REVIEW_CLIENT_SECRET; do
        if [[ "$(env_count "$variable_name")" -eq 0 ]]; then
            umask 077
            printf '%s=%s\n' "$variable_name" "$(random_secret)" >>"$ENV_FILE"
            chmod 600 "$ENV_FILE"
            printf 'Added the missing document-review configuration to existing local configuration.\n'
        fi
    done
}

ensure_decision_configuration() {
    [[ -f "$ENV_FILE" ]] || return 0
    if [[ "$(env_count DECISION_DATASOURCE_PASSWORD)" -eq 0 ]]; then
        umask 077
        printf 'DECISION_DATASOURCE_PASSWORD=%s\n' "$(random_secret)" >>"$ENV_FILE"
        chmod 600 "$ENV_FILE"
        printf 'Added the missing decision-service datasource password to existing local configuration.\n'
    fi
}

ensure_ai_agent_configuration() {
    [[ -f "$ENV_FILE" ]] || return 0
    local variable_name
    for variable_name in \
        AI_DATASOURCE_PASSWORD \
        AZN_AUTHORIZATION_SERVER_AI_AGENT_CLIENT_SECRET \
        AI_OCI_GENAI_AUTHENTICATION_TYPE \
        AI_OCI_GENAI_REGION \
        AI_OCI_GENAI_CHAT_MODEL \
        OKE_CLUSTER_COMPARTMENT_ID \
        AI_SERVICE_ACCOUNT; do
        if [[ "$(env_count "$variable_name")" -eq 0 ]]; then
            umask 077
            case "$variable_name" in
                AI_DATASOURCE_PASSWORD|AZN_AUTHORIZATION_SERVER_AI_AGENT_CLIENT_SECRET)
                    printf '%s=%s\n' "$variable_name" "$(random_secret)" >>"$ENV_FILE"
                    ;;
                AI_OCI_GENAI_AUTHENTICATION_TYPE)
                    printf '%s=WORKLOAD_IDENTITY\n' "$variable_name" >>"$ENV_FILE"
                    ;;
                AI_SERVICE_ACCOUNT)
                    printf '%s=ai-agent-service\n' "$variable_name" >>"$ENV_FILE"
                    ;;
                *)
                    printf '%s=\n' "$variable_name" >>"$ENV_FILE"
                    ;;
            esac
            chmod 600 "$ENV_FILE"
            printf 'Added the missing AI agent configuration to existing local configuration.\n'
        fi
    done
}

validate_env_file() {
    local variable_name
    local count
    local value
    local required_variables=(
        DATABASE_MODE
        SCHEMA_PROFILE
        ORACLE_IMAGE
        ORACLE_CONTAINER_NAME
        ORACLE_CONTAINER_PORT
        ORACLE_HOST_PORT
        ORACLE_ADMIN_USERNAME
        ORACLE_SERVICE_NAME
        ORACLE_PASSWORD
        LOAN_SCHEMA_OWNER_PASSWORD
        LOAN_DATASOURCE_PASSWORD
        DOCUMENT_INGEST_DATASOURCE_PASSWORD
        DOCUMENT_REVIEW_DATASOURCE_PASSWORD
        DECISION_DATASOURCE_PASSWORD
        AI_DATASOURCE_PASSWORD
        GEOGRAPHIC_RISK_DATASOURCE_PASSWORD
        POLICY_RETRIEVAL_DATASOURCE_PASSWORD
        AZN_USER_REPO_OWNER_PASSWORD
        AZN_USER_REPO_PASSWORD
        AZN_BOOTSTRAP_USERS_ADMIN_PASSWORD
        AZN_BOOTSTRAP_USERS_USER_PASSWORD
        AZN_AUTHORIZATION_SERVER_DEFAULT_CLIENT_SECRET
        AZN_AUTHORIZATION_SERVER_SERVICE_CLIENT_SECRET
        AZN_AUTHORIZATION_SERVER_DOCUMENT_INGEST_CLIENT_SECRET
        AZN_AUTHORIZATION_SERVER_DOCUMENT_REVIEW_CLIENT_SECRET
        AZN_AUTHORIZATION_SERVER_AI_AGENT_CLIENT_SECRET
        AZN_AUTHORIZATION_SERVER_MICROTX_CLIENT_SECRET
        AZN_AUTHORIZATION_SERVER_MICROTX_CONSOLE_CLIENT_SECRET
        AZN_ISSUER_URI
    )

    [[ -f "$ENV_FILE" ]] || die ".env is missing; run './run-compose.sh init'"
    for variable_name in "${required_variables[@]}"; do
        count="$(env_count "$variable_name")"
        [[ "$count" -eq 1 ]] || die ".env must contain exactly one $variable_name entry"
        value="$(env_value "$variable_name")"
        if [[ "$variable_name" != "ORACLE_CONTAINER_NAME" && -z "$value" ]]; then
            die ".env variable $variable_name must not be empty"
        fi
        case "$value" in
            *$'\n'* | *$'\r'*) die ".env variable $variable_name contains a newline" ;;
        esac
        export "$variable_name=$value"
    done

    for variable_name in \
        POLICY_OCI_GENAI_AUTHENTICATION_TYPE \
        POLICY_OCI_GENAI_CONFIG_DIRECTORY \
        POLICY_OCI_GENAI_PROFILE \
        POLICY_OCI_GENAI_REGION \
        POLICY_OCI_GENAI_EMBEDDING_MODEL \
        POLICY_OCI_GENAI_EMBEDDING_COMPARTMENT_ID; do
        count="$(env_count "$variable_name")"
        [[ "$count" -eq 1 ]] || die ".env must contain exactly one $variable_name entry"
        value="$(env_value "$variable_name")"
        case "$value" in
            *$'\n'* | *$'\r'*) die ".env variable $variable_name contains a newline" ;;
        esac
        export "$variable_name=$value"
    done

    for variable_name in \
        AI_OCI_GENAI_AUTHENTICATION_TYPE \
        AI_OCI_GENAI_REGION \
        AI_OCI_GENAI_CHAT_MODEL \
        OKE_CLUSTER_COMPARTMENT_ID \
        AI_SERVICE_ACCOUNT; do
        count="$(env_count "$variable_name")"
        [[ "$count" -eq 1 ]] || die ".env must contain exactly one $variable_name entry"
        value="$(env_value "$variable_name")"
        case "$value" in
            *$'\n'* | *$'\r'*) die ".env variable $variable_name contains a newline" ;;
        esac
        export "$variable_name=$value"
    done

    DATABASE_MODE="$(env_value DATABASE_MODE)"
    SCHEMA_PROFILE="$(env_value SCHEMA_PROFILE)"
    ORACLE_IMAGE="$(env_value ORACLE_IMAGE)"
    ORACLE_HOST_PORT="$(env_value ORACLE_HOST_PORT)"
    ORACLE_SERVICE_NAME="$(env_value ORACLE_SERVICE_NAME)"
    AZN_ISSUER_URI="$(env_value AZN_ISSUER_URI)"
    case "$DATABASE_MODE" in
        managed) ;;
        existing)
            [[ -n "$(env_value ORACLE_CONTAINER_NAME)" ]] ||
                die "ORACLE_CONTAINER_NAME is required when DATABASE_MODE=existing"
            ;;
        *) die "DATABASE_MODE must be managed or existing" ;;
    esac
    case "$SCHEMA_PROFILE" in
        runtime | full-demo) ;;
        *) die "SCHEMA_PROFILE must be runtime or full-demo" ;;
    esac
    [[ "$ORACLE_IMAGE" =~ ^[A-Za-z0-9][A-Za-z0-9._/:@-]*$ ]] ||
        die "ORACLE_IMAGE must be a valid container image reference without whitespace"
    [[ "$ORACLE_HOST_PORT" =~ ^[0-9]+$ ]] &&
        [[ "$ORACLE_HOST_PORT" -ge 1 && "$ORACLE_HOST_PORT" -le 65535 ]] ||
        die "ORACLE_HOST_PORT must be an integer from 1 to 65535"
    value="$(env_value ORACLE_CONTAINER_PORT)"
    [[ "$value" =~ ^[0-9]+$ ]] && [[ "$value" -ge 1 && "$value" -le 65535 ]] ||
        die "ORACLE_CONTAINER_PORT must be an integer from 1 to 65535"
    [[ "$(env_value ORACLE_ADMIN_USERNAME)" =~ ^[A-Za-z][A-Za-z0-9_$#]{0,127}$ ]] ||
        die "ORACLE_ADMIN_USERNAME must be a valid Oracle username"
    [[ "$ORACLE_SERVICE_NAME" =~ ^[A-Za-z0-9._-]+$ ]] ||
        die "ORACLE_SERVICE_NAME contains unsupported characters"
    [[ "$AZN_ISSUER_URI" =~ ^https?://[^[:space:]]+$ ]] ||
        die "AZN_ISSUER_URI must be an HTTP or HTTPS URL without whitespace"
}

validate_policy_retrieval_oci_configuration() {
    local authentication_type
    local config_directory
    local embedding_model
    local compartment_id

    [[ "$SCHEMA_PROFILE" == "full-demo" ]] || return 0

    authentication_type="$(env_value POLICY_OCI_GENAI_AUTHENTICATION_TYPE)"
    [[ -n "$authentication_type" ]] || authentication_type=FILE
    config_directory="$(env_value POLICY_OCI_GENAI_CONFIG_DIRECTORY)"
    embedding_model="$(env_value POLICY_OCI_GENAI_EMBEDDING_MODEL)"
    compartment_id="$(env_value POLICY_OCI_GENAI_EMBEDDING_COMPARTMENT_ID)"

    [[ "$authentication_type" == "FILE" ]] || die \
        "POLICY_OCI_GENAI_AUTHENTICATION_TYPE must be FILE for local Compose"
    [[ "$config_directory" == /* && -d "$config_directory" ]] || die \
        "POLICY_OCI_GENAI_CONFIG_DIRECTORY must be an absolute local directory containing OCI config and key files"
    [[ -f "$config_directory/config" ]] || die \
        "POLICY_OCI_GENAI_CONFIG_DIRECTORY must contain an OCI config file named config"
    [[ -n "$embedding_model" ]] || die \
        "POLICY_OCI_GENAI_EMBEDDING_MODEL must be set for policy-retrieval-service"
    [[ -n "$compartment_id" ]] || die \
        "POLICY_OCI_GENAI_EMBEDDING_COMPARTMENT_ID must be set for policy-retrieval-service"
}

validate_ai_agent_oci_configuration() {
    local authentication_type
    local region
    local chat_model
    local compartment_id

    authentication_type="$(env_value AI_OCI_GENAI_AUTHENTICATION_TYPE)"
    [[ -n "$authentication_type" ]] || authentication_type=WORKLOAD_IDENTITY
    region="$(env_value AI_OCI_GENAI_REGION)"
    chat_model="$(env_value AI_OCI_GENAI_CHAT_MODEL)"
    compartment_id="$(env_value OKE_CLUSTER_COMPARTMENT_ID)"

    [[ "$authentication_type" == "WORKLOAD_IDENTITY" ]] || die \
        "AI_OCI_GENAI_AUTHENTICATION_TYPE must be WORKLOAD_IDENTITY"
    [[ -n "$region" ]] || die \
        "AI_OCI_GENAI_REGION must be set for ai-agent-service"
    [[ -n "$chat_model" ]] || die \
        "AI_OCI_GENAI_CHAT_MODEL must be set for ai-agent-service"
    [[ -n "$compartment_id" ]] || die \
        "OKE_CLUSTER_COMPARTMENT_ID must be set for ai-agent-service"
}

ensure_signing_keys() {
    local derived_public
    local configured_public

    if [[ ! -e "$PRIVATE_KEY" && ! -e "$PUBLIC_KEY" ]]; then
        umask 077
        mkdir -p "$LOCAL_DIR"
        openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -out "$PRIVATE_KEY" >/dev/null 2>&1
        openssl pkey -in "$PRIVATE_KEY" -pubout -out "$PUBLIC_KEY" >/dev/null 2>&1
        chmod 600 "$PRIVATE_KEY" "$PUBLIC_KEY"
        printf 'Created persistent signing keys in .cloudbank-local/.\n'
    elif [[ ! -f "$PRIVATE_KEY" || ! -f "$PUBLIC_KEY" ]]; then
        die "Both persistent signing-key files must exist; restore the missing file or run './run-compose.sh purge'"
    fi

    # `pkey -check` is unavailable in the LibreSSL shipped with macOS.
    # The signing key is always RSA, so `rsa -check` provides a portable
    # structural and consistency check on both LibreSSL and OpenSSL.
    openssl rsa -in "$PRIVATE_KEY" -check -noout >/dev/null 2>&1 ||
        die "The private signing key is invalid"
    derived_public="$(openssl pkey -in "$PRIVATE_KEY" -pubout 2>/dev/null)"
    configured_public="$(openssl pkey -pubin -in "$PUBLIC_KEY" -pubout 2>/dev/null)" ||
        die "The public signing key is invalid"
    [[ "$derived_public" == "$configured_public" ]] || die "The signing-key files do not form a matching pair"
}

inspect_existing_database() {
    local container_name
    local container_port
    local running
    local health
    local published_ports

    container_name="$(env_value ORACLE_CONTAINER_NAME)"
    container_port="$(env_value ORACLE_CONTAINER_PORT)"
    docker inspect --type container "$container_name" >/dev/null 2>&1 ||
        die "Existing Oracle container '$container_name' was not found"
    running="$(docker inspect --format '{{.State.Running}}' "$container_name")"
    [[ "$running" == "true" ]] || die "Existing Oracle container '$container_name' is not running"
    health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$container_name")"
    if [[ -n "$health" && "$health" != "healthy" ]]; then
        die "Existing Oracle container '$container_name' health is $health"
    fi
    published_ports="$(docker port "$container_name" "$container_port/tcp" 2>/dev/null || true)"
    [[ -n "$published_ports" ]] ||
        die "Existing Oracle container '$container_name' does not publish port $container_port/tcp"
    printf '%s\n' "$published_ports" | grep -Eq ":${ORACLE_HOST_PORT}$" ||
        die "ORACLE_HOST_PORT=$ORACLE_HOST_PORT does not match the published port for '$container_name'"
}

configure_database_values() {
    COMPOSE_MANAGED_PROFILE=false
    if [[ "$DATABASE_MODE" == "managed" ]]; then
        DATABASE_HOST="oracle"
        DATABASE_PORT="1521"
        COMPOSE_MANAGED_PROFILE=true
    else
        DATABASE_HOST="host.docker.internal"
        DATABASE_PORT="$ORACLE_HOST_PORT"
    fi
}

configure_database() {
    configure_database_values
    if [[ "$DATABASE_MODE" == "existing" ]]; then
        inspect_existing_database
    fi
}

compose() {
    local profile_args=()
    if [[ "${SCHEMA_PROFILE:-}" == "full-demo" ]]; then
        profile_args+=(--profile full-demo)
    fi
    if [[ "$COMPOSE_MANAGED_PROFILE" == "true" ]]; then
        profile_args=(--profile managed "${profile_args[@]}")
        DATABASE_HOST="$DATABASE_HOST" DATABASE_PORT="$DATABASE_PORT" \
            docker compose --project-directory "$SCRIPT_DIR" --env-file "$ENV_FILE" \
            "${profile_args[@]}" "$@"
    else
        DATABASE_HOST="$DATABASE_HOST" DATABASE_PORT="$DATABASE_PORT" \
        docker compose --project-directory "$SCRIPT_DIR" --env-file "$ENV_FILE" \
            "${profile_args[@]}" "$@"
    fi
}

compose_all_profiles() {
    DATABASE_HOST="${DATABASE_HOST:-oracle}" DATABASE_PORT="${DATABASE_PORT:-1521}" \
        ORACLE_IMAGE="${ORACLE_IMAGE:-$DEFAULT_ORACLE_IMAGE}" \
        SCHEMA_PROFILE="${SCHEMA_PROFILE:-full-demo}" \
        docker compose --project-directory "$SCRIPT_DIR" --env-file "$ENV_FILE" \
        --profile managed --profile full-demo "$@"
}

parse_schema_profile_option() {
    REQUESTED_SCHEMA_PROFILE=""
    case "$#" in
        0) ;;
        2)
            [[ "$1" == "--schema-profile" ]] || { usage >&2; exit 2; }
            case "$2" in
                runtime | full-demo) REQUESTED_SCHEMA_PROFILE="$2" ;;
                *) die "--schema-profile must be runtime or full-demo" ;;
            esac
            ;;
        *) usage >&2; exit 2 ;;
    esac
}

prepare_configuration() {
    local validate_oci_configuration="${1:-true}"
    local initial_profile="${REQUESTED_SCHEMA_PROFILE:-full-demo}"

    generate_env_file "$initial_profile"
    ensure_microtx_client_secret
    ensure_microtx_console_client_secret
    ensure_azn_issuer_uri
    ensure_geographic_risk_datasource_password
    ensure_policy_retrieval_configuration
    ensure_document_review_configuration
    ensure_decision_configuration
    ensure_ai_agent_configuration
    validate_env_file
    if [[ -n "$REQUESTED_SCHEMA_PROFILE" && "$REQUESTED_SCHEMA_PROFILE" != "$SCHEMA_PROFILE" ]]; then
        die "--schema-profile=$REQUESTED_SCHEMA_PROFILE conflicts with SCHEMA_PROFILE=$SCHEMA_PROFILE in .env; the script never overwrites existing configuration"
    fi
    if [[ "$validate_oci_configuration" == true ]]; then
        validate_policy_retrieval_oci_configuration
        validate_ai_agent_oci_configuration
    fi
    ensure_signing_keys
    configure_database
}

assert_service_healthy() {
    local service_name="$1"
    local container_id
    local running
    local health

    container_id="$(compose ps -q "$service_name")"
    [[ -n "$container_id" ]] || die "$service_name container is not running"
    running="$(docker inspect --format '{{.State.Running}}' "$container_id")"
    health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$container_id")"
    [[ "$running" == "true" && "$health" == "healthy" ]] ||
        die "$service_name is not healthy (running=$running, health=${health:-none})"
}

check_schema_initializer() {
    local container_id
    local exit_code

    container_id="$(compose ps -a -q schema-init)"
    [[ -n "$container_id" ]] || die "schema-init container was not found"
    exit_code="$(docker inspect --format '{{.State.ExitCode}}' "$container_id")"
    [[ "$exit_code" -eq 0 ]] || die "schema-init failed with exit code $exit_code"
}

check_http_endpoints() {
    local metadata
    local metadata_issuer
    local jwks
    local token_response
    local service_secret
    local escaped_credentials

    curl --silent --show-error --fail http://127.0.0.1:8080/actuator/health |
        grep -q '"status"[[:space:]]*:[[:space:]]*"UP"' || die "azn-server actuator health check failed"
    curl --silent --show-error --fail http://127.0.0.1:8081/actuator/health |
        grep -q '"status"[[:space:]]*:[[:space:]]*"UP"' || die "loan service actuator health check failed"
    curl --silent --show-error --fail http://127.0.0.1:8082/actuator/health |
        grep -q '"status"[[:space:]]*:[[:space:]]*"UP"' || die "document ingest actuator health check failed"
    curl --silent --show-error --fail http://127.0.0.1:8084/actuator/health |
        grep -q '"status"[[:space:]]*:[[:space:]]*"UP"' || die "document review actuator health check failed"
    curl --silent --show-error --fail http://127.0.0.1:8085/actuator/health |
        grep -q '"status"[[:space:]]*:[[:space:]]*"UP"' || die "AI agent mock actuator health check failed"
    curl --silent --show-error --fail http://127.0.0.1:8088/actuator/health |
        grep -q '"status"[[:space:]]*:[[:space:]]*"UP"' || die "decision service actuator health check failed"
    curl --silent --show-error --fail http://127.0.0.1:8087/actuator/health |
        grep -q '"status"[[:space:]]*:[[:space:]]*"UP"' ||
        die "workflow token refresh worker actuator health check failed"
    if [[ "$SCHEMA_PROFILE" == "full-demo" ]]; then
        curl --silent --show-error --fail http://127.0.0.1:8083/health/ready |
            grep -q '"status"[[:space:]]*:[[:space:]]*"UP"' ||
            die "geographic risk readiness check failed"
        curl --silent --show-error --fail http://127.0.0.1:8086/actuator/health |
            grep -q '"status"[[:space:]]*:[[:space:]]*"UP"' ||
            die "policy retrieval actuator health check failed"
    fi

    metadata="$(curl --silent --show-error --fail http://127.0.0.1:8080/.well-known/openid-configuration)" ||
        die "OpenID Connect metadata check failed"
    metadata_issuer="$(printf '%s' "$metadata" | sed -n 's/.*"issuer"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
    [[ "$metadata_issuer" == "$AZN_ISSUER_URI" ]] ||
        die "OpenID Connect issuer did not match configured AZN_ISSUER_URI=$AZN_ISSUER_URI"
    jwks="$(curl --silent --show-error --fail http://127.0.0.1:8080/oauth2/jwks)" || die "JWKS check failed"
    printf '%s' "$jwks" | grep -q '"keys"[[:space:]]*:' || die "JWKS response did not contain keys"

    service_secret="$(env_value AZN_AUTHORIZATION_SERVER_SERVICE_CLIENT_SECRET)"
    escaped_credentials="${service_secret//\\/\\\\}"
    escaped_credentials="${escaped_credentials//\"/\\\"}"
    token_response="$({
        printf 'user = "cloudbank-service-client:%s"\n' "$escaped_credentials"
    } | curl --silent --show-error --fail --config - --request POST \
        --header 'Content-Type: application/x-www-form-urlencoded' \
        --data-urlencode 'grant_type=client_credentials' \
        --data-urlencode 'scope=cloudbank.internal' \
        http://127.0.0.1:8080/oauth2/token)" || die "Service OAuth token issuance failed"
    service_secret=""
    escaped_credentials=""
    printf '%s' "$token_response" | grep -q '"access_token"[[:space:]]*:' ||
        die "Service OAuth response did not contain an access token"
    token_response=""
}

run_checks() {
    local service_name

    if [[ "$DATABASE_MODE" == "managed" ]]; then
        assert_service_healthy oracle
    fi
    check_schema_initializer
    for service_name in azn-server loan-application-service document-ingest document-review-service decision-service ai-agent-service workflow-token-refresh-worker; do
        assert_service_healthy "$service_name"
    done
    if [[ "$SCHEMA_PROFILE" == "full-demo" ]]; then
        assert_service_healthy geographic-risk-service
        assert_service_healthy policy-retrieval-service
    fi
    check_http_endpoints
    printf 'PASS: containers, schema initialization, actuator, metadata, JWKS, and OAuth checks\n'
}

print_stack_endpoints() {
    local heading="$1"

    printf '%s\n' "$heading"
    printf '  %-31s %s\n' \
        'Authorization server:' "$AZN_ISSUER_URI" \
        'Loan application service:' 'http://localhost:8081' \
        'Document ingest service:' 'http://localhost:8082' \
        'Document review service:' 'http://localhost:8084' \
        'AI agent service:' 'http://localhost:8085' \
        'Workflow token refresh worker:' 'http://localhost:8087' \
        'Decision service:' 'http://localhost:8088'
    if [[ "$SCHEMA_PROFILE" == "full-demo" ]]; then
        printf '  %-31s %s\n' \
            'Geographic risk service:' 'http://localhost:8083' \
            'Policy retrieval service:' 'http://localhost:8086'
    fi
    printf '  %-31s %s\n' \
        'Oracle Database:' "localhost:$ORACLE_HOST_PORT/$ORACLE_SERVICE_NAME"
}

print_smoke_test_coverage() {
    printf 'PASS: component smoke tests completed for the %s profile.\n' "$SCHEMA_PROFILE"
    printf '%s\n' \
        '  Verified: authorization, loan intake, document ingest, document review,' \
        '            AI agent, decision service, and workflow token refresh worker readiness.'
    if [[ "$SCHEMA_PROFILE" == "full-demo" ]]; then
        printf '%s\n' \
            '            Geographic risk and protected policy retrieval are also verified.'
    fi
}

run_smoke_tests() {
    local admin_password
    local user_password
    local browser_secret
    local service_secret
    local microtx_secret

    admin_password="$(env_value AZN_BOOTSTRAP_USERS_ADMIN_PASSWORD)"
    user_password="$(env_value AZN_BOOTSTRAP_USERS_USER_PASSWORD)"
    browser_secret="$(env_value AZN_AUTHORIZATION_SERVER_DEFAULT_CLIENT_SECRET)"
    service_secret="$(env_value AZN_AUTHORIZATION_SERVER_SERVICE_CLIENT_SECRET)"
    microtx_secret="$(env_value AZN_AUTHORIZATION_SERVER_MICROTX_CLIENT_SECRET)"

    BASE_URL=http://127.0.0.1:8080 \
    ADMIN_USERNAME=obaas-admin ADMIN_PASSWORD="$admin_password" \
    SERVICE_CLIENT_ID=cloudbank-service-client SERVICE_CLIENT_SECRET="$service_secret" \
    SERVICE_SCOPE=cloudbank.internal BROWSER_CLIENT_ID=cloudbank-client \
    BROWSER_CLIENT_SECRET="$browser_secret" MICROTX_CLIENT_ID=microtx-workflow-client \
    MICROTX_CLIENT_SECRET="$microtx_secret" MICROTX_SCOPE=microtx.workflow \
        "$SCRIPT_DIR/src/azn-server/smoke-test.sh" --non-interactive

    LOAN_BASE_URL=http://127.0.0.1:8081 AZN_BASE_URL=http://127.0.0.1:8080 \
    USERNAME=obaas-user USER_PASSWORD="$user_password" \
    BROWSER_CLIENT_ID=cloudbank-client BROWSER_CLIENT_SECRET="$browser_secret" \
    SERVICE_CLIENT_ID=cloudbank-service-client SERVICE_CLIENT_SECRET="$service_secret" \
    WORKFLOW_MODE=deferred \
        "$SCRIPT_DIR/src/loan-application-service/smoke-test.sh" --non-interactive

    INGEST_BASE_URL=http://127.0.0.1:8082 AZN_BASE_URL=http://127.0.0.1:8080 \
    SERVICE_CLIENT_ID=cloudbank-service-client SERVICE_CLIENT_SECRET="$service_secret" \
        "$SCRIPT_DIR/src/document-ingest/smoke-test.sh" --non-interactive

    DOCUMENT_REVIEW_BASE_URL=http://127.0.0.1:8084 AZN_BASE_URL=http://127.0.0.1:8080 \
    SERVICE_CLIENT_ID=cloudbank-service-client SERVICE_CLIENT_SECRET="$service_secret" \
        "$SCRIPT_DIR/src/document-review-service/smoke-test.sh" --non-interactive

    AI_AGENT_BASE_URL=http://127.0.0.1:8085 AZN_BASE_URL=http://127.0.0.1:8080 \
    SERVICE_CLIENT_ID=cloudbank-service-client SERVICE_CLIENT_SECRET="$service_secret" \
        "$SCRIPT_DIR/src/ai-agent-service/smoke-test.sh" --non-interactive

    DECISION_BASE_URL=http://127.0.0.1:8088 AZN_BASE_URL=http://127.0.0.1:8080 \
    SERVICE_CLIENT_ID=cloudbank-service-client SERVICE_CLIENT_SECRET="$service_secret" \
        "$SCRIPT_DIR/src/decision-service/smoke-test.sh" --non-interactive

    if [[ "$SCHEMA_PROFILE" == "full-demo" ]]; then
        GEOGRAPHIC_RISK_BASE_URL=http://127.0.0.1:8083 AZN_BASE_URL=http://127.0.0.1:8080 \
        SERVICE_CLIENT_ID=cloudbank-service-client SERVICE_CLIENT_SECRET="$service_secret" \
            "$SCRIPT_DIR/src/geographic-risk-service/smoke-test.sh" || die "Geographic risk smoke test failed"

        POLICY_RETRIEVAL_BASE_URL=http://127.0.0.1:8086 AZN_BASE_URL=http://127.0.0.1:8080 \
        SERVICE_CLIENT_ID=cloudbank-service-client SERVICE_CLIENT_SECRET="$service_secret" \
            "$SCRIPT_DIR/src/policy-retrieval-service/smoke-test.sh" --non-interactive ||
            die "Policy retrieval smoke test failed"
    fi

    admin_password=""
    user_password=""
    browser_secret=""
    service_secret=""
    microtx_secret=""
}

confirm_destructive_action() {
    local prompt="$1"
    local force="${2-}"
    local answer=""

    [[ "$force" == "--force" ]] && return
    [[ -t 0 ]] || die "This action requires an interactive terminal or --force"
    printf '%s [y/N] ' "$prompt"
    IFS= read -r answer
    case "$answer" in
        y | Y | yes | YES) ;;
        *) printf 'Action cancelled.\n'; return 1 ;;
    esac
}

remove_purge_images() {
    local image_name
    local removal_failed=false
    local images=(
        cloudbank-ai-azn-server:latest
        cloudbank-ai-loan-application-service:latest
        cloudbank-ai-document-ingest:latest
        cloudbank-ai-document-review-service:latest
        cloudbank-ai-decision-service:latest
        cloudbank-ai-ai-agent-service:latest
        cloudbank-ai-policy-retrieval-service:latest
        cloudbank-ai-geographic-risk-service:latest
        "${ORACLE_IMAGE:-$DEFAULT_ORACLE_IMAGE}"
        "$DEFAULT_ORACLE_IMAGE"
        "$LEGACY_ORACLE_IMAGE"
        "$SQLCL_IMAGE"
        "$ORACLE_JDK_IMAGE"
        "$LEGACY_OBAAS_JDK_IMAGE"
        "$MAVEN_BUILDER_IMAGE"
    )

    for image_name in "${images[@]}"; do
        if docker image inspect "$image_name" >/dev/null 2>&1; then
            if ! docker image rm "$image_name"; then
                printf 'WARNING: Could not remove image %s; it may be used by another container.\n' \
                    "$image_name" >&2
                removal_failed=true
            fi
        fi
    done

    [[ "$removal_failed" == "false" ]]
}

command_name="${1-}"
case "$command_name" in
    "" | help | -h | --help)
        usage
        exit 0
        ;;
esac

require_commands

case "$command_name" in
    init)
        parse_schema_profile_option "${@:2}"
        if has_deployment_inputs; then
            initialize_existing_env_file "${REQUESTED_SCHEMA_PROFILE:-full-demo}"
        fi
        prepare_configuration false
        printf 'Local configuration is complete and valid.\n'
        ;;
    up)
        parse_schema_profile_option "${@:2}"
        prepare_configuration
        compose up --build --detach --wait
        run_checks
        print_stack_endpoints 'CloudBank local stack is ready:'
        printf '%s\n' \
            '' \
            'Next: ./run-compose.sh verify'
        ;;
    check)
        [[ $# -eq 1 ]] || { usage >&2; exit 2; }
        prepare_configuration
        run_checks
        print_stack_endpoints 'CloudBank local stack checks passed:'
        ;;
    verify)
        [[ $# -eq 1 ]] || { usage >&2; exit 2; }
        prepare_configuration
        run_checks
        run_smoke_tests
        print_smoke_test_coverage
        ;;
    status)
        [[ $# -eq 1 ]] || { usage >&2; exit 2; }
        validate_env_file
        configure_database_values
        compose ps -a
        ;;
    logs)
        [[ $# -le 2 ]] || { usage >&2; exit 2; }
        validate_env_file
        configure_database_values
        if [[ $# -eq 2 ]]; then
            compose logs --follow "$2"
        else
            compose logs --follow
        fi
        ;;
    down)
        [[ $# -eq 1 ]] || { usage >&2; exit 2; }
        validate_env_file
        configure_database_values
        compose_all_profiles down --remove-orphans
        ;;
    reset)
        [[ $# -le 2 ]] || { usage >&2; exit 2; }
        validate_env_file
        configure_database_values
        [[ "$DATABASE_MODE" == "managed" ]] || die "reset is unavailable in existing database mode; the external database will not be modified"
        if confirm_destructive_action "Remove all Compose-managed containers, Oracle data, and built application images?" "${2-}"; then
            compose_all_profiles down --volumes --rmi local --remove-orphans
            printf '%s\n' \
                'Managed Oracle data and CloudBank application images removed.' \
                '.env, signing keys, and pulled base images were preserved.'
        fi
        ;;
    purge)
        [[ $# -le 2 ]] || { usage >&2; exit 2; }
        if [[ -f "$ENV_FILE" ]]; then
            ORACLE_IMAGE="$(env_value ORACLE_IMAGE)"
            ORACLE_IMAGE="${ORACLE_IMAGE:-$DEFAULT_ORACLE_IMAGE}"
            SCHEMA_PROFILE="$(env_value SCHEMA_PROFILE)"
            SCHEMA_PROFILE="${SCHEMA_PROFILE:-full-demo}"
        fi
        if confirm_destructive_action "Remove all CloudBank stack data, images, local configuration, and signing keys?" "${2-}"; then
            if [[ -f "$ENV_FILE" ]]; then
                compose_all_profiles down --volumes --rmi local --remove-orphans
            else
                docker volume rm "$ORACLE_VOLUME" >/dev/null 2>&1 || true
            fi
            image_removal_failed=false
            remove_purge_images || image_removal_failed=true
            rm -f -- "$ENV_FILE" "$PRIVATE_KEY" "$PUBLIC_KEY"
            rmdir "$LOCAL_DIR" 2>/dev/null || true
            if [[ "$image_removal_failed" == "true" ]]; then
                printf 'CloudBank local configuration was purged, but one or more images remain.\n' >&2
                exit 1
            fi
            printf 'CloudBank local environment purged, including pulled dependency images.\n'
        fi
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
