# OCI Resource Manager Build Script

`oci_build.py` packages the repository's top-level `opentofu/` configuration into a ZIP file for OCI Resource Manager. By default, it vendors the local `obaas-prereqs` and `obaas` charts. Use `--remote-charts` to have the stack install the published charts instead.

## Usage

Run from the repository root:

```bash
python3 helm/infra-charts/tools/oci_build.py
```

The script can also be run from the tools directory:

```bash
cd helm/infra-charts/tools
./oci_build.py
```

The output is written to `helm/infra-charts/stage/oci_build.zip`.

To use published charts, add `--remote-charts`:

```bash
python3 helm/infra-charts/tools/oci_build.py --remote-charts
```

The remote-chart package does not include local chart files and sets `k8s_use_local_charts = false`. Resource Manager must be able to reach the Helm repository configured in `opentofu/cfgmgt/apply.py` when it applies the stack.

For a Marketplace build, add `--marketplace`:

```bash
python3 helm/infra-charts/tools/oci_build.py --marketplace
```

That creates `oci_marketplace_build.zip` and sets `mktpl_use_image = true` in the packaged stack.

## Package Contents

- The files from the repository's top-level `opentofu/` directory.
- By default, the local charts at `helm/infra-charts/obaas-prereqs` and `helm/infra-charts/obaas`, placed in the archive at `helm/infra-charts/` so `cfgmgt/apply.py` can locate them. This is omitted when `--remote-charts` is selected.
- `local_charts.auto.tfvars`, which sets `k8s_use_local_charts` according to the selected chart source.

For local charts, the builder adjusts `LOCAL_HELM_DIR` in the packaged `cfgmgt/apply.py` to resolve `../helm/infra-charts` relative to `cfgmgt/`. Both charts then resolve inside Resource Manager's extracted Terraform directory. The repository's original `opentofu/cfgmgt/apply.py` retains its repository-relative path.

The builder excludes Terraform/OpenTofu variable files, state, private keys, caches, and generated `stage/` directories. Helm is not required. In the default local-chart mode, both local charts must have a `Chart.yaml` file.

The builder enforces an 11 MB maximum ZIP size. The legacy `--local-charts` flag remains accepted for compatibility; local charts are already the default.
