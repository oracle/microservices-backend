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

