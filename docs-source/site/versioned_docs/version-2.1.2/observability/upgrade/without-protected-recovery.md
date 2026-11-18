---
title: Upgrade without protected recovery
sidebar_position: 2
---

# Upgrade without protected recovery

For installations where observability data loss is acceptable, follow the
[two-step ClickHouse and SigNoZ upgrade procedure](../../upgrade/index.mdx#upgrade-signoz-and-clickhouse-in-two-steps).
Upgrade ClickHouse with migration disabled first, verify the running server
version, then upgrade SigNoZ and the collector with migration enabled.

This procedure does not create backups or guarantee data preservation. If
existing data must be preserved, follow [SigNoZ's ClickHouse upgrade and backup guidance](https://signoz.io/docs/operate/migration/upgrade-0-131/)
and validate a recovery point before upgrading.
