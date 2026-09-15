---
title: Replace SigNoZ during upgrade
sidebar_position: 9
---

# Replace SigNoZ during upgrade

## Warning: This permanently deletes observability data

Upgrading an existing OBaaS release to this optional 2.1.1 patch release
replaces SigNoZ rather than migrating it.
The procedure permanently deletes all existing SigNoZ telemetry, dashboards,
users, alerts, ClickHouse data, and ZooKeeper data. It does not affect the
application database or other OBaaS services.

This release has no in-place or data-preserving SigNoZ upgrade path.

If the destructive-replace settings are omitted from an existing-release
upgrade, Helm fails before changing any OBaaS resources. Users who require
a data-preserving upgrade are encouraged to follow SigNoZ's own documentation;
that path is
not supported by OBaaS 2.1.1.

## Upgrade command

Use the complete values file for the installed release and explicitly acknowledge
data loss:

```bash
helm upgrade <app-release> helm/infra-charts/obaas \
  -n <application-namespace> \
  --timeout 30m \
  -f <customer-values-file> \
  --set signozUpgrade.mode=destructive-replace \
  --set signozUpgrade.confirmDataLoss=true
```

Fresh installations do not need these settings.
