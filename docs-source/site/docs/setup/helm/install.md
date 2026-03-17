---
title: Helm Chart installation
sidebar_position: 3
---
## Oracle Backend for Microservices and AI (OBaaS) Helm Charts

This document describes how to deploy OBaaS to an existing Kubernetes cluster using Helm charts.

- [Quick Start Decision Guide](#quick-start-decision-guide) — Choose the right example values file for your deployment
- [Architecture](#architecture) — Two-chart design, components, and cluster layout
- [Prerequisites](#prerequisites) — Required tools and cluster access
- [Names and Namespace Conventions](#names-and-namespace-conventions) — Replace example release names and namespaces with your own values
- [Installation Guide](#installation-guide) — Step-by-step deployment process
- [Example Configurations](#example-configurations) — Common deployment scenarios:
  - [Default](#default-configuration-values-defaultyaml) — Quick start with no overrides
  - [SIDB-FREE Database](#sidb-free-database-values-sidb-freeyaml) — In-cluster Oracle Database Free container
  - [Existing ADB](#existing-adb-configuration-values-existing-adbyaml) — Connect to a pre-provisioned Autonomous Database
  - [Other Existing Database](#other-existing-database-values-byodbyaml) - Connect to another type of pre-existing Oracle AI Database, for example an Oracle Base DB, or an on-premises Oracle Database
  - [Multi-Tenant](#multi-tenant-setup-values-tenant1yaml-values-tenant2yaml) — Run multiple OBaaS instances in one cluster
  - [Namespace and Scope](#namespace-and-scope-configuration-values-namespace-overrideyaml) — Control which namespaces components watch
  - [SigNoz Existing Secret](#signoz-existing-secret-values-signoz-existing-secretyaml) — Pre-provisioned SigNoz credentials
  - [SigNoz Cold Storage](#signoz-cold-storage-values-signoz-cold-storageyaml) — Offload older observability data to S3-compatible object storage
  - [Private Registry](#private-registry-configuration-values-private-registryyaml) — Air-gapped and corporate registry setups
  - [Combining Examples](#combining-examples) — Layer multiple values files together
- [Uninstallation](#uninstallation) — Teardown instructions
- [Next Steps](#next-steps) — Deploy applications and configure observability

### Quick Start Decision Guide

Choose the example values file that best matches your deployment scenario:

- `values-default.yaml` - Minimal installation with default settings
- `values-sidb-free.yaml` - Development or testing with an in-cluster Oracle Database Free container
- `values-existing-adb.yaml` - Production deployments using an existing OCI Autonomous Database
- `values-byodb.yaml` - Production deployments using an existing non-Autonomous Oracle Database
- `values-tenant1.yaml` and `values-tenant2.yaml` - Multi-tenant deployments in a shared cluster
- `values-namespace-override.yaml` - Custom ingress namespace watching behavior
- `values-signoz-existing-secret.yaml` - Pre-provisioned SigNoz admin credentials
- `values-signoz-cold-storage.yaml` - Long-term observability retention using S3-compatible object storage
- `values-private-registry.yaml` - Air-gapped or private registry environments

If you are unsure where to start, use `values-sidb-free.yaml` for evaluation or `values-existing-adb.yaml` for an external OCI Autonomous Database deployment.

### Architecture

The deployment uses a two-chart architecture. The charts are separated because the OBaaS prerequisites chart installs cluster-wide CRDs and operators that may only exist once in a cluster, while the OBaaS chart contains namespace-scoped resources that can be safely installed multiple times.

**obaas-prereqs** (cluster-scoped, install once):

- **cert-manager** - Automatic TLS certificate management
- **external-secrets** - Integration with external secret stores
- **metrics-server** - Container resource metrics
- **kube-state-metrics** - Kubernetes object metrics
- **strimzi-kafka-operator** - Kafka cluster operator
- **oraoperator** - Oracle Database Operator for Kubernetes

:::danger Warning
Attempting to install the obaas-prereqs chart multiple times will cause CRD version conflicts, duplicate operator controllers, and resource contention.
:::

**obaas** (namespace-scoped, install per tenant):

- **ingress-nginx** - Namespace-specific ingress controller
- **Apache APISIX** - API Gateway
- **Eureka** - Service discovery
- **Signoz** - Observability stack with ClickHouse
- **Spring Boot Admin** - Application monitoring
- **Conductor** - Workflow orchestration
- **OTMM** - Transaction manager for microservices

Each instance operates independently in its own namespace with its own ingress controller and observability stack.

```tree
Cluster
├── obaas-system namespace (prerequisites - install once)
│   ├── cert-manager
│   ├── external-secrets
│   ├── metrics-server
│   ├── kube-state-metrics
│   └── strimzi-kafka-operator (manages Kafka CRs across all namespaces)
├── tenant1 namespace (OBaaS instance 1)
│   ├── ingress-nginx
│   ├── APISIX, Eureka, Coherence, etc.
│   ├── Kafka cluster (CR managed by Strimzi)
│   └── Signoz + ClickHouse
└── tenant2 namespace (OBaaS instance 2)
    ├── ingress-nginx
    ├── APISIX, Eureka, Coherence, etc.
    ├── Kafka cluster (CR managed by Strimzi)
    └── Signoz + ClickHouse
```

**Namespace behavior:** All OBaaS chart components deploy to the release namespace (specified with the `-n` flag during install). By default, ingress-nginx watches only its own release namespace (`scope.enabled: true`).

**Directory structure:**

```tree
helm/infra-charts/
├── obaas-prereqs/         # Cluster-singleton prerequisites (install once per cluster)
└── obaas/                 # OBaaS application chart (install N times in different namespaces)
    └── examples/          # Example values files for different scenarios
```

### Application & Privileged Database User

During installation, the Helm chart sets up two database users with different privilege levels:

| User | Purpose | Created by |
|------|---------|------------|
| **SYSTEM** (non-ADB) or **ADMIN** (ADB) | Privileged user for one-time database initialization | Pre-exists (external DBs) or auto-generated (container DBs) |
| **OBAAS_USER** | Application-level user for runtime platform operations | Created by the init script during first install |

**OBAAS_USER** is the unprivileged database identity used by OBaaS components at runtime. The privileged user is only used once — to create OBAAS_USER and grant it the
minimum permissions the platform needs.

<details>

<summary>What OBAAS_USER is granted</summary>

The init script grants the following permissions:

- **DB_DEVELOPER_ROLE** (Oracle 21c+). On Oracle 19c or earlier, falls back to `CREATE SESSION`.
- **SELECT on monitoring views** Required by the Oracle Database Exporter for Prometheus metrics.
- **Unlimited quota** on its default tablespace.
- **ADB only:** `EXECUTE ON DBMS_CLOUD_AI` and `EXECUTE ON DBMS_CLOUD_PIPELINE` for the AI Optimizer feature.

</details>

<details>

<summary>Which components use OBAAS_USER</summary>

Two components read the `<release>-db-authn` Secret at runtime:

- **Oracle Database Exporter** — connects as OBAAS_USER to query the monitoring views for Prometheus metrics.
- **Database init container** — uses the credentials during initialization to create the user and verify connectivity.

Other platform components (Eureka, Admin Server, Conductor) connect to the database through their own Spring Boot datasource configuration and do not use OBAAS_USER.

</details>

:::tip Bring Your Own Application User
To use a pre-existing database user instead of the auto-generated OBAAS_USER, create a Secret with your credentials and reference it via `database.authN.secretName`. The init script will skip user creation if the named user already exists in `DBA_USERS`.
:::

### Prerequisites

:::warning Important
Ensure all [prerequisites](./prereqs.md) are met before starting the deployment.
:::

Verify that you have the required tools installed:

```bash
# Verify Helm installation
helm version

# Verify kubectl and cluster access
kubectl get nodes
```

### Names and Namespace Conventions

The release names `obaas` and `obaas-prereqs`, along with the namespace names `obaas` and `obaas-system`, are used throughout this document as examples only. Replace them with the release names and namespaces that match your environment.

- `obaas` - example Helm release name for the OBaaS application chart
- `obaas-prereqs` - example Helm release name for the prerequisites chart
- `obaas` - example namespace for namespace-scoped OBaaS application components
- `obaas-system` - example namespace for the cluster-scoped prerequisites chart

All namespace-scoped OBaaS resources are deployed into the namespace provided with the `-n` flag in the Helm and `kubectl` commands, and the prerequisites chart is installed once per cluster into the namespace you choose for those cluster-level resources.

For example:

```bash
helm upgrade --install <prereqs-release> obaas/obaas-prereqs -n <platform-system-namespace> --create-namespace [--debug]
helm upgrade --install <app-release> obaas/obaas -n <application-namespace> --create-namespace [--debug]
kubectl get pods -n <platform-system-namespace>
kubectl get pods -n <application-namespace>
```

If you are deploying multiple OBaaS instances in the same cluster, each instance should use its own namespace. The prerequisite chart should still be installed once per cluster in a single shared namespace of your choice.

### Installation Guide

#### Step 0: Configure Helm Repository

Add the Helm repository to your local Helm installation using the following commands:

```bash
helm repo add obaas https://oracle.github.io/microservices-backend/helm
helm repo update
```

#### Step 1: Install cert-manager

OBaaS requires [cert-manager](https://cert-manager.io/) as a prerequisite. If you do not have cert-manager installed on your cluster, install it now:

```shell
helm install \
  cert-manager oci://quay.io/jetstack/charts/cert-manager \
  --version v1.19.1 \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true \
  --set crds.keep=false
```

#### Step 2: Install Prerequisites (Once Per Cluster)

:::warning Cluster-Scoped Installation
Only install prerequisites once per cluster. Installing multiple times will cause CRD conflicts and duplicate operator controllers.
:::

```bash
helm upgrade --install <prereqs-release> obaas/obaas-prereqs -n <platform-system-namespace> --create-namespace [--debug] [--values <path_to_custom_values>]
```

Verify all prerequisite pods are running before proceeding:

```bash
kubectl get pods -n <platform-system-namespace>
```

All pods should reach `Running` status within 2-3 minutes.

#### Step 3: Choose a Values File and Install OBaaS

Choose an example configuration that matches your deployment scenario and install:

```bash
helm upgrade --install <app-release> obaas/obaas -f examples/<values-file>.yaml -n <application-namespace> --create-namespace [--debug]
```

See [Example Configurations](#example-configurations) below for the full list of available examples.

Monitor the installation:

```bash
kubectl get pods -n <application-namespace> -w
```

:::tip First Deployment
It may take 5-10 additional minutes for all pods to reach Running state.
:::

#### Step 4: Verify Installation

After installation completes, verify all components are running:

```bash
kubectl get pods -A
```

**Expected results:**

- All pods in `Running` state
- Services with ClusterIP or LoadBalancer IPs assigned
- Ingress configured with your hostname

### Example Configurations

Several example configurations are provided for comparison.

| Values file | Best for | External DB required | Notes |
|---|---|---|---|
| `values-default.yaml` | Minimal evaluation | No | Uses chart defaults |
| `values-sidb-free.yaml` | Development and testing | No | Runs Oracle Database Free in the cluster |
| `values-existing-adb.yaml` | OCI production | Yes | Uses Autonomous Database |
| `values-byodb.yaml` | Existing Oracle Database | Yes | Non-Autonomous Oracle Database only |
| `values-tenant1.yaml`, `values-tenant2.yaml` | Multi-tenant setups | Depends | Requires unique ingress settings per tenant |
| `values-namespace-override.yaml` | Namespace watch tuning | Depends | Adjusts ingress scope |
| `values-signoz-existing-secret.yaml` | GitOps and pre-created credentials | Depends | Uses an existing SigNoz secret |
| `values-signoz-cold-storage.yaml` | Long-term observability retention | Depends | Uses S3-compatible object storage |
| `values-private-registry.yaml` | Air-gapped and private registry installs | Depends | Mirrors images to a private registry |

#### Default Configuration (`values-default.yaml`)

Minimal configuration with no overrides. All subcharts use their default settings.

**Use case:** Quick start, development, testing

**Installation:**

```bash
helm upgrade --install <app-release> obaas/obaas -f examples/values-default.yaml -n <application-namespace> --create-namespace [--debug]
```

#### SIDB-FREE Database (`values-sidb-free.yaml`)

:::warning Important
If you use SIDB, you may need more ephemeral storage on your nodes.  Please refer to [prerequisites](./prereqs.md) for details.
:::

Uses Oracle Database Free as an in-cluster container. This is the default database type.

**Use case:** Development, testing, standalone deployments

**Installation:**

```bash
helm upgrade --install <app-release> obaas/obaas -f examples/values-sidb-free.yaml -n <application-namespace> --create-namespace [--debug]
```

#### Existing ADB Configuration (`values-existing-adb.yaml`)

Connects to an existing OCI Autonomous Database (ADB-S) instead of deploying a database container.

**Use case:** Production deployments using a pre-provisioned OCI Autonomous Database

<details>
<summary>Prerequisites: Create required secrets before installing</summary>

1. Create the OCI API key secret.

   ```bash
   python3 tools/oci_config.py --namespace <application-namespace> [--config <config-file>] [--profile <profile-name>]
   ```

   :::note
   Python 3.12 or later is required to run the `oci_config.py` script.
   :::

1. Create the privileged authentication secret for the `ADMIN` user. Replace `<db-name>` with the name of your database.

   ```bash
    kubectl -n <application-namespace> create secret generic <db-name>-db-priv-authn \
      --from-literal=username=ADMIN \
      --from-literal=password=<admin-password> \
      --from-literal=service=<db-name>_tp
   ```

1. Optional: create the application user secret for `OBAAS_USER`. Replace `<db-name>` with the name of your database.

   ```bash
    kubectl -n <application-namespace> create secret generic <db-name>-db-authn \
      --from-literal=username=OBAAS_USER \
      --from-literal=password=<app-user-password> \
      --from-literal=service=<db-name>_tp
   ```

</details>

**Installation:**

The `--set database.authN.secretName=<app-user-secret>` argument is optional.

```bash
helm upgrade --install <app-release> obaas/obaas \
  -n <application-namespace> \
  -f examples/values-existing-adb.yaml \
  --set database.oci.ocid=<adb-ocid> \
  --set database.privAuthN.secretName=<admin-user-secret> \
  --set database.authN.secretName=<app-user-secret> \
  [--debug]
```

#### Other Existing Database (`values-byodb.yaml`)

Connects to an existing Oracle AI Database using a connect string and user credentials.
Do not use this option for an Oracle Autonomous Database.  This is a good option for
an Oracle Base DB or an on-premises Oracle AI Database.

**Use case:** Production deployments using a pre-existing Oracle AI Database (non-Autonomous)

<details>
<summary>Prerequisites: Create required secrets before installing</summary>

1. Create the privileged authentication secret for an appropriate admin user.

   ```bash
   kubectl -n <application-namespace> create secret generic <db-name>-db-priv-authn \
     --from-literal=username=SYSTEM \
     --from-literal=password=<system-password> \
     --from-literal=service=<service-name>
   ```

1. Use an admin user with DBA privileges that can create application users and grant the required permissions. The `SYSTEM` user is a good choice. This user should not require the `SYSDBA` role.

1. Ensure the admin user has the following permissions:

  ```sql
  SELECT WITH ADMIN OPTION on:
    DBA_TABLESPACE_USAGE_METRICS, DBA_TABLESPACES,
    GV_$SYSTEM_WAIT_CLASS, GV_$ASM_DISKGROUP_STAT, GV_$DATAFILE,
    GV_$SYSSTAT, GV_$PROCESS, GV_$WAITCLASSMETRIC, GV_$SESSION,
    GV_$RESOURCE_LIMIT, GV_$PARAMETER, GV_$DATABASE,
    GV_$SQLSTATS, GV_$SYSMETRIC, V_$DIAG_ALERT_EXT

  EXECUTE WITH GRANT OPTION on:
    SYS.DBMS_AQ, SYS.DBMS_AQADM, SYS.DBMS_AQIN,
    SYS.DBMS_AQIN, SYS.DBMS_AQJMS_INTERNAL
  ```

1. Review and update the database connection details in `examples/values-byodb.yaml`.

</details>

**Installation:**

```bash
helm upgrade --install <app-release> obaas/obaas \
  -n <application-namespace> \
  -f examples/values-byodb.yaml \
  [--debug]
```

#### Multi-Tenant Setup (`values-tenant1.yaml`, `values-tenant2.yaml`)

Configures unique IngressClass and credentials for each tenant to allow multiple OBaaS instances in the same cluster.

**Use case:** Multi-tenant deployments, namespace isolation

Each tenant **must** have unique values for the following to avoid conflicts:

- `controller.ingressClass`
- `controller.ingressClassResource.name`
- `controller.ingressClassResource.controllerValue`
- `controller.electionID`

**Installation:**

```bash
# Install first tenant
helm upgrade --install <tenant1-release> obaas/obaas -n <tenant1-namespace> -f examples/values-tenant1.yaml --create-namespace [--debug]

# Install second tenant
helm upgrade --install <tenant2-release> obaas/obaas -n <tenant2-namespace> -f examples/values-tenant2.yaml --create-namespace [--debug]
```

#### Namespace and Scope Configuration (`values-namespace-override.yaml`)

Demonstrates how to configure the ingress-nginx watching scope. All OBaaS components deploy to the release namespace (specified with the `-n` flag).

**Use case:** Controlling which namespaces components watch

**Installation:**

```bash
helm upgrade --install <app-release> obaas/obaas -f examples/values-namespace-override.yaml -n <application-namespace> --create-namespace [--debug]
```

#### SigNoz Existing Secret (`values-signoz-existing-secret.yaml`)

Uses a pre-existing Kubernetes secret for SigNoz admin authentication instead of auto-generating one.

**Use case:** GitOps workflows, pre-provisioned credentials

**Prerequisites:**

1. Create the secret before installing the chart.

**Installation:**

```bash
# Create the secret first
kubectl create secret generic my-signoz-secret \
  --from-literal=email=admin@mydomain.com \
  --from-literal=password=my-secure-password \
  -n <application-namespace>

# Install with the example
helm upgrade --install <app-release> obaas/obaas -f examples/values-signoz-existing-secret.yaml -n <application-namespace> [--debug]
```

#### SigNoz Cold Storage (`values-signoz-cold-storage.yaml`)

Configures SigNoz ClickHouse cold storage so recent telemetry stays on local persistent disk and older data is offloaded to S3-compatible object storage.

This example can be used with Oracle Cloud Infrastructure Object Storage or with an on-premises S3-compatible object store such as MinIO.

**Use case:** Longer telemetry retention, reduced local disk pressure, and support for both cloud and on-premises object storage backends

<details>
<summary>Prerequisites: Prepare object storage settings before installing</summary>

1. Create or identify an S3-compatible bucket for SigNoz cold storage.

1. Collect the connection details for your object store: `endpoint`, `accessKey`, and `secretAccess`.

1. Review and update `examples/values-signoz-cold-storage.yaml` with your environment-specific values.

1. Size local ClickHouse storage appropriately. `signoz.clickhouse.persistence.size` controls hot storage capacity, and `signoz.clickhouse.coldStorage.defaultKeepFreeSpaceBytes` controls how much local disk remains free before older data is offloaded.

1. For on-premises installations, you can use an S3-compatible endpoint provided by MinIO instead of OCI Object Storage. ([min.io](https://min.io/))

</details>

**Installation:**

```bash
helm upgrade --install <app-release> obaas/obaas \
  -f examples/values-signoz-cold-storage.yaml \
  -n <application-namespace> --create-namespace [--debug]
```

#### Private Registry Configuration (`values-private-registry.yaml`)

Uses a private container registry for all images with authentication.

**Use case:** Air-gapped environments, corporate registries, security compliance

<details>
<summary>Prerequisites</summary>

1. Mirror all required images to your private registry.

   A utility is provided to mirror the images to your registry. Provide the name of your target registry. You must be authenticated to the target registry before running this script.

   ```bash
   cd helm/infra-charts/tools
   ./mirror-images.sh myregistry.example.com
   ```

1. Create an image pull secret.

   ```bash
   kubectl create secret docker-registry myregistry-secret \
     --docker-server=myregistry.example.com \
     --docker-username=<username> \
     --docker-password=<password> \
     --docker-email=<email>
   ```

1. Install both the `obaas-prereqs` and `obaas` charts using values files with your registry details.

</details>

**Installation:**

```bash
helm upgrade --install <prereqs-release> obaas/obaas-prereqs -n <platform-system-namespace> -f obaas-prereqs/examples/values-private-registry.yaml --create-namespace [--debug]
helm upgrade --install <app-release> obaas/obaas -n <application-namespace> -f obaas/examples/values-private-registry.yaml --create-namespace [--debug]
```

<details>
<summary>Image registry override details</summary>

Each subchart has its own image configuration that must be set explicitly.

**Subcharts with a dedicated registry field** (set to your registry URL):

- **ingress-nginx**: `controller.image.registry`
- **signoz**: `global.imageRegistry`
- **apisix etcd**: `apisix.etcd.image.registry`

**OBaaS components requiring the full repository path** (include registry in `image.repository`):

- **eureka**, **admin-server**, **conductor-server**, **otmm**, **oracle-database-exporter**
- **database** (for SIDB-FREE/ADB-FREE)
- **apisix**: `apisix.image.repository`, `apisix.initContainer.image`

Image pull secrets are propagated to subcharts via `global.imagePullSecrets`. See `values-private-registry.yaml` for a complete example.

:::note
Cluster-singleton prerequisites (cert-manager, external-secrets, metrics-server, kube-state-metrics, strimzi-kafka-operator) have their own image configuration in the `obaas-prereqs` chart.
:::

</details>

#### Combining Examples

You can layer multiple values files to combine configurations:

```bash
# Combine multi-tenant and private registry configurations
helm upgrade --install <tenant1-release> obaas/obaas \
  -f examples/values-tenant1.yaml \
  -f examples/values-private-registry.yaml \
  -n <tenant1-namespace> --create-namespace [--debug]
```

Or create a custom values file:

```yaml
# my-custom-values.yaml
global:
  imagePullSecrets:
    - name: myregistry-secret

# Disable components you don't need
ai-optimizer:
  enabled: false

signoz:
  enabled: false
```

### Uninstallation

To remove OBaaS from your cluster:

:::warning Data Loss
Uninstalling will delete all resources. Ensure you have backups of any important data before proceeding.
:::

**Step 1: Uninstall OBaaS instances first:**

```bash
helm uninstall <app-release> -n <application-namespace>
helm uninstall <tenant1-release> -n <tenant1-namespace>
helm uninstall <tenant2-release> -n <tenant2-namespace>
```

**Step 2: Delete namespaces (optional):**

```bash
kubectl delete namespace <application-namespace> <tenant1-namespace> <tenant2-namespace>
```

**Step 3: Uninstall prerequisites (only if removing entirely):**

```bash
helm uninstall <prereqs-release> -n <platform-system-namespace>
```

:::danger Warning
Uninstalling prerequisites will affect **all** OBaaS instances in the cluster. Only do this if you're removing OBaaS completely.
:::

### Next Steps

Once OBaaS is running, you can:

- [Deploy your application](../../deploy/deploy.md) using the OBaaS platform
- [Configure observability](../../observability/configure.md) for metrics, logs, and traces
