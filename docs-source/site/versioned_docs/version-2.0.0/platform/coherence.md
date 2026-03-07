---
title: Coherence Operator
sidebar_position: 3
---
## Coherence Operator

The Oracle Coherence Operator is an open-source Kubernetes operator that enables the deployment and management of Oracle Coherence clusters in Kubernetes environments. It provides features to assist with deploying, scaling, and managing Coherence data grid clusters using cloud-native technologies. [Full Documentation can be found here](https://oracle.github.io/coherence-operator/)

### Installing the Coherence Operator

The Coherence Operator will be installed if `coherence.enabled` is set to `true` in the `values.yaml` file. The default namespace for the Coherence Operator is `coherence`.

### Creating a Coherence Cluster

Follow these steps to create a basic Coherence cluster named `mysample-cluster`:

#### Prerequisites

- Coherence Operator is installed and running
- `kubectl` is configured to access your Kubernetes cluster
- You have a namespace where you want to deploy the cluster (e.g., `coherence`)

##### Step 1: Create the Coherence Cluster YAML

Create a file named `mysample-cluster.yaml` with the basic cluster configuration

##### YAML Configuration Files

**Basic Cluster Configuration** (`mysample-cluster.yaml`):

```yaml
apiVersion: coherence.oracle.com/v1
kind: Coherence
metadata:
  name: mysample-cluster
spec:
  replicas: 3
  image: ghcr.io/oracle/coherence-ce:22.06.7
  coherence:
    cacheConfig: coherence-cache-config.xml
  jvm:
    memory:
      heapSize: 2g
  ports:
    - name: http
      port: 8080
```

**Cluster with Persistence** (`mysample-cluster-persistent.yaml`):

```yaml
apiVersion: coherence.oracle.com/v1
kind: Coherence
metadata:
  name: mysample-cluster
spec:
  replicas: 3
  image: ghcr.io/oracle/coherence-ce:22.06.7
  coherence:
    cacheConfig: coherence-cache-config.xml
    persistence:
      mode: active
      persistentVolumeClaim:
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 10Gi
  jvm:
    memory:
      heapSize: 2g
  ports:
    - name: http
      port: 8080
    - name: metrics
      port: 9612
  env:
    - name: OTEL_EXPORTER_OTLP_ENDPOINT
      value: "http://otel-collector:4317"
    - name: OTEL_SERVICE_NAME
      value: "mysample-cluster"
    - name: OTEL_METRICS_EXPORTER
      value: "otlp"
    - name: OTEL_TRACES_EXPORTER
      value: "otlp"
```

**Notes:**

- The `replicas` field determines the number of pods in the cluster (default: 3)
- The `image` field specifies the Coherence container image to use
- For persistence, ensure your Kubernetes cluster has a default StorageClass configured, or specify one using `storageClassName`
- The `env` section configures OpenTelemetry (OTEL) for metrics and traces export to an OTEL collector
- The `metrics` port (9612) exposes Coherence metrics for collection

##### Step 2: Deploy the Cluster

Apply the YAML configuration to create the cluster:

```bash
kubectl apply -f mysample-cluster.yaml -n coherence
```

##### Step 3: Verify the Deployment

Check that the cluster pods are running:

```bash
# Check the Coherence resource
kubectl get coherence -n coherence

# Check the pods
kubectl get pods -n coherence

# View cluster details
kubectl describe coherence mysample-cluster -n coherence
```

Wait for all pods to reach the `Running` state. You can watch the progress with:

```bash
kubectl get pods -n coherence -w
```

### Using Coherence with Spring Boot

To connect your Spring Boot application to the `mysample-cluster` Coherence cluster deployed above, you need to add the following dependencies and configuration. [Coherence Spring Documentation](https://spring.coherence.community/4.3.0/index.html#/about/01_overview)

#### Dependencies

**Maven** (`pom.xml`):

```xml
<dependencies>
    <!-- Coherence Spring Boot Starter -->
    <dependency>
        <groupId>com.oracle.coherence.spring</groupId>
        <artifactId>coherence-spring-boot-starter</artifactId>
    </dependency>

    <!-- Coherence CE -->
    <dependency>
        <groupId>com.oracle.coherence.ce</groupId>
        <artifactId>coherence</artifactId>
    </dependency>
</dependencies>
```

#### Spring Boot Configuration

Create or update your `application.yaml` file to connect to the `mysample-cluster`:

```yaml
coherence:
  # Set the instance type to 'client' to connect to an existing cluster
  instance:
    type: client

  # Configure the cluster connection
  cluster:
    name: mysample-cluster

  # Configure sessions
  sessions:
    - name: default
      config: coherence-cache-config.xml
      priority: 1

  # Logging configuration (optional)
  logging:
    destination: slf4j
    logger-name: Coherence

  # Server startup timeout (optional)
  server:
    startup-timeout: 60s
```
