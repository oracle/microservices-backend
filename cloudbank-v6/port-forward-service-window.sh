#!/usr/bin/env bash

if [[ $# -ne 4 ]]; then
    printf 'Usage: %s <context> <namespace> <service> <port-mapping>\n' "${0##*/}" >&2
    exit 2
fi

KUBE_CONTEXT="$1"
NAMESPACE="$2"
SERVICE="$3"
PORT_MAPPING="$4"

printf 'Context: %s\nNamespace: %s\nService: %s\nForwarding: %s\n\n' "$KUBE_CONTEXT" "$NAMESPACE" "$SERVICE" "$PORT_MAPPING"
kubectl --context "$KUBE_CONTEXT" --namespace "$NAMESPACE" port-forward --address 127.0.0.1 "service/$SERVICE" "$PORT_MAPPING"
STATUS=$?

printf '\nPort-forward exited with status %s.\n' "$STATUS"
if [[ -t 0 ]]; then
    read -r -p 'Press Enter to close this window...' _
fi

exit "$STATUS"
