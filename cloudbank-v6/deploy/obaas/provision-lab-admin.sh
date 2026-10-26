#!/usr/bin/env bash
# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0.
set -Eeuo pipefail
set +x

readonly LAB_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LAB_ROOT="$(cd "$LAB_SCRIPT_DIR/../.." && pwd)"
readonly LAB_ENV_FILE="${CLOUDBANK_ENV_FILE:-$LAB_ROOT/.env}"
LAB_WORK_DIR=""
LAB_FORWARD_PID=""
LAB_PORT=""
LAB_CONTEXT=""
LAB_NAMESPACE=""
LAB_ISSUER=""
LAB_PRINCIPAL_ID=""
LAB_DB_SECRET=""
LAB_WALLET_SECRET=""
LAB_PULL_SECRET=""
LAB_IMAGE=""
LAB_NAME=""
LAB_CHECK_IDENTITY=false
LAB_ASSUME_YES=false
LAB_CREATED_CONFIG=false
LAB_CREATED_IDENTITY=false
LAB_CREATED_JOB=false

lab_fail() { printf 'ERROR: %s\n' "$*" >&2; exit 2; }
lab_usage() {
    cat <<'EOF'
Usage: provision-lab-admin.sh [--check-identity] [--yes] [--image IMAGE]

Provision the existing obaas-admin identity for all CloudBank applications.
Reads the target and existing admin password from the protected root .env.
--check-identity performs only the authenticated identity/issuer lookup.
--yes uses a caller's prior deployment confirmation. Otherwise, apply prompts.
--image selects a published schema-init image; by default reuse the image tag
of the installed loan service. No application rebuild or restart is required.
EOF
}

lab_env_value() {
    awk -F= -v key="$1" '
        $1 == key { count++; value=substr($0,index($0,"=")+1) }
        END { if (count != 1 || value == "") exit 1; print value }
    ' "$LAB_ENV_FILE"
}

lab_config_escape() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '%s' "$value"
}

lab_cleanup() {
    local status=$?
    trap - EXIT
    if [[ -n "$LAB_FORWARD_PID" ]]; then
        kill "$LAB_FORWARD_PID" >/dev/null 2>&1 || true
        wait "$LAB_FORWARD_PID" >/dev/null 2>&1 || true
    fi
    # Only remove per-run resources that this invocation successfully created.
    if [[ "$LAB_CREATED_JOB" == true ]]; then
        kubectl --context "$LAB_CONTEXT" -n "$LAB_NAMESPACE" delete job "$LAB_NAME" \
            --wait=true --timeout=30s >/dev/null 2>&1 || true
    fi
    if [[ "$LAB_CREATED_IDENTITY" == true ]]; then
        kubectl --context "$LAB_CONTEXT" -n "$LAB_NAMESPACE" delete secret "$LAB_NAME" \
            >/dev/null 2>&1 || true
    fi
    if [[ "$LAB_CREATED_CONFIG" == true ]]; then
        kubectl --context "$LAB_CONTEXT" -n "$LAB_NAMESPACE" delete configmap "$LAB_NAME" \
            >/dev/null 2>&1 || true
    fi
    [[ -z "$LAB_WORK_DIR" ]] || rm -rf -- "$LAB_WORK_DIR"
    unset LAB_PRINCIPAL_ID
    exit "$status"
}

lab_load_target() {
    local kubeconfig
    local deployment
    local live_issuer
    [[ -r "$LAB_ENV_FILE" ]] || lab_fail 'The protected .env file is missing.'
    kubeconfig="$(lab_env_value CLOUDBANK_KUBECONFIG_PATH)" || lab_fail 'Missing kubeconfig input.'
    [[ "$kubeconfig" == /* && -r "$kubeconfig" ]] || lab_fail 'Invalid kubeconfig path.'
    export KUBECONFIG="$kubeconfig"
    LAB_CONTEXT="$(kubectl config current-context)"
    LAB_NAMESPACE="$(lab_env_value MICROTX_NAMESPACE)" || lab_fail 'Missing namespace input.'
    LAB_ISSUER="$(lab_env_value AZN_ISSUER_URI)" || lab_fail 'Missing issuer input.'
    LAB_PULL_SECRET="$(lab_env_value IMAGE_PULL_SECRET)" || lab_fail 'Missing image pull Secret input.'
    [[ -n "$LAB_CONTEXT" && "$LAB_NAMESPACE" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]] || lab_fail 'Invalid target.'
    [[ "$LAB_ISSUER" =~ ^https?://[A-Za-z0-9.-]+(:[0-9]+)?$ ]] || lab_fail 'Invalid issuer.'
    deployment="$(kubectl --context "$LAB_CONTEXT" -n "$LAB_NAMESPACE" get deployment azn-server -o json)"
    live_issuer="$(jq -er '[.spec.template.spec.containers[].env[]? | select(.name=="AZN_ISSUER_URI") | .value] | unique | select(length==1) | .[0]' <<<"$deployment")"
    [[ "$live_issuer" == "$LAB_ISSUER" ]] || lab_fail 'The live Azn issuer differs from .env.'
    LAB_DB_SECRET="$(jq -er '[.spec.template.spec.containers[].env[]? |
        select(.name=="AZN_LIQUIBASE_USERNAME" or .name=="AZN_LIQUIBASE_PASSWORD") |
        .valueFrom.secretKeyRef.name] | select(length==2) | unique | select(length==1) | .[0]' <<<"$deployment")" ||
        lab_fail 'Could not identify the existing database bootstrap Secret.'
    LAB_WALLET_SECRET="$(jq -er '. as $d |
        [.spec.template.spec.containers[].volumeMounts[]? | select(.mountPath=="/oracle/tnsadmin") | .name] |
        unique | select(length==1) | .[0] as $v |
        $d.spec.template.spec.volumes[] | select(.name==$v) | .secret.secretName' <<<"$deployment")" ||
        lab_fail 'Could not identify the existing ADB wallet Secret.'
}

lab_lookup_identity() {
    local password
    local credential
    local metadata
    local attempt
    password="$(lab_env_value AZN_BOOTSTRAP_USERS_ADMIN_PASSWORD)" || lab_fail 'Missing lab admin credential.'
    case "$password" in *$'\n'* | *$'\r'*) lab_fail 'Invalid admin credential format.' ;; esac
    kubectl --context "$LAB_CONTEXT" -n "$LAB_NAMESPACE" port-forward --address 127.0.0.1 \
        service/azn-server :8080 >"$LAB_WORK_DIR/forward.log" 2>&1 &
    LAB_FORWARD_PID=$!
    for attempt in {1..100}; do
        LAB_PORT="$(sed -n 's/^Forwarding from 127\.0\.0\.1:\([0-9][0-9]*\) -> 8080$/\1/p' "$LAB_WORK_DIR/forward.log" | head -n 1)"
        [[ -z "$LAB_PORT" ]] || break
        kill -0 "$LAB_FORWARD_PID" >/dev/null 2>&1 || lab_fail 'Azn port-forward failed.'
        sleep 0.2
    done
    [[ -n "$LAB_PORT" ]] || lab_fail 'Azn port-forward did not become ready.'
    metadata="$(curl --silent --show-error --fail --max-time 15 \
        "http://127.0.0.1:$LAB_PORT/.well-known/openid-configuration")"
    [[ "$(jq -er .issuer <<<"$metadata")" == "$LAB_ISSUER" ]] || lab_fail 'Azn discovery issuer mismatch.'
    credential="$(lab_config_escape "obaas-admin:$password")"
    LAB_PRINCIPAL_ID="$(printf 'user = "%s"\n' "$credential" |
        curl --config - --silent --show-error --fail --max-time 15 \
            "http://127.0.0.1:$LAB_PORT/user/api/v1/findUser?username=obaas-admin" |
        jq -er '[.[] | select(.username=="obaas-admin")] |
            select(length==1) | .[0] |
            select((.roles | split(",") | map(gsub("^\\s+|\\s+$"; "")) | index("ROLE_ADMIN")) != null) |
            .principalId')" || lab_fail 'Could not resolve exactly one lab owner with ROLE_ADMIN.'
    unset password credential metadata
    [[ "$LAB_PRINCIPAL_ID" =~ ^[A-Za-z0-9_-]{1,80}$ ]] || lab_fail 'Invalid lab owner principal ID.'
    kill "$LAB_FORWARD_PID" >/dev/null 2>&1 || true
    wait "$LAB_FORWARD_PID" >/dev/null 2>&1 || true
    LAB_FORWARD_PID=""
    printf 'PASS: lab owner identity and issuer verified through the internal admin API.\n'
}

lab_render() {
    local loan_image
    if [[ -z "$LAB_IMAGE" ]]; then
        loan_image="$(kubectl --context "$LAB_CONTEXT" -n "$LAB_NAMESPACE" get deployment loan-application-service \
            -o jsonpath='{.spec.template.spec.containers[0].image}')"
        [[ "$loan_image" == */loan-application-service:* ]] || lab_fail 'Set --image to a published schema-init image.'
        LAB_IMAGE="${loan_image%/loan-application-service:*}/cloudbank-schema-init:${loan_image##*:}"
    fi
    [[ "$LAB_IMAGE" =~ ^[A-Za-z0-9._:/@-]+$ && "$LAB_IMAGE" == */cloudbank-schema-init:* && "${LAB_IMAGE##*:}" != latest ]] ||
        lab_fail 'Use an immutable published cloudbank-schema-init image.'
    LAB_NAME="cloudbank-lab-admin-$(date -u +%s)-$$"
    jq -n --arg name "$LAB_NAME" --arg ns "$LAB_NAMESPACE" \
        --rawfile runner "$LAB_SCRIPT_DIR/lib/run-lab-admin-bootstrap.sh" \
        --rawfile sql "$LAB_ROOT/src/schema/admin/003-lab-admin-access.sql" \
        '{apiVersion:"v1",kind:"ConfigMap",metadata:{name:$name,namespace:$ns},
          data:{"run.sh":$runner,"provision.sql":$sql}}' >"$LAB_WORK_DIR/config.json"
    jq -n --arg name "$LAB_NAME" --arg ns "$LAB_NAMESPACE" --arg id "$LAB_PRINCIPAL_ID" --arg issuer "$LAB_ISSUER" \
        '{apiVersion:"v1",kind:"Secret",metadata:{name:$name,namespace:$ns},type:"Opaque",
          data:{principalId:($id|@base64),issuer:($issuer|@base64)}}' >"$LAB_WORK_DIR/identity.json"
    jq -n --arg name "$LAB_NAME" --arg ns "$LAB_NAMESPACE" --arg image "$LAB_IMAGE" \
        --arg db "$LAB_DB_SECRET" --arg wallet "$LAB_WALLET_SECRET" --arg pull "$LAB_PULL_SECRET" '
        def secretEnv($n;$s;$k): {name:$n,valueFrom:{secretKeyRef:{name:$s,key:$k}}};
        {apiVersion:"batch/v1",kind:"Job",metadata:{name:$name,namespace:$ns,
          labels:{"app.kubernetes.io/name":"cloudbank-lab-admin","app.kubernetes.io/part-of":"cloudbank-ai"}},
         spec:{backoffLimit:0,activeDeadlineSeconds:480,ttlSecondsAfterFinished:3600,
          template:{spec:{restartPolicy:"Never",automountServiceAccountToken:false,
           imagePullSecrets:[{name:$pull}],
           securityContext:{runAsNonRoot:true,runAsUser:10001,runAsGroup:10001,fsGroup:10001,seccompProfile:{type:"RuntimeDefault"}},
           containers:[{name:"provisioner",image:$image,command:["/bin/bash","/bootstrap/run.sh"],
            securityContext:{allowPrivilegeEscalation:false,readOnlyRootFilesystem:true,capabilities:{drop:["ALL"]}},
            resources:{requests:{cpu:"100m",memory:"256Mi"},limits:{memory:"512Mi"}},
            env:[secretEnv("DB_ADMIN_USERNAME";$db;"username"),secretEnv("DB_ADMIN_PASSWORD";$db;"password"),
                 secretEnv("DB_SERVICE";$db;"service"),secretEnv("LAB_ADMIN_PRINCIPAL_ID";$name;"principalId"),
                 secretEnv("LAB_ADMIN_ISSUER";$name;"issuer"),{name:"TNS_ADMIN",value:"/oracle/tnsadmin"},
                 {name:"HOME",value:"/tmp"},{name:"JAVA_TOOL_OPTIONS",value:"-Xmx256m -XX:ActiveProcessorCount=1"}],
            volumeMounts:[{name:"bootstrap",mountPath:"/bootstrap",readOnly:true},
                         {name:"wallet",mountPath:"/oracle/tnsadmin",readOnly:true},{name:"tmp",mountPath:"/tmp"}]}],
           volumes:[{name:"bootstrap",configMap:{name:$name,defaultMode:288}},
                    {name:"wallet",secret:{secretName:$wallet,defaultMode:288}},{name:"tmp",emptyDir:{}}]}}}}
        ' >"$LAB_WORK_DIR/job.json"
    for manifest in config identity job; do
        kubectl --context "$LAB_CONTEXT" -n "$LAB_NAMESPACE" create --dry-run=server \
            -f "$LAB_WORK_DIR/$manifest.json" >/dev/null 2>"$LAB_WORK_DIR/validation.log" ||
            lab_fail "Lab owner $manifest validation failed; no resources were created."
    done
}

lab_apply() {
    local answer
    local succeeded=false
    printf 'Lab owner provisioning: context=%s namespace=%s account=obaas-admin\n' "$LAB_CONTEXT" "$LAB_NAMESPACE"
    if [[ "$LAB_ASSUME_YES" != true ]]; then
        [[ -t 0 ]] || lab_fail 'An interactive confirmation is required, or use --yes after approving this target.'
        printf 'Grant the verified lab owner visibility of all applications? [y/N] '
        IFS= read -r answer
        [[ "$answer" == y || "$answer" == Y ]] || lab_fail 'Provisioning cancelled.'
    fi
    kubectl --context "$LAB_CONTEXT" -n "$LAB_NAMESPACE" create -f "$LAB_WORK_DIR/config.json" >/dev/null
    LAB_CREATED_CONFIG=true
    kubectl --context "$LAB_CONTEXT" -n "$LAB_NAMESPACE" create -f "$LAB_WORK_DIR/identity.json" >/dev/null
    LAB_CREATED_IDENTITY=true
    kubectl --context "$LAB_CONTEXT" -n "$LAB_NAMESPACE" create -f "$LAB_WORK_DIR/job.json" >/dev/null
    LAB_CREATED_JOB=true
    if kubectl --context "$LAB_CONTEXT" -n "$LAB_NAMESPACE" wait --for=condition=complete \
        "job/$LAB_NAME" --timeout=8m; then succeeded=true; fi
    kubectl --context "$LAB_CONTEXT" -n "$LAB_NAMESPACE" logs "job/$LAB_NAME" -c provisioner \
        >"$LAB_WORK_DIR/result.log" 2>&1 || true
    grep -E '^LAB_ADMIN_APPLICATIONS_(TOTAL|VISIBLE)=[0-9]+$' "$LAB_WORK_DIR/result.log" || true
    if [[ "$succeeded" != true ]] || ! grep -qx 'LAB_ADMIN_BOOTSTRAP_OK' "$LAB_WORK_DIR/result.log"; then
        grep -Eo '(ORA|SP2)-[0-9]+' "$LAB_WORK_DIR/result.log" | sort -u >&2 || true
        lab_fail 'Lab owner provisioning did not pass; no successful deployment is reported.'
    fi
    printf 'LAB_ADMIN_BOOTSTRAP_OK\n'
    printf 'SUCCESS: obaas-admin can access all current and future CloudBank applications.\n'
}

main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --check-identity) LAB_CHECK_IDENTITY=true; shift ;;
            --yes) LAB_ASSUME_YES=true; shift ;;
            --image) [[ $# -ge 2 ]] || lab_fail 'Missing image.'; LAB_IMAGE="$2"; shift 2 ;;
            -h|--help) lab_usage; return ;;
            *) lab_usage >&2; lab_fail 'Unknown option.' ;;
        esac
    done
    for command in kubectl curl jq awk mktemp chmod sed head grep sort date; do
        command -v "$command" >/dev/null || lab_fail "$command is required."
    done
    umask 077
    LAB_WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cloudbank-lab-admin.XXXXXX")"
    trap lab_cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' HUP TERM
    lab_load_target
    lab_lookup_identity
    [[ "$LAB_CHECK_IDENTITY" != true ]] || return 0
    lab_render
    lab_apply
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
