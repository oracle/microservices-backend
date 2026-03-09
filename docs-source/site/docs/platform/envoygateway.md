---
title: Envoy Gateway
sidebar_position: 7
---

## Envoy Gateway

[Envoy Gateway](https://gateway.envoyproxy.io/) is an open-source, CNCF graduated implementation of the [Kubernetes Gateway API](https://gateway-api.sigs.k8s.io/). The Gateway API provides L4 and L7 routing in Kubernetes, iterating on the prior Kubernetes Ingress, Load Balancing, and Service Mesh APIs.

### Installing Envoy Gateway

Envoy Gateway will be installed if `gateway-helm.enabled` is set to `true` in the `values.yaml` file. The default namespace for the Envoy Gateway is the chart installation namespace.

### Admin UI

To access the Envoy Gateway Admin UI, use kubectl port-forward to create a secure channel to `deployment/envoy-gateway`. Run the following command to establish the secure tunnel (replace the example namespace `obaas-dev` with the namespace where Envoy Gateway is deployed):

```shell
kubectl port-forward -n obaas-dev deployment/envoy-gateway 19000:19000
```
