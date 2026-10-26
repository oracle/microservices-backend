#!/usr/bin/env bash

# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at
# https://oss.oracle.com/licenses/upl.

set -Eeuo pipefail

readonly VERSION_TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly VERSION_TEST_ROOT="$(cd "$VERSION_TEST_DIR/../../.." && pwd)"
readonly VERSION_TEST_WORK="$(mktemp -d "${TMPDIR:-/tmp}/cloudbank-versions-test.XXXXXX")"
trap 'rm -rf -- "$VERSION_TEST_WORK"' EXIT

source "$VERSION_TEST_DIR/../lib/obaas-version.sh"

fail_test() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

for version in 2.1.0 2.1.1 2.1.2 2.2.0 2.10.0 3.0.0 10.0.0 \
    2.1.0+build.7 2.1.2-rc.1 2.2.0-SNAPSHOT 3.0.0-rc.1+build.9; do
    obaas_version_at_least "$version" || fail_test "rejected supported version $version"
done
for version in '' invalid v2.1.2 2.1 2.0.999 1.99.99 0.99.99 2.1.0-rc.1 \
    02.1.0 2.01.0 2.1.00 2.1.2-01 2.1.2-alpha.01 2.1.2- 2.1.2+; do
    if obaas_version_at_least "$version"; then
        fail_test "accepted invalid or too old version '$version'"
    fi
done
for pair in '2.10.0 2.9.99' '3.0.0 2.99.99' '2.1.2 2.1.2-rc.1' \
    '2.1.2-beta.10 2.1.2-beta.9' '2.1.2-beta 2.1.2-alpha' \
    '2.1.2-alpha.beta 2.1.2-alpha.1' '2.1.2-alpha.1 2.1.2-alpha' \
    '2.1.2+new 2.1.2+old' '9007199254740993.0.0 9007199254740992.0.0'; do
    read -r version minimum <<<"$pair"
    obaas_version_at_least "$version" "$minimum" || fail_test "incorrect ordering: $pair"
done
for pair in '2.9.99 2.10.0' '2.1.2-rc.1 2.1.2' '2.1.2-beta.9 2.1.2-beta.10' \
    '2.1.2-alpha.1 2.1.2-alpha.beta' '2.1.2-alpha 2.1.2-alpha.1' \
    '9007199254740992.0.0 9007199254740993.0.0'; do
    read -r version minimum <<<"$pair"
    if obaas_version_at_least "$version" "$minimum"; then
        fail_test "incorrect ordering: $pair"
    fi
done
printf 'PASS: semantic minimum, numeric ordering, prereleases, and build metadata\n'

# Only synthetic Helm metadata and Kubernetes reads; no cluster access.
platform_helm() {
    [[ "$1" == list ]] || return 64
    jq -n --arg version "$TEST_PLATFORM_VERSION" \
        '[{name:"obaas",namespace:"test-namespace",app_version:$version,chart:"obaas-0.9.0"}]'
}

platform_kubectl() {
    case "$*" in
        'config current-context') printf '%s\n' test-context ;;
        'config get-contexts test-context'|*' get namespace test-namespace'|*' get configmap/'*|*' get deployment/'*|*' get statefulset/'*) return 0 ;;
        *) return 64 ;;
    esac
}

test_platform_detection() (
    local script="$1"
    local detector="$2"
    local output
    source "$script"
    helm() { platform_helm "$@"; }
    kubectl() { platform_kubectl "$@"; }
    KUBECTL_CONTEXT=test-context
    OBAAS_RELEASE=obaas
    NAMESPACE=test-namespace
    CONFIGURED_OBAAS_RELEASE=obaas
    CONFIGURED_MICROTX_NAMESPACE=test-namespace
    for TEST_PLATFORM_VERSION in 2.1.0 2.1.2 2.10.0 3.0.0 2.2.0-rc.1+build.9; do
        output="$("$detector")"
        [[ "$output" == *"$TEST_PLATFORM_VERSION"* ]] || fail_test "version lost by $script"
    done
    for TEST_PLATFORM_VERSION in 2.0.99 1.99.99 2.1.0-rc.1 invalid; do
        if output="$("$detector" 2>&1)"; then
            fail_test "$script accepted $TEST_PLATFORM_VERSION"
        fi
        [[ "$output" == *'>= 2.1.0'* ]] || fail_test "missing minimum-version diagnostic in $script"
    done
)

test_platform_detection "$VERSION_TEST_DIR/../deploy-azn-server.sh" detect_obaas_release
test_platform_detection "$VERSION_TEST_DIR/../deploy-services.sh" detect_obaas_release
test_platform_detection "$VERSION_TEST_DIR/../deploy-azn-server_v1.sh" detect_obaas_target
printf 'PASS: Azn, Azn wrapper, and services detect future versions and reject older targets\n'

# The security loader reads a repository-root .env. Copy it into an isolated
# tree so this test never opens the operator's real configuration or secrets.
mkdir -p "$VERSION_TEST_WORK/security/deploy/microtx/oke-obaas" \
    "$VERSION_TEST_WORK/security/deploy/obaas/lib"
cp "$VERSION_TEST_ROOT/deploy/microtx/oke-obaas/secure-microtx-workflows.sh" \
    "$VERSION_TEST_WORK/security/deploy/microtx/oke-obaas/"
cp "$VERSION_TEST_DIR/../lib/obaas-version.sh" "$VERSION_TEST_WORK/security/deploy/obaas/lib/"
touch "$VERSION_TEST_WORK/security/kubeconfig"
cat >"$VERSION_TEST_WORK/security/.env" <<EOF
CLOUDBANK_KUBECONFIG_PATH=$VERSION_TEST_WORK/security/kubeconfig
OBAAS_RELEASE=obaas
MICROTX_NAMESPACE=test-namespace
AZN_ISSUER_URI=http://localhost:8080
MICROTX_PUBLIC_HOST=localhost
MICROTX_PROTOCOL=http
MICROTX_PUBLIC_PORT=5002
AZN_AUTHORIZATION_SERVER_MICROTX_CLIENT_SECRET=synthetic-placeholder
EOF
(
    source "$VERSION_TEST_WORK/security/deploy/microtx/oke-obaas/secure-microtx-workflows.sh"
    helm() { platform_helm "$@"; }
    kubectl() { platform_kubectl "$@"; }
    curl() { return 64; }
    openssl() { return 64; }
    for TEST_PLATFORM_VERSION in 2.1.0 2.1.2 2.10.0 3.0.0 2.2.0-rc.1+build.9; do
        (trap cleanup EXIT; load_configuration --enable)
    done
    for TEST_PLATFORM_VERSION in 2.0.99 2.1.0-rc.1 invalid; do
        if output="$(load_configuration --enable 2>&1)"; then
            fail_test "MicroTx security accepted $TEST_PLATFORM_VERSION"
        fi
        [[ "$output" == *'>= 2.1.0'* ]] || fail_test "missing minimum-version diagnostic for MicroTx"
    done
)
printf 'PASS: MicroTx security uses the same minimum-version rule\n'

# Reconstruct just the upstream template sections touched by our checked-in
# patch, preserving line numbers. Helm is mocked; the patch command is real.
mkdir -p "$VERSION_TEST_WORK/template/templates"
awk '
    /^@@/ {
        split($2, range, ",")
        start = substr(range[1], 2) + 0
        while (line < start - 1) { print ""; line++ }
        in_hunk = 1
        next
    }
    in_hunk && /^[ -]/ { print substr($0, 2); line++ }
' "$VERSION_TEST_DIR/../obaas-sample-app-database-optional.patch" \
    >"$VERSION_TEST_WORK/template/templates/_helpers.tpl"

chart_helm() {
    local destination=""
    local selected=""
    case "$1:${2:-}" in
        repo:list) printf '%s\n' '[{"name":"obaas"}]' ;;
        repo:update) return 0 ;;
        search:repo)
            [[ "$*" == *'--versions --devel --output json'* ]] || return 64
            if [[ "$TEST_CHART_SCENARIO" == missing ]]; then
                printf '%s\n' '[{"name":"obaas/obaas-sample-app","version":"9.0.0","app_version":"2.0.0"}]'
            else
                jq -n --arg target "$OBAAS_VERSION" \
                    '[{name:"obaas/obaas-sample-app-extra",version:"99.0.0",app_version:$target},
                      {name:"obaas/obaas-sample-app",version:"9.0.0",app_version:"2.0.0"},
                      {name:"obaas/obaas-sample-app",version:"0.9.7",app_version:$target}]'
            fi
            ;;
        pull:*)
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --version) selected="$2"; shift 2 ;;
                    --untardir) destination="$2"; shift 2 ;;
                    *) shift ;;
                esac
            done
            [[ "$selected" == 0.9.7 ]] || return 65
            printf '%s\n' "$selected" >"$WORK_DIR/pulled-version"
            mkdir -p "$destination/obaas-sample-app"
            cp -R "$VERSION_TEST_WORK/template/." "$destination/obaas-sample-app/"
            printf 'name: obaas-sample-app\nversion: %s\nappVersion: "%s"\n' \
                "$selected" "${TEST_CHART_METADATA_VERSION:-$OBAAS_VERSION}" \
                >"$destination/obaas-sample-app/Chart.yaml"
            if [[ "$TEST_CHART_SCENARIO" == patched ]]; then
                patch -f -N -s -p1 -d "$destination/obaas-sample-app" \
                    <"$VERSION_TEST_DIR/../obaas-sample-app-database-optional.patch"
            elif [[ "$TEST_CHART_SCENARIO" == incompatible ]]; then
                printf '%s\n' 'incompatible synthetic template' \
                    >"$destination/obaas-sample-app/templates/_helpers.tpl"
            fi
            ;;
        show:chart) cat "$3/Chart.yaml" ;;
        *) return 64 ;;
    esac
}

test_chart_selection() (
    local script="$1"
    local version="$2"
    local scenario="$3"
    local output
    source "$script"
    helm() { chart_helm "$@"; }
    OBAAS_VERSION="$version"
    TEST_CHART_SCENARIO="$scenario"
    TEST_CHART_METADATA_VERSION=""
    WORK_DIR="$(mktemp -d "$VERSION_TEST_WORK/chart.XXXXXX")"
    if [[ "$scenario" == mismatch ]]; then
        TEST_CHART_METADATA_VERSION=2.0.0
    fi
    case "$scenario" in
        missing|incompatible|mismatch)
            if output="$(resolve_app_chart 2>&1)"; then
                fail_test "$script accepted chart scenario $scenario"
            fi
            case "$scenario" in
                missing)
                    [[ ! -f "$WORK_DIR/pulled-version" ]] || fail_test "chart lookup fell back to another version"
                    [[ "$output" == *'no '*"appVersion $version"* ]] || fail_test "missing chart diagnostic"
                    ;;
                mismatch) [[ "$output" == *'does not match OBaaS'* ]] || fail_test "missing chart mismatch diagnostic" ;;
                incompatible) [[ "$output" == *'incompatible'* ]] || fail_test "missing patch incompatibility diagnostic" ;;
            esac
            ;;
        *)
            resolve_app_chart
            [[ "$APP_CHART_VERSION" == 0.9.7 ]] || fail_test "selected an unrelated chart or used appVersion as chart version"
            if [[ "$script" == */deploy-services.sh ]]; then
                if cmp -s "$VERSION_TEST_WORK/template/templates/_helpers.tpl" "$RESOLVED_CHART/templates/_helpers.tpl"; then
                    fail_test 'database-optional template fix was not applied'
                fi
                patch -f --dry-run -R -s -p1 -d "$RESOLVED_CHART" \
                    <"$VERSION_TEST_DIR/../obaas-sample-app-database-optional.patch" >/dev/null
            fi
            ;;
    esac
)

for script in "$VERSION_TEST_DIR/../deploy-azn-server.sh" "$VERSION_TEST_DIR/../deploy-services.sh"; do
    for version in 2.1.0 2.1.2 3.0.0 2.2.0-rc.1+build.9; do
        test_chart_selection "$script" "$version" original
    done
    test_chart_selection "$script" 2.1.2 missing
    test_chart_selection "$script" 2.1.2 mismatch
done
test_chart_selection "$VERSION_TEST_DIR/../deploy-services.sh" 2.1.2 patched
test_chart_selection "$VERSION_TEST_DIR/../deploy-services.sh" 2.1.2 incompatible
printf 'PASS: exact chart selection, suffix preservation, missing/mismatched charts, and patch compatibility\n'

(
    source "$VERSION_TEST_DIR/../deploy-azn-server.sh"
    helm() {
        [[ "$*" != 'list --help' ]] || { printf '%s\n' '  --all'; return; }
        [[ "$1" == list ]] || return 64
        jq -n --arg version "$TEST_INSTALLED_VERSION" --arg status "$TEST_RELEASE_STATUS" \
            '[{name:"azn-server",app_version:$version,status:$status}]'
    }
    kubectl() {
        [[ "$*" == *'get deployment azn-server'* ]] || return 64
        [[ "$*" != *jsonpath=* ]] || printf '%s' registry.example/azn:old
        return 0
    }
    KUBECTL_CONTEXT=test-context
    NAMESPACE=test-namespace
    OBAAS_VERSION=2.1.2
    TEST_INSTALLED_VERSION=2.1.0
    TEST_RELEASE_STATUS=deployed
    DEPLOY_MODE=redeploy
    validate_deploy_state
    DEPLOY_MODE=first-deploy
    TEST_RELEASE_STATUS=failed
    validate_deploy_state
    TEST_INSTALLED_VERSION=2.2.0
    DEPLOY_MODE=redeploy
    if output="$(validate_deploy_state 2>&1)"; then
        fail_test 'Azn allowed an automatic chart downgrade'
    fi
    [[ "$output" == *'newer than OBaaS'* ]] || fail_test 'missing chart downgrade diagnostic'
)
printf 'PASS: Azn chart upgrades and failed-deployment recovery; downgrades rejected\n'
