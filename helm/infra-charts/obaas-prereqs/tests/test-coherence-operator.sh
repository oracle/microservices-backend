#!/usr/bin/env bash
# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at http://oss.oracle.com/licenses/upl.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="${CHART_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)}"

OBAAS_PREREQS_RELEASE="${OBAAS_PREREQS_RELEASE:-obaas-prereqs-test}"
OBAAS_PREREQS_NAMESPACE="${OBAAS_PREREQS_NAMESPACE:-obaas-prereqs-test}"
COHERENCE_TEST_NAMESPACE="${COHERENCE_TEST_NAMESPACE:-coherence-operator-test}"
COHERENCE_TEST_CLUSTER="${COHERENCE_TEST_CLUSTER:-coherence-smoke}"
TIMEOUT="${TIMEOUT:-10m}"
KEEP_TEST_RESOURCES="${KEEP_TEST_RESOURCES:-false}"
INSTALL_PREREQS="${INSTALL_PREREQS:-true}"

cleanup() {
  if [[ "${KEEP_TEST_RESOURCES}" == "true" ]]; then
    return
  fi

  kubectl delete coherence "${COHERENCE_TEST_CLUSTER}" \
    -n "${COHERENCE_TEST_NAMESPACE}" \
    --ignore-not-found=true \
    --wait=true >/dev/null 2>&1 || true
  if [[ "${INSTALL_PREREQS}" == "true" ]]; then
    helm uninstall "${OBAAS_PREREQS_RELEASE}" \
      -n "${OBAAS_PREREQS_NAMESPACE}" >/dev/null 2>&1 || true
    kubectl delete namespace "${OBAAS_PREREQS_NAMESPACE}" \
      --ignore-not-found=true \
      --wait=false >/dev/null 2>&1 || true
  fi
  kubectl delete namespace "${COHERENCE_TEST_NAMESPACE}" \
    --ignore-not-found=true \
    --wait=false >/dev/null 2>&1 || true
}
trap cleanup EXIT

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_command helm
require_command kubectl

kubectl cluster-info >/dev/null

if [[ "${INSTALL_PREREQS}" == "true" ]]; then
  helm upgrade --install "${OBAAS_PREREQS_RELEASE}" "${CHART_DIR}" \
    -n "${OBAAS_PREREQS_NAMESPACE}" \
    --create-namespace \
    --set external-secrets.enabled=false \
    --set metrics-server.enabled=false \
    --set kube-state-metrics.enabled=false \
    --set strimzi-kafka-operator.enabled=false \
    --set opentelemetry-operator.enabled=false \
    --set oracle-database-operator.enabled=false \
    --set coherence-operator.enabled=true \
    --set coherence-operator.replicas=1 \
    --wait \
    --timeout "${TIMEOUT}"
fi

kubectl rollout status deployment/coherence-operator \
  -n "${OBAAS_PREREQS_NAMESPACE}" \
  --timeout "${TIMEOUT}"

kubectl get deployment/coherence-operator \
  -n "${OBAAS_PREREQS_NAMESPACE}" \
  -o jsonpath='{.spec.template.spec.containers[?(@.name=="manager")].image}{"\n"}' \
  | grep -Fx 'container-registry.oracle.com/middleware/coherence-operator:3.5.16'

kubectl wait --for=condition=Established \
  crd/coherence.coherence.oracle.com \
  crd/coherencejob.coherence.oracle.com \
  --timeout "${TIMEOUT}"

kubectl create namespace "${COHERENCE_TEST_NAMESPACE}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -n "${COHERENCE_TEST_NAMESPACE}" -f - <<EOF
apiVersion: coherence.oracle.com/v1
kind: Coherence
metadata:
  name: ${COHERENCE_TEST_CLUSTER}
spec:
  replicas: 1
  jvm:
    memory:
      heapSize: 256m
EOF

kubectl wait -n "${COHERENCE_TEST_NAMESPACE}" \
  --for=jsonpath='{.status.readyReplicas}'=1 \
  "coherence/${COHERENCE_TEST_CLUSTER}" \
  --timeout "${TIMEOUT}"

kubectl get "coherence/${COHERENCE_TEST_CLUSTER}" \
  -n "${COHERENCE_TEST_NAMESPACE}" \
  -o jsonpath='{.status.phase}{"\n"}'

echo "Coherence Operator smoke test passed"
