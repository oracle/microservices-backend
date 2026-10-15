# SigNoz User Dashboards Sample Chart

Install custom user dashboards into an existing OBaaS SigNoz instance. Keep the
dashboard files and this chart in your application's repository so a Helm install
or upgrade repeats the import independently of the OBaaS platform release.

The chart follows the flow in
[`Job-signoz-setup.yaml`](../../infra-charts/obaas/templates/observability/Job-signoz-setup.yaml):
wait for SigNoz, discover its organization ID, log in, list existing dashboards,
delete exact title matches, and create dashboards from the bundled JSON files.
It uses a small Python standard-library importer to parse JSON reliably, including
minified exports and titles containing quotes or other special characters.
All containers use `container-registry.oracle.com/os/oraclelinux:9`, which includes Python 3 and
its SQLite module. No custom image or runtime package installation is needed.

## Add dashboards

1. Export your dashboard as JSON from the target SigNoz instance.
2. Copy the file directly into this chart's `dashboards/` directory.
3. Remove `dashboards/sample-application.json` when replacing the empty example.
4. Give every dashboard a unique title: `title` in V1 exports or
   `spec.display.name` in V2 exports.

Only `dashboards/*.json` is included; subdirectories and other extensions are
ignored. The importer supports both the OBaaS 2.1.0 V1 format (`version: "v4"`
or `"v5"`) and the newer V2/Perses format (`schemaVersion: "v6"`). It probes the
V2 dashboard list endpoint and falls back to V1 when V2 is unavailable, including
older SigNoz servers that return frontend HTML for unknown routes. Authentication
errors and malformed JSON responses are reported rather than triggering fallback.

Use a V1 export when the same files must run on both OBaaS 2.1.0 and the current
OBaaS 2.1.2 chart. Newer SigNoz converts V1 exports submitted to its V2 create
endpoint. The included empty sample uses V1/v5 for this reason. A V2 export works
only with newer SigNoz; on a V1 instance, the importer rejects it before deleting
any dashboards. Arbitrary V2-to-V1 conversion is not provided.

The V1-on-V2 create compatibility is a transitional SigNoz feature; for future
SigNoz upgrades, re-export dashboards in the supported format. See the
[SigNoz migration guide](https://signoz.io/docs/operate/migration/upgrade-0-135/).

Compatibility checks performed for this sample:

- OBaaS 2.1.0 / SigNoz v0.113.0: installed and upgraded a temporary copy of this
  chart on an existing Kubernetes instance. The Oracle Linux Job completed the
  health wait, read-only SQLite organization discovery, login, import, and
  replacement. The upgrade changed the dashboard ID and applied its updated
  description. The temporary release, retained hook Job, and dashboard were
  removed, and all pre-existing dashboard IDs were preserved.
- OBaaS 2.1.2's SigNoz v0.142.1: ran the importer in plain Oracle Linux 9 against
  an isolated SigNoz container. V1/v5 conversion, native V2 creation, and
  replacement passed. A real V1/v4 export from the older installation also
  converted successfully.

The complete Helm flow has been verified on OBaaS 2.1.0; the newer-version check
verifies the importer against isolated SigNoz v0.142.1, not a complete OBaaS 2.1.2
Helm deployment. The hook's health wait requires a healthy SigNoz instance,
including its ClickHouse connection.

Each file becomes its own ConfigMap. `orders.json` produces a ConfigMap named
`orders`, with the JSON stored in its `dashboard.json` key. Short, valid lowercase
names are preserved. Other names are normalized to lowercase letters, digits, and
hyphens; normalized or shortened names receive an eight-character hash of the
original filename stem. Names are limited to 63 characters, and rendering fails
if two generated names collide. ConfigMaps are projected into a single
`/dashboards` directory in the Job under the original filenames.

ConfigMap names deliberately follow filenames rather than the Helm release name.
Use distinct filenames across dashboard releases in the same namespace, and
avoid filenames that collide with existing ConfigMaps. Each JSON file must fit
within Kubernetes' 1 MiB ConfigMap data limit. Helm also stores the complete
release manifest in its release storage: one ConfigMap per file does not remove
that aggregate size constraint. Keep this sample small; use an importer image
containing the files for large dashboard collections.

## Configure the existing SigNoz instance

Install into the **same namespace as OBaaS**. The default configuration assumes an
OBaaS release called `obaas` and the existing `signoz-authn` Secret. Create an
environment values file outside the chart, for example `my-dashboards-values.yaml`:

```yaml
signoz:
  releaseName: obaas
  auth:
    existingSecret: signoz-authn
```

Change `releaseName` to your actual OBaaS release and `existingSecret` to the
credential Secret configured for that instance. The Secret must contain `email`
and `password`. This chart references it; it does not create or modify credentials.

By default, organization discovery follows the OBaaS setup Job's approach: an
Oracle Linux init container reads the organization ID from the SigNoz SQLite PVC
using Python's built-in SQLite module in read-only mode. The PVC
defaults to `signoz-db-<releaseName>-signoz-0`. Required pod affinity schedules the
Job on the SigNoz pod's node so it can mount the same PVC. The platform must be
healthy and the storage must support this access. Override
`signoz.orgDiscovery.pvcName` if your instance uses a different PVC name.

If your existing credential Secret also contains `orgID`, disable PVC discovery:

```yaml
signoz:
  releaseName: obaas
  auth:
    existingSecret: my-signoz-credentials
  orgDiscovery:
    enabled: false
```

With discovery disabled, the Job does not mount the SigNoz PVC or require pod
affinity. `signoz.url` can override the default
`http://<releaseName>-signoz:8080`. The Secret must still exist in the namespace
where this chart is installed.

For private registries, override `image.repository`, `image.tag`, and
`imagePullSecrets` as needed. The sample follows the full Oracle Linux `9` tag;
use an approved version tag for your own deployment. Slim images are not supported
unless they also contain `python3` with the `sqlite3` module.

## Render and install

Run from the repository root, after adding your JSON files:

```bash
helm lint helm/app-charts/signoz-dashboards \
  -f my-dashboards-values.yaml

helm template my-dashboards helm/app-charts/signoz-dashboards \
  -n <application-namespace> -f my-dashboards-values.yaml \
  > /tmp/my-dashboards-rendered.yaml

helm upgrade --install my-dashboards helm/app-charts/signoz-dashboards \
  -n <application-namespace> --set signoz.releaseName=<OBaaS release name> \
  --timeout 15m
```

The ConfigMaps are ordinary Helm resources. The import Job is a
`post-install,post-upgrade` hook, so it runs after those ConfigMaps are created or
updated. Helm waits for the hook to finish and reports an error if it fails.
The Job has a ten-minute overall deadline by default. Successful and failed Jobs
remain available for inspection; the next install or upgrade replaces the previous
hook Job.

## Replacement behavior

On every install or upgrade, the importer fetches all dashboard list pages and
deletes **every existing dashboard whose title exactly matches a bundled
`title` (V1) or `spec.display.name` (V2)**, including legacy records returned by
the V2 API. It then POSTs every bundled dashboard to the detected
`/api/v1/dashboards` or `/api/v2/dashboards` endpoint.

This is the same title-based replacement policy as the OBaaS system setup Job.
Use application-specific titles: a matching user or system dashboard will be
overwritten regardless of who created it. Replacement creates new dashboard IDs,
so existing links to those IDs can break. UI edits to matching dashboards are
lost at the next chart install or upgrade.

Dashboards with other titles are preserved. Removing a file or changing its title
does not delete the old dashboard in SigNoz. Uninstalling this chart removes its
ConfigMaps but does not remove imported dashboards. Hook Jobs are not managed as
ordinary release resources; delete the retained Job separately if needed.

Local JSON and duplicate titles are checked before deletion. API-side validation
still happens during creation; replacement is not transactional. A failed import
can leave matching dashboards deleted or only partially recreated. Fix the export
or configuration and rerun `helm upgrade --install`.

## Verify and troubleshoot

```bash
helm status my-dashboards -n <application-namespace>
kubectl get configmaps -n <application-namespace> \
  -l app.kubernetes.io/instance=my-dashboards
kubectl get jobs -n <application-namespace> \
  -l app.kubernetes.io/instance=my-dashboards
kubectl logs -n <application-namespace> job/my-dashboards-signoz-setup \
  -c signoz-setup
```

Open SigNoz and confirm the imported titles appear. For startup problems, inspect
the Job's pod events and the `wait-for-signoz` and `signoz-id-discovery` init
container logs. Check the service URL, credential Secret, PVC name, and SigNoz
pod labels. HTTP 400 during creation usually requires checking the exported
dashboard against the deployed SigNoz schema; HTTP 401/403 requires checking the
credentials and permissions.

