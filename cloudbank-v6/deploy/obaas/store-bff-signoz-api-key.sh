#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

read_env_value() {
    local key="$1"
    local value
    value="$(sed -n "s/^${key}=//p" "$REPO_ROOT/.env" 2>/dev/null | tail -n 1)"
    printf '%s' "$value"
}

kubeconfig="${BFF_KUBECONFIG:-$(read_env_value CLOUDBANK_KUBECONFIG_PATH)}"
namespace="${BFF_NAMESPACE:-$(read_env_value MICROTX_NAMESPACE)}"
context="${BFF_KUBE_CONTEXT:-}"
secret_name="${BFF_SIGNOZ_API_KEY_SECRET_NAME:-cloudbank-bff-signoz-api}"
secret_key="${BFF_SIGNOZ_API_KEY_SECRET_KEY:-api-key}"

[[ -n "$kubeconfig" ]] || { printf '%s\n' 'Set BFF_KUBECONFIG or CLOUDBANK_KUBECONFIG_PATH in .env.' >&2; exit 1; }
[[ -n "$namespace" ]] || { printf '%s\n' 'Set BFF_NAMESPACE or MICROTX_NAMESPACE in .env.' >&2; exit 1; }
[[ -f "$kubeconfig" ]] || { printf '%s\n' 'The selected kubeconfig file does not exist.' >&2; exit 1; }
[[ "$namespace" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]] || { printf '%s\n' 'Invalid Kubernetes namespace.' >&2; exit 1; }
[[ "$secret_name" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]] || { printf '%s\n' 'Invalid Kubernetes Secret name.' >&2; exit 1; }
[[ "$secret_key" =~ ^[A-Za-z0-9._-]+$ ]] || { printf '%s\n' 'Invalid Kubernetes Secret key.' >&2; exit 1; }

if [[ -z "$context" ]]; then
    context="$(kubectl --kubeconfig "$kubeconfig" config current-context)"
fi
[[ -n "$context" ]] || { printf '%s\n' 'Select a Kubernetes context.' >&2; exit 1; }

printf 'Target context: %s\nTarget namespace: %s\nSecret: %s/%s\n' \
    "$context" "$namespace" "$namespace" "$secret_name"
read -r -p 'Type yes to continue: ' confirmation
[[ "$confirmation" == 'yes' ]] || { printf '%s\n' 'No Secret was written.'; exit 1; }

read -r -s -p 'SigNoz Viewer API key (hidden): ' api_key
printf '\n'
[[ -n "$api_key" ]] || { printf '%s\n' 'The API key must not be empty.' >&2; exit 1; }
[[ ! "$api_key" =~ [[:space:]] ]] || { printf '%s\n' 'The API key must not contain whitespace.' >&2; exit 1; }

api_key_b64="$(printf '%s' "$api_key" | base64 | tr -d '\n')"
unset api_key

if result="$(printf 'apiVersion: v1\nkind: Secret\nmetadata:\n  name: %s\n  namespace: %s\ntype: Opaque\ndata:\n  %s: %s\n' \
    "$secret_name" "$namespace" "$secret_key" "$api_key_b64" |
    kubectl --kubeconfig "$kubeconfig" --context "$context" -n "$namespace" \
        apply --server-side --field-manager=cloudbank-bff-trace -f - 2>/dev/null)"; then
    printf '%s\n' "$result"
else
    printf '%s\n' 'Secret write failed. Check cluster access, RBAC and resource ownership; output withheld.' >&2
    exit 1
fi

unset api_key_b64
