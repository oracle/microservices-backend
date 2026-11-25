---
title: Custom dashboards
sidebar_position: 5.5
---

Use the `helm/app-charts/signoz-dashboards` sample chart to install your own
dashboards into SigNoz and repeat the import with Helm upgrades. Keep your JSON
dashboard definitions with the chart in your application's source control.
Install it as a separate Helm release from the OBaaS platform release.

## Prerequisites

- A healthy OBaaS SigNoz instance, including its ClickHouse connection.
- Helm and `kubectl` configured for the target cluster.
- The namespace and Helm release name of your OBaaS instance.
- An existing SigNoz credential Secret containing `email` and `password`.

Install the dashboard chart in the same namespace as OBaaS. The default credential
Secret is `signoz-authn`; use the Secret configured for your instance if it has a
different name. See [Access SigNoz](./access.md) for connection and credential
instructions.

## Add your dashboard files

1. Export each custom dashboard as JSON from SigNoz.
2. Place each file directly in `helm/app-charts/signoz-dashboards/dashboards/`.
3. Remove `sample-application.json` when replacing the empty sample dashboard.
4. Give each dashboard a unique, application-specific title.

The chart includes only `dashboards/*.json`; it does not include subdirectories.
Each JSON file becomes a ConfigMap. For example, `orders.json` creates the
ConfigMap `orders`. Names are normalized when needed and shortened to at most
63 characters, with a hash suffix to distinguish changed names. Use distinct
filenames across dashboard releases in the same namespace because ConfigMap
names are based on filenames rather than Helm release names.

Each JSON file must fit within Kubernetes' 1 MiB ConfigMap data limit. The complete
chart must also fit within Helm's release storage limits; splitting files into
individual ConfigMaps does not remove the aggregate limit.

### Dashboard formats

The importer detects the dashboard API supported by the deployed SigNoz instance:

- Older instances, including OBaaS 2.1.0's SigNoz, use the V1 dashboard API and
  JSON exports with `version: "v4"` or `"v5"`. The dashboard title is `title`.
- Newer instances use the V2 API and Perses exports with `schemaVersion: "v6"`.
  The dashboard title is `spec.display.name`.

Use V1 exports when the same definitions need to run on both older and newer
instances. Newer SigNoz can convert V1 payloads submitted to its V2 create
endpoint. This compatibility is transitional; for future SigNoz upgrades,
re-export dashboards in the supported format. V2 files cannot be imported into a
V1 instance and are rejected before any dashboards are deleted.

## Configure the chart

Create a values file, for example `my-dashboards-values.yaml`, containing the
OBaaS release name and credential Secret reference:

```yaml
signoz:
  releaseName: obaas
  auth:
    existingSecret: signoz-authn
```

Replace `obaas` with your actual OBaaS platform release name, not the release name
you will use for the dashboard chart. Keep passwords out of the values file.

The Job runs a Python standard-library importer on
`container-registry.oracle.com/os/oraclelinux:9`. It waits for SigNoz, discovers
the organization through `/api/v2/sessions/context` using the credential Secret's
`email`, logs in, and imports dashboards through the detected dashboard API.

If the Secret contains a non-empty `orgID` key, that value takes precedence over
discovery. Accounts belonging to multiple organizations must supply this key to
select an organization explicitly. The Secret must contain `email` and `password`
in either case.

For private registries, configure `image.repository`, `image.tag`, and
`imagePullSecrets`. Replacement images must provide Python 3 and its standard
library. No runtime package installation is needed.

## Install and update dashboards

Run from the repository root. Use the same values file for rendering and installing:

```bash
helm lint helm/app-charts/signoz-dashboards \
  -f my-dashboards-values.yaml

helm template my-dashboards helm/app-charts/signoz-dashboards \
  -n <application-namespace> -f my-dashboards-values.yaml \
  > /tmp/my-dashboards-rendered.yaml

helm upgrade --install my-dashboards helm/app-charts/signoz-dashboards \
  -n <application-namespace> -f my-dashboards-values.yaml \
  --timeout 15m
```

The ConfigMaps are ordinary Helm resources. A `post-install,post-upgrade` hook Job
imports them after they are created or updated. Helm waits for the Job and reports
an error if it fails. Successful and failed Jobs remain available for inspection;
the next install or upgrade replaces the previous hook Job.

To apply dashboard changes, edit or replace the JSON files and run the same
`helm upgrade --install` command again. This upgrades the dashboard release; it
does not upgrade the OBaaS platform or replace the SigNoz installation.

## Replacement and removal behavior

On every install or upgrade, the importer deletes all existing dashboards whose
titles exactly match the bundled titles, then creates dashboards from the JSON
files. Other titles are preserved. Local JSON and duplicate titles are checked
before deletion, but creation can still fail server-side if a payload is invalid.
Replacement is not transactional; fix any failed import and rerun the upgrade.

:::important
A title match replaces the dashboard regardless of who created it. Avoid titles
used by [OBaaS system dashboards](./dashboards.md) or other users. Replacement
creates new dashboard IDs, which can break links, and overwrites UI edits to the
matching dashboards.
:::

If you remove a JSON file and upgrade the chart, Helm removes its ConfigMap, but
the dashboard remains in SigNoz. **Delete that dashboard manually in the SigNoz
UI when you no longer need it.** Changing a dashboard's title also leaves the old
dashboard for manual cleanup.

Uninstalling the dashboard chart removes its ConfigMaps but leaves the imported
dashboards in SigNoz. The retained hook Job can be deleted separately:

```bash
helm uninstall my-dashboards -n <application-namespace>
kubectl delete job my-dashboards-signoz-setup -n <application-namespace> \
  --ignore-not-found
```

## Verify and troubleshoot

```bash
helm status my-dashboards -n <application-namespace>
kubectl get jobs -n <application-namespace> \
  -l app.kubernetes.io/instance=my-dashboards
kubectl logs -n <application-namespace> job/my-dashboards-signoz-setup \
  -c signoz-setup
```

Open SigNoz and confirm your dashboard titles appear. If the Job does not start,
inspect its pod events and the `signoz-setup` container logs. Check image pulls,
SigNoz and ClickHouse health, the service URL, the credential Secret, and any
explicit `orgID` selection. HTTP 400 during
creation indicates the exported JSON needs checking against the deployed schema;
HTTP 401 or 403 indicates a credential or permission problem.
