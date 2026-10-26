#!/usr/bin/env bash

# Chart values are authoritative for fields rendered by the deployment helpers.
# Helm 4 uses server-side apply, which otherwise rejects prior kubectl edits.
# Capability detection keeps Helm 3 invocations free of unsupported flags.
configure_helm_upgrade_conflict_handling() {
    local upgrade_help

    HELM_UPGRADE_CONFLICT_ARGS=()
    upgrade_help="$(helm upgrade --help)" || die "could not inspect helm upgrade capabilities"
    if printf '%s\n' "$upgrade_help" | grep -Eq -- '(^|[[:space:]])--force-conflicts([[:space:]]|$)' &&
        printf '%s\n' "$upgrade_help" | grep -Eq -- '(^|[[:space:]])--server-side([[:space:]]|$)'; then
        HELM_UPGRADE_CONFLICT_ARGS=(--server-side=true --force-conflicts)
    fi
}
