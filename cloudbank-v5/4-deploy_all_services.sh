#!/bin/bash
# Copyright (c) 2024, 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at http://oss.oracle.com/licenses/upl.

# CloudBank v5 Deploy All Services Script
# Deploys all CloudBank microservices using the shared obaas-sample-app Helm chart.
#
# Usage:
#   ./4-deploy_all_services.sh [options]
#
# Options:
#   -n, --namespace NAMESPACE    Kubernetes namespace (required)
#   -o, --obaas-release RELEASE  OBaaS platform release name (auto-detected if not provided)
#   -d, --db-name DB_NAME        Database name (required)
#   -s, --priv-secret SECRET     Privileged secret name (default: {dbname}-db-priv-authn)
#   -r, --registry REGISTRY      Full container registry path (auto-detected from OCI CLI if not provided)
#   -p, --prefix PREFIX          Repository prefix for OCIR auto-detection (default: cloudbank-v5)
#   -t, --tag TAG                Image tag (default: 0.0.1-SNAPSHOT)
#   --image-pull-secret SECRET   Kubernetes image pull secret for private registries
#                                (fallback: CLOUDBANK_IMAGE_PULL_SECRET)
#   -y, --yes                    Do not prompt before deployment
#   --app-chart CHART            obaas-sample-app chart path/name (default: local repo chart if present)
#   --dry-run                    Show what would be deployed without deploying
#   -h, --help                   Show this help message
#
# Prerequisites:
#   - kubectl connected to cluster
#   - Helm installed
#   - OBaaS platform installed in the namespace
#   - Database secrets created (see 3-k8s_db_secrets.sh)
#   - Container images pushed to registry (see 2-images_build_push.sh)
#
# Example:
#   ./4-deploy_all_services.sh -n obaas-dev -d mydb
#   ./4-deploy_all_services.sh -n obaas-dev -d mydb -s my-custom-secret
#   ./4-deploy_all_services.sh -n obaas-dev -d mydb -r docker.io/myuser/cloudbank
#   ./4-deploy_all_services.sh -n obaas-dev -d mydb -r sjc.ocir.io/mytenancy/cloudbank-v5 --image-pull-secret ocir-pull-secret

set -e

# =============================================================================
# Script Directory and Prerequisites Library
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the prerequisites check library
# shellcheck source=check_prereqs.sh
source "${SCRIPT_DIR}/check_prereqs.sh"

# =============================================================================
# Variables
# =============================================================================
NAMESPACE=""
OBAAS_RELEASE=""
DB_NAME=""
PRIV_SECRET=""
REGISTRY=""
REPO_PREFIX="cloudbank-v5"
IMAGE_TAG="0.0.1-SNAPSHOT"
DRY_RUN=false
ASSUME_YES=false
APP_CHART=""
IMAGE_PULL_SECRET="${CLOUDBANK_IMAGE_PULL_SECRET:-}"
DEFAULT_APP_CHART_PATH="$(cd "${SCRIPT_DIR}/.." && pwd)/helm/app-charts/obaas-sample-app"
ROLLOUT_ID=""

# Services to deploy
SERVICE_LIST=(
    "azn-server"
    "account"
    "customer"
    "creditscore"
    "transfer"
    "checks"
    "testrunner"
)

# =============================================================================
# Parse Arguments
# =============================================================================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            -o|--obaas-release)
                OBAAS_RELEASE="$2"
                shift 2
                ;;
            -d|--db-name)
                DB_NAME="$2"
                shift 2
                ;;
            -s|--priv-secret)
                PRIV_SECRET="$2"
                shift 2
                ;;
            -r|--registry)
                REGISTRY="$2"
                shift 2
                ;;
            -p|--prefix)
                REPO_PREFIX="$2"
                shift 2
                ;;
            -t|--tag)
                IMAGE_TAG="$2"
                shift 2
                ;;
            --image-pull-secret)
                IMAGE_PULL_SECRET="$2"
                shift 2
                ;;
            -y|--yes)
                ASSUME_YES=true
                shift
                ;;
            --app-chart)
                APP_CHART="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

show_help() {
    cat << 'EOF'
CloudBank v5 Deploy All Services Script

Deploys all CloudBank microservices using the shared obaas-sample-app Helm chart.

Usage:
  ./4-deploy_all_services.sh [options]

Options:
  -n, --namespace NAMESPACE    Kubernetes namespace (required)
  -o, --obaas-release RELEASE  OBaaS platform release name (auto-detected if not provided)
  -d, --db-name DB_NAME        Database name (required)
  -s, --priv-secret SECRET     Privileged secret name (default: {dbname}-db-priv-authn)
  -r, --registry REGISTRY      Full container registry path (auto-detected from OCI CLI if not provided)
  -p, --prefix PREFIX          Repository prefix for OCIR auto-detection (default: cloudbank-v5)
  -t, --tag TAG                Image tag (default: 0.0.1-SNAPSHOT)
  --image-pull-secret SECRET   Kubernetes image pull secret for private registries
                               If omitted, CLOUDBANK_IMAGE_PULL_SECRET is used when set
  -y, --yes                    Do not prompt before deployment
  --app-chart CHART            obaas-sample-app chart path/name
                               (default: local repo chart if present, otherwise obaas/obaas-sample-app)
  --dry-run                    Show what would be deployed without deploying
  -h, --help                   Show this help message

Prerequisites:
  - kubectl connected to cluster
  - Helm installed
  - OBaaS platform installed in the namespace
  - Database secrets created (see 3-k8s_db_secrets.sh)
  - Container images pushed to registry (see 2-images_build_push.sh)

Services deployed:
  azn-server, account, customer, creditscore, transfer, checks, testrunner

Example:
  ./4-deploy_all_services.sh -n obaas-dev -d mydb
  ./4-deploy_all_services.sh -n obaas-dev -d mydb -o obaas
  ./4-deploy_all_services.sh -n obaas-dev -d mydb -s my-custom-secret
  ./4-deploy_all_services.sh -n obaas-dev -d mydb -r docker.io/myuser/cloudbank
  ./4-deploy_all_services.sh -n obaas-dev -d mydb -r sjc.ocir.io/mytenancy/cloudbank-v5 --image-pull-secret ocir-pull-secret
  ./4-deploy_all_services.sh -n obaas-dev -d mydb --dry-run
  ./4-deploy_all_services.sh -n obaas-dev -d mydb --yes

Create a pull secret for private registries:
  kubectl -n <namespace> create secret docker-registry <secret-name> \
    --docker-server=<registry-host> \
    --docker-username=<username> \
    --docker-password=<password>
EOF
}

# =============================================================================
# Prompt for Input
# =============================================================================
prompt_value() {
    local var_name="$1"
    local prompt="$2"
    local example="$3"
    local current_value="${!var_name}"

    if [[ -n "$current_value" ]]; then
        return 0
    fi

    local full_prompt="$prompt"
    if [[ -n "$example" ]]; then
        full_prompt="$prompt (e.g., $example)"
    fi

    while true; do
        read -p "$full_prompt: " value
        if [[ -n "$value" ]]; then
            printf -v "$var_name" '%s' "$value"
            return 0
        else
            print_error "Value is required. Please enter a value."
        fi
    done
}

# =============================================================================
# Validation
# =============================================================================
check_prerequisites() {
    print_step "Checking prerequisites..."

    local errors=0

    # Check kubectl and cluster connection
    if ! prereq_check_kubectl; then
        ((++errors))
    fi

    # Check helm
    if ! prereq_check_helm; then
        ((++errors))
    fi

    # Check namespace exists
    if ! prereq_check_namespace "$NAMESPACE"; then
        ((++errors))
    fi

    # Check helm chart exists
    if [[ -d "$APP_CHART" || -f "$APP_CHART/Chart.yaml" ]]; then
        print_success "Helm chart found: $APP_CHART"
    elif [[ "$APP_CHART" == "obaas/obaas-sample-app" ]]; then
        if ! prereq_check_helm_chart; then
            ((++errors))
        fi
    else
        print_error "Helm chart not found: $APP_CHART"
        ((++errors))
    fi

    if [[ $errors -gt 0 ]]; then
        return 1
    fi

    return 0
}

is_local_registry() {
    local registry="$1"
    [[ "$registry" == localhost/* || "$registry" == localhost:* ]]
}

validate_image_pull_secret() {
    local final_registry="$1"

    if [[ -n "$IMAGE_PULL_SECRET" ]]; then
        print_step "Checking image pull secret..."
        if kubectl get secret "$IMAGE_PULL_SECRET" -n "$NAMESPACE" &> /dev/null; then
            print_success "Image pull secret '$IMAGE_PULL_SECRET' exists in namespace '$NAMESPACE'"
        else
            print_error "Image pull secret '$IMAGE_PULL_SECRET' was not found in namespace '$NAMESPACE'"
            print_info "Create it with:"
            print_info "  kubectl -n $NAMESPACE create secret docker-registry $IMAGE_PULL_SECRET \\"
            print_info "    --docker-server=$(echo "$final_registry" | cut -d'/' -f1) \\"
            print_info "    --docker-username=<username> \\"
            print_info "    --docker-password=<password>"
            return 1
        fi
    elif ! is_local_registry "$final_registry"; then
        print_warning "No image pull secret configured."
        print_info "This is OK for public registries, but private registries may fail with ImagePullBackOff."
        print_info "Use --image-pull-secret <secret-name> if your registry requires authentication."
        if [[ "$DRY_RUN" == true ]]; then
            print_info "Continuing dry-run so the planned deployment commands can be reviewed."
        elif [[ "$ASSUME_YES" == true ]]; then
            print_warning "Continuing because --yes was specified."
        else
            echo ""
            read -p "Continue without an image pull secret? [y/N]: " confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                echo "Deployment cancelled."
                exit 0
            fi
        fi
    fi
}

# =============================================================================
# Deployment
# =============================================================================
get_db_user_for_service() {
    local service_name="$1"
    # Map services to their database user (matches 3-k8s_db_secrets.sh SERVICE_ACCOUNTS)
    case "$service_name" in
        azn-server)
            echo "azn-server"
            ;;
        account|checks|testrunner)
            echo "account"
            ;;
        customer)
            echo "customer"
            ;;
        transfer)
            echo "transfer"
            ;;
        creditscore)
            echo "creditscore"
            ;;
        *)
            echo "$service_name"
            ;;
    esac
}

deploy_service() {
    local service_name="$1"
    local final_registry="$2"
    local is_last_service="$3"

    local values_file_path="${SCRIPT_DIR}/${service_name}/values.yaml"

    if [[ ! -f "$values_file_path" ]]; then
        print_warning "Values file not found: $values_file_path (skipping)"
        return 0
    fi

    # Build image repository path
    local image_repository="${final_registry}/${service_name}"

    # Determine the database user/secret for this service
    local db_user
    db_user=$(get_db_user_for_service "$service_name")
    local db_secret_name="${DB_NAME}-${db_user}-db-authn"

    # Build helm command
    local helm_command="helm upgrade --install $service_name $APP_CHART --reset-values"
    helm_command+=" -f $values_file_path"
    helm_command+=" --namespace $NAMESPACE"
    helm_command+=" --set image.repository=$image_repository"
    helm_command+=" --set image.tag=$IMAGE_TAG"
    if [[ -n "$IMAGE_PULL_SECRET" ]]; then
        helm_command+=" --set imagePullSecrets[0].name=$IMAGE_PULL_SECRET"
    fi
    if is_local_registry "$final_registry"; then
        helm_command+=" --set image.pullPolicy=Never"
    fi
    helm_command+=" --set obaas.releaseName=$OBAAS_RELEASE"
    helm_command+=" --set otel.enabled=true"
    helm_command+=" --set otel.micrometer.enabled=true"
    helm_command+=" --set database.name=$DB_NAME"
    helm_command+=" --set database.authN.secretName=$db_secret_name"
    if [[ -n "$PRIV_SECRET" ]]; then
        helm_command+=" --set database.privAuthN.secretName=$PRIV_SECRET"
    fi
    helm_command+=" --set-string podAnnotations.cloudbank-restarted-at=$ROLLOUT_ID"

    if [[ "$service_name" == "azn-server" ]]; then
        local azn_secret_name="${DB_NAME}-azn-server-auth"
        local signing_secret_name="${DB_NAME}-azn-server-signing-key"
        helm_command+=" --set env[0].name=EUREKA_CLIENT_ENABLED"
        helm_command+=" --set-string env[0].value=true"
        helm_command+=" --set env[1].name=AZN_USER_REPO_PASSWORD"
        helm_command+=" --set env[1].valueFrom.secretKeyRef.name=$db_secret_name"
        helm_command+=" --set env[1].valueFrom.secretKeyRef.key=password"
        helm_command+=" --set env[2].name=OBAAS_ADMIN_PASSWORD"
        helm_command+=" --set env[2].valueFrom.secretKeyRef.name=$azn_secret_name"
        helm_command+=" --set env[2].valueFrom.secretKeyRef.key=admin-password"
        helm_command+=" --set env[3].name=OBAAS_USER_PASSWORD"
        helm_command+=" --set env[3].valueFrom.secretKeyRef.name=$azn_secret_name"
        helm_command+=" --set env[3].valueFrom.secretKeyRef.key=user-password"
        helm_command+=" --set env[4].name=AZN_AUTHORIZATION_SERVER_DEFAULT_CLIENT_ENABLED"
        helm_command+=" --set-string env[4].value=true"
        helm_command+=" --set env[5].name=AZN_AUTHORIZATION_SERVER_DEFAULT_CLIENT_ID"
        helm_command+=" --set-string env[5].value=cloudbank-client"
        helm_command+=" --set env[6].name=AZN_AUTHORIZATION_SERVER_DEFAULT_CLIENT_SECRET"
        helm_command+=" --set env[6].valueFrom.secretKeyRef.name=$azn_secret_name"
        helm_command+=" --set env[6].valueFrom.secretKeyRef.key=client-secret"
        helm_command+=" --set env[7].name=AZN_AUTHORIZATION_SERVER_SIGNING_KEY_PRIVATE_KEY_PATH"
        helm_command+=" --set-string env[7].value=/etc/azn-server/signing/private.pem"
        helm_command+=" --set env[8].name=AZN_AUTHORIZATION_SERVER_SIGNING_KEY_PUBLIC_KEY_PATH"
        helm_command+=" --set-string env[8].value=/etc/azn-server/signing/public.pem"
        helm_command+=" --set env[9].name=AZN_AUTHORIZATION_SERVER_SIGNING_KEY_KEY_ID"
        helm_command+=" --set env[9].valueFrom.secretKeyRef.name=$signing_secret_name"
        helm_command+=" --set env[9].valueFrom.secretKeyRef.key=key-id"
        helm_command+=" --set env[10].name=AZN_AUTHORIZATION_SERVER_SERVICE_CLIENT_ID"
        helm_command+=" --set-string env[10].value=cloudbank-service-client"
        helm_command+=" --set env[11].name=AZN_AUTHORIZATION_SERVER_SERVICE_CLIENT_SECRET"
        helm_command+=" --set env[11].valueFrom.secretKeyRef.name=$azn_secret_name"
        helm_command+=" --set env[11].valueFrom.secretKeyRef.key=service-client-secret"
        helm_command+=" --set env[12].name=AZN_AUTHORIZATION_SERVER_TEST_CLIENT_ID"
        helm_command+=" --set-string env[12].value=cloudbank-test-client"
        helm_command+=" --set env[13].name=AZN_AUTHORIZATION_SERVER_TEST_CLIENT_SECRET"
        helm_command+=" --set env[13].valueFrom.secretKeyRef.name=$azn_secret_name"
        helm_command+=" --set env[13].valueFrom.secretKeyRef.key=test-client-secret"
        helm_command+=" --set env[14].name=AZN_AUTHORIZATION_SERVER_ADMIN_CLIENT_ID"
        helm_command+=" --set-string env[14].value=cloudbank-admin-client"
        helm_command+=" --set env[15].name=AZN_AUTHORIZATION_SERVER_ADMIN_CLIENT_SECRET"
        helm_command+=" --set env[15].valueFrom.secretKeyRef.name=$azn_secret_name"
        helm_command+=" --set env[15].valueFrom.secretKeyRef.key=admin-client-secret"
        helm_command+=" --set env[16].name=AZN_BOOTSTRAP_USERS_ADMIN_PASSWORD"
        helm_command+=" --set env[16].valueFrom.secretKeyRef.name=$azn_secret_name"
        helm_command+=" --set env[16].valueFrom.secretKeyRef.key=admin-password"
        helm_command+=" --set env[17].name=AZN_BOOTSTRAP_USERS_USER_PASSWORD"
        helm_command+=" --set env[17].valueFrom.secretKeyRef.name=$azn_secret_name"
        helm_command+=" --set env[17].valueFrom.secretKeyRef.key=user-password"
        helm_command+=" --set env[18].name=AZN_AUTHORIZATION_SERVER_MICROTX_CLIENT_ID"
        helm_command+=" --set-string env[18].value=microtx-workflow-client"
        helm_command+=" --set env[19].name=AZN_AUTHORIZATION_SERVER_MICROTX_CLIENT_SECRET"
        helm_command+=" --set env[19].valueFrom.secretKeyRef.name=$azn_secret_name"
        helm_command+=" --set env[19].valueFrom.secretKeyRef.key=microtx-client-secret"
        helm_command+=" --set env[20].name=AZN_AUTHORIZATION_SERVER_ISSUER"
        helm_command+=" --set-string env[20].value=http://azn-server.${NAMESPACE}.svc.cluster.local:8080"
        helm_command+=" --set env[21].name=SERVER_TOMCAT_ACCESSLOG_ENABLED"
        helm_command+=" --set-string env[21].value=true"
        helm_command+=" --set volumeMounts[0].name=azn-server-signing-key"
        helm_command+=" --set volumeMounts[0].mountPath=/etc/azn-server/signing"
        helm_command+=" --set volumeMounts[0].readOnly=true"
        helm_command+=" --set volumes[0].name=azn-server-signing-key"
        helm_command+=" --set volumes[0].secret.secretName=$signing_secret_name"
        helm_command+=" --set volumes[0].secret.defaultMode=288"
    else
        local azn_secret_name="${DB_NAME}-azn-server-auth"
        local azn_jwk_set_uri="http://azn-server.${NAMESPACE}.svc.cluster.local:8080/oauth2/jwks"
        local azn_token_uri="http://azn-server.${NAMESPACE}.svc.cluster.local:8080/oauth2/token"
        helm_command+=" --set env[0].name=SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_JWK_SET_URI"
        helm_command+=" --set-string env[0].value=$azn_jwk_set_uri"
        helm_command+=" --set env[1].name=CLOUDBANK_SECURITY_REQUIRE_INTERNAL_TOKEN"
        helm_command+=" --set-string env[1].value=true"
        helm_command+=" --set env[2].name=CLOUDBANK_SECURITY_SERVICE_TOKEN_ENABLED"
        helm_command+=" --set-string env[2].value=true"
        helm_command+=" --set env[3].name=CLOUDBANK_SECURITY_SERVICE_TOKEN_URI"
        helm_command+=" --set-string env[3].value=$azn_token_uri"
        helm_command+=" --set env[4].name=CLOUDBANK_SECURITY_SERVICE_TOKEN_CLIENT_ID"
        helm_command+=" --set-string env[4].value=cloudbank-service-client"
        helm_command+=" --set env[5].name=CLOUDBANK_SECURITY_SERVICE_TOKEN_CLIENT_SECRET"
        helm_command+=" --set env[5].valueFrom.secretKeyRef.name=$azn_secret_name"
        helm_command+=" --set env[5].valueFrom.secretKeyRef.key=service-client-secret"
        helm_command+=" --set env[6].name=CLOUDBANK_SECURITY_SERVICE_TOKEN_SCOPE"
        helm_command+=" --set-string env[6].value=cloudbank.internal"
        if [[ "$service_name" == "transfer" ]]; then
            local account_base_url="http://account.${NAMESPACE}.svc.cluster.local:8080"
            local transfer_base_url="http://transfer.${NAMESPACE}.svc.cluster.local:8080"
            helm_command+=" --set env[7].name=ACCOUNT_DEPOSIT_URL"
            helm_command+=" --set-string env[7].value=$account_base_url/deposit"
            helm_command+=" --set env[8].name=ACCOUNT_WITHDRAW_URL"
            helm_command+=" --set-string env[8].value=$account_base_url/withdraw"
            helm_command+=" --set env[9].name=ACCOUNT_LOOKUP_URL"
            helm_command+=" --set-string env[9].value=$account_base_url/api/v1/account"
            helm_command+=" --set env[10].name=TRANSFER_CANCEL_URL"
            helm_command+=" --set-string env[10].value=$transfer_base_url/cancel"
            helm_command+=" --set env[11].name=TRANSFER_CANCEL_PROCESS_URL"
            helm_command+=" --set-string env[11].value=$transfer_base_url/processcancel"
            helm_command+=" --set env[12].name=TRANSFER_CONFIRM_URL"
            helm_command+=" --set-string env[12].value=$transfer_base_url/confirm"
            helm_command+=" --set env[13].name=TRANSFER_CONFIRM_PROCESS_URL"
            helm_command+=" --set-string env[13].value=$transfer_base_url/processconfirm"
        fi
    fi

    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would run: $helm_command"
        return 0
    fi

    print_step "Deploying $service_name..."
    print_info "Image: $image_repository:$IMAGE_TAG"

    # Verify image exists before deploying. Local test registries are loaded
    # directly into Docker/Rancher Desktop rather than pushed to a registry.
    if [[ "$final_registry" == localhost/* || "$final_registry" == localhost:* ]]; then
        if ! docker image inspect "$image_repository:$IMAGE_TAG" &>/dev/null; then
            print_error "Local image not found: $image_repository:$IMAGE_TAG"
            print_info "Build local images first: ./2-images_build_push.sh --skip-push"
            return 1
        fi
    elif ! docker manifest inspect "$image_repository:$IMAGE_TAG" &>/dev/null; then
        print_error "Image not found: $image_repository:$IMAGE_TAG"
        print_info "Build and push images first: ./2-images_build_push.sh"
        return 1
    fi
    print_success "Image verified"

    print_info "Running: $helm_command"

    # Suppress NOTES.txt output unless this is the last service
    if [[ "$is_last_service" == true ]]; then
        if $helm_command; then
            print_success "$service_name deployed successfully"
            return 0
        else
            print_error "Failed to deploy $service_name"
            print_info "Check pod status: kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=$service_name"
            print_info "Check pod logs:   kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=$service_name"
            return 1
        fi
    else
        if $helm_command > /dev/null; then
            print_success "$service_name deployed successfully"
            return 0
        else
            print_error "Failed to deploy $service_name"
            print_info "Check pod status: kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=$service_name"
            print_info "Check pod logs:   kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=$service_name"
            return 1
        fi
    fi
}

deploy_all_services() {
    local final_registry="$1"

    print_header "Deploying Services"

    if [[ "$DRY_RUN" == true ]]; then
        print_warning "DRY RUN MODE - No services will be deployed"
        echo ""
    fi

    local deployed_count=0
    local failed_count=0
    local skipped_count=0
    local total_services=${#SERVICE_LIST[@]}
    local service_index=0

    for service in "${SERVICE_LIST[@]}"; do
        ((++service_index))
        local is_last_service=false
        if [[ $service_index -eq $total_services ]]; then
            is_last_service=true
        fi

        if deploy_service "$service" "$final_registry" "$is_last_service"; then
            if [[ "$DRY_RUN" != true ]]; then
                ((++deployed_count))
            fi
        else
            ((++failed_count))
            # Stop on first failure
            print_error "Stopping deployment due to failure"
            break
        fi
    done

    echo ""
    if [[ "$DRY_RUN" == true ]]; then
        print_info "Dry run complete. No services were deployed."
    else
        print_info "Deployed: $deployed_count | Failed: $failed_count"
    fi

    if [[ $failed_count -gt 0 ]]; then
        return 1
    fi
    return 0
}

# =============================================================================
# Main
# =============================================================================
main() {
    print_header "CloudBank v5 Deploy All Services"

    # Parse command line arguments
    parse_args "$@"
    ROLLOUT_ID="$(date -u +%Y%m%dT%H%M%SZ)"

    if [[ -z "$APP_CHART" ]]; then
        if [[ -f "$DEFAULT_APP_CHART_PATH/Chart.yaml" ]]; then
            APP_CHART="$DEFAULT_APP_CHART_PATH"
        else
            APP_CHART="obaas/obaas-sample-app"
        fi
    fi

    if [[ "$APP_CHART" == "obaas/obaas-sample-app" ]]; then
        print_step "Checking obaas Helm repo..."
        if ! helm repo list | grep -q "^obaas"; then
            print_info "Adding obaas Helm repo..."
            helm repo add obaas https://oracle.github.io/microservices-backend/helm
        else
            print_info "obaas Helm repo already exists, skipping add"
        fi
    fi

    # Prompt for missing required values
    if [[ -z "$NAMESPACE" ]] || [[ -z "$DB_NAME" ]]; then
        echo "Please provide the following configuration values."
        echo ""
        prompt_value NAMESPACE "Kubernetes namespace" "obaas-dev"
        prompt_value DB_NAME "Database name" "mydb"
    fi

    # Check prerequisites
    if ! check_prerequisites; then
        exit 1
    fi

    # Auto-detect OBaaS release if not provided
    if [[ -z "$OBAAS_RELEASE" ]]; then
        print_step "Auto-detecting OBaaS release..."
        if prereq_check_obaas_release "$NAMESPACE"; then
            OBAAS_RELEASE="$PREREQ_OBAAS_RELEASE"
        else
            print_error "Could not auto-detect OBaaS release. Use -o/--obaas-release to specify."
            exit 1
        fi
    fi

    # Determine final registry path
    local final_registry=""

    if [[ -n "$REGISTRY" ]]; then
        # User provided explicit registry - use as-is
        final_registry="$REGISTRY"
    else
        # Try to auto-detect from OCI CLI and add prefix
        print_step "Auto-detecting registry from OCI CLI configuration..."
        if prereq_check_oci 2>/dev/null; then
            final_registry="${PREREQ_OCI_REGISTRY}/${REPO_PREFIX}"
            print_success "Registry: $final_registry"
        else
            # Fall back to prompting
            echo ""
            echo "Could not auto-detect registry from OCI CLI."
            echo "Please provide the container registry path."
            echo ""
            prompt_value REGISTRY "Container registry path" "us-phoenix-1.ocir.io/mytenancy/cloudbank-v5"
            final_registry="$REGISTRY"
        fi
    fi

    # Check database secrets exist
    print_step "Checking database secrets..."
    if ! prereq_check_db_priv_secret "$NAMESPACE" "$DB_NAME" "$PRIV_SECRET"; then
        if [[ "$DRY_RUN" == true ]]; then
            print_info "Continuing dry-run so the planned deployment commands can be reviewed."
        else
            exit 1
        fi
    fi
    if ! prereq_check_db_app_secrets "$NAMESPACE" "$DB_NAME"; then
        print_warning "Some database secrets are missing. Services may fail to start."
        if [[ "$DRY_RUN" == true ]]; then
            print_info "Continuing dry-run so the planned deployment commands can be reviewed."
        elif [[ "$ASSUME_YES" == true ]]; then
            print_warning "Continuing because --yes was specified."
        else
            echo ""
            read -p "Continue anyway? [y/N]: " confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                echo "Deployment cancelled."
                exit 0
            fi
        fi
    fi

    if ! validate_image_pull_secret "$final_registry"; then
        exit 1
    fi

    # Show configuration
    print_header "Configuration"
    echo "  Namespace:     $NAMESPACE"
    echo "  OBaaS Release: $OBAAS_RELEASE"
    echo "  Database:      $DB_NAME"
    echo "  Priv Secret:   ${PRIV_SECRET:-${DB_NAME}-db-priv-authn}"
    echo "  Registry:      $final_registry"
    echo "  Image Tag:     $IMAGE_TAG"
    echo "  Pull Secret:   ${IMAGE_PULL_SECRET:-<none>}"
    echo "  App Chart:     $APP_CHART"
    echo "  Dry Run:       $DRY_RUN"
    echo ""
    echo "  Services:      ${SERVICE_LIST[*]}"
    echo ""

    if [[ "$DRY_RUN" != true && "$ASSUME_YES" != true ]]; then
        read -p "Continue with deployment? [y/N]: " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "Deployment cancelled."
            exit 0
        fi
    fi

    # Deploy all services
    if ! deploy_all_services "$final_registry"; then
        exit 1
    fi

    # Summary
    print_header "Summary"
    if [[ "$DRY_RUN" == true ]]; then
        print_info "Dry run complete. Run without --dry-run to deploy services."
    else
        print_success "All services deployed successfully!"
        echo ""
        echo "Verify with:"
        echo "  kubectl get pods -n $NAMESPACE"
        echo "  kubectl get svc -n $NAMESPACE"
        echo ""
        echo "Next step:"
        echo "  Creates APISIX routes for all CloudBank microservices: ./5-apisix_create_routes.sh -n <namespace>"
    fi
}

# Run main function
main "$@"
