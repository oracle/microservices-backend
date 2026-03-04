---
title: Prerequisites
sidebar_position: 1
---
## Overview

Before installing Oracle Backend for Microservices and AI (OBaaS), ensure your environment meets all prerequisites. Installing without meeting these requirements will result in deployment failures.

:::danger Warning
If your environment does not meet the prerequisites, the installation may not succeed. Do not proceed with installation until you have confirmed your environment meets all requirements.
:::

## System Requirements

### Oracle OCI

If you are installing into Oracle OCI you need the right [OCI IAM policies](../oci_policies.md) in place.  Plwase review and ensure you have the required policies and permissions before installing.

### Kubernetes Cluster

A CNCF-compliant Kubernetes cluster with the following specifications:

**Cluster version:**

- Kubernetes 1.34+

**Infrastructure requirements:**

- Minimum 3 worker nodes
- At least 2 OCPU and 32GB memory per worker node
- Working storage provider with storage class for RWX (ReadWriteMany) PVs

**Capacity planning:**

- Base configuration supports ONE OBaaS installation plus applications
- For TWO OBaaS instances: double the number of worker nodes
- Scale worker nodes based on additional application requirements

:::tip Recommended
Oracle Kubernetes Engine (OKE) "Quick Create/Enhanced" cluster is the recommended platform for OBaaS deployments.
:::

### Oracle Database

You must have access to an Oracle Database instance (19c or later). The following database types are supported:

- Oracle Autonomous Database (ADB-S or ADB-D)
- Oracle Database on-premise or in the cloud

**Version requirements:**

| Minimum | Recommended |
|---------|-------------|
| Oracle Database 19c | Oracle Autonomous Database 26ai ATP |

:::info AI Features
To use OBaaS AI capabilities, you must use Oracle Database 26ai or later. Earlier versions do not support AI features.
:::

**Recommended configuration:**

- 2 ECPU
- 1 TB storage
- Secure access from anywhere enabled

**Access requirements:**

- ADMIN or SYSTEM credentials (required for schema creation)
- Connection details: host, port, and service name


### Private Image Repository (Optional)

If using a private container image repository:

**Requirements:**

- All OBaaS images copied to your private registry
- Registry credentials configured in Kubernetes
- Network access from cluster to private registry

**Helper script:**

OBaaS provides the `mirror-images.sh` script to assist with copying images to your private repository.

```bash
helm/tools/mirror-images.sh
```

## Verification

### Verify Kubernetes Cluster

Check your Kubernetes version:

```bash
kubectl version --short
```

Verify worker nodes meet requirements:

```bash
kubectl get nodes
kubectl describe nodes | grep -A 5 "Allocated resources"
```

Check storage classes:

```bash
kubectl get storageclass
```

Ensure you have a storage class that supports RWX (ReadWriteMany) access mode.

### Verify Default Namespaces

For a fresh OKE cluster, verify the default namespaces are present:

```bash
kubectl get ns
```

Expected output:

```text
NAME            STATUS   AGE
default         Active   4m52s
kube-node-lease Active   4m52s
kube-public     Active   4m52s
kube-system     Active   4m52s
```
