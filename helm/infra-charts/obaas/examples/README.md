# OBaaS Helm Chart - Example Configurations

This directory contains example values files demonstrating different configuration scenarios for the OBaaS Helm chart.

## Available Examples

### 1. Default Configuration (`values-default.yaml`)

Minimal configuration with no overrides. All subcharts use their default settings and deploy to the release namespace.

**Use case:** Quick start, development, testing

**Installation:**
```bash
helm upgrade --install obaas . -f examples/values-default.yaml -n obaas --create-namespace
```

### 2. Namespace and Scope Configuration (`values-namespace-override.yaml`)

Shows how to configure component scopes. All obaas components deploy to the release namespace (specified with `-n` flag). This example demonstrates how to configure the ingress-nginx watching scope.

**Use case:** Controlling which namespaces components watch

**Installation:**
```bash
# Option 1: Let Helm create the namespace
helm upgrade --install obaas . -f examples/values-namespace-override.yaml -n obaas-platform --create-namespace

# Option 2: Create the namespace first
kubectl create namespace obaas-platform
helm upgrade --install obaas . -f examples/values-namespace-override.yaml -n obaas-platform
```

### 3. Multi-Tenant Setup (`values-tenant1.yaml`, `values-tenant2.yaml`)

Configure unique IngressClass and credentials for each tenant to allow multiple OBaaS instances in the same cluster.

**Use case:** Multi-tenant deployments, namespace isolation, multiple independent OBaaS instances

**Why this is needed:**
- Each ingress-nginx controller creates a cluster-scoped `IngressClass` resource
- Multiple controllers must have unique IngressClass names to avoid conflicts
- Each controller needs unique election IDs to prevent leader election issues

**Installation:**
```bash
# Install first tenant
helm upgrade --install obaas-tenant1 . -n tenant1 -f examples/values-tenant1.yaml --create-namespace

# Install second tenant (with different IngressClass)
helm upgrade --install obaas-tenant2 . -n tenant2 -f examples/values-tenant2.yaml --create-namespace
```

**Important:** Always ensure each tenant has:
- Unique `controller.ingressClass` value
- Unique `controller.ingressClassResource.name` value
- Unique `controller.ingressClassResource.controllerValue`
- Unique `controller.electionID`

### 4. Existing ADB Configuration (`values-existing-adb.yaml`)

Configure OBaaS to use an existing OCI Autonomous Database (ADB-S) instead of deploying a database container.

**Use case:** Production deployments using a pre-provisioned OCI Autonomous Database

**Prerequisites:**
1. Obtain an OCI API Key and create the k8s configmap/secret:
```bash
python3 tools/oci_config.py --namespace NAMESPACE [--config CONFIG] [--profile PROFILE]
```

2. Create the privileged authentication secret for the ADMIN user:
```bash
kubectl -n NAMESPACE create secret generic db-priv-authn \
  --from-literal=username=ADMIN \
  --from-literal=password=<ADMIN PASSWORD> \
  --from-literal=service=<DBNAME>_TP
```

**Installation:**
```bash
helm upgrade --install obaas . \
  -n NAMESPACE \
  -f examples/values-existing-adb.yaml \
  --set database.oci.ocid=<ADB_OCID>
```

### 5. SIDB-FREE Database (`values-sidb-free.yaml`)

Example configuration for using Oracle Database Free as a container in the cluster. This is the default database type.

**Use case:** Development, testing, standalone deployments

**Installation:**
```bash
helm upgrade --install obaas . -f examples/values-sidb-free.yaml -n obaas --create-namespace
```

### 6. SigNoz Existing Secret (`values-signoz-existing-secret.yaml`)

Use a pre-existing Kubernetes secret for SigNoz admin authentication instead of auto-generating one.

**Use case:** GitOps workflows, pre-provisioned credentials

**Installation:**
```bash
# Create the secret first
kubectl create secret generic my-signoz-secret \
  --from-literal=email=admin@mydomain.com \
  --from-literal=password=my-secure-password \
  -n obaas

# Install with the example
helm upgrade --install obaas . -f examples/values-signoz-existing-secret.yaml -n obaas
```

### 7. Private Registry Configuration (`values-private-registry.yaml`)

Use a private container registry for all images with authentication.

**Use case:** Air-gapped environments, corporate registries, security compliance

**Prerequisites:**
1. Mirror all required images to your private registry
2. Create image pull secret:
```bash
kubectl create secret docker-registry myregistry-secret \
  --docker-server=myregistry.example.com \
  --docker-username=<username> \
  --docker-password=<password> \
  --docker-email=<email>
```

**Installation:**
```bash
helm upgrade --install obaas . -f examples/values-private-registry.yaml
```

## Customizing Examples

You can combine examples or create your own custom values file:

```bash
# Combine multi-tenant and private registry configurations
helm upgrade --install obaas-tenant1 . \
  -f examples/values-tenant1.yaml \
  -f examples/values-private-registry.yaml \
  -n tenant1 --create-namespace
```

Or create a custom values file that extends an example:

```yaml
# my-custom-values.yaml
global:
  imagePullSecrets:
    - myregistry-secret

# Disable components you don't need
ai-optimizer:
  enabled: false

signoz:
  enabled: false
```

## Namespace Details

All obaas chart components deploy to the release namespace (specified with `-n` flag during install). There is no `global.namespace` override.

**Component Scopes:**
- **ingress-nginx** - By default watches only the release namespace (`scope.enabled: true`)

## Image Registry Override Details

Each subchart has its own image configuration that must be explicitly set for private registries.

### Subcharts with Separate Registry Field
These subcharts have a dedicated registry field (set to your registry URL):
- **ingress-nginx**: `controller.image.registry`
- **signoz**: `global.imageRegistry`
- **apisix etcd**: `apisix.etcd.image.registry`

### OBaaS Components Requiring Full Repository Path
These components require the full image path including registry in their `image.repository`:
- **eureka**, **admin-server**, **conductor-server**, **otmm**, **oracle-database-exporter**
- **database** (for SIDB-FREE/ADB-FREE)
- **apisix**: `apisix.image.repository`, `apisix.initContainer.image`

**Note:** Image pull secrets are propagated to subcharts via `global.imagePullSecrets`.

See `values-private-registry.yaml` for complete examples.

**Note:** Cluster-singleton prerequisites (cert-manager, external-secrets, metrics-server, kube-state-metrics, strimzi-kafka-operator, coherence-operator) have their own image configuration in the `obaas-prereqs` chart.

## More Information

For complete configuration options, see the main `values.yaml` file and individual subchart documentation.
