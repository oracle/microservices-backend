---
title: Custom dashboards and alerts
sidebar_position: 5.5
---

Use `helm/app-charts/signoz-dashboards` to import your own dashboards and alerts
into an existing OBaaS SigNoz instance. Install it as a separate Helm release in
the same namespace as OBaaS.

## 1. Prepare your JSON files

**Dashboards**

1. Export each dashboard as JSON from SigNoz.
2. Copy the files into `helm/app-charts/signoz-dashboards/dashboards/`.
3. Remove `sample-application.json` if you do not want the sample dashboard.

**Alerts**

1. Add your alert definitions to `helm/app-charts/signoz-dashboards/alerts/`,
   using the included `example.json` as a template. For multiple alerts in one
   file, follow the inventory format in the chart's `tests/fixtures/inventory.json`.
2. Set namespace selectors, thresholds, and enabled settings for your environment.
3. Create referenced notification channels in SigNoz. For individual alert
   definitions using routing policies, set `notificationSettings.usePolicy: true`
   and configure a matching policy in SigNoz instead.
4. Remove `alerts/example.json` if you do not want the sample alert. Otherwise,
   it is imported disabled and uses notification policy routing.

Use unique filenames, dashboard titles, and alert names. Only `.json` files
directly inside these directories are imported. Include at least one dashboard or
alert file, and keep credentials out of the files.

## 2. Install or update

You need Helm, access to the cluster, and a healthy OBaaS SigNoz instance. See
[Access SigNoz](./access.md) for connection and credential instructions.

From the repository root, run:

```bash
helm upgrade --install my-dashboards helm/app-charts/signoz-dashboards \
  --namespace <application-namespace> \
  --set signoz.releaseName=<OBaaS-release-name> \
  --set signoz.auth.existingSecret=signoz-authn \
  --timeout 15m
```

Use the OBaaS namespace and platform release name. Change `signoz-authn` if your
SigNoz credential Secret has another name; it must contain `email` and `password`.

After changing your JSON files, rerun the same command with the same release name.
Matching dashboard titles are replaced, and alerts managed by this release are
updated. Keep edits in the JSON files because imports overwrite changes made in
SigNoz. Choose names that do not conflict with existing dashboards or alerts.

Removing files or uninstalling this chart leaves imported dashboards and alerts
in SigNoz. Delete unwanted items in SigNoz.

## 3. Verify

Open SigNoz and confirm the imported dashboards and alerts appear. Review alert
settings and test notification routing before enabling alerts.

If the import fails, inspect the release and import logs:

```bash
helm status my-dashboards -n <application-namespace>
kubectl logs -n <application-namespace> job/my-dashboards-signoz-setup \
  -c signoz-setup
```
