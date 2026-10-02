---
title: Oracle Transaction Manager for Microservices
sidebar_position: 10
---

[Oracle Transaction Manager for Microservices](https://docs.oracle.com/en/database/oracle/transaction-manager-for-microservices/26.1/index.html), also known as "MicroTx", simplifies application development and operations by enabling distributed transactions to ensure consistency across microservices deployed in Kubernetes.

Oracle Backend for Microservices and AI includes the free version of MicroTx, which has all of the functionality of the commercial version, but limits the number of transactions and only persists data in memory. It is recommended for evaluations and application development purposes.

MicroTx supports the following consistency models:

- Extended Architecture (XA)
- Long Running Actions (LRA)
- Try-Confirm/Cancel (TCC)

## Use Oracle Transaction Manager for Microservices with Spring Boot

To use MicroTx in your Spring Boot applications, include the following dependency in your `pom.xml` or equivalent:

```xml
<dependency>
    <groupId>com.oracle.microtx.lra</groupId>
    <artifactId>microtx-lra-spring-boot-starter-3x</artifactId>
</dependency>
```

Add the following configuration to your Spring application configuration. The variables in this configuration are automatically injected into your deployment and pods when you deploy applications to Oracle Backend for Microservices and AI using the OBaaS deployment Helm chart.

```yaml
spring:
  microtx:
    lra:
      coordinator-url: ${MP_LRA_COORDINATOR_URL}
      propagation-active: true
      headers-propagation-prefix: "{x-b3-, oracle-tmm-, authorization, refresh-}"

lra:
  coordinator:
    url: ${MP_LRA_COORDINATOR_URL}
```

## Components and enablement

The MicroTx installation is made up of three components, each of which can be enabled or disabled independently in the Helm values:

- `otmm.coordinator` — the transaction coordinator (XA/LRA/TCC).
- `otmm.workflowServer` — the [workflow server](#microtx-workflow-server) (see below).
- `otmm.console` — the web console used to monitor transactions and workflows.

All three are enabled by default. To disable a component, set its `enabled` flag to `false`:

```yaml
otmm:
  coordinator:
    enabled: true
  workflowServer:
    enabled: true
  console:
    enabled: false
```

The console exists only to front the coordinator and workflow server, so it is deployed only when at least one of those two components is enabled. If both `otmm.coordinator.enabled` and `otmm.workflowServer.enabled` are `false`, the console is not deployed even if `otmm.console.enabled` is `true`. When deployed, the console is connected only to the backends that are enabled, so a coordinator-only or workflow-only install does not leave the console pointing at a service that was not deployed.

## MicroTx Workflow Server

The MicroTx Workflow Server extends transaction coordinator with advanced workflow capabilities.

For MicroTx sizing and deployment guidance, see the official [Oracle Transaction Manager for Microservices 26.1 documentation](https://docs.oracle.com/en/database/oracle/transaction-manager-for-microservices/26.1/index.html). To enable the workflow server in OBaaS, set the `otmm.workflowServer.enabled` property to true in the Helm values:

```yaml
otmm:
  workflowServer:
    enabled: true
```

When the workflow server is enabled, it uses the OBaaS application database secret, typically `<release>-db-authn`, and runs Flyway against that schema during startup. The database init job grants `OBAAS_USER` the schema privileges required for this initialization. If a pre-existing application user is supplied through `database.authN.secretName`, that user must have equivalent schema DDL privileges and quota on its default tablespace.

## Upgrading to the commercial version

If you have licensed Oracle Transaction Manager for Microservices Enterprise Edition, please see the [documentation](https://docs.oracle.com/en/database/oracle/transaction-manager-for-microservices/26.1/index.html) for details of how to install and configure MicroTx. Oracle recommends that you perform a new installation rather than attempting to upgrade the provided MicroTx Free installation to the commercial version.
