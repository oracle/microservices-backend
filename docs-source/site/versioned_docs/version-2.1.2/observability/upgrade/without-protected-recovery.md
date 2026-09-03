---
title: Upgrade without protected recovery
sidebar_position: 2
---

# Upgrade to SigNoZ 0.134.0 without protected recovery

This procedure uses one Helm command and does not create Kubernetes volume
snapshots.

## When to use this guide

Use this guide only when losing historical telemetry, dashboards, users, and
ClickHouse data is acceptable. Existing data normally remains when the in-place
upgrade succeeds, but this procedure does not provide a snapshot-based recovery
point if it fails.

For production environments, use
[Upgrade with protected recovery](./protected-recovery.md).

## Prerequisites

Add and update the released OBaaS Helm repository:

```bash
helm repo add obaas https://oracle.github.io/microservices-backend/helm
helm repo update
```

Confirm the Kubernetes context, Helm release name, application namespace,
customer values file, database settings, secret names, and private-registry
settings. Confirm that SigNoZ, ClickHouse, and ZooKeeper are healthy.

## Step-by-step procedure

Record the existing state:

```bash
kubectl config current-context
helm status <app-release> -n <application-namespace>
kubectl get pods,pvc -n <application-namespace>

helm get values <app-release> -n <application-namespace> -o yaml \
  > /tmp/obaas-pre-signoz-upgrade-values.yaml
```

Run the standard upgrade:

```bash
helm upgrade <app-release> obaas/obaas \
  --version 0.1.1 \
  -n <application-namespace> \
  --timeout 30m \
  -f <customer-values-file> \
  --set signozUpgrade.stage=standard
```

This upgrades ClickHouse, SigNoZ, and the collector and runs the telemetry
migrations without first creating snapshots.

## Validation

```bash
kubectl get pods,jobs -n <application-namespace>
helm status <app-release> -n <application-namespace>
```

Confirm:

- SigNoZ is running `v0.134.0`.
- The SigNoZ collector is running `v0.144.6`.
- ClickHouse is running `25.12.5`.
- The telemetry-store migrator and SigNoZ setup Jobs completed.
- Users can sign in and dashboards load.
- New metrics, logs, and traces are ingested.

## Rollback and recovery

This path does not create a protected recovery point. ClickHouse downgrades are
not guaranteed after its on-disk format has been upgraded. Do not start an
older ClickHouse version against the upgraded live PVC.

Recovery is limited to an independently created provider backup or external
backup. If none exists, reinstalling SigNoZ with new storage may be required and
historical data may be lost.

Do not use `helm uninstall` merely to discard SigNoZ history. The OBaaS chart
can delete all PVCs in the application namespace during uninstall, including
PVCs that are not part of SigNoZ.

## Troubleshooting

Inspect the release and workloads:

```bash
helm status <app-release> -n <application-namespace>
kubectl get pods,jobs,pvc -n <application-namespace>
kubectl get events -n <application-namespace> --sort-by=.lastTimestamp
```

Review logs for the failed SigNoZ, ClickHouse, setup, or telemetry-migration
workload before attempting another upgrade.
