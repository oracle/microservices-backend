---
title: Common Customizations
sidebar_position: 2
---
## Configure Online Storage

You can configure the amount of online storage, for storing metrics, logs and traces, by specifying the desired size in the `values.yaml`
for the `obaas` Helm chart as follows.  The default size is 25 GB.  If you have a large number of applications, you may want to increase
the amount of storage.

```yaml
signoz:
  clickhouse:
    persistence: 
      size: 200Gi
```

## Configure Cold Storage

TODO write me