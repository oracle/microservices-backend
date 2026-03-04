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
#   -r, --registry REGISTRY      Full container registry path (auto-detected from OCI CLI if not provided)
#   -p, --prefix PREFIX          Repository prefix for OCIR auto-detection (default: cloudbank-v5)
#   -t, --tag TAG                Image tag (default: 0.0.1-SNAPSHOT)
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
#   ./4-deploy_all_services.sh -n obaas-dev -d mydb -r docker.io/myuser/cloudbank

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
REGISTRY=""
REPO_PREFIX="cloudbank-v5"
IMAGE_TAG="0.0.1-SNAPSHOT"
DRY_RUN=false

# Add Helm repo if not already added
print_step "Checking obaas Helm repo..."
if ! helm repo list | grep -q "^obaas"; then
    print_info "Adding obaas Helm repo..."
    helm repo add obaas https://oracle.github.io/microservices-backend/helm
else
    print_info "obaas Helm repo already exists, skipping add"
fi

# Services to deploy
SERVICE_LIST=(
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
  -r, --registry REGISTRY      Full container registry path (auto-detected from OCI CLI if not provided)
  -p, --prefix PREFIX          Repository prefix for OCIR auto-detection (default: cloudbank-v5)
  -t, --tag TAG                Image tag (default: 0.0.1-SNAPSHOT)
  --dry-run                    Show what would be deployed without deploying
  -h, --help                   Show this help message

Prerequisites:
  - kubectl connected to cluster
  - Helm installed
  - OBaaS platform installed in the namespace
  - Database secrets created (see 3-k8s_db_secrets.sh)
  - Container images pushed to registry (see 2-images_build_push.sh)

Services deployed:
  account, customer, creditscore, transfer, checks, testrunner

Example:
  ./4-deploy_all_services.sh -n obaas-dev -d mydb
  ./4-deploy_all_services.sh -n obaas-dev -d mydb -o obaas
  ./4-deploy_all_services.sh -n obaas-dev -d mydb -r docker.io/myuser/cloudbank
  ./4-deploy_all_services.sh -n obaas-dev -d mydb --dry-run
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
            eval "$var_name=\"$value\""
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
        ((errors++))
    fi

    # Check helm
    if ! prereq_check_helm; then
        ((errors++))
    fi

    # Check namespace exists
    if ! prereq_check_namespace "$NAMESPACE"; then
        ((errors++))
    fi

    # Check helm chart exists
    if ! prereq_check_helm_chart; then
        ((errors++))
    fi

    if [[ $errors -gt 0 ]]; then
        return 1
    fi

    return 0
}

# =============================================================================
# Deployment
# =============================================================================
get_db_user_for_service() {
    local service_name="$1"
    # Map services to their database user (matches 3-k8s_db_secrets.sh SERVICE_ACCOUNTS)
    case "$service_name" in
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
    local helm_command="helm upgrade --install $service_name obaas/obaas-sample-app"
    helm_command+=" -f $values_file_path"
    helm_command+=" --namespace $NAMESPACE"
    helm_command+=" --set image.repository=$image_repository"
    helm_command+=" --set image.tag=$IMAGE_TAG"
    helm_command+=" --set obaas.releaseName=$OBAAS_RELEASE"
    helm_command+=" --set database.name=$DB_NAME"
    helm_command+=" --set database.authN.secretName=$db_secret_name"

    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] Would run: $helm_command"
        return 0
    fi

    print_step "Deploying $service_name..."
    print_info "Image: $image_repository:$IMAGE_TAG"

    # Verify image exists before deploying
    if ! docker manifest inspect "$image_repository:$IMAGE_TAG" &>/dev/null; then
        print_error "Image not found: $image_repository:$IMAGE_TAG"
        print_info "Build and push images first: ./2-images_build_push.sh"
        return 1
    fi
    print_success "Image verified"

    print_info "Running: $helm_command --wait --timeout 5m"

    # Suppress NOTES.txt output unless this is the last service
    if [[ "$is_last_service" == true ]]; then
        if $helm_command --wait --timeout 5m; then
            print_success "$service_name deployed successfully"
            return 0
        else
            print_error "Failed to deploy $service_name"
            print_info "Check pod status: kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=$service_name"
            print_info "Check pod logs:   kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=$service_name"
            return 1
        fi
    else
        if $helm_command --wait --timeout 5m > /dev/null; then
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
        ((service_index++))
        local is_last_service=false
        if [[ $service_index -eq $total_services ]]; then
            is_last_service=true
        fi

        if deploy_service "$service" "$final_registry" "$is_last_service"; then
            if [[ "$DRY_RUN" != true ]]; then
                ((deployed_count++))
            fi
        else
            ((failed_count++))
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
    if ! prereq_check_db_app_secrets "$NAMESPACE" "$DB_NAME"; then
        print_warning "Some database secrets are missing. Services may fail to start."
        echo ""
        read -p "Continue anyway? [y/N]: " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "Deployment cancelled."
            exit 0
        fi
    fi

    # Show configuration
    print_header "Configuration"
    echo "  Namespace:     $NAMESPACE"
    echo "  OBaaS Release: $OBAAS_RELEASE"
    echo "  Database:      $DB_NAME"
    echo "  Registry:      $final_registry"
    echo "  Image Tag:     $IMAGE_TAG"
    echo "  Dry Run:       $DRY_RUN"
    echo ""
    echo "  Services:      ${SERVICE_LIST[*]}"
    echo ""

    if [[ "$DRY_RUN" != true ]]; then
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
