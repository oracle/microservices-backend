# Import SigNoz Dashboards and Alerts

Use this chart to import dashboards, alerts, or both into an existing OBaaS
SigNoz instance.

## 1. Add your JSON files

**Dashboards**

- Export each dashboard as JSON from SigNoz.
- Copy the files into [`dashboards/`](dashboards/), one dashboard per file.
- Remove `dashboards/sample-application.json` if you do not want the sample.

**Alerts**

- Copy individual alert definitions into [`alerts/`](alerts/), following
  [`alerts/example.json`](alerts/example.json).
- To keep multiple alerts in one file, use an `alerts` array following the
  [inventory example](tests/fixtures/inventory.json), including its supported
  settings. Copy the whole inventory file into `alerts/`.
- Review namespace selectors, thresholds, enabled settings, and notification
  channel names for your environment.
- Create any referenced notification channels in SigNoz before importing. If
  using notification policies instead, configure routing in SigNoz and set
  `notificationSettings.usePolicy: true` in individual alert definitions.
- Remove `alerts/example.json` if you do not want the sample. Otherwise, it is
  imported disabled and uses notification policy routing.

Put `.json` files directly in these directories; subdirectories are not imported.
Use unique filenames, dashboard titles, and alert names. Keep credentials out of
the JSON files. Include at least one dashboard or alert file.

## 2. Install or update

Run from the repository root:

```bash
helm upgrade --install my-dashboards helm/app-charts/signoz-dashboards \
  --namespace <application-namespace> \
  --set signoz.releaseName=<OBaaS-release-name> \
  --set signoz.auth.existingSecret=signoz-authn \
  --timeout 15m
```

Use the same namespace as OBaaS. Set `signoz.releaseName` to your OBaaS release
name and `signoz.auth.existingSecret` to its existing SigNoz credential Secret,
which must contain `email` and `password`.

For example, with OBaaS release `obaas-tenant1` in namespace `tenant1`:

```bash
helm upgrade --install my-dashboards helm/app-charts/signoz-dashboards \
  --namespace tenant1 \
  --set signoz.releaseName=obaas-tenant1 \
  --set signoz.auth.existingSecret=signoz-authn \
  --timeout 15m
```

After editing or adding JSON files, rerun the same command with the same release
name. Keep your changes in the JSON files so future imports retain them.

## 3. Verify the import

Open SigNoz and confirm your dashboards and alerts appear. Review alert settings
and notification routing before enabling alerts, and test notification delivery.

If installation fails, check the release and import logs:

```bash
helm status my-dashboards -n <application-namespace>
kubectl logs -n <application-namespace> job/my-dashboards-signoz-setup \
  -c signoz-setup
```
