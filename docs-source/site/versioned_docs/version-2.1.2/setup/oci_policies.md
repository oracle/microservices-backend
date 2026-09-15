---
title: OCI Policies
sidebar_position: 3
---

## Overview

The following policies need to be in place to install Oracle Backend for Microservices and AI.

:::tip[Use names or OCIDs]
You can use OCIDs instead of names by replacing the `<group-name>` or `<comparment-name>` with the word `id` followed by the OCID.  Use of OCIDs may be required for some kinds of identity domains.
:::

### Identity and Access Management

```text
Allow group <group-name> to read compartments in tenancy
Allow group <group-name> to read domains in tenancy
Allow group <group-name> to inspect all-resources in tenancy
Allow group <group-name> to inspect resource-availability in tenancy
Allow group <group-name> to read limits in tenancy
Allow group <group-name> to manage dynamic-groups in tenancy
Allow group <group-name> to manage policies in tenancy
```

### Oracle Container Engine for Kubernetes

```text
Allow group <group-name> to manage cluster-family in compartment <compartment-name>
Allow group <group-name> to manage cluster-node-pools in compartment <compartment-name>
Allow group <group-name> to manage clusters in compartment <compartment-name>
Allow group <group-name> to manage instance-family in compartment <compartment-name>
Allow group <group-name> to manage cluster-node-pools in compartment <compartment-name>
Allow group <group-name> to manage instance-family in compartment <compartment-name>
Allow group <group-name> to manage public-ips in compartment <compartment-name>
```

### VCN

```text
Allow group <group-name> to manage vcns in compartment <compartment-name>
Allow group <group-name> to manage virtual-network-family in compartment <compartment-name>
Allow group <group-name> to use private-ips in compartment <compartment-name>
Allow group <group-name> to use subnets in compartment <compartment-name>
Allow group <group-name> to use vnics in compartment <compartment-name>
Allow group <group-name> to manage route-tables in compartment <compartment-name>
Allow group <group-name> to manage security-lists in compartment <compartment-name>
Allow group <group-name> to manage dhcp-options in compartment <compartment-name>
Allow group <group-name> to manage nat-gateways in compartment <compartment-name>
Allow group <group-name> to manage service-gateways in compartment <compartment-name>
Allow group <group-name> to manage network-security-groups in compartment <compartment-name>
Allow group <group-name> to manage subnets in compartment <compartment-name>
Allow group <group-name> to manage load-balancers in compartment <compartment-name>
```

### Container Registry

```text
Allow group <group-name> to manage repos in compartment <compartment-name>
```

### Object Storage

```text
Allow group <group-name> to read objectstorage-namespaces in compartment <compartment-name>
Allow group <group-name> to manage objects in compartment <compartment-name>
Allow group <group-name> to inspect buckets in compartment <compartment-name>
```

### Autonomous Database

```text
Allow group <group-name> to manage autonomous-database-family in compartment <compartment-name>
```

### Oracle Resource Manager

```text
Allow group <group-name> to manage orm-family in compartment <compartment-name>
Allow group <group-name> to manage orm-config-source-providers in compartment <compartment-name>
Allow group <group-name> to manage orm-stacks in compartment <compartment-name>
Allow group <group-name> to manage orm-jobs in compartment <compartment-name>
Allow group <group-name> to manage orm-private-endpoints in compartment <compartment-name>
Allow group <group-name> to manage orm-template in compartment <compartment-name>
Allow group <group-name> to manage orm-work-requests in compartment <compartment-name>
Allow group <group-name> to use cloud-shell-public-network in tenancy
Allow group <group-name> to use cloud-shell in tenancy
```
