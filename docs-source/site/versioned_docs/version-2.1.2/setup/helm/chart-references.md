---
title: Dependent Helm Chart References
sidebar_position: 4
---

OBaaS 2.1.2 uses the dependent charts listed below. Each link is pinned to the
chart release bundled with this OBaaS release and opens the upstream chart's
rendered README or values file. Use these references when customizing a
component; do not copy the complete dependency values into OBaaS documentation.

| Chart | Version | Chart README | Values reference |
| --- | --- | --- | --- |
| `ai-optimizer` | 2.0.3 | [README](https://github.com/oracle/ai-optimizer/blob/v2.0.3/helm/README.md) | [values.yaml](https://github.com/oracle/ai-optimizer/blob/v2.0.3/helm/values.yaml) |
| `apisix` | 2.17.0 | [README](https://github.com/apache/apisix-helm-chart/blob/apisix-2.17.0/charts/apisix/README.md) | [values.yaml](https://github.com/apache/apisix-helm-chart/blob/apisix-2.17.0/charts/apisix/values.yaml) |
| `cert-manager` | v1.21.1 | [README template](https://github.com/cert-manager/cert-manager/blob/v1.21.1/deploy/charts/cert-manager/README.template.md) | [values.yaml](https://github.com/cert-manager/cert-manager/blob/v1.21.1/deploy/charts/cert-manager/values.yaml) |
| `coherence-operator` | 3.5.16 | [README](https://github.com/oracle/coherence-operator/blob/v3.5.16/helm-charts/coherence-operator/README.md) | [values.yaml](https://github.com/oracle/coherence-operator/blob/v3.5.16/helm-charts/coherence-operator/values.yaml) |
| `external-secrets` | 2.10.0 | [README](https://github.com/external-secrets/external-secrets/blob/helm-chart-2.10.0/deploy/charts/external-secrets/README.md) | [values.yaml](https://github.com/external-secrets/external-secrets/blob/helm-chart-2.10.0/deploy/charts/external-secrets/values.yaml) |
| `gateway-helm` | 1.8.2 | [README](https://github.com/envoyproxy/gateway/blob/6c2e80d5158926749b95e948d7aae36b9ae67669/charts/gateway-helm/README.md) | [values template](https://github.com/envoyproxy/gateway/blob/6c2e80d5158926749b95e948d7aae36b9ae67669/charts/gateway-helm/values.tmpl.yaml) |
| `ingress-nginx` | 4.15.1 | [README](https://github.com/kubernetes/ingress-nginx/blob/controller-v1.15.1/charts/ingress-nginx/README.md) | [values.yaml](https://github.com/kubernetes/ingress-nginx/blob/controller-v1.15.1/charts/ingress-nginx/values.yaml) |
| `k8s-infra` | 0.15.0 | [README](https://github.com/SigNoz/charts/blob/signoz-0.134.0/charts/k8s-infra/README.md) | [values.yaml](https://github.com/SigNoz/charts/blob/signoz-0.134.0/charts/k8s-infra/values.yaml) |
| `kube-state-metrics` | 6.4.1 | [README](https://github.com/prometheus-community/helm-charts/blob/kube-state-metrics-6.4.1/charts/kube-state-metrics/README.md) | [values.yaml](https://github.com/prometheus-community/helm-charts/blob/kube-state-metrics-6.4.1/charts/kube-state-metrics/values.yaml) |
| `metrics-server` | 3.14.0 | [README](https://github.com/kubernetes-sigs/metrics-server/blob/metrics-server-helm-chart-3.14.0/charts/metrics-server/README.md) | [values.yaml](https://github.com/kubernetes-sigs/metrics-server/blob/metrics-server-helm-chart-3.14.0/charts/metrics-server/values.yaml) |
| `opentelemetry-operator` | 0.122.0 | [README](https://github.com/open-telemetry/opentelemetry-helm-charts/blob/opentelemetry-operator-0.122.0/charts/opentelemetry-operator/README.md) | [values.yaml](https://github.com/open-telemetry/opentelemetry-helm-charts/blob/opentelemetry-operator-0.122.0/charts/opentelemetry-operator/values.yaml) |
| `signoz` | 0.134.0 | [README](https://github.com/SigNoz/charts/blob/signoz-0.134.0/charts/signoz/README.md) | [values.yaml](https://github.com/SigNoz/charts/blob/signoz-0.134.0/charts/signoz/values.yaml) |
| `strimzi-kafka-operator` | 1.1.0 | [README](https://github.com/strimzi/strimzi-kafka-operator/blob/1.1.0/packaging/helm-charts/helm3/strimzi-kafka-operator/README.md) | [values.yaml](https://github.com/strimzi/strimzi-kafka-operator/blob/1.1.0/packaging/helm-charts/helm3/strimzi-kafka-operator/values.yaml) |

## Vendored Oracle Database Operator

The `oracle-database-operator` chart is vendored locally at version 0.2.0 and
does not publish a matching upstream chart README and values page. To inspect
the exact chart bundled with OBaaS, run these commands from the chart checkout:

```bash
helm show readme helm/infra-charts/obaas-prereqs/charts/oracle-database-operator-0.2.0.tgz
helm show values helm/infra-charts/obaas-prereqs/charts/oracle-database-operator-0.2.0.tgz
```

The top-level `obaas` and `obaas-prereqs` values remain the authoritative
OBaaS-specific configuration references.
