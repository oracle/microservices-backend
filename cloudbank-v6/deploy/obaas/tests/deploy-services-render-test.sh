#!/usr/bin/env bash

# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at
# https://oss.oracle.com/licenses/upl.

set -Eeuo pipefail

readonly TEST_FILE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../deploy-services.sh
source "$TEST_FILE_DIR/../deploy-services.sh"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cloudbank-render-test.XXXXXX")"
trap 'rm -rf -- "$WORK_DIR"' EXIT
mkdir -p "$WORK_DIR/values"

KUBECTL_CONTEXT=test-context
NAMESPACE=test-namespace
RESOLVED_CHART=test-chart
DATABASE_SECRET_PREFIX=test
DB_PRIV_SECRET=test-privileged-db
SCHEMA_OWNER_SECRET=test-schema-owner
AUTH_SECRET=test-auth
WALLET_SECRET=test-wallet
AI_SERVICE_ACCOUNT=test-ai-agent
POLICY_SERVICE_ACCOUNT=test-policy
MOCK_SCENARIO=valid

printf '%s\n' \
    'kind: Job' \
    'env:' \
    '  - name: TNS_ADMIN' \
    '    value: /oracle/tnsadmin' \
    '  - name: LOAN_SQLCL_CONNECT' \
    '    value: "$(DB_SERVICE)"' >"$WORK_DIR/schema-init-job.yaml"
printf '%s\n' 'kind: ServiceAccount' >"$WORK_DIR/policy-service-account.yaml"
printf '%s\n' \
    'kind: Job' \
    "serviceAccountName: \"$POLICY_SERVICE_ACCOUNT\"" \
    "runtimeSecret: $(service_db_secret policy-loader)" \
    "walletSecret: $WALLET_SECRET" >"$WORK_DIR/policy-loader-job.yaml"

# Reject every Kubernetes operation except the preflight's dry-run validation.
kubectl() {
    [[ "$*" == *' apply '* && "$*" == *'--dry-run='* ]] || return 64
}

# Render synthetic manifests: no cluster access, real chart, or credentials.
helm() {
    local service
    case "${1-}" in
        lint) return 0 ;;
        template) service="$2" ;;
        *) return 64 ;;
    esac

    printf '%s\n' 'kind: Deployment'
    if [[ "$service" != workflow-token-refresh-worker ]]; then
        if [[ "$service:$MOCK_SCENARIO" != ai-agent-service:missing-db-secret ]]; then
            printf 'runtimeSecret: %s\n' "$(service_db_secret "$service")"
        fi
        if [[ "$service:$MOCK_SCENARIO" != ai-agent-service:missing-wallet ]]; then
            printf 'walletSecret: %s\n' "$WALLET_SECRET"
        fi
        printf '%s\n' 'env:' '  - name: DB_SERVICE'
    elif [[ "$MOCK_SCENARIO" == worker-db-access ]]; then
        printf '%s\n' 'env:' '  - name: DB_SERVICE'
    fi

    if [[ "$service" == ai-agent-service ]]; then
        if [[ "$MOCK_SCENARIO" != missing-service-account ]]; then
            printf 'serviceAccountName: %s\n' "$AI_SERVICE_ACCOUNT"
        fi
        printf '%s\n' '  - name: AI_OCI_GENAI_AUTHENTICATION_TYPE'
        if [[ "$MOCK_SCENARIO" == wrong-authentication-type ]]; then
            printf '%s\n' '    value: API_KEY'
        else
            printf '%s\n' '    value: WORKLOAD_IDENTITY'
        fi
        if [[ "$MOCK_SCENARIO" == privileged-db-access ]]; then
            printf 'unexpectedSecret: %s\n' "$DB_PRIV_SECRET"
        fi
    fi
}

expect_render_failure() {
    local scenario="$1"
    local expected="$2"
    local output
    MOCK_SCENARIO="$scenario"
    if output="$(render_and_lint 2>&1)"; then
        printf 'FAIL: render accepted scenario %s\n' "$scenario" >&2
        return 1
    fi
    [[ "$output" == *"$expected"* ]] || {
        printf 'FAIL: scenario %s did not report %s\n%s\n' \
            "$scenario" "$expected" "$output" >&2
        return 1
    }
}

render_and_lint
expect_render_failure missing-db-secret "database-enabled service 'ai-agent-service' does not reference its runtime database Secret"
expect_render_failure missing-wallet "database-enabled service 'ai-agent-service' does not mount the ADB wallet"
expect_render_failure missing-service-account 'ai-agent-service does not use its Workload Identity ServiceAccount'
expect_render_failure wrong-authentication-type 'ai-agent-service does not select OKE Workload Identity'
expect_render_failure privileged-db-access "rendered chart for 'ai-agent-service' exposes the privileged database Secret"
expect_render_failure worker-db-access "database-disabled service 'workflow-token-refresh-worker' still renders database access"
printf 'PASS: deploy-services render validation tests (7 scenarios)\n'
