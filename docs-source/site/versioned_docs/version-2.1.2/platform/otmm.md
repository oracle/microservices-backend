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

## Coordinator database storage

The coordinator defaults to `otmm.coordinator.storage.type: memory`. To persist
transaction state across coordinator restarts, use `db` with a MicroTx Enterprise
Edition image. The Free coordinator image does not support database storage.
Database storage does not require a coordinator PVC and does not migrate
transactions previously held in memory.

Before installing, prepare a reachable Oracle Database and grant the storage user
MicroTx's [required privileges and tablespace quota](https://docs.oracle.com/en/database/oracle/transaction-manager-for-microservices/26.1/tmmdg/grant-privileges-create-and-run-stored-procedures.html).
Follow the [database setup prerequisites](https://docs.oracle.com/en/database/oracle/transaction-manager-for-microservices/26.1/tmmdg/create-data-store.html),
including separate schemas for the coordinator and workflow server when both use
Oracle Database. Accept the applicable Enterprise Edition image terms and provide
an image pull secret if required by Oracle Container Registry.

### Reuse the OBaaS database credentials

For a coordinator-only installation, layer these overrides after your normal
OBaaS values:

```yaml
otmm:
  coordinator:
    image:
      repository: container-registry.oracle.com/database/microtx-ee-coordinator
      tag: "26.1.2"
    storage:
      type: db
      db:
        credentialSecretName: ""
  workflowServer:
    enabled: false
```

With `credentialSecretName` empty, the coordinator uses the same application
credential secret as the database metrics exporter. This includes custom secret
names and keys configured through `database.authN`. The application secret's
service key supplies the connection string; optionally override it with
`otmm.coordinator.storage.db.connectionString`.

The chart also reuses the exporter's database wallet and mounts it at
`/etc/config/dbwallet`. It overlays `sqlnet.ora` to point to that directory without
changing the shared Secret. No separate JSON credential Secret is needed: the
chart serializes the application username and password at startup. Custom
coordinator images using this path must provide Python 3 and `/app/tcs`.

### Use a separate coordinator schema

When the workflow server is enabled, keep its OBaaS application schema separate
from the coordinator's transaction-store schema. Create a Secret in the OBaaS
application namespace for the coordinator user. Its `secret` key must contain JSON
in this format:

```json
{"username":"<coordinator-user>","password":"<coordinator-password>"}
```

Create it from a protected local file rather than placing credentials in a
committed values file:

```bash
kubectl -n <application-namespace> create secret generic microtx-coordinator-db \
  --from-file=secret=<credential-json-file>
```

Keep the Enterprise Edition image override above and configure:

```yaml
otmm:
  coordinator:
    storage:
      type: db
      db:
        credentialSecretName: microtx-coordinator-db
        credentialSecretKey: secret
        connectionString: "<coordinator-connect-string>"
        # Set one of these when the connection requires a wallet:
        # walletSecretName: "<coordinator-wallet-secret>"
        # walletConfigMapName: "<coordinator-wallet-configmap>"
```

A separate credential Secret requires an explicit connection string. It does not
implicitly select the shared OBaaS wallet: supply `walletSecretName` or
`walletConfigMapName` when needed, in the application namespace. The wallet is
mounted at `/etc/config/dbwallet`; its `sqlnet.ora` must use that wallet directory.
The chart does not rewrite custom wallet configuration.

### Schema initialization and verification

For database storage, `otmm.coordinator.storage.db.initializeSchema` defaults to
`true`. The `initialize-coordinator-schema` init container runs the selected image
in MicroTx initialization mode with the same credentials and wallet as the
service. The coordinator starts only after initialization succeeds. This step can
create or upgrade database objects; review MicroTx's migration requirements and
back up an existing transaction store before upgrading its image.

If a DBA provisions and upgrades the schema separately, set
`otmm.coordinator.storage.db.initializeSchema: false`.

After the Helm installation or upgrade, check both containers:

```bash
kubectl -n <application-namespace> logs <app-release>-otmm-tcs-0 \
  -c initialize-coordinator-schema
kubectl -n <application-namespace> logs <app-release>-otmm-tcs-0 -c otmm-tcs
```

Initialization should complete successfully and the coordinator should report
`serving...`. If startup reports `ORA-00942` for `OMTM_STATS`, check schema
initialization and the storage user's privileges. For `ORA-28759`, check that the
wallet files are readable and `sqlnet.ora` points to their mounted directory.

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

If you have licensed Oracle Transaction Manager for Microservices Enterprise Edition (EE), upgrade the MicroTx components as follows:

- **Transaction Coordinator:** Replace the Free container image with the EE container image from [Oracle Container Registry](https://container-registry.oracle.com/ords/ocr/ba/database/microtx-ee-coordinator). You must also configure persistence when upgrading to EE. Follow the [Set Up Oracle Database as Data Store](https://docs.oracle.com/en/database/oracle/transaction-manager-for-microservices/26.1/tmmdg/create-data-store.html) instructions.
- **Workflow Server:** Replace the Free container image with the EE container image from [Oracle Container Registry](https://container-registry.oracle.com/ords/ocr/ba/database/microtx-ee-workflow).
- **Console:** Replace the Free container image with the EE container image from [Oracle Container Registry](https://container-registry.oracle.com/ords/ocr/ba/database/microtx-ee-console).
