---
title: OCI Policies
sidebar_position: 3
---

## Overview

The following policies need to be in place to install Oracle Backend for Microservices and AI.

### Oracle Container Engine for Kubernetes

```text
Allow group `<group-name>` to manage cluster-family in `<location>`
├── Allow group `<group-name>` to inspect compartments in `<location>`
├── Allow group `<group-name>` to read virtual-network-family in `<location>`
├── Allow group `<group-name>` to use network-security-groups in `<location>`
├── Allow group `<group-name>` to use private-ips in `<location>`
├── Allow group `<group-name>` to use subnets in `<location>`
├── Allow group `<group-name>` to use vnics in `<location>`
├── Allow group `<group-name>` to manage cluster-node-pools in `<location>`
├── Allow group `<group-name>` to manage instance-family in `<location>`
└── Allow group `<group-name>` to manage public-ips in `<location>`
```

### VCN

```text
Allow group `<group-name>` to manage vcns in `<location>`
├── Allow group `<group-name>` to manage route-tables in `<location>`
├── Allow group `<group-name>` to manage security-lists in `<location>`
├── Allow group `<group-name>` to manage dhcp-options in `<location>`
├── Allow group `<group-name>` to manage nat-gateways in `<location>`
├── Allow group `<group-name>` to manage service-gateways in `<location>`
├── Allow group `<group-name>` to manage network-security-groups in `<location>`
└── Allow group `<group-name>` to manage subnets in `<location>`
```

### Container Registry

```text
Allow group `<group-name>` to manage repos in `<location>`
```

### Object Storage

```text
Allow group `<group-name>` to read objectstorage-namespaces in `<location>`
Allow group `<group-name>` to manage objects in `<location>`
└── Allow group `<group-name>` to manage buckets in `<location>`
```

### Autonomous Database

```text
Allow group `<group-name>` to manage autonomous-database-family in `<location>`
```

### Oracle Resource Manager

```text
Allow group `<group-name>` to read orm-template in `<location>`
Allow group `<group-name>` to use orm-stacks in `<location>`
└── Allow group `<group-name>` to manage orm-jobs in `<location>`
Allow group `<group-name>` to manage orm-private-endpoints in `<location>`
```
