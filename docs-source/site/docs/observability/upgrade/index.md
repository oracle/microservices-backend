---
title: Upgrade SigNoZ in place
sidebar_position: 9
---

# Upgrade SigNoZ in place

OBaaS 2.1.2 requires ClickHouse `25.12.5` before its new telemetry-store
migrations run. The migrator is a Helm `pre-upgrade` hook, so a single application
upgrade from an older ClickHouse version can fail before the database is updated.

Follow the [two-step ClickHouse and SigNoZ upgrade procedure](../../upgrade/index.mdx#upgrade-signoz-and-clickhouse-in-two-steps)
after applying the required operator and Gateway API CRD updates. That procedure
is for installations where data loss is acceptable and does not create backups.

If existing data must be preserved, follow [SigNoZ's ClickHouse upgrade and backup guidance](https://signoz.io/docs/operate/migration/upgrade-0-131/)
and validate your recovery point before upgrading. Do not select
`signozUpgrade.mode=destructive-replace` for this in-place upgrade.
