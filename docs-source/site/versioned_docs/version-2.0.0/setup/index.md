---
title: Setup
sidebar_position: 0
---

## Oracle Backend for Microservices and AI (OBaaS) - Deployment Options

Choose your preferred deployment method for OBaaS based on your requirements and existing infrastructure.

### Deploy with Helm

**Best for**: Deploying to existing Kubernetes clusters.

**What you get**:

- **Flexible deployment** to existing Kubernetes cluster
- **Multi-tenancy support** - deploy multiple OBaaS instances
- **Granular control** over individual components
- **Use existing infrastructure** (cluster, database, networking)

**Prerequisites**:

- Existing Kubernetes cluster (1.34+)
- Helm 3.8+ installed
- kubectl configured
- Access to Oracle Database (19c or later)

**[Get started with Helm Charts →](./helm/install.md)**

### Deploy using OCI "Magic Button"

Complete infrastructure provisioning on Oracle Cloud Infrastructure.

**What you get**:

- Automated OKE cluster creation and configuration
- Autonomous Database provisioning (or BYO database support)
- Network infrastructure (VCN, subnets, load balancers, security lists)
- Complete OBaaS platform deployed and configured

**Prerequisites:**

- OCI tenancy with appropriate quotas and permissions

To use this approach, click on this button to get started:

[![Deploy to Oracle Cloud](https://oci-resourcemanager-plugin.plugins.oci.oraclecloud.com/latest/deploy-to-oracle-cloud.svg)](https://cloud.oracle.com/resourcemanager/stacks/create?zipUrl=https://github.com/oracle/microservices-backend/releases/latest/download/obaas-iac.zip)

When deploying using this method you may see the following error, the resolution is to run the `Apply` job again:

```log
module.kubernetes["managed"].oci_identity_policy.workers_policies: Creating...
module.kubernetes["managed"].oci_identity_policy.workers_policies: Creation complete after 0s [id=ocid1.policy.oc1..aaaaaaaasaxvpssa2h2qgzacgc5az6s477gn3o4sdhwwh3fo7jxyxmu2k24a]
╷
│ Error: During creation, Terraform expected the resource to reach state(s): ACTIVE,NEEDS_ATTENTION, but the service reported unexpected state: DELETING.
│ 
│   with module.kubernetes["managed"].oci_containerengine_addon.ingress_addon[0],
│   on modules/kubernetes/main.tf line 125, in resource "oci_containerengine_addon" "ingress_addon":
│  125: resource "oci_containerengine_addon" "ingress_addon" {
│ 
```
