---
title: Dependent Helm Chart References
sidebar_position: 4
---

OBaaS 2.1.2 uses the dependent charts listed below. Each link is pinned to the
chart release bundled with this OBaaS release and opens the upstream chart's
rendered README or values file. Use these references when customizing a
component; do not copy the complete dependency values into OBaaS documentation.

<table aria-label="Dependent Helm Chart References table">
  <thead>
    <tr>
      <th scope="col">Chart</th>
      <th scope="col">Version</th>
      <th scope="col">Chart README</th>
      <th scope="col">Values reference</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <th scope="row"><code>ai-optimizer</code></th>
      <td>2.0.3</td>
      <td><a href="https://github.com/oracle/ai-optimizer/blob/v2.0.3/helm/README.md" target="_blank" rel="noopener noreferrer">README</a></td>
      <td><a href="https://github.com/oracle/ai-optimizer/blob/v2.0.3/helm/values.yaml" target="_blank" rel="noopener noreferrer">values.yaml</a></td>
    </tr>
    <tr>
      <th scope="row"><code>apisix</code></th>
      <td>2.17.0</td>
      <td><a href="https://github.com/apache/apisix-helm-chart/blob/apisix-2.17.0/charts/apisix/README.md" target="_blank" rel="noopener noreferrer">README</a></td>
      <td><a href="https://github.com/apache/apisix-helm-chart/blob/apisix-2.17.0/charts/apisix/values.yaml" target="_blank" rel="noopener noreferrer">values.yaml</a></td>
    </tr>
    <tr>
      <th scope="row"><code>cert-manager</code></th>
      <td>v1.21.1</td>
      <td><a href="https://github.com/cert-manager/cert-manager/blob/v1.21.1/deploy/charts/cert-manager/README.template.md" target="_blank" rel="noopener noreferrer">README template</a></td>
      <td><a href="https://github.com/cert-manager/cert-manager/blob/v1.21.1/deploy/charts/cert-manager/values.yaml" target="_blank" rel="noopener noreferrer">values.yaml</a></td>
    </tr>
    <tr>
      <th scope="row"><code>coherence-operator</code></th>
      <td>3.5.16</td>
      <td><a href="https://github.com/oracle/coherence-operator/blob/v3.5.16/helm-charts/coherence-operator/README.md" target="_blank" rel="noopener noreferrer">README</a></td>
      <td><a href="https://github.com/oracle/coherence-operator/blob/v3.5.16/helm-charts/coherence-operator/values.yaml" target="_blank" rel="noopener noreferrer">values.yaml</a></td>
    </tr>
    <tr>
      <th scope="row"><code>external-secrets</code></th>
      <td>2.10.0</td>
      <td><a href="https://github.com/external-secrets/external-secrets/blob/helm-chart-2.10.0/deploy/charts/external-secrets/README.md" target="_blank" rel="noopener noreferrer">README</a></td>
      <td><a href="https://github.com/external-secrets/external-secrets/blob/helm-chart-2.10.0/deploy/charts/external-secrets/values.yaml" target="_blank" rel="noopener noreferrer">values.yaml</a></td>
    </tr>
    <tr>
      <th scope="row"><code>gateway-helm</code></th>
      <td>1.8.2</td>
      <td><a href="https://github.com/envoyproxy/gateway/blob/6c2e80d5158926749b95e948d7aae36b9ae67669/charts/gateway-helm/README.md" target="_blank" rel="noopener noreferrer">README</a></td>
      <td><a href="https://github.com/envoyproxy/gateway/blob/6c2e80d5158926749b95e948d7aae36b9ae67669/charts/gateway-helm/values.tmpl.yaml" target="_blank" rel="noopener noreferrer">values template</a></td>
    </tr>
    <tr>
      <th scope="row"><code>ingress-nginx</code></th>
      <td>4.15.1</td>
      <td><a href="https://github.com/kubernetes/ingress-nginx/blob/controller-v1.15.1/charts/ingress-nginx/README.md" target="_blank" rel="noopener noreferrer">README</a></td>
      <td><a href="https://github.com/kubernetes/ingress-nginx/blob/controller-v1.15.1/charts/ingress-nginx/values.yaml" target="_blank" rel="noopener noreferrer">values.yaml</a></td>
    </tr>
    <tr>
      <th scope="row"><code>k8s-infra</code></th>
      <td>0.15.0</td>
      <td><a href="https://github.com/SigNoz/charts/blob/signoz-0.134.0/charts/k8s-infra/README.md" target="_blank" rel="noopener noreferrer">README</a></td>
      <td><a href="https://github.com/SigNoz/charts/blob/signoz-0.134.0/charts/k8s-infra/values.yaml" target="_blank" rel="noopener noreferrer">values.yaml</a></td>
    </tr>
    <tr>
      <th scope="row"><code>kube-state-metrics</code></th>
      <td>6.4.1</td>
      <td><a href="https://github.com/prometheus-community/helm-charts/blob/kube-state-metrics-6.4.1/charts/kube-state-metrics/README.md" target="_blank" rel="noopener noreferrer">README</a></td>
      <td><a href="https://github.com/prometheus-community/helm-charts/blob/kube-state-metrics-6.4.1/charts/kube-state-metrics/values.yaml" target="_blank" rel="noopener noreferrer">values.yaml</a></td>
    </tr>
    <tr>
      <th scope="row"><code>metrics-server</code></th>
      <td>3.14.0</td>
      <td><a href="https://github.com/kubernetes-sigs/metrics-server/blob/metrics-server-helm-chart-3.14.0/charts/metrics-server/README.md" target="_blank" rel="noopener noreferrer">README</a></td>
      <td><a href="https://github.com/kubernetes-sigs/metrics-server/blob/metrics-server-helm-chart-3.14.0/charts/metrics-server/values.yaml" target="_blank" rel="noopener noreferrer">values.yaml</a></td>
    </tr>
    <tr>
      <th scope="row"><code>opentelemetry-operator</code></th>
      <td>0.122.0</td>
      <td><a href="https://github.com/open-telemetry/opentelemetry-helm-charts/blob/opentelemetry-operator-0.122.0/charts/opentelemetry-operator/README.md" target="_blank" rel="noopener noreferrer">README</a></td>
      <td><a href="https://github.com/open-telemetry/opentelemetry-helm-charts/blob/opentelemetry-operator-0.122.0/charts/opentelemetry-operator/values.yaml" target="_blank" rel="noopener noreferrer">values.yaml</a></td>
    </tr>
    <tr>
      <th scope="row"><code>signoz</code></th>
      <td>0.134.0</td>
      <td><a href="https://github.com/SigNoz/charts/blob/signoz-0.134.0/charts/signoz/README.md" target="_blank" rel="noopener noreferrer">README</a></td>
      <td><a href="https://github.com/SigNoz/charts/blob/signoz-0.134.0/charts/signoz/values.yaml" target="_blank" rel="noopener noreferrer">values.yaml</a></td>
    </tr>
    <tr>
      <th scope="row"><code>strimzi-kafka-operator</code></th>
      <td>1.1.0</td>
      <td><a href="https://github.com/strimzi/strimzi-kafka-operator/blob/1.1.0/packaging/helm-charts/helm3/strimzi-kafka-operator/README.md" target="_blank" rel="noopener noreferrer">README</a></td>
      <td><a href="https://github.com/strimzi/strimzi-kafka-operator/blob/1.1.0/packaging/helm-charts/helm3/strimzi-kafka-operator/values.yaml" target="_blank" rel="noopener noreferrer">values.yaml</a></td>
    </tr>
  </tbody>
</table>

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
