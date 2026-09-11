# Oracle Backend for Microservices and AI - Terraform for OCI

This directory contains Terraform configuration to deploy Oracle Backend for Microservices and AI (OBaaS) on Oracle Cloud Infrastructure (OCI).

## Prerequisites

- [Terraform](https://www.terraform.io/) (>= 1.5)
- [OCI CLI](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm) configured with API key authentication
- OCI tenancy with sufficient quotas for:
  - OKE (Oracle Kubernetes Engine) cluster
  - Flexible compute shapes (VM.Standard.E4/E5.Flex or VM.Standard.A1/A2.Flex)
  - Autonomous Database (unless using BYO database)
  - Load Balancer (flexible shape)

## Quick Start

1. **Initialize the configuration:**
   ```bash
   terraform init
   ```

2. **Copy an example configuration:**
   ```bash
   cp examples/k8s-new-adb.tfvars terraform.tfvars
   ```

3. **Configure OCI credentials** in `terraform.tfvars`:
   ```hcl
   tenancy_ocid     = "ocid1.tenancy.oc1..aaa..."
   compartment_ocid = "ocid1.compartment.oc1..aaa..."
   user_ocid        = "ocid1.user.oc1..aaa..."
   fingerprint      = "xx:xx:xx:..."
   private_key_path = "~/.oci/oci_api_key.pem"
   region           = "us-phoenix-1"
   ```

4. **Review and apply:**
   ```bash
   terraform plan
   terraform apply
   ```

5. **Configure kubectl access** (after apply completes):
   ```bash
   # Use the kubeconfig_cmd output
   oci ce cluster create-kubeconfig --cluster-id <cluster_ocid> --region <region>
   ```

## Configuration Options

### General Settings

| Variable | Description | Default |
|----------|-------------|---------|
| `tenancy_ocid` | OCI Tenancy OCID | Required |
| `compartment_ocid` | Compartment for resources | Required |
| `region` | OCI Region | Required |
| `label_prefix` | Prefix for resource names (max 12 chars) | Auto-generated |

### Database Options

The deployment supports three database configurations:

#### Option 1: New Autonomous Database (Default)
```hcl
# Leave byo_db_type empty (default)
adb_ecpu_core_count         = 2
adb_data_storage_size_in_gb = 20
adb_license_model           = "LICENSE_INCLUDED"  # or "BRING_YOUR_OWN_LICENSE"
adb_networking              = "PRIVATE_ENDPOINT_ACCESS"  # or "SECURE_ACCESS"
```

#### Option 2: Bring Your Own Autonomous Database (ADB-S)
```hcl
byo_db_type    = "ADB-S"
byo_db_password = "your_admin_password"
byo_adb_ocid   = "ocid1.autonomousdatabase.oc1..."
```

#### Option 3: Bring Your Own Other Database
```hcl
byo_db_type     = "OTHER"
byo_db_password = "your_system_password"
byo_odb_host    = "db-host.example.com"
byo_odb_port    = 1521
byo_odb_service = "SERVICENAME"
```

### Kubernetes Options

| Variable | Description | Default |
|----------|-------------|---------|
| `k8s_cpu_node_pool_size` | Number of CPU worker nodes | 3 |
| `k8s_api_is_public` | Expose K8s API publicly | true |
| `k8s_api_endpoint_allowed_cidrs` | CIDRs allowed to access K8s API | "0.0.0.0/0" |
| `k8s_node_pool_gpu_deploy` | Deploy GPU node pool | false |
| `k8s_gpu_node_pool_size` | Number of GPU worker nodes | 1 |
| `k8s_run_cfgmgt` | Run configuration management | true |
| `k8s_use_cluster_addons` | Install OKE cluster add-ons | true |
| `k8s_use_local_charts` | Use local Helm charts from `helm/` instead of the remote Helm repository | false |
| `k8s_byo_ocir_url` | BYO Oracle Container Registry URL | "" |

### Local Helm Chart Development

By default, the OCI Resource Manager build vendors the published Helm charts into the stack package. For local Terraform development, you can test charts from a local checkout without rebuilding the ZIP.

`apply.py` looks for local charts under the sibling `helm` directory:

```text
../helm/infra-charts/obaas-prereqs
../helm/infra-charts/obaas
```

Verify the charts are visible:

```bash
ls ../helm/infra-charts/obaas/Chart.yaml
ls ../helm/infra-charts/obaas-prereqs/Chart.yaml
```

If the charts have dependencies, update them in the chart repo before applying:

```bash
cd ../helm/infra-charts
helm dependency update obaas-prereqs
helm dependency update obaas
```

Then run Terraform with local charts enabled:

```bash
cd opentofu
terraform plan -var='k8s_use_local_charts=true'
terraform apply -var='k8s_use_local_charts=true'
```

You can also set this in `terraform.tfvars`:

```hcl
k8s_use_local_charts = true
```

To return to published charts for direct Terraform runs, remove that variable or set it to `false`.

### Compute Options

| Variable | Description | Default |
|----------|-------------|---------|
| `compute_cpu_shape` | CPU compute shape | VM.Standard.E5.Flex |
| `compute_cpu_ocpu` | OCPUs per CPU worker | 2 |
| `compute_gpu_shape` | GPU compute shape | VM.GPU.A10.1 |

### Network Options

By default, a new VCN with public and private subnets is created. To use existing networking:

```hcl
byo_vcn_ocid            = "ocid1.vcn.oc1..."
byo_public_subnet_ocid  = "ocid1.subnet.oc1..."
byo_private_subnet_ocid = "ocid1.subnet.oc1..."
```

### Load Balancer Options

| Variable | Description | Default |
|----------|-------------|---------|
| `lb_min_shape` | Minimum bandwidth (Mbps) | 10 |
| `lb_max_shape` | Maximum bandwidth (Mbps) | 10 |
| `client_allowed_cidrs` | CIDRs allowed for client access | "0.0.0.0/0" |
| `server_allowed_cidrs` | CIDRs allowed for server API access | "0.0.0.0/0" |

### AI Optimizer

| Variable | Description | Default |
|----------|-------------|---------|
| `deploy_optimizer` | Deploy AI Optimizer and Toolkit | false |

## Examples

See the [examples/](examples/) directory for complete configuration examples:

| File | Description |
|------|-------------|
| `k8s-new-adb.tfvars` | Kubernetes deployment with new Autonomous Database |
| `k8s-byo-other-db.tfvars` | Kubernetes deployment with bring-your-own database |

### Running Tests

The `examples/manual-test.sh` script validates configurations using your OCI credentials:

```bash
# Uses ~/.oci/config [DEFAULT] profile
./examples/manual-test.sh

# Use a specific profile
./examples/manual-test.sh MYPROFILE
```

## Outputs

After successful deployment:

| Output | Description |
|--------|-------------|
| `app_name` | Application label/namespace |
| `app_version` | Deployed application version |
| `optimizer_client_url` | AI Optimizer web UI URL |
| `optimizer_server_url` | AI Optimizer API URL |
| `kubeconfig_cmd` | Command to generate kubeconfig |

## OCI Resource Manager (ORM)

This configuration is compatible with OCI Resource Manager for deployment via the OCI Console. The `schema.yaml` file defines the ORM form layout.

## Directory Structure

```
.
├── README.md                 # This file
├── main.tf                   # Core resources (LB, ADB)
├── variables.tf              # Root-level variables
├── output.tf                 # Root-level outputs
├── locals.tf                 # Local values
├── provider.tf               # Provider configuration
├── versions.tf               # Version constraints
├── data.tf                   # Data sources
├── nsgs.tf                   # Network Security Groups
├── module_network.tf         # Network module invocation
├── module_kubernetes.tf      # Kubernetes module invocation
├── schema.yaml               # OCI ORM schema
├── examples/                 # Example tfvars files
│   ├── README.md
│   ├── k8s-new-adb.tfvars
│   ├── k8s-byo-other-db.tfvars
│   └── manual-test.sh
├── modules/
│   ├── kubernetes/           # OKE cluster and configuration
│   └── network/              # VCN, subnets, gateways
└── cfgmgt/                   # Configuration management scripts
```

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

## License

Copyright (c) 2024, 2026, Oracle and/or its affiliates.
Licensed under the Universal Permissive License (UPL), Version 1.0.
See [LICENSE](http://oss.oracle.com/licenses/upl) for details.
