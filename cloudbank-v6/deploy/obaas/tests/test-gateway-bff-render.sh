#!/usr/bin/env bash
# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at
# https://oss.oracle.com/licenses/upl/.

set -Eeuo pipefail

readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
mkdir -p "$ROOT_DIR/.cloudbank-local"
TEST_DIR="$(mktemp -d "$ROOT_DIR/.cloudbank-local/bff-render-test.XXXXXX")"
trap 'rm -rf -- "$TEST_DIR"' EXIT
mkdir -p "$TEST_DIR/bin"

cat >"$TEST_DIR/test.env" <<'EOF'
CLOUDBANK_KUBECONFIG_PATH=/tmp/cloudbank-test-kubeconfig
MICROTX_NAMESPACE=cloudbankai1
IMAGE_PULL_SECRET=cloudbank-ai-ocir-pull
AZN_ISSUER_URI=http://localhost:8080
BFF_IMAGE_TAG=test-123
BFF_AUTHORIZATION_URI=http://127.0.0.1:18080/oauth2/authorize
AZN_AUTHORIZATION_SERVER_BFF_CLIENT_REDIRECT_URI=http://127.0.0.1:5173/bff/auth/callback
EOF

cat >"$TEST_DIR/bin/kubectl" <<'EOF'
#!/usr/bin/env bash
case "$*" in
    'config current-context') printf '%s' 'test-oke-context' ;;
    *'get deployment azn-server -o jsonpath='*)
        printf '%s' 'ocir.eu-frankfurt-1.oci.oraclecloud.com/testnamespace/cloudbank-ai/azn-server:old-tag' ;;
    *'get deployment azn-server -o go-template='*AZN_ISSUER_URI*)
        printf '%s' "${TEST_LIVE_ISSUER:-http://localhost:8080}" ;;
    *'get deployment loan-application-service -o go-template='*AZN_ISSUER_URI*)
        printf '%s' "${TEST_LOAN_ISSUER:-${TEST_LIVE_ISSUER:-http://localhost:8080}}" ;;
    *'get deployment loan-application-service -o go-template='*MICROTX_WORKFLOW_URL*)
        printf '%s' 'http://obaas-otmm-workflow-server.cloudbankai1.svc.cluster.local:9010/workflow-server' ;;
    *'get service loan-application-service -o jsonpath='*) printf '%s' '8081' ;;
    *'get deployment azn-server -o go-template='*AZN_AUTHORIZATION_SERVER_BFF_CLIENT_SECRET*)
        printf '%s' 'yes' ;;
    *'get deployment azn-server -o go-template='*AZN_AUTHORIZATION_SERVER_BFF_CLIENT_REDIRECT_URI*)
        printf '%s' 'yes' ;;
    *'get secret cloudbank-ai-azn-auth -o go-template='*bff-client-secret*)
        printf '%s' 'yes' ;;
    *'get secret cloudbank-ai-azn-auth -o go-template='*microtx-client-secret*)
        printf '%s' 'yes' ;;
    *'get secret cloudbank-ai-azn-auth -o go-template='*bff-redirect-uri*)
        printf '%s' "$TEST_REDIRECT_BASE64" ;;
    *'get deployment azn-server'*) ;;
    *'get service loan-application-service'*) ;;
    *'get secret cloudbank-ai-ocir-pull'*) ;;
    *'rollout status deployment/gateway-bff-service'*) ;;
    *'get service gateway-bff-service'*) ;;
    *) printf 'Unexpected kubectl call\n' >&2; exit 1 ;;
esac
EOF
cat >"$TEST_DIR/bin/helm" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    lint) exit 0 ;;
    template) printf '%s\n' "$*" >"$TEST_HELM_ARGS" ;;
    upgrade)
        if [[ "$2" == --help ]]; then
            if [[ "${TEST_HELM_VERSION:-4}" == 4 ]]; then
                printf '  --server-side string\n  --force-conflicts\n'
            else
                printf '  --timeout duration\n'
            fi
        else
            printf '%s\n' "$*" >"$TEST_HELM_ARGS"
        fi ;;
    *) printf 'Unexpected Helm call\n' >&2; exit 1 ;;
esac
EOF
chmod 700 "$TEST_DIR/bin/kubectl" "$TEST_DIR/bin/helm"

redirect_base64="$(printf '%s' 'http://127.0.0.1:5173/bff/auth/callback' | base64 | tr -d '\n')"
env -i PATH="$TEST_DIR/bin:/usr/bin:/bin" \
    BFF_ENV_FILE="$TEST_DIR/test.env" \
    TEST_REDIRECT_BASE64="$redirect_base64" \
    TEST_HELM_ARGS="$TEST_DIR/helm-args" \
    "$ROOT_DIR/deploy/obaas/deploy-gateway-bff.sh" render

grep -Fq -- '--namespace cloudbankai1' "$TEST_DIR/helm-args"
grep -Fq -- '--set-string image=ocir.eu-frankfurt-1.oci.oraclecloud.com/testnamespace/cloudbank-ai/gateway-bff-service:test-123' "$TEST_DIR/helm-args"
grep -Fq -- '--set-string imagePullSecret=cloudbank-ai-ocir-pull' "$TEST_DIR/helm-args"
grep -Fq -- '--set-string authorizationUri=http://127.0.0.1:18080/oauth2/authorize' "$TEST_DIR/helm-args"
grep -Fq -- '--set-string cookieSecure=false' "$TEST_DIR/helm-args"
grep -Fq -- '--set-string issuerUri=http://localhost:8080' "$TEST_DIR/helm-args"
grep -Fq -- '--set-string microtxBaseUrl=http://obaas-otmm-workflow-server.cloudbankai1.svc.cluster.local:9010/workflow-server/api' "$TEST_DIR/helm-args"

for microtx_url in \
    'http://workflow.example:9010/workflow-server' \
    'http://workflow.example:9010/workflow-server/' \
    'http://workflow.example:9010/workflow-server/api' \
    'http://workflow.example:9010/workflow-server/api/'; do
    env -i PATH="$TEST_DIR/bin:/usr/bin:/bin" \
        BFF_ENV_FILE="$TEST_DIR/test.env" BFF_MICROTX_BASE_URL="$microtx_url" \
        TEST_REDIRECT_BASE64="$redirect_base64" TEST_HELM_ARGS="$TEST_DIR/helm-args" \
        "$ROOT_DIR/deploy/obaas/deploy-gateway-bff.sh" render
    grep -Fq -- '--set-string microtxBaseUrl=http://workflow.example:9010/workflow-server/api ' "$TEST_DIR/helm-args"
done

for microtx_url in \
    'http://user:password@workflow.example:9010/workflow-server' \
    'http://workflow.example:9010/workflow-server?parameter=value' \
    'http://workflow.example:9010/workflow-server#fragment' \
    'http://workflow.example:9010/workflow-server,extra' \
    'http://workflow.example:9010/workflow server'; do
    if env -i PATH="$TEST_DIR/bin:/usr/bin:/bin" \
        BFF_ENV_FILE="$TEST_DIR/test.env" BFF_MICROTX_BASE_URL="$microtx_url" \
        TEST_REDIRECT_BASE64="$redirect_base64" TEST_HELM_ARGS="$TEST_DIR/helm-args" \
        "$ROOT_DIR/deploy/obaas/deploy-gateway-bff.sh" render \
        >"$TEST_DIR/microtx.out" 2>"$TEST_DIR/microtx.err"; then
        printf 'FAIL: invalid MicroTx URL was accepted\n' >&2
        exit 1
    fi
    grep -Fq 'BFF_MICROTX_BASE_URL must be' "$TEST_DIR/microtx.err"
done

if env -i PATH="$TEST_DIR/bin:/usr/bin:/bin" \
    BFF_ENV_FILE="$TEST_DIR/test.env" \
    BFF_CALLBACK_URI='https://example.test/bff/auth/callback' \
    TEST_REDIRECT_BASE64="$redirect_base64" \
    TEST_HELM_ARGS="$TEST_DIR/helm-args" \
    "$ROOT_DIR/deploy/obaas/deploy-gateway-bff.sh" render \
    >"$TEST_DIR/override.out" 2>"$TEST_DIR/override.err"; then
    printf 'Expected mismatched BFF_CALLBACK_URI to fail\n' >&2
    exit 1
fi
grep -Fq 'BFF_CALLBACK_URI does not match' "$TEST_DIR/override.err"
for mismatch in live loan; do
    case "$mismatch" in
        live) issuer_override=TEST_LIVE_ISSUER=http://old-issuer ;;
        loan) issuer_override=TEST_LOAN_ISSUER=http://old-issuer ;;
    esac
    if env -i PATH="$TEST_DIR/bin:/usr/bin:/bin" \
        BFF_ENV_FILE="$TEST_DIR/test.env" \
        "$issuer_override" TEST_REDIRECT_BASE64="$redirect_base64" \
        TEST_HELM_ARGS="$TEST_DIR/helm-args" \
        "$ROOT_DIR/deploy/obaas/deploy-gateway-bff.sh" render \
        >"$TEST_DIR/$mismatch.out" 2>"$TEST_DIR/$mismatch.err"; then
        printf 'FAIL: mismatched %s issuer was accepted\n' "$mismatch" >&2
        exit 1
    fi
    grep -Fiq 'issuer' "$TEST_DIR/$mismatch.err"
done
for helm_version in 3 4; do
    env -i PATH="$TEST_DIR/bin:/usr/bin:/bin" \
        BFF_ENV_FILE="$TEST_DIR/test.env" BFF_BUILD_PUSH=false \
        TEST_HELM_VERSION="$helm_version" \
        TEST_REDIRECT_BASE64="$redirect_base64" TEST_HELM_ARGS="$TEST_DIR/helm-args" \
        "$ROOT_DIR/deploy/obaas/deploy-gateway-bff.sh" deploy
    if [[ "$helm_version" == 4 ]]; then
        grep -Fq -- '--server-side=true --force-conflicts' "$TEST_DIR/helm-args"
    elif grep -Fq -- '--force-conflicts' "$TEST_DIR/helm-args"; then
        printf 'FAIL: Helm 3 received a Helm 4 flag\n' >&2
        exit 1
    fi
done
printf 'PASS: BFF render normalizes MicroTx URLs and rejects invalid URLs, mismatched callback and issuers.\n'
