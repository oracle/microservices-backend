#!/usr/bin/env bash
# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at http://oss.oracle.com/licenses/upl.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="${CHART_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
OUTPUT=$(mktemp)
trap 'rm -f "$OUTPUT"' EXIT

helm template setup-test "$CHART_DIR" --is-upgrade > "$OUTPUT"
rg -q 'name: setup-test-signoz-setup$' "$OUTPUT"

# First upgrade pass retains the old API and must not reconcile V2 dashboards.
helm template setup-test "$CHART_DIR" --is-upgrade \
  --set signoz.telemetryStoreMigrator.enabled=false \
  --set signoz.setup.enabled=false \
  --set signoz.signoz.image.tag=v0.113.0 > "$OUTPUT"
if rg -q 'name: setup-test-signoz-setup$' "$OUTPUT"; then
  echo 'First-pass setup hook was not disabled' >&2
  exit 1
fi

# Second pass explicitly restores setup even if the first flag was saved.
helm template setup-test "$CHART_DIR" --is-upgrade \
  --set signoz.setup.enabled=false --set signoz.setup.enabled=true \
  --set signoz.telemetryStoreMigrator.enabled=true \
  --set signoz.signoz.image.tag=v0.142.1 > "$OUTPUT"
rg -q 'name: setup-test-signoz-setup$' "$OUTPUT"
rg -q '/api/v2/dashboards' "$OUTPUT"
echo 'SigNoz setup toggle render checks passed.'
