#!/usr/bin/env bash

# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at
# https://oss.oracle.com/licenses/upl.

# Build, publish, and deploy the CloudBank AI services that complement
# azn-server. azn-server must already be healthy in the target namespace.

set -Eeuo pipefail
set +x

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/helm-upgrade.sh"
source "$SCRIPT_DIR/lib/obaas-version.sh"
readonly REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly ENV_FILE="$REPOSITORY_ROOT/.env"
readonly LAB_ADMIN_HELPER="$SCRIPT_DIR/provision-lab-admin.sh"
readonly DOCKERFILE="$REPOSITORY_ROOT/Dockerfile"
readonly DEFAULT_APP_CHART="obaas/obaas-sample-app"
readonly OBAAS_HELM_REPOSITORY="https://oracle.github.io/microservices-backend/helm"
readonly OBAAS_SAMPLE_APP_DATABASE_PATCH="$SCRIPT_DIR/obaas-sample-app-database-optional.patch"
readonly DEFAULT_REPOSITORY_PREFIX="cloudbank-ai"
readonly DEFAULT_AUTH_SECRET="cloudbank-ai-azn-auth"
readonly DEFAULT_DATABASE_SECRET_PREFIX="cloudbank-ai"
readonly DEFAULT_SCHEMA_OWNER_SECRET="cloudbank-ai-schema-owner"
readonly DEFAULT_MICROTX_WORKFLOW_PATH="/workflow-server"
readonly SCHEMA_INITIALIZER="cloudbank-schema-init"
readonly POLICY_LOADER="policy-loader"
readonly SERVICES=(
    loan-application-service
    document-ingest
    document-review-service
    decision-service
    ai-agent-service
    geographic-risk-service
    policy-retrieval-service
    workflow-token-refresh-worker
)
readonly DATABASE_IDENTITIES=(
    loan-application-service
    document-ingest
    document-review-service
    decision-service
    ai-agent-service
    geographic-risk-service
    policy-retrieval-service
    policy-loader
)
readonly PUBLISHED_IMAGES=(
    cloudbank-schema-init
    policy-loader
    loan-application-service
    document-ingest
    document-review-service
    decision-service
    ai-agent-service
    geographic-risk-service
    policy-retrieval-service
    workflow-token-refresh-worker
)

DEPLOY_MODE=""
KUBECTL_CONTEXT=""
OCI_REGION=""
NAMESPACE=""
OBAAS_RELEASE=""
OBAAS_VERSION=""
CLOUDBANK_KUBECONFIG_PATH=""
OKE_CLUSTER_OCID=""
OCI_COMPARTMENT_OCID=""
OCI_IDENTITY_NAME=""
OCI_AUTH_TOKEN=""
OCIR_NAMESPACE=""
OCIR_HOST=""
REPOSITORY_PREFIX="$DEFAULT_REPOSITORY_PREFIX"
OCI_REPOSITORY_PATH_PREFIX=""
IMAGE_REPOSITORY_PREFIX=""
IMAGE_TAG=""
IMAGE_PULL_SECRET=""
AUTH_SECRET="$DEFAULT_AUTH_SECRET"
DATABASE_SECRET_PREFIX="$DEFAULT_DATABASE_SECRET_PREFIX"
SCHEMA_OWNER_SECRET="$DEFAULT_SCHEMA_OWNER_SECRET"
DATABASE_SERVICE_B64=""
DATABASE_SERVICE_SOURCE=""
DB_PRIV_SECRET=""
WALLET_SECRET=""
APP_CHART="$DEFAULT_APP_CHART"
APP_CHART_VERSION=""
RESOLVED_CHART=""
TIMEOUT="8m"
TARGET_PLATFORMS=""
WORKFLOW_MODE="microtx"
MICROTX_WORKFLOW_URL=""
MICROTX_WORKFLOW_URL_SOURCE=""
AZN_ISSUER_URI=""
AZN_CLUSTER_URL=""
POLICY_AUTHENTICATION_TYPE="WORKLOAD_IDENTITY"
POLICY_OCI_REGION=""
POLICY_OCI_EMBEDDING_MODEL=""
POLICY_OCI_COMPARTMENT_ID=""
POLICY_OCI_FEDERATION_ENDPOINT=""
POLICY_SERVICE_ACCOUNT=""
AI_OCI_REGION=""
AI_OCI_GENAI_CHAT_MODEL=""
OKE_CLUSTER_COMPARTMENT_ID=""
AI_OCI_FEDERATION_ENDPOINT=""
AI_SERVICE_ACCOUNT=""
GEOGRAPHIC_RISK_LOG_GEOCODING_DETAILS=""
DRY_RUN=true
DB_SECRET_STATE="none"
SCHEMA_OWNER_SECRET_STATE="missing"
SCHEMA_JOB_NAME=""
POLICY_LOADER_JOB_NAME=""
WORK_DIR=""
ISOLATED_DOCKER_CONFIG=""
REGISTRY_LOGGED_IN=false
CREATED_DB_SECRETS=()
MISSING_DATABASE_IDENTITIES=()
HELM_LIST_ALL_STATUS_ARGS=()

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 2
}

info() {
    printf '%s\n' "$*"
}

usage() {
    cat <<'EOF'
Build, publish, and deploy the CloudBank AI services on OBaaS / OKE, version 2.1.0 or later.

Deploys, in dependency order:
  loan-application-service, document-ingest, document-review-service,
  decision-service, ai-agent-service, geographic-risk-service,
  policy-retrieval-service, workflow-token-refresh-worker

azn-server is not deployed by this script. It must already be healthy in the
target namespace and provide the CloudBank application authorization Secret.

Usage:
  ./deploy/obaas/deploy-services.sh first-deploy
  ./deploy/obaas/deploy-services.sh redeploy

The redeploy mode upgrades existing service releases and installs services
added to CloudBank after the original deployment. A service must have both its
Helm release and Deployment, or neither; partial ownership remains an error.

Configuration is read exclusively from the protected repository-root .env
documented in deploy/obaas/azn-server-runbook.md. The script derives the current
kubectl context from CLOUDBANK_KUBECONFIG_PATH, generates a new immutable image
tag, performs the complete dry-run automatically, displays the deployment plan,
and asks for confirmation before changing OCI or Kubernetes resources.

On first-deploy, the script generates strong CloudBank schema-owner and
per-service database passwords when their Secrets are absent. Values are never
displayed. It uses OCI_AUTH_TOKEN from .env through standard input and creates
or refreshes the private image-pull Secret on every deployment.

It creates private OCIR repositories when needed, builds and pushes eight
service images plus the schema-initializer and one-shot policy-loader images,
runs the full-demo SQLcl/Liquibase bootstrap used by Compose against ADB, loads
the versioned policy corpus with OCI GenAI embeddings, waits for every
Deployment and EndpointSlice, and leaves all application services internal
ClusterIP services. It does not create API gateway routes or deploy a MicroTx
workflow definition. The internal Workflow Server URL is auto-detected from the
configured OBaaS release at runtime.
EOF
}

env_file_value() {
    local variable_name="$1"
    local line
    local value=""
    local matches=0

    [[ -f "$ENV_FILE" ]] || return 0
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        [[ "$line" == "$variable_name="* ]] || continue
        matches=$((matches + 1))
        value="${line#*=}"
    done <"$ENV_FILE"
    [[ "$matches" -le 1 ]] || die ".env must contain at most one $variable_name entry"
    printf '%s' "$value"
}

parse_args() {
    if [[ $# -eq 1 && ( "$1" == "-h" || "$1" == "--help" ) ]]; then
        usage
        exit 0
    fi
    [[ $# -eq 1 ]] || { usage >&2; exit 2; }
    DEPLOY_MODE="$1"
    case "$DEPLOY_MODE" in
        first-deploy|redeploy) ;;
        *) die "mode must be 'first-deploy' or 'redeploy'" ;;
    esac
}

required_env_file_value() {
    local variable_name="$1"
    local value

    [[ -f "$ENV_FILE" ]] || die ".env is missing; follow deploy/obaas/azn-server-runbook.md"
    value="$(env_file_value "$variable_name")"
    [[ -n "$value" ]] || die ".env must contain exactly one non-empty $variable_name entry"
    case "$value" in
        *$'\n'* | *$'\r'*) die ".env variable $variable_name contains a newline" ;;
    esac
    printf '%s' "$value"
}

load_deployment_configuration() {
    CLOUDBANK_KUBECONFIG_PATH="$(required_env_file_value CLOUDBANK_KUBECONFIG_PATH)"
    OCI_REGION="$(required_env_file_value OCI_REGION)"
    OKE_CLUSTER_OCID="$(required_env_file_value OKE_CLUSTER_OCID)"
    OCI_COMPARTMENT_OCID="$(required_env_file_value OCI_COMPARTMENT_OCID)"
    OCI_IDENTITY_NAME="$(required_env_file_value OCI_IDENTITY_NAME)"
    OCI_AUTH_TOKEN="$(required_env_file_value OCI_AUTH_TOKEN)"
    OBAAS_RELEASE="$(required_env_file_value OBAAS_RELEASE)"
    NAMESPACE="$(required_env_file_value MICROTX_NAMESPACE)"
    IMAGE_PULL_SECRET="$(required_env_file_value IMAGE_PULL_SECRET)"
    POLICY_SERVICE_ACCOUNT="$(required_env_file_value POLICY_SERVICE_ACCOUNT)"
    POLICY_OCI_EMBEDDING_MODEL="$(required_env_file_value POLICY_OCI_GENAI_EMBEDDING_MODEL)"
    AI_SERVICE_ACCOUNT="$(required_env_file_value AI_SERVICE_ACCOUNT)"
    AI_OCI_GENAI_CHAT_MODEL="$(required_env_file_value AI_OCI_GENAI_CHAT_MODEL)"
    OKE_CLUSTER_COMPARTMENT_ID="$(required_env_file_value OKE_CLUSTER_COMPARTMENT_ID)"
    GEOGRAPHIC_RISK_LOG_GEOCODING_DETAILS="$(required_env_file_value GEOGRAPHIC_RISK_LOG_GEOCODING_DETAILS)"

    [[ "$CLOUDBANK_KUBECONFIG_PATH" == /* && -f "$CLOUDBANK_KUBECONFIG_PATH" ]] ||
        die "CLOUDBANK_KUBECONFIG_PATH must identify an existing absolute file path"
    export KUBECONFIG="$CLOUDBANK_KUBECONFIG_PATH"
    KUBECTL_CONTEXT="$(kubectl config current-context)" ||
        die "could not determine the current context from CLOUDBANK_KUBECONFIG_PATH"
    [[ -n "$KUBECTL_CONTEXT" ]] || die "the configured kubeconfig has no current context"

    POLICY_OCI_REGION="$OCI_REGION"
    AI_OCI_REGION="$OCI_REGION"
    POLICY_OCI_COMPARTMENT_ID="$OKE_CLUSTER_COMPARTMENT_ID"
    IMAGE_TAG="oke-$(date -u +%Y%m%dT%H%M%SZ)"
}

require_commands() {
    local command_name
    for command_name in kubectl helm jq awk grep mktemp mkdir chmod sort cksum cp ln patch date; do
        command -v "$command_name" >/dev/null 2>&1 || die "$command_name is required"
    done
    command -v oci >/dev/null 2>&1 || die "oci is required for OCIR operations"
    if [[ "$DRY_RUN" != true ]]; then
        for command_name in docker mvn date openssl tr; do
            command -v "$command_name" >/dev/null 2>&1 || die "$command_name is required"
        done
        docker info >/dev/null 2>&1 || die "Docker daemon is unavailable"
        docker buildx version >/dev/null 2>&1 || die "Docker Buildx is unavailable"
        docker buildx inspect >/dev/null 2>&1 || die "the selected Docker Buildx builder is unavailable"
    fi
}

prepare_isolated_docker_config() {
    local source_config_dir="${DOCKER_CONFIG:-}"
    local buildx_plugin_metadata
    local buildx_plugin_path
    local state_dir

    [[ "$DRY_RUN" != true ]] || return 0

    if [[ -z "$source_config_dir" && -n "${HOME:-}" ]]; then
        source_config_dir="$HOME/.docker"
    fi
    if [[ -d "$source_config_dir" ]]; then
        source_config_dir="$(cd "$source_config_dir" && pwd)" ||
            die "could not resolve the Docker client configuration directory"
    fi
    unset DOCKER_AUTH_CONFIG

    ISOLATED_DOCKER_CONFIG="$WORK_DIR/docker-config"
    mkdir -p "$ISOLATED_DOCKER_CONFIG"
    chmod 700 "$ISOLATED_DOCKER_CONFIG"

    # Preserve only non-registry Docker CLI settings. In particular, retain the
    # active context and Buildx state without copying existing registry auth.
    if [[ -n "$source_config_dir" && -f "$source_config_dir/config.json" ]]; then
        jq '{currentContext, proxies, features, experimental, cliPluginsExtraDirs}
            | with_entries(select(.value != null))' \
            "$source_config_dir/config.json" >"$ISOLATED_DOCKER_CONFIG/config.json" ||
            die "could not prepare an isolated Docker client configuration"
        chmod 600 "$ISOLATED_DOCKER_CONFIG/config.json"
    fi
    if [[ -n "$source_config_dir" ]]; then
        for state_dir in contexts buildx; do
            if [[ -d "$source_config_dir/$state_dir" ]]; then
                cp -R "$source_config_dir/$state_dir" "$ISOLATED_DOCKER_CONFIG/$state_dir" ||
                    die "could not preserve Docker $state_dir state in the isolated configuration"
            fi
        done
    fi

    # A per-user Buildx plugin normally lives below the original Docker config
    # directory. Make that exact plugin visible after DOCKER_CONFIG is isolated.
    buildx_plugin_metadata="$(docker info --format '{{json .ClientInfo.Plugins}}' 2>/dev/null || true)"
    buildx_plugin_path="$(jq -r \
        '[.[]? | select(.Name == "buildx") | .Path | select(type == "string" and length > 0)][0] // empty' \
        <<<"$buildx_plugin_metadata" 2>/dev/null || true)"
    if [[ -z "$buildx_plugin_path" && -n "$source_config_dir" &&
        -x "$source_config_dir/cli-plugins/docker-buildx" ]]; then
        buildx_plugin_path="$source_config_dir/cli-plugins/docker-buildx"
    fi
    if [[ -n "$buildx_plugin_path" && -x "$buildx_plugin_path" ]]; then
        mkdir -p "$ISOLATED_DOCKER_CONFIG/cli-plugins"
        ln -s "$buildx_plugin_path" "$ISOLATED_DOCKER_CONFIG/cli-plugins/docker-buildx" ||
            die "could not expose Docker Buildx in the isolated configuration"
    fi

    DOCKER_CONFIG="$ISOLATED_DOCKER_CONFIG" docker info >/dev/null 2>&1 ||
        die "Docker daemon is unavailable with the isolated OCIR configuration"
    DOCKER_CONFIG="$ISOLATED_DOCKER_CONFIG" docker buildx version >/dev/null 2>&1 ||
        die "Docker Buildx is unavailable with the isolated OCIR configuration"
    DOCKER_CONFIG="$ISOLATED_DOCKER_CONFIG" docker buildx inspect >/dev/null 2>&1 ||
        die "the selected Docker Buildx builder is unavailable with the isolated OCIR configuration"
}

configure_helm_list_compatibility() {
    local list_help

    list_help="$(helm list --help)" || die "could not inspect helm list capabilities"
    if printf '%s\n' "$list_help" | grep -Eq -- '(^|[[:space:]])--all([[:space:]]|$)'; then
        # Helm 3 lists only deployed releases by default and exposes --all.
        HELM_LIST_ALL_STATUS_ARGS=(--all)
    else
        # Helm 4 lists releases in every status by default and removed --all.
        HELM_LIST_ALL_STATUS_ARGS=()
    fi
}

validate_microtx_workflow_url() {
    local url="$1"

    [[ "$url" =~ ^https?://[^[:space:]\"]+$ ]] ||
        die "MicroTx Workflow URL must be an http(s) URL without whitespace"
    [[ "$url" != *://localhost* && "$url" != *://127.0.0.1* &&
        "$url" != *://0.0.0.0* ]] || die "MicroTx Workflow URL must not be loopback"
}

validate_inputs() {
    local configured_cluster_compartment

    [[ -f "$DOCKERFILE" ]] || die "Dockerfile not found: $DOCKERFILE"
    [[ -n "$KUBECTL_CONTEXT" ]] || die "kubectl context must not be empty"
    [[ "$OCI_REGION" =~ ^[a-z0-9]+([a-z0-9-]*[a-z0-9])?$ ]] ||
        die "OCI region must be a region identifier such as eu-frankfurt-1"
    [[ "$IMAGE_TAG" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]] ||
        die "the generated image tag is invalid"
    [[ "$IMAGE_TAG" != latest ]] || die "refusing mutable image tag 'latest'"
    [[ "$TIMEOUT" =~ ^[1-9][0-9]*(s|m|h)$ ]] || die "invalid timeout"
    [[ "$REPOSITORY_PREFIX" =~ ^[a-z0-9][a-z0-9._/-]*$ ]] || die "invalid repository prefix"
    [[ "$DATABASE_SECRET_PREFIX" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "invalid database Secret prefix"
    [[ "$SCHEMA_OWNER_SECRET" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]] || die "invalid schema-owner Secret name"
    [[ "$IMAGE_PULL_SECRET" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]] || die "invalid image pull Secret name"
    [[ "$AUTH_SECRET" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]] || die "invalid auth Secret name"
    [[ "$POLICY_SERVICE_ACCOUNT" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]] || die "invalid policy ServiceAccount name"
    [[ "$AI_SERVICE_ACCOUNT" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]] || die "invalid AI ServiceAccount name"
    [[ "$WORKFLOW_MODE" == microtx || "$WORKFLOW_MODE" == fake ]] || die "workflow mode must be microtx or fake"
    case "$POLICY_AUTHENTICATION_TYPE" in
        WORKLOAD_IDENTITY|RESOURCE_PRINCIPAL|INSTANCE_PRINCIPAL) ;;
        *) die "unsupported policy OCI authentication type" ;;
    esac
    if [[ "$WORKFLOW_MODE" == microtx && -n "$MICROTX_WORKFLOW_URL" ]]; then
        validate_microtx_workflow_url "$MICROTX_WORKFLOW_URL"
    fi
    [[ -n "$POLICY_OCI_REGION" ]] || POLICY_OCI_REGION="$OCI_REGION"
    [[ -n "$POLICY_OCI_EMBEDDING_MODEL" ]] ||
        die "POLICY_OCI_GENAI_EMBEDDING_MODEL must be configured in .env"
    [[ "$POLICY_OCI_EMBEDDING_MODEL" =~ ^[A-Za-z0-9._:/-]+$ ]] || die "invalid policy embedding model"
    [[ "$POLICY_OCI_COMPARTMENT_ID" =~ ^ocid1\.[A-Za-z0-9._-]+$ ]] || die "invalid policy OCI compartment OCID"
    if [[ -n "$POLICY_OCI_FEDERATION_ENDPOINT" ]]; then
        [[ "$POLICY_OCI_FEDERATION_ENDPOINT" =~ ^https?://[^[:space:]\"]+$ ]] || die "invalid federation endpoint"
    fi
    [[ -n "$AI_OCI_REGION" ]] || AI_OCI_REGION="$OCI_REGION"
    [[ -n "$AI_OCI_GENAI_CHAT_MODEL" ]] ||
        die "AI_OCI_GENAI_CHAT_MODEL must be configured in .env"
    [[ "$AI_OCI_GENAI_CHAT_MODEL" =~ ^[A-Za-z0-9._:/-]+$ ]] || die "invalid AI chat model"
    [[ -n "$OKE_CLUSTER_COMPARTMENT_ID" ]] ||
        die "OKE_CLUSTER_COMPARTMENT_ID must be configured in .env"
    [[ "$OKE_CLUSTER_COMPARTMENT_ID" =~ ^ocid1\.[A-Za-z0-9._-]+$ ]] ||
        die "invalid OKE cluster compartment OCID"
    if [[ -n "$AI_OCI_FEDERATION_ENDPOINT" ]]; then
        [[ "$AI_OCI_FEDERATION_ENDPOINT" =~ ^https?://[^[:space:]\"]+$ ]] || die "invalid AI federation endpoint"
    fi
    [[ "$OCI_COMPARTMENT_OCID" =~ ^ocid1\.[A-Za-z0-9._-]+$ ]] ||
        die "OCI_COMPARTMENT_OCID in .env is not a valid OCID"
    [[ "$OKE_CLUSTER_OCID" =~ ^ocid1\.cluster\.[A-Za-z0-9._-]+$ ]] ||
        die "OKE_CLUSTER_OCID in .env is not a valid cluster OCID"
    [[ -n "$OCI_IDENTITY_NAME" && "$OCI_IDENTITY_NAME" != *[[:space:]]* ]] ||
        die "OCI_IDENTITY_NAME in .env must not contain whitespace"
    [[ -n "$OCI_AUTH_TOKEN" ]] || die "OCI_AUTH_TOKEN in .env must not be empty"
    [[ "$NAMESPACE" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]] ||
        die "MICROTX_NAMESPACE in .env is not a DNS-1123 name"
    [[ "$OBAAS_RELEASE" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]] ||
        die "OBAAS_RELEASE in .env is not a DNS-1123 name"
    [[ "$GEOGRAPHIC_RISK_LOG_GEOCODING_DETAILS" == true ||
        "$GEOGRAPHIC_RISK_LOG_GEOCODING_DETAILS" == false ]] ||
        die "GEOGRAPHIC_RISK_LOG_GEOCODING_DETAILS in .env must be true or false"
    if ! kubectl config get-contexts "$KUBECTL_CONTEXT" -o name 2>/dev/null | grep -Fxq "$KUBECTL_CONTEXT"; then
        die "kubectl context does not exist: $KUBECTL_CONTEXT"
    fi
    kubectl --context "$KUBECTL_CONTEXT" cluster-info >/dev/null

    configured_cluster_compartment="$(oci ce cluster get \
        --cluster-id "$OKE_CLUSTER_OCID" \
        --region "$OCI_REGION" \
        --query 'data."compartment-id"' \
        --raw-output)" || die "could not inspect OKE_CLUSTER_OCID in OCI_REGION"
    [[ "$configured_cluster_compartment" == "$OKE_CLUSTER_COMPARTMENT_ID" ]] ||
        die "OKE_CLUSTER_COMPARTMENT_ID does not match the configured OKE cluster"
}

detect_obaas_release() {
    local -a helm_list_args
    local releases_json
    local release_rows
    local release_count
    local selected_chart

    helm_list_args=(list --kube-context "$KUBECTL_CONTEXT" --output json)
    if [[ -n "$NAMESPACE" ]]; then
        helm_list_args+=(--namespace "$NAMESPACE")
    else
        helm_list_args+=(--all-namespaces)
    fi
    releases_json="$(helm "${helm_list_args[@]}")"
    release_rows="$(printf '%s' "$releases_json" | jq -r \
        --arg namespace "$NAMESPACE" --arg release "$OBAAS_RELEASE" '
          .[]
          | select(.chart | test("^obaas-[0-9]"))
          | select(($namespace == "") or (.namespace == $namespace))
          | select(($release == "") or (.name == $release))
          | [.name, .namespace, .app_version, .chart]
          | @tsv')"
    release_count="$(printf '%s\n' "$release_rows" | awk 'NF { count++ } END { print count + 0 }')"
    [[ "$release_count" -eq 1 ]] || {
        if [[ "$release_count" -gt 1 ]]; then
            printf 'Matching OBaaS releases (name, namespace, appVersion, chart):\n%s\n' "$release_rows" >&2
        fi
        die "expected exactly one OBaaS platform Helm release in context '$KUBECTL_CONTEXT'"
    }

    IFS=$'\t' read -r OBAAS_RELEASE NAMESPACE OBAAS_VERSION selected_chart <<<"$release_rows"
    obaas_version_at_least "$OBAAS_VERSION" ||
        die "installed release '$OBAAS_RELEASE' must advertise an OBaaS semantic version >= 2.1.0 (found '$OBAAS_VERSION')"
    kubectl --context "$KUBECTL_CONTEXT" get namespace "$NAMESPACE" >/dev/null
    info "Detected OBaaS release '$OBAAS_RELEASE' ($selected_chart, appVersion $OBAAS_VERSION) in namespace '$NAMESPACE'."
}

resolve_microtx_workflow_url() {
    local workflow_service
    local service_json
    local service_type
    local workflow_port
    local endpoint_count

    if [[ "$WORKFLOW_MODE" != microtx ]]; then
        MICROTX_WORKFLOW_URL=""
        MICROTX_WORKFLOW_URL_SOURCE="disabled"
        return
    fi

    workflow_service="${OBAAS_RELEASE}-otmm-workflow-server"
    service_json="$(kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" \
        get service "$workflow_service" -o json)" ||
        die "MicroTx Workflow Server Service '$workflow_service' was not found"

    service_type="$(printf '%s' "$service_json" | jq -r '.spec.type // "ClusterIP"')"
    [[ "$service_type" == ClusterIP ]] ||
        die "MicroTx Workflow Server Service '$workflow_service' must be ClusterIP for automatic discovery"

    workflow_port="$(printf '%s' "$service_json" | jq -er '
      (.spec.ports // []) as $ports
      | if ([$ports[] | select(.port == 9010)] | length) == 1 then
          [$ports[] | select(.port == 9010)][0].port
        elif ($ports | length) == 1 then
          $ports[0].port
        else
          error("expected port 9010 or exactly one Service port")
        end
    ')" || die "could not select the MicroTx Workflow Server port from service/$workflow_service"
    [[ "$workflow_port" =~ ^[1-9][0-9]{0,4}$ && "$workflow_port" -le 65535 ]] ||
        die "invalid port discovered for service/$workflow_service"

    endpoint_count="$(kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" get endpointslice \
        -l "kubernetes.io/service-name=$workflow_service" -o json |
        jq '[.items[]?.endpoints[]? | select(.conditions.ready != false)] | length')"
    [[ "$endpoint_count" -ge 1 ]] ||
        die "MicroTx Workflow Server Service '$workflow_service' has no ready EndpointSlice endpoint"

    MICROTX_WORKFLOW_URL="http://${workflow_service}.${NAMESPACE}.svc.cluster.local:${workflow_port}${DEFAULT_MICROTX_WORKFLOW_PATH}"
    validate_microtx_workflow_url "$MICROTX_WORKFLOW_URL"
    MICROTX_WORKFLOW_URL_SOURCE="auto-detected from service/$workflow_service"
    info "Detected MicroTx Workflow Server URL '$MICROTX_WORKFLOW_URL'."
}

ensure_obaas_helm_repository() {
    local repositories_json

    repositories_json="$(helm repo list --output json 2>/dev/null || printf '[]')"
    if ! printf '%s' "$repositories_json" | jq -e '.[] | select(.name == "obaas")' >/dev/null; then
        info "Adding the official OBaaS Helm repository."
        helm repo add obaas "$OBAAS_HELM_REPOSITORY" >/dev/null
    fi
    helm repo update obaas >/dev/null
}

resolve_app_chart() {
    local chart_metadata
    local chart_app_version
    local chart_name

    if [[ -f "$APP_CHART/Chart.yaml" ]]; then
        RESOLVED_CHART="$APP_CHART"
    else
        [[ "$APP_CHART" == obaas/* ]] && ensure_obaas_helm_repository
        if [[ -z "$APP_CHART_VERSION" ]]; then
            APP_CHART_VERSION="$(helm search repo "$APP_CHART" --versions --devel --output json |
                jq -er --arg chart "$APP_CHART" --arg target "$OBAAS_VERSION" \
                    'first(.[] | select(.name == $chart and .app_version == $target) | .version) // empty')" ||
                die "no '$APP_CHART' chart advertises appVersion $OBAAS_VERSION, or Helm search failed"
        fi
        [[ -n "$APP_CHART_VERSION" ]] || die "no '$APP_CHART' chart advertises appVersion $OBAAS_VERSION"
        mkdir -p "$WORK_DIR/chart"
        helm pull "$APP_CHART" --version "$APP_CHART_VERSION" \
            --untar --untardir "$WORK_DIR/chart" >/dev/null
        RESOLVED_CHART="$WORK_DIR/chart/$(basename "$APP_CHART")"
        [[ -f "$RESOLVED_CHART/Chart.yaml" ]] || die "pulled chart has no Chart.yaml"
    fi

    chart_metadata="$(helm show chart "$RESOLVED_CHART")"
    chart_name="$(printf '%s\n' "$chart_metadata" |
        awk -F':[[:space:]]*' '$1 == "name" { gsub(/"/, "", $2); print $2; exit }')"
    chart_app_version="$(printf '%s\n' "$chart_metadata" |
        awk -F':[[:space:]]*' '$1 == "appVersion" { gsub(/"/, "", $2); print $2; exit }')"
    [[ "$chart_name" == obaas-sample-app ]] || die "application chart must be obaas-sample-app"
    [[ "$chart_app_version" == "$OBAAS_VERSION" ]] ||
        die "application chart appVersion '$chart_app_version' does not match OBaaS $OBAAS_VERSION"
    [[ -f "$OBAAS_SAMPLE_APP_DATABASE_PATCH" ]] ||
        die "CloudBank database-optional chart patch was not found"
    if [[ "$RESOLVED_CHART" != "$WORK_DIR/"* ]]; then
        mkdir -p "$WORK_DIR/chart-overlay"
        cp -R "$RESOLVED_CHART" "$WORK_DIR/chart-overlay/obaas-sample-app"
        RESOLVED_CHART="$WORK_DIR/chart-overlay/obaas-sample-app"
    fi
    if patch -f --dry-run -R -s -p1 -d "$RESOLVED_CHART" \
        <"$OBAAS_SAMPLE_APP_DATABASE_PATCH" >/dev/null 2>&1; then
        info "The application chart already contains the CloudBank database-optional patch."
    elif patch -f -N -s -p1 -d "$RESOLVED_CHART" <"$OBAAS_SAMPLE_APP_DATABASE_PATCH"; then
        info "Applied the CloudBank database-optional chart patch."
    else
        die "the application chart is incompatible with the CloudBank database-optional patch"
    fi
    info "Using application chart '$chart_name' appVersion $chart_app_version${APP_CHART_VERSION:+ (chart $APP_CHART_VERSION)}."
}

resolve_image_repository_prefix() {
    local repository_path
    local -a oci_args

    if [[ -n "$IMAGE_REPOSITORY_PREFIX" ]]; then
        IMAGE_REPOSITORY_PREFIX="${IMAGE_REPOSITORY_PREFIX%/}"
        [[ "$IMAGE_REPOSITORY_PREFIX" != *@* && "$IMAGE_REPOSITORY_PREFIX" != *:* &&
            "$IMAGE_REPOSITORY_PREFIX" != *[[:space:]]* && "$IMAGE_REPOSITORY_PREFIX" == */*/* ]] ||
            die "image repository prefix must be registry/namespace/path without tag or digest"
        OCIR_HOST="${IMAGE_REPOSITORY_PREFIX%%/*}"
        repository_path="${IMAGE_REPOSITORY_PREFIX#*/}"
        OCIR_NAMESPACE="${repository_path%%/*}"
        OCI_REPOSITORY_PATH_PREFIX="${repository_path#*/}"
    else
        if [[ -z "$OCIR_NAMESPACE" ]]; then
            oci_args=(os ns get --region "$OCI_REGION" --query data --raw-output)
            OCIR_NAMESPACE="$(oci "${oci_args[@]}")"
        fi
        [[ -n "$OCIR_HOST" ]] || OCIR_HOST="ocir.${OCI_REGION}.oci.oraclecloud.com"
        OCI_REPOSITORY_PATH_PREFIX="$REPOSITORY_PREFIX"
        IMAGE_REPOSITORY_PREFIX="$OCIR_HOST/$OCIR_NAMESPACE/$OCI_REPOSITORY_PATH_PREFIX"
    fi

    [[ "$OCIR_HOST" =~ ^[A-Za-z0-9.-]+$ ]] || die "invalid OCIR host"
    [[ "$OCIR_NAMESPACE" =~ ^[A-Za-z0-9._-]+$ ]] || die "invalid OCIR namespace"
    [[ "$OCI_REPOSITORY_PATH_PREFIX" =~ ^[a-z0-9][a-z0-9._/-]*$ ]] || die "invalid OCIR repository path"
    [[ "$IMAGE_REPOSITORY_PREFIX" == "$OCIR_HOST/$OCIR_NAMESPACE/$OCI_REPOSITORY_PATH_PREFIX" ]] ||
        die "image repository prefix could not be normalized"
}

image_repository() {
    printf '%s/%s' "$IMAGE_REPOSITORY_PREFIX" "$1"
}

service_db_secret() {
    printf '%s-%s-db-authn' "$DATABASE_SECRET_PREFIX" "$1"
}

service_db_username() {
    case "$1" in
        loan-application-service) printf '%s' CB_LOAN_APPLICATION_APP ;;
        document-ingest) printf '%s' CB_DOCUMENT_INGEST_APP ;;
        document-review-service) printf '%s' CB_DOCUMENT_REVIEW_APP ;;
        decision-service) printf '%s' CB_DECISION_APP ;;
        ai-agent-service) printf '%s' CB_AI_AGENT_APP ;;
        geographic-risk-service) printf '%s' CB_GEOGRAPHIC_RISK_APP ;;
        policy-retrieval-service) printf '%s' CB_POLICY_APPLICATION_APP ;;
        policy-loader) printf '%s' CB_POLICY_LOADER_APP ;;
        *) die "no database username is defined for '$1'" ;;
    esac
}

secret_names() {
    kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" get secrets \
        -o custom-columns=NAME:.metadata.name --no-headers
}

resolve_platform_secrets() {
    local names
    local candidates
    local candidate_count

    names="$(secret_names)"
    if [[ -z "$DB_PRIV_SECRET" ]]; then
        candidates="$(printf '%s\n' "$names" | grep -E -- '-db-priv-authn$' || true)"
        candidate_count="$(printf '%s\n' "$candidates" | awk 'NF { count++ } END { print count + 0 }')"
        [[ "$candidate_count" -eq 1 ]] || {
            printf 'Privileged database Secret candidates:\n%s\n' "${candidates:-<none>}" >&2
            die "expected exactly one OBaaS privileged database Secret in namespace '$NAMESPACE'"
        }
        DB_PRIV_SECRET="$candidates"
    fi
    if [[ -z "$WALLET_SECRET" ]]; then
        candidates="$(printf '%s\n' "$names" | grep -E -- '-adb-tns-admin(-|$)' || true)"
        candidate_count="$(printf '%s\n' "$candidates" | awk 'NF { count++ } END { print count + 0 }')"
        [[ "$candidate_count" -eq 1 ]] || {
            printf 'Database wallet Secret candidates:\n%s\n' "${candidates:-<none>}" >&2
            die "expected exactly one OBaaS database wallet Secret in namespace '$NAMESPACE'"
        }
        WALLET_SECRET="$candidates"
    fi
}

require_secret_keys() {
    local secret_name="$1"
    shift
    local keys
    local required_key

    keys="$(kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" get secret "$secret_name" \
        -o go-template='{{range $key, $_ := .data}}{{$key}}{{"\n"}}{{end}}')" ||
        die "required Secret '$secret_name' was not found in namespace '$NAMESPACE'"
    for required_key in "$@"; do
        printf '%s\n' "$keys" | grep -Fxq "$required_key" ||
            die "Secret '$secret_name' is missing required key '$required_key'"
    done
}

validate_platform_secrets() {
    require_secret_keys "$DB_PRIV_SECRET" username password service
    kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" get secret "$WALLET_SECRET" >/dev/null ||
        die "wallet Secret '$WALLET_SECRET' was not found"
}

validate_azn_precondition() {
    kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" get deployment azn-server >/dev/null ||
        die "azn-server Deployment is missing; deploy azn-server first"
    kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" get service azn-server >/dev/null ||
        die "azn-server Service is missing"
    kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" rollout status \
        deployment/azn-server --timeout="$TIMEOUT"
    require_secret_keys "$AUTH_SECRET" \
        service-client-secret microtx-client-secret \
        document-ingest-client-secret document-review-client-secret
    if ! kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" \
        get secret "$AUTH_SECRET" -o json |
        jq -e '.data["ai-agent-client-secret"] | type == "string" and length > 0' >/dev/null; then
        die "Secret '$AUTH_SECRET' lacks ai-agent-client-secret; redeploy azn-server first so its deployment helper generates and registers the client credential"
    fi
}

resolve_azn_runtime_urls() {
    local deployment_json
    local configured_issuer

    AZN_CLUSTER_URL="http://azn-server.${NAMESPACE}.svc.cluster.local:8080"
    deployment_json="$(kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" \
        get deployment azn-server -o json)"
    AZN_ISSUER_URI="$(printf '%s' "$deployment_json" | jq -er '
      [.spec.template.spec.containers[]?.env[]?
       | select(.name == "AZN_ISSUER_URI")
       | .value // empty]
      | unique
      | if length == 1 then .[0]
        else error("expected exactly one literal AZN_ISSUER_URI value")
        end
    ')" || die "could not determine the live AZN_ISSUER_URI from deployment/azn-server"
    [[ "$AZN_ISSUER_URI" =~ ^https?://[A-Za-z0-9.-]+(:[0-9]+)?$ ]] ||
        die "the live azn-server issuer must be an HTTP(S) origin without a path"
    configured_issuer="$(required_env_file_value AZN_ISSUER_URI)"
    [[ "$AZN_ISSUER_URI" == "$configured_issuer" ]] ||
        die "the live azn-server issuer differs from AZN_ISSUER_URI in .env; redeploy azn-server before deploying services"
    info "Detected azn-server issuer '$AZN_ISSUER_URI'; pods use '$AZN_CLUSTER_URL' for token and JWKS access."
}

inspect_database_secret_state() {
    local service
    local secret_name
    local existing_count=0
    local existing_names=""
    MISSING_DATABASE_IDENTITIES=()

    for service in "${DATABASE_IDENTITIES[@]}"; do
        secret_name="$(service_db_secret "$service")"
        if kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" get secret "$secret_name" >/dev/null 2>&1; then
            existing_count=$((existing_count + 1))
            existing_names="${existing_names}${existing_names:+, }${secret_name}"
        else
            MISSING_DATABASE_IDENTITIES+=("$service")
        fi
    done

    if [[ "$existing_count" -eq 0 ]]; then
        DB_SECRET_STATE=none
    elif [[ "$existing_count" -eq "${#DATABASE_IDENTITIES[@]}" ]]; then
        DB_SECRET_STATE=complete
    else
        DB_SECRET_STATE=partial
    fi

    if [[ "$DB_SECRET_STATE" == complete ]]; then
        for service in "${DATABASE_IDENTITIES[@]}"; do
            require_secret_keys "$(service_db_secret "$service")" username password service
        done
    elif [[ "$DB_SECRET_STATE" == partial ]]; then
        for service in "${DATABASE_IDENTITIES[@]}"; do
            [[ " ${MISSING_DATABASE_IDENTITIES[*]} " == *" $service "* ]] && continue
            require_secret_keys "$(service_db_secret "$service")" username password service
        done
    elif [[ "$DEPLOY_MODE" == redeploy ]]; then
        die "redeploy requires all CloudBank database Secrets to exist"
    fi

    if kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" \
        get secret "$SCHEMA_OWNER_SECRET" >/dev/null 2>&1; then
        require_secret_keys "$SCHEMA_OWNER_SECRET" password
        SCHEMA_OWNER_SECRET_STATE="present"
    else
        SCHEMA_OWNER_SECRET_STATE="missing"
    fi
}

validate_adb_password() {
    local variable_name="$1"
    local value="$2"
    local database_username="$3"

    [[ ${#value} -ge 12 && ${#value} -le 30 ]] ||
        die "$variable_name must be 12 to 30 characters for Autonomous Database"
    [[ "$value" =~ ^[A-Za-z0-9#_]+$ &&
        "$value" =~ [A-Z].*[A-Z] &&
        "$value" =~ [a-z].*[a-z] &&
        "$value" =~ [0-9].*[0-9] &&
        "$value" =~ [#_].*[#_] ]] ||
        die "$variable_name does not meet the Autonomous Database password rules"
    if printf '%s' "$value" | grep -Fqi "$database_username"; then
        die "$variable_name must not contain the database username"
    fi
}

validate_database_secret_material() {
    [[ "$DB_SECRET_STATE" == none || "$DB_SECRET_STATE" == partial ]] || return 0

    DATABASE_SERVICE_B64="$(kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" \
        get secret "$DB_PRIV_SECRET" -o jsonpath='{.data.service}')" ||
        die "could not read the encoded service key from privileged database Secret '$DB_PRIV_SECRET'"
    [[ -n "$DATABASE_SERVICE_B64" ]] ||
        die "privileged database Secret '$DB_PRIV_SECRET' has an empty service key"
    DATABASE_SERVICE_SOURCE="copied from $DB_PRIV_SECRET/service"
}

generate_adb_password_file() {
    local label="$1"
    local database_username="$2"
    local output_file="$3"
    local random_part
    local password
    local attempt

    for attempt in 1 2 3 4 5; do
        random_part="$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9')"
        [[ ${#random_part} -ge 20 ]] || continue
        password="Aa1#Bb2_${random_part:0:20}"
        if printf '%s' "$password" | grep -Fqi "$database_username"; then
            continue
        fi
        validate_adb_password "$label" "$password" "$database_username"
        printf '%s' "$password" >"$output_file"
        unset random_part password
        return 0
    done
    unset random_part password
    die "could not generate a valid Autonomous Database password for $label"
}

rollback_created_db_secrets() {
    local secret_name
    for secret_name in "${CREATED_DB_SECRETS[@]}"; do
        kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" delete secret "$secret_name" \
            --ignore-not-found >/dev/null || true
    done
}

create_database_secret() {
    local secret_name="$1"
    local username_file="$2"
    local password_file="$3"
    local service_b64="$4"
    local service_patch_file="$WORK_DIR/database-secrets/$secret_name-service-patch.json"

    if kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" create secret generic "$secret_name" \
        --from-file=username="$username_file" \
        --from-file=password="$password_file" >/dev/null; then
        CREATED_DB_SECRETS+=("$secret_name")
        printf '{"data":{"service":"%s"}}\n' "$service_b64" >"$service_patch_file"
        if kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" patch secret "$secret_name" \
            --type merge --patch-file "$service_patch_file" >/dev/null; then
            rm -f -- "$service_patch_file"
            return 0
        fi
    fi

    rollback_created_db_secrets
    die "failed to create CloudBank database Secrets; newly created Secrets were rolled back"
}

create_schema_owner_secret() {
    local password_file="$1"

    if kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" create secret generic "$SCHEMA_OWNER_SECRET" \
        --from-file=password="$password_file" >/dev/null; then
        CREATED_DB_SECRETS+=("$SCHEMA_OWNER_SECRET")
    else
        rollback_created_db_secrets
        die "failed to create the CloudBank schema-owner Secret; newly created Secrets were rolled back"
    fi
}

create_cloudbank_database_secrets() {
    local secret_dir="$WORK_DIR/database-secrets"
    local service
    local secret_name
    local username

    validate_database_secret_material

    umask 077
    mkdir -p "$secret_dir"
    chmod 700 "$secret_dir"
    CREATED_DB_SECRETS=()

    if [[ "$DB_SECRET_STATE" == none || "$DB_SECRET_STATE" == partial ]]; then
        local services_to_create=("${DATABASE_IDENTITIES[@]}")
        if [[ "$DB_SECRET_STATE" == partial ]]; then
            services_to_create=("${MISSING_DATABASE_IDENTITIES[@]}")
        fi
        for service in "${services_to_create[@]}"; do
            secret_name="$(service_db_secret "$service")"
            username="$(service_db_username "$service")"
            printf '%s' "$username" >"$secret_dir/$service-username"
            generate_adb_password_file "$service runtime password" "$username" \
                "$secret_dir/$service-password"
            create_database_secret "$secret_name" \
                "$secret_dir/$service-username" \
                "$secret_dir/$service-password" \
                "$DATABASE_SERVICE_B64"
        done
        DB_SECRET_STATE=complete
        info "Generated and created the missing CloudBank database Secrets without displaying values."
    fi

    if [[ "$SCHEMA_OWNER_SECRET_STATE" == missing ]]; then
        generate_adb_password_file "CLOUDBANK schema-owner password" CLOUDBANK \
            "$secret_dir/schema-owner-password"
        create_schema_owner_secret "$secret_dir/schema-owner-password"
        SCHEMA_OWNER_SECRET_STATE="present"
        info "Generated and created the CloudBank schema-owner Secret without displaying its value."
    fi
}

resolve_schema_job_name() {
    local tag_checksum

    tag_checksum="$(printf '%s' "$IMAGE_TAG" | cksum | awk '{print $1}')"
    [[ "$tag_checksum" =~ ^[0-9]+$ ]] || die "could not derive the schema Job name"
    SCHEMA_JOB_NAME="cloudbank-schema-init-$tag_checksum"
    POLICY_LOADER_JOB_NAME="cloudbank-policy-loader-$tag_checksum"
}

generate_schema_job_manifest() {
    local file="$WORK_DIR/schema-init-job.yaml"

    cat >"$file" <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: "$SCHEMA_JOB_NAME"
  namespace: "$NAMESPACE"
  labels:
    app.kubernetes.io/name: "$SCHEMA_INITIALIZER"
    app.kubernetes.io/component: database-bootstrap
    app.kubernetes.io/part-of: cloudbank-ai
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 3600
  template:
    metadata:
      labels:
        app.kubernetes.io/name: "$SCHEMA_INITIALIZER"
        app.kubernetes.io/component: database-bootstrap
        app.kubernetes.io/part-of: cloudbank-ai
    spec:
      restartPolicy: Never
      imagePullSecrets:
        - name: "$IMAGE_PULL_SECRET"
      securityContext:
        runAsNonRoot: true
        runAsUser: 10001
        runAsGroup: 10001
        fsGroup: 10001
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: "$SCHEMA_INITIALIZER"
          image: "$(image_repository "$SCHEMA_INITIALIZER"):$IMAGE_TAG"
          imagePullPolicy: IfNotPresent
          securityContext:
            runAsNonRoot: true
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop:
                - ALL
          env:
            - name: LOAN_DB_ADMIN_USERNAME
              valueFrom:
                secretKeyRef:
                  name: "$DB_PRIV_SECRET"
                  key: username
            - name: LOAN_DB_ADMIN_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: "$DB_PRIV_SECRET"
                  key: password
            - name: DB_SERVICE
              valueFrom:
                secretKeyRef:
                  name: "$DB_PRIV_SECRET"
                  key: service
            - name: TNS_ADMIN
              value: /oracle/tnsadmin
            - name: LOAN_SQLCL_CONNECT
              value: "\$(DB_SERVICE)"
            - name: LOAN_SCHEMA_OWNER_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: "$SCHEMA_OWNER_SECRET"
                  key: password
            - name: LOAN_DATASOURCE_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: "$(service_db_secret loan-application-service)"
                  key: password
            - name: DOCUMENT_INGEST_DATASOURCE_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: "$(service_db_secret document-ingest)"
                  key: password
            - name: DOCUMENT_REVIEW_DATASOURCE_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: "$(service_db_secret document-review-service)"
                  key: password
            - name: DECISION_DATASOURCE_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: "$(service_db_secret decision-service)"
                  key: password
            - name: AI_DATASOURCE_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: "$(service_db_secret ai-agent-service)"
                  key: password
            - name: GEOGRAPHIC_RISK_DATASOURCE_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: "$(service_db_secret geographic-risk-service)"
                  key: password
            - name: POLICY_RETRIEVAL_DATASOURCE_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: "$(service_db_secret policy-retrieval-service)"
                  key: password
            - name: POLICY_LOADER_DATASOURCE_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: "$(service_db_secret policy-loader)"
                  key: password
            - name: SCHEMA_PROFILE
              value: full-demo
          volumeMounts:
            - name: adb-wallet
              mountPath: /oracle/tnsadmin
              readOnly: true
            - name: temporary-files
              mountPath: /tmp
      volumes:
        - name: adb-wallet
          secret:
            secretName: "$WALLET_SECRET"
            defaultMode: 288
        - name: temporary-files
          emptyDir: {}
EOF
}

generate_policy_service_account_manifest() {
    local file="$WORK_DIR/policy-service-account.yaml"

    cat >"$file" <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: "$POLICY_SERVICE_ACCOUNT"
  namespace: "$NAMESPACE"
  labels:
    app.kubernetes.io/name: policy-retrieval-service
    app.kubernetes.io/part-of: cloudbank-ai
    app.kubernetes.io/managed-by: Helm
  annotations:
    meta.helm.sh/release-name: policy-retrieval-service
    meta.helm.sh/release-namespace: "$NAMESPACE"
EOF
}

generate_policy_loader_job_manifest() {
    local file="$WORK_DIR/policy-loader-job.yaml"
    local federation_endpoint_env=""

    if [[ -n "$POLICY_OCI_FEDERATION_ENDPOINT" ]]; then
        federation_endpoint_env="$(printf '%s\n%s' \
            '            - name: OCI_GENAI_FEDERATION_ENDPOINT' \
            "              value: \"$POLICY_OCI_FEDERATION_ENDPOINT\"")"
    fi

    cat >"$file" <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: "$POLICY_LOADER_JOB_NAME"
  namespace: "$NAMESPACE"
  labels:
    app.kubernetes.io/name: "$POLICY_LOADER"
    app.kubernetes.io/component: policy-corpus-loader
    app.kubernetes.io/part-of: cloudbank-ai
spec:
  backoffLimit: 1
  ttlSecondsAfterFinished: 3600
  template:
    metadata:
      labels:
        app.kubernetes.io/name: "$POLICY_LOADER"
        app.kubernetes.io/component: policy-corpus-loader
        app.kubernetes.io/part-of: cloudbank-ai
    spec:
      serviceAccountName: "$POLICY_SERVICE_ACCOUNT"
      restartPolicy: Never
      imagePullSecrets:
        - name: "$IMAGE_PULL_SECRET"
      securityContext:
        runAsNonRoot: true
        runAsUser: 10001
        runAsGroup: 10001
        fsGroup: 10001
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: "$POLICY_LOADER"
          image: "$(image_repository "$POLICY_LOADER"):$IMAGE_TAG"
          imagePullPolicy: IfNotPresent
          securityContext:
            runAsNonRoot: true
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop:
                - ALL
          env:
            - name: DB_SERVICE
              valueFrom:
                secretKeyRef:
                  name: "$(service_db_secret policy-loader)"
                  key: service
            - name: POLICY_LOADER_DATASOURCE_URL
              value: "jdbc:oracle:thin:@\$(DB_SERVICE)?TNS_ADMIN=/oracle/tnsadmin"
            - name: POLICY_LOADER_DATASOURCE_USERNAME
              valueFrom:
                secretKeyRef:
                  name: "$(service_db_secret policy-loader)"
                  key: username
            - name: POLICY_LOADER_DATASOURCE_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: "$(service_db_secret policy-loader)"
                  key: password
            - name: POLICY_SCHEMA
              value: "CLOUDBANK"
            - name: POLICY_CORPUS_PATH
              value: "/app/policy"
            - name: OCI_GENAI_AUTHENTICATION_TYPE
              value: "$POLICY_AUTHENTICATION_TYPE"
            - name: OCI_GENAI_REGION
              value: "$POLICY_OCI_REGION"
            - name: OCI_GENAI_EMBEDDING_MODEL
              value: "$POLICY_OCI_EMBEDDING_MODEL"
            - name: OCI_GENAI_EMBEDDING_COMPARTMENT_ID
              value: "$POLICY_OCI_COMPARTMENT_ID"
$federation_endpoint_env
          volumeMounts:
            - name: adb-wallet
              mountPath: /oracle/tnsadmin
              readOnly: true
            - name: temporary-files
              mountPath: /tmp
      volumes:
        - name: adb-wallet
          secret:
            secretName: "$WALLET_SECRET"
            defaultMode: 288
        - name: temporary-files
          emptyDir: {}
EOF
}

report_schema_initializer_failure() {
    info "Schema initializer Pod status:"
    kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" get pods \
        -l "job-name=$SCHEMA_JOB_NAME" \
        -o 'custom-columns=POD:.metadata.name,PHASE:.status.phase,REASON:.status.containerStatuses[0].state.terminated.reason,EXIT_CODE:.status.containerStatuses[0].state.terminated.exitCode' \
        --no-headers >&2 || true

    info "Schema initializer event reasons:"
    kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" get events \
        --field-selector "involvedObject.kind=Job,involvedObject.name=$SCHEMA_JOB_NAME" \
        -o json 2>/dev/null |
        jq -r '[.items[]?.reason] | group_by(.)[] | "  \(.[0]): \(length)"' >&2 || true

    info "Schema initializer safe failure summary:"
    kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" logs \
        "job/$SCHEMA_JOB_NAME" --tail=200 2>/dev/null |
        awk '
          function emit_error_codes(line, remaining, code) {
            remaining = line
            while (match(remaining, /(ORA|SP2|TNS)-[0-9][0-9]*/)) {
              code = substr(remaining, RSTART, RLENGTH)
              if (!seen[code]++) print "  database error code: " code
              remaining = substr(remaining, RSTART + RLENGTH)
            }
          }
          /^(Preparing CLOUDBANK|Checking full-demo|Applying pending|Verifying full-demo|Granting the runtime|Verifying the loan|Verifying runtime database credentials|Securing the CLOUDBANK|ERROR:|WARNING:)/ {
            print "  " $0
          }
          { emit_error_codes($0) }
        ' >&2 || true
}

run_schema_initializer() {
    local file="$WORK_DIR/schema-init-job.yaml"

    info "Bootstrapping the CloudBank full-demo schema on Autonomous Database with Job '$SCHEMA_JOB_NAME'."
    kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" apply -f "$file" >/dev/null
    if ! kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" wait \
        --for=condition=complete "job/$SCHEMA_JOB_NAME" --timeout="$TIMEOUT"; then
        kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" get "job/$SCHEMA_JOB_NAME" \
            -o custom-columns=NAME:.metadata.name,ACTIVE:.status.active,SUCCEEDED:.status.succeeded,FAILED:.status.failed >&2 || true
        report_schema_initializer_failure
        die "CloudBank schema bootstrap did not complete; review the safe failure summary above"
    fi
    info "CloudBank full-demo schema bootstrap and contract verification completed."
}

ensure_policy_service_account() {
    local release_name
    local release_namespace
    local managed_by

    if kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" \
        get serviceaccount "$POLICY_SERVICE_ACCOUNT" >/dev/null 2>&1; then
        release_name="$(kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" \
            get serviceaccount "$POLICY_SERVICE_ACCOUNT" \
            -o jsonpath='{.metadata.annotations.meta\.helm\.sh/release-name}')"
        release_namespace="$(kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" \
            get serviceaccount "$POLICY_SERVICE_ACCOUNT" \
            -o jsonpath='{.metadata.annotations.meta\.helm\.sh/release-namespace}')"
        managed_by="$(kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" \
            get serviceaccount "$POLICY_SERVICE_ACCOUNT" \
            -o jsonpath='{.metadata.labels.app\.kubernetes\.io/managed-by}')"
        [[ "$release_name" == policy-retrieval-service && "$release_namespace" == "$NAMESPACE" &&
            "$managed_by" == Helm ]] ||
            die "existing policy ServiceAccount is not owned by the policy-retrieval-service Helm release"
        return 0
    fi

    kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" \
        apply -f "$WORK_DIR/policy-service-account.yaml" >/dev/null
    info "Created the policy ServiceAccount for the loader; the policy-retrieval-service Helm release will adopt it."
}

report_policy_loader_failure() {
    info "Policy loader Pod status:"
    kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" get pods \
        -l "job-name=$POLICY_LOADER_JOB_NAME" \
        -o 'custom-columns=POD:.metadata.name,PHASE:.status.phase,REASON:.status.containerStatuses[0].state.terminated.reason,EXIT_CODE:.status.containerStatuses[0].state.terminated.exitCode' \
        --no-headers >&2 || true

    info "Policy loader event reasons:"
    kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" get events \
        --field-selector "involvedObject.kind=Job,involvedObject.name=$POLICY_LOADER_JOB_NAME" \
        -o json 2>/dev/null |
        jq -r '[.items[]?.reason] | group_by(.)[] | "  \(.[0]): \(length)"' >&2 || true

    info "Policy loader safe failure summary:"
    kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" logs \
        "job/$POLICY_LOADER_JOB_NAME" --tail=200 2>/dev/null |
        awk '/Policy corpus|policy corpus|OCI GenAI EmbedText request failed|APPLICATION FAILED|ORA-[0-9]+/ { print "  " $0 }' \
        >&2 || true
}

run_policy_loader() {
    local file="$WORK_DIR/policy-loader-job.yaml"

    info "Loading the versioned policy corpus with Job '$POLICY_LOADER_JOB_NAME'."
    kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" apply -f "$file" >/dev/null
    if ! kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" wait \
        --for=condition=complete "job/$POLICY_LOADER_JOB_NAME" --timeout="$TIMEOUT"; then
        report_policy_loader_failure
        die "CloudBank policy corpus loading did not complete"
    fi
    kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" get "job/$POLICY_LOADER_JOB_NAME" \
        -o custom-columns=NAME:.metadata.name,SUCCEEDED:.status.succeeded,FAILED:.status.failed
    info "CloudBank policy corpus load completed."
}

yaml_literal() {
    local value="$1"
    [[ "$value" != *'"'* && "$value" != *$'\n'* && "$value" != *$'\r'* ]] ||
        die "value cannot be represented safely in generated Helm values"
    printf '%s' "$value"
}

write_env_literal() {
    local name="$1"
    local value="$2"
    printf '  - name: %s\n    value: "%s"\n' "$name" "$(yaml_literal "$value")"
}

write_env_secret() {
    local name="$1"
    local secret_name="$2"
    local key="$3"
    printf '  - name: %s\n    valueFrom:\n      secretKeyRef:\n        name: "%s"\n        key: "%s"\n' \
        "$name" "$secret_name" "$key"
}

write_common_values() {
    local file="$1"
    local service="$2"
    local framework="$3"
    local port="$4"
    local eureka_enabled="$5"
    local liveness_path="$6"
    local readiness_path="$7"

    {
        printf 'fullnameOverride: "%s"\n' "$service"
        printf 'image:\n  repository: "%s"\n  tag: "%s"\n  pullPolicy: IfNotPresent\n' \
            "$(image_repository "$service")" "$IMAGE_TAG"
        printf 'imagePullSecrets:\n  - name: "%s"\n' "$IMAGE_PULL_SECRET"
        printf 'obaas:\n  releaseName: "%s"\n  framework: "%s"\n' "$OBAAS_RELEASE" "$framework"
        printf 'replicaCount: 1\n'
        printf 'service:\n  type: ClusterIP\n  port: %s\n' "$port"
        printf 'eureka:\n  enabled: %s\n' "$eureka_enabled"
        printf 'otel:\n  enabled: true\n'
        printf 'otmm:\n  enabled: false\n'
        printf 'podSecurityContext:\n  runAsNonRoot: true\n  runAsUser: 10001\n  runAsGroup: 10001\n  fsGroup: 10001\n  seccompProfile:\n    type: RuntimeDefault\n'
        printf 'securityContext:\n  runAsNonRoot: true\n  allowPrivilegeEscalation: false\n  capabilities:\n    drop:\n      - ALL\n'
        printf 'livenessProbe:\n  httpGet:\n    path: %s\n    port: %s\n  initialDelaySeconds: 60\n  periodSeconds: 10\n  timeoutSeconds: 5\n  failureThreshold: 12\n' "$liveness_path" "$port"
        printf 'readinessProbe:\n  httpGet:\n    path: %s\n    port: %s\n  initialDelaySeconds: 20\n  periodSeconds: 10\n  timeoutSeconds: 5\n  failureThreshold: 18\n' "$readiness_path" "$port"
    } >"$file"
}

append_database_values() {
    local file="$1"
    local service="$2"
    local secret_name

    secret_name="$(service_db_secret "$service")"
    {
        printf 'database:\n  enabled: true\n  authN:\n    secretName: "%s"\n' "$secret_name"
        printf '  walletSecret: "%s"\n  aq:\n    enabled: false\n' "$WALLET_SECRET"
    } >>"$file"
}

disable_database_values() {
    printf 'database:\n  enabled: false\n' >>"$1"
}

start_env() {
    printf 'env:\n' >>"$1"
}

append_spring_common_env() {
    local file="$1"
    {
        write_env_literal AZN_ISSUER_URI "$AZN_ISSUER_URI"
        write_env_literal AZN_JWK_SET_URI "$AZN_CLUSTER_URL/oauth2/jwks"
        write_env_literal AZN_AUDIENCE cloudbank-api
    } >>"$file"
}

append_spring_database_env() {
    local file="$1"
    local service="$2"
    local prefix
    local secret_name

    case "$service" in
        loan-application-service) prefix=LOAN ;;
        document-ingest) prefix=DOCUMENT_INGEST ;;
        document-review-service) prefix=DOCUMENT_REVIEW ;;
        decision-service) prefix=DECISION ;;
        ai-agent-service) prefix=AI ;;
        policy-retrieval-service) prefix=POLICY ;;
        *) die "no Spring datasource prefix for '$service'" ;;
    esac
    secret_name="$(service_db_secret "$service")"
    {
        write_env_literal "${prefix}_DATASOURCE_URL" 'jdbc:oracle:thin:@$(DB_SERVICE)?TNS_ADMIN=/oracle/tnsadmin'
        write_env_secret "${prefix}_DATASOURCE_USERNAME" "$secret_name" username
        write_env_secret "${prefix}_DATASOURCE_PASSWORD" "$secret_name" password
    } >>"$file"
}

append_workflow_env() {
    local file="$1"
    {
        write_env_literal WORKFLOW_MODE "$WORKFLOW_MODE"
        write_env_literal MICROTX_WORKFLOW_URL "$MICROTX_WORKFLOW_URL"
        write_env_literal MICROTX_WORKFLOW_NAME cloudbank-loan-origination
        write_env_literal MICROTX_TOKEN_URI "$AZN_CLUSTER_URL/oauth2/token"
        write_env_literal MICROTX_CLIENT_ID microtx-workflow-client
        write_env_secret MICROTX_CLIENT_SECRET "$AUTH_SECRET" microtx-client-secret
        write_env_literal MICROTX_SCOPE microtx.workflow
        write_env_literal WORKFLOW_TASK_TOKEN_URI "$AZN_CLUSTER_URL/oauth2/token"
        write_env_literal WORKFLOW_TASK_CLIENT_ID cloudbank-service-client
        write_env_secret WORKFLOW_TASK_CLIENT_SECRET "$AUTH_SECRET" service-client-secret
        write_env_literal WORKFLOW_TASK_SCOPE cloudbank.internal
        write_env_literal WORKFLOW_DISPATCH_DELAY_MS 1000
        write_env_literal WORKFLOW_MAX_DISPATCH_ATTEMPTS 5
    } >>"$file"
}

generate_service_values() {
    local service="$1"
    local file="$2"

    case "$service" in
        loan-application-service)
            write_common_values "$file" "$service" SPRING_BOOT 8080 true \
                /actuator/health/liveness /actuator/health/readiness
            append_database_values "$file" "$service"
            start_env "$file"
            append_spring_common_env "$file"
            {
                write_env_literal PORT 8080
                write_env_literal EUREKA_CLIENT_ENABLED true
            } >>"$file"
            append_spring_database_env "$file" "$service"
            {
                write_env_literal LOAN_SCHEMA CLOUDBANK
                write_env_literal LOAN_INTERNAL_CLIENT_IDS \
                    cloudbank-service-client,cloudbank-document-ingest-client,cloudbank-document-review-client
            } >>"$file"
            append_workflow_env "$file"
            ;;
        document-ingest)
            write_common_values "$file" "$service" SPRING_BOOT 8080 false \
                /actuator/health/liveness /actuator/health/readiness
            append_database_values "$file" "$service"
            start_env "$file"
            append_spring_common_env "$file"
            write_env_literal PORT 8080 >>"$file"
            append_spring_database_env "$file" "$service"
            {
                write_env_literal DOCUMENT_INGEST_SCHEMA CLOUDBANK
                write_env_literal DOCUMENT_INGEST_TOKEN_URI "$AZN_CLUSTER_URL/oauth2/token"
                write_env_literal DOCUMENT_INGEST_CLIENT_ID cloudbank-document-ingest-client
                write_env_secret DOCUMENT_INGEST_CLIENT_SECRET "$AUTH_SECRET" document-ingest-client-secret
                write_env_literal DOCUMENT_INGEST_CALLER_CLIENT_IDS \
                    cloudbank-service-client,cloudbank-document-review-client
                write_env_literal DOCUMENT_INGEST_REVIEW_INPUT_CLIENT_IDS cloudbank-ai-agent-client
                write_env_literal LOAN_APPLICATION_BASE_URL http://loan-application-service:8080
            } >>"$file"
            ;;
        document-review-service)
            write_common_values "$file" "$service" SPRING_BOOT 8080 false \
                /actuator/health/liveness /actuator/health/readiness
            append_database_values "$file" "$service"
            start_env "$file"
            append_spring_common_env "$file"
            write_env_literal PORT 8080 >>"$file"
            append_spring_database_env "$file" "$service"
            {
                write_env_literal DOCUMENT_REVIEW_SCHEMA CLOUDBANK
                write_env_literal DOCUMENT_REVIEW_TOKEN_URI "$AZN_CLUSTER_URL/oauth2/token"
                write_env_literal DOCUMENT_REVIEW_CLIENT_ID cloudbank-document-review-client
                write_env_secret DOCUMENT_REVIEW_CLIENT_SECRET "$AUTH_SECRET" document-review-client-secret
                write_env_literal DOCUMENT_REVIEW_CALLER_CLIENT_IDS \
                    cloudbank-service-client,cloudbank-ai-agent-client
                write_env_literal LOAN_APPLICATION_BASE_URL http://loan-application-service:8080
                write_env_literal DOCUMENT_INGEST_BASE_URL http://document-ingest:8080
            } >>"$file"
            ;;
        decision-service)
            write_common_values "$file" "$service" SPRING_BOOT 8080 false \
                /actuator/health/liveness /actuator/health/readiness
            append_database_values "$file" "$service"
            start_env "$file"
            append_spring_common_env "$file"
            write_env_literal PORT 8080 >>"$file"
            append_spring_database_env "$file" "$service"
            {
                write_env_literal DECISION_SCHEMA CLOUDBANK
                write_env_literal DECISION_CALLER_CLIENT_IDS cloudbank-service-client
                write_env_literal DECISION_TOKEN_URI "$AZN_CLUSTER_URL/oauth2/token"
                write_env_literal DECISION_CLIENT_ID cloudbank-service-client
                write_env_secret DECISION_CLIENT_SECRET "$AUTH_SECRET" service-client-secret
                write_env_literal LOAN_APPLICATION_BASE_URL http://loan-application-service:8080
            } >>"$file"
            ;;
        ai-agent-service)
            write_common_values "$file" "$service" SPRING_BOOT 8080 false \
                /actuator/health/liveness /actuator/health/readiness
            append_database_values "$file" "$service"
            printf 'serviceAccount:\n  create: true\n  name: "%s"\n' "$AI_SERVICE_ACCOUNT" >>"$file"
            start_env "$file"
            append_spring_common_env "$file"
            append_spring_database_env "$file" "$service"
            {
                write_env_literal PORT 8080
                write_env_literal AI_SCHEMA CLOUDBANK
                write_env_literal AI_AGENT_CALLER_CLIENT_IDS cloudbank-service-client
                write_env_literal AI_AGENT_TOKEN_URI "$AZN_CLUSTER_URL/oauth2/token"
                write_env_literal AI_AGENT_CLIENT_ID cloudbank-ai-agent-client
                write_env_secret AI_AGENT_CLIENT_SECRET "$AUTH_SECRET" ai-agent-client-secret
                write_env_literal DOCUMENT_REVIEW_BASE_URL http://document-review-service:8080
                write_env_literal DOCUMENT_INGEST_BASE_URL http://document-ingest:8080
                write_env_literal AI_OCI_GENAI_AUTHENTICATION_TYPE WORKLOAD_IDENTITY
                write_env_literal AI_OCI_GENAI_REGION "$AI_OCI_REGION"
                write_env_literal AI_OCI_GENAI_CHAT_MODEL "$AI_OCI_GENAI_CHAT_MODEL"
                write_env_literal OKE_CLUSTER_COMPARTMENT_ID "$OKE_CLUSTER_COMPARTMENT_ID"
                if [[ -n "$AI_OCI_FEDERATION_ENDPOINT" ]]; then
                    write_env_literal AI_OCI_GENAI_FEDERATION_ENDPOINT "$AI_OCI_FEDERATION_ENDPOINT"
                fi
            } >>"$file"
            ;;
        geographic-risk-service)
            write_common_values "$file" "$service" HELIDON 8080 false /health/live /health/ready
            append_database_values "$file" "$service"
            printf 'helidon:\n  datasource:\n    name: geographic-risk\n  metrics:\n    rest_request_enabled: true\n    virtual_threads_enabled: true\n' >>"$file"
            start_env "$file"
            {
                write_env_literal OTEL_INSTRUMENTATION_LOGBACK_MDC_ENABLED true
                write_env_literal GEOGRAPHIC_RISK_BOUNDARY_DISTANCE_METERS 100
                write_env_literal GEOGRAPHIC_RISK_LOG_GEOCODING_DETAILS "$GEOGRAPHIC_RISK_LOG_GEOCODING_DETAILS"
                write_env_literal AZN_ISSUER_URI "$AZN_ISSUER_URI"
                write_env_literal AZN_JWK_SET_URI "$AZN_CLUSTER_URL/oauth2/jwks"
                write_env_literal AZN_AUDIENCE cloudbank-api
                write_env_literal GEOGRAPHIC_RISK_CALLER_CLIENT_IDS cloudbank-service-client
                write_env_literal javax.sql.DataSource.geographic-risk.initialPoolSize 2
                write_env_literal javax.sql.DataSource.geographic-risk.minPoolSize 2
                write_env_literal javax.sql.DataSource.geographic-risk.maxPoolSize 16
                write_env_literal javax.sql.DataSource.geographic-risk.connectionWaitTimeout 10
                write_env_literal javax.sql.DataSource.geographic-risk.validateConnectionOnBorrow true
                write_env_literal javax.sql.DataSource.geographic-risk.SQLForValidateConnection 'select 1 from dual'
                write_env_literal javax.sql.DataSource.geographic-risk.inactiveConnectionTimeout 120
                write_env_literal javax.sql.DataSource.geographic-risk.timeoutCheckInterval 30
            } >>"$file"
            ;;
        policy-retrieval-service)
            write_common_values "$file" "$service" SPRING_BOOT 8080 true \
                /actuator/health/liveness /actuator/health/readiness
            append_database_values "$file" "$service"
            printf 'serviceAccount:\n  create: true\n  name: "%s"\n' "$POLICY_SERVICE_ACCOUNT" >>"$file"
            start_env "$file"
            append_spring_common_env "$file"
            {
                write_env_literal PORT 8080
                write_env_literal EUREKA_CLIENT_ENABLED true
                # OCI GenAI uses Jersey 3. Keep Eureka on Spring RestClient so
                # Jersey's presence does not select an unavailable Eureka transport.
                write_env_literal EUREKA_CLIENT_JERSEY_ENABLED false
            } >>"$file"
            append_spring_database_env "$file" "$service"
            {
                write_env_literal POLICY_SCHEMA CLOUDBANK
                write_env_literal OCI_GENAI_AUTHENTICATION_TYPE "$POLICY_AUTHENTICATION_TYPE"
                write_env_literal OCI_GENAI_REGION "$POLICY_OCI_REGION"
                write_env_literal OCI_GENAI_EMBEDDING_MODEL "$POLICY_OCI_EMBEDDING_MODEL"
                write_env_literal OCI_GENAI_EMBEDDING_COMPARTMENT_ID "$POLICY_OCI_COMPARTMENT_ID"
                if [[ -n "$POLICY_OCI_FEDERATION_ENDPOINT" ]]; then
                    write_env_literal OCI_GENAI_FEDERATION_ENDPOINT "$POLICY_OCI_FEDERATION_ENDPOINT"
                fi
            } >>"$file"
            ;;
        workflow-token-refresh-worker)
            write_common_values "$file" "$service" SPRING_BOOT 8080 false \
                /actuator/health/liveness /actuator/health/readiness
            disable_database_values "$file"
            start_env "$file"
            {
                write_env_literal PORT 8080
                write_env_literal WORKFLOW_MODE "$WORKFLOW_MODE"
                write_env_literal MICROTX_WORKFLOW_URL "$MICROTX_WORKFLOW_URL"
                write_env_literal WORKFLOW_TOKEN_REFRESH_TASK_TYPE refresh_workflow_authorization
                write_env_literal WORKFLOW_TOKEN_REFRESH_WORKER_ID cloudbank-workflow-token-refresh-worker
                write_env_literal WORKFLOW_TOKEN_REFRESH_POLL_DELAY_MS 1000
                write_env_literal WORKFLOW_TOKEN_REFRESH_MICROTX_TOKEN_URI "$AZN_CLUSTER_URL/oauth2/token"
                write_env_literal WORKFLOW_TOKEN_REFRESH_MICROTX_CLIENT_ID microtx-workflow-client
                write_env_secret WORKFLOW_TOKEN_REFRESH_MICROTX_CLIENT_SECRET "$AUTH_SECRET" microtx-client-secret
                write_env_literal WORKFLOW_TOKEN_REFRESH_MICROTX_SCOPE microtx.workflow
                write_env_literal WORKFLOW_TOKEN_REFRESH_TASK_TOKEN_URI "$AZN_CLUSTER_URL/oauth2/token"
                write_env_literal WORKFLOW_TOKEN_REFRESH_TASK_CLIENT_ID cloudbank-service-client
                write_env_secret WORKFLOW_TOKEN_REFRESH_TASK_CLIENT_SECRET "$AUTH_SECRET" service-client-secret
                write_env_literal WORKFLOW_TOKEN_REFRESH_TASK_SCOPE cloudbank.internal
            } >>"$file"
            ;;
        *) die "unsupported service '$service'" ;;
    esac
}

generate_values_files() {
    local service
    mkdir -p "$WORK_DIR/values"
    for service in "${SERVICES[@]}"; do
        generate_service_values "$service" "$WORK_DIR/values/$service.yaml"
    done
}

validate_deploy_state() {
    local service
    local release_json
    local release_count
    local release_status
    local installed_app_version
    local current_image
    local deployment_exists
    local first_deploy_ready_count=0
    local redeploy_existing_count=0
    local redeploy_new_count=0

    for service in "${SERVICES[@]}"; do
        release_json="$(helm list "${HELM_LIST_ALL_STATUS_ARGS[@]}" \
            --kube-context "$KUBECTL_CONTEXT" --namespace "$NAMESPACE" \
            --filter "^${service}$" --output json)"
        release_count="$(printf '%s' "$release_json" | jq 'length')"
        deployment_exists=false
        if kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" get deployment "$service" >/dev/null 2>&1; then
            deployment_exists=true
        fi

        if [[ "$DEPLOY_MODE" == first-deploy ]]; then
            if [[ "$release_count" -eq 0 && "$deployment_exists" == false ]]; then
                continue
            fi
            if [[ "$release_count" -eq 1 ]]; then
                release_status="$(printf '%s' "$release_json" | jq -r '.[0].status')"
                installed_app_version="$(printf '%s' "$release_json" | jq -r '.[0].app_version')"
                validate_obaas_application_chart_transition "$service" "$installed_app_version" "$OBAAS_VERSION"
                case "$release_status" in
                    failed)
                        info "Found failed '$service' deployment; it will be resumed."
                        continue
                        ;;
                    deployed)
                        [[ "$deployment_exists" == true ]] ||
                            die "deployed Helm release '$service' has no Deployment"
                        first_deploy_ready_count=$((first_deploy_ready_count + 1))
                        info "Found completed '$service' deployment; it will be reconciled with the generated image tag."
                        continue
                        ;;
                esac
            fi
            die "$service already exists in namespace '$NAMESPACE'; use redeploy"
        fi

        if [[ "$release_count" -eq 0 && "$deployment_exists" == false ]]; then
            redeploy_new_count=$((redeploy_new_count + 1))
            info "No existing '$service' Helm release or Deployment; redeploy will install it."
            continue
        fi
        [[ "$release_count" -eq 1 && "$deployment_exists" == true ]] ||
            die "redeploy found an inconsistent '$service' state; expected both its Helm release and Deployment, or neither"
        redeploy_existing_count=$((redeploy_existing_count + 1))
        installed_app_version="$(printf '%s' "$release_json" | jq -r '.[0].app_version')"
        validate_obaas_application_chart_transition "$service" "$installed_app_version" "$OBAAS_VERSION"
        current_image="$(kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" get deployment "$service" \
            -o jsonpath='{.spec.template.spec.containers[0].image}')"
        [[ -n "$current_image" ]] || die "could not determine current image for '$service'"
        [[ "$current_image" != "$(image_repository "$service"):$IMAGE_TAG" ]] ||
            die "redeploy requires a new image tag for '$service'"
    done

    if [[ "$DEPLOY_MODE" == first-deploy &&
          "$first_deploy_ready_count" -eq "${#SERVICES[@]}" ]]; then
        die "all CloudBank services are already deployed; use redeploy with a new image tag"
    fi
    if [[ "$DEPLOY_MODE" == redeploy && "$redeploy_existing_count" -eq 0 ]]; then
        die "redeploy found no existing CloudBank service releases; use first-deploy"
    fi
    if [[ "$DEPLOY_MODE" == redeploy && "$redeploy_new_count" -gt 0 ]]; then
        info "Redeploy will upgrade $redeploy_existing_count existing service(s) and install $redeploy_new_count new service(s)."
    fi
}

detect_platforms() {
    local architectures
    local architecture
    local platforms=""

    architectures="$(kubectl --context "$KUBECTL_CONTEXT" get nodes \
        --output jsonpath='{range .items[*]}{.status.nodeInfo.architecture}{"\n"}{end}' | sort -u)"
    [[ -n "$architectures" ]] || die "no node architecture was returned by the target cluster"
    while IFS= read -r architecture; do
        case "$architecture" in
            amd64|arm64) ;;
            *) die "unsupported Kubernetes node architecture: $architecture" ;;
        esac
        [[ -n "$platforms" ]] && platforms="$platforms,"
        platforms="${platforms}linux/${architecture}"
    done <<<"$architectures"
    TARGET_PLATFORMS="$platforms"
}

ensure_ocir_repositories() {
    local image_name
    local repository_name
    local repository_visibility
    local repository_count
    local -a oci_args

    for image_name in "${PUBLISHED_IMAGES[@]}"; do
        repository_name="$OCI_REPOSITORY_PATH_PREFIX/$image_name"
        oci_args=(artifacts container repository list
            --compartment-id "$OCI_COMPARTMENT_OCID"
            --display-name "$repository_name"
            --region "$OCI_REGION"
            --query 'data.items[*]."is-public"'
            --output json)
        repository_visibility="$(oci "${oci_args[@]}")"
        repository_count="$(printf '%s' "$repository_visibility" | jq -r length)"
        case "$repository_count" in
            0)
                info "Creating private OCIR repository '$repository_name'."
                oci_args=(artifacts container repository create
                    --compartment-id "$OCI_COMPARTMENT_OCID"
                    --display-name "$repository_name"
                    --is-public false
                    --region "$OCI_REGION")
                oci "${oci_args[@]}" >/dev/null
                ;;
            1)
                jq -e '.[0] == false' <<<"$repository_visibility" >/dev/null ||
                    die "OCIR repository '$repository_name' is public; refusing deployment"
                ;;
            *) die "unexpected number of OCIR repositories named '$repository_name'" ;;
        esac
    done
}

prepare_registry_login_and_pull_secret() {
    local secret_type
    local pull_config_file

    [[ "$DRY_RUN" != true ]] || return 0
    [[ -n "$ISOLATED_DOCKER_CONFIG" && -d "$ISOLATED_DOCKER_CONFIG" ]] ||
        die "the isolated Docker configuration was not prepared"

    if ! printf '%s' "$OCI_AUTH_TOKEN" | DOCKER_CONFIG="$ISOLATED_DOCKER_CONFIG" docker login \
        --username "$OCI_IDENTITY_NAME" --password-stdin "$OCIR_HOST" >/dev/null 2>&1; then
        die "Docker login to '$OCIR_HOST' failed"
    fi
    REGISTRY_LOGGED_IN=true

    if kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" get secret "$IMAGE_PULL_SECRET" >/dev/null 2>&1; then
        secret_type="$(kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" get secret "$IMAGE_PULL_SECRET" \
            -o jsonpath='{.type}')"
        [[ "$secret_type" == kubernetes.io/dockerconfigjson ]] ||
            die "existing image pull Secret '$IMAGE_PULL_SECRET' has the wrong type"
    fi

    pull_config_file="$WORK_DIR/ocir-pull-config.json"
    # Embed auth for Kubernetes rather than copying Docker Desktop helper references.
    (
        umask 077
        printf '%s' "$OCI_AUTH_TOKEN" |
            jq -Rs --arg username "$OCI_IDENTITY_NAME" --arg registry "$OCIR_HOST" \
                '{auths: {($registry): {auth: (($username + ":" + .) | @base64)}}}' \
                >"$pull_config_file"
    ) ||
        die "could not prepare the OCIR image pull configuration"
    chmod 600 "$pull_config_file"
    kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" create secret generic "$IMAGE_PULL_SECRET" \
        --type=kubernetes.io/dockerconfigjson \
        --from-file=.dockerconfigjson="$pull_config_file" --dry-run=client -o yaml |
        kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" \
            apply --server-side --field-manager=cloudbank-ocir-pull-secret --force-conflicts -f - >/dev/null ||
        die "failed to synchronize image pull Secret '$IMAGE_PULL_SECRET'"
    info "Synchronized private image pull Secret '$IMAGE_PULL_SECRET' using OCI_AUTH_TOKEN."
}

run_tests() {
    info "Running the root Maven test suite before image publication."
    mvn -B -ntp test
}

build_and_publish_images() {
    local image_name
    local image_reference

    for image_name in "${PUBLISHED_IMAGES[@]}"; do
        image_reference="$(image_repository "$image_name"):$IMAGE_TAG"
        info "Building and publishing '$image_name' for $TARGET_PLATFORMS."
        DOCKER_CONFIG="$ISOLATED_DOCKER_CONFIG" docker buildx build \
            --platform "$TARGET_PLATFORMS" \
            --target "$image_name" \
            --tag "$image_reference" \
            --push \
            "$REPOSITORY_ROOT"
        DOCKER_CONFIG="$ISOLATED_DOCKER_CONFIG" docker buildx imagetools inspect "$image_reference" >/dev/null ||
            die "published image verification failed for '$image_name'"
    done
}

show_plan() {
    local service
    local current_image

    cat <<EOF

CloudBank services deployment plan
  mode:                    $DEPLOY_MODE
  kubectl context:         $KUBECTL_CONTEXT
  OCI region:              $OCI_REGION
  OKE cluster:             $OKE_CLUSTER_OCID
  namespace:               $NAMESPACE
  OBaaS release:           $OBAAS_RELEASE ($OBAAS_VERSION)
  application chart:      $RESOLVED_CHART
  image tag:               $IMAGE_TAG
  build platforms:         ${TARGET_PLATFORMS:-<not detected>}
  OCIR base:               $IMAGE_REPOSITORY_PREFIX
  image pull Secret:       $IMAGE_PULL_SECRET
  privileged DB Secret:    $DB_PRIV_SECRET
  database wallet Secret:  $WALLET_SECRET
  database Secret state:   $DB_SECRET_STATE
  database service source: ${DATABASE_SERVICE_SOURCE:-existing per-service Secrets}
  schema-owner Secret:     $SCHEMA_OWNER_SECRET ($SCHEMA_OWNER_SECRET_STATE)
  schema profile:          full-demo
  schema Job:              $SCHEMA_JOB_NAME
  schema image:            $(image_repository "$SCHEMA_INITIALIZER"):$IMAGE_TAG
  policy loader Job:       $POLICY_LOADER_JOB_NAME
  policy loader image:     $(image_repository "$POLICY_LOADER"):$IMAGE_TAG
  azn-server auth Secret:  $AUTH_SECRET
  azn-server issuer:       $AZN_ISSUER_URI
  lab owner:              obaas-admin (automatic application ADMIN grant)
  Helm conflict mode:     ${HELM_UPGRADE_CONFLICT_ARGS[*]:-standard}
  azn-server pod URL:      $AZN_CLUSTER_URL
  workflow mode:           $WORKFLOW_MODE
  workflow URL:            ${MICROTX_WORKFLOW_URL:-<disabled>}
  workflow URL source:     $MICROTX_WORKFLOW_URL_SOURCE
  policy OCI auth:         $POLICY_AUTHENTICATION_TYPE
  policy ServiceAccount:   $POLICY_SERVICE_ACCOUNT
  AI OCI auth:             WORKLOAD_IDENTITY
  AI OCI region:           $AI_OCI_REGION
  AI chat model:           $AI_OCI_GENAI_CHAT_MODEL
  AI ServiceAccount:       $AI_SERVICE_ACCOUNT
  preflight validation:    passed
  services:
EOF
    for service in "${SERVICES[@]}"; do
        printf '    - %s: %s:%s' "$service" "$(image_repository "$service")" "$IMAGE_TAG"
        if [[ "$DEPLOY_MODE" == redeploy ]]; then
            if kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" \
                get deployment "$service" >/dev/null 2>&1; then
                current_image="$(kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" \
                    get deployment "$service" \
                    -o jsonpath='{.spec.template.spec.containers[0].image}')"
                printf ' (current: %s)' "$current_image"
            else
                printf ' (new Helm release and Deployment)'
            fi
        fi
        printf '\n'
    done
}

confirm_deployment() {
    local answer

    [[ -t 0 ]] || die "deployment confirmation requires an interactive terminal"
    printf '\nBuild/push ten images, bootstrap ADB, load policy, and deploy all eight services on this target? [y/N] ' >&2
    read -r answer
    [[ "$answer" == y || "$answer" == Y ]] || {
        info "Deployment cancelled."
        exit 0
    }
}

render_and_lint() {
    local service
    local values_file
    local rendered_manifest
    local lint_output

    kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" apply \
        --dry-run=client -f "$WORK_DIR/schema-init-job.yaml" >/dev/null
    kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" apply \
        --dry-run=client -f "$WORK_DIR/policy-service-account.yaml" >/dev/null
    kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" apply \
        --dry-run=client -f "$WORK_DIR/policy-loader-job.yaml" >/dev/null
    grep -A1 'name:[[:space:]]*TNS_ADMIN[[:space:]]*$' "$WORK_DIR/schema-init-job.yaml" |
        grep -q 'value:[[:space:]]*/oracle/tnsadmin[[:space:]]*$' ||
        die "schema initializer does not configure SQLcl TNS_ADMIN"
    grep -A1 'name:[[:space:]]*LOAN_SQLCL_CONNECT[[:space:]]*$' "$WORK_DIR/schema-init-job.yaml" |
        grep -Fq 'value: "$(DB_SERVICE)"' ||
        die "schema initializer does not configure the SQLcl service alias"
    if grep -A1 'name:[[:space:]]*LOAN_SQLCL_CONNECT[[:space:]]*$' "$WORK_DIR/schema-init-job.yaml" |
        grep -Fq '?TNS_ADMIN='; then
        die "schema initializer must pass SQLcl TNS_ADMIN separately from the service alias"
    fi
    grep -q "serviceAccountName:[[:space:]]*\"$POLICY_SERVICE_ACCOUNT\"" \
        "$WORK_DIR/policy-loader-job.yaml" ||
        die "policy loader does not use the policy Workload Identity ServiceAccount"
    grep -Fq "$(service_db_secret policy-loader)" "$WORK_DIR/policy-loader-job.yaml" ||
        die "policy loader does not reference its dedicated database Secret"
    grep -Fq "$WALLET_SECRET" "$WORK_DIR/policy-loader-job.yaml" ||
        die "policy loader does not mount the ADB wallet"
    if grep -Fq "$DB_PRIV_SECRET" "$WORK_DIR/policy-loader-job.yaml" ||
        grep -Fq "$SCHEMA_OWNER_SECRET" "$WORK_DIR/policy-loader-job.yaml" ||
        grep -Fq "$AUTH_SECRET" "$WORK_DIR/policy-loader-job.yaml"; then
        die "policy loader references a privileged or unrelated Secret"
    fi
    kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" apply \
        --server-side --dry-run=server --force-conflicts \
        --field-manager=cloudbank-render-preflight \
        -f "$WORK_DIR/policy-service-account.yaml" >/dev/null ||
        die "Kubernetes server-side validation failed for the policy ServiceAccount"
    kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" apply \
        --server-side --dry-run=server --force-conflicts \
        --field-manager=cloudbank-render-preflight \
        -f "$WORK_DIR/policy-loader-job.yaml" >/dev/null ||
        die "Kubernetes server-side validation failed for the policy loader Job"

    for service in "${SERVICES[@]}"; do
        values_file="$WORK_DIR/values/$service.yaml"
        rendered_manifest="$WORK_DIR/$service-rendered.yaml"
        if ! lint_output="$(helm lint "$RESOLVED_CHART" --namespace "$NAMESPACE" \
            --values "$values_file" 2>&1)"; then
            printf 'Helm lint failed for service %q:\n%s\n' "$service" "$lint_output" >&2
            die "chart validation failed for '$service'"
        fi
        helm template "$service" "$RESOLVED_CHART" --namespace "$NAMESPACE" \
            --values "$values_file" >"$rendered_manifest"
        grep -q '^kind:[[:space:]]*Deployment[[:space:]]*$' "$rendered_manifest" ||
            die "rendered chart for '$service' has no Deployment"
        if grep -Fq "$DB_PRIV_SECRET" "$rendered_manifest"; then
            die "rendered chart for '$service' exposes the privileged database Secret"
        fi
        if grep -q '^kind:[[:space:]]*Job[[:space:]]*$' "$rendered_manifest"; then
            die "rendered application chart for '$service' contains an unexpected database Job"
        fi
        case "$service" in
            ai-agent-service)
                grep -Fq "$(service_db_secret "$service")" "$rendered_manifest" ||
                    die "database-enabled service '$service' does not reference its runtime database Secret"
                grep -Fq "$WALLET_SECRET" "$rendered_manifest" ||
                    die "database-enabled service '$service' does not mount the ADB wallet"
                grep -Eq "^[[:space:]]*serviceAccountName:[[:space:]]*[\"']?${AI_SERVICE_ACCOUNT}[\"']?[[:space:]]*$" \
                    "$rendered_manifest" ||
                    die "ai-agent-service does not use its Workload Identity ServiceAccount"
                grep -A1 'name:[[:space:]]*AI_OCI_GENAI_AUTHENTICATION_TYPE[[:space:]]*$' \
                    "$rendered_manifest" | grep -q 'value:[[:space:]]*WORKLOAD_IDENTITY[[:space:]]*$' ||
                    die "ai-agent-service does not select OKE Workload Identity"
                ;;
            workflow-token-refresh-worker)
                if grep -Fq "$WALLET_SECRET" "$rendered_manifest" ||
                    grep -q 'name:[[:space:]]*DB_SERVICE[[:space:]]*$' "$rendered_manifest"; then
                    die "database-disabled service '$service' still renders database access"
                fi
                ;;
            *)
                grep -Fq "$(service_db_secret "$service")" "$rendered_manifest" ||
                    die "database-enabled service '$service' does not reference its runtime database Secret"
                grep -Fq "$WALLET_SECRET" "$rendered_manifest" ||
                    die "database-enabled service '$service' does not mount the ADB wallet"
                ;;
        esac
        if grep -Eq '^kind:[[:space:]]*Ingress[[:space:]]*$|^[[:space:]]*type:[[:space:]]*LoadBalancer[[:space:]]*$' \
            "$rendered_manifest"; then
            die "rendered chart for '$service' exposes an external route; services must remain internal"
        fi
        kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" apply \
            --server-side --dry-run=server --force-conflicts \
            --field-manager=cloudbank-render-preflight \
            -f "$rendered_manifest" >/dev/null ||
            die "Kubernetes server-side validation failed for '$service'"
    done
}

deploy_services() {
    local service
    local values_file
    local endpoint_count
    local deployed_service_account

    for service in "${SERVICES[@]}"; do
        values_file="$WORK_DIR/values/$service.yaml"
        info "Deploying '$service'."
        helm upgrade --install "$service" "$RESOLVED_CHART" \
            --kube-context "$KUBECTL_CONTEXT" \
            --namespace "$NAMESPACE" \
            --reset-values \
            --values "$values_file" \
            ${HELM_UPGRADE_CONFLICT_ARGS[@]+"${HELM_UPGRADE_CONFLICT_ARGS[@]}"} \
            --wait --wait-for-jobs --timeout "$TIMEOUT"
        kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" rollout status \
            deployment/"$service" --timeout="$TIMEOUT"
        case "$service" in
            ai-agent-service)
                deployed_service_account="$(kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" \
                    get deployment "$service" -o jsonpath='{.spec.template.spec.serviceAccountName}')"
                [[ "$deployed_service_account" == "$AI_SERVICE_ACCOUNT" ]] ||
                    die "deployed ai-agent-service does not use ServiceAccount '$AI_SERVICE_ACCOUNT'"
                ;;
            policy-retrieval-service)
                deployed_service_account="$(kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" \
                    get deployment "$service" -o jsonpath='{.spec.template.spec.serviceAccountName}')"
                [[ "$deployed_service_account" == "$POLICY_SERVICE_ACCOUNT" ]] ||
                    die "deployed policy-retrieval-service does not use ServiceAccount '$POLICY_SERVICE_ACCOUNT'"
                ;;
        esac
        endpoint_count="$(kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" get endpointslice \
            -l "kubernetes.io/service-name=$service" -o json |
            jq '[.items[]?.endpoints[]? | select(.conditions.ready != false)] | length')"
        [[ "$endpoint_count" -ge 1 ]] ||
            die "service '$service' has no ready EndpointSlice endpoint"
        kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" get deployment "$service" \
            -o custom-columns=NAME:.metadata.name,READY:.status.readyReplicas,IMAGE:.spec.template.spec.containers[0].image
    done
}

cleanup() {
    local status=$?
    trap - EXIT
    if [[ "$REGISTRY_LOGGED_IN" == true ]]; then
        DOCKER_CONFIG="$ISOLATED_DOCKER_CONFIG" docker logout "$OCIR_HOST" >/dev/null 2>&1 || true
    fi
    if [[ -n "${WORK_DIR:-}" && -d "$WORK_DIR" ]]; then
        rm -rf -- "$WORK_DIR"
    fi
    OCI_AUTH_TOKEN=""
    exit "$status"
}

main() {
    parse_args "$@"
    require_commands
    load_deployment_configuration
    configure_helm_list_compatibility
    configure_helm_upgrade_conflict_handling
    validate_inputs

    WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cloudbank-services-deploy.XXXXXX")"
    chmod 700 "$WORK_DIR"
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' HUP TERM

    detect_obaas_release
    resolve_app_chart
    validate_azn_precondition
    resolve_azn_runtime_urls
    [[ -x "$LAB_ADMIN_HELPER" ]] || die "lab owner bootstrap helper is missing or not executable"
    CLOUDBANK_ENV_FILE="$ENV_FILE" "$LAB_ADMIN_HELPER" --check-identity
    resolve_microtx_workflow_url
    resolve_image_repository_prefix
    resolve_schema_job_name
    resolve_platform_secrets
    validate_platform_secrets
    inspect_database_secret_state
    validate_database_secret_material
    validate_deploy_state
    detect_platforms
    generate_values_files
    generate_schema_job_manifest
    generate_policy_service_account_manifest
    generate_policy_loader_job_manifest
    render_and_lint
    show_plan

    info "Preflight completed: chart lint, render, and Kubernetes server-side validation passed; no resources were changed."
    confirm_deployment
    DRY_RUN=false
    require_commands
    prepare_isolated_docker_config
    run_tests
    ensure_ocir_repositories
    prepare_registry_login_and_pull_secret
    build_and_publish_images
    create_cloudbank_database_secrets
    run_schema_initializer
    CLOUDBANK_ENV_FILE="$ENV_FILE" "$LAB_ADMIN_HELPER" --yes \
        --image "$(image_repository "$SCHEMA_INITIALIZER"):$IMAGE_TAG"
    ensure_policy_service_account
    run_policy_loader
    deploy_services
    info ""
    info "CloudBank schema, lab owner access, and policy bootstrap completed; all eight application services are deployed and have ready endpoints."
    info "Deploy and verify workflow-v1-obaas separately against the configured MicroTx Workflow Server."
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
