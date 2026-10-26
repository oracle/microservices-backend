#!/usr/bin/env bash

# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at
# https://oss.oracle.com/licenses/upl.

# Build and publish only the CloudBank AI azn-server image to OCIR.
# Registry authentication is deliberately external to this script: authenticate
# first with `docker login <region>.ocir.io` using an OCI auth token.

set -Eeuo pipefail
set +x

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly DOCKERFILE="$REPOSITORY_ROOT/Dockerfile"

KUBE_CONTEXT=""
IMAGE_REPOSITORY=""
IMAGE_TAG=""
TARGET_PLATFORMS=""
SKIP_TESTS=false
DRY_RUN=false
ASSUME_YES=false

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 2
}

info() {
    printf '%s\n' "$*"
}

usage() {
    printf '%s\n' \
        'Usage:' \
        '  ./src/azn-server/build-push-azn-server.sh <kube-context> --image-repository OCIR_REPOSITORY [options]' \
        '' \
        'Builds only the Docker target azn-server and pushes it to OCIR.' \
        'The target node architecture is discovered from the supplied cluster.' \
        '' \
        'Required:' \
        '  -c, --context CONTEXT         Target Kubernetes context (or first argument)' \
        '  -r, --image-repository REPO   Full OCIR repository without a tag' \
        '' \
        'Options:' \
        '  -t, --image-tag TAG           Unique tag (default: UTC timestamp tag)' \
        '      --platform PLATFORMS      Override detected platforms, for example linux/amd64' \
        '                                or linux/amd64,linux/arm64' \
        '      --skip-tests              Skip azn-server Maven tests' \
        '      --dry-run                 Validate and show the plan without building or pushing' \
        '  -y, --yes                     Build and push without interactive confirmation' \
        '  -h, --help                    Show this help' \
        '' \
        'Prerequisites:' \
        '  - The OCIR repository already exists.' \
        '  - Docker is authenticated with: docker login <region>.ocir.io' \
        '  - Docker Buildx, Maven, Java 25, and kubectl are available.' \
        '' \
        'Example:' \
        '  ./src/azn-server/build-push-azn-server.sh my-oke-context \' \
        '    --image-repository eu-milan-1.ocir.io/<tenancy-namespace>/cloudbank-ai/azn-server'
}

require_value() {
    local option_name="$1"
    local option_value="${2-}"
    [[ -n "$option_value" && "$option_value" != -* ]] ||
        die "$option_name requires a value"
}

parse_args() {
    if [[ $# -gt 0 && "$1" != -* ]]; then
        KUBE_CONTEXT="$1"
        shift
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c | --context)
                require_value "$1" "${2-}"
                KUBE_CONTEXT="$2"
                shift 2
                ;;
            -r | --image-repository)
                require_value "$1" "${2-}"
                IMAGE_REPOSITORY="$2"
                shift 2
                ;;
            -t | --image-tag)
                require_value "$1" "${2-}"
                IMAGE_TAG="$2"
                shift 2
                ;;
            --platform)
                require_value "$1" "${2-}"
                TARGET_PLATFORMS="$2"
                shift 2
                ;;
            --skip-tests)
                SKIP_TESTS=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -y | --yes)
                ASSUME_YES=true
                shift
                ;;
            -h | --help)
                usage
                exit 0
                ;;
            --)
                shift
                [[ $# -eq 0 ]] || die "unexpected positional argument: $1"
                ;;
            *)
                die "unknown option or extra argument: $1"
                ;;
        esac
    done
}

validate_inputs() {
    [[ -n "$KUBE_CONTEXT" ]] || die "a kube context is required; see --help"
    [[ -n "$IMAGE_REPOSITORY" ]] || die "--image-repository is required"
    [[ -f "$DOCKERFILE" ]] || die "Dockerfile not found: $DOCKERFILE"

    [[ "$IMAGE_REPOSITORY" =~ ^[a-z0-9][a-z0-9.-]*\.ocir\.io/[a-z0-9._-]+/[a-z0-9._/-]+$ ]] ||
        die "--image-repository must be a full OCIR path without a tag"
    [[ "$IMAGE_REPOSITORY" != */ ]] ||
        die "--image-repository must not end with a slash"

    if [[ -z "$IMAGE_TAG" ]]; then
        IMAGE_TAG="dev-$(date -u +%Y%m%dT%H%M%SZ)"
    fi
    [[ "$IMAGE_TAG" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]] ||
        die "--image-tag is not a valid container image tag"
    [[ "$IMAGE_TAG" != latest ]] || die "refusing mutable image tag 'latest'"

    if [[ -n "$TARGET_PLATFORMS" ]]; then
        [[ "$TARGET_PLATFORMS" =~ ^linux/(amd64|arm64)(,linux/(amd64|arm64))*$ ]] ||
            die "--platform supports linux/amd64, linux/arm64, or both"
    fi
}

require_commands() {
    local command_name
    for command_name in docker kubectl mvn sort date; do
        command -v "$command_name" >/dev/null 2>&1 || die "$command_name is required"
    done

    if [[ "$DRY_RUN" != true ]]; then
        docker info >/dev/null 2>&1 || die "Docker daemon is unavailable"
        docker buildx version >/dev/null 2>&1 || die "Docker Buildx is unavailable"
    fi
}

detect_platforms() {
    local architectures
    local architecture
    local platforms=""

    kubectl --context "$KUBE_CONTEXT" cluster-info >/dev/null
    [[ -n "$TARGET_PLATFORMS" ]] && return 0

    architectures="$(kubectl --context "$KUBE_CONTEXT" get nodes \
        --output jsonpath='{range .items[*]}{.status.nodeInfo.architecture}{"\n"}{end}' |
        sort -u)"
    [[ -n "$architectures" ]] || die "no node architecture was returned by the target cluster"

    while IFS= read -r architecture; do
        case "$architecture" in
            amd64 | arm64) ;;
            *) die "unsupported Kubernetes node architecture: $architecture" ;;
        esac
        if [[ -n "$platforms" ]]; then
            platforms="$platforms,"
        fi
        platforms="${platforms}linux/${architecture}"
    done <<<"$architectures"

    TARGET_PLATFORMS="$platforms"
}

show_plan() {
    info ""
    info "Image publication plan"
    info "  Context:     $KUBE_CONTEXT"
    info "  Docker target: azn-server"
    info "  Platforms:   $TARGET_PLATFORMS"
    info "  Image:       $IMAGE_REPOSITORY:$IMAGE_TAG"
    info "  Maven tests: $([[ "$SKIP_TESTS" == true ]] && printf 'skipped' || printf 'enabled')"
    info ""
}

confirm_publish() {
    [[ "$ASSUME_YES" == true ]] && return 0
    [[ -t 0 ]] || die "interactive confirmation is unavailable; rerun with --yes after reviewing --dry-run"

    local reply
    read -r -p "Build and push this image to OCIR? [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]] || {
        info "Image publication cancelled."
        exit 0
    }
}

run_tests() {
    [[ "$SKIP_TESTS" == true ]] && return 0
    info "Running azn-server tests..."
    mvn -B -ntp -f "$SCRIPT_DIR/pom.xml" test
}

build_and_push() {
    local image_reference="$IMAGE_REPOSITORY:$IMAGE_TAG"

    info "Building and pushing azn-server..."
    docker buildx build \
        --platform "$TARGET_PLATFORMS" \
        --target azn-server \
        --tag "$image_reference" \
        --push \
        "$REPOSITORY_ROOT"

    info "Verifying the published multi-platform manifest..."
    docker buildx imagetools inspect "$image_reference" >/dev/null
}

show_next_step() {
    info ""
    info "Image published successfully: $IMAGE_REPOSITORY:$IMAGE_TAG"
    info ""
    info "To deploy this already-published tag with the lower-level Helm helper:"
    info "  NEW_IMAGE_TAG='$IMAGE_TAG' ./deploy/obaas/deploy-azn-server.sh redeploy"
}

main() {
    parse_args "$@"
    validate_inputs
    require_commands
    detect_platforms
    show_plan

    if [[ "$DRY_RUN" == true ]]; then
        info "Dry-run completed; no image was built or pushed."
        return 0
    fi

    confirm_publish
    run_tests
    build_and_push
    show_next_step
}

main "$@"
