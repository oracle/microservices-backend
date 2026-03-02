# OBaaS Helm Charts - version 2.0.0 

This directory contains the Helm charts for Oracle Backend for Microservices and AI (OBaaS).

## Directory Structure

The `infra-charts` directory contains charts for installing OBaaS itself into a Kubernetes
cluster.  The `app-charts` directory contains charts that can be used to deploy your own
microservices applications into an existing OBaaS environment.

```
helm/
├── app-charts/           # Charts for deploying microservices applications into OBaaS
|  └── obaas-sample-app/  # Chart to deploy a Spring Boot or Helidon microservice
├── infra-charts/         # Charts for installing the OBaaS infrastructure itself
   ├── obaas-prereqs/     # Cluster-singleton prerequisites (install once per cluster)
   ├── obaas/             # OBaaS application chart (install N times in different namespaces)
   └── tools/             # Supporting scripts and tools
```

## Infrastructure - Installation Order

### Step 0: Configure Helm Repository

Add the Helm repository to your local Helm installation using the following commands:

```bash
helm repo add obaas https://oracle.github.io/microservices-backend/helm
helm repo update
```

### Step 1: Install Prerequisites (Once Per Cluster)

The prerequisites chart contains cluster-scoped singleton components that should only be installed once:

- **cert-manager** - Certificate management
- **external-secrets** - External secrets management
- **metrics-server** - Resource metrics
- **kube-state-metrics** - Cluster state metrics
- **strimzi-kafka-operator** - Kafka cluster management
- **oraoperator** - Oracle Database Operator for Kubernetes

```bash
helm upgrade --install obaas-prereqs obaas/obaas-prereqs -n obaas-system --create-namespace [--debug] [--values <path_to_custom_values>]
```

### Step 2: Install OBaaS (Multiple Times)

If you're installing OBaaS using an ADB-S and not using **workload identity**, you need to create the namespace for OBaas and the secret containing the API key. You also need to change `values.yaml` file. There is a helper script called `tools/oci_config` that generates the `kubectl` command needed to create the secret. The secret name will be `oci-config-file`.

Make sure you have cloned this GitHub repository and then run the following commands:

```bash
cd helm/infra-charts
python3 tools/oci-config.py --namespace [namespace] 
```

After prerequisites are installed, you can install the OBaaS chart multiple times in different namespaces for multi-tenancy:

```bash
# Install for tenant 1
helm upgrade --install obaas-tenant1 obaas/obaas -n tenant1 --create-namespace [--debug] [--values examples/values-tenant1.yaml]

# Install for tenant 2
helm upgrade --install obaas-tenant2 obaas/obaas -n tenant2 --create-namespace [--debug] [--values examples/values-tenant2.yaml]

# Install for tenant N...
helm upgrade --install obaas-tenantN obaas/obaas -n tenantN --create-namespace [--debug] [--values examples/values-tenantN.yaml]
```

Each OBaaS instance includes:

- **ingress-nginx** - Ingress controller for the namespace (unless running on OCI)
- **signoz** - Observability stack (with its own ClickHouse)
- **Coherence Operator** - Coherence cluster operator
- **Admin Server** - Admins server
- **Conductor server and Redis** - Workflow server
- **Eureka** - Service Discovery
- **OTMM** - Oracle Transaction Manager for Microserveices
- **APISIX** - APISIX API GW

## Architecture

**Why separate charts?**

- **obaas-prereqs**: Contains operators and infrastructure that install CRDs (Custom Resource Definitions) which are cluster-scoped. Installing these multiple times would cause conflicts.

- **obaas**: Contains namespace-scoped resources that can be installed multiple times. Each installation can create Kafka clusters via CRs (managed by the Strimzi operator from prereqs).

## Configuration

See individual chart directories for detailed configuration options:

- [obaas-prereqs/README.md](obaas-prereqs/README.md)
- [obaas/examples/](obaas/examples/) - Example configurations

## Uninstallation

**Uninstall OBaaS instances first:**
```bash
helm uninstall obaas-tenant1 -n tenant1
helm uninstall obaas-tenant2 -n tenant2
```

**Then uninstall prerequisites:**
```bash
helm uninstall obaas-prereqs -n obaas-system
```

**Warning:** Uninstalling prerequisites will affect all OBaaS instances in the cluster.
