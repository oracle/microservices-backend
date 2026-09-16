# OBaaS Helm Charts

This directory contains the Helm charts for Oracle Backend for Microservices and AI (OBaaS).

The current development charts deploy OBaaS application version **2.2.0**:

- `infra-charts/obaas-prereqs` — cluster-singleton prerequisites; install once per cluster.
- `infra-charts/obaas` — namespace-scoped OBaaS platform; install once per tenant or application namespace.
- `app-charts/obaas-sample-app` — sample application deployment chart.
- `infra-charts/tools` — utilities, including OCI configuration and image mirroring helpers.

## Chart layout

```text
helm/
├── app-charts/
│   └── obaas-sample-app/
└── infra-charts/
    ├── obaas-prereqs/
    ├── obaas/
    │   └── examples/
    └── tools/
```

## Installation overview

Before installing OBaaS:

1. Confirm cluster capacity, storage, database connectivity, and external-access requirements.
2. Install and verify cert-manager.
3. Install `obaas-prereqs` once for the cluster.
4. Install `obaas` in each application namespace.

For the current in-development version, use the local chart paths:

```bash
helm upgrade --install obaas-prereqs helm/infra-charts/obaas-prereqs \
  --namespace obaas-system \
  --create-namespace \
  --values helm/infra-charts/obaas-prereqs/examples/<values-file>.yaml

helm upgrade --install obaas helm/infra-charts/obaas \
  --namespace obaas \
  --create-namespace \
  --values helm/infra-charts/obaas/examples/<values-file>.yaml
```

Use `values-sidb-free.yaml` for an in-cluster development database or `values-existing-adb.yaml` for an existing Autonomous Database. See [`infra-charts/obaas/examples/README.md`](infra-charts/obaas/examples/README.md) for all supported scenarios.

## Important behavior

- `obaas-prereqs` is cluster-singleton. Do not install it separately for each tenant.
- Envoy Gateway is enabled by default.
- ingress-nginx is deprecated and disabled by default; enable it only for legacy Ingress API environments.
- SigNoz is enabled by default. Upgrading an existing release with SigNoz requires explicit destructive-replacement confirmation.
- For `SIDB-FREE` and `ADB-FREE`, review PVC retention before uninstalling. `global.cleanupPVCs: true` removes database storage on uninstall.

## Documentation and configuration

For complete prerequisites, database setup, cert-manager installation, OCI authentication, private-registry configuration, upgrade behavior, and verification steps, see the [Helm installation guide](https://oracle.github.io/microservices-backend/obaas/docs/setup/helm/).

The chart values and examples are authoritative:

- [`infra-charts/obaas/values.yaml`](infra-charts/obaas/values.yaml)
- [`infra-charts/obaas-prereqs/values.yaml`](infra-charts/obaas-prereqs/values.yaml)
- [`infra-charts/obaas/examples/`](infra-charts/obaas/examples/)
- [`infra-charts/obaas-prereqs/examples/`](infra-charts/obaas-prereqs/examples/)

## Uninstallation

Uninstall all namespace-scoped OBaaS releases before uninstalling the shared prerequisites release:

```bash
helm uninstall obaas --namespace obaas
helm uninstall obaas-prereqs --namespace obaas-system
```

Uninstalling prerequisites affects every OBaaS instance in the cluster.
