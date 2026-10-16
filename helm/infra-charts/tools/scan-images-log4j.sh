#!/usr/bin/env bash
# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at http://oss.oracle.com/licenses/upl.

# =============================================================================
# OBaaS Log4j Image Scanner
# =============================================================================
# Pulls each image in an image list, exports its final container filesystem, and
# reports JAR files whose filename contains "log4j". The image is never run.
#
# Usage:
#   ./scan-images-log4j.sh [options]
#
# Examples:
#   ./scan-images-log4j.sh
#   ./scan-images-log4j.sh --no-pull --file ./images.txt
#   ./scan-images-log4j.sh --platform linux/arm64 --output /tmp/log4j.tsv
#
# Prerequisites:
#   - docker or podman must be installed and usable
#   - tar and mktemp must be installed
#   - registry authentication is required when images are not public
#
# Exit codes:
#   0  Scan completed and no matching JAR files were found
#   1  Scan completed and at least one matching JAR file was found
#   2  One or more images could not be pulled or scanned
#
# Notes:
#   - The scan covers the final filesystem presented by the image. JAR files
#     deleted by a later image layer are not part of the final image and are not
#     reported.
#   - Matching is filename-based. For example, log4j-api-*.jar and
#     log4j-core-*.jar are reported; arbitrary JARs that embed Log4j classes are
#     not inspected.
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_FILE="${SCRIPT_DIR}/../obaas/Chart.yaml"

get_app_version() {
    if [[ -f "$CHART_FILE" ]]; then
        grep '^appVersion:' "$CHART_FILE" | sed 's/appVersion:[[:space:]]*"\{0,1\}\([^"]*\)"\{0,1\}/\1/'
    else
        echo "unknown"
    fi
}

APP_VERSION="$(get_app_version)"
IMAGE_LISTS_DIR="${SCRIPT_DIR}/image_lists"
IMAGES_FILE="${IMAGE_LISTS_DIR}/k8s_images_${APP_VERSION}.txt"

CONTAINER_RUNTIME="${CONTAINER_RUNTIME:-}"
PLATFORM="linux/amd64"
PULL_IMAGES=true
OUTPUT_FILE=""
TEMP_DIR=""
CURRENT_CONTAINER=""
MATCH_FILE=""

TOTAL_COUNT=0
MATCHED_COUNT=0
FAILED_COUNT=0
MATCHED_IMAGES=()
FAILED_IMAGES=()

log() {
    case "$1" in
        none)    echo "$2" ;;
        info)    echo "ℹ️  $2" ;;
        success) echo "✅ $2" ;;
        warn)    echo "⚠️  $2" ;;
        error)   echo "❌ $2" >&2 ;;
    esac
}

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Scan container images for JAR filenames containing "log4j".

Options:
    -h, --help               Show this help message
    -f, --file FILE          Image list (default: ./image_lists/k8s_images_<appVersion>.txt)
    -p, --platform PLATFORM  Image platform (default: linux/amd64)
    --no-pull                Scan images already present locally
    -o, --output FILE        Write tab-separated results to FILE
    --runtime COMMAND        Use COMMAND instead of auto-detecting docker/podman

Examples:
    $(basename "$0")
    $(basename "$0") --no-pull --file ./images.txt
    $(basename "$0") --platform linux/arm64 --output /tmp/log4j.tsv

The command exits 0 for a clean scan, 1 when Log4j JARs are found, and 2 when
one or more images could not be scanned.
EOF
}

die() {
    log error "$1"
    exit 2
}

cleanup() {
    remove_current_container

    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf -- "$TEMP_DIR"
    fi
}

remove_current_container() {
    if [[ -n "$CURRENT_CONTAINER" ]]; then
        "$CONTAINER_RUNTIME" rm "$CURRENT_CONTAINER" >/dev/null 2>&1 || true
        CURRENT_CONTAINER=""
    fi
}

on_signal() {
    exit 130
}

trap cleanup EXIT
trap on_signal INT TERM

detect_runtime() {
    if [[ -n "$CONTAINER_RUNTIME" ]]; then
        command -v "$CONTAINER_RUNTIME" >/dev/null 2>&1 || \
            die "Container runtime not found: $CONTAINER_RUNTIME"
        return
    fi

    if command -v docker >/dev/null 2>&1; then
        CONTAINER_RUNTIME="docker"
    elif command -v podman >/dev/null 2>&1; then
        CONTAINER_RUNTIME="podman"
    else
        die "Neither docker nor podman is installed or available in PATH"
    fi
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            -f|--file)
                [[ $# -ge 2 ]] || die "Missing value for $1"
                IMAGES_FILE="$2"
                shift 2
                ;;
            -p|--platform)
                [[ $# -ge 2 ]] || die "Missing value for $1"
                PLATFORM="$2"
                shift 2
                ;;
            --no-pull)
                PULL_IMAGES=false
                shift
                ;;
            -o|--output)
                [[ $# -ge 2 ]] || die "Missing value for $1"
                OUTPUT_FILE="$2"
                shift 2
                ;;
            --runtime)
                [[ $# -ge 2 ]] || die "Missing value for $1"
                CONTAINER_RUNTIME="$2"
                shift 2
                ;;
            --)
                shift
                [[ $# -eq 0 ]] || die "Unexpected positional argument: $1"
                ;;
            -* )
                die "Unknown option: $1"
                ;;
            *)
                die "Unexpected positional argument: $1"
                ;;
        esac
    done
}

trim() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

count_images() {
    local line count=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="$(trim "$line")"
        [[ -z "$line" || "$line" == \#* ]] && continue
        ((count+=1))
    done < "$IMAGES_FILE"

    echo "$count"
}

write_report_header() {
    [[ -n "$OUTPUT_FILE" ]] || return 0

    printf 'image\tstatus\tmatching_jar_count\tmatching_paths\n' > "$OUTPUT_FILE" || \
        die "Cannot write output file: $OUTPUT_FILE"
}

write_result() {
    local image="$1"
    local status="$2"
    local match_count="$3"
    local paths="${4:-}"

    [[ -n "$OUTPUT_FILE" ]] || return 0
    paths="${paths//$'\n'/,}"
    printf '%s\t%s\t%s\t%s\n' "$image" "$status" "$match_count" "$paths" >> "$OUTPUT_FILE"
}

scan_image() {
    local image="$1"
    local container_id
    local entries_file="${TEMP_DIR}/entries"

    MATCH_FILE="${TEMP_DIR}/matches"
    : > "$MATCH_FILE"

    if [[ "$PULL_IMAGES" == "true" ]]; then
        log info "Pulling $image (platform: $PLATFORM)"
        if ! "$CONTAINER_RUNTIME" pull --platform "$PLATFORM" "$image"; then
            log error "Failed to pull: $image"
            return 1
        fi
    else
        log info "Using local image: $image"
    fi

    log info "Creating temporary container for $image"
    if ! container_id=$("$CONTAINER_RUNTIME" create --platform "$PLATFORM" "$image"); then
        log error "Failed to create a container from: $image"
        return 1
    fi

    if [[ -z "$container_id" ]]; then
        log error "Container runtime returned no container ID for: $image"
        return 1
    fi
    CURRENT_CONTAINER="$container_id"

    log info "Scanning final filesystem: $image"
    if ! "$CONTAINER_RUNTIME" export "$container_id" | LC_ALL=C tar -tf - > "$entries_file"; then
        log error "Failed to export or inspect filesystem: $image"
        remove_current_container
        return 1
    fi

    remove_current_container

    LC_ALL=C awk '
        {
            path = tolower($0)
            if (path ~ /(^|\/)[^\/]*log4j[^\/]*\.jar$/) {
                print $0
            }
        }
    ' "$entries_file" > "$MATCH_FILE"

    return 0
}

print_summary() {
    echo
    log none "=============================================="
    log none "Log4j Scan Complete"
    log none "=============================================="
    log info "Images scanned: $((TOTAL_COUNT - FAILED_COUNT))/$TOTAL_COUNT"
    log success "Images without matching JAR filenames: $((TOTAL_COUNT - MATCHED_COUNT - FAILED_COUNT))"
    log warn "Images with matching JAR filenames: $MATCHED_COUNT"
    log error "Images that failed to scan: $FAILED_COUNT"

    if [[ ${#MATCHED_IMAGES[@]} -gt 0 ]]; then
        echo
        log none "Matching images:"
        printf '  %s\n' "${MATCHED_IMAGES[@]}"
    fi

    if [[ ${#FAILED_IMAGES[@]} -gt 0 ]]; then
        echo
        log none "Failed images:"
        printf '  %s\n' "${FAILED_IMAGES[@]}"
    fi

    if [[ -n "$OUTPUT_FILE" ]]; then
        log info "Results written to: $OUTPUT_FILE"
    fi
}

main() {
    local line image match_count matches current=0

    parse_args "$@"

    [[ -f "$IMAGES_FILE" ]] || die "Image list not found: $IMAGES_FILE"
    command -v tar >/dev/null 2>&1 || die "tar is required"
    command -v mktemp >/dev/null 2>&1 || die "mktemp is required"
    detect_runtime

    TOTAL_COUNT="$(count_images)"
    [[ "$TOTAL_COUNT" -gt 0 ]] || die "Image list contains no image references: $IMAGES_FILE"

    TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/obaas-log4j-scan.XXXXXX")" || \
        die "Unable to create a temporary directory"
    write_report_header

    log none "=============================================="
    log none "OBaaS Log4j Image Scanner"
    log none "=============================================="
    log info "Image list: $IMAGES_FILE"
    log info "Images: $TOTAL_COUNT"
    log info "Runtime: $CONTAINER_RUNTIME"
    log info "Platform: $PLATFORM"
    if [[ "$PULL_IMAGES" == "true" ]]; then
        log info "Pull behavior: pull before scanning"
    else
        log info "Pull behavior: local images only"
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        image="$(trim "$line")"
        [[ -z "$image" || "$image" == \#* ]] && continue

        ((current+=1))
        echo
        log none "[$current/$TOTAL_COUNT] $image"

        if scan_image "$image"; then
            matches="$(cat "$MATCH_FILE")"
            if [[ -n "$matches" ]]; then
                match_count="$(wc -l < "$MATCH_FILE" | tr -d '[:space:]')"
                ((MATCHED_COUNT+=1))
                MATCHED_IMAGES+=("$image")
                log warn "Found $match_count matching JAR filename(s) in $image:"
                sed 's/^/  /' "$MATCH_FILE"
                write_result "$image" "MATCH" "$match_count" "$matches"
            else
                log success "No matching JAR filenames found: $image"
                write_result "$image" "CLEAN" "0"
            fi
        else
            ((FAILED_COUNT+=1))
            FAILED_IMAGES+=("$image")
            write_result "$image" "FAILED" ""
        fi
    done < "$IMAGES_FILE"

    print_summary

    if [[ "$FAILED_COUNT" -gt 0 ]]; then
        return 2
    elif [[ "$MATCHED_COUNT" -gt 0 ]]; then
        return 1
    fi
    return 0
}

main "$@"
