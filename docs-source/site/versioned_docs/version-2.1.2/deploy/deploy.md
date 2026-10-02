---
title: Deploying an Application to OBaaS
sidebar_position: 5
---

This guide walks through deploying an application to Oracle Backend for Microservices and AI (OBaaS). It covers each step from creating container repositories through exposing services via the API gateway.

The steps below are generic — replace placeholder values like `my-app`, `my-service`, and `mydb` with values appropriate to your application.

## Prerequisites

Before you begin, ensure the following tools are installed and configured:

<table aria-label="Prerequisites table">
  <thead>
    <tr>
      <th scope="col">Tool</th>
      <th scope="col">Purpose</th>
      <th scope="col">Verify</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <th scope="row"><strong>Java</strong></th>
      <td>Build application JARs</td>
      <td><code>java -version</code></td>
    </tr>
    <tr>
      <th scope="row"><strong>Maven</strong></th>
      <td>Build and package</td>
      <td><code>mvn --version</code></td>
    </tr>
    <tr>
      <th scope="row"><strong>Docker</strong></th>
      <td>Build and push container images</td>
      <td><code>docker ps</code></td>
    </tr>
    <tr>
      <th scope="row"><strong>kubectl</strong></th>
      <td>Interact with Kubernetes cluster</td>
      <td><code>kubectl cluster-info</code></td>
    </tr>
    <tr>
      <th scope="row"><strong>Helm</strong></th>
      <td>Deploy applications to Kubernetes</td>
      <td><code>helm version</code></td>
    </tr>
    <tr>
      <th scope="row"><strong>OCI CLI</strong></th>
      <td>Manage OCI resources (if using OCIR)</td>
      <td><code>oci --version</code></td>
    </tr>
  </tbody>
</table>

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

<table aria-label="Secret Naming Convention table">
  <thead>
    <tr>
      <th scope="col">Secret</th>
      <th scope="col">Purpose</th>
      <th scope="col">Keys</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <th scope="row"><code>&#123;dbname&#125;-db-priv-authn</code></th>
      <td>Privileged credentials (for creating users, Liquibase)</td>
      <td><code>username</code>, <code>password</code>, <code>service</code></td>
    </tr>
    <tr>
      <th scope="row"><code>&#123;dbname&#125;-&#123;service&#125;-db-authn</code></th>
      <td>Application credentials (per service)</td>
      <td><code>username</code>, <code>password</code>, <code>service</code></td>
    </tr>
  </tbody>
</table>

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

:::info[Oracle Password Requirements]
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

<table aria-label="Helm Values Reference table">
  <thead>
    <tr>
      <th scope="col">Value</th>
      <th scope="col">Required</th>
      <th scope="col">Description</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <th scope="row"><code>image.repository</code></th>
      <td>Yes</td>
      <td>Full image path (without tag)</td>
    </tr>
    <tr>
      <th scope="row"><code>image.tag</code></th>
      <td>Yes</td>
      <td>Image tag</td>
    </tr>
    <tr>
      <th scope="row"><code>obaas.releaseName</code></th>
      <td>Yes</td>
      <td>OBaaS platform Helm release name</td>
    </tr>
    <tr>
      <th scope="row"><code>obaas.framework</code></th>
      <td>Yes</td>
      <td><code>SPRING_BOOT</code> or <code>HELIDON</code></td>
    </tr>
    <tr>
      <th scope="row"><code>database.name</code></th>
      <td>If using DB</td>
      <td>Database name (derives secret names and wallet)</td>
    </tr>
    <tr>
      <th scope="row"><code>database.authN.secretName</code></th>
      <td>No</td>
      <td>Override derived secret name <code>&#123;dbname&#125;-&#123;release&#125;-db-authn</code></td>
    </tr>
    <tr>
      <th scope="row"><code>database.aq.enabled</code></th>
      <td>No</td>
      <td>Grant Advanced Queuing (AQ/JMS) permissions (default: <code>false</code>)</td>
    </tr>
    <tr>
      <th scope="row"><code>eureka.enabled</code></th>
      <td>No</td>
      <td>Register with Eureka service discovery (default: <code>true</code>)</td>
    </tr>
    <tr>
      <th scope="row"><code>otel.enabled</code></th>
      <td>No</td>
      <td>Enable OpenTelemetry integration (default: <code>true</code>)</td>
    </tr>
    <tr>
      <th scope="row"><code>otmm.enabled</code></th>
      <td>No</td>
      <td>Enable MicroTx LRA distributed transactions (default: <code>false</code>)</td>
    </tr>
    <tr>
      <th scope="row"><code>service.port</code></th>
      <td>No</td>
      <td>Container and service port (default: <code>8080</code>)</td>
    </tr>
    <tr>
      <th scope="row"><code>replicaCount</code></th>
      <td>No</td>
      <td>Number of pod replicas (default: <code>1</code>)</td>
    </tr>
  </tbody>
</table>

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

<table aria-label="Create a Route table">
  <thead>
    <tr>
      <th scope="col">Field</th>
      <th scope="col">Description</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <th scope="row"><code>uri</code></th>
      <td>The URL pattern to match. Use a wildcard suffix (e.g., <code>/api/v1/my-service*</code>).</td>
    </tr>
    <tr>
      <th scope="row"><code>upstream.service_name</code></th>
      <td>The Eureka-registered service name (uppercase by default for Spring Boot).</td>
    </tr>
    <tr>
      <th scope="row"><code>upstream.discovery_type</code></th>
      <td>Set to <code>eureka</code> so APISIX resolves service instances from the Eureka registry.</td>
    </tr>
    <tr>
      <th scope="row"><code>plugins.opentelemetry</code></th>
      <td>Enables distributed tracing through the gateway.</td>
    </tr>
    <tr>
      <th scope="row"><code>plugins.prometheus</code></th>
      <td>Enables Prometheus metrics collection for the route.</td>
    </tr>
  </tbody>
</table>

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

<table aria-label="Summary table">
  <thead>
    <tr>
      <th scope="col">Step</th>
      <th scope="col">What</th>
      <th scope="col">How</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <th scope="row">1</th>
      <td>Create container repositories</td>
      <td>OCI CLI or registry UI</td>
    </tr>
    <tr>
      <th scope="row">2</th>
      <td>Build and push images</td>
      <td>Maven + JKube (<code>k8s:build</code> + <code>k8s:push</code>)</td>
    </tr>
    <tr>
      <th scope="row">3</th>
      <td>Create database secrets</td>
      <td><code>kubectl create secret</code></td>
    </tr>
    <tr>
      <th scope="row">4</th>
      <td>Deploy with Helm</td>
      <td><code>helm upgrade --install</code> with <code>obaas-sample-app</code> chart</td>
    </tr>
    <tr>
      <th scope="row">5</th>
      <td>Create API gateway routes</td>
      <td>APISIX Admin API via <code>curl</code></td>
    </tr>
  </tbody>
</table>

After all steps are complete, your application is accessible through the APISIX gateway at the URI patterns you configured.
