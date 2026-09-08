# Changelog

## Unreleased

- Improve APISIX Eureka discovery resilience by configuring direct endpoints for all three Eureka replicas and increasing registry send and read timeouts.
- Keep Eureka Jetty connections open for 90 seconds by default, longer than APISIX/OpenResty's pooled connection lifetime, to avoid intermittent registry refresh failures caused by stale keepalive connections.
- Automatically register the required APISIX `opentelemetry` plugin_metadata via a sidecar container in the APISIX pod, eliminating the manual admin-API curl workaround and the recurring "plugin_metadata is required" warning.

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

- Adds the ability to create a Kafka cluster as part of the obaas chart installation

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

# 0.0.7 - Mar 12, 2026

AppVersion: 2.1.0-build.6

- Add OpenTelemetry Operator to enable auto-instrumentation via custom resources
- Fixes for private registry installation
- OTMM is updated
- Custom APISIX plugins are supported
- SigNoz cold storage is supported
- Config server is installed

# 0.0.8 - Mar 18, 2026

AppVersion: 2.1.0-build.7

- Strimzi operator updated to 0.51.0 and supports Kafka 4.2.0 deployment

# 0.0.9 - Mar 26, 2026

AppVersion: 2.1.0-build.8

- Fixes for Strimzi operator and Kafka
- Allow OpenTelemetry operator image to be installed from a private registry

# 0.0.10 - Apr 9, 2026

AppVersion: 2.1.0-build.9

- Fixes for Kafka cluster creation
- OSS Conductor removed (replaced by OTMM/MicroTx Workflow)

# 0.0.11 - Apr 16, 2026

AppVersion: 2.1.0-build.10

- Database Exporter updated to version 2.2.2
- Busybox updated to version 1.37
- Signoz updated to verion 0.113

# 0.0.12 - Apr 20, 2026

AppVersion: 2.1.0-build.11

- Allow custom Java env vars in Instrumentation CR

# 0.0.13 - Apr 27, 2026

AppVersion: 2.1.0-build.12

- Add Kafka metrics

# 0.0.14 - Jun 5, 2026

AppVersion: 2.1.0-build.13

- Restructure OTMM (MicroTX) values into independently toggleable `coordinator`, `workflowServer`, and `console` components, each with its own image and `pullPolicy`; the top-level `otmm.enabled` flag is removed
- The OTMM console now deploys only when the coordinator and/or workflow server is enabled; an explicit `otmm.console.enabled: true` is overridden when both are disabled. The console is wired only to the backends that are enabled (no dead coordinator/workflow endpoints in single-backend installs)
- Fix OTMM templates that still referenced the removed top-level `otmm.image`/`otmm.replicas`/`otmm.metrics` paths

# 0.0.15 - May 20, 2026

AppVersion: 2.1.0-build.14

- Allow `otelCollectorEndpoint` override in `Instrumentation` resource
- Update charts to version 0.0.14 and appVersion 2.1.0-build.13
- Align `obaas` and `obaas-prereqs` chart `kubeVersion` metadata with the documented Kubernetes 1.34+ minimum requirement.
- Remove database.enabled parameter; database resources are now controlled by the presence of the database values block
- Fix Config Server SigNoz metrics scrape path from /metrics to /actuator/prometheus
- Add template-time validation for database.type, failing fast with a clear error for missing or unsupported database configuration
- Component version revisions

# 0.1.0 - June 15, 2026

AppVersion: 2.1.0

- Production release of 2.1.0

# TBD

AppVersion 2.1.2
