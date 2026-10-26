#!/usr/bin/env bash

# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at
# https://oss.oracle.com/licenses/upl.

set -uo pipefail

readonly DEFAULT_AZN_LOCAL_PORT="8080"
readonly DEFAULT_LOAN_LOCAL_PORT="18081"
readonly DEFAULT_GEO_LOCAL_PORT="18083"
readonly DEFAULT_WORKFLOW_TIMEOUT="120"
readonly EXPECTED_WORKFLOW_NAME="cloudbank-loan-origination"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly CLOUDBANK_ENV_FILE="${CLOUDBANK_ENV_FILE:-$REPOSITORY_ROOT/.env}"
readonly LOCAL_SMOKE_TEST="$SCRIPT_DIR/smoke-test.sh"

KUBECTL_CONTEXT=""
OBAAS_NAMESPACE=""
OBAAS_RELEASE=""
OBAAS_APP_VERSION=""
AZN_LOCAL_PORT="${OBAAS_AZN_LOCAL_PORT:-$DEFAULT_AZN_LOCAL_PORT}"
LOAN_LOCAL_PORT="${OBAAS_LOAN_LOCAL_PORT:-$DEFAULT_LOAN_LOCAL_PORT}"
GEO_LOCAL_PORT="${OBAAS_GEO_LOCAL_PORT:-$DEFAULT_GEO_LOCAL_PORT}"
WORKFLOW_TIMEOUT="${WORKFLOW_TIMEOUT:-$DEFAULT_WORKFLOW_TIMEOUT}"
NON_INTERACTIVE=false
MANUAL_REVIEW=false
APPLICATION_JSON_FILE="${LOAN_SMOKE_APPLICATION_JSON_FILE:-}"
TEMP_DIR=""
PORT_FORWARD_PIDS=()
USER_PASSWORD="${USER_PASSWORD-}"
USERNAME="${USERNAME:-obaas-admin}"
BROWSER_CLIENT_SECRET="${BROWSER_CLIENT_SECRET-}"
SERVICE_CLIENT_SECRET="${SERVICE_CLIENT_SECRET-}"

usage() {
    cat <<EOF
Usage: ${0##*/} <kubectl-context> [options]

Runs the loan application smoke test against CloudBank deployed on OBaaS/OKE.
The script discovers the OBaaS namespace, validates the live MicroTx setup,
starts private localhost port-forwards when needed, and always uses
WORKFLOW_MODE=microtx. An already occupied local port is assumed to belong to
an existing port-forward and is reused.

Options:
  -n, --namespace NAME  OBaaS application namespace (auto-detected)
      --from-env        Read smoke-test credentials from the repository-root
                        .env file without prompting; explicit environment
                        overrides take precedence
      --non-interactive Alias for --from-env
      --application-file FILE  Intake JSON and ready PDFs from its directory
      --manual-review   Use the packet employer-conflict fixture for the
                        MANUAL_REVIEW workflow branch
  -h, --help            Show this help

Optional environment variables:
  OBAAS_AZN_LOCAL_PORT   Local azn-server port (default: $DEFAULT_AZN_LOCAL_PORT)
  OBAAS_LOAN_LOCAL_PORT  Local loan-service port (default: $DEFAULT_LOAN_LOCAL_PORT)
  OBAAS_GEO_LOCAL_PORT   Local geographic-risk port when verification is enabled
                         (default: $DEFAULT_GEO_LOCAL_PORT)
  WORKFLOW_TIMEOUT       Dispatch polling timeout in seconds (default: $DEFAULT_WORKFLOW_TIMEOUT)
  CLOUDBANK_ENV_FILE     Credential file (default: repository-root .env)
  USERNAME              User identity (default: obaas-admin); alternate users
                         require an explicit USER_PASSWORD with --from-env

Changing OBAAS_AZN_LOCAL_PORT also requires REDIRECT_URI to identify a URI
registered for the browser OAuth client. The standard deployment uses port 8080.

By default the test verifies only that MicroTx dispatch reaches STARTED.
With LOAN_SMOKE_VERIFY_GEO=true and LOAN_SMOKE_STOP_AFTER_DISPATCH=true, it
also waits for a geographic-risk result. It never completes a HUMAN task.
EOF
}

die() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 2
}

info() {
    printf '%s\n' "$1"
}

read_local_env_value() {
    local name="$1"

    [[ -r "$CLOUDBANK_ENV_FILE" ]] || return 1
    awk -v name="$name" '
        index($0, name "=") == 1 { value = substr($0, length(name) + 2) }
        END {
            if (value == "") exit 1
            print value
        }
    ' "$CLOUDBANK_ENV_FILE"
}

load_non_interactive_credentials() {
    if [[ "$USERNAME" != obaas-admin && -z "$USER_PASSWORD" ]]; then
        die "An alternate username requires an explicit USER_PASSWORD; the lab defaults to obaas-admin"
    fi
    USER_PASSWORD="${USER_PASSWORD:-$(
        read_local_env_value AZN_BOOTSTRAP_USERS_ADMIN_PASSWORD || true
    )}"
    BROWSER_CLIENT_SECRET="${BROWSER_CLIENT_SECRET:-$(
        read_local_env_value AZN_AUTHORIZATION_SERVER_DEFAULT_CLIENT_SECRET || true
    )}"
    SERVICE_CLIENT_SECRET="${SERVICE_CLIENT_SECRET:-$(
        read_local_env_value AZN_AUTHORIZATION_SERVER_SERVICE_CLIENT_SECRET || true
    )}"

    [[ -n "$USER_PASSWORD" ]] ||
        die "Set USER_PASSWORD or AZN_BOOTSTRAP_USERS_ADMIN_PASSWORD in the configured .env file"
    [[ -n "$BROWSER_CLIENT_SECRET" ]] ||
        die "Set BROWSER_CLIENT_SECRET or AZN_AUTHORIZATION_SERVER_DEFAULT_CLIENT_SECRET in the configured .env file"
    [[ -n "$SERVICE_CLIENT_SECRET" ]] ||
        die "Set SERVICE_CLIENT_SECRET or AZN_AUTHORIZATION_SERVER_SERVICE_CLIENT_SECRET in the configured .env file"
    info "Loaded required smoke-test credentials without displaying their values."
}

cleanup() {
    local pid

    USER_PASSWORD=""
    BROWSER_CLIENT_SECRET=""
    SERVICE_CLIENT_SECRET=""
    unset USER_PASSWORD BROWSER_CLIENT_SECRET SERVICE_CLIENT_SECRET
    if [[ "${#PORT_FORWARD_PIDS[@]}" -gt 0 ]]; then
        for pid in "${PORT_FORWARD_PIDS[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                kill "$pid" 2>/dev/null || true
            fi
        done
        for pid in "${PORT_FORWARD_PIDS[@]}"; do
            wait "$pid" 2>/dev/null || true
        done
    fi
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf -- "$TEMP_DIR"
    fi
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "$1 is required"
}

require_port() {
    local name="$1"
    local value="$2"

    [[ "$value" =~ ^[1-9][0-9]{0,4}$ && "$value" -le 65535 ]] ||
        die "$name must be an integer from 1 through 65535"
}

port_is_in_use() {
    local local_port="$1"

    (exec 3<>"/dev/tcp/127.0.0.1/$local_port") >/dev/null 2>&1
}

prompt_secret() {
    local variable_name="$1"
    local label="$2"
    local entered_value

    IFS= read -r -s -p "$label: " entered_value
    printf '\n'
    [[ -n "$entered_value" ]] || die "$label must not be empty"
    printf -v "$variable_name" '%s' "$entered_value"
}

parse_args() {
    [[ $# -ge 1 ]] || {
        usage >&2
        exit 2
    }
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        usage
        exit 0
    fi

    KUBECTL_CONTEXT="$1"
    shift
    [[ -n "$KUBECTL_CONTEXT" ]] || die "kubectl context must not be empty"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n | --namespace)
                [[ $# -ge 2 && -n "${2-}" ]] || die "$1 requires a namespace"
                OBAAS_NAMESPACE="$2"
                shift 2
                ;;
            --from-env | --non-interactive)
                NON_INTERACTIVE=true
                shift
                ;;
            --manual-review)
                MANUAL_REVIEW=true
                shift
                ;;
            --application-file)
                [[ $# -ge 2 && -n "$2" && "$2" != -* ]] || die "--application-file requires a path"
                APPLICATION_JSON_FILE="$2"
                shift 2
                ;;
            -h | --help)
                usage
                exit 0
                ;;
            *)
                usage >&2
                die "unknown option: $1"
                ;;
        esac
    done
}

detect_obaas_target() {
    local releases_json
    local target

    if [[ -n "$OBAAS_NAMESPACE" ]]; then
        releases_json="$(helm list --kube-context "$KUBECTL_CONTEXT" \
            --namespace "$OBAAS_NAMESPACE" --output json)" ||
            die "could not list Helm releases in namespace '$OBAAS_NAMESPACE'"
    else
        releases_json="$(helm list --kube-context "$KUBECTL_CONTEXT" \
            --all-namespaces --output json)" ||
            die "could not list Helm releases in context '$KUBECTL_CONTEXT'"
    fi

    target="$(printf '%s' "$releases_json" | jq -er '
      [.[] | select(.chart | test("^obaas-[0-9]"))]
      | if length == 1 then
          .[0] | [.name, .namespace, .app_version] | @tsv
        else
          error("expected exactly one deployed OBaaS release; found \(length)")
        end
    ')" || die "expected exactly one deployed OBaaS release on the selected target"

    IFS=$'\t' read -r OBAAS_RELEASE OBAAS_NAMESPACE OBAAS_APP_VERSION <<<"$target"
    [[ -n "$OBAAS_RELEASE" && -n "$OBAAS_NAMESPACE" ]] ||
        die "OBaaS release discovery returned an incomplete target"
    case "${OBAAS_APP_VERSION%%-*}" in
        2.1.0 | 2.1.1) ;;
        *) die "unsupported OBaaS appVersion '$OBAAS_APP_VERSION'" ;;
    esac
}

service_port() {
    local service_name="$1"
    local preferred_port="$2"

    kubectl --context "$KUBECTL_CONTEXT" --namespace "$OBAAS_NAMESPACE" \
        get service "$service_name" -o json |
        jq -er --argjson preferred "$preferred_port" '
          (.spec.ports // []) as $ports
          | if ([$ports[] | select(.port == $preferred)] | length) == 1 then
              [$ports[] | select(.port == $preferred)][0].port
            elif ($ports | length) == 1 then
              $ports[0].port
            else
              error("expected the preferred port or exactly one Service port")
            end
        '
}

validate_required_services() {
    local required_services_json
    local services_json
    local endpoint_slices_json
    local endpoint_readiness
    local missing_services
    local service_name
    local endpoint_count

    required_services_json="$(jq -cn '$ARGS.positional' --args "$@")" ||
        die "could not prepare the required-service list"

    info "Checking $# required Kubernetes Services in namespace '$OBAAS_NAMESPACE'..."
    services_json="$(kubectl --context "$KUBECTL_CONTEXT" \
        --namespace "$OBAAS_NAMESPACE" get services -o json)" ||
        die "could not list Services in namespace '$OBAAS_NAMESPACE'"
    missing_services="$(printf '%s' "$services_json" | jq -r \
        --argjson required "$required_services_json" \
        '$required - [.items[]?.metadata.name] | join(", ")')" ||
        die "could not inspect required Services"
    [[ -z "$missing_services" ]] ||
        die "required Services were not found: $missing_services"
    info "All required Services exist. Checking ready EndpointSlices..."

    endpoint_slices_json="$(kubectl --context "$KUBECTL_CONTEXT" \
        --namespace "$OBAAS_NAMESPACE" get endpointslices -o json)" ||
        die "could not list EndpointSlices in namespace '$OBAAS_NAMESPACE'"
    endpoint_readiness="$(printf '%s' "$endpoint_slices_json" | jq -r \
        --argjson required "$required_services_json" '
          $required[] as $service
          | ([.items[]?
              | select(.metadata.labels["kubernetes.io/service-name"] == $service)
              | .endpoints[]?
              | select(.conditions.ready != false)] | length) as $ready
          | [$service, $ready] | @tsv
        ')" || die "could not inspect required EndpointSlices"
    while IFS=$'\t' read -r service_name endpoint_count; do
        [[ "$endpoint_count" -ge 1 ]] ||
            die "service '$service_name' has no ready EndpointSlice endpoint"
        info "  ready: $service_name ($endpoint_count endpoint(s))"
    done <<<"$endpoint_readiness"
}

validate_required_deployments() {
    local deployment_json
    local worker_available
    local workflow_mode
    local workflow_name

    info "Checking required deployments and Loan Service MicroTx configuration..."
    deployment_json="$(kubectl --context "$KUBECTL_CONTEXT" \
        --namespace "$OBAAS_NAMESPACE" get deployments -o json)" ||
        die "could not list deployments in namespace '$OBAAS_NAMESPACE'"
    worker_available="$(printf '%s' "$deployment_json" | jq -r '
      [.items[]? | select(.metadata.name == "workflow-token-refresh-worker")
       | (.status.availableReplicas // 0) >= 1][0] // false')" ||
        die "could not inspect workflow-token-refresh-worker"
    [[ "$worker_available" == "true" ]] ||
        die "deployment 'workflow-token-refresh-worker' was not found or has no available replica"
    info "  available: workflow-token-refresh-worker"

    workflow_mode="$(printf '%s' "$deployment_json" | jq -r '
      [.items[]? | select(.metadata.name == "loan-application-service")
       | .spec.template.spec.containers[]?.env[]?
       | select(.name == "WORKFLOW_MODE") | .value // empty][0] // empty')"
    workflow_name="$(printf '%s' "$deployment_json" | jq -r '
      [.items[]? | select(.metadata.name == "loan-application-service")
       | .spec.template.spec.containers[]?.env[]?
       | select(.name == "MICROTX_WORKFLOW_NAME") | .value // empty][0] // empty')"

    [[ "$workflow_mode" == "microtx" ]] ||
        die "loan-application-service WORKFLOW_MODE is '${workflow_mode:-unset}', expected 'microtx'"
    [[ "$workflow_name" == "$EXPECTED_WORKFLOW_NAME" ]] ||
        die "loan-application-service workflow name is '${workflow_name:-unset}', expected '$EXPECTED_WORKFLOW_NAME'"
    info "  configured: loan-application-service (MicroTx workflow $workflow_name)"
}

start_port_forward() {
    local service_name="$1"
    local local_port="$2"
    local remote_port="$3"
    local label="$4"
    local log_file="$TEMP_DIR/${service_name}-port-forward.log"
    local pid
    local attempt

    if port_is_in_use "$local_port"; then
        info "$label port-forward already available on http://127.0.0.1:$local_port; reusing it"
        return
    fi

    kubectl --context "$KUBECTL_CONTEXT" --namespace "$OBAAS_NAMESPACE" \
        port-forward --address 127.0.0.1 "service/$service_name" \
        "${local_port}:${remote_port}" >"$log_file" 2>&1 &
    pid=$!
    PORT_FORWARD_PIDS+=("$pid")

    for attempt in 1 2 3 4 5 6 7 8 9 10; do
        if ! kill -0 "$pid" 2>/dev/null; then
            if port_is_in_use "$local_port"; then
                info "$label port-forward became available externally on http://127.0.0.1:$local_port; reusing it"
                return
            fi
            info "$label port-forward failed:"
            sed -n '1,20p' "$log_file" >&2
            die "could not start $label port-forward on 127.0.0.1:$local_port"
        fi
        if grep -Fq "Forwarding from 127.0.0.1:${local_port} ->" "$log_file"; then
            info "$label port-forward: http://127.0.0.1:$local_port"
            return
        fi
        sleep 1
    done

    die "$label port-forward did not become ready"
}

run_smoke_test() {
    local -a smoke_args
    local loan_service_port
    local azn_service_port
    local geo_service_port
    local smoke_status

    loan_service_port="$(service_port loan-application-service 8080)" ||
        die "could not determine the loan-application-service port"
    azn_service_port="$(service_port azn-server 8080)" ||
        die "could not determine the azn-server port"

    start_port_forward azn-server "$AZN_LOCAL_PORT" "$azn_service_port" "azn-server"
    start_port_forward loan-application-service "$LOAN_LOCAL_PORT" \
        "$loan_service_port" "loan-application-service"
    if [[ "${LOAN_SMOKE_VERIFY_GEO-false}" == "true" ]]; then
        geo_service_port="$(service_port geographic-risk-service 8080)" ||
            die "could not determine the geographic-risk-service port"
        start_port_forward geographic-risk-service "$GEO_LOCAL_PORT" \
            "$geo_service_port" "geographic-risk-service"
    fi

    smoke_args=(--non-interactive)
    if [[ -n "$APPLICATION_JSON_FILE" ]]; then
        smoke_args+=(--application-file "$APPLICATION_JSON_FILE")
    fi
    if [[ "$MANUAL_REVIEW" == "true" ]]; then
        smoke_args+=(--manual-review)
    fi

    info ""
    info "Running authenticated OKE smoke test."
    LOAN_BASE_URL="http://127.0.0.1:$LOAN_LOCAL_PORT" \
    AZN_BASE_URL="http://127.0.0.1:$AZN_LOCAL_PORT" \
    GEO_BASE_URL="http://127.0.0.1:$GEO_LOCAL_PORT" \
    WORKFLOW_MODE="microtx" \
    WORKFLOW_TIMEOUT="$WORKFLOW_TIMEOUT" \
    USERNAME="$USERNAME" \
    USER_PASSWORD="$USER_PASSWORD" \
    BROWSER_CLIENT_SECRET="$BROWSER_CLIENT_SECRET" \
    SERVICE_CLIENT_SECRET="$SERVICE_CLIENT_SECRET" \
        "$LOCAL_SMOKE_TEST" "${smoke_args[@]}"
    smoke_status=$?
    return "$smoke_status"
}

main() {
    local workflow_service
    local -a required_services

    parse_args "$@"
    for command_name in kubectl helm jq grep sed awk mktemp rm chmod sleep; do
        require_command "$command_name"
    done
    [[ -x "$LOCAL_SMOKE_TEST" ]] || die "smoke test is not executable: $LOCAL_SMOKE_TEST"
    require_port OBAAS_AZN_LOCAL_PORT "$AZN_LOCAL_PORT"
    require_port OBAAS_LOAN_LOCAL_PORT "$LOAN_LOCAL_PORT"
    if [[ "${LOAN_SMOKE_VERIFY_GEO-false}" == "true" ]]; then
        require_port OBAAS_GEO_LOCAL_PORT "$GEO_LOCAL_PORT"
    fi
    [[ "$WORKFLOW_TIMEOUT" =~ ^[1-9][0-9]{0,2}$ ]] ||
        die "WORKFLOW_TIMEOUT must be an integer from 1 through 999"

    kubectl config get-contexts "$KUBECTL_CONTEXT" -o name 2>/dev/null |
        grep -Fxq "$KUBECTL_CONTEXT" || die "kubectl context does not exist: $KUBECTL_CONTEXT"
    kubectl --context "$KUBECTL_CONTEXT" cluster-info >/dev/null ||
        die "cannot reach kubectl context '$KUBECTL_CONTEXT'"

    detect_obaas_target
    printf 'OBaaS target: release=%s namespace=%s appVersion=%s\n' \
        "$OBAAS_RELEASE" "$OBAAS_NAMESPACE" "$OBAAS_APP_VERSION"

    workflow_service="${OBAAS_RELEASE}-otmm-workflow-server"
    required_services=(
        azn-server
        loan-application-service
        document-ingest
        document-review-service
        ai-agent-service
        geographic-risk-service
        policy-retrieval-service
        "$workflow_service"
    )
    validate_required_services "${required_services[@]}"
    validate_required_deployments
    info "OBaaS services, EndpointSlices, and Loan Service MicroTx configuration are ready."

    if [[ "$NON_INTERACTIVE" == "true" ]]; then
        load_non_interactive_credentials
    else
        [[ -t 0 ]] || die "interactive input is required for credential prompts"
        info ""
        info "Enter the credentials installed in the selected OKE environment."
        [[ -n "$USER_PASSWORD" ]] ||
            prompt_secret USER_PASSWORD \
                "Lab owner password (AZN_BOOTSTRAP_USERS_ADMIN_PASSWORD)"
        [[ -n "$BROWSER_CLIENT_SECRET" ]] ||
            prompt_secret BROWSER_CLIENT_SECRET \
                "Browser OAuth client secret (AZN_AUTHORIZATION_SERVER_DEFAULT_CLIENT_SECRET)"
        [[ -n "$SERVICE_CLIENT_SECRET" ]] ||
            prompt_secret SERVICE_CLIENT_SECRET \
                "Service OAuth client secret (AZN_AUTHORIZATION_SERVER_SERVICE_CLIENT_SECRET)"
    fi

    TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cloudbank-loan-obaas-smoke.XXXXXX")" ||
        die "unable to create a private temporary directory"
    chmod 700 "$TEMP_DIR"

    run_smoke_test
}

main "$@"
