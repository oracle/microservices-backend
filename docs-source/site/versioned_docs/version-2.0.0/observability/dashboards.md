---
title: Pre-installed dashboards
sidebar_position: 4
---
:::note
More details can be found in the [SigNoz Documentation](https://signoz.io/docs/introduction/).
:::

## Pre-installed dashboards

There are several dashboards that are pre-installed in SigNoz, for example:

- [Pre-installed dashboards](#pre-installed-dashboards)
  - [Spring Boot Observability](#spring-boot-observability)
  - [Spring Boot Statistics](#spring-boot-statistics)
  - [Oracle Database Dashboard](#oracle-database-dashboard)
  - [Kube State Metrics Dashboard](#kube-state-metrics-dashboard)
  - [Apache APISIX Dashboard](#apache-apisix-dashboard)
  - [Helidon Main Dashboard](#helidon-main-dashboard)
  - [Helidon MP Details](#helidon-mp-details)
  - [Helidon SE Details](#helidon-se-details)
  - [Helidon JVM Details](#helidon-jvm-details)
  - [APM Metrics](#apm-metrics)
  - [Kafka Server Monitoring Dashboard](#kafka-server-monitoring-dashboard)
  - [Kubernetes Pod Metrics - Overall](#kubernetes-pod-metrics---overall)
  - [Kubernetes Pod Metrics - Detailed](#kubernetes-pod-metrics---detailed)
  - [Kubernetes PVC Metrics](#kubernetes-pvc-metrics)
  - [Kubernetes Node Metrics - Overall](#kubernetes-node-metrics---overall)
  - [Kubernetes Node Metrics - Detailed](#kubernetes-node-metrics---detailed)
  - [DB Calls Monitoring](#db-calls-monitoring)
  - [Host Metrics (k8s)](#host-metrics-k8s)
  - [HTTP API Monitoring](#http-api-monitoring)
  - [JVM Metrics](#jvm-metrics)
  - [NGINX (OTEL)](#nginx-otel)
  - [MicroTx](#microtx)

### Spring Boot Observability

This dashboard provides details of one or more Spring Boot applications including the following:

- The number of HTTP requests received by the application
- A breakdown of which URL paths requests were received for
- The average duration of requests by path
- The number of exceptions encountered by the application
- Details of 2xx (that is, successful) and 5xx (that is, exceptions) requests
- The request rate per second over time, by path
- Log messages from the service

You may adjust the time period and drill down into issues, and search the logs for particular messages. This dashboard is designed for Spring Boot 3.x applications. Some features may work for Spring Boot 2.x applications.

Here is an example of this dashboard displaying data for a simple application:

![Spring Boot Observability Dashboard](images/spring-boot-observability-dashboard.png)

### Spring Boot Statistics

This dashboard provides more in-depth information about services including the following:

- JVM statistics like heap and non-heap memory usage, and details of garbage collection
- Load average and open files
- Database connection pool statistics (for HikariCP)
- HTTP request statistics
- Logging (logback) statistics

You may adjust the time period and drill down into issues, and search the logs for particular messages. This dashboard is designed for Spring Boot 3.x applications. Some features may work for Spring Boot 2.x applications.

Here is an example of this dashboard displaying data for a simple application:

![Spring Boot Stats Dashboard](images/spring-boot-stats-dashboard.png)

### Oracle Database Dashboard

This dashboard provides details about the Oracle Database including:

- SGA and PGA size
- Active sessions
- User commits
- Execute count
- CPU count and platform
- Top SQL
- Wait time statistics by class

Here is an example of this dashboard:

![Oracle Database Dashboard](images/db-dashboard.png)

### Kube State Metrics Dashboard

This dashboard provides details of the Kubernetes cluster including:

- Pod capacity and requests for CPU and memory
- Node availability
- Deployment, Stateful Set, Pod, Job and Container statistics
- Details of horizontal pod autoscalers
- Details of persistent volume claims

Here is an example of this dashboard:

![Kube State Metrics Dashboard](images/kube-state-metrics-dashboard.png)

### Apache APISIX Dashboard

This dashboard provides details of the APISIX API Gateway including:

- Total Requests
- NGINX Connection State
- Etcd modifications

Here is an example of this dashboard:

![Apache APISIX Dashboard](images/apache-apisix-dashboard.png)

In addition, the following dashboards are also pre-installed:

### Helidon Main Dashboard

Combined dashboard for Heap memory usage statistics about all [Helidon SE](https://helidon.io/docs/v3/about/introduction) and [Helidon MP](https://helidon.io/docs/v4/mp/introduction) applications deployed in the cluster.

![Helidon Main Dashboard](images/helidon-main-dashboard.png)

### Helidon MP Details

Details about CPU and Memory usage of [Helidon MP](https://helidon.io/docs/v4/mp/introduction) applications along with statistics about HTTP/REST requests per JVM.

![Helidon MP Dashboard](images/helidon-mp-dashboard.png)

### Helidon SE Details

Details about Memory usage of [Helidon SE](https://helidon.io/docs/v3/about/introduction) applications along with statistics about HTTP/REST requests per JVM.

![Helidon SE Dashboard](images/helidon-se-dashboard.png)

### Helidon JVM Details

JVM level details about Helidon applications, including statistics about [Virtual Threads](https://docs.oracle.com/en/java/javase/24/core/virtual-threads.html), CPU and Memory usage and HTTP requests.

![Helidon JVM Dashboard](images/helidon-jvm-dashboard.png)

### APM Metrics

Application Performance overview for all deployed services in terms of request execution times and consistency.

![APM Dashboard](images/apm-dashboard.png)

### Kafka Server Monitoring Dashboard

Details about Kafka brokers, topics, partitions, and consumers.

![Kafka Dashboard](images/kafka-dashboard.png)

### Kubernetes Pod Metrics - Overall

Aggregated view of CPU, Memory, FileSystem, and Network usage by pods.

![Kubernetes Pod Metrics Overall](images/k8s-pod-metrics-overall.png)

### Kubernetes Pod Metrics - Detailed

Detailed view of CPU, Memory, FileSystem, and Network usage by pods.

![Kubernetes Pod Metrics Detailed](images/k8s-pod-metrics-detailed.png)

### Kubernetes PVC Metrics

Capacity and Usage statistics about Persistent Volume Claims in the cluster.

![Kubernetes PVC Metrics](images/k8s-pvc-metrics.png)

### Kubernetes Node Metrics - Overall

Aggregated view of CPU, Memory, FileSystem, and Network usage by Nodes in the cluster.

![Kubernetes Node Metrics Overall Dashboard](images/k8s-node-metrics-overall.png)

### Kubernetes Node Metrics - Detailed

Detailed view of CPU, Memory, FileSystem, and Network usage by Nodes in the cluster.

![Kubernetes Node Metrics Detailed Dashboard](images/k8s-node-metrics-detailed.png)

### DB Calls Monitoring

Details about [DB attributes from opentelemetry](https://opentelemetry.io/docs/specs/semconv/attributes-registry/db/).

![Host Metrics Dashboard](images/db-calls-dashboard.png)

### Host Metrics (k8s)

This dashboard uses the system metrics collected from the [hostmetrics receiver](https://uptrace.dev/opentelemetry/collector/host-metrics) to show CPU, Memory, Disk, Network and Filesystem usage.

![Host Metrics Dashboard](images/host-metrics-dashboard.png)

### HTTP API Monitoring

This dashboard is built on top of available [HTTP attributes from opentelemetry](https://opentelemetry.io/docs/specs/semconv/attributes-registry/http/) and provides insights about endpoint level performance indicators for HTTP calls.

![HTTP API Dashboard](images/http-api-dashboard.png)

### JVM Metrics

JVM Runtime metrics for all services deployed in the cluster in terms of CPU/Memory usage, Garbage collection events, threads and class loading/unloading.

![JVM Metrics Dashboard](images/jvm-metrics-dashboard.png)

### NGINX (OTEL)

Details about connections/requests being handled by the [NGINX Ingress controller](https://github.com/kubernetes/ingress-nginx).

![Nginx Dashboard](images/nginx-dashboard.png)

### MicroTx

Details about [Transaction Manager for Microservices](https://docs.oracle.com/en/database/oracle/transaction-manager-for-microservices/24.2/tmmdg/oracle-transaction-manager-microservices.html) component and statistics about participating transactions.

![MicroTx Dashboard](images/microtx-dashboard.png)
