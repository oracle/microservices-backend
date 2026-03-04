---
title: Helm Chart installation
sidebar_position: 2
---
## Oracle Backend for Microservices and AI (OBaaS) Helm Charts

This document describes how to deploy OBaaS to an existing Kubernetes cluster using Helm charts.

- [Architecture](#architecture) — Two-chart design, components, and cluster layout
- [Prerequisites](#prerequisites) — Required tools and cluster access
- [Installation Guide](#installation-guide) — Step-by-step deployment process
- [Example Configurations](#example-configurations) — Common deployment scenarios:
  - [Default](#default-configuration-values-defaultyaml) — Quick start with no overrides
  - [SIDB-FREE Database](#sidb-free-database-values-sidb-freeyaml) — In-cluster Oracle Database Free container
  - [Existing ADB](#existing-adb-configuration-values-existing-adbyaml) — Connect to a pre-provisioned Autonomous Database
  - [Other Existing Database](#other-existing-database-values-byodbyaml) - Connect to another type of pre-existing Oracle AI Database, for example an Oracle Base DB, or an on-premises Oracle Database
  - [Multi-Tenant](#multi-tenant-setup-values-tenant1yaml-values-tenant2yaml) — Run multiple OBaaS instances in one cluster
  - [Namespace and Scope](#namespace-and-scope-configuration-values-namespace-overrideyaml) — Control which namespaces components watch
  - [SigNoz Existing Secret](#signoz-existing-secret-values-signoz-existing-secretyaml) — Pre-provisioned SigNoz credentials
  - [Private Registry](#private-registry-configuration-values-private-registryyaml) — Air-gapped and corporate registry setups
  - [Combining Examples](#combining-examples) — Layer multiple values files together
- [Uninstallation](#uninstallation) — Teardown instructions
- [Next Steps](#next-steps) — Deploy applications and configure observability

### Architecture

The deployment uses a two-chart architecture. The charts are separated because the OBaaS Prerequisites cahrt installs cluster-wide CRDs and operators that may only exist once in a cluster, while the OBaaS chart contains namespace-scoped resources that can be safely installed multiple times.

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

### Installation Guide

#### Step 0: Configure Helm Repository

Add the Helm repository to your local Helm installation using the following commands:

```bash
helm repo add obaas https://oracle.github.io/microservices-backend/helm
helm repo update
```

#### Step 1: Install Prerequisites (Once Per Cluster)

:::warning Cluster-Scoped Installation
Only install prerequisites once per cluster. Installing multiple times will cause CRD conflicts and duplicate operator controllers.
:::

```bash
helm upgrade --install obaas-prereqs obaas/obaas-prereqs -n obaas-system --create-namespace [--debug] [--values <path_to_custom_values>]
```

Verify all prerequisite pods are running before proceeding:

```bash
kubectl get pods -n obaas-system
```

All pods should reach `Running` status within 2-3 minutes.

#### Step 2: Install OBaaS

Choose an example configuration that matches your deployment scenario and install:

```bash
helm upgrade --install obaas obaas/obaas -f examples/<values-file>.yaml -n <namespace> --create-namespace [--debug]
```

See [Example Configurations](#example-configurations) below for the full list of available examples.

Monitor the installation:

```bash
kubectl get pods -n <namespace> -w
```

:::tip First Deployment
It may take 5-10 additional minutes for all pods to reach Running state.
:::

#### Step 3: Verify Installation

After installation completes, verify all components are running:

```bash
kubectl get pods -A
```

**Expected results:**

- All pods in `Running` state
- Services with ClusterIP or LoadBalancer IPs assigned
- Ingress configured with your hostname

### Example Configurations

#### Default Configuration (`values-default.yaml`)

Minimal configuration with no overrides. All subcharts use their default settings.

**Use case:** Quick start, development, testing

```bash
helm upgrade --install obaas obaas/obaas -f examples/values-default.yaml -n obaas --create-namespace [--debug]
```

#### SIDB-FREE Database (`values-sidb-free.yaml`)

Uses Oracle Database Free as an in-cluster container. This is the default database type.

**Use case:** Development, testing, standalone deployments

```bash
helm upgrade --install obaas obaas/obaas -f examples/values-sidb-free.yaml -n obaas --create-namespace [--debug]
```

#### Existing ADB Configuration (`values-existing-adb.yaml`)

Connects to an existing OCI Autonomous Database (ADB-S) instead of deploying a database container.

**Use case:** Production deployments using a pre-provisioned OCI Autonomous Database

<details>
<summary>Prerequisites: Create required secrets before installing</summary>

1. Create the OCI API key secret:

   ```bash
   python3 tools/oci_config.py --namespace NAMESPACE [--config CONFIG] [--profile PROFILE]
   ```

   :::note
   Python 3.12 or later is required to run the `oci_config.py` script.
   :::

1. Create the privileged authentication secret for the ADMIN user, replace DBNAME with the name of your database:

   ```bash
    kubectl -n NAMESPACE create secret generic DBNAME-db-priv-authn \
      --from-literal=username=ADMIN \
      --from-literal=password=YOUR_ADMIN_PASSWORD \
      --from-literal=service=DBNAME_tp
   ```

1. **OPTIONAL**: Create the application user secret for the OBAAS_USER user, replace DBNAME with the name of your database:

   ```bash
    kubectl -n NAMESPACE create secret generic DBNAME-db-authn \
      --from-literal=username=OBAAS_USER \
      --from-literal=password=YOUR_ADMIN_PASSWORD \
      --from-literal=service=DBNAME_tp
   ```

</details>

**Installation:**

The name `obaas` in the command below should reflect your environment, the `obaas` value is just an example. The `--set database.authN.secretName=NAME_OF_APPUSER_SECRET` is optional.

```bash
helm upgrade --install obaas obaas/obaas \
  -n NAMESPACE \
  -f examples/values-existing-adb.yaml \
  --set database.oci.ocid=ADB_OCID \
  --set database.privAuthN.secretName=NAME_OF_ADMINUSER_SECRET
  --set database.authN.secretName=NAME_OF_APPUSER_SECRET
  [--debug]
```

#### Other Existing Database (`values-byodb.yaml`)

Connects to an existing Oracle AI Database using a connect string and user credentials.
Do not use this option for an Oracle Autonomous Database.  This is a good option for
an Oracle Base DB or an on-premises Oracle AI Database.

**Use case:** Production deployments using a pre-existing Oracle AI Database (non-Autonomous)

<details>
<summary>Prerequisites: Create required secrets before installing</summary>

Create the privileged authentication secret for an appropriate admin user:

   ```bash
   kubectl -n NAMESPACE create secret generic obaas-db-priv-authn \
     --from-literal=username=SYSTEM \
     --from-literal=password=<SYSTEM PASSWORD> \
     --from-literal=service=your.service.name
   ```

  The admin user should be a user with DBA privileges that can be used to create application users and grant them appropriate privileges For example, the SYSTEM user is a good choice.  This user should not require the SYSDBA role.

  This user should have the following permissions:

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

Review and update the database connection details in `examples/values-byodb.yaml`

</details>

**Installation:**

```bash
helm upgrade --install obaas obaas/obaas \
  -n NAMESPACE \
  -f examples/values-byodb.yaml 
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

```bash
# Install first tenant
helm upgrade --install obaas-tenant1 obaas/obaas -n tenant1 -f examples/values-tenant1.yaml --create-namespace [--debug]

# Install second tenant
helm upgrade --install obaas-tenant2 obaas/obaas -n tenant2 -f examples/values-tenant2.yaml --create-namespace [--debug]
```

#### Namespace and Scope Configuration (`values-namespace-override.yaml`)

Demonstrates how to configure the ingress-nginx watching scope. All OBaaS components deploy to the release namespace (specified with the `-n` flag).

**Use case:** Controlling which namespaces components watch

```bash
helm upgrade --install obaas obaas/obaas -f examples/values-namespace-override.yaml -n obaas-platform --create-namespace [--debug]
```

#### SigNoz Existing Secret (`values-signoz-existing-secret.yaml`)

Uses a pre-existing Kubernetes secret for SigNoz admin authentication instead of auto-generating one.

**Use case:** GitOps workflows, pre-provisioned credentials

```bash
# Create the secret first
kubectl create secret generic my-signoz-secret \
  --from-literal=email=admin@mydomain.com \
  --from-literal=password=my-secure-password \
  -n obaas

# Install with the example
helm upgrade --install obaas obaas/obaas -f examples/values-signoz-existing-secret.yaml -n obaas [--debug]
```

#### Private Registry Configuration (`values-private-registry.yaml`)

Uses a private container registry for all images with authentication.

**Use case:** Air-gapped environments, corporate registries, security compliance

**Prerequisites:**

1. Mirror all required images to your private registry.

    A utility is provided to mirror the images to your registry.  Provide the name of your target registry.
    Note that you must be authenticated to the target registry before running this script.

    ```bash
    cd helm/infra-charts/tools
    ./mirror-images.sh myregistry.example.com
    ```

2. Create an image pull secret:

   ```bash
   kubectl create secret docker-registry myregistry-secret \
     --docker-server=myregistry.example.com \
     --docker-username=<username> \
     --docker-password=<password> \
     --docker-email=<email>
   ```

3. Install both the obaas-prereqs and obaas charts using a values file with your registry details:

```bash
helm upgrade --install obaas-prereqs obaas/obaas-prereqs -f obaas-prereqs/examples/values-private-registry.yaml [--debug]
helm upgrade --install obaas obaas/obaas -f obaas/examples/values-private-registry.yaml [--debug]
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
helm upgrade --install obaas-tenant1 obaas/obaas \
  -f examples/values-tenant1.yaml \
  -f examples/values-private-registry.yaml \
  -n tenant1 --create-namespace [--debug]
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
helm uninstall obaas -n obaas-prod
helm uninstall obaas-tenant1 -n tenant1
helm uninstall obaas-tenant2 -n tenant2
```

**Step 2: Delete namespaces (optional):**

```bash
kubectl delete namespace obaas-prod tenant1 tenant2
```

**Step 3: Uninstall prerequisites (only if removing entirely):**

```bash
helm uninstall obaas-prereqs -n obaas-system
```

:::danger Warning
Uninstalling prerequisites will affect **all** OBaaS instances in the cluster. Only do this if you're removing OBaaS completely.
:::

### Next Steps

Once OBaaS is running, you can:

- [Deploy your application](../../deploy/deploy.md) using the OBaaS platform
- [Configure observability](../../observability/configure.md) for metrics, logs, and traces
