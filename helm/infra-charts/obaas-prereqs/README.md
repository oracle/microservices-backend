# OBaaS Prerequisites Helm Chart

This chart contains cluster-scoped singleton infrastructure components required by the OBaaS platform.

## Overview

This chart must be installed **once per cluster** before installing any OBaaS instances. It provides:

- **external-secrets** - External secrets management
- **metrics-server** - Resource metrics for HPA and kubectl top
- **kube-state-metrics** - Kubernetes cluster state metrics
- **strimzi-kafka-operator** - Kafka cluster management via CRDs
- **clickhouse-operator CRDs** - Custom Resource Definitions for ClickHouse management (operator runs per-tenant namespace)
- **oracle-database-operator** - Oracle Database lifecycle management via CRDs
- **cert-manager** (subchart) - Certificate management and issuance.

## Installation

### Prerequisites

- Kubernetes >= 1.34.0
- Helm 3.x

### Install Prerequisites (once per cluster)

```bash
# Install prerequisites
helm upgrade --install obaas-prereqs . --create-namespace -n obaas-system

# Or with custom values
helm upgrade --install obaas-prereqs . -n obaas-system --create-namespace --values <path_to_custom_values>.yaml
```

**Note:** All prerequisite components will be installed into the `obaas-system` namespace. While these components operate cluster-wide and manage cluster-scoped resources (CRDs, cluster roles, etc.), their deployments, services, and other namespaced resources will reside in `obaas-system`.

### Verify Metrics Server

Metrics Server is working when its aggregated APIService is available and
`kubectl top` returns current node or pod usage:

```bash
kubectl get apiservice v1beta1.metrics.k8s.io
kubectl top nodes
kubectl top pods -n <application-namespace>
```

The APIService should report `Available=True`; an empty `kubectl top` result
immediately after startup can be normal while the first scrape completes.

### After Prerequisites are Installed

Once the prerequisites are installed, you can install the main OBaaS chart multiple times in different namespaces:

```bash
# Install OBaaS instance for tenant-1
helm upgrade --install obaas-tenant1 ../obaas -n tenant1 --create-namespace

# Install OBaaS instance for tenant-2
helm upgrade --install obaas-tenant2 ../obaas -n tenant2 --create-namespace
```

## Configuration

See `values.yaml` for all configuration options.

### Common Configurations

**Using Private Container Registries:**

All component images can be overridden to use a private registry. See `values.yaml` for detailed configuration options for each component. Image override settings are commented out by default and use upstream defaults when not specified.

```yaml
global:
  imagePullSecrets:
    - name: myregistry-secret

# Example: Override specific component images
# See values.yaml for complete configuration options
```

**Restrict Kafka operator to specific namespaces:**
```yaml
strimzi-kafka-operator:
  watchAnyNamespace: false
  watchNamespaces:
    - tenant1
    - tenant2
```

**Configure Oracle Database Operator:**
```yaml
oracle-database-operator:
  enabled: true
  # Uncomment to override default image for air-gapped installations
  # image:
  #   registry: myregistry.example.com
  #   repository: database/operator
  #   tag: "2.1.0"
  # Uncomment to watch specific namespace instead of all namespaces
  # watchNamespace: "tenant1"
```

**AKS-specific note for metrics-server:**

AKS clusters can already have `metrics-server` installed through the AKS addon path. If that addon is present, disable the chart-managed `metrics-server` to avoid installing a duplicate copy:

```yaml
metrics-server:
  enabled: false
```

## Uninstallation

**Warning:** Uninstalling this chart will remove cluster-wide operators and may affect all OBaaS instances.

```bash
helm uninstall obaas-prereqs -n obaas-system
```

## Architecture

These components are cluster-scoped singletons because:
- They install CRDs (Custom Resource Definitions) which are cluster-scoped
- Multiple installations would conflict
- They provide cluster-wide functionality

The main OBaaS chart can be installed multiple times and will use these shared infrastructure components.

### ClickHouse Operator Architecture

Unlike other operators in this chart, the **ClickHouse Operator** follows a hybrid approach:

- **CRDs (in prereqs)**: Installed once cluster-wide via this chart (manually maintained in `templates/`)
- **Operator (in tenant namespaces)**: Each tenant gets its own namespace-scoped operator via the SigNoz subchart in the main OBaaS chart

**Why this design?**
- CRDs are cluster-scoped and can only be installed once
- Each tenant needs an isolated operator for their observability stack
- The main OBaaS chart includes a pre-delete hook to prevent namespaces from getting stuck during uninstall

**Maintenance:** See [CLICKHOUSE-CRD-MAINTENANCE.md](./CLICKHOUSE-CRD-MAINTENANCE.md) for instructions on updating ClickHouse CRDs when upgrading operator versions.
