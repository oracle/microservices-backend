
#!/usr/bin/env bash

# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at
# https://oss.oracle.com/licenses/upl.

set -Eeuo pipefail
set +x
umask 077

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly ENV_FILE="$REPOSITORY_ROOT/.env"
readonly AZN_DEPLOY_SCRIPT="$SCRIPT_DIR/deploy-azn-server_v1.sh"
readonly SERVICES_DEPLOY_SCRIPT="$SCRIPT_DIR/deploy-services.sh"
readonly WORKFLOW_DIR="$REPOSITORY_ROOT/src/workflows/cloudbank-loan-origination"

DEPLOY_MODE=""
START_FROM="azn-server"
CONTEXT=""
NAMESPACE=""
OBAAS_RELEASE=""
WORK_DIR=""
MONITOR_PID=""
AZN_FORWARD_PID=""
WORKFLOW_FORWARD_PID=""

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 2
}

usage() {
    cat <<'EOF'
Deploy CloudBank AI on an existing OBaaS OKE installation, version 2.1.0 or later.

Usage:
  ./deploy/obaas/cloudbankai_deploy.sh first-deploy [--from services|workflow]
  ./deploy/obaas/cloudbankai_deploy.sh redeploy [--from services|workflow]

Configure the repository-root .env and OCI GenAI Workload Identity policies
following deploy/obaas/cloudbank-v6-install.md.
Export a new immutable NEW_IMAGE_TAG when running the azn-server step;
the services helper generates its own immutable image tag. Use --from services
after azn-server succeeded, or --from workflow after services succeeded.

The command runs the existing azn-server deployment (including MicroTx OIDC),
services deployment, and version 1 workflow deployment in order. Keep their
interactive confirmations and complete the workflow operator OAuth/PKCE login
when prompted. Temporary deployment port-forwards are stopped on exit.
EOF
}

required_env_value() {
    local name="$1"
    local value

    value="$(awk -v name="$name" '
        index($0, name "=") == 1 { count++; value = substr($0, length(name) + 2) }
        END {
            if (count != 1 || value == "") exit 1
            print value
        }
    ' "$ENV_FILE")" || die ".env must contain exactly one non-empty $name entry"
    case "$value" in
        *$'\n'* | *$'\r'*) die ".env variable $name contains a newline" ;;
    esac
    printf '%s' "$value"
}

cleanup() {
    local pid
    for pid in "$AZN_FORWARD_PID" "$WORKFLOW_FORWARD_PID" "$MONITOR_PID"; do
        if [[ -n "$pid" ]]; then
            kill "$pid" >/dev/null 2>&1 || true
            wait "$pid" >/dev/null 2>&1 || true
        fi
    done
    if [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]]; then
        rm -rf -- "$WORK_DIR"
    fi
}

preflight() {
    local command_name
    local name
    local file

    [[ -t 0 ]] || die "deployment requires an interactive terminal"
    for command_name in oci kubectl helm docker mvn jq openssl curl awk sed grep \
        sort mktemp mkdir chmod dirname head tail patch tee mkfifo sleep; do
        command -v "$command_name" >/dev/null 2>&1 || die "$command_name is required"
    done
    for file in "$AZN_DEPLOY_SCRIPT" "$SERVICES_DEPLOY_SCRIPT" "$WORKFLOW_DIR/deploy.sh"; do
        [[ -x "$file" ]] || die "deployment helper is missing or not executable: $file"
    done
    for file in workflow-v1-obaas.json review-documents-task-def.json \
        refresh-workflow-authorization-task-def.json; do
        [[ -r "$WORKFLOW_DIR/$file" ]] || die "workflow asset is missing: $file"
    done
    [[ -r "$ENV_FILE" ]] || die ".env is missing; follow deploy/obaas/cloudbank-v6-install.md"
    for name in OCI_REGION OKE_CLUSTER_OCID CLOUDBANK_KUBECONFIG_PATH \
        OCI_COMPARTMENT_OCID OCI_IDENTITY_NAME OCI_AUTH_TOKEN OBAAS_RELEASE \
        MICROTX_NAMESPACE MICROTX_PUBLIC_HOST MICROTX_PROTOCOL MICROTX_PUBLIC_PORT \
        IMAGE_PULL_SECRET POLICY_SERVICE_ACCOUNT POLICY_OCI_GENAI_EMBEDDING_MODEL \
        AI_SERVICE_ACCOUNT AI_OCI_GENAI_CHAT_MODEL OKE_CLUSTER_COMPARTMENT_ID \
        GEOGRAPHIC_RISK_LOG_GEOCODING_DETAILS; do
        required_env_value "$name" >/dev/null
    done
    if [[ "$START_FROM" == azn-server ]]; then
        [[ "${NEW_IMAGE_TAG:-}" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]] ||
            die "export a new immutable NEW_IMAGE_TAG before deployment"
        [[ "$NEW_IMAGE_TAG" != latest ]] || die "refusing mutable image tag 'latest'"
        export NEW_IMAGE_TAG
    fi
    KUBECONFIG="$(required_env_value CLOUDBANK_KUBECONFIG_PATH)"
    export KUBECONFIG
    [[ "$KUBECONFIG" == /* && "$KUBECONFIG" != / ]] ||
        die "CLOUDBANK_KUBECONFIG_PATH must be an absolute file path"
    NAMESPACE="$(required_env_value MICROTX_NAMESPACE)"
    OBAAS_RELEASE="$(required_env_value OBAAS_RELEASE)"
    [[ "$NAMESPACE" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]] ||
        die "MICROTX_NAMESPACE must be a Kubernetes namespace name"
    [[ "$OBAAS_RELEASE" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]] ||
        die "OBAAS_RELEASE must be a Helm release name"
}

run_step() {
    local name="$1"
    local success_message="$2"
    shift 2
    local fifo="$WORK_DIR/$name.output"
    local completion_file="$WORK_DIR/$name.complete"
    local status=0

    # Existing helpers also exit zero when cancelled. Require their final success
    # message before advancing, while streaming prompts without storing raw logs.
    mkfifo "$fifo"
    awk -v expected="$success_message" -v completion="$completion_file" '
        $0 == expected { complete = 1 }
        END { if (complete) print "complete" > completion }
    ' "$fifo" &
    MONITOR_PID=$!
    "$@" | tee "$fifo" || status=$?
    wait "$MONITOR_PID" || status=$?
    MONITOR_PID=""
    if [[ "$status" -ne 0 ]]; then
        printf 'ERROR: CloudBank deployment stopped during %s (exit %s).\n' "$name" "$status" >&2
        exit "$status"
    fi
    [[ -f "$completion_file" ]] ||
        die "$name did not complete or was cancelled; subsequent deployment steps were not run"
}

start_port_forward() {
    local service_name="$1"
    local local_port="$2"
    local remote_port="$3"
    local pid_variable="$4"
    local log_file="$WORK_DIR/$service_name.port-forward.log"
    local pid
    local attempt

    kubectl --context "$CONTEXT" --namespace "$NAMESPACE" port-forward \
        --address 127.0.0.1 "service/$service_name" "$local_port:$remote_port" \
        >"$log_file" 2>&1 &
    pid=$!
    printf -v "$pid_variable" '%s' "$pid"
    for attempt in {1..100}; do
        kill -0 "$pid" >/dev/null 2>&1 ||
            die "port-forward for service/$service_name stopped; ensure local port $local_port is free"
        if grep -Fqx "Forwarding from 127.0.0.1:$local_port -> $remote_port" "$log_file"; then
            return 0
        fi
        sleep 0.2
    done
    die "port-forward for service/$service_name did not become ready"
}

deploy_workflow() (
    # Use the documented operator login against this deployment's Azn instance.
    # Discard ambient authentication overrides for other environments.
    unset MICROTX_BEARER_TOKEN MICROTX_OPERATOR_TOKEN_URI MICROTX_OPERATOR_CLIENT_ID \
        MICROTX_OPERATOR_REDIRECT_URI MICROTX_OPERATOR_CLIENT_SECRET MICROTX_OPERATOR_SCOPE
    export CLOUDBANK_ENV_FILE="$ENV_FILE"
    export MICROTX_WORKFLOW_URL='http://127.0.0.1:9010/workflow-server'
    export MICROTX_OPERATOR_AUTH_SERVER_URL='http://127.0.0.1:8080'
    export MICROTX_DEPLOY_AUTH_MODE=operator
    export MICROTX_TASK_DEFINITION_FILE="$WORKFLOW_DIR/review-documents-task-def.json"
    export MICROTX_TOKEN_REFRESH_TASK_DEFINITION_FILE="$WORKFLOW_DIR/refresh-workflow-authorization-task-def.json"
    "$WORKFLOW_DIR/deploy.sh" "$WORKFLOW_DIR/workflow-v1-obaas.json"
)

main() {
    if [[ $# -eq 1 && ( "$1" == -h || "$1" == --help ) ]]; then
        usage
        return 0
    fi
    [[ $# -ge 1 ]] || { usage >&2; exit 2; }
    DEPLOY_MODE="$1"
    case "$DEPLOY_MODE" in
        first-deploy | redeploy) ;;
        *) die "mode must be 'first-deploy' or 'redeploy'" ;;
    esac
    shift
    START_FROM=azn-server
    if [[ $# -gt 0 ]]; then
        [[ $# -eq 2 && "$1" == --from ]] || { usage >&2; exit 2; }
        case "$2" in
            services | workflow) START_FROM="$2" ;;
            *) die "--from must be 'services' or 'workflow'" ;;
        esac
    fi
    preflight
    cd "$REPOSITORY_ROOT"
    WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cloudbankai-deploy.XXXXXX")"
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' HUP TERM

    if [[ "$START_FROM" == azn-server ]]; then
        printf '\n[1/3] Deploy azn-server and secure MicroTx\n'
        run_step azn-server \
            "SUCCESS: azn-server $DEPLOY_MODE completed and all verification checks passed." \
            "$AZN_DEPLOY_SCRIPT" "$DEPLOY_MODE"
    else
        CONTEXT="$(kubectl config current-context)"
        [[ -n "$CONTEXT" ]] || die "the dedicated kubeconfig has no current context"
        kubectl --context "$CONTEXT" --namespace "$NAMESPACE" rollout status \
            deployment/azn-server --timeout=30s >/dev/null ||
            die "azn-server must be ready before resuming from $START_FROM"
        printf '\nResuming from %s using the existing azn-server deployment.\n' "$START_FROM"
    fi

    if [[ "$START_FROM" != workflow ]]; then
        printf '\n[2/3] Deploy CloudBank services\n'
        run_step services \
            'CloudBank schema, lab owner access, and policy bootstrap completed; all eight application services are deployed and have ready endpoints.' \
            "$SERVICES_DEPLOY_SCRIPT" "$DEPLOY_MODE"
    fi

    printf '\n[3/3] Deploy MicroTx task and workflow definitions\n'
    CONTEXT="$(kubectl config current-context)"
    [[ -n "$CONTEXT" ]] || die "the dedicated kubeconfig has no current context"
    start_port_forward azn-server 8080 8080 AZN_FORWARD_PID
    start_port_forward "$OBAAS_RELEASE-otmm-workflow-server" 9010 9010 WORKFLOW_FORWARD_PID
    curl --silent --show-error --fail --connect-timeout 5 --max-time 15 \
        http://127.0.0.1:8080/actuator/health |
        jq -e '.status == "UP"' >/dev/null || die "azn-server is not ready for operator login"
    local workflow_status
    workflow_status="$(curl --silent --show-error --connect-timeout 5 --max-time 15 \
        --output /dev/null --write-out '%{http_code}' \
        http://127.0.0.1:9010/workflow-server/api/metadata/workflow)"
    case "$workflow_status" in
        401 | 403) ;;
        *) die "Workflow API must require authentication before metadata deployment (HTTP $workflow_status)" ;;
    esac
    run_step workflow \
        'Workflow cloudbank-loan-origination version 1 deployed successfully.' \
        deploy_workflow

    printf '\nSUCCESS: CloudBank deployment completed.\n'
    printf 'Complete the post-launch ADB geocoding setup in deploy/obaas/cloudbank-v6-install.md.\n'
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
