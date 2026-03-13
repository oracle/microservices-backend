# Oracle Database Operator Helm Chart

This Helm chart installs the Oracle Database Operator for Kubernetes.

## Prerequisites

- Kubernetes 1.21+
- Helm 3.7+

## cert-manager Installation Options

This chart requires cert-manager for webhook certificates. Four deployment scenarios are supported:

| Use-Case | cert-manager Install | Namespace | Example File |
|----------|---------------------|-----------|--------------|
| 1 | Standalone (external) | `cert-manager` | [standalone-cert-manager-default-ns.yaml](examples/standalone-cert-manager-default-ns.yaml) |
| 2 | Standalone (external) | Custom | [standalone-cert-manager-custom-ns.yaml](examples/standalone-cert-manager-custom-ns.yaml) |
| 3 | Subchart (bundled) | `cert-manager` | [subchart-cert-manager-default-ns.yaml](examples/subchart-cert-manager-default-ns.yaml) |
| 4 | Subchart (bundled) | Custom | [subchart-cert-manager-custom-ns.yaml](examples/subchart-cert-manager-custom-ns.yaml) |

### Use-Case 1: Standalone cert-manager in "cert-manager" namespace

Use this when cert-manager is already installed or managed separately.

```bash
# Pre-requisite: Install cert-manager
helm repo add jetstack https://charts.jetstack.io
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --set installCRDs=true

# Install operator
helm upgrade --install oraoperator . --set cert-manager.enabled=false
```

### Use-Case 2: Standalone cert-manager in custom namespace

Use this when cert-manager is installed in a non-default namespace.

```bash
# Pre-requisite: Install cert-manager in custom namespace
helm repo add jetstack https://charts.jetstack.io
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace my-cert-manager --create-namespace \
  --set installCRDs=true

# Install operator
helm upgrade --install oraoperator . \
  --set cert-manager.enabled=false \
  --set cert-manager.namespace=my-cert-manager
```

### Use-Case 3: Subchart cert-manager in "cert-manager" namespace (default)

Use this for a simple all-in-one installation.

```bash
# Update dependencies first
helm dependency update .

# Install operator (cert-manager installed automatically)
helm upgrade --install oraoperator .
```

### Use-Case 4: Subchart cert-manager in custom namespace

Use this when you want the bundled cert-manager in a custom namespace.

```bash
# Update dependencies first
helm dependency update .

# Install operator
helm upgrade --install oraoperator . --set cert-manager.namespace=my-cert-manager
```

## Uninstall

```bash
helm uninstall oraoperator
```

## Configuration

### cert-manager Settings

| Parameter | Description | Default |
|-----------|-------------|---------|
| `cert-manager.enabled` | Install cert-manager as a subchart | `true` |
| `cert-manager.namespace` | Namespace for cert-manager | `cert-manager` |
| `cert-manager.installCRDs` | Install cert-manager CRDs | `true` |
| `certManagerWaitJob.enabled` | Wait for cert-manager webhook before creating Issuer | `true` |
| `certManagerWaitJob.image.repository` | Image repository for wait job | `registry.k8s.io/kubectl` |
| `certManagerWaitJob.image.tag` | Image tag for wait job | `v1.28.0` |
| `certManagerWaitJob.image.pullPolicy` | Image pull policy for wait job | `IfNotPresent` |
| `certManagerWaitJob.maxAttempts` | Max retry attempts for webhook readiness | `60` |
| `certManagerWaitJob.sleepSeconds` | Sleep duration between retries | `5` |
| `certManagerWaitJob.resources` | Resource limits for wait job | `{}` |
| `certManagerWaitJob.externalWebhookServiceName` | Webhook service name (when `cert-manager.enabled=false`) | `cert-manager-webhook` |

### General Settings

| Parameter | Description | Default |
|-----------|-------------|---------|
| `namespace` | Namespace for Oracle Database Operator resources | `oracle-database-operator-system` |
| `imagePullSecrets` | Image pull secrets for private registries | `[]` |

### Scope Settings

| Parameter | Description | Default |
|-----------|-------------|---------|
| `scope.mode` | Deployment scope: `cluster` or `namespace` | `cluster` |
| `scope.watchNamespaces` | Namespaces to watch when `scope.mode=namespace` | `[]` |
| `rbac.nodeAccess` | Grant permission to list/watch nodes (for NodePort services) | `false` |

### Operator Deployment Settings

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicas` | Number of replicas | `3` |
| `image.repository` | Image repository | `container-registry.oracle.com/database/operator` |
| `image.tag` | Image tag | `2.0` |
| `image.pullPolicy` | Image pull policy | `IfNotPresent` |
| `resources.limits.cpu` | CPU limit | `400m` |
| `resources.limits.memory` | Memory limit | `400Mi` |
| `resources.requests.cpu` | CPU request | `400m` |
| `resources.requests.memory` | Memory request | `400Mi` |
| `leaderElection` | Enable leader election | `true` |
| `probes.liveness.initialDelaySeconds` | Liveness probe initial delay | `15` |
| `probes.liveness.periodSeconds` | Liveness probe period | `20` |
| `probes.readiness.initialDelaySeconds` | Readiness probe initial delay | `5` |
| `probes.readiness.periodSeconds` | Readiness probe period | `10` |
| `pdb.enabled` | Enable PodDisruptionBudget (when replicas > 1) | `true` |
| `pdb.minAvailable` | Minimum available pods | `1` |
| `pdb.maxUnavailable` | Maximum unavailable pods (alternative to minAvailable) | - |
| `affinity` | Pod affinity rules (default: soft anti-affinity when replicas > 1) | `{}` |
| `nodeSelector` | Node selector for scheduling | `{}` |
| `tolerations` | Pod tolerations | `[]` |
| `terminationGracePeriodSeconds` | Termination grace period | `10` |
| `extraEnv` | Extra environment variables | `[]` |

### Webhook Settings

| Parameter | Description | Default |
|-----------|-------------|---------|
| `webhook.failurePolicy` | Webhook failure policy (`Fail` or `Ignore`) | `Fail` |
| `webhook.port` | Webhook server port | `9443` |
| `webhook.certificateSecretName` | Secret name for webhook TLS certificate | `webhook-server-cert` |
| `webhook.timeoutSeconds` | Webhook timeout in seconds | `10` |

### OCI Credentials Settings

| Parameter | Description | Default |
|-----------|-------------|---------|
| `ociCredentials.existingSecretName` | Existing Secret with OCI credentials | `""` |
| `ociCredentials.tenancy` | OCI tenancy OCID | `""` |
| `ociCredentials.user` | OCI user OCID | `""` |
| `ociCredentials.fingerprint` | OCI API key fingerprint | `""` |
| `ociCredentials.region` | OCI region | `""` |
| `ociCredentials.passphrase` | Passphrase for encrypted private key | `""` |
| `ociCredentials.secretName` | Existing Secret with OCI API private key | `""` |

## Deployment Modes

### Cluster-Scoped (Default)

The operator monitors all namespaces in the cluster.

```bash
helm upgrade --install oraoperator . --set scope.mode=cluster
```

### Namespace-Scoped

The operator monitors only specified namespaces.

```bash
helm upgrade --install oraoperator . \
  --set scope.mode=namespace \
  --set 'scope.watchNamespaces={default,my-app-ns}'
```

## High Availability

When running multiple replicas (`replicas > 1`), the chart automatically:

1. **Enables leader election** - Only one replica processes events at a time
2. **Applies pod anti-affinity** - Spreads pods across nodes (soft preference)
3. **Creates PodDisruptionBudget** - Ensures minimum availability during disruptions

To customize HA behavior:

```bash
helm upgrade --install oraoperator . \
  --set replicas=3 \
  --set pdb.minAvailable=2
```

## OCI Credentials

Autonomous Database operations require OCI credentials.

### Option 1: Reference Existing Secret

```bash
helm upgrade --install oraoperator . \
  --set ociCredentials.existingSecretName=oci-cred \
  --set ociCredentials.secretName=oci-privatekey
```

### Option 2: Provide Values Directly

```bash
# Create the secret with your private key first
kubectl create secret generic oci-privatekey \
  --from-file=privatekey=/path/to/oci_api_key.pem \
  -n oracle-database-operator-system

# Install with credential values
helm upgrade --install oraoperator . \
  --set ociCredentials.tenancy=ocid1.tenancy.oc1..xxx \
  --set ociCredentials.user=ocid1.user.oc1..xxx \
  --set ociCredentials.fingerprint=aa:bb:cc:dd:... \
  --set ociCredentials.region=us-ashburn-1 \
  --set ociCredentials.secretName=oci-privatekey
```

## Generating YAML Manifests

```bash
# Generate with defaults
helm template oraoperator . --include-crds > oracle-database-operator.yaml

# Namespace-scoped
helm template oraoperator . \
  --include-crds \
  --set scope.mode=namespace \
  --set 'scope.watchNamespaces={default,my-app-ns}' \
  > oracle-database-operator-namespace-scoped.yaml
```

## Notes

- The chart creates the cert-manager namespace automatically when using the subchart.
- A wait job ensures the cert-manager webhook is ready before creating Issuer resources.
- Use `skipCertManagerCheck=true` for GitOps workflows where cert-manager is installed separately.
- Health probes use HTTP GET requests on the `/metrics` endpoint (port 8080).
