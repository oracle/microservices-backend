#!/usr/bin/env bash

# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at
# https://oss.oracle.com/licenses/upl.

set -euo pipefail
set +x

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/helm-upgrade.sh"
source "$SCRIPT_DIR/lib/obaas-version.sh"
readonly REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly VALUES_FILE="$REPOSITORY_ROOT/src/azn-server/values.yaml"
readonly RELEASE_NAME="azn-server"
readonly DEFAULT_APP_CHART="obaas/obaas-sample-app"
readonly OBAAS_HELM_REPOSITORY="https://oracle.github.io/microservices-backend/helm"
readonly ENV_FILE="$REPOSITORY_ROOT/.env"
readonly SIGNING_PRIVATE_KEY="$REPOSITORY_ROOT/.cloudbank-local/signing-private.pem"
readonly SIGNING_PUBLIC_KEY="$REPOSITORY_ROOT/.cloudbank-local/signing-public.pem"

DEPLOY_MODE=""
KUBECTL_CONTEXT=""
OCI_REGION=""
CLOUDBANK_KUBECONFIG_PATH=""
NAMESPACE=""
OBAAS_RELEASE=""
OBAAS_VERSION=""
AZN_ISSUER_URI=""
IMAGE_REPOSITORY=""
IMAGE_TAG=""
OCIR_NAMESPACE=""
OCIR_HOST=""
REPOSITORY_PREFIX="cloudbank-ai"
IMAGE_PULL_SECRET=""
APP_CHART="$DEFAULT_APP_CHART"
APP_CHART_VERSION=""
DB_AUTH_SECRET="cloudbank-ai-azn-db-authn"
DB_PRIV_SECRET=""
WALLET_SECRET=""
AUTH_SECRET="cloudbank-ai-azn-auth"
CONSOLE_SECRET="cloudbank-ai-azn-microtx-console"
SIGNING_SECRET="cloudbank-ai-azn-signing-key"
OCI_PROFILE=""
TIMEOUT="8m"
DRY_RUN=false
ASSUME_YES=false
WORK_DIR=""
RESOLVED_CHART=""
CURRENT_IMAGE=""
APPLICATION_SECRET_STATE="none"
BFF_CLIENT_SECRET_MISSING=false
BFF_REDIRECT_MISSING=false
HELM_UPGRADE_CONFLICT_ARGS=()

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 2
}

info() {
    printf '%s\n' "$*"
}

helm_list_supports_all_flag() {
    helm list --help 2>&1 |
        grep -Eq '(^|[[:space:],])--all([[:space:]]|$)'
}

usage() {
    cat <<'EOF'
Deploy or update CloudBank AI azn-server on an OBaaS cluster, version 2.1.0 or later.

Usage:
  ./deploy/obaas/deploy-azn-server.sh first-deploy
  ./deploy/obaas/deploy-azn-server.sh redeploy

Modes:
  first-deploy                Install on a cluster containing OBaaS but no azn-server
  redeploy                    Install a new image tag over an existing azn-server release

Configuration is read from the repository-root .env file. The image tag is read
from NEW_IMAGE_TAG in the process environment. Use deploy-azn-server_v1.sh as
the public entry point; it performs image publication, dry-run review, deployment,
and verification around this Helm helper.
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
        first-deploy|redeploy) ;;
        *) die "mode must be 'first-deploy' or 'redeploy'" ;;
    esac
}

load_deployment_configuration() {
    local variable_name
    local value

    [[ -f "$ENV_FILE" ]] || die ".env is missing; follow azn-server-runbook.md"
    for variable_name in OCI_REGION CLOUDBANK_KUBECONFIG_PATH IMAGE_PULL_SECRET AZN_ISSUER_URI; do
        [[ "$(env_count "$variable_name")" -eq 1 ]] ||
            die "$ENV_FILE must contain exactly one $variable_name entry"
        value="$(env_value "$variable_name")"
        [[ -n "$value" ]] || die "$ENV_FILE variable $variable_name must not be empty"
        case "$value" in
            *$'\n'* | *$'\r'*) die "$ENV_FILE variable $variable_name contains a newline" ;;
        esac
        printf -v "$variable_name" '%s' "$value"
    done
    unset value

    [[ "$CLOUDBANK_KUBECONFIG_PATH" == /* ]] ||
        die "CLOUDBANK_KUBECONFIG_PATH must be an absolute path"
    [[ -f "$CLOUDBANK_KUBECONFIG_PATH" ]] ||
        die "kubeconfig not found: $CLOUDBANK_KUBECONFIG_PATH"
    export KUBECONFIG="$CLOUDBANK_KUBECONFIG_PATH"
    KUBECTL_CONTEXT="$(kubectl config current-context)"
    [[ -n "$KUBECTL_CONTEXT" ]] || die "the configured kubeconfig has no current context"

    IMAGE_TAG="${NEW_IMAGE_TAG:-}"
    case "${AZN_DEPLOY_DRY_RUN:-false}" in
        true) DRY_RUN=true ;;
        false) DRY_RUN=false ;;
        *) die "AZN_DEPLOY_DRY_RUN must be true or false" ;;
    esac
    case "${AZN_DEPLOY_ASSUME_YES:-false}" in
        true) ASSUME_YES=true ;;
        false) ASSUME_YES=false ;;
        *) die "AZN_DEPLOY_ASSUME_YES must be true or false" ;;
    esac
}

require_commands() {
    local command_name
    for command_name in kubectl helm jq awk grep mktemp mkdir chmod tail; do
        command -v "$command_name" >/dev/null 2>&1 || die "$command_name is required"
    done
    if [[ "$DEPLOY_MODE" == "first-deploy" && -z "$IMAGE_REPOSITORY" && -z "$OCIR_NAMESPACE" ]]; then
        command -v oci >/dev/null 2>&1 ||
            die "oci is required for OCIR namespace discovery"
    fi
    command -v openssl >/dev/null 2>&1 || die "openssl is required for OAuth client-secret generation"
}

validate_inputs() {
    [[ "$AZN_ISSUER_URI" == 'http://localhost:8080' ]] ||
        die "this local port-forward profile requires AZN_ISSUER_URI=http://localhost:8080 in .env"
    [[ -f "$VALUES_FILE" ]] || die "Helm values file not found: $VALUES_FILE"
    [[ -n "$KUBECTL_CONTEXT" ]] || die "kubectl context must not be empty"
    [[ -n "$IMAGE_TAG" ]] ||
        die "$DEPLOY_MODE requires NEW_IMAGE_TAG for an already-published image"
    [[ "$IMAGE_TAG" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]] ||
        die "image tag is not a valid OCI image tag"
    [[ -n "$IMAGE_PULL_SECRET" ]] ||
        die "$DEPLOY_MODE requires IMAGE_PULL_SECRET in .env"
    [[ "$OCI_REGION" =~ ^[a-z0-9]+([a-z0-9-]*[a-z0-9])?$ ]] ||
        die "OCI region must be a region identifier such as eu-frankfurt-1"
    [[ "$REPOSITORY_PREFIX" =~ ^[A-Za-z0-9._/-]+$ ]] ||
        die "repository prefix contains unsupported characters"
    if [[ -n "$OCIR_HOST" && ! "$OCIR_HOST" =~ ^[A-Za-z0-9.-]+$ ]]; then
        die "OCIR host contains unsupported characters"
    fi
    [[ "$TIMEOUT" =~ ^[1-9][0-9]*(s|m|h)$ ]] ||
        die "timeout must use Helm duration syntax such as 480s or 8m"
    if ! kubectl config get-contexts "$KUBECTL_CONTEXT" -o name 2>/dev/null |
        grep -Fxq "$KUBECTL_CONTEXT"; then
        die "kubectl context does not exist: $KUBECTL_CONTEXT"
    fi
    kubectl --context "$KUBECTL_CONTEXT" cluster-info >/dev/null
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
        --arg namespace "$NAMESPACE" \
        --arg release "$OBAAS_RELEASE" '
          .[]
          | select(.chart | test("^obaas-[0-9]"))
          | select(($namespace == "") or (.namespace == $namespace))
          | select(($release == "") or (.name == $release))
          | [.name, .namespace, .app_version, .chart]
          | @tsv')"
    release_count="$(printf '%s\n' "$release_rows" | awk 'NF { count++ } END { print count + 0 }')"

    if [[ "$release_count" -eq 0 ]]; then
        die "no OBaaS platform Helm release matched context '$KUBECTL_CONTEXT'${NAMESPACE:+ and namespace '$NAMESPACE'}"
    fi
    if [[ "$release_count" -ne 1 ]]; then
        printf 'Matching OBaaS releases (name, namespace, appVersion, chart):\n%s\n' "$release_rows" >&2
        die "the target kubeconfig must expose exactly one OBaaS platform release"
    fi

    IFS=$'\t' read -r OBAAS_RELEASE NAMESPACE OBAAS_VERSION selected_chart <<<"$release_rows"
    obaas_version_at_least "$OBAAS_VERSION" ||
        die "installed release '$OBAAS_RELEASE' must advertise an OBaaS semantic version >= 2.1.0 (found '$OBAAS_VERSION')"

    kubectl --context "$KUBECTL_CONTEXT" get namespace "$NAMESPACE" >/dev/null
    info "Detected OBaaS release '$OBAAS_RELEASE' ($selected_chart, appVersion $OBAAS_VERSION) in namespace '$NAMESPACE'."
}

validate_deploy_state() {
    local -a helm_list_args
    local release_json
    local release_count
    local release_status
    local installed_app_version
    local deployment_exists=false

    helm_list_args=(list
        --kube-context "$KUBECTL_CONTEXT"
        --namespace "$NAMESPACE"
        --filter "^${RELEASE_NAME}$"
        --output json)
    if helm_list_supports_all_flag; then
        helm_list_args+=(--all)
    fi
    release_json="$(helm "${helm_list_args[@]}")"
    release_count="$(printf '%s' "$release_json" | jq 'length')"
    if kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" get deployment azn-server >/dev/null 2>&1; then
        deployment_exists=true
    fi

    if [[ "$DEPLOY_MODE" == "first-deploy" ]]; then
        if [[ "$release_count" -eq 0 && "$deployment_exists" == false ]]; then
            return 0
        fi
        if [[ "$release_count" -eq 1 ]]; then
            release_status="$(printf '%s' "$release_json" | jq -r '.[0].status')"
            if [[ "$release_status" == "failed" ]]; then
                installed_app_version="$(printf '%s' "$release_json" | jq -r '.[0].app_version')"
                validate_obaas_application_chart_transition "$RELEASE_NAME" "$installed_app_version" "$OBAAS_VERSION"
                info "Found a failed azn-server first deployment; resuming it with helm upgrade --install."
                return 0
            fi
        fi
        die "azn-server already exists in namespace '$NAMESPACE'; use redeploy"
    fi

    [[ "$release_count" -eq 1 && "$deployment_exists" == true ]] ||
        die "redeploy requires an existing Helm release and Deployment named azn-server"
    installed_app_version="$(printf '%s' "$release_json" | jq -r '.[0].app_version')"
    validate_obaas_application_chart_transition "$RELEASE_NAME" "$installed_app_version" "$OBAAS_VERSION"
    CURRENT_IMAGE="$(kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" get deployment azn-server \
        -o jsonpath='{.spec.template.spec.containers[0].image}')"
    [[ -n "$CURRENT_IMAGE" ]] || die "could not determine the current azn-server image"
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
        if [[ "$APP_CHART" == obaas/* ]]; then
            ensure_obaas_helm_repository
        fi
        if [[ -z "$APP_CHART_VERSION" ]]; then
            APP_CHART_VERSION="$(helm search repo "$APP_CHART" --versions --devel --output json |
                jq -er --arg chart "$APP_CHART" --arg target "$OBAAS_VERSION" \
                    'first(.[] | select(.name == $chart and .app_version == $target) | .version) // empty')" ||
                die "no '$APP_CHART' chart advertises appVersion $OBAAS_VERSION, or Helm search failed"
        fi
        [[ -n "$APP_CHART_VERSION" ]] ||
            die "no '$APP_CHART' chart advertises appVersion $OBAAS_VERSION"

        mkdir -p "$WORK_DIR/chart"
        helm pull "$APP_CHART" --version "$APP_CHART_VERSION" \
            --untar --untardir "$WORK_DIR/chart" >/dev/null
        RESOLVED_CHART="$WORK_DIR/chart/$(basename "$APP_CHART")"
        [[ -f "$RESOLVED_CHART/Chart.yaml" ]] ||
            die "pulled chart does not contain the expected Chart.yaml"
    fi

    chart_metadata="$(helm show chart "$RESOLVED_CHART")"
    chart_name="$(printf '%s\n' "$chart_metadata" |
        awk -F':[[:space:]]*' '$1 == "name" { gsub(/"/, "", $2); print $2; exit }')"
    chart_app_version="$(printf '%s\n' "$chart_metadata" |
        awk -F':[[:space:]]*' '$1 == "appVersion" { gsub(/"/, "", $2); print $2; exit }')"

    [[ "$chart_name" == "obaas-sample-app" ]] ||
        die "application chart must be named obaas-sample-app, found '$chart_name'"
    [[ "$chart_app_version" == "$OBAAS_VERSION" ]] ||
        die "application chart appVersion '$chart_app_version' does not match OBaaS $OBAAS_VERSION"
    info "Using application chart '$chart_name' appVersion $chart_app_version${APP_CHART_VERSION:+ (chart $APP_CHART_VERSION)}."
}

resolve_image_repository() {
    local -a oci_args
    local current_reference
    local current_repository_name
    local repository_name

    if [[ "$DEPLOY_MODE" == "redeploy" && -z "$IMAGE_REPOSITORY" ]]; then
        current_reference="${CURRENT_IMAGE%%@*}"
        current_repository_name="${current_reference##*/}"
        IMAGE_REPOSITORY="${current_reference%/*}/${current_repository_name%%:*}"
    fi

    if [[ -z "$IMAGE_REPOSITORY" ]]; then
        if [[ -z "$OCIR_NAMESPACE" ]]; then
            oci_args=(os ns get --region "$OCI_REGION" --query data --raw-output)
            if [[ -n "$OCI_PROFILE" ]]; then
                oci_args+=(--profile "$OCI_PROFILE")
            fi
            OCIR_NAMESPACE="$(oci "${oci_args[@]}")"
        fi
        [[ "$OCIR_NAMESPACE" =~ ^[A-Za-z0-9]+([._-][A-Za-z0-9]+)*$ ]] ||
            die "could not resolve a valid OCIR namespace"

        if [[ -z "$OCIR_HOST" ]]; then
            OCIR_HOST="ocir.${OCI_REGION}.oci.oraclecloud.com"
        fi
        IMAGE_REPOSITORY="${OCIR_HOST}/${OCIR_NAMESPACE}/${REPOSITORY_PREFIX}/azn-server"
    fi

    repository_name="${IMAGE_REPOSITORY##*/}"
    [[ "$IMAGE_REPOSITORY" == */* && "$IMAGE_REPOSITORY" != *[[:space:]]* &&
        "$IMAGE_REPOSITORY" != *@* && "$repository_name" != *:* ]] ||
        die "image repository must be a repository path without a tag or digest"
    if [[ "$DEPLOY_MODE" == "redeploy" && "$IMAGE_REPOSITORY:$IMAGE_TAG" == "$CURRENT_IMAGE" ]]; then
        die "redeploy requires a new image tag; '$IMAGE_TAG' is already deployed"
    fi
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
            die "the target namespace must contain exactly one installation-specific privileged database Secret"
        }
        DB_PRIV_SECRET="$candidates"
    fi
    if [[ -z "$WALLET_SECRET" ]]; then
        candidates="$(printf '%s\n' "$names" | grep -E -- '-adb-tns-admin(-|$)' || true)"
        candidate_count="$(printf '%s\n' "$candidates" | awk 'NF { count++ } END { print count + 0 }')"
        [[ "$candidate_count" -eq 1 ]] || {
            printf 'Database wallet Secret candidates:\n%s\n' "${candidates:-<none>}" >&2
            die "the target namespace must contain exactly one OBaaS database wallet Secret"
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
    if [[ -n "$IMAGE_PULL_SECRET" ]]; then
        kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" get secret "$IMAGE_PULL_SECRET" >/dev/null ||
            die "image pull Secret '$IMAGE_PULL_SECRET' was not found"
    fi
}

validate_application_secrets_without_ai_agent() {
    require_secret_keys "$DB_AUTH_SECRET" username password service
    require_secret_keys "$AUTH_SECRET" \
        user-repo-owner-password admin-password user-password \
        default-client-secret service-client-secret \
        document-ingest-client-secret document-review-client-secret \
        microtx-client-secret
    require_secret_keys "$CONSOLE_SECRET" \
        client-id client-secret scopes redirect-uri post-logout-redirect-uri
    require_secret_keys "$SIGNING_SECRET" private.pem public.pem key-id
}

validate_application_secrets() {
    validate_application_secrets_without_ai_agent
    require_secret_keys "$AUTH_SECRET" ai-agent-client-secret bff-client-secret bff-redirect-uri
}

secret_data_key_is_nonempty() {
    local secret_name="$1"
    local key_name="$2"

    kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" get secret "$secret_name" -o json |
        jq -e --arg key_name "$key_name" \
            '.data[$key_name] | type == "string" and length > 0' >/dev/null
}

inspect_application_secret_state() {
    local secret_name
    local existing_count=0
    local existing_names=""

    for secret_name in "$DB_AUTH_SECRET" "$AUTH_SECRET" "$CONSOLE_SECRET" "$SIGNING_SECRET"; do
        if kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" get secret "$secret_name" >/dev/null 2>&1; then
            existing_count=$((existing_count + 1))
            existing_names="${existing_names}${existing_names:+, }${secret_name}"
        fi
    done

    case "$existing_count" in
        0)
            APPLICATION_SECRET_STATE="none"
            ;;
        4)
            validate_application_secrets_without_ai_agent
            secret_data_key_is_nonempty "$AUTH_SECRET" bff-client-secret || BFF_CLIENT_SECRET_MISSING=true
            secret_data_key_is_nonempty "$AUTH_SECRET" bff-redirect-uri || BFF_REDIRECT_MISSING=true
            if secret_data_key_is_nonempty "$AUTH_SECRET" ai-agent-client-secret; then
                APPLICATION_SECRET_STATE="complete"
                require_secret_keys "$AUTH_SECRET" ai-agent-client-secret
            else
                APPLICATION_SECRET_STATE="ai-agent-client-secret-missing"
            fi
            ;;
        *)
            printf 'Existing CloudBank Secret subset: %s\n' "$existing_names" >&2
            die "CloudBank application Secrets are only partially provisioned; reconcile them before deployment"
            ;;
    esac

    if [[ "$DEPLOY_MODE" == "redeploy" && "$APPLICATION_SECRET_STATE" == "none" ]]; then
        die "redeploy requires the existing CloudBank application Secrets"
    fi
}

env_count() {
    local variable_name="$1"
    awk -F= -v variable_name="$variable_name" \
        '$1 == variable_name { count++ } END { print count + 0 }' "$ENV_FILE"
}

env_value() {
    local variable_name="$1"
    awk -F= -v variable_name="$variable_name" \
        '$1 == variable_name { print substr($0, index($0, "=") + 1) }' "$ENV_FILE" | tail -n 1
}

write_required_env_file() {
    local variable_name="$1"
    local output_file="$2"
    local value

    [[ "$(env_count "$variable_name")" -eq 1 ]] ||
        die "$ENV_FILE must contain exactly one $variable_name entry"
    value="$(env_value "$variable_name")"
    [[ -n "$value" ]] || die "$ENV_FILE variable $variable_name must not be empty"
    printf '%s' "$value" >"$output_file"
    unset value
}

write_optional_env_file() {
    local variable_name="$1"
    local default_value="$2"
    local output_file="$3"
    local value="$default_value"
    local configured_value

    if [[ -f "$ENV_FILE" && "$(env_count "$variable_name")" -eq 1 ]]; then
        configured_value="$(env_value "$variable_name")"
        if [[ -n "$configured_value" ]]; then
            value="$configured_value"
        fi
    fi
    printf '%s' "$value" >"$output_file"
    unset value configured_value
}

bff_redirect_uri() {
    local redirect_uri="http://127.0.0.1:5173/bff/auth/callback"
    local configured_uri
    local variable_name
    local first_configured_uri=""

    for variable_name in BFF_CALLBACK_URI AZN_AUTHORIZATION_SERVER_BFF_CLIENT_REDIRECT_URI; do
        if [[ "$(env_count "$variable_name")" -gt 1 ]]; then
            die "$ENV_FILE contains duplicate $variable_name entries"
        fi
        if [[ "$(env_count "$variable_name")" -eq 1 ]]; then
            configured_uri="$(env_value "$variable_name")"
            if [[ -n "$configured_uri" ]]; then
                if [[ -n "$first_configured_uri" && "$configured_uri" != "$first_configured_uri" ]]; then
                    die "BFF_CALLBACK_URI and AZN_AUTHORIZATION_SERVER_BFF_CLIENT_REDIRECT_URI must match"
                fi
                first_configured_uri="$configured_uri"
                redirect_uri="$configured_uri"
            fi
        fi
    done
    [[ "$redirect_uri" == https://* || "$redirect_uri" == http://127.0.0.1:* ]] ||
        die "BFF callback must use HTTPS or the local 127.0.0.1 test origin"
    [[ "$redirect_uri" == */bff/auth/callback && "$redirect_uri" != *','* && "$redirect_uri" != *$'\n'* &&
        "$redirect_uri" != *$'\r'* ]] || die "invalid BFF callback URI"
    printf '%s' "$redirect_uri"
}

write_bff_client_secret_file() {
    local output_file="$1"
    local configured_secret
    local generated_secret

    [[ "$(env_count AZN_AUTHORIZATION_SERVER_BFF_CLIENT_SECRET)" -le 1 ]] ||
        die "$ENV_FILE contains duplicate AZN_AUTHORIZATION_SERVER_BFF_CLIENT_SECRET entries"
    if [[ "$(env_count AZN_AUTHORIZATION_SERVER_BFF_CLIENT_SECRET)" -eq 1 ]]; then
        configured_secret="$(env_value AZN_AUTHORIZATION_SERVER_BFF_CLIENT_SECRET)"
        [[ -n "$configured_secret" && "$configured_secret" != *$'\n'* &&
            "$configured_secret" != *$'\r'* ]] || die "invalid BFF OAuth client secret in .env"
        printf '%s' "$configured_secret" >"$output_file"
        unset configured_secret
    else
        generated_secret="$(openssl rand -hex 32)" || die "could not generate the BFF OAuth client secret"
        [[ "$generated_secret" =~ ^[a-f0-9]{64}$ ]] || die "generated BFF OAuth client secret has an unexpected format"
        printf '%s' "$generated_secret" >"$output_file"
        unset generated_secret
    fi
}

provision_missing_bff_client_config() {
    local secret_dir="$WORK_DIR/bff-client-config"
    local patch_file="$secret_dir/patch.json"
    local secret_files=()

    [[ "$BFF_CLIENT_SECRET_MISSING" == true || "$BFF_REDIRECT_MISSING" == true ]] || return 0
    umask 077
    mkdir -p "$secret_dir"
    chmod 700 "$secret_dir"
    if [[ "$BFF_CLIENT_SECRET_MISSING" == true ]]; then
        write_bff_client_secret_file "$secret_dir/client-secret"
        secret_files+=(--from-file=bff-client-secret="$secret_dir/client-secret")
    fi
    if [[ "$BFF_REDIRECT_MISSING" == true ]]; then
        bff_redirect_uri >"$secret_dir/redirect-uri"
        secret_files+=(--from-file=bff-redirect-uri="$secret_dir/redirect-uri")
    fi
    kubectl create secret generic "$AUTH_SECRET" "${secret_files[@]}" --dry-run=client -o json |
        jq '{data: .data}' >"$patch_file"
    chmod 600 "$patch_file"
    kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" patch secret "$AUTH_SECRET" \
        --type merge --patch-file "$patch_file" >/dev/null ||
        die "could not add the missing BFF OAuth client keys to Secret '$AUTH_SECRET'"
    BFF_CLIENT_SECRET_MISSING=false
    BFF_REDIRECT_MISSING=false
    info "Added the missing BFF OAuth client keys to Secret '$AUTH_SECRET' without displaying their values."
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
        die "$variable_name does not meet the Autonomous Database password complexity rules"
    if printf '%s' "$value" | grep -Fqi "$database_username"; then
        die "$variable_name must not contain the database username"
    fi
}

validate_first_deploy_local_material() {
    local variable_name
    local owner_password
    local runtime_password
    local derived_public
    local configured_public

    [[ "$DEPLOY_MODE" == "first-deploy" && "$APPLICATION_SECRET_STATE" == "none" ]] ||
        return 0

    [[ -f "$ENV_FILE" && -f "$SIGNING_PRIVATE_KEY" && -f "$SIGNING_PUBLIC_KEY" ]] ||
        die "first-deploy requires './run-compose.sh init --schema-profile runtime' before the dry run"

    for variable_name in \
        AZN_USER_REPO_PASSWORD \
        AZN_USER_REPO_OWNER_PASSWORD \
        AZN_BOOTSTRAP_USERS_ADMIN_PASSWORD \
        AZN_BOOTSTRAP_USERS_USER_PASSWORD \
        AZN_AUTHORIZATION_SERVER_DEFAULT_CLIENT_SECRET \
        AZN_AUTHORIZATION_SERVER_SERVICE_CLIENT_SECRET \
        AZN_AUTHORIZATION_SERVER_DOCUMENT_INGEST_CLIENT_SECRET \
        AZN_AUTHORIZATION_SERVER_DOCUMENT_REVIEW_CLIENT_SECRET \
        AZN_AUTHORIZATION_SERVER_MICROTX_CLIENT_SECRET \
        AZN_AUTHORIZATION_SERVER_MICROTX_CONSOLE_CLIENT_SECRET; do
        [[ "$(env_count "$variable_name")" -eq 1 && -n "$(env_value "$variable_name")" ]] ||
            die "$ENV_FILE must contain exactly one non-empty $variable_name entry; rerun run-compose init"
    done

    owner_password="$(env_value AZN_USER_REPO_OWNER_PASSWORD)"
    runtime_password="$(env_value AZN_USER_REPO_PASSWORD)"
    validate_adb_password AZN_USER_REPO_OWNER_PASSWORD "$owner_password" USER_REPO
    validate_adb_password AZN_USER_REPO_PASSWORD "$runtime_password" USER_REPO_APP
    [[ "$owner_password" != "$runtime_password" ]] ||
        die "AZN_USER_REPO_OWNER_PASSWORD and AZN_USER_REPO_PASSWORD must differ"
    unset owner_password runtime_password

    openssl rsa -in "$SIGNING_PRIVATE_KEY" -check -noout >/dev/null 2>&1 ||
        die "the persistent private signing key is invalid"
    derived_public="$(openssl pkey -in "$SIGNING_PRIVATE_KEY" -pubout 2>/dev/null)"
    configured_public="$(openssl pkey -pubin -in "$SIGNING_PUBLIC_KEY" -pubout 2>/dev/null)" ||
        die "the persistent public signing key is invalid"
    [[ "$derived_public" == "$configured_public" ]] ||
        die "the persistent signing-key files do not form a pair"
    unset derived_public configured_public
}

rollback_created_secrets() {
    local secret_name

    for secret_name in "${CREATED_SECRETS[@]}"; do
        kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" delete secret "$secret_name" \
            --ignore-not-found >/dev/null || true
    done
}

create_application_secret() {
    local secret_name="$1"
    shift

    if kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" create secret generic \
        "$secret_name" "$@"; then
        CREATED_SECRETS+=("$secret_name")
    else
        rollback_created_secrets
        die "failed to create CloudBank application Secrets; newly created Secrets were rolled back"
    fi
}

generate_ai_agent_client_secret_file() {
    local output_file="$1"
    local generated_secret

    generated_secret="$(openssl rand -hex 32)" ||
        die "could not generate the AI-agent OAuth client secret"
    [[ "$generated_secret" =~ ^[a-f0-9]{64}$ ]] ||
        die "generated AI-agent OAuth client secret has an unexpected format"
    printf '%s' "$generated_secret" >"$output_file"
    unset generated_secret
}

provision_missing_ai_agent_client_secret() {
    local secret_dir="$WORK_DIR/ai-agent-client-secret"
    local patch_file="$secret_dir/patch.json"

    [[ "$APPLICATION_SECRET_STATE" == "ai-agent-client-secret-missing" ]] || return 0

    umask 077
    mkdir -p "$secret_dir"
    chmod 700 "$secret_dir"
    generate_ai_agent_client_secret_file "$secret_dir/value"
    kubectl create secret generic "$AUTH_SECRET" \
        --from-file=ai-agent-client-secret="$secret_dir/value" \
        --dry-run=client -o json |
        jq '{data: {"ai-agent-client-secret": .data["ai-agent-client-secret"]}}' >"$patch_file"
    chmod 600 "$patch_file"
    kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" patch secret "$AUTH_SECRET" \
        --type merge --patch-file "$patch_file" >/dev/null ||
        die "could not add the generated AI-agent OAuth client key to Secret '$AUTH_SECRET'"

    APPLICATION_SECRET_STATE="complete"
    validate_application_secrets
    info "Generated and added the missing AI-agent OAuth client key to Secret '$AUTH_SECRET' without displaying it."
}

create_first_deploy_secrets() {
    local secret_dir="$WORK_DIR/secrets"
    local database_service

    [[ "$APPLICATION_SECRET_STATE" == "none" ]] || return 0

    database_service="$(kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" \
        get secret "$DB_PRIV_SECRET" \
        -o go-template='{{index .data "service" | base64decode}}')"
    [[ "$database_service" =~ ^[A-Za-z0-9._-]+$ ]] ||
        die "the OBaaS privileged database Secret contains an invalid service alias"

    umask 077
    mkdir -p "$secret_dir"
    chmod 700 "$secret_dir"
    printf '%s' 'USER_REPO_APP' >"$secret_dir/username"
    printf '%s' "$database_service" >"$secret_dir/database-service"
    openssl rand -hex 16 >"$secret_dir/key-id"

    write_required_env_file AZN_USER_REPO_PASSWORD "$secret_dir/runtime-password"
    write_required_env_file AZN_USER_REPO_OWNER_PASSWORD "$secret_dir/user-repo-owner-password"
    write_required_env_file AZN_BOOTSTRAP_USERS_ADMIN_PASSWORD "$secret_dir/admin-password"
    write_required_env_file AZN_BOOTSTRAP_USERS_USER_PASSWORD "$secret_dir/user-password"
    write_required_env_file AZN_AUTHORIZATION_SERVER_DEFAULT_CLIENT_SECRET "$secret_dir/default-client-secret"
    write_required_env_file AZN_AUTHORIZATION_SERVER_SERVICE_CLIENT_SECRET "$secret_dir/service-client-secret"
    write_required_env_file AZN_AUTHORIZATION_SERVER_DOCUMENT_INGEST_CLIENT_SECRET "$secret_dir/document-ingest-client-secret"
    write_required_env_file AZN_AUTHORIZATION_SERVER_DOCUMENT_REVIEW_CLIENT_SECRET "$secret_dir/document-review-client-secret"
    generate_ai_agent_client_secret_file "$secret_dir/ai-agent-client-secret"
    write_bff_client_secret_file "$secret_dir/bff-client-secret"
    bff_redirect_uri >"$secret_dir/bff-redirect-uri"
    write_required_env_file AZN_AUTHORIZATION_SERVER_MICROTX_CLIENT_SECRET "$secret_dir/microtx-client-secret"
    write_required_env_file AZN_AUTHORIZATION_SERVER_MICROTX_CONSOLE_CLIENT_SECRET "$secret_dir/console-client-secret"
    write_optional_env_file AZN_AUTHORIZATION_SERVER_MICROTX_CONSOLE_CLIENT_ID \
        microtx-console-client "$secret_dir/console-client-id"
    write_optional_env_file AZN_AUTHORIZATION_SERVER_MICROTX_CONSOLE_CLIENT_SCOPES \
        openid,cloudbank.read,cloudbank.write "$secret_dir/console-scopes"
    write_optional_env_file AZN_AUTHORIZATION_SERVER_MICROTX_CONSOLE_CLIENT_REDIRECT_URI \
        http://localhost/console/oidc/redirect "$secret_dir/console-redirect-uri"
    write_optional_env_file AZN_AUTHORIZATION_SERVER_MICROTX_CONSOLE_CLIENT_POST_LOGOUT_REDIRECT_URI \
        http://localhost/consoleui/index.html "$secret_dir/console-post-logout-redirect-uri"

    CREATED_SECRETS=()
    create_application_secret "$DB_AUTH_SECRET" \
        --from-file=username="$secret_dir/username" \
        --from-file=password="$secret_dir/runtime-password" \
        --from-file=service="$secret_dir/database-service"
    create_application_secret "$AUTH_SECRET" \
        --from-file=user-repo-owner-password="$secret_dir/user-repo-owner-password" \
        --from-file=admin-password="$secret_dir/admin-password" \
        --from-file=user-password="$secret_dir/user-password" \
        --from-file=default-client-secret="$secret_dir/default-client-secret" \
        --from-file=service-client-secret="$secret_dir/service-client-secret" \
        --from-file=document-ingest-client-secret="$secret_dir/document-ingest-client-secret" \
        --from-file=document-review-client-secret="$secret_dir/document-review-client-secret" \
        --from-file=ai-agent-client-secret="$secret_dir/ai-agent-client-secret" \
        --from-file=bff-client-secret="$secret_dir/bff-client-secret" \
        --from-file=bff-redirect-uri="$secret_dir/bff-redirect-uri" \
        --from-file=microtx-client-secret="$secret_dir/microtx-client-secret"
    create_application_secret "$CONSOLE_SECRET" \
        --from-file=client-id="$secret_dir/console-client-id" \
        --from-file=client-secret="$secret_dir/console-client-secret" \
        --from-file=scopes="$secret_dir/console-scopes" \
        --from-file=redirect-uri="$secret_dir/console-redirect-uri" \
        --from-file=post-logout-redirect-uri="$secret_dir/console-post-logout-redirect-uri"
    create_application_secret "$SIGNING_SECRET" \
        --from-file=private.pem="$SIGNING_PRIVATE_KEY" \
        --from-file=public.pem="$SIGNING_PUBLIC_KEY" \
        --from-file=key-id="$secret_dir/key-id"

    APPLICATION_SECRET_STATE="complete"
    validate_application_secrets
    unset database_service
    info "Created the CloudBank application Secrets for the first deployment."
}

validate_issuer_transition() {
    local live_issuer
    [[ "$DEPLOY_MODE" == redeploy ]] || return 0
    live_issuer="$(kubectl --context "$KUBECTL_CONTEXT" --namespace "$NAMESPACE" \
        get deployment azn-server \
        -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="AZN_ISSUER_URI")].value}')"
    [[ "$live_issuer" == "$AZN_ISSUER_URI" ]] ||
        die "refusing to change the JWT issuer during redeploy; an issuer migration requires coordinated changes to BFF and service validators"
}

build_helm_overrides() {
    HELM_OVERRIDES=(
        --set-string "image.repository=$IMAGE_REPOSITORY"
        --set-string "image.tag=$IMAGE_TAG"
        --set-string "obaas.releaseName=$OBAAS_RELEASE"
        --set-string "database.authN.secretName=$DB_AUTH_SECRET"
        --set-string "database.walletSecret=$WALLET_SECRET"
        --set-string "env[1].value=$AZN_ISSUER_URI"
        --set-string "env[4].valueFrom.secretKeyRef.name=$DB_AUTH_SECRET"
        --set-string "env[6].valueFrom.secretKeyRef.name=$DB_PRIV_SECRET"
        --set-string "env[7].valueFrom.secretKeyRef.name=$DB_PRIV_SECRET"
    )
    if [[ -n "$IMAGE_PULL_SECRET" ]]; then
        HELM_OVERRIDES+=(--set-string "imagePullSecrets[0].name=$IMAGE_PULL_SECRET")
    fi
}

render_and_lint() {
    local rendered_manifest="$WORK_DIR/azn-server-rendered.yaml"

    helm lint "$RESOLVED_CHART" \
        --namespace "$NAMESPACE" \
        --values "$VALUES_FILE" \
        "${HELM_OVERRIDES[@]}" >/dev/null

    helm template "$RELEASE_NAME" "$RESOLVED_CHART" \
        --namespace "$NAMESPACE" \
        --values "$VALUES_FILE" \
        "${HELM_OVERRIDES[@]}" >"$rendered_manifest"

    if grep -q '^kind:[[:space:]]*Job[[:space:]]*$' "$rendered_manifest"; then
        die "rendered chart contains a database-init Job; azn-server Liquibase must own schema provisioning"
    fi
    if grep -q '^kind:[[:space:]]*Ingress[[:space:]]*$' "$rendered_manifest"; then
        die "rendered chart exposes an Ingress; azn-server must remain internal at this stage"
    fi
}

show_configuration() {
    local pull_secret_display="<none; repository must be public>"

    if [[ -n "$IMAGE_PULL_SECRET" ]]; then
        pull_secret_display="$IMAGE_PULL_SECRET"
    fi
    cat <<EOF

Deployment target
  mode:             $DEPLOY_MODE
  kubectl context:  $KUBECTL_CONTEXT
  OCI region:       $OCI_REGION
  namespace:        $NAMESPACE
  OBaaS release:    $OBAAS_RELEASE ($OBAAS_VERSION)
  JWT issuer:       $AZN_ISSUER_URI
  Helm release:     $RELEASE_NAME
  image:            $IMAGE_REPOSITORY:$IMAGE_TAG
  current image:    ${CURRENT_IMAGE:-<not installed>}
  image pull Secret: $pull_secret_display
  DB runtime Secret: $DB_AUTH_SECRET
  DB privileged:     $DB_PRIV_SECRET
  DB wallet:         $WALLET_SECRET
  application Secrets: $APPLICATION_SECRET_STATE
  Helm conflict mode: ${HELM_UPGRADE_CONFLICT_ARGS[*]:-standard}
  dry run:           $DRY_RUN
EOF
}

confirm_deployment() {
    local answer

    if [[ "$DRY_RUN" == true || "$ASSUME_YES" == true ]]; then
        return 0
    fi
    printf '\nRun %s for azn-server on this target? [y/N] ' "$DEPLOY_MODE"
    read -r answer
    [[ "$answer" == "y" || "$answer" == "Y" ]] || {
        info "Deployment cancelled."
        exit 0
    }
}

deploy() {
    if [[ "$DEPLOY_MODE" == "first-deploy" ]]; then
        helm upgrade --install "$RELEASE_NAME" "$RESOLVED_CHART" \
            --kube-context "$KUBECTL_CONTEXT" \
            --namespace "$NAMESPACE" \
            --reset-values \
            --values "$VALUES_FILE" \
            "${HELM_OVERRIDES[@]}" \
            ${HELM_UPGRADE_CONFLICT_ARGS[@]+"${HELM_UPGRADE_CONFLICT_ARGS[@]}"} \
            --wait \
            --timeout "$TIMEOUT"
    else
        helm upgrade "$RELEASE_NAME" "$RESOLVED_CHART" \
            --kube-context "$KUBECTL_CONTEXT" \
            --namespace "$NAMESPACE" \
            --reset-values \
            --values "$VALUES_FILE" \
            "${HELM_OVERRIDES[@]}" \
            ${HELM_UPGRADE_CONFLICT_ARGS[@]+"${HELM_UPGRADE_CONFLICT_ARGS[@]}"} \
            --wait \
            --timeout "$TIMEOUT"
    fi

    kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" rollout status \
        deployment/azn-server --timeout="$TIMEOUT"
    kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" get deployment azn-server \
        -o custom-columns=NAME:.metadata.name,READY:.status.readyReplicas,IMAGE:.spec.template.spec.containers[0].image
    kubectl --context "$KUBECTL_CONTEXT" -n "$NAMESPACE" get endpointslice \
        -l kubernetes.io/service-name=azn-server \
        -o custom-columns=NAME:.metadata.name,ENDPOINTS:.endpoints[*].addresses[*]
}

cleanup() {
    if [[ -n "${WORK_DIR:-}" && -d "$WORK_DIR" ]]; then
        rm -rf -- "$WORK_DIR"
    fi
}

main() {
    parse_args "$@"
    require_commands
    load_deployment_configuration
    validate_inputs

    WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cloudbank-azn-deploy.XXXXXX")"
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' HUP TERM

    detect_obaas_release
    validate_deploy_state
    validate_issuer_transition
    configure_helm_upgrade_conflict_handling
    resolve_app_chart
    resolve_image_repository
    resolve_platform_secrets
    validate_platform_secrets
    inspect_application_secret_state
    validate_first_deploy_local_material
    build_helm_overrides
    render_and_lint
    show_configuration

    if [[ "$DRY_RUN" == true ]]; then
        info ""
        if [[ "$DEPLOY_MODE" == "first-deploy" && "$APPLICATION_SECRET_STATE" == "none" ]]; then
            info "First deployment will create the four CloudBank application Secrets."
        fi
        if [[ "$APPLICATION_SECRET_STATE" == "ai-agent-client-secret-missing" ]]; then
            info "Deployment will generate and add the missing AI-agent OAuth client key to '$AUTH_SECRET'."
        fi
        if [[ "$BFF_CLIENT_SECRET_MISSING" == true || "$BFF_REDIRECT_MISSING" == true ]]; then
            info "Deployment will add the missing BFF OAuth client keys to '$AUTH_SECRET'."
        fi
        info "Dry run completed: chart lint and render checks passed; no cluster resources were changed."
        exit 0
    fi

    confirm_deployment
    if [[ "$DEPLOY_MODE" == "first-deploy" ]]; then
        create_first_deploy_secrets
    fi
    provision_missing_bff_client_config
    provision_missing_ai_agent_client_secret
    validate_application_secrets
    deploy
    info ""
    info "azn-server deployed successfully. It remains a ClusterIP service with issuer:"
    info "  $AZN_ISSUER_URI"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
