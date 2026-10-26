#!/usr/bin/env bash

# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at
# https://oss.oracle.com/licenses/upl.

set -euo pipefail

readonly WORKFLOW_NAME="${MICROTX_WORKFLOW_NAME:-cloudbank-loan-origination}"
readonly WORKFLOW_VERSION="1"

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 2
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "$1 is required"
}

normalize_api_base() {
    local base="${1%/}"
    case "$base" in
        */api) printf '%s\n' "$base" ;;
        *) printf '%s/api\n' "$base" ;;
    esac
}

print_json_or_raw() {
    if ! jq . 2>/dev/null; then
        cat
    fi
}

require_command curl
require_command jq

[[ -n "${MICROTX_WORKFLOW_URL:-}" ]] ||
    die "Set MICROTX_WORKFLOW_URL, for example: http://127.0.0.1/workflow-server"
[[ "$WORKFLOW_NAME" == "cloudbank-loan-origination" ]] ||
    die "Only cloudbank-loan-origination may be verified"
[[ "$WORKFLOW_VERSION" == "1" ]] ||
    die "Only cloudbank-loan-origination version 1 may be verified"

API_BASE="$(normalize_api_base "$MICROTX_WORKFLOW_URL")"
METADATA_URL="$API_BASE/metadata/workflow/$WORKFLOW_NAME"

AUTH_ARGS=()
if [[ -n "${MICROTX_BEARER_TOKEN:-}" ]]; then
    AUTH_ARGS=(-H "Authorization: Bearer $MICROTX_BEARER_TOKEN")
fi

printf 'Verifying MicroTx workflow definition\n'
printf '  Workflow: %s version %s\n' "$WORKFLOW_NAME" "$WORKFLOW_VERSION"
printf '  API base: %s\n\n' "$API_BASE"

response_body="$(mktemp "${TMPDIR:-/tmp}/cloudbank-workflow-verify.XXXXXX")"
status="$(
    curl --silent --show-error \
        --output "$response_body" \
        --write-out '%{http_code}' \
        "${AUTH_ARGS[@]}" \
        "$METADATA_URL"
)"

if [[ "$status" == "404" ]]; then
    printf 'Workflow %s was not found.\n' "$WORKFLOW_NAME" >&2
    rm -f "$response_body"
    exit 1
fi

if [[ "$status" -lt 200 || "$status" -ge 300 ]]; then
    printf 'Workflow metadata lookup failed with HTTP %s\n' "$status" >&2
    print_json_or_raw < "$response_body" >&2
    rm -f "$response_body"
    exit 1
fi

if jq -e --arg name "$WORKFLOW_NAME" --argjson version "$WORKFLOW_VERSION" '
    if type == "array" then
      any(.[]; .name == $name and .version == $version)
    else
      .name == $name and .version == $version
    end
' "$response_body" >/dev/null; then
    printf 'Workflow %s version %s exists.\n' "$WORKFLOW_NAME" "$WORKFLOW_VERSION"
    rm -f "$response_body"
    exit 0
fi

printf 'Workflow %s exists, but version %s was not found in metadata response.\n' \
    "$WORKFLOW_NAME" "$WORKFLOW_VERSION" >&2
print_json_or_raw < "$response_body" >&2
rm -f "$response_body"
exit 1
