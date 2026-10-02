---
title: Azure Kubernetes Service (AKS)
sidebar_position: 3
---

# OBaaS on Azure Kubernetes Service (AKS)

OBaaS installs on Azure AKS with minimal additional configuration. This document documents installation for the `obaas-prereqs` and `obaas` Helm charts on AKS.

## Scope

The repository includes two AKS example values files:

- `helm/infra-charts/obaas-prereqs/examples/values-aks.yaml`
- `helm/infra-charts/obaas/examples/values-aks.yaml`

Use them as the starting point for AKS deployments.

## Prerequisites

- AKS must meet the chart Kubernetes version requirement.
- The examples assume Azure Disk CSI storage is available.
- The `obaas` AKS example uses `managed-csi` as the storage class. Replace it if your AKS cluster standardizes on a different StorageClass.

## Install Sequence

Install cluster-scoped prerequisites once per AKS cluster:

```bash
helm upgrade --install obaas-prereqs ./obaas-prereqs \
  -n obaas-system \
  --create-namespace \
  -f obaas-prereqs/examples/values-aks.yaml
```

Install the main chart per namespace:

```bash
helm upgrade --install obaas ./obaas \
  -n obaas \
  --create-namespace \
  -f obaas/examples/values-aks.yaml
```

## `obaas-prereqs` Guidance

### `metrics-server`

AKS may already install and manage `metrics-server` through an AKS addon or another cluster-level installation.

If `metrics-server` is already present, disable the copy from `obaas-prereqs`:

```yaml
metrics-server:
  enabled: false
```

If AKS is not already providing `metrics-server`, leave it enabled.

## `obaas` Guidance

### Azure Cloud Detection

The AKS example sets both `k8s-infra.global.cloud` and `signoz.global.cloud` to `azure` so the observability stack identifies the environment correctly.

### Storage Classes

The AKS example sets:

- `signoz.global.storageClass: managed-csi`
- `signoz.clickhouse.persistence.storageClass: managed-csi`
- `signoz.signoz.persistence.storageClass: managed-csi`

This is intended for AKS clusters using the Azure Disk CSI driver. If your platform team uses a different StorageClass, update these values before install.

## Recommended Review Before Install

Review these values before using the AKS examples unchanged:

- StorageClass names
- Whether AKS already manages `metrics-server`
- How ingress should be exposed on AKS
