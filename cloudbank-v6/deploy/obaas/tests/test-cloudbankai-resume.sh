#!/usr/bin/env bash

# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at
# https://oss.oracle.com/licenses/upl.

set -Eeuo pipefail

TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cloudbank-resume-test.XXXXXX")"
trap 'rm -rf -- "$TEST_DIR"' EXIT
export TEST_DEPLOY_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/cloudbankai_deploy.sh"
export TEST_EVENTS="$TEST_DIR/events"

# Exercise the real argument parsing and step ordering with synthetic helpers.
# No real configuration, build, Kubernetes, registry, or workflow calls.
invoke() {
    : >"$TEST_EVENTS"
    bash -s -- "$@" <<'BASH'
source "$TEST_DEPLOY_SCRIPT"
preflight() {
    NAMESPACE=test-namespace
    OBAAS_RELEASE=obaas
    printf 'preflight\n' >>"$TEST_EVENTS"
}
kubectl() {
    case "$*" in
        'config current-context') printf 'test-context\n' ;;
        *'rollout status deployment/azn-server --timeout=30s')
            printf 'azn-readiness\n' >>"$TEST_EVENTS"
            [[ "${TEST_AZN_READY:-true}" == true ]]
            ;;
        *) return 64 ;;
    esac
}
run_step() {
    printf '%s|%s\n' "$1" "${4:-}" >>"$TEST_EVENTS"
    if [[ "$1" == services && "${TEST_SERVICES_FAIL:-false}" == true ]]; then
        exit 7
    fi
}
start_port_forward() { :; }
curl() {
    case "$*" in
        *'/actuator/health') printf '{"status":"UP"}\n' ;;
        *'/api/metadata/workflow') printf '401' ;;
        *) return 64 ;;
    esac
}
main "$@"
BASH
}

for mode in first-deploy redeploy; do
    invoke "$mode" >"$TEST_DIR/output"
    printf 'preflight\nazn-server|%s\nservices|%s\nworkflow|\n' "$mode" "$mode" \
        >"$TEST_DIR/expected"
    cmp "$TEST_DIR/expected" "$TEST_EVENTS"

    unset NEW_IMAGE_TAG
    invoke "$mode" --from services >"$TEST_DIR/output"
    printf 'preflight\nazn-readiness\nservices|%s\nworkflow|\n' "$mode" \
        >"$TEST_DIR/expected"
    cmp "$TEST_DIR/expected" "$TEST_EVENTS"

    invoke "$mode" --from workflow >"$TEST_DIR/output"
    printf 'preflight\nazn-readiness\nworkflow|\n' >"$TEST_DIR/expected"
    cmp "$TEST_DIR/expected" "$TEST_EVENTS"
done

for arguments in 'first-deploy --from' 'first-deploy --from invalid' \
    'first-deploy --other services' 'first-deploy --from services --from workflow'; do
    read -r -a args <<<"$arguments"
    if invoke "${args[@]}" >"$TEST_DIR/output" 2>&1; then
        printf 'FAIL: invalid arguments accepted\n' >&2
        exit 1
    fi
    [[ ! -s "$TEST_EVENTS" ]]
done

export TEST_AZN_READY=false
if invoke first-deploy --from services >"$TEST_DIR/output" 2>&1; then
    printf 'FAIL: resumed with an unavailable authorization server\n' >&2
    exit 1
fi
printf 'preflight\nazn-readiness\n' >"$TEST_DIR/expected"
cmp "$TEST_DIR/expected" "$TEST_EVENTS"
unset TEST_AZN_READY

export TEST_SERVICES_FAIL=true
if invoke first-deploy --from services >"$TEST_DIR/output" 2>&1; then
    printf 'FAIL: ignored a services deployment failure\n' >&2
    exit 1
fi
printf 'preflight\nazn-readiness\nservices|first-deploy\n' >"$TEST_DIR/expected"
cmp "$TEST_DIR/expected" "$TEST_EVENTS"

printf 'PASS: complete and resumed deployment ordering, invalid arguments, readiness, and failure handling\n'
