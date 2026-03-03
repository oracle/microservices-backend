---
title: Strimzi Kafka Operator
sidebar_position: 2
---
## Strimzi Kafka Operator

[Strimzi](https://strimzi.io/) is an open-source operator that simplifies running Apache Kafka on Kubernetes. It extends Kubernetes with Custom Resources (CRDs) to declaratively manage Kafka clusters, topics, and users. [Full documentation can be found here](https://strimzi.io/docs/operators/latest/overview)

Oracle Backend for Microservices and AI deploys the operator as a cluster-scoped component via the `obaas-prereqs` Helm chart. Once installed, you can create Kafka clusters in any namespace by applying Strimzi custom resources.

### Installing the Strimzi Kafka Operator

The Strimzi Kafka Operator is installed if `strimzi.enabled` is set to `true` in the `values.yaml` file. The operator is deployed cluster-wide and manages Kafka custom resources across all namespaces.

### Creating a Kafka Cluster

Follow these steps to create a single-node Kafka cluster named `my-cluster` in a given namespace.

#### Prerequisites

- Strimzi Kafka Operator is installed and running
- `kubectl` is configured to access your Kubernetes cluster
- A namespace where you want to deploy the cluster (examples below use `my-namespace`)

#### Step 1: Create the Kafka Cluster YAML

Create a file named `kafka-cluster.yaml`. This defines a single-node KRaft-based cluster suitable for development and testing:

```yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaNodePool
metadata:
  name: dual-role
  labels:
    strimzi.io/cluster: my-cluster
spec:
  replicas: 1
  roles:
    - controller
    - broker
  storage:
    type: jbod
    volumes:
      - id: 0
        type: persistent-claim
        size: 100Gi
        deleteClaim: false
        kraftMetadata: shared
---
apiVersion: kafka.strimzi.io/v1beta2
kind: Kafka
metadata:
  name: my-cluster
  annotations:
    strimzi.io/node-pools: enabled
    strimzi.io/kraft: enabled
spec:
  kafka:
    version: 3.9.0
    metadataVersion: 3.9-IV0
    listeners:
      - name: plain
        port: 9092
        type: internal
        tls: false
      - name: tls
        port: 9093
        type: internal
        tls: true
    config:
      offsets.topic.replication.factor: 1
      transaction.state.log.replication.factor: 1
      transaction.state.log.min.isr: 1
      default.replication.factor: 1
      min.insync.replicas: 1
  entityOperator:
    topicOperator: {}
    userOperator: {}
```

**Notes:**

- This uses **KRaft mode** (Kafka Raft) — no ZooKeeper required
- The `dual-role` node pool runs both controller and broker roles on a single node
- Replication factors are set to 1 for single-node operation — for production, increase `replicas` and replication factors to 3+
- Two listeners are configured: `plain` (port 9092, no TLS) and `tls` (port 9093, encrypted)
- The `entityOperator` enables the Topic Operator and User Operator for declarative topic and user management

#### Step 2: Deploy the Cluster

Apply the YAML to your namespace:

```bash
kubectl apply -f kafka-cluster.yaml -n my-namespace
```

Wait for the cluster to be ready:

```bash
kubectl wait kafka/my-cluster --for=condition=Ready --timeout=300s -n my-namespace
```

#### Step 3: Verify the Deployment

```bash
# Check the Kafka resource status
kubectl get kafka -n my-namespace

# Check that pods are running
kubectl get pods -n my-namespace

# View cluster details
kubectl describe kafka my-cluster -n my-namespace
```

### Creating a Kafka Topic

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

### Testing with a Producer and Consumer

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

### Strimzi Custom Resources Reference

| Resource | Purpose |
|----------|---------|
| `Kafka` | Defines the Kafka cluster configuration |
| `KafkaNodePool` | Manages groups of Kafka nodes with specific roles |
| `KafkaTopic` | Declaratively manages Kafka topics |
| `KafkaUser` | Manages user authentication and authorization |
| `KafkaConnect` | Deploys Kafka Connect for data integration |
| `KafkaBridge` | Provides HTTP API access to Kafka |

For the full custom resource reference, see the [Strimzi documentation](https://strimzi.io/docs/operators/latest/configuring).
