---
title: Deploying an Application to OBaaS
sidebar_position: 5
---

# Deploying an Application to OBaaS

This guide walks through deploying an application to Oracle Backend for Microservices and AI (OBaaS). It covers each step from creating container repositories through exposing services via the API gateway.

The steps below are generic — replace placeholder values like `my-app`, `my-service`, and `mydb` with values appropriate to your application.

## Prerequisites

Before you begin, ensure the following tools are installed and configured:

| Tool | Purpose | Verify |
|------|---------|--------|
| **Java** | Build application JARs | `java -version` |
| **Maven** | Build and package | `mvn --version` |
| **Docker** | Build and push container images | `docker ps` |
| **kubectl** | Interact with Kubernetes cluster | `kubectl cluster-info` |
| **Helm** | Deploy applications to Kubernetes | `helm version` |
| **OCI CLI** | Manage OCI resources (if using OCIR) | `oci --version` |

Additional requirements:

- `JAVA_HOME` must be set and point to your Java installation
- Docker daemon must be running
- kubectl must be connected to the target cluster (`kubectl config current-context`)
- OBaaS platform must already be installed in your target namespace

:::tip
If you are using OCI Container Registry (OCIR), configure the OCI CLI first:

```bash
oci setup config
```

The registry URL is derived from your OCI region and namespace: `<region>.ocir.io/<namespace>`.
:::

## Step 1: Create Container Repositories

Each microservice needs a container repository to store its image. Create one repository per service in your container registry of choice — OCI Container Registry (OCIR), Amazon ECR, Azure Container Registry, Google Artifact Registry, Docker Hub, GitHub Container Registry, or any Docker V2-compatible registry. Use your provider's CLI or console to create the repositories, then authenticate Docker with `docker login`. The registry URL format varies by provider; consult your provider's documentation for the correct path. The rest of this guide works the same regardless of which registry you use.

The example below shows how to create repositories in OCI Container Registry. Adapt to your registry as needed.

```bash
# Set your variables
COMPARTMENT="my-compartment"
PREFIX="my-app"

# Get your compartment OCID
COMPARTMENT_OCID=$(oci iam compartment list --all \
  --compartment-id-in-subtree true \
  --query "data[?name=='${COMPARTMENT}'].id | [0]" \
  --raw-output)

# Create a repository for each service
for SERVICE in service1 service2 service3; do
  oci artifacts container repository create \
    --compartment-id "$COMPARTMENT_OCID" \
    --display-name "${PREFIX}/${SERVICE}" \
    --is-public true
done
```

After creating the repositories, authenticate Docker to your registry:

```bash
docker login <registry-host>
```

## Step 2: Build and Push Container Images

### Configure JKube in Your pom.xml

The `obaas-sample-app` Helm chart expects a standard container image. Use [Eclipse JKube](https://eclipse.dev/jkube/) to build and push images with Maven.

Add the JKube plugin to each service's `pom.xml`:

```xml
<plugin>
  <groupId>org.eclipse.jkube</groupId>
  <artifactId>kubernetes-maven-plugin</artifactId>
  <version>1.18.2</version>
  <configuration>
    <images>
      <image>
        <!-- highlight-next-line -->
        <name>${image.registry}/${project.artifactId}:${project.version}</name>
        <build>
          <from>ghcr.io/oracle/openjdk-image-obaas:21</from>
          <assembly>
            <mode>dir</mode>
            <targetDir>/deployments</targetDir>
          </assembly>
          <cmd>java -jar /deployments/${project.artifactId}-${project.version}.jar</cmd>
        </build>
      </image>
    </images>
  </configuration>
</plugin>
```

Replace the `<name>` value with your registry path. The `${image.registry}` property can be passed on the command line with `-Dimage.registry=...`.

### Build Dependencies

If your project has shared modules (parent POM, common libraries, build tools), install them to your local Maven repository first:

```bash
# Install parent POM
mvn clean install -N

# Install shared modules (adjust module names to your project)
mvn clean install -pl common
```

### Build and Push

```bash
# Set your registry path
REGISTRY="<region>.ocir.io/<namespace>/my-app"

# Build the JAR
mvn clean package -DskipTests -pl my-service

# Build the container image
mvn org.eclipse.jkube:kubernetes-maven-plugin:build \
  -pl my-service \
  -Dimage.registry=$REGISTRY

# Push to registry
mvn org.eclipse.jkube:kubernetes-maven-plugin:push \
  -pl my-service \
  -Dimage.registry=$REGISTRY
```

Or combine build and push in a single command:

```bash
mvn clean package k8s:build k8s:push \
  -DskipTests \
  -pl my-service \
  -Dimage.registry=$REGISTRY
```

:::tip
To build and push all services at once, pass a comma-separated list to `-pl`:

```bash
mvn clean package k8s:build k8s:push \
  -DskipTests \
  -pl service1,service2,service3 \
  -Dimage.registry=$REGISTRY
```
:::

## Step 3: Create Database Secrets

If your application connects to an Oracle database, you need to create Kubernetes secrets containing the database credentials. The Helm chart uses these secrets to configure datasource environment variables and to run a database initialization job.

### Secret Naming Convention

The Helm chart expects secrets following this naming pattern:

| Secret | Purpose | Keys |
|--------|---------|------|
| `{dbname}-db-priv-authn` | Privileged credentials (for creating users, Liquibase) | `username`, `password`, `service` |
| `{dbname}-{service}-db-authn` | Application credentials (per service) | `username`, `password`, `service` |

### Create the Privileged Secret

The privileged secret must exist before deploying. It is typically created during OBaaS platform setup. If it does not exist, create it manually:

```bash
kubectl -n <namespace> create secret generic <dbname>-db-priv-authn \
  --from-literal=username=ADMIN \
  --from-literal=password='<admin-password>' \
  --from-literal=service=<dbname>_tp
```

The `service` value is the TNS service name for your database (for example, `mydb_tp`).

### Create Application Secrets

Create a secret for each distinct database user your application needs. Services that share a schema can share a secret.

```bash
kubectl -n <namespace> create secret generic <dbname>-<service>-db-authn \
  --from-literal=username=<SERVICE_USERNAME> \
  --from-literal=password='<service-password>' \
  --from-literal=service=<dbname>_tp
```

:::info Oracle Password Requirements
Oracle database passwords must meet the following rules:
- 12–30 characters
- At least two uppercase letters, two lowercase letters, two digits, and two special characters (`#` or `_`)
- Cannot start with a digit or special character
- Cannot contain the username

Oracle usernames are stored as uppercase by default.
:::

### Verify Secrets

```bash
# List all database secrets
kubectl get secrets -n <namespace> | grep db-authn

# View a secret's keys (not values)
kubectl describe secret <dbname>-<service>-db-authn -n <namespace>

# Decode a specific value
kubectl get secret <dbname>-<service>-db-authn -n <namespace> \
  -o jsonpath='{.data.password}' | base64 -d
```

## Step 4: Deploy with Helm

### Add the Helm Repository

The `obaas-sample-app` Helm chart is published in the OBaaS Helm repository:

```bash
helm repo add obaas https://oracle.github.io/microservices-backend/helm
helm repo update
```

Verify the chart is available:

```bash
helm search repo obaas/obaas-sample-app
```

### Identify the OBaaS Release Name

The Helm chart needs to know the OBaaS platform release name to derive service endpoints (Eureka, OTEL collector, APISIX, etc.). Find it with:

```bash
helm list -n <namespace>
```

Look for the release that is **not** an application deployment (i.e., not using the `obaas-sample-app` chart). This is your OBaaS platform release name.

### Create a values.yaml

Create a `values.yaml` for each service you want to deploy. Here is a minimal example for a Spring Boot service:

```yaml
fullnameOverride: "my-service"

image:
  repository: "<region>.ocir.io/<namespace>/my-app/my-service"
  tag: "0.0.1-SNAPSHOT"

obaas:
  releaseName: "<obaas-release-name>"
  framework: "SPRING_BOOT"

database:
  name: "<dbname>"

eureka:
  enabled: true

otel:
  enabled: true

otmm:
  enabled: false
```

For a Helidon service, set `framework: "HELIDON"` and add the required Helidon values:

```yaml
obaas:
  framework: "HELIDON"

helidon:
  datasource:
    name: "myDatasource"       # Must match application.yaml
  otel:
    serviceName: "my-service"
```

### Helm Values Reference

| Value | Required | Description |
|-------|----------|-------------|
| `image.repository` | Yes | Full image path (without tag) |
| `image.tag` | Yes | Image tag |
| `obaas.releaseName` | Yes | OBaaS platform Helm release name |
| `obaas.framework` | Yes | `SPRING_BOOT` or `HELIDON` |
| `database.name` | If using DB | Database name (derives secret names and wallet) |
| `database.authN.secretName` | No | Override derived secret name `{dbname}-{release}-db-authn` |
| `database.aq.enabled` | No | Grant Advanced Queuing (AQ/JMS) permissions (default: `false`) |
| `eureka.enabled` | No | Register with Eureka service discovery (default: `true`) |
| `otel.enabled` | No | Enable OpenTelemetry integration (default: `true`) |
| `otmm.enabled` | No | Enable MicroTx LRA distributed transactions (default: `false`) |
| `service.port` | No | Container and service port (default: `8080`) |
| `replicaCount` | No | Number of pod replicas (default: `1`) |

### Deploy a Service

```bash
helm upgrade --install my-service obaas/obaas-sample-app \
  -f values.yaml \
  --namespace <namespace> \
  --set image.repository=<registry>/my-service \
  --set image.tag=0.0.1-SNAPSHOT \
  --set obaas.releaseName=<obaas-release> \
  --set database.name=<dbname> \
  --wait --timeout 5m
```

Values passed via `--set` override those in `values.yaml`. This is useful for CI/CD pipelines where the registry and tag vary per build.

### What Gets Deployed

For each `helm install`, the chart creates:

1. **Deployment** — your application pod with framework-aware environment variables (datasource, Eureka, OTEL, LRA)
2. **Service** — a ClusterIP service on port 8080 (default)
3. **DB Init Job** — a Kubernetes Job that runs SQLcl to create the database user if it doesn't already exist. It uses the privileged secret to connect and creates a user matching the application secret credentials. The job retries up to 60 times (10-second intervals) and auto-cleans after 5 minutes.
4. **DB Init ConfigMap** — the SQL script used by the init job. If `database.aq.enabled` is `true`, AQ permissions (`DBMS_AQ`, `DBMS_AQADM`, etc.) are included.

The database wallet (TLS certificates for Oracle Autonomous Database) is automatically mounted at `/oracle/tnsadmin` from the OBaaS platform's wallet secret.

### Verify the Deployment

```bash
# Check pod status
kubectl get pods -n <namespace>

# Check service
kubectl get svc -n <namespace>

# View pod logs
kubectl logs -n <namespace> -l app.kubernetes.io/name=my-service

# Check the db-init job
kubectl get jobs -n <namespace>

# Test connectivity via port-forward
kubectl port-forward -n <namespace> svc/my-service 8080:8080
curl http://localhost:8080/actuator/health
```

### Upgrade and Uninstall

```bash
# Upgrade (after pushing a new image)
helm upgrade my-service obaas/obaas-sample-app \
  -f values.yaml \
  --namespace <namespace> \
  --set image.tag=0.0.2-SNAPSHOT \
  --wait --timeout 5m

# Uninstall
helm uninstall my-service -n <namespace>
```

## Step 5: Create API Gateway Routes

The OBaaS platform uses [Apache APISIX](https://apisix.apache.org/) as its API gateway. To expose your services externally, create routes that map URI patterns to Eureka service names.

### Get the APISIX Admin Key

The admin API key is stored in the APISIX ConfigMap:

```bash
# Replace <obaas-release> with your release name
kubectl get configmap <obaas-release>-apisix -n <namespace> \
  -o jsonpath='{.data.config\.yaml}' | grep -A2 '"admin"'
```

Look for the `key:` value under the admin user.

### Port-Forward to the Admin API

```bash
kubectl port-forward -n <namespace> svc/<obaas-release>-apisix-admin 9180:9180 &
```

### Create a Route

```bash
ADMIN_KEY="<your-admin-key>"

curl http://localhost:9180/apisix/admin/routes/1 \
  -H "X-API-KEY: $ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -X PUT \
  -d '{
    "name": "my-service",
    "desc": "My Service",
    "uri": "/api/v1/my-service*",
    "methods": ["GET", "POST", "PUT", "DELETE", "OPTIONS", "HEAD"],
    "upstream": {
      "service_name": "MY-SERVICE",
      "type": "roundrobin",
      "discovery_type": "eureka"
    },
    "plugins": {
      "opentelemetry": {
        "sampler": {
          "name": "always_on"
        }
      },
      "prometheus": {
        "prefer_name": true
      }
    }
  }'
```

Key fields:

| Field | Description |
|-------|-------------|
| `uri` | The URL pattern to match. Use a wildcard suffix (e.g., `/api/v1/my-service*`). |
| `upstream.service_name` | The Eureka-registered service name (uppercase by default for Spring Boot). |
| `upstream.discovery_type` | Set to `eureka` so APISIX resolves service instances from the Eureka registry. |
| `plugins.opentelemetry` | Enables distributed tracing through the gateway. |
| `plugins.prometheus` | Enables Prometheus metrics collection for the route. |

### Verify the Route

```bash
# Test through the gateway
curl http://<apisix-gateway>/api/v1/my-service/health

# List all routes
curl http://localhost:9180/apisix/admin/routes \
  -H "X-API-KEY: $ADMIN_KEY" | jq '.list[].value.name'
```

### Stop Port-Forward

When done configuring routes, stop the port-forward:

```bash
kill %1
```

## Summary

The full deployment flow:

| Step | What | How |
|------|------|-----|
| 1 | Create container repositories | OCI CLI or registry UI |
| 2 | Build and push images | Maven + JKube (`k8s:build` + `k8s:push`) |
| 3 | Create database secrets | `kubectl create secret` |
| 4 | Deploy with Helm | `helm upgrade --install` with `obaas-sample-app` chart |
| 5 | Create API gateway routes | APISIX Admin API via `curl` |

After all steps are complete, your application is accessible through the APISIX gateway at the URI patterns you configured.
