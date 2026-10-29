---
title: SigNoz SQLStore
sidebar_position: 6.3
---

SigNoz uses a SQL store for metadata such as organizations, users, dashboards,
alerts and configuration, separate from the Clickhouse telemetry store. SQLite is the default for quick setups. PostgreSQL is the recommended alternative metadata store; see [SigNoz relational database configuration](https://signoz.io/docs/manage/administrator-guide/configuration/relational-database/).

## Bundled PostgreSQL example

The [values-signoz-postgres.yaml example](https://github.com/oracle/microservices-datadriven/blob/main/helm/infra-charts/obaas/examples/values-signoz-postgres.yaml)
enables **SigNoz's bundled PostgreSQL subchart**. It deploys a single PostgreSQL
instance inside Kubernetes with a persistent volume. The parent SigNoz chart
configures the SQLStore provider, connection string and credential environment
from those values.

Layer the example after your normal OBaaS values and optional
[SigNoz sizing profile](https://oracle.github.io/microservices-backend/obaas/docs/observability/signoz-profiles).
Follow its instructions to create the password Secret and select a suitable
StorageClass. PostgreSQL resources and storage are configured separately from
the sizing profiles.

Use this example for evaluation or deployments where you operate PostgreSQL
yourself. The bundled chart does not configure replication, automatic failover
or backups. Increasing its replica count does not establish a replicated
PostgreSQL service.

## Managed PostgreSQL

For production, it is recommended to **use a managed PostgreSQL service** or similarly configured PostgreSQL server with appropriate availability,
backup, point-in-time recovery and maintenance settings. This follows
[SigNoz's resource-planning recommendation](https://signoz.io/docs/setup/capacity-planning/community/resources-planning/)
and reduces the database operations you must manage inside the OBaaS cluster.

For an external managed database, leave the bundled PostgreSQL chart disabled
and configure SQLStore on the SigNoz server. For example:

```yaml
signoz:
  postgresql:
    enabled: false
  signoz:
    env:
      SIGNOZ_SQLSTORE_PROVIDER: postgres
      SIGNOZ_SQLSTORE_POSTGRES_DSN:
        valueFrom:
          secretKeyRef:
            name: signoz-sqlstore
            key: dsn
```

Create `signoz-sqlstore` in the release namespace with a `dsn` key containing
the complete PostgreSQL connection URI. Keep credentials in a Secret, encode
URI credentials correctly, and apply the provider's TLS and CA requirements.
The database must already exist, the SigNoz pods must be able to reach it, and
the database user needs permission to create and migrate SigNoz's metadata
tables. Size and monitor the database for metadata volume and query load.

## Existing installations

Switching SQLStore providers does not copy existing SQLite metadata into
PostgreSQL. Back up the current metadata store and validate a migration and
restore procedure before changing providers. Confirm users, dashboards, alerts
and other configuration after migration, and test recovery independently of
ClickHouse backups. A Helm rollback alone does not reverse database migrations.
