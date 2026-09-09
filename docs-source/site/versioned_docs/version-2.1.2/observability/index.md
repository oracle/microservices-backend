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

<table aria-label="Guides table">
  <thead>
    <tr>
      <th scope="col">Guide</th>
      <th scope="col">Description</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <th scope="row"><a href="./overview">Introduction and Overview</a></th>
      <td>Architecture and how the observability stack fits together</td>
    </tr>
    <tr>
      <th scope="row"><a href="./access">Access SigNoz</a></th>
      <td>Retrieve credentials and connect to the SigNoz UI</td>
    </tr>
    <tr>
      <th scope="row"><a href="./metricslogstraces">Metrics, Logs and Traces</a></th>
      <td>Navigate metrics, logs, and traces in the SigNoz dashboard</td>
    </tr>
    <tr>
      <th scope="row"><a href="./dashboards">Pre-installed Dashboards</a></th>
      <td>Catalog of 20+ ready-to-use dashboards (Spring Boot, Kafka, Kubernetes, Oracle DB, and more)</td>
    </tr>
    <tr>
      <th scope="row"><a href="./configure">Configure Applications for SigNoz</a></th>
      <td>Add OpenTelemetry and Micrometer dependencies to your application</td>
    </tr>
    <tr>
      <th scope="row"><a href="./kafka">Kafka Observability</a></th>
      <td>Monitor Kafka clusters, producers, and consumers</td>
    </tr>
    <tr>
      <th scope="row"><a href="./java-instrumentation">Customize Java Instrumentation</a></th>
      <td>Pass custom environment variables to the OpenTelemetry Java agent through Helm values or CLI overrides</td>
    </tr>
    <tr>
      <th scope="row"><a href="./dbexporter">Oracle Database Metrics Exporter</a></th>
      <td>Database-level metrics collection and configuration guidance</td>
    </tr>
    <tr>
      <th scope="row"><a href="./customizations">Common Customizations</a></th>
      <td>Configure Online and Cold Storage</td>
    </tr>
    <tr>
      <th scope="row"><a href="./upgrade/index">Replace SigNoZ during upgrade</a></th>
      <td>Replace SigNoZ during an optional OBaaS 2.1.2 upgrade; existing observability data is permanently deleted</td>
    </tr>
  </tbody>
</table>
