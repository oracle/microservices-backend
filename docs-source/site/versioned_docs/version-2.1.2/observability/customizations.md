---
title: Common Customizations
sidebar_position: 2
---
## Configure Online Storage

You can configure the amount of online storage, for storing metrics, logs and traces, by specifying the desired size in the `values.yaml`
for the `obaas` Helm chart as follows. The default ClickHouse volume request is `20Gi`. If you have a large number of applications, you may want to increase
the amount of storage.

```yaml
signoz:
  clickhouse:
    persistence: 
      size: 200Gi
```

This value controls the ClickHouse volume that stores telemetry. It is separate
from the SigNoZ metadata volume, configured with
`signoz.signoz.persistence.size`, whose default request is `1Gi`.

## Configure Cold Storage

### Use Case

Use this configuration when you want recent telemetry data to remain on local persistent storage while older data is offloaded to object storage for long-term retention. For on-premises deployments, use a supported S3-compatible object store. For additional information, see the [SigNoz Administrator Guide](https://signoz.io/docs/manage/administrator-guide/).

### Storage Hierarchy

SigNoZ stores recent ClickHouse data on the local persistent volume as hot storage. After the configured retention threshold is reached, older data is moved to OCI Object Storage or another supported S3-compatible object store. When needed, ClickHouse retrieves older data from cold storage to satisfy queries.

```text
  Hot Storage (Local Disk)
  ↓ [after retention threshold]
  Cold Storage (OCI Object Storage / S3-compatible object storage)
  ↓ [query hits cold data]
```

### Configuration Summary

| Key | Value | Description |
|---|---|---|
| `signoz.enabled` | `true` | Enables the SigNoz deployment. |
| `signoz.clickhouse.coldStorage.enabled` | `true` | Enables ClickHouse cold storage. |
| `signoz.clickhouse.coldStorage.defaultKeepFreeSpaceBytes` | `"10485760"` | Keeps at least 10 MiB of local disk space free before moving older data to cold storage. Set value to reflect your environment |
| `signoz.clickhouse.coldStorage.type` | `s3` | Uses an S3-compatible object storage API. |
| `signoz.clickhouse.coldStorage.endpoint` | `<END-POINT>` | Object storage endpoint URL. |
| `signoz.clickhouse.coldStorage.accessKey` | `<YOUR-ACCESS-KEY>` | Access key for the object storage service. |
| `signoz.clickhouse.coldStorage.secretAccess` | `<YOUR-SECRET-ACCESS-KEY>` | Secret key for the object storage service. |
| `signoz.clickhouse.persistence.enabled` | `true` | Enables persistent local storage for ClickHouse hot data. |
| `signoz.clickhouse.persistence.size` | `100Gi` | Size of the local persistent volume used for hot storage. Set value to reflect your environment |

### Installation

Before installation modify the `values-signoz-cold-storage.yaml` file with values that reflects your environment.

```bash
  helm upgrade --install <app-release> obaas/obaas \
    -f examples/values-signoz-cold-storage.yaml \
    -n <application-namespace> \
    --create-namespace [--debug]
```
