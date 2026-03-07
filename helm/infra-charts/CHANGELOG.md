# Changelog

## 0.0.1 - Feb 18, 2026

AppVersion: 2.0.0

- Initial release of Helm chart
- Allows install of OBaaS pre-requisties (once per cluster, shared) and 1..m OBaaS instances (in their own namespaces)
- Choose which components to install 
- Choose which namespace to install components into
- Customize components' configuration (anything supported by subcharts)
- Use different (private) image repository

## 0.0.2 - Feb 27, 2026

AppVersion: 2.1.0-build.1

- Fixes to allow installation in an airgapped environment, i.e., a k8s cluster that cannot access the public internet
- Update APISIX plugin configuration to include batch-requests
- Update SigNoz metrics collection config to include app label (for Helidon apps)
- Update SigNoz logs pipeline receivers config to include k8s_events

# 0.0.3 - Feb 28, 2026

AppVersion: 2.1.0-build.2

- Adds the ability to create a Kafaka cluster as part of the obaas chart installation

# 0.0.4 - Mar 1, 2026

AppVersion: 2.1.0-build.3

- Fix issue in oraOperator wait-for-certmgr job: was not creating imagePullSecret
- Fix issue in airgap patch job to handle imagePullSecret correctly
- Fix issue in otmm template to handle imagePullSecret correctly
- Update sample values files to specificy imagePullSecrets as required for each sub-chart

# 0.0.5 - Mar 3, 2026

AppVersion: 2.1.0-build.4

- Update otel-collector config to add k8s_events receiver
- Update rbac to allow otel-collector to get/list/watch events

# 0.0.6 - Mar 6, 2026

AppVersion: 2.1.0-build.5

- Add Envoy Gateway Controller Helm chart to `obaas`. The Envoy Gateway Controller implements the Kubernetes Gateway API as a replacement for `ingress-nginx`. Because the Gateway and Ingress APIs are separate, the gateway and ingress controllers may run concurrently.
- Add Spring Cloud Config Server
- Add ability to create extra arbitrary config maps, e.g., to hold code for custom APISIX plugins
- Add example of custom APISIX plugin configuration