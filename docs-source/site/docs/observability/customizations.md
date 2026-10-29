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

<table aria-label="Configuration Summary table">
  <thead>
    <tr>
      <th scope="col">Key</th>
      <th scope="col">Value</th>
      <th scope="col">Description</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <th scope="row"><code>signoz.enabled</code></th>
      <td><code>true</code></td>
      <td>Enables the SigNoz deployment.</td>
    </tr>
    <tr>
      <th scope="row"><code>signoz.clickhouse.coldStorage.enabled</code></th>
      <td><code>true</code></td>
      <td>Enables ClickHouse cold storage.</td>
    </tr>
    <tr>
      <th scope="row"><code>signoz.clickhouse.coldStorage.defaultKeepFreeSpaceBytes</code></th>
      <td><code>"10485760"</code></td>
      <td>Keeps at least 10 MiB of local disk space free before moving older data to cold storage. Set value to reflect your environment</td>
    </tr>
    <tr>
      <th scope="row"><code>signoz.clickhouse.coldStorage.type</code></th>
      <td><code>s3</code></td>
      <td>Uses an S3-compatible object storage API.</td>
    </tr>
    <tr>
      <th scope="row"><code>signoz.clickhouse.coldStorage.endpoint</code></th>
      <td><code>&lt;END-POINT&gt;</code></td>
      <td>Object storage endpoint URL.</td>
    </tr>
    <tr>
      <th scope="row"><code>signoz.clickhouse.coldStorage.accessKey</code></th>
      <td><code>&lt;YOUR-ACCESS-KEY&gt;</code></td>
      <td>Access key for the object storage service.</td>
    </tr>
    <tr>
      <th scope="row"><code>signoz.clickhouse.coldStorage.secretAccess</code></th>
      <td><code>&lt;YOUR-SECRET-ACCESS-KEY&gt;</code></td>
      <td>Secret key for the object storage service.</td>
    </tr>
    <tr>
      <th scope="row"><code>signoz.clickhouse.persistence.enabled</code></th>
      <td><code>true</code></td>
      <td>Enables persistent local storage for ClickHouse hot data.</td>
    </tr>
    <tr>
      <th scope="row"><code>signoz.clickhouse.persistence.size</code></th>
      <td><code>100Gi</code></td>
      <td>Size of the local persistent volume used for hot storage. Set value to reflect your environment</td>
    </tr>
  </tbody>
</table>

### Installation

Before installation modify the `values-signoz-cold-storage.yaml` file with values that reflects your environment.

```bash
  helm upgrade --install <app-release> obaas/obaas \
    -f examples/values-signoz-cold-storage.yaml \
    -n <application-namespace> \
    --create-namespace [--debug]
```
