#!/usr/bin/env bash
set -euo pipefail
set +x

# Configure or remove authentication on the MicroTx resources owned by the
# existing OBaaS release. This script patches only live Azn and OTMM resources;
# it never runs `helm upgrade obaas` or creates workflow definitions.

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/deploy/obaas/lib/obaas-version.sh"
readonly ENV_FILE="$REPO_ROOT/.env"
readonly BRIDGE_TEMPLATE="$SCRIPT_DIR/oidc-bridge.yaml.template"

readonly AZN_SERVICE="azn-server"
readonly AZN_DEPLOYMENT="azn-server"
readonly AZN_CONSOLE_SECRET_NAME="cloudbank-ai-azn-microtx-console"
readonly OAUTH_SECRET_NAME="microtx-console-oauth"
readonly COOKIE_SECRET_NAME="microtx-console-cookie-encryption"
readonly OIDC_BRIDGE_NAME="microtx-azn-oidc-bridge"
readonly WORKFLOW_CLIENT_ID="microtx-workflow-client"

MODE=""
ASSUME_YES=false
KUBECONFIG_PATH=""
CONTEXT=""
RELEASE=""
NAMESPACE=""
OBAAS_APP_VERSION=""
AZN_ISSUER_URI=""
AZN_CLUSTER_URL=""
MICROTX_PUBLIC_HOST=""
MICROTX_PROTOCOL=""
MICROTX_PUBLIC_PORT=""
AZN_CONSOLE_REDIRECT_URI=""
AZN_CONSOLE_POST_LOGOUT_REDIRECT_URI=""
OIDC_BRIDGE_URL=""
COORDINATOR_CONFIG=""
CONSOLE_DEPLOYMENT=""
WORKFLOW_DEPLOYMENT=""
COORDINATOR_STATEFULSET=""
AZN_CONTAINER=""
BRIDGE_MANIFEST=""
SOURCE_CLIENT_ID_B64=""
SOURCE_CLIENT_SECRET_B64=""
TARGET_CLIENT_ID_B64=""
TARGET_CLIENT_SECRET_B64=""
COOKIE_SECRET_B64=""
MICROTX_CLIENT_SECRET=""
TOKEN_RESPONSE=""
ACCESS_TOKEN=""
WORK_DIR=""
AZN_FORWARD_PID=""
WORKFLOW_FORWARD_PID=""
AZN_FORWARD_PORT=""
WORKFLOW_FORWARD_PORT=""

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

usage() {
    printf 'Usage: %s --enable [--yes] | --disable\n' "$0" >&2
}

cleanup() {
    if [[ -n "$AZN_FORWARD_PID" ]]; then
        kill "$AZN_FORWARD_PID" >/dev/null 2>&1 || true
        wait "$AZN_FORWARD_PID" >/dev/null 2>&1 || true
    fi
    if [[ -n "$WORKFLOW_FORWARD_PID" ]]; then
        kill "$WORKFLOW_FORWARD_PID" >/dev/null 2>&1 || true
        wait "$WORKFLOW_FORWARD_PID" >/dev/null 2>&1 || true
    fi
    unset SOURCE_CLIENT_ID_B64 SOURCE_CLIENT_SECRET_B64
    unset TARGET_CLIENT_ID_B64 TARGET_CLIENT_SECRET_B64 COOKIE_SECRET_B64
    unset MICROTX_CLIENT_SECRET TOKEN_RESPONSE ACCESS_TOKEN
    if [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]]; then
        rm -rf -- "$WORK_DIR"
    fi
}
load_configuration() {
    if [[ $# -lt 1 || $# -gt 2 ]]; then
        usage
        exit 2
    fi
    case "$1" in
        --enable) MODE="enable" ;;
        --disable) MODE="disable" ;;
        *) usage; exit 2 ;;
    esac
    if [[ $# -eq 2 ]]; then
        [[ "$MODE" == enable && "$2" == --yes ]] || { usage; exit 2; }
        ASSUME_YES=true
    fi

    for required_command in awk base64 cat curl head helm jq kubectl mktemp openssl sed sleep tail tr; do
        command -v "$required_command" >/dev/null 2>&1 ||
            fail "$required_command is required."
    done
    [[ -f "$ENV_FILE" ]] ||
        fail ".env was not found at $ENV_FILE. Complete Chapter 1 of deploy/obaas/azn-server-runbook.md first."

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

    required_env_value() {
        local variable_name="$1"
        local value

        [[ "$(env_count "$variable_name")" -eq 1 ]] ||
            fail ".env must contain exactly one $variable_name entry. See Chapter 1 of deploy/obaas/azn-server-runbook.md."
        value="$(env_value "$variable_name")"
        [[ -n "$value" ]] ||
            fail ".env variable $variable_name must not be empty. See Chapter 1 of deploy/obaas/azn-server-runbook.md."
        case "$value" in
            *$'\n'* | *$'\r'*) fail ".env variable $variable_name contains a newline." ;;
        esac
        printf '%s' "$value"
    }

    KUBECONFIG_PATH="$(required_env_value CLOUDBANK_KUBECONFIG_PATH)"
    RELEASE="$(required_env_value OBAAS_RELEASE)"
    NAMESPACE="$(required_env_value MICROTX_NAMESPACE)"
    AZN_ISSUER_URI="$(required_env_value AZN_ISSUER_URI)"
    MICROTX_PUBLIC_HOST="$(required_env_value MICROTX_PUBLIC_HOST)"
    MICROTX_PROTOCOL="$(required_env_value MICROTX_PROTOCOL)"
    MICROTX_PUBLIC_PORT="$(required_env_value MICROTX_PUBLIC_PORT)"
    if [[ "$MODE" == enable ]]; then
        MICROTX_CLIENT_SECRET="$(required_env_value AZN_AUTHORIZATION_SERVER_MICROTX_CLIENT_SECRET)"
    fi

    [[ "$KUBECONFIG_PATH" == /* ]] ||
        fail 'CLOUDBANK_KUBECONFIG_PATH must be an absolute path.'
    [[ -f "$KUBECONFIG_PATH" ]] ||
        fail "CLOUDBANK_KUBECONFIG_PATH does not identify an existing file."
    [[ "$RELEASE" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]] ||
        fail 'OBAAS_RELEASE must be a DNS-1123 name.'
    [[ "$NAMESPACE" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]] ||
        fail 'MICROTX_NAMESPACE must be a DNS-1123 name.'
    [[ "$AZN_ISSUER_URI" == 'http://localhost:8080' ]] ||
        fail 'This local port-forward profile requires AZN_ISSUER_URI=http://localhost:8080.'
    [[ "$MICROTX_PUBLIC_HOST" == localhost ]] ||
        fail 'This local port-forward profile requires MICROTX_PUBLIC_HOST=localhost.'
    [[ "$MICROTX_PROTOCOL" == http ]] ||
        fail 'This local port-forward profile requires MICROTX_PROTOCOL=http.'
    [[ "$MICROTX_PUBLIC_PORT" == 5002 ]] ||
        fail 'This local port-forward profile requires MICROTX_PUBLIC_PORT=5002.'

    export KUBECONFIG="$KUBECONFIG_PATH"
    CONTEXT="$(kubectl config current-context)" ||
        fail 'Could not determine the current context from CLOUDBANK_KUBECONFIG_PATH.'
    [[ -n "$CONTEXT" ]] || fail 'The configured kubeconfig has no current context.'
    kubectl config get-contexts "$CONTEXT" >/dev/null ||
        fail "Kubernetes context '$CONTEXT' does not exist in the configured kubeconfig."
    kubectl --context "$CONTEXT" get namespace "$NAMESPACE" >/dev/null 2>&1 ||
        fail "Namespace '$NAMESPACE' was not found on context '$CONTEXT'."

    RELEASE_JSON="$(
        helm list --kube-context "$CONTEXT" --namespace "$NAMESPACE" \
            --filter "^${RELEASE}$" --output json
    )" || fail "Could not inspect Helm release '$RELEASE'."
    [[ "$(jq 'length' <<<"$RELEASE_JSON")" -eq 1 ]] ||
        fail "Expected exactly one Helm release named '$RELEASE' in namespace '$NAMESPACE'."
    OBAAS_CHART="$(jq -r '.[0].chart // empty' <<<"$RELEASE_JSON")"
    OBAAS_APP_VERSION="$(jq -r '.[0].app_version // empty' <<<"$RELEASE_JSON")"
    [[ "$OBAAS_CHART" =~ ^obaas- ]] ||
        fail "Helm release '$RELEASE' is not an OBaaS release."
    obaas_version_at_least "$OBAAS_APP_VERSION" ||
        fail "OBaaS appVersion '$OBAAS_APP_VERSION' must be a semantic version >= 2.1.0."

    AZN_CLUSTER_URL="http://${AZN_SERVICE}.${NAMESPACE}.svc.cluster.local:8080"
    AZN_CONSOLE_REDIRECT_URI="${MICROTX_PROTOCOL}://${MICROTX_PUBLIC_HOST}:${MICROTX_PUBLIC_PORT}/oidc/redirect"
    AZN_CONSOLE_POST_LOGOUT_REDIRECT_URI="${MICROTX_PROTOCOL}://${MICROTX_PUBLIC_HOST}:${MICROTX_PUBLIC_PORT}/consoleui/index.html"
    OIDC_BRIDGE_URL="http://${OIDC_BRIDGE_NAME}.${NAMESPACE}.svc.cluster.local:8080"
    COORDINATOR_CONFIG="${RELEASE}-otmm-config"
    CONSOLE_DEPLOYMENT="${RELEASE}-otmm-console"
    WORKFLOW_DEPLOYMENT="${RELEASE}-otmm-workflow-server"
    COORDINATOR_STATEFULSET="${RELEASE}-otmm-tcs"

    for resource in \
        "configmap/$COORDINATOR_CONFIG" \
        "deployment/$CONSOLE_DEPLOYMENT" \
        "deployment/$WORKFLOW_DEPLOYMENT" \
        "statefulset/$COORDINATOR_STATEFULSET"; do
        kubectl --context "$CONTEXT" --namespace "$NAMESPACE" get "$resource" >/dev/null 2>&1 ||
            fail "Required resource '$resource' was not found in namespace '$NAMESPACE'."
    done

    WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cloudbank-microtx-auth.XXXXXX")"
    chmod 700 "$WORK_DIR"
}

patch_strategic() {
    local resource="$1"
    local patch="$2"
    local field_manager="$3"
    local dry_run="$4"
    local dry_run_args=()

    if [[ "$dry_run" == true ]]; then
        dry_run_args=(--dry-run=server)
    fi
    kubectl --context "$CONTEXT" --namespace "$NAMESPACE" patch "$resource" \
        --type=strategic --field-manager="$field_manager" --patch "$patch" \
        "${dry_run_args[@]}" >/dev/null
}

patch_merge() {
    local resource="$1"
    local patch="$2"
    local dry_run="$3"
    local dry_run_args=()

    if [[ "$dry_run" == true ]]; then
        dry_run_args=(--dry-run=server)
    fi
    kubectl --context "$CONTEXT" --namespace "$NAMESPACE" patch "$resource" \
        --type=merge --patch "$patch" "${dry_run_args[@]}" >/dev/null
}

apply_bridge() {
    local dry_run="$1"
    local dry_run_args=()

    if [[ "$dry_run" == true ]]; then
        dry_run_args=(--dry-run=server)
    fi
    kubectl --context "$CONTEXT" --namespace "$NAMESPACE" apply \
        "${dry_run_args[@]}" --filename - <<<"$BRIDGE_MANIFEST" >/dev/null
}

confirm_action() {
    local prompt="$1"
    local answer=""

    # The unified deployment passes --yes only after its own target confirmation.
    [[ "$ASSUME_YES" == true ]] && return 0
    [[ -t 0 ]] || fail 'Confirmation requires an interactive terminal.'
    printf '%s [y/N] ' "$prompt"
    IFS= read -r answer
    case "$answer" in
        y | Y | yes | YES) ;;
        *) printf 'Action cancelled; no Kubernetes resources were changed.\n'; exit 0 ;;
    esac
}

prepare_console_secrets() {
    local target_exists=false

    kubectl --context "$CONTEXT" --namespace "$NAMESPACE" \
        get "secret/$AZN_CONSOLE_SECRET_NAME" >/dev/null 2>&1 ||
        fail "Source Secret '$AZN_CONSOLE_SECRET_NAME' was not found; deploy azn-server first."
    SOURCE_CLIENT_ID_B64="$(
        kubectl --context "$CONTEXT" --namespace "$NAMESPACE" \
            get "secret/$AZN_CONSOLE_SECRET_NAME" -o jsonpath='{.data.client-id}'
    )"
    SOURCE_CLIENT_SECRET_B64="$(
        kubectl --context "$CONTEXT" --namespace "$NAMESPACE" \
            get "secret/$AZN_CONSOLE_SECRET_NAME" -o jsonpath='{.data.client-secret}'
    )"
    [[ -n "$SOURCE_CLIENT_ID_B64" && -n "$SOURCE_CLIENT_SECRET_B64" ]] ||
        fail "Source Secret '$AZN_CONSOLE_SECRET_NAME' has missing OAuth client keys."

    if kubectl --context "$CONTEXT" --namespace "$NAMESPACE" \
        get "secret/$OAUTH_SECRET_NAME" >/dev/null 2>&1; then
        target_exists=true
        TARGET_CLIENT_ID_B64="$(
            kubectl --context "$CONTEXT" --namespace "$NAMESPACE" \
                get "secret/$OAUTH_SECRET_NAME" -o jsonpath='{.data.clientId}'
        )"
        TARGET_CLIENT_SECRET_B64="$(
            kubectl --context "$CONTEXT" --namespace "$NAMESPACE" \
                get "secret/$OAUTH_SECRET_NAME" -o jsonpath='{.data.clientPassword}'
        )"
    fi

    if [[ "$target_exists" == false ]]; then
        printf "OAuth Secret '%s' will be created from the authoritative Azn Secret.\n" \
            "$OAUTH_SECRET_NAME"
    elif [[ "$SOURCE_CLIENT_ID_B64" == "$TARGET_CLIENT_ID_B64" &&
            "$SOURCE_CLIENT_SECRET_B64" == "$TARGET_CLIENT_SECRET_B64" ]]; then
        printf "OAuth Secret '%s' is already synchronized.\n" "$OAUTH_SECRET_NAME"
    else
        printf "OAuth Secret '%s' will be synchronized from the authoritative Azn Secret.\n" \
            "$OAUTH_SECRET_NAME"
    fi

    if kubectl --context "$CONTEXT" --namespace "$NAMESPACE" \
        get "secret/$COOKIE_SECRET_NAME" >/dev/null 2>&1; then
        printf "Console cookie Secret '%s' exists and will be preserved.\n" "$COOKIE_SECRET_NAME"
    else
        printf "Console cookie Secret '%s' will be generated.\n" "$COOKIE_SECRET_NAME"
    fi
}

apply_console_secrets() {
    local oauth_file="$WORK_DIR/oauth-secret.json"
    local cookie_file="$WORK_DIR/cookie-secret.json"

    if kubectl --context "$CONTEXT" --namespace "$NAMESPACE" \
        get "secret/$OAUTH_SECRET_NAME" >/dev/null 2>&1; then
        printf '{"data":{"clientId":"%s","clientPassword":"%s"}}\n' \
            "$SOURCE_CLIENT_ID_B64" "$SOURCE_CLIENT_SECRET_B64" >"$oauth_file"
        chmod 600 "$oauth_file"
        kubectl --context "$CONTEXT" --namespace "$NAMESPACE" \
            patch "secret/$OAUTH_SECRET_NAME" --type=merge --patch-file "$oauth_file" >/dev/null
        printf "Synchronized OAuth Secret '%s'.\n" "$OAUTH_SECRET_NAME"
    else
        printf '{"apiVersion":"v1","kind":"Secret","metadata":{"name":"%s","namespace":"%s"},"type":"Opaque","data":{"clientId":"%s","clientPassword":"%s"}}\n' \
            "$OAUTH_SECRET_NAME" "$NAMESPACE" "$SOURCE_CLIENT_ID_B64" \
            "$SOURCE_CLIENT_SECRET_B64" >"$oauth_file"
        chmod 600 "$oauth_file"
        kubectl --context "$CONTEXT" create --filename "$oauth_file" >/dev/null
        printf "Created OAuth Secret '%s'.\n" "$OAUTH_SECRET_NAME"
    fi

    if ! kubectl --context "$CONTEXT" --namespace "$NAMESPACE" \
        get "secret/$COOKIE_SECRET_NAME" >/dev/null 2>&1; then
        COOKIE_SECRET_B64="$(openssl rand -hex 32 | tr -d '\n' | base64 | tr -d '\n')"
        printf '{"apiVersion":"v1","kind":"Secret","metadata":{"name":"%s","namespace":"%s"},"type":"Opaque","data":{"secret":"%s"}}\n' \
            "$COOKIE_SECRET_NAME" "$NAMESPACE" "$COOKIE_SECRET_B64" >"$cookie_file"
        chmod 600 "$cookie_file"
        kubectl --context "$CONTEXT" create --filename "$cookie_file" >/dev/null
        printf "Created Console cookie Secret '%s'.\n" "$COOKIE_SECRET_NAME"
    fi

    TARGET_CLIENT_ID_B64="$(
        kubectl --context "$CONTEXT" --namespace "$NAMESPACE" \
            get "secret/$OAUTH_SECRET_NAME" -o jsonpath='{.data.clientId}'
    )"
    TARGET_CLIENT_SECRET_B64="$(
        kubectl --context "$CONTEXT" --namespace "$NAMESPACE" \
            get "secret/$OAUTH_SECRET_NAME" -o jsonpath='{.data.clientPassword}'
    )"
    [[ "$SOURCE_CLIENT_ID_B64" == "$TARGET_CLIENT_ID_B64" &&
       "$SOURCE_CLIENT_SECRET_B64" == "$TARGET_CLIENT_SECRET_B64" ]] ||
        fail "OAuth Secret '$OAUTH_SECRET_NAME' is not synchronized."
}

render_enable_configuration() {
    local azn_authority="${AZN_CLUSTER_URL#*://}"
    local live_issuer

    live_issuer="$(kubectl --context "$CONTEXT" --namespace "$NAMESPACE" \
        get "deployment/$AZN_DEPLOYMENT" \
        -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="AZN_ISSUER_URI")].value}')"
    [[ "$live_issuer" == "$AZN_ISSUER_URI" ]] ||
        fail 'Azn issuer differs from .env; deploy azn-server with the configured issuer before securing MicroTx. Changing issuer here would invalidate BFF/service tokens.'

    [[ -f "$BRIDGE_TEMPLATE" ]] || fail 'oidc-bridge.yaml.template was not found.'
    BRIDGE_MANIFEST="$(<"$BRIDGE_TEMPLATE")"
    BRIDGE_MANIFEST="${BRIDGE_MANIFEST//__NAMESPACE__/$NAMESPACE}"
    BRIDGE_MANIFEST="${BRIDGE_MANIFEST//__AZN_CLUSTER_URL__/$AZN_CLUSTER_URL}"
    BRIDGE_MANIFEST="${BRIDGE_MANIFEST//__AZN_AUTHORITY__/$azn_authority}"
    BRIDGE_MANIFEST="${BRIDGE_MANIFEST//__AZN_ISSUER_URI__/$AZN_ISSUER_URI}"
    BRIDGE_MANIFEST="${BRIDGE_MANIFEST//__OIDC_BRIDGE_URL__/$OIDC_BRIDGE_URL}"

    AZN_CONTAINER="$(
        kubectl --context "$CONTEXT" --namespace "$NAMESPACE" \
            get "deployment/$AZN_DEPLOYMENT" \
            -o jsonpath='{.spec.template.spec.containers[0].name}'
    )"
    [[ -n "$AZN_CONTAINER" ]] ||
        fail "Could not determine the container in deployment/$AZN_DEPLOYMENT."

    AZN_SECRET_PATCH="$(cat <<EOF
{"stringData":{"redirect-uri":"$AZN_CONSOLE_REDIRECT_URI","post-logout-redirect-uri":"$AZN_CONSOLE_POST_LOGOUT_REDIRECT_URI"}}
EOF
)"
    AZN_DEPLOYMENT_PATCH="$(cat <<EOF
{"spec":{"template":{"spec":{"containers":[{"name":"$AZN_CONTAINER","env":[{"name":"AZN_ISSUER_URI","value":"$AZN_ISSUER_URI"}]}]}}}}
EOF
)"
    COORDINATOR_PATCH="$(cat <<EOF
{"data":{"AUTHORIZATION_ENABLED":"true","AUTHORIZATION_TOKEN_PROPAGATION_ENABLED":"false","IDENTITY_PROVIDER_SERVER_TYPE":"other","IDENTITY_PROVIDER_URL":"$AZN_CLUSTER_URL","IDENTITY_PROVIDER_CLIENT_ID":"$OAUTH_SECRET_NAME","ADMIN_USER_ROLES":"ROLE_ADMIN","ADMIN_USER_ROLES_PATH":"roles","REQUEST_WITH_NO_JWT":"DENY","JWT_ISSUER":"$AZN_ISSUER_URI","JWT_JWKS_URI":"$AZN_CLUSTER_URL/oauth2/jwks"}}
EOF
)"
    CONSOLE_PATCH="$(cat <<EOF
{"spec":{"template":{"spec":{"volumes":[{"name":"oidc-diagnostics","\$patch":"delete"}],"containers":[{"name":"console","volumeMounts":[{"mountPath":"/etc/microtx-oidc-diagnostics","\$patch":"delete"}],"env":[{"name":"TMM_ADMIN_USER_ROLE_NAMES","value":"ROLE_ADMIN"},{"name":"TMM_ROLES_PATH","value":"roles"},{"name":"SECURITY_PROPERTIES_OIDC_IDENTITY_URI","value":"$OIDC_BRIDGE_URL"},{"name":"SECURITY_PROPERTIES_COOKIE_ENCRYPTION_PASSWORD","valueFrom":{"secretKeyRef":{"name":"$COOKIE_SECRET_NAME","key":"secret"}}},{"name":"SECURITY_PROPERTIES_COOKIE_ENCRYPTION_ENABLED","value":"true"},{"name":"SECURITY_PROPERTIES_OIDC_CLIENT_ID","valueFrom":{"secretKeyRef":{"name":"$OAUTH_SECRET_NAME","key":"clientId"}}},{"name":"SECURITY_PROPERTIES_OIDC_CLIENT_SECRET","valueFrom":{"secretKeyRef":{"name":"$OAUTH_SECRET_NAME","key":"clientPassword"}}},{"name":"SECURITY_PROPERTIES_OIDC_ISSUER","value":"$AZN_ISSUER_URI"},{"name":"SECURITY_PROPERTIES_OIDC_AUDIENCE","value":"cloudbank-api"},{"name":"SECURITY_PROPERTIES_OIDC_BASE_SCOPES","value":"openid cloudbank.read cloudbank.write"},{"name":"SECURITY_PROVIDERS_1_OIDC_TOKEN_ENDPOINT_AUTH","\$patch":"delete"},{"name":"JAVA_TOOL_OPTIONS","value":"-Dsecurity.providers.1.oidc.token-endpoint-auth=CLIENT_SECRET_POST"},{"name":"SECURITY_PROPERTIES_FRONTEND_URI","value":"$MICROTX_PROTOCOL://$MICROTX_PUBLIC_HOST:$MICROTX_PUBLIC_PORT"},{"name":"CONDUCTOR_FRONTEND_ENDPOINT","value":"$MICROTX_PROTOCOL://$MICROTX_PUBLIC_HOST:$MICROTX_PUBLIC_PORT"},{"name":"SECURITY_ENABLED","value":"true"}]}]}}}}
EOF
)"
    WORKFLOW_PATCH="$(cat <<EOF
{"spec":{"template":{"spec":{"containers":[{"name":"server","env":[{"name":"CONDUCTOR_SECURITY_ENABLED","value":"true"},{"name":"SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_ISSUER_URI","value":"$AZN_ISSUER_URI"},{"name":"SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_JWK_SET_URI","value":"$AZN_CLUSTER_URL/oauth2/jwks"},{"name":"POLICY_SECURITY_CLAIMS_ROLE_PATHS","value":"roles"},{"name":"POLICY_SECURITY_ROLE_SUPER_ADMIN","value":"ROLE_ADMIN"},{"name":"POLICY_SECURITY_ROLE_ADMIN","value":"ROLE_ADMIN"},{"name":"POLICY_SECURITY_ROLE_USER","value":"microtx-conductor-user"},{"name":"POLICY_SECURITY_ROLE_READ_ONLY_USER","value":"ROLE_USER"},{"name":"POLICY_SECURITY_ROLE_METADATA_MANAGER","value":"ROLE_CONFIG_EDITOR"},{"name":"POLICY_SECURITY_ROLE_WORKER","value":"microtx-conductor-worker"}]}]}}}}
EOF
)"
}

preview_enable() {
    patch_merge "secret/$AZN_CONSOLE_SECRET_NAME" "$AZN_SECRET_PATCH" true
    # Reuse Helm's field manager for this chart-owned value so the next Azn
    # server-side upgrade does not conflict with a separate kubectl owner.
    patch_strategic "deployment/$AZN_DEPLOYMENT" "$AZN_DEPLOYMENT_PATCH" helm true
    apply_bridge true
    patch_strategic "configmap/$COORDINATOR_CONFIG" "$COORDINATOR_PATCH" kubectl-patch true
    patch_strategic "deployment/$CONSOLE_DEPLOYMENT" "$CONSOLE_PATCH" kubectl-patch true
    patch_strategic "deployment/$WORKFLOW_DEPLOYMENT" "$WORKFLOW_PATCH" kubectl-patch true
}

apply_enable() {
    apply_console_secrets
    patch_merge "secret/$AZN_CONSOLE_SECRET_NAME" "$AZN_SECRET_PATCH" false
    patch_strategic "deployment/$AZN_DEPLOYMENT" "$AZN_DEPLOYMENT_PATCH" helm false
    apply_bridge false
    patch_strategic "configmap/$COORDINATOR_CONFIG" "$COORDINATOR_PATCH" kubectl-patch false
    patch_strategic "deployment/$WORKFLOW_DEPLOYMENT" "$WORKFLOW_PATCH" kubectl-patch false

    kubectl --context "$CONTEXT" --namespace "$NAMESPACE" rollout restart \
        "deployment/$AZN_DEPLOYMENT" >/dev/null
    kubectl --context "$CONTEXT" --namespace "$NAMESPACE" rollout status \
        "deployment/$AZN_DEPLOYMENT" --timeout=10m
    kubectl --context "$CONTEXT" --namespace "$NAMESPACE" rollout restart \
        "deployment/$OIDC_BRIDGE_NAME" >/dev/null
    kubectl --context "$CONTEXT" --namespace "$NAMESPACE" rollout status \
        "deployment/$OIDC_BRIDGE_NAME" --timeout=5m
    # Helidon caches discovery. Do not start a Console using an old Azn/bridge.
    verify_bridge_discovery
    patch_strategic "deployment/$CONSOLE_DEPLOYMENT" "$CONSOLE_PATCH" kubectl-patch false
    kubectl --context "$CONTEXT" --namespace "$NAMESPACE" rollout restart \
        "deployment/$CONSOLE_DEPLOYMENT" >/dev/null
    kubectl --context "$CONTEXT" --namespace "$NAMESPACE" rollout status \
        "deployment/$CONSOLE_DEPLOYMENT" --timeout=10m
    kubectl --context "$CONTEXT" --namespace "$NAMESPACE" rollout restart \
        "statefulset/$COORDINATOR_STATEFULSET" >/dev/null
    kubectl --context "$CONTEXT" --namespace "$NAMESPACE" rollout status \
        "deployment/$WORKFLOW_DEPLOYMENT" --timeout=10m
    kubectl --context "$CONTEXT" --namespace "$NAMESPACE" rollout status \
        "statefulset/$COORDINATOR_STATEFULSET" --timeout=10m
}

start_port_forward() {
    local service_name="$1"
    local remote_port="$2"
    local log_file="$3"
    local pid_variable="$4"
    local port_variable="$5"
    local pid
    local attempt
    local local_port=""

    # Endpoint selection can briefly lag behind a successful pod rollout.
    for attempt in 1 2 3; do
        kubectl --context "$CONTEXT" --namespace "$NAMESPACE" port-forward \
            --address 127.0.0.1 "service/$service_name" \
            ":${remote_port}" >"$log_file" 2>&1 &
        pid=$!
        printf -v "$pid_variable" '%s' "$pid"
        for _ in {1..50}; do
            local_port="$(
                sed -n "s/^Forwarding from 127\\.0\\.0\\.1:\\([0-9][0-9]*\\) -> ${remote_port}$/\\1/p" \
                    "$log_file" | head -n 1
            )"
            if [[ -n "$local_port" ]] && kill -0 "$pid" >/dev/null 2>&1; then
                printf -v "$port_variable" '%s' "$local_port"
                return 0
            fi
            kill -0 "$pid" >/dev/null 2>&1 || break
            sleep 0.2
        done
        kill "$pid" >/dev/null 2>&1 || true
        wait "$pid" >/dev/null 2>&1 || true
        printf -v "$pid_variable" '%s' ''
    done
    fail "Could not start the port-forward for service/$service_name after three attempts; inspect Kubernetes endpoints/events."
}

curl_config_escape() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '%s' "$value"
}

verify_authenticated_workflow_api() {
    local client_id_escaped
    local client_secret_escaped
    local token_escaped
    local status

    start_port_forward "$AZN_SERVICE" 8080 \
        "$WORK_DIR/azn-port-forward.log" AZN_FORWARD_PID AZN_FORWARD_PORT
    start_port_forward "$WORKFLOW_DEPLOYMENT" 9010 \
        "$WORK_DIR/workflow-port-forward.log" WORKFLOW_FORWARD_PID WORKFLOW_FORWARD_PORT

    client_id_escaped="$(curl_config_escape "$WORKFLOW_CLIENT_ID")"
    client_secret_escaped="$(curl_config_escape "$MICROTX_CLIENT_SECRET")"
    TOKEN_RESPONSE="$(
        printf 'user = "%s:%s"\n' "$client_id_escaped" "$client_secret_escaped" |
            curl --config - --silent --show-error --fail --max-time 15 \
                --request POST "http://127.0.0.1:${AZN_FORWARD_PORT}/oauth2/token" \
                --data-urlencode grant_type=client_credentials \
                --data-urlencode scope=microtx.workflow
    )" || fail 'Could not obtain the MicroTx service token through the local Azn port-forward.'
    ACCESS_TOKEN="$(jq --raw-output '.access_token // empty' <<<"$TOKEN_RESPONSE")"
    [[ -n "$ACCESS_TOKEN" ]] || fail 'Azn did not return a MicroTx access token.'
    token_escaped="$(curl_config_escape "$ACCESS_TOKEN")"
    status="$(
        printf 'header = "Authorization: Bearer %s"\n' "$token_escaped" |
            curl --config - --silent --show-error --max-time 15 \
                --output /dev/null --write-out '%{http_code}' \
                "http://127.0.0.1:${WORKFLOW_FORWARD_PORT}/workflow-server/api/tasks/poll/__microtx_auth_probe__?workerid=oke-auth-probe&timeout=0"
    )" || fail 'Could not call the Workflow API through the local port-forward.'
    case "$status" in
        200 | 204)
            printf 'PASS: Workflow API accepted an authenticated worker request (HTTP %s).\n' "$status"
            ;;
        401 | 403)
            fail "Workflow API rejected the service token (HTTP $status)."
            ;;
        *)
            fail "Workflow API authentication probe returned unexpected HTTP $status."
            ;;
    esac
}

verify_enable() {
    local console_token_auth
    local console_identity_uri
    local live_workflow_issuer
    local live_azn_issuer

    console_token_auth="$(
        kubectl --context "$CONTEXT" --namespace "$NAMESPACE" \
            get "deployment/$CONSOLE_DEPLOYMENT" \
            -o jsonpath='{.spec.template.spec.containers[?(@.name=="console")].env[?(@.name=="JAVA_TOOL_OPTIONS")].value}'
    )"
    [[ "$console_token_auth" == '-Dsecurity.providers.1.oidc.token-endpoint-auth=CLIENT_SECRET_POST' ]] ||
        fail 'The Console does not contain the required client_secret_post setting.'
    console_identity_uri="$(
        kubectl --context "$CONTEXT" --namespace "$NAMESPACE" \
            get "deployment/$CONSOLE_DEPLOYMENT" \
            -o jsonpath='{.spec.template.spec.containers[?(@.name=="console")].env[?(@.name=="SECURITY_PROPERTIES_OIDC_IDENTITY_URI")].value}'
    )"
    [[ "$console_identity_uri" == "$OIDC_BRIDGE_URL" ]] ||
        fail 'The Console does not use the internal OIDC bridge.'
    live_workflow_issuer="$(
        kubectl --context "$CONTEXT" --namespace "$NAMESPACE" \
            get "deployment/$WORKFLOW_DEPLOYMENT" \
            -o jsonpath='{.spec.template.spec.containers[?(@.name=="server")].env[?(@.name=="SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_ISSUER_URI")].value}'
    )"
    [[ "$live_workflow_issuer" == "$AZN_ISSUER_URI" ]] ||
        fail 'The Workflow Server JWT issuer does not match AZN_ISSUER_URI.'
    live_azn_issuer="$(
        kubectl --context "$CONTEXT" --namespace "$NAMESPACE" \
            get "deployment/$AZN_DEPLOYMENT" \
            -o jsonpath="{.spec.template.spec.containers[?(@.name==\"$AZN_CONTAINER\")].env[?(@.name==\"AZN_ISSUER_URI\")].value}"
    )"
    [[ "$live_azn_issuer" == "$AZN_ISSUER_URI" ]] ||
        fail 'The Azn deployment does not publish the local port-forward issuer.'
    verify_bridge_discovery
    verify_console_redirect
    verify_authenticated_workflow_api
}

verify_bridge_discovery() {
    local live_bridge_discovery
    live_bridge_discovery="$(
        kubectl --context "$CONTEXT" --namespace "$NAMESPACE" \
            exec "deployment/$CONSOLE_DEPLOYMENT" -c console -- \
            curl --silent --show-error --fail \
                "$OIDC_BRIDGE_URL/.well-known/openid-configuration"
    )" || fail 'The Console pod could not read discovery through the internal OIDC bridge.'
    [[ "$(jq --raw-output '.issuer // empty' <<<"$live_bridge_discovery")" == "$AZN_ISSUER_URI" ]] ||
        fail 'The OIDC bridge discovery document does not preserve the Azn issuer.'
    [[ "$(jq --raw-output '.authorization_endpoint // empty' <<<"$live_bridge_discovery")" == "$AZN_ISSUER_URI/oauth2/authorize" ]] ||
        fail 'The OIDC bridge discovery document has an invalid browser authorization endpoint.'
    [[ "$(jq --raw-output '.token_endpoint // empty' <<<"$live_bridge_discovery")" == "$OIDC_BRIDGE_URL/oauth2/token" ]] ||
        fail 'The OIDC bridge discovery document has an invalid token endpoint.'
    [[ "$(jq --raw-output '.jwks_uri // empty' <<<"$live_bridge_discovery")" == "$OIDC_BRIDGE_URL/oauth2/jwks" ]] ||
        fail 'The OIDC bridge discovery document has an invalid JWKS endpoint.'
}

verify_console_redirect() {
    local redirect
    # Capture only the redirect URL, never headers/cookies, codes, or credentials.
    redirect="$(kubectl --context "$CONTEXT" --namespace "$NAMESPACE" \
        exec "deployment/$CONSOLE_DEPLOYMENT" -c console -- \
        curl --silent --show-error --max-time 15 --output /dev/null \
        --write-out '%{redirect_url}' --header "Host: $MICROTX_PUBLIC_HOST:$MICROTX_PUBLIC_PORT" \
        http://127.0.0.1:8080/consoleui/)" ||
        fail 'Could not check the Console OIDC redirect.'
    [[ "$redirect" == "$AZN_ISSUER_URI/oauth2/authorize?"* ]] ||
        fail 'The Console browser redirect does not use the configured Azn issuer.'
    printf 'PASS: Console browser redirect uses the configured Azn issuer.\n'
}

verify_consumer_issuers() {
    local mismatches
    mismatches="$(kubectl --context "$CONTEXT" --namespace "$NAMESPACE" get deployments -o json |
        jq -r --arg issuer "$AZN_ISSUER_URI" '
            .items[] | .metadata.name as $name |
            [.spec.template.spec.containers[].env[]? |
                select(.name == "AZN_ISSUER_URI" or .name == "BFF_ISSUER_URI") |
                select(.value != $issuer)] | select(length > 0) | $name')" ||
        fail 'Could not check the JWT issuer used by existing services.'
    [[ -z "$mismatches" ]] ||
        fail "JWT issuer mismatch in deployments: $mismatches. Redeploy CloudBank services and BFF with the configured issuer before enabling MicroTx."
}

render_disable_configuration() {
    COORDINATOR_PATCH='{"data":{"AUTHORIZATION_ENABLED":"false","AUTHORIZATION_TOKEN_PROPAGATION_ENABLED":"false","IDENTITY_PROVIDER_SERVER_TYPE":"","IDENTITY_PROVIDER_URL":"","IDENTITY_PROVIDER_CLIENT_ID":"","ADMIN_USER_ROLES":"","ADMIN_USER_ROLES_PATH":"","REQUEST_WITH_NO_JWT":"ALLOW","JWT_ISSUER":"","JWT_JWKS_URI":""}}'
    CONSOLE_PATCH='{"spec":{"template":{"spec":{"containers":[{"name":"console","env":[{"name":"SECURITY_ENABLED","value":"false"}]}]}}}}'
    WORKFLOW_PATCH='{"spec":{"template":{"spec":{"containers":[{"name":"server","env":[{"name":"CONDUCTOR_SECURITY_ENABLED","value":"false"},{"name":"SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_ISSUER_URI","$patch":"delete"},{"name":"SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_JWK_SET_URI","$patch":"delete"},{"name":"POLICY_SECURITY_CLAIMS_ROLE_PATHS","$patch":"delete"},{"name":"POLICY_SECURITY_ROLE_SUPER_ADMIN","$patch":"delete"},{"name":"POLICY_SECURITY_ROLE_ADMIN","$patch":"delete"},{"name":"POLICY_SECURITY_ROLE_USER","$patch":"delete"},{"name":"POLICY_SECURITY_ROLE_READ_ONLY_USER","$patch":"delete"},{"name":"POLICY_SECURITY_ROLE_METADATA_MANAGER","$patch":"delete"},{"name":"POLICY_SECURITY_ROLE_WORKER","$patch":"delete"}]}]}}}}'
}

preview_disable() {
    patch_strategic "configmap/$COORDINATOR_CONFIG" "$COORDINATOR_PATCH" kubectl-patch true
    patch_strategic "deployment/$CONSOLE_DEPLOYMENT" "$CONSOLE_PATCH" kubectl-patch true
    patch_strategic "deployment/$WORKFLOW_DEPLOYMENT" "$WORKFLOW_PATCH" kubectl-patch true
}

apply_disable() {
    patch_strategic "configmap/$COORDINATOR_CONFIG" "$COORDINATOR_PATCH" kubectl-patch false
    patch_strategic "deployment/$CONSOLE_DEPLOYMENT" "$CONSOLE_PATCH" kubectl-patch false
    patch_strategic "deployment/$WORKFLOW_DEPLOYMENT" "$WORKFLOW_PATCH" kubectl-patch false
    kubectl --context "$CONTEXT" --namespace "$NAMESPACE" rollout restart \
        "statefulset/$COORDINATOR_STATEFULSET" >/dev/null
    kubectl --context "$CONTEXT" --namespace "$NAMESPACE" rollout status \
        "deployment/$CONSOLE_DEPLOYMENT" --timeout=10m
    kubectl --context "$CONTEXT" --namespace "$NAMESPACE" rollout status \
        "deployment/$WORKFLOW_DEPLOYMENT" --timeout=10m
    kubectl --context "$CONTEXT" --namespace "$NAMESPACE" rollout status \
        "statefulset/$COORDINATOR_STATEFULSET" --timeout=10m
}

workflow_api_status() {
    local method="$1"
    local path="$2"
    local payload="${3:-}"
    local curl_args=(
        --silent --show-error --max-time 15 --output /dev/null
        --write-out '%{http_code}' --request "$method"
    )

    if [[ -n "$payload" ]]; then
        curl_args+=(--header 'Content-Type: application/json' --data "$payload")
    fi
    kubectl --context "$CONTEXT" --namespace "$NAMESPACE" exec \
        "deployment/$WORKFLOW_DEPLOYMENT" -c server -- \
        curl "${curl_args[@]}" "http://127.0.0.1:9010/workflow-server/api$path"
}

verify_anonymous_route() {
    local method="$1"
    local path="$2"
    local payload="$3"
    local description="$4"
    local status

    status="$(workflow_api_status "$method" "$path" "$payload")" ||
        fail "Could not probe anonymous $description access in the Workflow Server pod."
    case "$method:$status" in
        GET:200 | POST:200 | POST:204 | POST:400 | POST:422 | PUT:200 | PUT:204 | PUT:400 | PUT:422)
            printf 'PASS: Anonymous %s access reached the Workflow API (HTTP %s).\n' \
                "$description" "$status"
            ;;
        *:401 | *:403)
            fail "Anonymous $description access is still protected (HTTP $status)."
            ;;
        *)
            fail "Anonymous $description probe returned unexpected HTTP $status."
            ;;
    esac
}

verify_disable() {
    local live_workflow_security

    live_workflow_security="$(
        kubectl --context "$CONTEXT" --namespace "$NAMESPACE" \
            get "deployment/$WORKFLOW_DEPLOYMENT" \
            -o jsonpath='{.spec.template.spec.containers[?(@.name=="server")].env[?(@.name=="CONDUCTOR_SECURITY_ENABLED")].value}'
    )"
    [[ "$live_workflow_security" == false ]] ||
        fail 'The Workflow Server does not have CONDUCTOR_SECURITY_ENABLED=false.'

    # Invalid payloads reach authorization-protected routes without creating or
    # changing workflow definitions. Validation errors prove security was passed.
    verify_anonymous_route GET '/metadata/workflow' '' 'metadata-read'
    verify_anonymous_route POST '/metadata/workflow/validate' '{}' 'workflow-validation'
    verify_anonymous_route PUT '/metadata/workflow' '[]' 'workflow-deployment-write'
}

main() {
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' HUP TERM
    load_configuration "$@"
    printf '%s\n' \
        'MicroTx authentication target' \
        "  action:           $MODE" \
        "  kubeconfig:       $KUBECONFIG_PATH" \
        "  context:          $CONTEXT" \
        "  namespace:        $NAMESPACE" \
        "  OBaaS release:    $RELEASE ($OBAAS_APP_VERSION)"

    if [[ "$MODE" == enable ]]; then
        kubectl --context "$CONTEXT" --namespace "$NAMESPACE" \
            get "service/$AZN_SERVICE" "deployment/$AZN_DEPLOYMENT" >/dev/null 2>&1 ||
            fail 'azn-server Service or Deployment was not found; deploy azn-server first.'
        prepare_console_secrets
        render_enable_configuration
        verify_consumer_issuers
        preview_enable
        printf 'Server-side validation passed; no Kubernetes resources have been changed.\n'
        confirm_action 'Enable Azn authentication on MicroTx for this target?'
        apply_enable
        verify_enable
        printf 'SUCCESS: MicroTx authentication is enabled and the authenticated Workflow API check passed.\n'
    else
        render_disable_configuration
        preview_disable
        printf '%s\n' \
            'WARNING: This development-recovery action permits anonymous MicroTx Workflow API access.' \
            'Server-side validation passed; no Kubernetes resources have been changed.'
        confirm_action 'Remove authentication from MicroTx on this development target?'
        apply_disable
        verify_disable
        printf '%s\n' \
            'SUCCESS: MicroTx authentication is disabled for development recovery.' \
            'Azn, the OIDC bridge, and OAuth Secrets were retained. Restore protection with --enable.'
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
