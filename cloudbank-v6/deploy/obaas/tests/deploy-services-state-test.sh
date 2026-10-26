#!/usr/bin/env bash

# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at
# https://oss.oracle.com/licenses/upl.

set -Eeuo pipefail

readonly TEST_FILE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../deploy-services.sh
source "$TEST_FILE_DIR/../deploy-services.sh"

MOCK_SCENARIO=""
MOCK_INSTALLED_APP_VERSION=2.1.1
MOCK_RELEASE_STATUS=deployed

release_exists() {
    local service="$1"
    case "$MOCK_SCENARIO:$service" in
        mixed:decision-service|deployment-only:decision-service|all-missing:*) return 1 ;;
        *) return 0 ;;
    esac
}

deployment_exists() {
    local service="$1"
    case "$MOCK_SCENARIO:$service" in
        mixed:decision-service|release-only:decision-service|all-missing:*) return 1 ;;
        *) return 0 ;;
    esac
}

helm() {
    local filter=""
    local service
    local previous=""
    local argument

    [[ "${1-}" == list ]] || return 64
    for argument in "$@"; do
        if [[ "$previous" == --filter ]]; then
            filter="$argument"
            break
        fi
        previous="$argument"
    done
    [[ ${#filter} -ge 3 ]] || return 64
    service="${filter:1:${#filter}-2}"
    if release_exists "$service"; then
        printf '[{"name":"%s","status":"%s","app_version":"%s"}]\n' \
            "$service" "$MOCK_RELEASE_STATUS" "$MOCK_INSTALLED_APP_VERSION"
    else
        printf '[]\n'
    fi
}

kubectl() {
    local service=""
    local previous=""
    local argument

    for argument in "$@"; do
        if [[ "$previous" == deployment ]]; then
            service="$argument"
            break
        fi
        previous="$argument"
    done
    [[ -n "$service" ]] || return 64
    deployment_exists "$service" || return 1
    if [[ "$*" == *jsonpath=* ]]; then
        printf '%s/%s:old-tag' "$IMAGE_REPOSITORY_PREFIX" "$service"
    fi
}

configure_test_state() {
    DEPLOY_MODE=redeploy
    KUBECTL_CONTEXT=test-context
    NAMESPACE=test-namespace
    OBAAS_VERSION=2.1.1
    OBAAS_RELEASE=obaas
    OCI_REGION=test-region-1
    IMAGE_REPOSITORY_PREFIX=registry.example/test/cloudbank-ai
    IMAGE_TAG=new-tag
    RESOLVED_CHART=obaas/obaas-sample-app
    TARGET_PLATFORMS=linux/arm64
    DB_PRIV_SECRET=test-db-priv-authn
    WALLET_SECRET=test-wallet
    DB_SECRET_STATE=partial
    DATABASE_SERVICE_SOURCE="copied from test secret"
    SCHEMA_JOB_NAME=test-schema-job
    POLICY_LOADER_JOB_NAME=test-policy-loader-job
    AZN_ISSUER_URI=https://issuer.example
    AZN_CLUSTER_URL=http://azn-server.test-namespace.svc.cluster.local:8080
    MICROTX_WORKFLOW_URL=http://workflow.test-namespace.svc.cluster.local:9010/workflow-server
    MICROTX_WORKFLOW_URL_SOURCE=service
    POLICY_OCI_REGION=test-region-1
    POLICY_OCI_EMBEDDING_MODEL=test-embedding-model
    AI_OCI_REGION=test-region-1
    AI_OCI_GENAI_CHAT_MODEL=test-chat-model
    AI_SERVICE_ACCOUNT=ai-agent-service
    HELM_LIST_ALL_STATUS_ARGS=(--all)
}

assert_contains() {
    local output="$1"
    local expected="$2"
    [[ "$output" == *"$expected"* ]] || {
        printf 'FAIL: expected output to contain: %s\n' "$expected" >&2
        return 1
    }
}

test_mixed_redeploy_installs_absent_service() {
    local output
    MOCK_SCENARIO=mixed
    output="$(validate_deploy_state)"
    assert_contains "$output" "redeploy will install it"
    assert_contains "$output" "upgrade 7 existing service(s) and install 1 new service(s)"

    output="$(show_plan)"
    assert_contains "$output" "decision-service"
    assert_contains "$output" "new Helm release and Deployment"
}

test_release_without_deployment_is_rejected() {
    local output
    MOCK_SCENARIO=release-only
    if output="$(validate_deploy_state 2>&1)"; then
        printf 'FAIL: release-only state was accepted\n' >&2
        return 1
    fi
    assert_contains "$output" "inconsistent 'decision-service' state"
}

test_deployment_without_release_is_rejected() {
    local output
    MOCK_SCENARIO=deployment-only
    if output="$(validate_deploy_state 2>&1)"; then
        printf 'FAIL: deployment-only state was accepted\n' >&2
        return 1
    fi
    assert_contains "$output" "inconsistent 'decision-service' state"
}

test_redeploy_does_not_replace_first_deploy() {
    local output
    MOCK_SCENARIO=all-missing
    if output="$(validate_deploy_state 2>&1)"; then
        printf 'FAIL: an empty target was accepted for redeploy\n' >&2
        return 1
    fi
    assert_contains "$output" "use first-deploy"
}

test_ai_service_values_include_own_database_and_bounded_ingest_access() {
    local values_file
    local output
    values_file="$(mktemp)"
    DATABASE_SECRET_PREFIX=test
    IMAGE_PULL_SECRET=test-pull-secret
    generate_service_values ai-agent-service "$values_file"
    output="$(cat "$values_file")"
    rm -f -- "$values_file"
    assert_contains "$output" 'database:'
    assert_contains "$output" 'enabled: true'
    assert_contains "$output" 'test-ai-agent-service-db-authn'
    assert_contains "$output" 'AI_DATASOURCE_PASSWORD'
    assert_contains "$output" 'DOCUMENT_INGEST_BASE_URL'
    assert_contains "$output" 'AI_OCI_GENAI_AUTHENTICATION_TYPE'
    assert_contains "$output" 'WORKLOAD_IDENTITY'
    [[ "$(service_db_username ai-agent-service)" == CB_AI_AGENT_APP ]]

    values_file="$(mktemp)"
    generate_service_values document-ingest "$values_file"
    output="$(cat "$values_file")"
    rm -f -- "$values_file"
    assert_contains "$output" 'DOCUMENT_INGEST_REVIEW_INPUT_CLIENT_IDS'
    assert_contains "$output" 'cloudbank-ai-agent-client'
}

test_platform_upgrade_reconciles_older_application_charts() {
    local output
    local transition_count
    MOCK_SCENARIO=all-existing
    OBAAS_VERSION=2.1.2
    output="$(validate_deploy_state)"
    assert_contains "$output" 'will move from appVersion 2.1.1 to 2.1.2 after chart validation'
    transition_count="$(printf '%s\n' "$output" | grep -c 'will move from appVersion')"
    [[ "$transition_count" -eq 8 ]] || {
        printf 'FAIL: expected all eight application charts to move to the target version\n' >&2
        return 1
    }
}

test_failed_first_deployment_can_resume_after_platform_upgrade() {
    local output
    DEPLOY_MODE=first-deploy
    MOCK_RELEASE_STATUS=failed
    output="$(validate_deploy_state)"
    assert_contains "$output" 'will move from appVersion 2.1.1 to 2.1.2 after chart validation'
    assert_contains "$output" 'will be resumed'
    DEPLOY_MODE=redeploy
    MOCK_RELEASE_STATUS=deployed
}

test_application_chart_downgrade_is_rejected() {
    local output
    OBAAS_VERSION=2.1.0
    if output="$(validate_deploy_state 2>&1)"; then
        printf 'FAIL: an automatic application chart downgrade was accepted\n' >&2
        return 1
    fi
    assert_contains "$output" 'newer than OBaaS'
}

configure_test_state
test_mixed_redeploy_installs_absent_service
test_release_without_deployment_is_rejected
test_deployment_without_release_is_rejected
test_redeploy_does_not_replace_first_deploy
test_ai_service_values_include_own_database_and_bounded_ingest_access
test_platform_upgrade_reconciles_older_application_charts
test_failed_first_deployment_can_resume_after_platform_upgrade
test_application_chart_downgrade_is_rejected
printf 'PASS: deploy-services redeploy state tests\n'
