---
title: Observability Overview
sidebar_position: 0
---

## Observability

Oracle Backend for Microservices and AI ships with a fully integrated observability stack powered by [SigNoz](https://signoz.io/), providing metrics, logs, and distributed traces out of the box. Applications deployed to the platform automatically export telemetry data via OpenTelemetry — no additional infrastructure setup required.

### What's Included

- **Metrics** — Application and infrastructure metrics collected via OpenTelemetry and Micrometer, with 20+ pre-installed dashboards
- **Logs** — Centralized log aggregation with filtering and search
- **Traces** — Distributed tracing across microservices with request correlation
- **Database Monitoring** — Oracle Database metrics via the built-in database exporter

### Guides

| Guide | Description |
|-------|-------------|
| [Introduction and Overview](./overview.md) | Architecture and how the observability stack fits together |
| [Access SigNoz](./access.md) | Retrieve credentials and connect to the SigNoz UI |
| [Metrics, Logs and Traces](./metricslogstraces.md) | Navigate metrics, logs, and traces in the SigNoz dashboard |
| [Pre-installed Dashboards](./dashboards.md) | Catalog of 20+ ready-to-use dashboards (Spring Boot, Kafka, Kubernetes, Oracle DB, and more) |
| [Configure Applications for SigNoz](./configure.md) | Add OpenTelemetry and Micrometer dependencies to your application |
| [Oracle Database Metrics Exporter](./dbexporter.md) | Database-level metrics collection and Grafana integration |
