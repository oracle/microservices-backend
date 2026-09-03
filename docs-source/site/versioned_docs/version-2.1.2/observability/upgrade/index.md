---
title: Upgrade SigNoZ
sidebar_position: 9
---

# Upgrade SigNoZ

SigNoZ recommends backing up configuration and persistent data before an
upgrade. Its ClickHouse upgrade guidance explains that ClickHouse updates its
on-disk format in place and that downgrades are not guaranteed. See the official
[SigNoZ ClickHouse 25.12.5 upgrade guide](https://signoz.io/docs/operate/migration/upgrade-0-131/)
and [standard upgrade guide](https://signoz.io/docs/operate/migration/upgrade-standard/).

OBaaS provides separate upgrade paths so that each procedure can be followed
from beginning to end without branching.

## When to use these guides

Use these guides when upgrading an existing OBaaS installation that has SigNoZ
enabled. Fresh installations do not use an upgrade path; install the current
OBaaS chart normally.

## Choose an upgrade path

| Existing environment | Recovery requirement | Guide |
|---|---|---|
| OBaaS 2.0.0 or 2.1.x with a SigNoZ version earlier than `0.134.0` | Historical telemetry, dashboards, and users must be recoverable | [Upgrade with protected recovery](./protected-recovery.md) **(recommended)** |
| Any supported SigNoZ version earlier than `0.134.0` | Historical data does not require a protected recovery point | [Upgrade without protected recovery](./without-protected-recovery.md) |

If you are unsure which path applies, use the protected recovery guide.

## Behavior by source version

OBaaS 2.0.0 includes SigNoZ `0.102.1`. Its upgrade path crosses the SigNoZ
`0.113.0` migration boundary, where `telemetryStoreMigrator` replaces the
earlier `schemaMigrator` resources.

OBaaS 2.1.0 already includes SigNoZ `0.113.0`, so that migrator replacement has
already occurred. The Stage 2 cleanup is separate from that SigNoZ migration:
it removes obsolete OBaaS OIDC mock resources from air-gapped OBaaS 2.1.0
installations. The cleanup is a no-op when those resources are absent.

## Common requirements

Before selecting a guide:

1. Confirm the Kubernetes context, Helm release name, and application namespace.
2. Confirm that SigNoZ, ClickHouse, and ZooKeeper are healthy.
3. Retain the customer values files and all database, secret, image, storage,
   and private-registry settings used by the existing release.
4. Do not use an older ClickHouse version against a persistent volume whose
   on-disk format has already been upgraded.
