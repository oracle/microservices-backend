---
title: Persistent SigNoz collector queues
sidebar_position: 6.2
---

The [persistent queue example](https://github.com/oracle/microservices-datadriven/blob/main/helm/infra-charts/obaas/examples/values-signoz-persistent-queue.yaml)
configures queuing and backpressure in the SigNoz collector to help mitigate
telemetry bursts overwhelming ClickHouse. It buffers pending exports on disk,
bounds concurrent export requests and blocks enqueueing when a queue is full.
This gives ClickHouse time to recover from temporary ingestion pressure or
backend interruptions.

Layer this example after a
[small or medium sizing profile](https://oracle.github.io/microservices-backend/obaas/docs/observability/signoz-profiles).
It uses one collector with a dedicated PVC. The distributed profile requires
independent storage for each collector and cannot share this queue directory.

## What the example configures

<table>
  <thead>
    <tr>
      <th scope="col">Setting</th>
      <th scope="col">Example configuration</th>
      <th scope="col">Purpose</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <th scope="row">Collector deployment</th>
      <td>1 replica, autoscaling disabled, <code>Recreate</code> rollouts</td>
      <td>Keep one collector attached to the queue volume and avoid overlapping pods during upgrades.</td>
    </tr>
    <tr>
      <th scope="row">Exporter coverage</th>
      <td>Traces, metrics, logs, metadata and meter data</td>
      <td>Enable persistent queues on all five ClickHouse exporters.</td>
    </tr>
    <tr>
      <th scope="row">Queue storage</th>
      <td>Separate <code>signoz-collector-queue</code> PVC, requesting 20Gi with <code>ReadWriteOncePod</code></td>
      <td>Retain queued exports across pod replacement and restrict the claim to one pod.</td>
    </tr>
    <tr>
      <th scope="row">Storage extension</th>
      <td><code>file_storage/queue</code>, mounted under <code>/var/lib/otelcol/queue</code></td>
      <td>Store exporter queues on the PVC using stable exporter and extension IDs.</td>
    </tr>
    <tr>
      <th scope="row">Queue capacity</th>
      <td>1,000 requests/batches per exporter queue</td>
      <td>Bound the pending backlog. Capacity is measured in requests, not records or bytes.</td>
    </tr>
    <tr>
      <th scope="row">Export concurrency</th>
      <td>2 consumers per exporter queue</td>
      <td>Limit concurrent exports from each queue to ClickHouse.</td>
    </tr>
    <tr>
      <th scope="row">Backpressure</th>
      <td><code>block_on_overflow: true</code></td>
      <td>Block enqueueing until space becomes available, allowing pressure to propagate through the collector pipeline.</td>
    </tr>
    <tr>
      <th scope="row">Retry policy</th>
      <td>5-second initial backoff, 30-second maximum backoff, unlimited elapsed retry time</td>
      <td>Keep retrying retryable export failures while the backend recovers.</td>
    </tr>
    <tr>
      <th scope="row">Export timeout</th>
      <td>30 seconds per attempt</td>
      <td>Bound the duration of individual export attempts.</td>
    </tr>
    <tr>
      <th scope="row">File storage</th>
      <td>Directory creation, <code>fsync</code> and rebound compaction enabled</td>
      <td>Persist writes and reclaim file space after queues drain, with additional I/O and temporary disk-space requirements.</td>
    </tr>
    <tr>
      <th scope="row">Volume permissions</th>
      <td>UID/GID and volume group 10001</td>
      <td>Run the collector as a non-root user with write access to the queue volume.</td>
    </tr>
    <tr>
      <th scope="row">Existing collector configuration</th>
      <td>Preserved signal pipelines and diagnostic extensions; memory limiting and batching inherited from the sizing profile</td>
      <td>Add persistence alongside the profile's processing and memory controls.</td>
    </tr>
  </tbody>
</table>

The request counts, concurrency and storage capacity are starting values. Size
them against your telemetry volume, payload sizes, storage performance and target
buffering duration. Queuing absorbs temporary excess; sustained ingestion must
remain below ClickHouse's processing capacity, with enough headroom to drain the
backlog. The consumer count bounds concurrency rather than imposing a fixed
telemetry rate.

## Use the example

Copy [signoz-collector-queue-pvc.yaml](https://github.com/oracle/microservices-datadriven/blob/main/helm/infra-charts/obaas/examples/signoz-collector-queue-pvc.yaml)
to a site-specific manifest. Select a durable CSI StorageClass supporting
`ReadWriteOncePod`, file locking and write permissions through `fsGroup`. The
manifest uses the default StorageClass unless you set `storageClassName`. Check
the allocated capacity: providers may provision more than the requested size.

From the repository root, apply the PVC in the release namespace and layer the
queue values after your environment and sizing values:

```bash
kubectl create namespace <application-namespace>
kubectl -n <application-namespace> apply -f <site-queue-pvc.yaml>

helm template <app-release> helm/infra-charts/obaas -n <application-namespace> \
  -f <environment-values.yaml> \
  -f helm/infra-charts/obaas/examples/values-signoz-small.yaml \
  -f helm/infra-charts/obaas/examples/values-signoz-persistent-queue.yaml \
  > /tmp/obaas-persistent-queue-rendered.yaml

helm install <app-release> helm/infra-charts/obaas -n <application-namespace> \
  -f <environment-values.yaml> \
  -f helm/infra-charts/obaas/examples/values-signoz-small.yaml \
  -f helm/infra-charts/obaas/examples/values-signoz-persistent-queue.yaml
```

These commands illustrate a fresh installation after preparing OBaaS
prerequisites. Use medium in place of small if appropriate, and skip namespace
creation when it already exists. With `WaitForFirstConsumer`, the PVC can remain
Pending until the collector is scheduled. Review the rendered configuration
before installing; Helm replaces lists such as volumes, mounts and extensions.
Protect rendered files containing credentials.

For an existing collector, drain its memory queues before enabling persistence;
the rollout does not copy them to disk. Keep the same PVC and exporter/extension
IDs for replay. The PVC is managed separately from Helm and survives release
uninstallation. Drain persistent queues before removing the overlay.

## Operational considerations

Persistence covers data successfully enqueued at the exporter. Receiver, batch
and processor state can still be in memory. Permanent export errors, disk
exhaustion, upstream retry expiry and storage loss can still lose data; replay
can produce duplicates. Single-collector restarts also interrupt ingestion.

Monitor queue size/capacity, enqueue/send failures, PVC free space, memory and
telemetry freshness. Leave disk space for compaction and account for file-backed
memory usage. Validate recovery by interrupting a test collector's backend path,
sending identifiable telemetry, replacing its pod with backlog present, and
confirming replay and queue drainage after connectivity returns. Reconcile total
and distinct-record counts without resending the test records.

See [OpenTelemetry exporter queues and retries](https://raw.githubusercontent.com/open-telemetry/opentelemetry-collector/v0.144.0/exporter/exporterhelper/README.md)
and [file storage and compaction](https://raw.githubusercontent.com/open-telemetry/opentelemetry-collector-contrib/v0.144.0/extension/storage/filestorage/README.md)
for the underlying collector behavior.
