#!/usr/bin/env bash
set -Eeuo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Synthetic Helm/Kubernetes functions only; exercise the actual upgrade callers.
helm() {
    if [[ "$*" == 'upgrade --help' ]]; then
        if [[ "$MOCK_HELM_VERSION" == 4 ]]; then
            printf '  --server-side string\n  --force-conflicts\n'
        else
            printf '  --timeout duration\n'
        fi
        return
    fi
    [[ "$1" == upgrade ]]
    [[ "$*" != *--force-replace* && "$*" != *--take-ownership* ]]
    if [[ "$MOCK_HELM_VERSION" == 4 ]]; then
        [[ " $* " == *' --server-side=true --force-conflicts '* ]]
    else
        [[ "$*" != *--force-conflicts* && "$*" != *--server-side* ]]
    fi
    MOCK_UPGRADES=$((MOCK_UPGRADES + 1))
}

kubectl() {
    case "$*" in
        *'get endpointslice '*' -o json') printf '%s' '{"items":[{"endpoints":[{"conditions":{"ready":true}}]}]}' ;;
        *'get deployment ai-agent-service -o jsonpath='*) printf '%s' test-ai ;;
        *'get deployment policy-retrieval-service -o jsonpath='*) printf '%s' test-policy ;;
        *) return 0 ;;
    esac
}

(
    source "$TEST_DIR/../deploy-services.sh"
    KUBECTL_CONTEXT=test
    NAMESPACE=test
    RESOLVED_CHART=synthetic-chart
    WORK_DIR=/synthetic
    AI_SERVICE_ACCOUNT=test-ai
    POLICY_SERVICE_ACCOUNT=test-policy
    for MOCK_HELM_VERSION in 4 3; do
        configure_helm_upgrade_conflict_handling
        for DEPLOY_MODE in first-deploy redeploy; do
            MOCK_UPGRADES=0
            deploy_services >/dev/null
            [[ "$MOCK_UPGRADES" -eq 8 ]]
        done
    done
)
(
    source "$TEST_DIR/../deploy-azn-server.sh"
    for MOCK_HELM_VERSION in 4 3; do
        configure_helm_upgrade_conflict_handling
        for DEPLOY_MODE in first-deploy redeploy; do
            MOCK_UPGRADES=0
            build_helm_overrides
            deploy >/dev/null
            [[ "$MOCK_UPGRADES" -eq 1 ]]
        done
    done
)
printf 'PASS: Helm 3/4 upgrades for Azn and all services, first-deploy and redeploy.\n'
