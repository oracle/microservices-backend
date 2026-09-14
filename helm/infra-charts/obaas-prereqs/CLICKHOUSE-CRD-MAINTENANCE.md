# ClickHouse Operator CRD Maintenance

## Overview

The ClickHouse Operator CRDs are installed as part of `obaas-prereqs` chart but the actual operator runs in each tenant namespace via the SigNoz subchart.

**Why this architecture?**
- CRDs are cluster-scoped resources (not namespaced)
- Installing them once in prereqs prevents conflicts between multiple tenant installations
- Each tenant gets their own namespace-scoped operator via SigNoz
- Similar pattern to other operators in this chart (Strimzi, Oracle Database Operator, etc.)

## Current CRD Version

**Operator Version:** 0.25.5
**Last Updated:** 2025-11-10

The following CRD files are maintained in `templates/`:
- `CustomResourceDefinition-clickhouseinstallations.clickhouse.altinity.com.yaml`
- `CustomResourceDefinition-clickhouseinstallationtemplates.clickhouse.altinity.com.yaml`
- `CustomResourceDefinition-clickhousekeeperinstallations.clickhouse-keeper.altinity.com.yaml`
- `CustomResourceDefinition-clickhouseoperatorconfigurations.clickhouse.altinity.com.yaml`

## How to Update CRDs

When updating to a new version of the ClickHouse Operator (e.g., to match a SigNoz upgrade):

### 1. Check the target operator version

Look at the SigNoz chart dependency or the version you want to target:

```bash
# Check SigNoz's embedded operator version
helm show values signoz/signoz | grep "clickhouseOperator:" -A 5

# Or check latest available versions
helm repo add altinity https://helm.altinity.com
helm repo update
helm search repo altinity/altinity-clickhouse-operator --versions
```

### 2. Extract CRDs from the operator chart

```bash
# Set the version you want to extract
OPERATOR_VERSION="0.25.5"

# Download the chart
cd /tmp
helm pull altinity/altinity-clickhouse-operator --version ${OPERATOR_VERSION}

# Extract CRDs
tar -xzf altinity-clickhouse-operator-${OPERATOR_VERSION}.tgz \
    altinity-clickhouse-operator/crds/

# List extracted CRDs
ls -la altinity-clickhouse-operator/crds/
```

### 3. Copy CRDs to the templates directory

```bash
# Navigate to obaas-prereqs
cd /path/to/obaas/helm_v2/obaas-prereqs

# Backup old CRDs (optional)
mkdir -p .crd-backups
cp templates/CustomResourceDefinition-*.yaml .crd-backups/ 2>/dev/null || true

# Copy new CRDs
cp /tmp/altinity-clickhouse-operator/crds/*.yaml templates/

# Verify
ls -1 templates/CustomResourceDefinition-*.yaml
```

### 4. Verify compatibility

```bash
# Test template rendering
helm template test . --namespace test

# Check for errors
echo $?  # Should be 0
```

### 5. Update this document

Update the "Current CRD Version" section at the top with:
- New operator version
- Date of update
- Any breaking changes or notes

### 6. Test the upgrade

Before deploying to production:

```bash
# Test in a development cluster
helm upgrade obaas-prereqs . \
  --namespace obaas-system \
  --dry-run --debug

# Check CRD diff
kubectl diff -f templates/CustomResourceDefinition-clickhouseinstallations.clickhouse.altinity.com.yaml
```

## Important Notes

### CRD Upgrade Considerations

- **CRDs are NOT automatically deleted** when uninstalling the chart (Helm best practice)
- **Manual CRD deletion required** if you need to remove them completely:
  ```bash
  kubectl delete crd clickhouseinstallations.clickhouse.altinity.com
  kubectl delete crd clickhouseinstallationtemplates.clickhouse.altinity.com
  kubectl delete crd clickhousekeeperinstallations.clickhouse-keeper.altinity.com
  kubectl delete crd clickhouseoperatorconfigurations.clickhouse.altinity.com
  ```

- **Version compatibility**: Ensure the CRD version matches or is compatible with the operator versions deployed in tenant namespaces via SigNoz

### Troubleshooting

**Problem:** CRD already exists error during install
```
Error: INSTALLATION FAILED: rendered manifests contain a resource that already exists
```

**Solution:** CRDs already installed. Either:
1. Skip CRD installation: `helm upgrade --install --skip-crds ...`
2. Use `kubectl apply` to update CRDs manually
3. Use `helm upgrade` instead of `helm upgrade --install`

**Problem:** Operator version mismatch
```
Warning: ClickHouseInstallation spec contains unknown fields
```

**Solution:** CRD version doesn't match operator version. Update CRDs following steps above.

## Related Files

- **Pre-delete hook:** `../obaas/templates/observability/clickhouse-pre-delete-hook.yaml`
  - Removes finalizers from ClickHouseInstallation resources before helm uninstall
  - Prevents namespace from getting stuck in Terminating state

## References

- [Altinity ClickHouse Operator Releases](https://github.com/Altinity/clickhouse-operator/releases)
- [Altinity Helm Charts](https://github.com/Altinity/helm-charts)
- [Helm Chart: altinity-clickhouse-operator](https://artifacthub.io/packages/helm/altinity-clickhouse-operator/altinity-clickhouse-operator)
- [SigNoz Helm Chart](https://github.com/SigNoz/charts)
