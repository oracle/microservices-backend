#!/usr/bin/env bash
# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.

set -Eeuo pipefail
set +x

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/helm-upgrade.sh"
readonly ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly CHART="$SCRIPT_DIR/gateway-bff"
readonly RELEASE="gateway-bff-service"
readonly ENV_FILE="${BFF_ENV_FILE:-$ROOT_DIR/.env}"
DOCKER_CONFIG_DIR=""

usage() {
    cat <<'EOF'
Usage: deploy-gateway-bff.sh render|deploy

The script reads existing deployment values from repository-root .env and the
running azn-server Deployment. Shell BFF_* values override .env values.
By default, deploy creates a unique image tag, authenticates to OCIR using
.env, builds/pushes only the BFF image, and updates only the BFF Helm release.
azn-server must already have its BFF OAuth client configured.

Optional: BFF_IMAGE, BFF_IMAGE_TAG, BFF_CALLBACK_URI,
BFF_AUTHORIZATION_URI, BFF_COOKIE_SECURE, BFF_BUILD_PUSH=false.
EOF
}

die() { printf 'ERROR: %s\n' "$*" >&2; exit 2; }
required() { [[ -n "${!1:-}" ]] || die "$1 is required"; }
env_count() {
    awk -F= -v key="$1" '$1 == key { count++ } END { print count + 0 }' "$ENV_FILE"
}
env_value() {
    awk -F= -v key="$1" '$1 == key { print substr($0, index($0, "=") + 1) }' "$ENV_FILE"
}
use_env_value() {
    local target="$1"
    local source="$2"
    local count
    local value

    [[ -n "${!target:-}" || ! -f "$ENV_FILE" ]] && return 0
    count="$(env_count "$source")"
    [[ "$count" -le 1 ]] || die "$ENV_FILE contains duplicate $source entries"
    [[ "$count" -eq 1 ]] || return 0
    value="$(env_value "$source")"
    [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] || die "$source contains a line break"
    if [[ -n "$value" ]]; then
        printf -v "$target" '%s' "$value"
    fi
}
cleanup() {
    if [[ -n "$DOCKER_CONFIG_DIR" && -d "$DOCKER_CONFIG_DIR" ]]; then
        rm -rf -- "$DOCKER_CONFIG_DIR"
    fi
}
prepare_isolated_docker_config() {
    local source_config_dir="${DOCKER_CONFIG:-${HOME:-}/.docker}"
    local buildx_plugin_path
    local buildx_plugin_metadata
    local state_dir

    if [[ -d "$source_config_dir" ]]; then
        source_config_dir="$(cd "$source_config_dir" && pwd)" ||
            die "could not resolve the Docker client configuration directory"
    fi
    buildx_plugin_metadata="$(docker info --format '{{json .ClientInfo.Plugins}}' 2>/dev/null || true)"
    buildx_plugin_path="$(jq -r \
        '[.[]? | select(.Name == "buildx") | .Path | select(type == "string" and length > 0)][0] // empty' \
        <<<"$buildx_plugin_metadata" 2>/dev/null || true)"
    if [[ -z "$buildx_plugin_path" && -x "$source_config_dir/cli-plugins/docker-buildx" ]]; then
        buildx_plugin_path="$source_config_dir/cli-plugins/docker-buildx"
    fi

    DOCKER_CONFIG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cloudbank-bff-docker.XXXXXX")"
    chmod 700 "$DOCKER_CONFIG_DIR"
    trap cleanup EXIT
    if [[ -f "$source_config_dir/config.json" ]]; then
        jq '{currentContext, proxies, features, experimental, cliPluginsExtraDirs}
            | with_entries(select(.value != null))' \
            "$source_config_dir/config.json" >"$DOCKER_CONFIG_DIR/config.json" ||
            die "could not prepare an isolated Docker client configuration"
        chmod 600 "$DOCKER_CONFIG_DIR/config.json"
    fi
    for state_dir in contexts buildx; do
        if [[ -d "$source_config_dir/$state_dir" ]]; then
            cp -R "$source_config_dir/$state_dir" "$DOCKER_CONFIG_DIR/$state_dir" ||
                die "could not preserve Docker $state_dir state"
        fi
    done
    if [[ -n "$buildx_plugin_path" && -x "$buildx_plugin_path" ]]; then
        mkdir -p "$DOCKER_CONFIG_DIR/cli-plugins"
        ln -s "$buildx_plugin_path" "$DOCKER_CONFIG_DIR/cli-plugins/docker-buildx" ||
            die "could not expose Docker Buildx in the isolated configuration"
    fi
    unset DOCKER_AUTH_CONFIG
    export DOCKER_CONFIG="$DOCKER_CONFIG_DIR"
    docker info >/dev/null 2>&1 || die "Docker daemon is unavailable with the isolated OCIR configuration"
    docker buildx version >/dev/null 2>&1 || die "Docker Buildx is unavailable with the isolated OCIR configuration"
    docker buildx inspect >/dev/null 2>&1 || die "Docker Buildx builder is unavailable with the isolated OCIR configuration"
}

[[ $# -eq 1 ]] || { usage; exit 2; }
mode="$1"
[[ "$mode" == render || "$mode" == deploy ]] || { usage; exit 2; }
[[ -f "$ENV_FILE" ]] || die "deployment configuration file $ENV_FILE is missing"
use_env_value BFF_KUBECONFIG BFF_KUBECONFIG
use_env_value BFF_KUBECONFIG CLOUDBANK_KUBECONFIG_PATH
required BFF_KUBECONFIG
export KUBECONFIG="$BFF_KUBECONFIG"
use_env_value BFF_KUBE_CONTEXT BFF_KUBE_CONTEXT
use_env_value BFF_NAMESPACE BFF_NAMESPACE
use_env_value BFF_NAMESPACE MICROTX_NAMESPACE
use_env_value BFF_IMAGE_PULL_SECRET BFF_IMAGE_PULL_SECRET
use_env_value BFF_IMAGE_PULL_SECRET IMAGE_PULL_SECRET
use_env_value BFF_IMAGE BFF_IMAGE
use_env_value BFF_IMAGE_TAG BFF_IMAGE_TAG
use_env_value BFF_ISSUER_URI BFF_ISSUER_URI
use_env_value BFF_AUTHORIZATION_URI BFF_AUTHORIZATION_URI
use_env_value BFF_CALLBACK_URI BFF_CALLBACK_URI
use_env_value BFF_CALLBACK_URI AZN_AUTHORIZATION_SERVER_BFF_CLIENT_REDIRECT_URI
use_env_value BFF_COOKIE_SECURE BFF_COOKIE_SECURE
use_env_value BFF_BUILD_PUSH BFF_BUILD_PUSH
use_env_value BFF_MICROTX_BASE_URL BFF_MICROTX_BASE_URL
use_env_value BFF_MICROTX_CLIENT_ID BFF_MICROTX_CLIENT_ID
command -v kubectl >/dev/null || die "kubectl is required"
command -v helm >/dev/null || die "helm is required"
BFF_KUBE_CONTEXT="${BFF_KUBE_CONTEXT:-$(kubectl config current-context)}"
required BFF_KUBE_CONTEXT
required BFF_NAMESPACE
required BFF_IMAGE_PULL_SECRET
BFF_AUTHORIZATION_URI="${BFF_AUTHORIZATION_URI:-http://127.0.0.1:8080/oauth2/authorize}"
BFF_CALLBACK_URI="${BFF_CALLBACK_URI:-http://127.0.0.1:5173/bff/auth/callback}"
if [[ -z "${BFF_COOKIE_SECURE:-}" ]]; then
    BFF_COOKIE_SECURE=true
    if [[ "$BFF_CALLBACK_URI" == http://* ]]; then
        BFF_COOKIE_SECURE=false
    fi
fi
[[ "$BFF_KUBE_CONTEXT" =~ ^[A-Za-z0-9._:@-]+$ ]] || die "invalid Kubernetes context"
[[ "$BFF_NAMESPACE" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]] || die "invalid namespace"
[[ "$BFF_IMAGE_PULL_SECRET" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]] || die "invalid image pull Secret name"
[[ "$BFF_COOKIE_SECURE" == true || "$BFF_COOKIE_SECURE" == false ]] || die "BFF_COOKIE_SECURE must be true or false"
[[ "${BFF_BUILD_PUSH:-true}" == true || "${BFF_BUILD_PUSH:-true}" == false ]] || die "BFF_BUILD_PUSH must be true or false"
[[ "$BFF_CALLBACK_URI" == http://127.0.0.1:* || "$BFF_CALLBACK_URI" == https://* ]] ||
    die "callback must be HTTPS or the local 127.0.0.1 test origin"
[[ "$BFF_CALLBACK_URI" == */bff/auth/callback ]] || die "callback path must be /bff/auth/callback"
if [[ "$BFF_CALLBACK_URI" == http://* && "$BFF_COOKIE_SECURE" != false ]]; then
    die "local HTTP callback requires BFF_COOKIE_SECURE=false"
fi
secret_name=cloudbank-ai-azn-auth
kubectl --context "$BFF_KUBE_CONTEXT" -n "$BFF_NAMESPACE" get deployment azn-server >/dev/null
kubectl --context "$BFF_KUBE_CONTEXT" -n "$BFF_NAMESPACE" get service loan-application-service >/dev/null
loan_service_port="$(kubectl --context "$BFF_KUBE_CONTEXT" -n "$BFF_NAMESPACE" \
    get service loan-application-service -o jsonpath='{.spec.ports[0].port}')"
[[ "$loan_service_port" =~ ^[0-9]+$ ]] || die "loan-application-service has no numeric Service port"
azn_image="$(kubectl --context "$BFF_KUBE_CONTEXT" -n "$BFF_NAMESPACE" \
    get deployment azn-server -o jsonpath='{.spec.template.spec.containers[0].image}')"
auto_image=false
if [[ -z "${BFF_IMAGE:-}" ]]; then
    auto_image=true
    [[ "$azn_image" == */cloudbank-ai/azn-server:* ]] ||
        die "cannot derive the BFF image repository from the azn-server Deployment; set BFF_IMAGE"
    image_tag="${BFF_IMAGE_TAG:-}"
    [[ -n "$image_tag" ]] || image_tag="bff-$(date -u +%Y%m%d%H%M%S)-$$"
    BFF_IMAGE="${azn_image%/azn-server:*}/gateway-bff-service:$image_tag"
fi
image_name="${BFF_IMAGE##*/}"
[[ "$image_name" == *:* && "${image_name##*:}" != latest && -n "${image_name##*:}" ]] ||
    die "BFF_IMAGE needs an immutable tag other than latest"
[[ "${image_name##*:}" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]] || die "invalid BFF image tag"
live_issuer="$(kubectl --context "$BFF_KUBE_CONTEXT" -n "$BFF_NAMESPACE" \
    get deployment azn-server -o 'go-template={{range .spec.template.spec.containers}}{{range .env}}{{if eq .name "AZN_ISSUER_URI"}}{{.value}}{{end}}{{end}}{{end}}')"
[[ -n "$live_issuer" ]] || die "azn-server Deployment has no AZN_ISSUER_URI"
loan_issuer="$(kubectl --context "$BFF_KUBE_CONTEXT" -n "$BFF_NAMESPACE" \
    get deployment loan-application-service -o 'go-template={{range .spec.template.spec.containers}}{{range .env}}{{if eq .name "AZN_ISSUER_URI"}}{{.value}}{{end}}{{end}}{{end}}')"
[[ "$loan_issuer" == "$live_issuer" ]] ||
    die "loan-application-service AZN_ISSUER_URI must match azn-server; correct or redeploy the loan service before deploying the BFF"
BFF_ISSUER_URI="${BFF_ISSUER_URI:-$live_issuer}"
[[ "$(env_count AZN_ISSUER_URI)" -eq 1 ]] || die ".env must contain exactly one AZN_ISSUER_URI"
configured_issuer="$(env_value AZN_ISSUER_URI)"
[[ -n "$configured_issuer" && "$live_issuer" == "$configured_issuer" ]] ||
    die "azn-server issuer must match AZN_ISSUER_URI in .env; redeploy azn-server before the BFF"
for value in "$BFF_IMAGE" "$BFF_ISSUER_URI" "$BFF_AUTHORIZATION_URI" "$BFF_CALLBACK_URI"; do
    [[ "$value" != *','* && "$value" != *$'\n'* && "$value" != *$'\r'* ]] ||
        die "deployment values cannot contain a comma or line break"
done
[[ "$live_issuer" == "$BFF_ISSUER_URI" ]] || die "BFF_ISSUER_URI must exactly match the azn-server Deployment issuer"
secret_present="$(kubectl --context "$BFF_KUBE_CONTEXT" -n "$BFF_NAMESPACE" \
    get secret "$secret_name" -o 'go-template={{if index .data "bff-client-secret"}}yes{{end}}')"
[[ "$secret_present" == yes ]] || die "Secret $secret_name lacks bff-client-secret; redeploy azn-server with deploy-azn-server_v1.sh first"
registered_redirect_base64="$(kubectl --context "$BFF_KUBE_CONTEXT" -n "$BFF_NAMESPACE" \
    get secret "$secret_name" -o 'go-template={{index .data "bff-redirect-uri"}}')"
expected_redirect_base64="$(printf '%s' "$BFF_CALLBACK_URI" | base64 | tr -d '\n')"
[[ "$registered_redirect_base64" == "$expected_redirect_base64" ]] ||
    die "BFF_CALLBACK_URI does not match azn-server's configured callback; use the registered URI or update the azn-server Secret and redeploy azn-server"
registered_env="$(kubectl --context "$BFF_KUBE_CONTEXT" -n "$BFF_NAMESPACE" \
    get deployment azn-server -o 'go-template={{range .spec.template.spec.containers}}{{range .env}}{{if eq .name "AZN_AUTHORIZATION_SERVER_BFF_CLIENT_SECRET"}}yes{{end}}{{end}}{{end}}')"
[[ "$registered_env" == yes ]] || die "redeploy azn-server with the dedicated BFF OAuth client before deploying the BFF"
registered_redirect_env="$(kubectl --context "$BFF_KUBE_CONTEXT" -n "$BFF_NAMESPACE" \
    get deployment azn-server -o 'go-template={{range .spec.template.spec.containers}}{{range .env}}{{if eq .name "AZN_AUTHORIZATION_SERVER_BFF_CLIENT_REDIRECT_URI"}}yes{{end}}{{end}}{{end}}')"
[[ "$registered_redirect_env" == yes ]] || die "azn-server Deployment lacks the BFF callback configuration"
kubectl --context "$BFF_KUBE_CONTEXT" -n "$BFF_NAMESPACE" \
    get secret "$BFF_IMAGE_PULL_SECRET" >/dev/null || die "image pull Secret not found"

azn_base="http://azn-server.$BFF_NAMESPACE.svc.cluster.local:8080"
loan_base="http://loan-application-service.$BFF_NAMESPACE.svc.cluster.local:$loan_service_port"
if [[ -z "${BFF_MICROTX_BASE_URL:-}" ]]; then
    BFF_MICROTX_BASE_URL="$(kubectl --context "$BFF_KUBE_CONTEXT" -n "$BFF_NAMESPACE" \
        get deployment loan-application-service -o 'go-template={{range .spec.template.spec.containers}}{{range .env}}{{if eq .name "MICROTX_WORKFLOW_URL"}}{{.value}}{{end}}{{end}}{{end}}')"
fi
BFF_MICROTX_CLIENT_ID="${BFF_MICROTX_CLIENT_ID:-microtx-workflow-client}"
if [[ -n "$BFF_MICROTX_BASE_URL" ]]; then
    [[ "$BFF_MICROTX_BASE_URL" =~ ^https?://[A-Za-z0-9.:-]+(/[-A-Za-z0-9._~]+)*/?$ ]] ||
        die "BFF_MICROTX_BASE_URL must be the cluster-reachable MicroTx API URL without credentials or query parameters"
    # The loan service stores the context root and appends /api in its client.
    # The BFF client expects the API base, as does complete-manual-review.sh.
    BFF_MICROTX_BASE_URL="${BFF_MICROTX_BASE_URL%/}"
    [[ "$BFF_MICROTX_BASE_URL" == */api ]] || BFF_MICROTX_BASE_URL="$BFF_MICROTX_BASE_URL/api"
    [[ "$BFF_MICROTX_CLIENT_ID" =~ ^[A-Za-z0-9._:-]+$ ]] || die "invalid MicroTx client ID"
    microtx_secret_present="$(kubectl --context "$BFF_KUBE_CONTEXT" -n "$BFF_NAMESPACE" \
        get secret "$secret_name" -o 'go-template={{if index .data "microtx-client-secret"}}yes{{end}}')"
    [[ "$microtx_secret_present" == yes ]] || die "MicroTx HUMAN support requires microtx-client-secret in the existing authorization Secret"
fi
values=(
    --set-string "image=$BFF_IMAGE"
    --set-string "imagePullSecret=$BFF_IMAGE_PULL_SECRET"
    --set-string "oauthSecretName=$secret_name"
    --set-string "issuerUri=$BFF_ISSUER_URI"
    --set-string "authorizationUri=$BFF_AUTHORIZATION_URI"
    --set-string "callbackUri=$BFF_CALLBACK_URI"
    --set-string "tokenUri=$azn_base/oauth2/token"
    --set-string "jwkSetUri=$azn_base/oauth2/jwks"
    --set-string "userInfoUri=$azn_base/userinfo"
    --set-string "loanBaseUrl=$loan_base"
    --set-string "microtxBaseUrl=$BFF_MICROTX_BASE_URL"
    --set-string "microtxClientId=$BFF_MICROTX_CLIENT_ID"
    --set-string "cookieSecure=$BFF_COOKIE_SECURE"
)

helm lint "$CHART" "${values[@]}" >/dev/null
if [[ "$mode" == render ]]; then
    helm template "$RELEASE" "$CHART" --namespace "$BFF_NAMESPACE" "${values[@]}"
    exit 0
fi
helm template "$RELEASE" "$CHART" --namespace "$BFF_NAMESPACE" "${values[@]}" >/dev/null
configure_helm_upgrade_conflict_handling
printf 'Helm upgrade conflict mode: %s\n' "${HELM_UPGRADE_CONFLICT_ARGS[*]:-standard}"

if [[ "${BFF_BUILD_PUSH:-true}" == true ]]; then
    command -v docker >/dev/null || die "docker is required for BFF_BUILD_PUSH=true"
    docker info >/dev/null 2>&1 || die "Docker daemon is unavailable"
    docker buildx version >/dev/null 2>&1 || die "Docker Buildx is required for BFF_BUILD_PUSH=true"
    docker buildx inspect >/dev/null 2>&1 || die "Docker Buildx builder is unavailable"
    command -v oci >/dev/null || die "OCI CLI is required for BFF_BUILD_PUSH=true"
    command -v jq >/dev/null || die "jq is required for BFF_BUILD_PUSH=true"
    use_env_value OCI_REGION OCI_REGION
    use_env_value OCI_COMPARTMENT_OCID OCI_COMPARTMENT_OCID
    use_env_value OCI_IDENTITY_NAME OCI_IDENTITY_NAME
    use_env_value OCI_AUTH_TOKEN OCI_AUTH_TOKEN
    required OCI_REGION
    required OCI_COMPARTMENT_OCID
    required OCI_IDENTITY_NAME
    required OCI_AUTH_TOKEN
    ocir_host="${BFF_IMAGE%%/*}"
    [[ "$ocir_host" == "ocir.$OCI_REGION.oci.oraclecloud.com" || "$ocir_host" == *.ocir.io ]] ||
        die "BFF_IMAGE must target OCIR when the script builds and pushes it"
    if [[ "$auto_image" == true ]]; then
        repository_visibility="$(oci artifacts container repository list \
            --compartment-id "$OCI_COMPARTMENT_OCID" \
            --display-name cloudbank-ai/gateway-bff-service \
            --region "$OCI_REGION" --query 'data.items[*]."is-public"' --output json)"
        repository_count="$(jq -er 'length' <<<"$repository_visibility")"
        case "$repository_count" in
            0)
                oci artifacts container repository create \
                    --compartment-id "$OCI_COMPARTMENT_OCID" \
                    --display-name cloudbank-ai/gateway-bff-service \
                    --is-public false --region "$OCI_REGION" >/dev/null
                printf 'Created private OCIR repository for gateway-bff-service.\n'
                ;;
            1)
                jq -e '.[0] == false' <<<"$repository_visibility" >/dev/null ||
                    die "the BFF OCIR repository must be private"
                ;;
            *) die "unexpected number of BFF OCIR repositories" ;;
        esac
    fi
    prepare_isolated_docker_config
    printf '%s' "$OCI_AUTH_TOKEN" | docker login \
        --username "$OCI_IDENTITY_NAME" --password-stdin "$ocir_host" >/dev/null
    OCI_AUTH_TOKEN=""
    architectures="$(kubectl --context "$BFF_KUBE_CONTEXT" get nodes \
        -o jsonpath='{range .items[*]}{.status.nodeInfo.architecture}{"\n"}{end}' | sort -u)"
    [[ -n "$architectures" ]] || die "OKE node architectures could not be detected"
    platforms=()
    while IFS= read -r architecture; do
        case "$architecture" in
            amd64|arm64) platforms+=("linux/$architecture") ;;
            *) die "unsupported OKE node architecture: $architecture" ;;
        esac
    done <<<"$architectures"
    platform_list="$(IFS=,; printf '%s' "${platforms[*]}")"
    docker buildx build --platform "$platform_list" \
        -f "$ROOT_DIR/src/gateway-bff-service/Dockerfile" \
        -t "$BFF_IMAGE" --push "$ROOT_DIR"
    docker buildx imagetools inspect "$BFF_IMAGE" >/dev/null || die "published image could not be verified"
fi

helm upgrade --install "$RELEASE" "$CHART" \
    --kube-context "$BFF_KUBE_CONTEXT" --namespace "$BFF_NAMESPACE" \
    --reset-values "${values[@]}" \
    ${HELM_UPGRADE_CONFLICT_ARGS[@]+"${HELM_UPGRADE_CONFLICT_ARGS[@]}"} --wait --timeout 5m
kubectl --context "$BFF_KUBE_CONTEXT" -n "$BFF_NAMESPACE" \
    rollout status "deployment/$RELEASE" --timeout=5m
kubectl --context "$BFF_KUBE_CONTEXT" -n "$BFF_NAMESPACE" get service "$RELEASE"
