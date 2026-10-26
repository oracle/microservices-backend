#!/usr/bin/env bash
set -Eeuo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# No real Kubernetes/Helm calls: exercise issuer transitions and startup ordering.
(
    source "$TEST_DIR/../deploy-azn-server.sh"
    AZN_ISSUER_URI=http://localhost:8080
    for DEPLOY_MODE in first-deploy redeploy; do
        build_helm_overrides
        [[ " ${HELM_OVERRIDES[*]} " == *' env[1].value=http://localhost:8080 '* ]]
    done
    kubectl() { printf '%s' "$AZN_ISSUER_URI"; }
    validate_issuer_transition
    kubectl() { printf '%s' 'http://azn-server.example.svc.cluster.local:8080'; }
    if (validate_issuer_transition) 2>/dev/null; then
        printf 'FAIL: redeploy silently changed the JWT issuer\n' >&2
        exit 1
    fi
)

(
    source "$TEST_DIR/../../microtx/oke-obaas/secure-microtx-workflows.sh"
    AZN_ISSUER_URI=http://localhost:8080
    CONTEXT=test
    NAMESPACE=test
    AZN_CONTAINER=app
    COORDINATOR_CONFIG=config
    CONSOLE_DEPLOYMENT=console
    WORKFLOW_DEPLOYMENT=workflow
    COORDINATOR_STATEFULSET=coordinator
    AZN_SECRET_PATCH='{}'
    AZN_DEPLOYMENT_PATCH='{}'
    COORDINATOR_PATCH='{}'
    CONSOLE_PATCH='{}'
    WORKFLOW_PATCH='{}'
    OIDC_BRIDGE_URL=http://bridge:8080
    MICROTX_PUBLIC_HOST=localhost
    MICROTX_PUBLIC_PORT=5002
    azn_ready=false
    bridge_ready=false
    console_ready=false
    MOCK_AUTH_ENDPOINT=http://localhost:8080/oauth2/authorize
    apply_console_secrets() { :; }
    patch_merge() { :; }
    apply_bridge() { :; }
    patch_strategic() {
        if [[ "$1" == deployment/console ]]; then
            [[ "$bridge_ready" == true ]] || { printf 'FAIL: Console patched before bridge readiness\n' >&2; exit 1; }
        fi
    }
    kubectl() {
        case "$*" in
            *'rollout status deployment/azn-server '*) azn_ready=true ;;
            *'rollout restart deployment/microtx-azn-oidc-bridge'*) [[ "$azn_ready" == true ]] ;;
            *'rollout status deployment/microtx-azn-oidc-bridge '*) bridge_ready=true ;;
            *'rollout restart deployment/console'*) [[ "$bridge_ready" == true ]] ;;
            *'rollout status deployment/console '*) console_ready=true ;;
            *'/.well-known/openid-configuration'*)
                [[ "$bridge_ready" == true ]]
                printf '{"issuer":"http://localhost:8080","authorization_endpoint":"%s","token_endpoint":"http://bridge:8080/oauth2/token","jwks_uri":"http://bridge:8080/oauth2/jwks"}' "$MOCK_AUTH_ENDPOINT" ;;
            *'--write-out'*'/consoleui/'*) printf '%s' "$MOCK_REDIRECT" ;;
            *) [[ "$*" == *'rollout '* ]] ;;
        esac
    }
    # Same path for an initial configuration and a reapplication.
    for scenario in first-deploy redeploy; do
        azn_ready=false bridge_ready=false console_ready=false
        apply_enable
        [[ "$console_ready" == true ]]
    done
    MOCK_AUTH_ENDPOINT=http://old-issuer/oauth2/authorize
    if (verify_bridge_discovery) 2>/dev/null; then
        printf 'FAIL: stale bridge authorization endpoint was accepted\n' >&2
        exit 1
    fi
    MOCK_REDIRECT=http://localhost:8080/oauth2/authorize?synthetic=true
    verify_console_redirect
    MOCK_REDIRECT=http://azn-server.example.svc.cluster.local:8080/oauth2/authorize?synthetic=true
    if (verify_console_redirect) 2>/dev/null; then
        printf 'FAIL: Console redirect to cluster DNS was accepted\n' >&2
        exit 1
    fi
    kubectl() { printf '%s' '{"items":[{"metadata":{"name":"gateway-bff-service"},"spec":{"template":{"spec":{"containers":[{"env":[{"name":"BFF_ISSUER_URI","value":"http://old-issuer"}]}]}}}}]}'; }
    if (verify_consumer_issuers) 2>/dev/null; then
        printf 'FAIL: mismatched BFF issuer was accepted\n' >&2
        exit 1
    fi
)
(
    source "$TEST_DIR/../../microtx/oke-obaas/secure-microtx-workflows.sh"
    mkdir -p "$TEST_DIR/../../../.cloudbank-local"
    WORK_DIR="$(mktemp -d "$TEST_DIR/../../../.cloudbank-local/oidc-forward-test.XXXXXX")"
    trap cleanup EXIT
    kubectl() {
        if [[ ! -f "$WORK_DIR/attempted" ]]; then
            : >"$WORK_DIR/attempted"
            return 1
        fi
        printf 'Forwarding from 127.0.0.1:50123 -> 9010\n'
        exec sleep 30
    }
    start_port_forward workflow 9010 "$WORK_DIR/forward.log" AZN_FORWARD_PID AZN_FORWARD_PORT
    [[ "$AZN_FORWARD_PORT" == 50123 ]]
)
(
    source "$TEST_DIR/../deploy-services.sh"
    KUBECTL_CONTEXT=test
    NAMESPACE=test
    MOCK_CONFIGURED_ISSUER=http://localhost:8080
    required_env_file_value() { printf '%s' "$MOCK_CONFIGURED_ISSUER"; }
    kubectl() { printf '%s' '{"spec":{"template":{"spec":{"containers":[{"env":[{"name":"AZN_ISSUER_URI","value":"http://localhost:8080"}]}]}}}}'; }
    resolve_azn_runtime_urls >/dev/null
    MOCK_CONFIGURED_ISSUER=http://old-issuer
    if (resolve_azn_runtime_urls) >/dev/null 2>&1; then
        printf 'FAIL: services accepted an issuer different from .env\n' >&2
        exit 1
    fi
)
printf 'PASS: stable issuer, ordered OIDC rollout, and stale redirect/consumer rejection.\n'
