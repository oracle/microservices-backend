# OBaaS 2.1.2 Installation Guide For AI Agents

This guide tells an AI agent how to plan, prepare, install, and verify Oracle Backend for Microservices and AI, commonly called OBaaS, version 2.1.2. In the product documentation, this version is the `next` documentation stream.

## Source Rules

- Use only the OBaaS `next` documentation and chart sources:
  - `docs-source/site/docs`
  - `helm/infra-charts`
- Do not use documentation for the previous 2.0.0 version.
- Do not infer installation behavior from unrelated repository directories.
- Treat the public docs entry point as the same content represented locally under `docs-source/site/docs/intro.md` and the setup pages under `docs-source/site/docs/setup/helm/`.
- Treat Helm chart defaults and examples under `helm/infra-charts` as the source of truth for chart value names and installable optional components.
- For the currently in-development OBaaS version, install, render, lint, and test with the local chart paths under `helm/infra-charts`, not with public Helm repository references, unless the public Helm repository has already published charts whose `APP VERSION` or `appVersion` matches the target version.
- OBaaS 2.1.2 is currently an in-development target in this repository. Its local charts are `helm/infra-charts/obaas-prereqs` and `helm/infra-charts/obaas`; do not install `obaas/obaas-prereqs` or `obaas/obaas` from the public repository for a 2.1.2 test while the public repository still advertises an older application version.

## Before You Start

Do not begin a cluster installation until the target environment, database choice, access model, and optional components are known. Many OBaaS failures come from missing cluster capacity, missing database credentials, unavailable storage, or mismatched values files.

Use placeholders until the operator provides real values:

- `<platform-system-namespace>`: namespace for cluster-singleton prerequisites, for example `obaas-system`.
- `<prereqs-release>`: Helm release for `obaas-prereqs`, for example `obaas-prereqs`.
- `<application-namespace>`: namespace for one OBaaS instance, for example `obaas`, `tenant1`, or `obaas-prod`.
- `<app-release>`: Helm release for the OBaaS application chart, for example `obaas`.
- `<values-file>`: the prepared Helm values file or files for the chosen scenario.

## Prerequisites

### Local Tools

The installer workstation or automation environment must have:

- Helm 3.8 or later.
- `kubectl` configured for the target Kubernetes context.
- OCI CLI or SDK configuration if installing against an OCI Autonomous Database with API key authentication.
- Python 3.12 or later if using `helm/infra-charts/tools/oci_config.py` to create OCI config resources.
- Registry login tooling if images must be mirrored to a private registry.

Run:

```bash
helm version
kubectl config current-context
kubectl get nodes
```

### Kubernetes Cluster

OBaaS 2.1.2 requires a CNCF-compliant Kubernetes cluster. The `next` prerequisites documentation states:

- Kubernetes 1.34 or later.
- At least 3 worker nodes.
- At least 2 OCPU and 32 GB memory per worker node.
- A working storage provider with a storage class that supports `ReadWriteMany` persistent volumes.
- A working network provider that supports either Ingress or Gateway API for external access.
- No conflicting cluster-managed copy of singleton infrastructure that the prerequisite chart would also install, especially `metrics-server` on AKS or any cluster where it is already provided as an addon.

Plan extra capacity when enabling heavier options:

- Add at least 2 CPUs and 4 GiB RAM per cluster if installing the OTMM workflow server.
- For `SIDB-FREE`, which runs Oracle Database Free inside the Kubernetes cluster, plan at least 250 GB of ephemeral node storage for database filesystem needs.
- For two OBaaS instances in the same cluster, plan roughly double the worker-node capacity before application workload sizing.

Verify:

```bash
kubectl version
kubectl get nodes
kubectl describe nodes
kubectl get storageclass
kubectl get ns
```

Confirm which storage class supports RWX before choosing SigNoz, ClickHouse, and database persistence settings.

### OCI Requirements

If installing on Oracle Cloud Infrastructure, confirm the required OCI IAM policies and permissions from the `next` setup docs before starting. This matters especially for:

- The policy reference is `docs-source/site/docs/setup/oci_policies.md`.
- Identity and access management permissions to read compartments, domains, limits, and inspect resources.
- Dynamic group and policy management when the install flow creates or updates IAM resources.
- OKE permissions for cluster-family, clusters, cluster node pools, instance-family resources, and public IPs.
- VCN permissions for virtual networks, private IPs, subnets, VNICs, route tables, security lists, DHCP options, NAT gateways, service gateways, network security groups, and load balancers.
- Container Registry permissions to manage repositories.
- Object Storage permissions to read namespaces, inspect buckets, and manage objects.
- Autonomous Database permissions to manage autonomous-database-family resources.
- Oracle Resource Manager permissions if using ORM-driven deployment flows.
- Oracle Kubernetes Engine resources.
- Autonomous Database discovery or management.
- OCI API key or OKE Workload Identity access.
- OCI Object Storage when used for SigNoz cold storage.
- OCI Container Registry or private registry access.

OCI API keys and OKE Workload Identity are both supported authentication patterns for Autonomous Database-related automation. Use Workload Identity on OKE when the cluster and IAM policies are prepared for it; otherwise use OCI API key resources created from the OCI config helper.

For strict OCI policy auditing, do not rely only on the summary above. Read `docs-source/site/docs/setup/oci_policies.md` directly and compare the tenancy policies against the exact `Allow group ... to read/inspect/manage/use ...` statements listed there.

### Oracle Database

OBaaS requires access to Oracle Database 19c or later. Oracle Autonomous Database 26ai ATP is recommended, and Oracle Database 26ai or later is required for OBaaS AI capabilities.

Recommended Autonomous Database sizing from the prerequisites docs:

- 2 ECPU.
- 1 TB storage.
- Secure access from anywhere enabled.

Supported planning categories:

- `ADB-S`: an existing OCI Autonomous Database, including shared Autonomous Database deployments.
- `ADB-D`: Autonomous Database Dedicated is supported by the prerequisite docs and should be planned like an external Autonomous Database deployment. Set `database.type: "ADB-S"` because the chart does not have a separate `ADB-D` type.
- Globally Distributed Autonomous AI Database is also supported and should be planned like an Autonomous Database deployment. Set `database.type: "ADB-S"` because the chart does not have a separate globally distributed database type.
- `ADB-FREE`: Oracle Autonomous Database Free running in the Kubernetes cluster.
- `OTHER`: an existing non-Autonomous Oracle Database, such as Base Database Service or an on-premises Oracle Database.
- `SIDB-FREE`: Oracle Database Free running inside the Kubernetes cluster, primarily for evaluation, development, and testing.

Collect:

- Database type.
- Host, port, and service name, or a full DSN, for `OTHER`.
- Autonomous Database OCID for external Autonomous Database deployments.
- Privileged database username and password, usually `ADMIN` for ADB or `SYSTEM` for non-ADB.
- Application user choice, usually auto-created as `OBAAS_USER` unless a pre-existing application user secret is supplied.
- Network reachability from the Kubernetes cluster to the database.

For external databases, the privileged user must be able to create the application user and grant the required runtime permissions. For non-ADB databases, verify the required grantable access to database monitoring views and queue packages before installing.

Required `OTHER` database privileges:

```sql
SELECT WITH GRANT OPTION on:
  DBA_TABLESPACE_USAGE_METRICS, DBA_TABLESPACES,
  GV_$SYSTEM_WAIT_CLASS, GV_$ASM_DISKGROUP_STAT, GV_$DATAFILE,
  GV_$SYSSTAT, GV_$PROCESS, GV_$WAITCLASSMETRIC, GV_$SESSION,
  GV_$RESOURCE_LIMIT, GV_$PARAMETER, GV_$DATABASE,
  GV_$SQLSTATS, GV_$SYSMETRIC, GV_$CON_SYSMETRIC, V_$DIAG_ALERT_EXT

EXECUTE WITH GRANT OPTION on:
  SYS.DBMS_AQ, SYS.DBMS_AQADM, SYS.DBMS_AQIN,
  SYS.DBMS_AQIN, SYS.DBMS_AQJMS_INTERNAL
```

### cert-manager

OBaaS requires cert-manager. If cert-manager is not already installed and healthy in the cluster, install it before `obaas-prereqs`.

An installation is healthy only when both the Kubernetes components are ready and
the Helm release reports `STATUS: deployed`. Healthy pods alone are not sufficient:
cert-manager uses a post-install startup-check Job, and an interrupted Helm client
can leave a release `pending-install` or leave running resources with no release
record.

Run Helm in the foreground. The caller's execution timeout must exceed Helm's
timeout, and automation must retain Helm's exit code and output. Do not use
`--no-hooks` to bypass the startup check.

The OBaaS install docs use:

```bash
helm install \
  cert-manager oci://quay.io/jetstack/charts/cert-manager \
  --version v1.21.1 \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true \
  --set crds.keep=false
```

Verify:

```bash
helm status cert-manager -n cert-manager
kubectl get pods -n cert-manager
kubectl wait --for=condition=Available deployment --all \
  -n cert-manager --timeout=5m
kubectl get crd | grep cert-manager
```

Do not continue to `obaas-prereqs` unless `helm status` reports
`STATUS: deployed`.

If Helm reports `pending-install` or `release: not found`, stop before installing
OBaaS prerequisites. Collect `helm status`, `helm history`, the cert-manager Job
list and relevant Job logs, deployment readiness, and namespace events. Do not
delete cert-manager workloads or CRDs merely to clear Helm state.

When workloads are healthy but `helm status` reports `release: not found`, inspect
the Helm ownership metadata before retrying `helm upgrade --install`:

```bash
kubectl get deployment cert-manager -n cert-manager \
  -o jsonpath='{.metadata.labels.app\.kubernetes\.io/managed-by}{"\\n"}{.metadata.annotations.meta\.helm\.sh/release-name}{"\\n"}{.metadata.annotations.meta\.helm\.sh/release-namespace}{"\\n"}'
```

Retry only when existing resources are owned by the `cert-manager` release in the
`cert-manager` namespace. If Helm reports an ownership conflict, escalate for a
controlled metadata reconciliation; do not perform destructive cleanup
automatically.

### Private Registry Or Air-Gapped Requirements

If the cluster cannot pull from public registries:

- Mirror all OBaaS, prerequisite, and dependency images to the private registry.
- Create image pull secrets in each namespace that needs them.
- Prepare both `obaas-prereqs` and `obaas` private-registry values.
- Preserve YAML anchors in the example private-registry values files because they propagate image pull secrets to subcharts.

The helper script is:

```bash
cd helm/infra-charts/tools
./mirror-images.sh myregistry.example.com
```

The image list for this version is available under `helm/infra-charts/tools/image_lists/k8s_images_2.1.2.txt`.

## Planning The Installation

### Questions To Resolve Before Installing

Ask and record answers for these decisions:

- What Kubernetes context and cluster will receive the install?
- Is this OCI OKE, AKS, another public cloud, or on-premises Kubernetes?
- What are the prerequisite and application namespaces?
- What are the Helm release names?
- Is this the first OBaaS install in the cluster?
- Has `obaas-prereqs` already been installed in this cluster?
- Is cert-manager already installed and healthy?
- Which database mode will be used: `SIDB-FREE`, `ADB-FREE`, `ADB-S`, or `OTHER`?
- For external database modes, have Kubernetes secrets been created for privileged and optional application credentials?
- Which external access path should be installed: Envoy Gateway default, deprecated ingress-nginx opt-in, both, or neither?
- Will multiple OBaaS tenants share the cluster?
- Are all images pulled from public registries, or is a private registry required?
- Should SigNoz be installed?
- Should SigNoz use auto-generated admin credentials, an existing secret, or cold storage?
- Should Kafka, AI Optimizer, OTMM workflow server, OTMM console, Coherence, custom APISIX plugins, or OpenTelemetry customization be enabled?
- Which storage class and storage sizes should be used for persistent components?
- Are there corporate policies for ingress hostnames, load balancer type, TLS, image tags, secrets, and namespaces?

Do not proceed until all high-impact choices are known.

### Installation Types

Use these scenario labels when asking clarifying questions:

- Minimal evaluation: `values-default.yaml`; uses chart defaults and the default database behavior.
- Development with in-cluster database: `values-sidb-free.yaml`; uses `database.type: SIDB-FREE`.
- Development with in-cluster Autonomous Database Free: no dedicated example values file exists; start from `values-sidb-free.yaml`, change `database.type` to `ADB-FREE`, and override `database.image.repository` and `database.image.tag` if the environment needs a specific ADB Free image or private registry image.
- OCI production with Autonomous Database: `values-existing-adb.yaml`; set `database.type: ADB-S` for external Autonomous Database deployments, including ADB-S, ADB-D, and Globally Distributed Autonomous Database. The chart does not have separate type values for ADB-D or globally distributed variants.
- Existing non-Autonomous database: `values-byodb.yaml`; uses `database.type: OTHER`.
- Multi-tenant cluster: `values-tenant1.yaml` and `values-tenant2.yaml`; use unique namespaces and unique ingress settings.
- Namespace watch tuning: `values-namespace-override.yaml`.
- Pre-created SigNoz credentials: `values-signoz-existing-secret.yaml`.
- Long-term observability retention: `values-signoz-cold-storage.yaml`.
- Private registry or air-gapped install: `values-private-registry.yaml` for both charts.
- AKS-specific install: `obaas-prereqs/examples/values-aks.yaml` and `obaas/examples/values-aks.yaml` together.
- AI Optimizer install: `values-ai-optimizer.yaml`.
- Custom APISIX plugins: `values-custom-apisix-plugins.yaml`.

The examples are stored locally under:

```text
helm/infra-charts/obaas-prereqs/examples/
helm/infra-charts/obaas/examples/
```

If the target version has been published and installing from the public Helm repository is appropriate, copy or reference prepared local values files. The `examples/...` paths only work from a checkout or environment where those files exist.

### AKS-Specific Planning

For Azure Kubernetes Service, use both AKS example values files as the starting point:

- `helm/infra-charts/obaas-prereqs/examples/values-aks.yaml`
- `helm/infra-charts/obaas/examples/values-aks.yaml`

Before installing on AKS, confirm:

- Whether AKS already provides `metrics-server` as a managed addon. If it does, set `metrics-server.enabled: false` in the `obaas-prereqs` values to avoid a duplicate singleton install.
- Whether `oracle-database-operator` is needed. Keep it enabled when the deployment needs Autonomous Database operator integration, especially with `database.type: ADB-S`; otherwise review whether cluster policy requires disabling it with `oracle-database-operator.enabled: false`.
- Whether the cluster uses the assumed Azure Disk CSI storage class. The `obaas` AKS example sets `managed-csi` for SigNoz and ClickHouse storage; replace it if the cluster uses a different StorageClass.
- How ingress should be exposed. The `obaas` AKS example disables legacy ingress-nginx and leaves the Envoy Gateway path as the default access strategy.

The AKS `obaas` values file also sets observability cloud metadata to Azure through `k8s-infra.global.cloud` and `signoz.global.cloud`.

## Helm Values Preparation

### Chart Architecture

OBaaS uses two Helm charts.

`obaas-prereqs` installs cluster-singleton prerequisites and must be installed only once per cluster. It includes:

- `external-secrets`
- `metrics-server`
- `kube-state-metrics`
- `strimzi-kafka-operator`
- `coherence-operator`
- `opentelemetry-operator`
- `oracle-database-operator`
- ClickHouse CRDs in chart templates

`obaas` installs namespace-scoped OBaaS platform components and can be installed once per tenant or application namespace. It includes:

- `gateway-helm` for Envoy Gateway
- deprecated `ingress-nginx`, disabled by default and available for explicit opt-in
- Apache APISIX
- Eureka service discovery
- Spring Boot Admin server
- Config Server
- OTMM and optional workflow server or console
- Oracle Database or database integration resources
- Oracle Database Exporter
- SigNoz and ClickHouse observability resources
- AI Optimizer
- optional Kafka cluster resources
- extra ConfigMaps for APISIX custom plugins

### Choose And Layer Values Files

Start from the closest example and add only the overrides needed for the environment. For an in-development version such as the current 2.1.2 work, use the local chart path:

```bash
helm upgrade --install <app-release> helm/infra-charts/obaas \
  -n <application-namespace> \
  --create-namespace \
  -f <base-values-file> \
  -f <environment-overrides-file>
```

Later values files override earlier files. Keep secrets out of committed files unless the operator explicitly uses a secure secret-management workflow.

Before installing, render or lint the chart when feasible. For in-development versions, use local chart paths for both `helm lint` and `helm template`:

```bash
helm lint helm/infra-charts/obaas-prereqs -f <prereqs-values-file>
helm lint helm/infra-charts/obaas -f <app-values-file>
helm template <app-release> helm/infra-charts/obaas -n <application-namespace> -f <app-values-file> >/tmp/obaas-rendered.yaml
```

### Database Values

OBaaS requires database access. Do not set an `enabled` field under `database`; it is not a chart value. Use `database.type` to choose the database mode.

For `SIDB-FREE`:

```yaml
database:
  type: "SIDB-FREE"
```

Notes:

- Best for development, testing, and standalone evaluation.
- Requires sufficient ephemeral node storage.
- Privileged and application credentials can be auto-generated when not supplied.
- The database container image defaults to Oracle Database Free.

For `ADB-FREE`:

```yaml
database:
  type: "ADB-FREE"
```

Notes:

- Best for development and testing when the operator wants the in-cluster Autonomous Database Free path rather than `SIDB-FREE`.
- Like `SIDB-FREE`, it runs database infrastructure inside the Kubernetes cluster and needs adequate node storage and capacity.
- Privileged and application credentials can be auto-generated when not supplied.
- The database container image is controlled by `database.image.repository` and `database.image.tag`, the same value path used by `SIDB-FREE`.
- Private registry installs must override `database.image.repository` and `database.image.tag` when the database image is mirrored; see the private registry values section.

For `ADB-S` and other external Autonomous Database deployments:

```yaml
database:
  type: "ADB-S"
  privAuthN:
    secretName: "<db-name>-db-priv-authn"
    # secretNamespace: "<secret-namespace>"
  oci:
    ocid: "<adb-ocid>"
  oci_config:
    keySecretName: "oci-privatekey"
    configMapName: "oci-config"
```

Use `database.privAuthN.secretNamespace` when the privileged credential secret is stored in a namespace other than the OBaaS release namespace.

Prepare OCI API key resources. Python 3.12 or later is required for the helper:

```bash
cd helm/infra-charts
python3 tools/oci_config.py --namespace <application-namespace> \
  --config <oci-config-file> \
  --profile <oci-profile>
```

Alternatively, use OKE Workload Identity instead of API key authentication when the cluster and OCI IAM policies are configured for it. Do not set `database.oci_config.oke`; that placeholder is not consumed by the chart templates. In a Workload Identity setup, omit or leave empty `database.oci_config.keySecretName` and `database.oci_config.configMapName`, and ensure the Oracle Database Operator pod receives credentials through the cluster's IAM binding or instance principal configuration.

Create the privileged `ADMIN` secret:

```bash
kubectl -n <application-namespace> create secret generic <db-name>-db-priv-authn \
  --from-literal=username=ADMIN \
  --from-literal=password=<admin-password> \
  --from-literal=service=<db-name>_tp
```

Optionally create an application user secret:

```bash
kubectl -n <application-namespace> create secret generic <db-name>-db-authn \
  --from-literal=username=OBAAS_USER \
  --from-literal=password=<app-user-password> \
  --from-literal=service=<db-name>_tp
```

Then reference it:

```bash
--set database.authN.secretName=<app-user-secret>
```

For `OTHER`:

```yaml
database:
  type: "OTHER"
  other:
    dsn: ""
    host: "<db-host>"
    port: "1521"
    service_name: "<service-name>"
  privAuthN:
    secretName: "<db-name>-db-priv-authn"
    # secretNamespace: "<secret-namespace>"
```

Use `database.privAuthN.secretNamespace` when the privileged credential secret is stored in a namespace other than the OBaaS release namespace.

Create the privileged non-ADB secret:

```bash
kubectl -n <application-namespace> create secret generic <db-name>-db-priv-authn \
  --from-literal=username=SYSTEM \
  --from-literal=password=<system-password> \
  --from-literal=service=<service-name>
```

Use `dsn` instead of `host`, `port`, and `service_name` when the operator supplies a full connect string.

Before installing with `database.type: OTHER`, verify the privileged user has the `SELECT WITH GRANT OPTION` and `EXECUTE WITH GRANT OPTION` privileges listed in the Oracle Database prerequisites section above.

### Cluster Access Values

OBaaS 2.1.2 supports both Gateway API through Envoy Gateway and Ingress API through ingress-nginx. Envoy Gateway is enabled by default. ingress-nginx is deprecated and disabled by default; enable it only when an environment still requires the legacy Ingress API path.

Enable Envoy Gateway:

```yaml
gateway-helm:
  enabled: true
```

Enable deprecated ingress-nginx only when the legacy Ingress API path is required:

```yaml
ingress-nginx:
  enabled: true
  controller:
    scope:
      enabled: true
```

Valid choices:

- Use the default Envoy Gateway path for Gateway API-first clusters.
- Explicitly enable ingress-nginx only for legacy Ingress API-based environments.
- Enable both during migration or where both access patterns are required.
- Disable both if the cluster already provides another supported external access mechanism.

For multi-tenant ingress-nginx opt-in installs, each tenant must use unique values for:

- `ingress-nginx.controller.ingressClass`
- `ingress-nginx.controller.ingressClassResource.name`
- `ingress-nginx.controller.ingressClassResource.controllerValue`
- `ingress-nginx.controller.electionID`

### Optional Component Values

Disable unneeded optional components by setting their `enabled` field to `false`.

Common options:

```yaml
ai-optimizer:
  enabled: false

kafka:
  enabled: false

signoz:
  enabled: true

otmm:
  enabled: true
  workflowServer:
    enabled: false
  console:
    enabled: false
```

AI Optimizer requires additional planning. The example expects:

- `database.type: ADB-S`
- an `ai-optimizer-api` secret containing key `apiKey`
- a privileged database secret such as `db-priv-authn`
- an optional `ai-optimizer-openai` secret for third-party model access

Kafka cluster creation is controlled by:

```yaml
kafka:
  enabled: true
  version: 4.2.0
  metadataVersion: 4.2-IV1
```

If Kafka is enabled, confirm the Strimzi operator from `obaas-prereqs` is installed and watching the application namespace.

The default `obaas-prereqs` values set:

```yaml
strimzi-kafka-operator:
  watchNamespaces: []
  watchAnyNamespace: true
```

That means the operator watches all namespaces by default. If an environment override restricted namespace watching, the Kafka custom resources in a new OBaaS namespace will not be reconciled until the namespace is added. Check the running operator configuration before enabling Kafka in a tenant namespace:

```bash
kubectl get deploy -n <platform-system-namespace> | grep strimzi
kubectl get deploy -n <platform-system-namespace> <strimzi-operator-deployment> -o yaml \
  | grep -E 'STRIMZI_NAMESPACE|watchNamespaces|watchAnyNamespace|--watch'
```

Expected: the operator is configured for all namespaces, or it explicitly includes `<application-namespace>`.

### SigNoz Values

SigNoz is enabled by default in the OBaaS values.

To use an existing admin credential secret:

```yaml
signoz:
  enabled: true
  auth:
    existingSecret: "my-signoz-secret"
```

The secret must contain `email` and `password` keys:

```bash
kubectl -n <application-namespace> create secret generic my-signoz-secret \
  --from-literal=email=admin@example.com \
  --from-literal=password=<secure-password>
```

To configure cold storage:

```yaml
signoz:
  enabled: true
  clickhouse:
    coldStorage:
      enabled: true
      defaultKeepFreeSpaceBytes: "10485760"
      type: s3
      endpoint: "<object-storage-endpoint>"
      accessKey: "<access-key>"
      secretAccess: "<secret-access-key>"
    persistence:
      enabled: true
      size: 100Gi
```

For production, confirm the storage class, object storage endpoint, retention needs, and secret-handling policy before installing.

### Private Registry Values

For the `obaas` chart, the private registry example uses:

```yaml
global:
  airGapped: true
  imagePullSecretName: &secretName myregistry-secret
  imagePullSecrets: &imagePullSecrets
    - *secretName
```

For the `obaas-prereqs` chart, the private registry example uses object-shaped pull secrets:

```yaml
global:
  imagePullSecrets: &imagePullSecrets
    - name: myregistry-secret
```

Create the image pull secret in each relevant namespace:

```bash
kubectl -n <namespace> create secret docker-registry myregistry-secret \
  --docker-server=myregistry.example.com \
  --docker-username=<username> \
  --docker-password=<password> \
  --docker-email=<email>
```

Subcharts do not all use the same image value shape. In private registry installs, review and override:

- `ingress-nginx.controller.image.registry` when deprecated ingress-nginx is explicitly enabled
- `signoz.global.imageRegistry`
- `apisix.etcd.image.registry`
- full `image.repository` paths for OBaaS components such as Eureka, admin-server, config-server, OTMM, database, Oracle Database Exporter, and APISIX
- prerequisite chart image fields for external-secrets, metrics-server, kube-state-metrics, Strimzi, Coherence Operator, OpenTelemetry Operator, and Oracle Database Operator

### APISIX Custom Plugins

Use `extraConfigMaps` to create ConfigMaps containing Lua plugin files, then use `apisix.apisix.customPlugins` to mount and register them.

Skeleton:

```yaml
extraConfigMaps:
  apisix-custom-plugin:
    my-plugin.lua: |
      local core = require("apisix.core")
      local plugin_name = "my-plugin"
      local _M = { version = 0.1, priority = 2500, name = plugin_name, schema = {} }
      function _M.access(conf, ctx)
          core.log.info("my-plugin executed")
      end
      return _M

apisix:
  enabled: true
  apisix:
    customPlugins:
      enabled: true
      luaPath: "/opts/custom_plugins/?.lua"
      plugins:
        - name: "my-plugin"
          attrs: {}
          configMap:
            name: "apisix-custom-plugin"
            mounts:
              - key: "my-plugin.lua"
                path: "/opts/custom_plugins/apisix/plugins/my-plugin.lua"
```

Custom plugins do not need to be added manually to `apisix.apisix.plugins`; the custom plugin configuration adds them.

## Installation Procedure

### Step 1: Confirm Preflight State

```bash
kubectl config current-context
kubectl get nodes
kubectl get storageclass
helm version
helm list -A
```

If this is not the first OBaaS install in the cluster, determine whether `obaas-prereqs` already exists:

```bash
helm list -A | grep obaas-prereqs
kubectl get pods -A | grep -E 'external-secrets|metrics-server|kube-state-metrics|strimzi|coherence|opentelemetry|oracle-database'
```

Install `obaas-prereqs` only once per cluster.

### Step 2: Check Chart Source Availability

For in-development releases, first compare the target local chart `appVersion` with the public Helm repository metadata:

```bash
grep '^appVersion:' helm/infra-charts/obaas/Chart.yaml
grep '^appVersion:' helm/infra-charts/obaas-prereqs/Chart.yaml
helm repo add obaas https://oracle.github.io/microservices-backend/helm
helm repo update
helm search repo obaas/obaas --versions
helm search repo obaas/obaas-prereqs --versions
```

Use the local chart paths when the public repository does not show the target application version:

```text
helm/infra-charts/obaas-prereqs
helm/infra-charts/obaas
```

For the current 2.1.2 development stream, the local charts have `appVersion: 2.1.2` and chart `version: 0.1.2`. If the public Helm repository does not report `APP VERSION: 2.1.2`, do not install or test with `obaas/obaas-prereqs` or `obaas/obaas`; use the local chart paths above.

Once the public repository publishes charts whose `APP VERSION` matches the target version, public chart references may be used. Use the chart version that corresponds to the target OBaaS application version.

For local chart installs, pin the repository checkout or commit and verify the `version` and `appVersion` fields in each local `Chart.yaml`. For public repository installs, where strict pinning is required after the target version has been published, add:

```bash
--version 0.1.2
```

to the public chart install commands.

### Step 3: Install cert-manager If Needed

Skip this step only if cert-manager is already healthy and
`helm status cert-manager -n cert-manager` reports `STATUS: deployed`.

```bash
helm install \
  cert-manager oci://quay.io/jetstack/charts/cert-manager \
  --version v1.21.1 \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true \
  --set crds.keep=false
```

Verify:

```bash
helm status cert-manager -n cert-manager
kubectl get pods -n cert-manager
kubectl wait --for=condition=Available deployment --all -n cert-manager --timeout=5m
kubectl get crd | grep cert-manager
```

Do not install `obaas-prereqs` if the Helm release is pending, missing, or failed.
Follow the cert-manager recovery guidance above.

### Step 4: Install Cluster Prerequisites Once

Generic install:

```bash
helm upgrade --install <prereqs-release> helm/infra-charts/obaas-prereqs \
  -n <platform-system-namespace> \
  --create-namespace \
  -f <prereqs-values-file>
```

If no custom prerequisites values are needed, omit `-f <prereqs-values-file>`.

Private registry example:

```bash
helm upgrade --install <prereqs-release> helm/infra-charts/obaas-prereqs \
  -n <platform-system-namespace> \
  --create-namespace \
  -f helm/infra-charts/obaas-prereqs/examples/values-private-registry.yaml
```

AKS example:

```bash
helm upgrade --install <prereqs-release> helm/infra-charts/obaas-prereqs \
  -n <platform-system-namespace> \
  --create-namespace \
  -f helm/infra-charts/obaas-prereqs/examples/values-aks.yaml
```

For AKS, review `metrics-server.enabled` before running this command. If AKS already manages `metrics-server`, set it to `false` in your prerequisite values. Also review whether `oracle-database-operator.enabled` should remain enabled for the selected database mode.

Verify before continuing:

```bash
helm status <prereqs-release> -n <platform-system-namespace>
kubectl get pods -n <platform-system-namespace>
kubectl get crd | grep -E 'external-secrets|kafka|coherence|opentelemetry|database|clickhouse'
```

All prerequisite pods should be `Running` or otherwise healthy before installing `obaas`.

### Step 5: Prepare Required Secrets

Create database, OCI, SigNoz, private registry, and AI Optimizer secrets before installing `obaas` whenever the selected values file references existing secrets.

If the application namespace does not already exist, create it before creating pre-install secrets:

```bash
kubectl create namespace <application-namespace>
```

Examples:

```bash
kubectl -n <application-namespace> create secret generic db-priv-authn \
  --from-literal=username=<ADMIN-or-SYSTEM> \
  --from-literal=password=<privileged-password> \
  --from-literal=service=<service-name>
```

```bash
kubectl -n <application-namespace> create secret generic my-signoz-secret \
  --from-literal=email=<admin-email> \
  --from-literal=password=<admin-password>
```

```bash
kubectl -n <application-namespace> create secret docker-registry myregistry-secret \
  --docker-server=<registry-host> \
  --docker-username=<username> \
  --docker-password=<password> \
  --docker-email=<email>
```

Confirm secret names match the values file:

```bash
kubectl get secrets -n <application-namespace>
```

### Step 6: Install OBaaS

Generic install:

```bash
helm upgrade --install <app-release> helm/infra-charts/obaas \
  -n <application-namespace> \
  --create-namespace \
  -f <app-values-file>
```

Minimal/default example from a checkout:

```bash
helm upgrade --install <app-release> helm/infra-charts/obaas \
  -n <application-namespace> \
  --create-namespace \
  -f helm/infra-charts/obaas/examples/values-default.yaml
```

SIDB-FREE example:

```bash
helm upgrade --install <app-release> helm/infra-charts/obaas \
  -n <application-namespace> \
  --create-namespace \
  -f helm/infra-charts/obaas/examples/values-sidb-free.yaml
```

Existing ADB example:

```bash
helm upgrade --install <app-release> helm/infra-charts/obaas \
  -n <application-namespace> \
  --create-namespace \
  -f helm/infra-charts/obaas/examples/values-existing-adb.yaml \
  --set database.oci.ocid=<adb-ocid> \
  --set database.privAuthN.secretName=<admin-user-secret> \
  --set database.authN.secretName=<app-user-secret>
```

If no pre-created application user secret is used, omit `--set database.authN.secretName=<app-user-secret>`.

Existing non-ADB database example:

```bash
helm upgrade --install <app-release> helm/infra-charts/obaas \
  -n <application-namespace> \
  --create-namespace \
  -f helm/infra-charts/obaas/examples/values-byodb.yaml
```

AKS example:

```bash
helm upgrade --install <app-release> helm/infra-charts/obaas \
  -n <application-namespace> \
  --create-namespace \
  -f helm/infra-charts/obaas/examples/values-aks.yaml
```

On AKS, review the `managed-csi` storage class values and the access strategy in the values file before installing.

Multi-tenant example:

```bash
helm upgrade --install <tenant1-release> helm/infra-charts/obaas \
  -n <tenant1-namespace> \
  --create-namespace \
  -f helm/infra-charts/obaas/examples/values-tenant1.yaml

helm upgrade --install <tenant2-release> helm/infra-charts/obaas \
  -n <tenant2-namespace> \
  --create-namespace \
  -f helm/infra-charts/obaas/examples/values-tenant2.yaml
```

Layered example for private registry plus tenant overrides:

```bash
helm upgrade --install <tenant1-release> helm/infra-charts/obaas \
  -n <tenant1-namespace> \
  --create-namespace \
  -f helm/infra-charts/obaas/examples/values-tenant1.yaml \
  -f helm/infra-charts/obaas/examples/values-private-registry.yaml
```

Monitor rollout:

```bash
helm status <app-release> -n <application-namespace>
kubectl get pods -n <application-namespace> -w
```

First deployment can take several additional minutes before all pods are ready.

## Verification And Smoke Tests

### Helm Release Checks

```bash
helm list -A
helm status <prereqs-release> -n <platform-system-namespace>
helm status <app-release> -n <application-namespace>
helm get notes <app-release> -n <application-namespace>
```

Expected:

- `obaas-prereqs` release is deployed once in the cluster.
- Each OBaaS tenant/application release is deployed in its own namespace.
- Helm notes render without obvious missing value errors.

### Kubernetes Resource Checks

Prerequisites namespace:

```bash
kubectl get pods -n <platform-system-namespace>
kubectl get deploy -n <platform-system-namespace>
kubectl get svc -n <platform-system-namespace>
kubectl get events -n <platform-system-namespace> --sort-by=.lastTimestamp
```

Application namespace:

```bash
kubectl get pods -n <application-namespace>
kubectl get jobs -n <application-namespace>
kubectl get svc -n <application-namespace>
kubectl get ingress -n <application-namespace>
kubectl get gateway -n <application-namespace>
kubectl get httproute -n <application-namespace>
kubectl get secrets -n <application-namespace>
kubectl get events -n <application-namespace> --sort-by=.lastTimestamp
```

Expected:

- Pods reach `Running` or `Completed` as appropriate.
- Init jobs complete successfully.
- Services have ClusterIP or LoadBalancer addresses as appropriate.
- Ingress or Gateway resources exist when enabled.
- Required secrets exist.

If a namespace does not have Gateway API resources because Envoy Gateway is disabled, that is acceptable. If a namespace does not have Ingress resources because ingress-nginx is disabled, that is acceptable.

### Wait And Describe Checks

```bash
kubectl wait --for=condition=Ready pod --all -n <platform-system-namespace> --timeout=10m
kubectl wait --for=condition=Ready pod --all -n <application-namespace> --timeout=15m
```

If the application namespace contains completed job pods, `kubectl wait pod --all` may report those completed pods as not ready. In that case, verify jobs separately with `kubectl get jobs -n <application-namespace>` and check readiness on current deployment/statefulset pods.

If anything is not ready:

```bash
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --all-containers --tail=200
```

Look for:

- image pull failures
- missing secrets
- pending PVCs
- failed database connection
- failed certificate webhook calls
- insufficient CPU or memory
- failed ClickHouse or SigNoz initialization
- failed APISIX or gateway startup

### Database Initialization Checks

Find database-related jobs and pods:

```bash
kubectl get jobs -n <application-namespace> | grep -E 'db|database|init|sql'
kubectl get pods -n <application-namespace> | grep -E 'db|database|sql|exporter'
```

Inspect logs:

```bash
kubectl logs -n <application-namespace> job/<database-init-job-name> --all-containers --tail=200
kubectl logs -n <application-namespace> deploy/<database-exporter-deployment-name> --all-containers --tail=200
```

Expected:

- Database init job completes.
- `OBAAS_USER` is created or detected if pre-existing.
- Database exporter starts and can connect.
- No repeated authentication, wallet, DSN, or service-name errors appear.

### SigNoz Verification

Find the SigNoz service and credential secret:

```bash
kubectl get svc -n <application-namespace> | grep signoz
kubectl get secrets -n <application-namespace> | grep -i signoz
```

If `signoz.auth.existingSecret` was set, use that secret. If the chart auto-created credentials, the chart notes and templates use `signoz-authn`; some docs may describe a namespace-derived Signoz secret name, so discover the exact secret with the command above.

Read credentials:

```bash
kubectl -n <application-namespace> get secret <signoz-secret-name> \
  -o jsonpath='{.data.email}' | base64 -d && echo

kubectl -n <application-namespace> get secret <signoz-secret-name> \
  -o jsonpath='{.data.password}' | base64 -d && echo
```

Port-forward:

```bash
kubectl -n <application-namespace> port-forward svc/<signoz-service-name> 8080:8080
```

Smoke test:

```bash
curl -f http://127.0.0.1:8080/api/v1/health?live=1
```

Expected:

- Health endpoint returns success.
- UI loads at `http://localhost:8080`.
- Retrieved credentials allow login.
- Pre-installed dashboards are present.
- Logs, metrics, or traces begin appearing after platform and application traffic.

### APISIX Verification

Find APISIX resources:

```bash
kubectl get pods -n <application-namespace> | grep apisix
kubectl get svc -n <application-namespace> | grep apisix
kubectl get configmap -n <application-namespace> | grep apisix
```

Port-forward the admin service:

```bash
kubectl -n <application-namespace> port-forward svc/<apisix-admin-service-name> 9180:9180
```

Retrieve the admin key from the APISIX configmap. If the configmap is named `apisix`, the docs show:

```bash
kubectl -n <application-namespace> get configmap apisix -o yaml \
  | yq '.data."config.yaml"' \
  | yq '.deployment.admin.admin_key[] | select(.name == "admin") | .key'
```

If the configmap name is release-prefixed, substitute the discovered configmap name.

Smoke test:

```bash
curl http://127.0.0.1:9180/apisix/admin/routes \
  -H "X-API-key: <admin-key>" \
  -X GET
```

Expected:

- APISIX admin API responds.
- Route list request returns JSON.
- APISIX pod logs do not show repeated etcd, plugin, or discovery errors.

If custom plugins were installed, create or use a test route with the plugin enabled and confirm the APISIX logs contain the plugin's expected log message.

### Eureka Verification

Find the Eureka service:

```bash
kubectl get svc -n <application-namespace> | grep eureka
kubectl get pods -n <application-namespace> | grep eureka
```

Port-forward:

```bash
kubectl -n <application-namespace> port-forward svc/<eureka-service-name> 8761:8761
```

Open or curl:

```bash
curl -f http://127.0.0.1:8761
```

Expected:

- Eureka UI loads.
- Eureka server pods are ready.
- Registered services appear after platform/application services register.

### Spring Boot Admin Verification

Find the admin service:

```bash
kubectl get svc -n <application-namespace> | grep admin-server
kubectl get pods -n <application-namespace> | grep admin-server
```

Port-forward:

```bash
kubectl -n <application-namespace> port-forward svc/<admin-server-service-name> 8989:8989
```

Smoke test:

```bash
curl -f http://127.0.0.1:8989
```

Expected:

- Spring Boot Admin UI loads.
- Services appear once applications with actuator endpoints register.

### Envoy Gateway Verification

If `gateway-helm.enabled` is true, find Envoy Gateway resources:

```bash
kubectl get pods -n <application-namespace> | grep -i envoy
kubectl get gatewayclass
kubectl get gateway -n <application-namespace>
kubectl get httproute -n <application-namespace>
```

Port-forward the admin interface when available:

```bash
kubectl -n <application-namespace> port-forward deployment/envoy-gateway 19000:19000
```

Expected:

- Envoy Gateway controller is running.
- Gateway API resources are accepted and programmed.
- No repeated listener, route, or certificate errors appear in logs.

### Ingress Verification

If `ingress-nginx.enabled` is true:

```bash
kubectl get pods -n <application-namespace> | grep ingress
kubectl get svc -n <application-namespace> | grep ingress
kubectl get ingressclass
kubectl get ingress -n <application-namespace>
```

Expected:

- ingress-nginx controller is running.
- Multi-tenant installs have unique IngressClass and election IDs.
- LoadBalancer service receives an external address when applicable.

### Platform Component Logs

Inspect logs for enabled components:

```bash
kubectl logs -n <application-namespace> deploy/<config-server-deployment-name> --all-containers --tail=100
kubectl logs -n <application-namespace> deploy/<admin-server-deployment-name> --all-containers --tail=100
kubectl logs -n <application-namespace> statefulset/<eureka-statefulset-name> --all-containers --tail=100
kubectl logs -n <application-namespace> deploy/<otmm-deployment-name> --all-containers --tail=100
kubectl logs -n <application-namespace> deploy/<database-exporter-deployment-name> --all-containers --tail=100
```

Discover exact workload names with:

```bash
kubectl get deploy,statefulset -n <application-namespace>
```

Expected:

- No repeated startup crashes.
- No missing secret/configmap errors.
- No persistent database authentication or network failures.
- No telemetry collector connection loops when SigNoz is enabled.

### Final Acceptance Checklist

Consider installation successful when:

- Helm releases are deployed.
- All prerequisite pods are healthy.
- All OBaaS pods are `Running` and init jobs are `Completed`.
- Persistent volume claims are bound.
- The selected external access resources are present.
- Database initialization succeeded.
- Database exporter is connected when enabled.
- SigNoz UI and health endpoint work when enabled.
- APISIX admin API responds when enabled.
- Eureka UI works when enabled.
- Spring Boot Admin UI works when enabled.
- Envoy Gateway or ingress-nginx reports healthy resources when enabled.
- No relevant namespace events show active image pull, scheduling, storage, webhook, or authentication failures.

## Troubleshooting Pointers

- `ImagePullBackOff`: verify private registry mirroring, pull secret names, and per-subchart image fields.
- `Pending` pods: verify node capacity and PVC binding.
- Failed database init: verify secret names, username/password, service name, ADB OCID, OCI config, wallet/API key setup, and database network access.
- cert-manager webhook errors: verify cert-manager pods and CRDs are healthy before installing `obaas-prereqs`.
- Duplicate CRD or operator conflicts: confirm `obaas-prereqs` was installed only once per cluster.
- Missing ingress or gateway address: verify the cluster network provider supports the selected access API and that load balancers can be provisioned.
- SigNoz setup failures: inspect Signoz, ClickHouse, and `signoz-setup` job logs; verify storage and credentials.
- APISIX failures: inspect APISIX, etcd, and custom plugin configuration; verify plugin file mount paths.
- Multi-tenant ingress conflicts: verify each tenant's ingress class, controller value, and election ID are unique.
