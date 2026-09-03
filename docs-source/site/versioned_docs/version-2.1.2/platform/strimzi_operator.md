---
title: Strimzi Kafka Operator
sidebar_position: 2
---

[Strimzi](https://strimzi.io/) is an open-source operator that simplifies running Apache Kafka on Kubernetes. It extends Kubernetes with Custom Resources (CRDs) to declaratively manage Kafka clusters, topics, and users. [Full documentation can be found here](https://strimzi.io/docs/operators/latest/overview)

Oracle Backend for Microservices and AI deploys the operator as a cluster-scoped component via the `obaas-prereqs` Helm chart. Once installed, you can create Kafka clusters in any namespace by applying Strimzi custom resources.

## Installing the Strimzi Kafka Operator

The Strimzi Kafka Operator is installed if `strimzi.enabled` is set to `true` in the `values.yaml` file. The operator is deployed cluster-wide and manages Kafka custom resources across all namespaces.

### Creating a Kafka Cluster

Follow these steps to create a single-node Kafka cluster named `my-cluster` in a given namespace.

### Prerequisites

- Strimzi Kafka Operator is installed and running
- `kubectl` is configured to access your Kubernetes cluster
- A namespace where you want to deploy the cluster (examples below use `my-namespace`)

### Step 1: Create the Kafka Cluster YAML

Create a file named `kafka-cluster.yaml`. This defines a single-node KRaft-based cluster suitable for development and testing:

```yaml
apiVersion: kafka.strimzi.io/v1
kind: Kafka
metadata:
  name: basic-kafka
spec:
  kafka:
    version: 4.2.0
    metadataVersion: "4.2"
    listeners:
      - name: plain
        port: 9092
        type: internal
        tls: false
    config:
      offsets.topic.replication.factor: 3
      transaction.state.log.replication.factor: 3
      transaction.state.log.min.isr: 2
      default.replication.factor: 3
      min.insync.replicas: 2
  entityOperator:
    topicOperator: {}
    userOperator: {}
---
apiVersion: kafka.strimzi.io/v1
kind: KafkaNodePool
metadata:
  name: pool-a
  labels:
    strimzi.io/cluster: basic-kafka
spec:
  replicas: 3
  roles:
    - controller
    - broker
  storage:
    type: ephemeral
```

**Notes:**

- This uses **KRaft mode** (Kafka Raft) — no ZooKeeper required
- The `dual-role` node pool runs both controller and broker roles on a single node
- Replication factors are set to 1 for single-node operation — for production, increase `replicas` and replication factors to 3+
- Two listeners are configured: `plain` (port 9092, no TLS) and `tls` (port 9093, encrypted)
- The `entityOperator` enables the Topic Operator and User Operator for declarative topic and user management
- `KafkaNodePool` names are scoped to the **namespace**, not to the cluster — if you run multiple Kafka clusters in the same namespace, each node pool must have a unique name (e.g. `cluster-a-pool`, `cluster-b-pool`)

### Step 2: Deploy the Cluster

Apply the YAML to your namespace:

```bash
kubectl apply -f kafka-cluster.yaml -n my-namespace
```

Wait for the cluster to be ready:

```bash
kubectl wait kafka/my-cluster --for=condition=Ready --timeout=300s -n my-namespace
```

### Step 3: Verify the Deployment

```bash
# Check the Kafka resource status
kubectl get kafka -n my-namespace

# Check that pods are running
kubectl get pods -n my-namespace

# View cluster details
kubectl describe kafka my-cluster -n my-namespace
```

## Creating a Kafka Topic

Once your cluster is running, create topics declaratively using the `KafkaTopic` resource.

Create a file named `my-topic.yaml`:

```yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaTopic
metadata:
  name: my-topic
  labels:
    strimzi.io/cluster: my-cluster
spec:
  partitions: 1
  replicas: 1
  config:
    retention.ms: 7200000
    segment.bytes: 1073741824
```

Apply it:

```bash
kubectl apply -f my-topic.yaml -n my-namespace
```

Verify the topic was created:

```bash
kubectl get kafkatopic -n my-namespace
```

## Testing with a Producer and Consumer

You can quickly test your cluster using the Kafka console tools:

**Start a producer** (type messages and press Enter to send):

```bash
kubectl -n my-namespace run kafka-producer -ti \
  --image=quay.io/strimzi/kafka:0.45.0-kafka-3.9.0 \
  --rm=true --restart=Never -- \
  bin/kafka-console-producer.sh \
    --bootstrap-server my-cluster-kafka-bootstrap:9092 \
    --topic my-topic
```

**Start a consumer** (in a separate terminal):

```bash
kubectl -n my-namespace run kafka-consumer -ti \
  --image=quay.io/strimzi/kafka:0.45.0-kafka-3.9.0 \
  --rm=true --restart=Never -- \
  bin/kafka-console-consumer.sh \
    --bootstrap-server my-cluster-kafka-bootstrap:9092 \
    --topic my-topic \
    --from-beginning
```

## Configuring TLS

To configure a Kafka cluster with TLS, add a new listener with `tls=true` in the `Kafka` custom resource. By default, the Kafka cluster will sign certificates using the Strimzi cluster CA.

```yaml
listeners:
  - name: tls
    port: 9093
    type: internal
    tls: true
```

Strimzi will create the following secrets in the cluster namespace, prefixed by the cluster name: `clients-ca`, `clients-ca-cert`, `cluster-ca`, and `cluster-ca-cert`.

### Trusting the cluster CA cert from internal clients

Clients running in the Kubernetes cluster should mount the cluster CA cert to their client pod:

```yaml
volumes:
  - name: cluster-ca
    secret:
      secretName: my-cluster-cluster-ca-cert

containers:
  - name: my-java-client
    image: my-java-client:latest
    volumeMounts:
      - name: cluster-ca
        mountPath: /etc/kafka/cluster-ca
        readOnly: true
```

Then, configure the Kafka client to use TLS. The truststore password is stored in the `cluster-ca-cert` secret under the `ca.password` key:

```properties
bootstrap.servers=my-cluster-kafka-bootstrap:9093
security.protocol=SSL

ssl.truststore.location=/etc/kafka/cluster-ca/ca.p12
ssl.truststore.password=<truststore-password>
ssl.truststore.type=PKCS12
```

This must be configured in the relevant Kafka clients settings.

### Configuring SASL_SSL with SCRAM

SASL_SSL with SCRAM is configurable through the Kafka custom resource listeners. First, add a new SCRAM listener with TLS enabled:

```yaml
listeners:
  - name: scram
    port: 9094
    type: internal
    tls: true
    authentication:
      type: scram-sha-512
```

Create a KafkaUser for your cluster using SCRAM authentication:

```yaml
apiVersion: kafka.strimzi.io/v1
kind: KafkaUser
metadata:
  name: my-cluster-kafka-scram-user   # name also becomes the Secret name
  labels:
    strimzi.io/cluster: my-cluster
spec:
  authentication:
    type: scram-sha-512
```

Strimzi creates a Secret with the same name as the KafkaUser (`my-cluster-kafka-scram-user`), containing the password and JAAS config. Clients running in the Kubernetes cluster should mount the cluster CA cert and scram user secrets:

```yaml
volumes:
  - name: cluster-ca
    secret:
      secretName: my-cluster-cluster-ca-cert
  - name: scram-user
    secret:
      secretName: my-cluster-kafka-scram-user
containers:
  - name: my-java-client
    image: my-java-client:latest
    volumeMounts:
      - name: cluster-ca
        mountPath: /etc/kafka/cluster-ca
        readOnly: true
      - name: scram-user
        mountPath: /etc/kafka/scram-user
        readOnly: true
```

Then, configure the client to use SASL_SSL with SCRAM-SHA-512:

```properties
security.protocol=SASL_SSL
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=<value of sasl.jaas.config key in the my-cluster-kafka-scram-user Secret>
ssl.truststore.location=/etc/kafka/cluster-ca/ca.p12
ssl.truststore.password=<truststore password>
ssl.truststore.type=PKCS12
```

Strimzi also supports mTLS and custom CA certificates. For additional Strimzi certificate documentation, see the [Strimzi security reference](https://github.com/IBM/strimzi-kafka-operator/tree/main/documentation/modules/security).

## Strimzi Custom Resources Reference

| Resource | Purpose |
|----------|---------|
| `Kafka` | Defines the Kafka cluster configuration |
| `KafkaNodePool` | Manages groups of Kafka nodes with specific roles |
| `KafkaTopic` | Declaratively manages Kafka topics |
| `KafkaUser` | Manages user authentication and authorization |
| `KafkaConnect` | Deploys Kafka Connect for data integration |
| `KafkaBridge` | Provides HTTP API access to Kafka |

For the full custom resource reference, see the [Strimzi documentation](https://strimzi.io/docs/operators/latest/configuring).

## Next Steps

- **Kafka Observability**: Learn how to monitor your Strimzi Kafka clusters, producers, and consumers using the [Kafka Observability Guide](../observability/kafka.md).
