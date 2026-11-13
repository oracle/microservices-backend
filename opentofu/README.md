# OBaaS Infrastructure Source for OCI

This directory contains the OpenTofu/Terraform configuration, OCI Resource Manager schema, and configuration-management scripts for Oracle Backend for Microservices and AI (OBaaS).

For prerequisites, configuration choices, deployment, verification, disaster recovery, and cleanup, use the [OCI deployment guide](../docs-source/site/docs/setup/cloud/oci.mdx). This README covers developing and administering the source.

## Source Map

| Path | Responsibility |
|------|----------------|
| `main.tf`, `locals.tf`, `data.tf`, `nsgs.tf` | Root resources, derived settings, discovery, and network security |
| `variables.tf`, `provider.tf`, `output.tf` | Root inputs, provider configuration, and outputs |
| `versions.tf` | Release-managed application, OS, and Kubernetes versions |
| `module_network.tf`, `module_kubernetes.tf`, `module_fsdr.tf` | Module wiring and deployment-specific inputs and outputs |
| `schema.yaml` | Resource Manager form layout |
| `modules/network/` | VCN, subnets, and gateways |
| `modules/kubernetes/` | OKE clusters, workers, add-ons, and generated configuration |
| `modules/kubernetes/storage/` | Primary volume inventory and PV configuration |
| `modules/fsdr/` | Regional recovery coordination, buckets, and IAM |
| `modules/fsdr/storage/` | Volume groups and replication for supplied primary volumes |
| `modules/fsdr/region/` | Protection groups, plans, executions, and Automatic DR |
| `cfgmgt/` | Installation scripts and generated files under `stage/` |
| `examples/` | Deployment inputs |
| `tests/` | Root and module suites, live configuration validation, and schema validation |

Keep root inputs, the Resource Manager schema, examples, and the deployment guide aligned when changing configuration. Leave the `app_version` placeholder in `versions.tf` at `0.0.0` outside the release workflow.

## Packaging IaC Stack

The IaC is packaged and attached to each release using GitHub Actions. Below is the manual procedure:

1. Zip the IaC with Archives
    ```bash
    zip -r obaas-iac.zip . \
      -x "terraform*" ".terraform*" "*/terraform*" "*/.terraform*" "tests/*" \
      -x "cfgmgt/stage/*.*" "*.tfplan*" "examples/*" "*.md" ".gitignore" "*pycache*"
    ```

## Local Helm Chart Development

`cfgmgt/apply.py` resolves local charts from the sibling `helm/infra-charts/` directory. From `opentofu/`, verify the paths:

```bash
ls ../helm/infra-charts/obaas-prereqs/Chart.yaml ../helm/infra-charts/obaas/Chart.yaml
```

[Prepare the chart dependencies](../docs-source/site/docs/setup/cloud/oci.mdx#prepare-helm-charts) and set `k8s_use_local_charts=true` in the run's variable file when developing or testing with this checkout. Follow [Local Deployment](../docs-source/site/docs/setup/cloud/oci.mdx#local-deployment) for initialization, planning, and apply, and [Clean Up](../docs-source/site/docs/setup/cloud/oci.mdx#clean-up) for teardown.

For direct IaC runs, `k8s_use_local_charts=false` selects the published chart version configured in `cfgmgt/apply.py`. The Resource Manager build vendors charts into the stack package; preserve the sibling chart layout when packaging or moving configuration management to another host.

## Storage and Recovery Internals

`modules/kubernetes/storage` owns the inventory shared by OCI volume provisioning, generated PVs, and chart storage settings. Update it when changing chart replica counts or storage requests. `cfgmgt/apply.py` applies the generated manifest before Helm installation. See [Primary Storage](../docs-source/site/docs/setup/cloud/oci.mdx#primary-storage) for storage behavior and migration instructions.

Root configuration supplies OKE, database, and network details to `modules/fsdr`. Auto-generated application labels use a separate persisted protection-group prefix available during planning; existing deployments retain their recorded group names.

Standard FSDR plan keys run in order: `failover`, `switchover`, `start_drill`, then `stop_drill`. Their dependencies serialize shared OKE backup setup while other stack resources run in parallel. State moves preserve existing standard plans. Custom regional-module plan keys retain their original addresses and run in the initial stage; use the standard keys when ordering is required.

The regional submodule supports:

- `plans[key].source_plan_id` for plan cloning.
- `executions[key].plan_id` to select an existing plan; otherwise the execution selects the plan with the same key.
- OKE `resource_modifier_mappings` for ConfigMaps describing destination resource changes.
- `block_volume_attach_and_mount_operations` for non-movable compute storage.

Resource outputs expose provider-computed plan groups, execution progress, and automatic execution details. The protection-group resource output is sensitive because it includes secret references; `dr_protection_group_id` exposes its identifier separately.

Use [Full Stack Disaster Recovery](../docs-source/site/docs/setup/cloud/oci.mdx#full-stack-disaster-recovery) for configuration, drills, recovery, and failback procedures.

## Running Tests

Use OpenTofu 1.12.6 to match the [IaC workflow](../.github/workflows/opentofu.yml).

Run the regression suites from `opentofu/` with Python 3 and OpenSSL installed:

```bash
tofu init -backend=false
python3 tests/run-mocked-plans.py
python3 -m unittest discover -s tests -p 'test_*.py'
```

Root suites live directly in `tests/`; child-module suites mirror their source paths under `tests/modules/`. The runner places each suite in its module's temporary `tests/` directory. The IaC workflow runs these commands and discovers every suite. Tests run in temporary copies with isolated inputs and state, using the initialized provider versions. Kubernetes image tests use a targeted mocked cluster setup, and generated-label tests persist a local random value; all assertions run as plans. OCI providers are mocked, and the suites execute no OCI operations or provisioners.

Python regression tests also inspect FSDR plan dependencies and state migrations using the initialized OCI provider, synthetic state, generated test keys, and refresh-disabled plans.

| Suite | Coverage |
|-------|----------|
| Root | Database modes, networking, load balancer access, Marketplace, configuration management, FSDR wiring |
| Network | Public/private subnet separation, CIDR allocation, gateway routes, default ingress |
| Kubernetes | CPU/ARM/GPU workers, image selection, add-ons, API access, IAM, generated Helm values and credentials |
| FSDR | Protection groups, plans, executions, Automatic DR |

To run one module, use `python3 tests/run-mocked-plans.py --module modules/kubernetes` (or `--module .` for the root).

The `tests/manual-test.sh` script validates configurations using your OCI credentials:

```bash
# Uses ~/.oci/config [DEFAULT] profile
./tests/manual-test.sh

# Use a specific profile
./tests/manual-test.sh MYPROFILE
```

For live provisioning coverage and evidence requirements, use [TEST-AGENT.md](../TEST-AGENT.md) with the [OCI deployment guide](../docs-source/site/docs/setup/cloud/oci.mdx).

## License

Copyright (c) 2024, 2026, Oracle and/or its affiliates.
Licensed under the Universal Permissive License (UPL), Version 1.0.
See [LICENSE](http://oss.oracle.com/licenses/upl) for details.
