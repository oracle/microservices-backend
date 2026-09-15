---
title: Coherence Operator
sidebar_position: 3
---

The Oracle Coherence Operator is an open-source Kubernetes operator that enables the deployment and management of Oracle Coherence clusters in Kubernetes environments. It provides features to assist with deploying, scaling, and managing Coherence data grid clusters using cloud-native technologies. [Full Documentation can be found here](https://oracle.github.io/coherence-operator/)

:::note
 Note that the Coherence Operator is deprecated in this release of OBaaS and may be removed in a future release.
:::

## Installing the Coherence Operator

The cluster-wide Coherence Operator is installed by the `obaas-prereqs` chart. Install that chart once per cluster and keep `coherence-operator.enabled` set to `true` (the default). The operator runs in the namespace used for the `obaas-prereqs` release and must watch the namespace where an OBaaS release creates a Coherence cluster.

```yaml
# obaas-prereqs values
coherence-operator:
  enabled: true
```

Before installing an OBaaS release with Coherence enabled, verify that the operator is ready and the Coherence custom resource definition is established:

```bash
kubectl rollout status deployment/coherence-operator -n <platform-system-namespace> --timeout=5m
kubectl wait --for=condition=Established crd/coherence.coherence.oracle.com --timeout=5m
```

## Creating a Coherence Cluster

### Helm-managed cluster (recommended)

Enable Coherence in the namespace-scoped `obaas` chart. The provided `values-coherence.yaml` example creates a three-member, ephemeral cluster named `mysample-cluster`, with a 512 MiB JVM heap and an HTTP port on 8080. Set `coherence.name` to a DNS-compatible name unique within the release namespace. The cluster uses the default Coherence image configured by the installed operator unless you override `coherence.image`.

```bash
helm upgrade --install <app-release> obaas/obaas \
  -f examples/values-coherence.yaml \
  -n <application-namespace> \
  --create-namespace
```

Helm creates the `Coherence` custom resource using `coherence.name` in the OBaaS release namespace. Verify `<coherence-cluster-name>` and wait for all three members:

```bash
kubectl get coherence <coherence-cluster-name> -n <application-namespace>
kubectl wait -n <application-namespace> \
  --for=jsonpath='{.status.readyReplicas}'=3 \
  coherence/<coherence-cluster-name> \
  --timeout=5m
kubectl get pods -n <application-namespace>
```

The Coherence Operator creates and manages an internal health port on `6676` for the cluster members. It configures the Kubernetes liveness probe as `GET /healthz` and the readiness probe as `GET /ready`. This port is intentionally not added to `coherence.ports` or exposed through the application Service.

To create durable Coherence data, layer an override with persistence settings after `values-coherence.yaml`. Choose a StorageClass and size appropriate to the cluster:

```yaml
coherence:
  coherence:
    persistence:
      mode: active
      persistentVolumeClaim:
        storageClassName: <storage-class>
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 10Gi
```

The Coherence custom resource is owned by the OBaaS Helm release. Do not create a second resource with the same name outside Helm.

### Manually managed cluster (advanced)

For a Coherence cluster that is intentionally independent of an OBaaS Helm release, create its custom resource directly after installing and verifying the operator. Use a namespace of your choice and manage its lifecycle separately from Helm.

```yaml
apiVersion: coherence.oracle.com/v1
kind: Coherence
metadata:
  name: mysample-cluster
spec:
  replicas: 3
  jvm:
    memory:
      heapSize: 512m
  ports:
    - name: http
      port: 8080
```

```bash
kubectl apply -f mysample-cluster.yaml -n coherence
kubectl describe coherence mysample-cluster -n coherence
kubectl get pods -n coherence
```

## Using Coherence with Spring Boot

To connect your Spring Boot application to a Coherence cluster, add the following dependencies and configuration. Set the client cluster name to the value configured in `coherence.name`; the Helm example uses `mysample-cluster`. [Coherence Spring Documentation](https://spring.coherence.community/4.3.0/index.html#/about/01_overview)

### Dependencies

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

### Spring Boot Configuration

Create or update your `application.yaml` file to connect to the Helm-managed cluster. Replace `mysample-cluster` with your chosen cluster name:

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
