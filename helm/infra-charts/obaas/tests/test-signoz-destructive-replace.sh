set -euo pipefail
chart="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
helm lint "$chart"
helm template obaas "$chart" -n obaas >"$tmp"
! grep -qE 'signoz-destructive-replace|kind: VolumeSnapshot|signoz-stage2' "$tmp"
if helm template obaas "$chart" -n obaas --is-upgrade >"$tmp" 2>&1; then exit 1; fi
grep -qF 'Destructive upgrade warning' "$tmp"
grep -qF 'signozUpgrade.mode=destructive-replace and signozUpgrade.confirmDataLoss=true' "$tmp"
helm template obaas "$chart" -n obaas --is-upgrade \
  --set signozUpgrade.mode=destructive-replace \
  --set signozUpgrade.confirmDataLoss=true >"$tmp"
for image in 'signoz/signoz:v0.134.0' 'signoz/signoz-otel-collector:v0.144.6' 'clickhouse/clickhouse-server:25.12.5'; do grep -qF "$image" "$tmp"; done
grep -qF 'erase-observability-data' "$tmp"
grep -qF 'kubectl delete chi obaas-clickhouse' "$tmp"
grep -qF 'kubectl delete job signoz-telemetrystore-migrator' "$tmp"
grep -qF 'app.kubernetes.io/component=clickhouse' "$tmp"
grep -qF 'name: signoz-telemetrystore-migrator' "$tmp"
! awk '/telemetrystore-migrator\/job.yaml/{found=1} found{print} found && /^---$/{exit}' "$tmp" | grep -q 'helm.sh/hook: pre-upgrade'
grep -qF 'Deleting existing dashboard:' "$tmp"
