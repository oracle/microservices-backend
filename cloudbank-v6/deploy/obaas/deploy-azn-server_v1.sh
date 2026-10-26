#!/usr/bin/env bash

# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at
# https://oss.oracle.com/licenses/upl.

set -Eeuo pipefail
set +x

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/obaas-version.sh"
readonly REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly ENV_FILE="$REPOSITORY_ROOT/.env"
readonly CORE_DEPLOY_SCRIPT="$SCRIPT_DIR/deploy-azn-server.sh"
readonly MICROTX_SECURITY_SCRIPT="$SCRIPT_DIR/../microtx/oke-obaas/secure-microtx-workflows.sh"
readonly RUN_COMPOSE_SCRIPT="$REPOSITORY_ROOT/run-compose.sh"
readonly REPOSITORY_NAME="cloudbank-ai/azn-server"

DEPLOY_MODE=""
OCI_REGION=""
OKE_CLUSTER_OCID=""
CLOUDBANK_KUBECONFIG_PATH=""
OCI_COMPARTMENT_OCID=""
OCI_IDENTITY_NAME=""
OCI_AUTH_TOKEN=""
IMAGE_PULL_SECRET=""
NEW_IMAGE_TAG="${NEW_IMAGE_TAG:-}"
KUBECTL_CONTEXT=""
OBAAS_RELEASE=""
OBAAS_NAMESPACE=""
OBAAS_VERSION=""
CONFIGURED_OBAAS_RELEASE=""
CONFIGURED_MICROTX_NAMESPACE=""
AZN_ISSUER_URI=""
OCIR_HOST=""
OCIR_NAMESPACE=""
IMAGE_REPOSITORY=""
TARGET_PLATFORMS=""
WORK_DIR=""
DOCKER_LOGGED_IN=false
PORT_FORWARD_PID=""

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 2
}

info() {
    printf '%s\n' "$*"
}

usage() {
    cat <<'EOF'
Prepare and deploy CloudBank AI azn-server on OCI OBaaS.

Usage:
  ./deploy/obaas/deploy-azn-server_v1.sh first-deploy
  ./deploy/obaas/deploy-azn-server_v1.sh redeploy

The repository-root .env must contain the deployment inputs documented in
./deploy/obaas/azn-server-runbook.md. NEW_IMAGE_TAG must be exported by the
caller and must identify a new immutable image tag.
EOF
}

parse_args() {
    if [[ $# -eq 1 && ( "$1" == "-h" || "$1" == "--help" ) ]]; then
        usage
        exit 0
    fi
    [[ $# -eq 1 ]] || {
        usage >&2
        exit 2
    }
    DEPLOY_MODE="$1"
    case "$DEPLOY_MODE" in
        first-deploy | redeploy) ;;
        *) die "mode must be 'first-deploy' or 'redeploy'" ;;
    esac
}

require_commands() {
    local command_name

    for command_name in oci kubectl helm docker jq openssl curl awk sed grep sort mktemp mkdir chmod dirname head tail; do
        command -v "$command_name" >/dev/null 2>&1 || die "$command_name is required"
    done
    docker info >/dev/null 2>&1 || die "Docker daemon is unavailable"
    docker buildx version >/dev/null 2>&1 || die "Docker Buildx is unavailable"
    docker compose version >/dev/null 2>&1 || die "Docker Compose is unavailable"
}

env_count() {
    local variable_name="$1"
    awk -F= -v variable_name="$variable_name" \
        '$1 == variable_name { count++ } END { print count + 0 }' "$ENV_FILE"
}

env_value() {
    local variable_name="$1"
    awk -F= -v variable_name="$variable_name" \
        '$1 == variable_name { print substr($0, index($0, "=") + 1) }' "$ENV_FILE" |
        tail -n 1
}

read_required_env_value() {
    local variable_name="$1"
    local value

    [[ "$(env_count "$variable_name")" -eq 1 ]] ||
        die "$ENV_FILE must contain exactly one $variable_name entry"
    value="$(env_value "$variable_name")"
    [[ -n "$value" ]] || die "$ENV_FILE variable $variable_name must not be empty"
    case "$value" in
        *$'\n'* | *$'\r'*) die "$ENV_FILE variable $variable_name contains a newline" ;;
    esac
    printf '%s' "$value"
}

load_bootstrap_configuration() {
    [[ -f "$ENV_FILE" ]] || die ".env is missing; follow azn-server-runbook.md"

    OCI_REGION="$(read_required_env_value OCI_REGION)"
    OKE_CLUSTER_OCID="$(read_required_env_value OKE_CLUSTER_OCID)"
    CLOUDBANK_KUBECONFIG_PATH="$(read_required_env_value CLOUDBANK_KUBECONFIG_PATH)"
    OCI_COMPARTMENT_OCID="$(read_required_env_value OCI_COMPARTMENT_OCID)"
    OCI_IDENTITY_NAME="$(read_required_env_value OCI_IDENTITY_NAME)"
    OCI_AUTH_TOKEN="$(read_required_env_value OCI_AUTH_TOKEN)"
    CONFIGURED_OBAAS_RELEASE="$(read_required_env_value OBAAS_RELEASE)"
    CONFIGURED_MICROTX_NAMESPACE="$(read_required_env_value MICROTX_NAMESPACE)"

    [[ "$OCI_REGION" =~ ^[a-z0-9]+([a-z0-9-]*[a-z0-9])?$ ]] ||
        die "OCI_REGION must be an OCI region identifier"
    [[ "$OKE_CLUSTER_OCID" =~ ^ocid1\.cluster\.[A-Za-z0-9._-]+$ ]] ||
        die "OKE_CLUSTER_OCID is not a valid OKE cluster OCID"
    [[ "$OCI_COMPARTMENT_OCID" =~ ^ocid1\.compartment\.[A-Za-z0-9._-]+$ ]] ||
        die "OCI_COMPARTMENT_OCID is not a valid compartment OCID"
    [[ "$CLOUDBANK_KUBECONFIG_PATH" == /* && "$CLOUDBANK_KUBECONFIG_PATH" != "/" ]] ||
        die "CLOUDBANK_KUBECONFIG_PATH must be an absolute file path"
    [[ "$OCI_IDENTITY_NAME" != *[[:space:]]* ]] ||
        die "OCI_IDENTITY_NAME must not contain whitespace"
    [[ "$CONFIGURED_OBAAS_RELEASE" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]] ||
        die "OBAAS_RELEASE must be a DNS-1123 name"
    [[ "$CONFIGURED_MICROTX_NAMESPACE" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]] ||
        die "MICROTX_NAMESPACE must be a DNS-1123 name"
    [[ "$NEW_IMAGE_TAG" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]] ||
        die "NEW_IMAGE_TAG must be exported with a valid immutable image tag"
    [[ "$NEW_IMAGE_TAG" != latest ]] || die "refusing mutable image tag 'latest'"
}

prepare_kubeconfig() {
    local kubeconfig_directory
    local oke_public_endpoint
    local oke_kube_endpoint="PUBLIC_ENDPOINT"

    kubeconfig_directory="$(dirname "$CLOUDBANK_KUBECONFIG_PATH")"
    if [[ ! -d "$kubeconfig_directory" ]]; then
        mkdir -p "$kubeconfig_directory"
        chmod 700 "$kubeconfig_directory"
    fi

    oke_public_endpoint="$(oci ce cluster get \
        --cluster-id "$OKE_CLUSTER_OCID" \
        --region "$OCI_REGION" \
        --query 'data.endpoints."public-endpoint"' \
        --raw-output)"
    case "$oke_public_endpoint" in
        '' | null | None)
            oke_kube_endpoint="PRIVATE_ENDPOINT"
            info "The OKE cluster uses its private Kubernetes API endpoint."
            ;;
    esac
    unset oke_public_endpoint

    oci ce cluster create-kubeconfig \
        --cluster-id "$OKE_CLUSTER_OCID" \
        --file "$CLOUDBANK_KUBECONFIG_PATH" \
        --region "$OCI_REGION" \
        --token-version 2.0.0 \
        --kube-endpoint "$oke_kube_endpoint" >/dev/null
    chmod 600 "$CLOUDBANK_KUBECONFIG_PATH"

    export KUBECONFIG="$CLOUDBANK_KUBECONFIG_PATH"
    KUBECTL_CONTEXT="$(kubectl config current-context)"
    [[ -n "$KUBECTL_CONTEXT" ]] || die "the generated kubeconfig has no current context"
    kubectl --context "$KUBECTL_CONTEXT" cluster-info >/dev/null
    info "OKE kubeconfig and kubectl context are ready."
}

detect_obaas_target() {
    local target

    target="$(helm list \
        --kube-context "$KUBECTL_CONTEXT" \
        --all-namespaces \
        --output json |
        jq -er '[.[] | select(.chart | test("^obaas-[0-9]"))] |
          if length == 1 then
            .[0] | [.name, .namespace, .app_version] | @tsv
          else
            error("expected exactly one OBaaS platform release; found \(length)")
          end')" || die "could not identify a unique OBaaS platform release"
    IFS=$'\t' read -r OBAAS_RELEASE OBAAS_NAMESPACE OBAAS_VERSION <<<"$target"
    obaas_version_at_least "$OBAAS_VERSION" ||
        die "OBaaS appVersion '$OBAAS_VERSION' must be a semantic version >= 2.1.0"
    [[ "$OBAAS_RELEASE" == "$CONFIGURED_OBAAS_RELEASE" ]] ||
        die "detected OBaaS release '$OBAAS_RELEASE', but .env specifies '$CONFIGURED_OBAAS_RELEASE'"
    [[ "$OBAAS_NAMESPACE" == "$CONFIGURED_MICROTX_NAMESPACE" ]] ||
        die "detected OBaaS namespace '$OBAAS_NAMESPACE', but .env specifies '$CONFIGURED_MICROTX_NAMESPACE'"
    kubectl --context "$KUBECTL_CONTEXT" get namespace "$OBAAS_NAMESPACE" >/dev/null
    info "OBaaS target: release=$OBAAS_RELEASE namespace=$OBAAS_NAMESPACE appVersion=$OBAAS_VERSION"
}

validate_microtx_target() {
    local resource
    for resource in \
        "configmap/${OBAAS_RELEASE}-otmm-config" \
        "deployment/${OBAAS_RELEASE}-otmm-console" \
        "deployment/${OBAAS_RELEASE}-otmm-workflow-server" \
        "statefulset/${OBAAS_RELEASE}-otmm-tcs"; do
        kubectl --context "$KUBECTL_CONTEXT" --namespace "$OBAAS_NAMESPACE" \
            get "$resource" >/dev/null 2>&1 ||
            die "required MicroTx resource '$resource' is missing; enable the OBaaS Console and Workflow Server before this deployment"
    done
}

initialize_local_configuration() {
    local secret_name
    local existing_application_secrets=0

    if [[ "$DEPLOY_MODE" == "first-deploy" ]]; then
        for secret_name in \
            cloudbank-ai-azn-db-authn \
            cloudbank-ai-azn-auth \
            cloudbank-ai-azn-microtx-console \
            cloudbank-ai-azn-signing-key; do
            if kubectl --context "$KUBECTL_CONTEXT" --namespace "$OBAAS_NAMESPACE" \
                get secret "$secret_name" >/dev/null 2>&1; then
                existing_application_secrets=$((existing_application_secrets + 1))
            fi
        done
        if [[ "$existing_application_secrets" -eq 0 ]]; then
            "$RUN_COMPOSE_SCRIPT" init --schema-profile runtime
        else
            info "Existing CloudBank application Secrets detected; preserving local generated values for first-deploy recovery."
        fi
    fi
    IMAGE_PULL_SECRET="$(read_required_env_value IMAGE_PULL_SECRET)"
    [[ "$IMAGE_PULL_SECRET" =~ ^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$ ]] ||
        die "IMAGE_PULL_SECRET in .env is not a valid Kubernetes resource name"
}

resolve_ocir_target() {
    OCIR_HOST="ocir.${OCI_REGION}.oci.oraclecloud.com"
    OCIR_NAMESPACE="$(oci os ns get \
        --region "$OCI_REGION" \
        --query data \
        --raw-output)"
    [[ "$OCIR_NAMESPACE" =~ ^[a-z0-9]+([._-][a-z0-9]+)*$ ]] ||
        die "OCI CLI did not return a valid OCIR namespace"
    IMAGE_REPOSITORY="$OCIR_HOST/$OCIR_NAMESPACE/$REPOSITORY_NAME"
}

ensure_private_ocir_repository() {
    local repository_visibility
    local repository_count

    repository_visibility="$(oci artifacts container repository list \
        --compartment-id "$OCI_COMPARTMENT_OCID" \
        --display-name "$REPOSITORY_NAME" \
        --region "$OCI_REGION" \
        --query 'data.items[*]."is-public"' \
        --output json)"
    repository_count="$(jq -er 'length' <<<"$repository_visibility")"

    case "$repository_count" in
        0)
            [[ "$DEPLOY_MODE" == "first-deploy" ]] ||
                die "OCIR repository '$REPOSITORY_NAME' does not exist"
            oci artifacts container repository create \
                --compartment-id "$OCI_COMPARTMENT_OCID" \
                --display-name "$REPOSITORY_NAME" \
                --is-public false \
                --region "$OCI_REGION" >/dev/null
            info "Created private OCIR repository '$REPOSITORY_NAME'."
            ;;
        1)
            jq -e '.[0] == false' <<<"$repository_visibility" >/dev/null ||
                die "existing OCIR repository '$REPOSITORY_NAME' is public"
            info "Private OCIR repository '$REPOSITORY_NAME' is ready."
            ;;
        *) die "unexpected number of matching OCIR repositories" ;;
    esac
}

sync_ocir_pull_secret() {
    local docker_config_dir="$WORK_DIR/pull-secret-docker-config"
    local secret_type

    if kubectl --context "$KUBECTL_CONTEXT" --namespace "$OBAAS_NAMESPACE" \
        get secret "$IMAGE_PULL_SECRET" >/dev/null 2>&1; then
        secret_type="$(kubectl --context "$KUBECTL_CONTEXT" --namespace "$OBAAS_NAMESPACE" \
            get secret "$IMAGE_PULL_SECRET" -o jsonpath='{.type}')"
        [[ "$secret_type" == "kubernetes.io/dockerconfigjson" ]] ||
            die "existing image pull Secret '$IMAGE_PULL_SECRET' has type '$secret_type'"
    else
        [[ "$DEPLOY_MODE" == "first-deploy" ]] ||
            die "redeploy requires existing image pull Secret '$IMAGE_PULL_SECRET'"
    fi

    mkdir -p "$docker_config_dir"
    chmod 700 "$docker_config_dir"
    # Kubernetes needs inline auth; Docker Desktop may store login credentials
    # in a host credential helper that is unavailable to the cluster.
    (
        umask 077
        printf '%s' "$OCI_AUTH_TOKEN" |
            jq -Rs --arg username "$OCI_IDENTITY_NAME" --arg registry "$OCIR_HOST" \
                '{auths: {($registry): {auth: (($username + ":" + .) | @base64)}}}' \
                > "$docker_config_dir/config.json"
    )
    kubectl --context "$KUBECTL_CONTEXT" --namespace "$OBAAS_NAMESPACE" \
        create secret generic "$IMAGE_PULL_SECRET" \
        --type=kubernetes.io/dockerconfigjson \
        --from-file=.dockerconfigjson="$docker_config_dir/config.json" \
        --dry-run=client -o yaml |
        kubectl --context "$KUBECTL_CONTEXT" --namespace "$OBAAS_NAMESPACE" \
            apply --server-side --field-manager=cloudbank-ocir-pull-secret --force-conflicts -f - >/dev/null
    info "Synchronized private-OCIR image pull Secret '$IMAGE_PULL_SECRET' using OCI_AUTH_TOKEN."
}

login_to_ocir() {
    printf '%s' "$OCI_AUTH_TOKEN" |
        docker login \
            --username "$OCI_IDENTITY_NAME" \
            --password-stdin "$OCIR_HOST" >/dev/null
    DOCKER_LOGGED_IN=true
    info "Authenticated the local Docker client to OCIR."
}

detect_target_platforms() {
    local architectures
    local architecture

    architectures="$(kubectl --context "$KUBECTL_CONTEXT" get nodes \
        --output jsonpath='{range .items[*]}{.status.nodeInfo.architecture}{"\n"}{end}' |
        sort -u)"
    [[ -n "$architectures" ]] || die "the OKE cluster returned no node architecture"

    while IFS= read -r architecture; do
        case "$architecture" in
            amd64 | arm64) ;;
            *) die "unsupported Kubernetes node architecture: $architecture" ;;
        esac
        TARGET_PLATFORMS="${TARGET_PLATFORMS}${TARGET_PLATFORMS:+,}linux/$architecture"
    done <<<"$architectures"
}

build_and_push_image() {
    local image_reference="$IMAGE_REPOSITORY:$NEW_IMAGE_TAG"

    detect_target_platforms
    info "Building and pushing $image_reference for $TARGET_PLATFORMS."
    docker buildx build \
        --platform "$TARGET_PLATFORMS" \
        --target azn-server \
        --tag "$image_reference" \
        --push \
        "$REPOSITORY_ROOT"
    docker buildx imagetools inspect "$image_reference" >/dev/null
    info "Published and verified $image_reference."
}

run_deployment_dry_run() {
    info "Running the Helm lint and render checks."
    NEW_IMAGE_TAG="$NEW_IMAGE_TAG" \
    AZN_DEPLOY_DRY_RUN=true \
    AZN_DEPLOY_ASSUME_YES=true \
        "$CORE_DEPLOY_SCRIPT" "$DEPLOY_MODE"
}

confirm_deployment() {
    local answer

    [[ -t 0 ]] || die "deployment confirmation requires an interactive terminal"
    printf '\nDry-run checks passed. Proceed with %s and MicroTx OIDC configuration? [y/N] ' "$DEPLOY_MODE"
    IFS= read -r answer
    case "$answer" in
        y | Y | yes | YES) ;;
        *) info "Deployment cancelled after the successful dry run."; exit 0 ;;
    esac
}

run_deployment() {
    NEW_IMAGE_TAG="$NEW_IMAGE_TAG" \
    AZN_DEPLOY_DRY_RUN=false \
    AZN_DEPLOY_ASSUME_YES=true \
        "$CORE_DEPLOY_SCRIPT" "$DEPLOY_MODE"
}

show_deployment_results() {
    local secret_name

    info ""
    info "OCIR repositories"
    oci artifacts container repository list \
        --compartment-id "$OCI_COMPARTMENT_OCID" \
        --region "$OCI_REGION" \
        --is-public false \
        --lifecycle-state AVAILABLE \
        --all \
        --sort-by DISPLAYNAME \
        --sort-order ASC \
        --query 'data.items[].{Repository:"display-name",Images:"image-count",Created:"time-created"}' \
        --output table

    info ""
    info "Published azn-server images"
    oci artifacts container image list \
        --compartment-id "$OCI_COMPARTMENT_OCID" \
        --region "$OCI_REGION" \
        --repository-name "$REPOSITORY_NAME" \
        --all \
        --sort-by TIMECREATED \
        --sort-order DESC \
        --query 'data.items[].{Repository:"repository-name",Tag:version,Digest:digest,Created:"time-created"}' \
        --output table

    info ""
    info "Kubernetes resources"
    kubectl --context "$KUBECTL_CONTEXT" --namespace "$OBAAS_NAMESPACE" \
        get deployment,service azn-server
    kubectl --context "$KUBECTL_CONTEXT" --namespace "$OBAAS_NAMESPACE" \
        get endpointslice \
        --selector kubernetes.io/service-name=azn-server

    for secret_name in \
        cloudbank-ai-azn-db-authn \
        cloudbank-ai-azn-auth \
        cloudbank-ai-azn-microtx-console \
        cloudbank-ai-azn-signing-key; do
        kubectl --context "$KUBECTL_CONTEXT" --namespace "$OBAAS_NAMESPACE" \
            get secret "$secret_name" \
            -o custom-columns=NAME:.metadata.name,TYPE:.type --no-headers
    done
}

verify_http_endpoints() {
    local port_forward_log="$WORK_DIR/azn-port-forward.log"
    local local_port=""
    local attempt
    local metadata

    kubectl --context "$KUBECTL_CONTEXT" --namespace "$OBAAS_NAMESPACE" \
        port-forward --address 127.0.0.1 service/azn-server :8080 \
        >"$port_forward_log" 2>&1 &
    PORT_FORWARD_PID=$!

    for attempt in {1..50}; do
        local_port="$(sed -n \
            's/^Forwarding from 127\.0\.0\.1:\([0-9][0-9]*\) -> 8080$/\1/p' \
            "$port_forward_log" | head -n 1)"
        [[ -n "$local_port" ]] && break
        kill -0 "$PORT_FORWARD_PID" >/dev/null 2>&1 ||
            die "azn-server port-forward stopped before becoming ready"
        sleep 0.2
    done
    [[ -n "$local_port" ]] || die "azn-server port-forward did not become ready"

    curl --fail --silent "http://127.0.0.1:$local_port/actuator/health" |
        jq -e '.status == "UP"' >/dev/null || die "azn-server health check failed"
    metadata="$(curl --fail --silent \
        "http://127.0.0.1:$local_port/.well-known/openid-configuration")" ||
        die "azn-server OpenID metadata check failed"
    jq -e --arg expected "$AZN_ISSUER_URI" \
        '.issuer == $expected' <<<"$metadata" >/dev/null ||
        die "azn-server issuer does not match AZN_ISSUER_URI in .env"
    metadata=""
    curl --fail --silent "http://127.0.0.1:$local_port/oauth2/jwks" |
        jq -e '.keys | length > 0' >/dev/null || die "azn-server JWKS check failed"
    info "PASS: azn-server health, issuer metadata, and JWKS checks."
}

cleanup() {
    OCI_AUTH_TOKEN=""
    if [[ -n "${PORT_FORWARD_PID:-}" ]]; then
        kill "$PORT_FORWARD_PID" >/dev/null 2>&1 || true
        wait "$PORT_FORWARD_PID" 2>/dev/null || true
    fi
    if [[ "$DOCKER_LOGGED_IN" == true && -n "${OCIR_HOST:-}" ]]; then
        docker logout "$OCIR_HOST" >/dev/null 2>&1 || true
    fi
    if [[ -n "${WORK_DIR:-}" && -d "$WORK_DIR" ]]; then
        rm -rf -- "$WORK_DIR"
    fi
}

main() {
    parse_args "$@"
    require_commands
    load_bootstrap_configuration

    WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cloudbank-azn-v1.XXXXXX")"
    chmod 700 "$WORK_DIR"
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' HUP TERM

    prepare_kubeconfig
    detect_obaas_target
    validate_microtx_target
    initialize_local_configuration
    AZN_ISSUER_URI="$(read_required_env_value AZN_ISSUER_URI)"
    [[ "$AZN_ISSUER_URI" == 'http://localhost:8080' ]] ||
        die "this local port-forward profile requires AZN_ISSUER_URI=http://localhost:8080"
    [[ -x "$MICROTX_SECURITY_SCRIPT" ]] || die "MicroTx security helper is missing or not executable"
    resolve_ocir_target
    ensure_private_ocir_repository
    login_to_ocir
    sync_ocir_pull_secret
    build_and_push_image
    run_deployment_dry_run
    confirm_deployment
    run_deployment
    show_deployment_results
    verify_http_endpoints
    info "Configuring and verifying MicroTx OIDC using the deployment confirmation."
    "$MICROTX_SECURITY_SCRIPT" --enable --yes

    info ""
    info "SUCCESS: azn-server $DEPLOY_MODE completed and all verification checks passed."
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
