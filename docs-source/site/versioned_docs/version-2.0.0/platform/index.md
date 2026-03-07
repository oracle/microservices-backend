---
title: Platform Services Overview
sidebar_position: 0
---

## Platform Services

Oracle Backend for Microservices and AI includes a set of pre-integrated platform services that handle common infrastructure concerns — API routing, service discovery, messaging, distributed transactions, secrets management, and more. These services are deployed and managed via Helm and can be enabled or disabled individually in your `values.yaml`.

### API Gateway & Networking

| Service | Description |
|---------|-------------|
| [Apache APISIX](./apacheapisix.md) | Cloud-native API gateway for routing, traffic management, and rate limiting |
| [Spring Boot Eureka Server](./eureka.md) | Service registry for automatic discovery between microservices |

### Messaging & Event Streaming

| Service | Description |
|---------|-------------|
| [Strimzi Kafka Operator](./strimzi_operator.md) | Kubernetes operator for deploying and managing Apache Kafka clusters |

### Data & Transactions

| Service | Description |
|---------|-------------|
| [Oracle Transaction Manager for Microservices](./otmm.md) | Distributed transaction coordinator supporting XA, LRA, and TCC consistency models |
| [Oracle Database Operator](./dboperator.md) | Kubernetes operator for provisioning and managing Oracle Database instances |
| [Coherence Operator](./coherence.md) | In-memory data grid for caching, data distribution, and compute |

### Operations & Security

| Service | Description |
|---------|-------------|
| [Oracle Database Metrics Exporter](./dbexporter.md) | Exposes Oracle Database metrics for monitoring and alerting |
| [External Secrets Operator](./esooperator.md) | Syncs secrets from external stores (OCI Vault, AWS, HashiCorp Vault) into Kubernetes |
| [Spring Boot Admin Server](./sbadminserver.md) | Web dashboard for monitoring and managing Spring Boot applications |
| [Conductor Workflow Orchestration](./conductor.md) | Workflow orchestration engine for multi-step service choreography |
