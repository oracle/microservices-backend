---
title: Observability Overview
sidebar_position: 0
---

Oracle Backend for Microservices and AI ships with a fully integrated observability stack powered by [SigNoz](https://signoz.io/), providing metrics, logs, and distributed traces. Platform services are preconfigured for observability. Applications export telemetry after they are instrumented with OpenTelemetry or configured with supported metrics annotations.

### What's Included

- **Metrics** — Application and infrastructure metrics collected via OpenTelemetry and Micrometer, with 20+ pre-installed dashboards
- **Logs** — Centralized log aggregation with filtering and search
- **Traces** — Distributed tracing across microservices with request correlation
- **Database Monitoring** — Oracle Database metrics via the built-in database exporter
- **Kafka Monitoring** — End-to-end visibility for Kafka clusters, producers, and consumers

### Guides

| Guide | Description |
|-------|-------------|
| [Introduction and Overview](./overview.md) | Architecture and how the observability stack fits together |
| [Access SigNoz](./access.md) | Retrieve credentials and connect to the SigNoz UI |
| [Metrics, Logs and Traces](./metricslogstraces.md) | Navigate metrics, logs, and traces in the SigNoz dashboard |
| [Pre-installed Dashboards](./dashboards.md) | Catalog of 20+ ready-to-use dashboards (Spring Boot, Kafka, Kubernetes, Oracle DB, and more) |
| [Configure Applications for SigNoz](./configure.md) | Add OpenTelemetry and Micrometer dependencies to your application |
| [Kafka Observability](./kafka.md) | Monitor Kafka clusters, producers, and consumers |
| [Customize Java Instrumentation](./java-instrumentation) | Pass custom environment variables to the OpenTelemetry Java agent through Helm values or CLI overrides |
| [Oracle Database Metrics Exporter](./dbexporter.md) | Database-level metrics collection and configuration guidance |
| [Common Customizations](./customizations.md) | Configure Online and Cold Storage |
| [Replace SigNoZ during upgrade](./upgrade/index.md) | Replace SigNoZ during an optional OBaaS 2.1.2 upgrade; existing observability data is permanently deleted |
