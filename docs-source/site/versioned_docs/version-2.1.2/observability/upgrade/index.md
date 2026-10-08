---
title: Upgrade SigNoZ in place
sidebar_position: 9
---

# Upgrade SigNoZ in place

## In-place patch upgrade

The optional OBaaS 2.1.2 patch release upgrades SigNoZ in place. Existing
telemetry, dashboards, users, alerts, ClickHouse data, and ZooKeeper data are
retained. The application database and other OBaaS services are unchanged.

Do not set `signozUpgrade.mode=destructive-replace` for this patch upgrade.

## Upgrade command

Use the complete values file for the installed release:

```bash
helm upgrade <app-release> helm/infra-charts/obaas \
  -n <application-namespace> \
  --timeout 30m \
  -f <customer-values-file>
```
