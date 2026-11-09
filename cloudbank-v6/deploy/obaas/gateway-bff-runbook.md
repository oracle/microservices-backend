# Deploy the CloudBank BFF on OKE/OBaaS

The BFF script creates or upgrades only the `gateway-bff-service` Helm release
and its own private OCIR image repository. It uses the existing `azn-server`,
`loan-application-service`, application namespace, and image pull Secret. It
does not alter the OBaaS platform release or create a public gateway route.

## One-time authorization-server preparation

The BFF needs its confidential OAuth client in the running `azn-server` pod.
The authorization-server deployment script provisions the client Secret keys
automatically. If `azn-server` was deployed before BFF support was added,
run `./deploy/obaas/deploy-azn-server_v1.sh redeploy` once to register the
client. Otherwise no separate Secret setup is needed. The BFF deploy script
checks the registration and reports what is missing.

## Trace configuration

Trace uses the authorized loan workspace's application/workflow/trace IDs.
`TraceReadService` queries only that trace's waterfall through SigNoz's
v0.134.0 read API. The response contains at most 100 recorded spans and approved
attributes, with timing, status, truncation and missing-span indicators.
Correlation remains available when span access is unconfigured or denied.
The browser has no generic telemetry proxy or API key. See the
[Trace contract](../../docs/ui/minimum-bff-api.md#implemented-trace-read-increment-2026-11-06).

### 1. Select the existing OKE deployment

Run the commands from the repository root on an operator workstation with OKE
access. The existing `.env` must already contain `CLOUDBANK_KUBECONFIG_PATH`,
`MICROTX_NAMESPACE`, image-pull and OCIR configuration used by the
[BFF deployment runbook](../../deploy/obaas/gateway-bff-runbook.md).
The commands require `kubectl`, the OCI CLI/authentication used by the kubeconfig,
Helm, Docker with Buildx, and `jq`. The operator needs permission to
create/patch Secrets and deploy the BFF in the application namespace, plus
administrative access to SigNoz for API-key provisioning.

```bash
export BFF_KUBECONFIG="$(sed -n 's/^CLOUDBANK_KUBECONFIG_PATH=//p' .env)"
export BFF_NAMESPACE="$(sed -n 's/^MICROTX_NAMESPACE=//p' .env)"
: "${BFF_KUBECONFIG:?Set CLOUDBANK_KUBECONFIG_PATH in .env}"
: "${BFF_NAMESPACE:?Set MICROTX_NAMESPACE in .env}"
export BFF_KUBE_CONTEXT="$(kubectl --kubeconfig "$BFF_KUBECONFIG" config current-context)"

kubectl --kubeconfig "$BFF_KUBECONFIG" config get-contexts
printf 'Target context: %s\nTarget namespace: %s\n' "$BFF_KUBE_CONTEXT" "$BFF_NAMESPACE"
```

Confirm these are the intended OKE context and namespace before continuing.
If this BFF uses explicit `BFF_KUBECONFIG`, `BFF_NAMESPACE` or `BFF_KUBE_CONTEXT`
overrides, export those values instead. Every following cluster command pins
the selected kubeconfig, context and namespace.

For the existing OBaaS installation, check the SigNoz Service and its ports:

```bash
kubectl --kubeconfig "$BFF_KUBECONFIG" --context "$BFF_KUBE_CONTEXT" \
  -n "$BFF_NAMESPACE" get service obaas-signoz \
  -o 'custom-columns=NAME:.metadata.name,PORTS:.spec.ports[*].port'
```

This procedure uses `obaas-signoz` port `8080`, as verified for the installed
SigNoz v0.134.0. Substitute the actual Service/namespace if your OBaaS release
uses different names.

### 2. Open SigNoz and generate a Viewer API key

In a separate terminal, repeat the exports from step 1, then keep this tunnel
running:

```bash
kubectl --kubeconfig "$BFF_KUBECONFIG" --context "$BFF_KUBE_CONTEXT" \
  -n "$BFF_NAMESPACE" port-forward --address 127.0.0.1 \
  service/obaas-signoz 3301:8080
```

Open `http://127.0.0.1:3301` and sign in using your existing SigNoz administrator
credentials. A bootstrap Secret such as `cloudbankai-signoz`, with fields
`email` and `password`, supplies login credentials; neither field is a query
API key for the BFF.

API-key issuance is the manual SigNoz step:

1. Open the bottom-left **Settings** menu and select **Workspace Settings**.
   The dropdown itself contains workspace/account links.
2. In the workspace settings page, select **Service Accounts** in the settings
   navigation, click **New Service Account**, and create `cloudbank-bff-trace`.
   With the tunnel above, the direct URL is
   `http://127.0.0.1:3301/settings/service-accounts`.
3. Open its **Overview**, assign **`signoz-viewer`** and save.
4. Open **Keys → Add Key**, name the key `cloudbank-bff-trace`, and create it.
5. Keep the generated value available for the hidden prompt in section 3 below; SigNoz
   shows it only once.

The navigation and `/settings/service-accounts` route are present in the
[SigNoz v0.134.0 settings source](https://github.com/SigNoz/signoz/blob/v0.134.0/frontend/src/pages/Settings/Settings.tsx)
and [route definitions](https://github.com/SigNoz/signoz/blob/v0.134.0/frontend/src/constants/routes.ts).
If the direct page reports access denied, check the signed-in SigNoz account's
permissions. If it does not exist, confirm the running SigNoz frontend version
before continuing with instructions for a different release.

The account/key must have read access only. See the official
[SigNoz service-account instructions](https://signoz.io/docs/manage/administrator-guide/iam/service-accounts/).
Kubernetes Secret creation stores an already issued key; it does not create a
SigNoz API key or assign its role.

### 3. Store the API key in a dedicated Kubernetes Secret

From the repository root, run:

```bash
./deploy/obaas/store-bff-signoz-api-key.sh
```


### 4. Persist the BFF configuration in `.env`

Edit the protected repository-root configuration:

```bash
vi .env
```

Add or replace these entries, keeping exactly one occurrence of each:

```dotenv
BFF_SIGNOZ_API_KEY_SECRET_NAME=cloudbank-bff-signoz-api
BFF_SIGNOZ_API_KEY_SECRET_KEY=api-key
```

`BFF_SIGNOZ_API_KEY_SECRET_KEY` is the field name inside the Secret, not the API
key value. The deploy helper detects a unique SigNoz Service on port `8080` in
the BFF namespace when these references are supplied.

If explicit routing is needed, also set `BFF_SIGNOZ_BASE_URL` to the internal
cluster URL, for example `http://obaas-signoz.<application-namespace>.svc:8080`
with the actual namespace substituted. This setting is required when SigNoz
runs in another namespace or service detection is ambiguous. The BFF pod must
be able to reach this address; `127.0.0.1:3301` is only the workstation tunnel.

Optionally set `BFF_SIGNOZ_PUBLIC_URL=http://127.0.0.1:3301` for the GUI's
**Open SigNoz** link while using this tunnel, or use your existing browser-facing
SigNoz HTTPS URL. The link is optional and span reads do not depend on it.
These URLs must not include credentials, query parameters or fragments.
API key values stay in the Secret; the chart supplies `BFF_SIGNOZ_API_KEY`
through `secretKeyRef`. Host-based BFF execution can receive that server-only
environment variable through the operator's secure secret-injection mechanism.

### 5. Rebuild and redeploy the BFF

From the repository root, using the original terminal and its target exports:

```bash
./deploy/obaas/deploy-gateway-bff.sh render
./deploy/obaas/deploy-gateway-bff.sh deploy

kubectl --kubeconfig "$BFF_KUBECONFIG" --context "$BFF_KUBE_CONTEXT" \
  -n "$BFF_NAMESPACE" rollout status deployment/gateway-bff-service --timeout=5m

kubectl --kubeconfig "$BFF_KUBECONFIG" --context "$BFF_KUBE_CONTEXT" \
  -n "$BFF_NAMESPACE" get pods -l app.kubernetes.io/name=gateway-bff-service
```

The deploy command builds/pushes the updated BFF image to OCIR and upgrades its
existing Helm release. It requires the existing Docker/OCI configuration from
the BFF runbook. If you override `BFF_IMAGE`/`BFF_BUILD_PUSH`, follow that
runbook's instructions for publishing and selecting an updated immutable image.

Check only the configured API-key reference, without reading its value:

```bash
kubectl --kubeconfig "$BFF_KUBECONFIG" --context "$BFF_KUBE_CONTEXT" \
  -n "$BFF_NAMESPACE" get deployment gateway-bff-service \
  -o 'go-template={{range .spec.template.spec.containers}}{{range .env}}{{if eq .name "BFF_SIGNOZ_API_KEY"}}{{.valueFrom.secretKeyRef.name}}{{"/"}}{{.valueFrom.secretKeyRef.key}}{{"\n"}}{{end}}{{end}}{{end}}'
```

Expected output: `cloudbank-bff-signoz-api/api-key`.

### 6. Open the updated GUI and check Trace

For the existing local Vite/OKE browser setup, run the following in **three
separate terminals**, from the repository root. Repeat the target exports from
step 1 in terminals A and B, retaining the same selected context and namespace.
Keep both tunnels running and restart the BFF tunnel after its rollout:

```bash
# Terminal A: authorization server
kubectl --kubeconfig "$BFF_KUBECONFIG" --context "$BFF_KUBE_CONTEXT" \
  -n "$BFF_NAMESPACE" \
  port-forward --address 127.0.0.1 service/azn-server 8080:8080
```

```bash
# Terminal B: BFF
kubectl --kubeconfig "$BFF_KUBECONFIG" --context "$BFF_KUBE_CONTEXT" \
  -n "$BFF_NAMESPACE" \
  port-forward --address 127.0.0.1 service/gateway-bff-service 8089:8089
```

```bash
# Terminal C: updated GUI; use Node.js 22.12+ for the current Vite toolchain
cd src/cloudbank_ui
npm ci
VITE_DATA_MODE=api npm run dev
```

For a separately hosted SPA, publish the current frontend through its existing
deployment process instead. The BFF helper deploys the BFF only.

Open `http://127.0.0.1:5173`, sign in again, select an application, and open
**Explore Application → Trace**. Correlation IDs should be available for the
authorized application; spans appear only if SigNoz retained data for that
exact trace ID. An empty span list can mean the trace was not collected or has
expired. `TELEMETRY_NOT_CONFIGURED` indicates missing API URL/key configuration;
`TELEMETRY_ACCESS_DENIED` indicates a rejected key or insufficient permissions;
`TELEMETRY_API_UNAVAILABLE` indicates the configured trace API is unavailable.
Enabling read access does not backfill telemetry from previous executions.

No loan/schema/workflow migration is required for Trace. Collection, correlation
propagation, retention and actual API access remain target-environment
dependencies. The implementation was compiled/built; this documentation update
did not create a Secret, query authenticated traces or deploy to OKE.
## BFF deployment

**Pre-requisites**: **Node.js 22.12+** is recommended.

From the repository root, run:

```bash
./deploy/obaas/deploy-gateway-bff.sh deploy
```

The script reads `CLOUDBANK_KUBECONFIG_PATH`, `MICROTX_NAMESPACE`,
`IMAGE_PULL_SECRET`, and OCIR credentials from `.env`. It derives the BFF image
repository and issuer from the running `azn-server`, creates a unique immutable
image tag, ensures its private OCIR repository exists, logs in to OCIR using
an isolated temporary Docker config that retains the active context and Buildx
plugin, builds and pushes the image, then waits
for the BFF rollout. Repeating the command updates the same Helm release;
it does not create a second Service or Deployment.
Helm 4 upgrades reconcile chart-rendered fields with
`--server-side=true --force-conflicts` when those flags are supported, including
issuer values previously edited through `kubectl set env`. Helm 3 uses its
standard upgrade arguments. The selected mode is displayed before the build.

To inspect the rendered chart first, run:

```bash
./deploy/obaas/deploy-gateway-bff.sh render
```

Shell `BFF_*` variables override matching `.env` entries. Set
`BFF_IMAGE_TAG` to use the exact same image tag for `render` and `deploy`;
change or unset it before a later build to keep published tags immutable. You can
set `BFF_IMAGE` and `BFF_BUILD_PUSH=false` to deploy an image already published
in OCIR. For an HTTPS browser origin, set `BFF_CALLBACK_URI` in `.env` before
the one-time `azn-server` deployment and retain the default secure cookie.
The BFF and `azn-server` must use the same callback URI. The default HTTP
callback is only for the local Vite test and automatically selects
`BFF_COOKIE_SECURE=false`.
The deploy script also checks that the running loan service validates the same
issuer as `azn-server`; otherwise its application-list request would reject a
valid BFF user token.
The live issuer must also match `AZN_ISSUER_URI` in `.env`. The configured
issuer identifies tokens; the BFF still calls token, userinfo, and JWKS endpoints
through the internal Azn Service. If an older BFF or loan deployment expects the
cluster issuer while Azn publishes `http://localhost:8080`, redeploy CloudBank
services first and then the BFF. Start a fresh login after the rollouts; callback
URLs containing an authorization code must not be reused.

## HUMAN task support

The review increment requires a rebuilt/redeployed BFF and the updated local SPA;
the workflow definition and loan/ingest services need no changes for this feature.
`deploy-gateway-bff.sh` copies the cluster-reachable `MICROTX_WORKFLOW_URL` from
the existing loan Deployment into `BFF_MICROTX_BASE_URL`. Override the API base
with `BFF_MICROTX_BASE_URL` in `.env` or the shell when needed. A browser tunnel
such as `127.0.0.1:9010` is not the correct URL inside the BFF pod.
The deploy script accepts either the service context root (`/workflow-server`)
or the API base (`/workflow-server/api`), with an optional trailing slash, and
normalizes the value passed to the BFF so that `/api` appears exactly once.
The chart uses the internal Azn token URI and references the existing
`cloudbank-ai-azn-auth` / `microtx-client-secret`; it never renders its value.
`BFF_MICROTX_CLIENT_ID` defaults to `microtx-workflow-client`. If no workflow URL
is configured, review returns a safe `503` and intake remains available.

The current `azn-server` demo bootstrap provisions `obaas-admin` with
`ROLE_ADMIN,ROLE_CONFIG_EDITOR,ROLE_USER,ROLE_UNDERWRITER`. A clean demo installation
is ready for HUMAN review without a separate role-change command. With bootstrap
enabled, startup also adds missing baseline roles to existing demo accounts,
preserving password hashes, stable identity and any additional grants.
For an existing installation using an older authorization-server image, rebuild
and redeploy it once with `./deploy/obaas/deploy-azn-server_v1.sh redeploy`.
For a new installation, the normal authorization-server `first-deploy` includes
these roles. The BFF still verifies the explicit signed UNDERWRITER grant;
the general ADMIN role hierarchy remains unchanged.
After the upgrade, use a fresh authorization-server login (for example a private
browser window) so the BFF receives a token containing the updated roles.
User management stays internal; `/user/api/v1*` is never publicly routed.

Then run `./deploy/obaas/deploy-gateway-bff.sh render` and
`./deploy/obaas/deploy-gateway-bff.sh deploy`, restart the BFF port-forward after
rollout if needed, and reload Vite. Open **Manual review**, select a pending task,
edit the three completion fields and submit. Both APPROVED and REJECTED complete
the HUMAN task as COMPLETED; decision-service still owns the final outcome.
The queue/detail/completion checks are covered by local tests. This change has
not completed or rejected any live HUMAN task as part of validation.

## Local browser test

- Replace `<CLOUDBANKAI_NAMESPACE>` with your namespace in each port-forward terminal, and keep the following processes running in separate terminals:


```bash
# Terminal 1: authorization server
export KUBE_CONTEXT="$(kubectl config current-context)"
export MICROTX_NAMESPACE='<CLOUDBANKAI_NAMESPACE>'
kubectl --context "$KUBE_CONTEXT" --namespace "$MICROTX_NAMESPACE" \
  port-forward --address 127.0.0.1 service/azn-server 8080:8080
```

```bash
# Terminal 2: BFF
export KUBE_CONTEXT="$(kubectl config current-context)"
export MICROTX_NAMESPACE='<CLOUDBANKAI_NAMESPACE>'
kubectl --context "$KUBE_CONTEXT" --namespace "$MICROTX_NAMESPACE" \
  port-forward --address 127.0.0.1 service/gateway-bff-service 8089:8089
```

- install the npm env node 22.x+ if not yet done:

```bash
# Terminal 3: Web GUI
nvm install 22
nvm alias default 22
nvm use 22
```

- run the web front-end

```bash
# Terminal 3: Web GUI
cd src/cloudbank_ui && npm ci && npm run dev
```

- Open `http://127.0.0.1:5173`, select **Sign in with CloudBank**, and sign in
as `obaas-admin`. The **Applications** view loads the current authorized
records from the loan service through the BFF. Refresh, status filtering,
pagination, and sign-out use the live BFF. **New application** registers
application and document metadata with deferred dispatch, then keeps the page
open for individual **Upload** actions and **Start processing**. Each successful
upload stores actual PDF bytes in the loan service and shows received status.
Start acceptance means scheduling, not workflow completion or approval. Return
to the application list and refresh to see the assigned workflow ID.
Complete this flow on the same page; reopening existing applications is outside
this increment. Deploy the updated BFF and loan service for upload/release and
release-retry reconciliation. The deployed Azn/BFF OAuth client must grant
`cloudbank.write`; sign in again after upgrading from the read-only client.
The Vite proxy exposes BFF endpoints on the GUI's browser origin. To explore the
full simulated workspace, restart Vite with:

  ```bash
  VITE_DATA_MODE=mock npm run dev
  ```


