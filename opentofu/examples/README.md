# OpenTofu Example Variable Files

This directory contains example `.tfvars` files for different deployment scenarios.

## Quick Start

```bash
# Load credentials from ~/.oci/config and run all tests
cd /path/to/terraform/
./examples/manual-test.sh
```

The test script automatically loads credentials from `~/.oci/config`, sets compartment to your tenancy root, and runs `tofu plan` on all testable examples.

## Example Scenarios

| File | Description | Database |
|------|-------------|----------|
| `k8s-new-adb.tfvars` | Kubernetes deployment with new Autonomous Database | New ADB |
| `k8s-byo-other-db.tfvars` | Kubernetes deployment with bring-your-own database | BYO OTHER |

### k8s-new-adb.tfvars

Creates a new OKE cluster with a new Autonomous Database:
- Private endpoint ADB networking
- E4.Flex compute shape with 2 OCPUs
- Flexible load balancer (10-100 Mbps)

### k8s-byo-other-db.tfvars

Creates a new OKE cluster using an existing external database:
- Requires `byo_odb_host`, `byo_odb_port`, `byo_odb_service`, and `byo_db_password`
- A1.Flex (ARM) compute shape with 4 OCPUs
- Flexible load balancer (10-50 Mbps)

## Manual Setup (Without Helper Script)

If you prefer not to use the helper script:

1. Copy an example:
   ```bash
   cd /path/to/terraform/
   cp examples/k8s-new-adb.tfvars terraform.tfvars
   ```

2. Edit `terraform.tfvars` and add the authentication variables:
   ```hcl
   tenancy_ocid     = "ocid1.tenancy.oc1..aaa..."
   compartment_ocid = "ocid1.compartment.oc1..aaa..."
   user_ocid        = "ocid1.user.oc1..aaa..."
   fingerprint      = "xx:xx:xx:..."
   private_key_path = "~/.oci/oci_api_key.pem"
   region           = "us-phoenix-1"
   ```

3. Run OpenTofu:
   ```bash
   tofu init
   tofu plan
   tofu apply
   ```

## OCI Config File Format

The helper script `manual-test.sh` reads from `~/.oci/config` which should look like:

```ini
[DEFAULT]
user=ocid1.user.oc1..aaa...
tenancy=ocid1.tenancy.oc1..aaa...
region=us-phoenix-1
fingerprint=xx:xx:xx:...
key_file=~/.oci/oci_api_key.pem
```

If you don't have this file, run: `oci setup config`
