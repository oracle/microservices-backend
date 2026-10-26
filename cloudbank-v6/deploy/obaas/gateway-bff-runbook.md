# Deploy the CloudBank BFF on OKE/OBaaS

The BFF script creates or upgrades only the `gateway-bff-service` Helm release
and its own private OCIR image repository. It uses the existing `azn-server`,
`loan-application-service`, application namespace, and image pull Secret. It
does not alter the OBaaS platform release or create a public gateway route.

## One-time authorization-server preparation

The BFF needs its confidential OAuth client in the running `azn-server` pod.
The authorization-server deployment script provisions the client Secret keys
automatically. If `azn-server` was deployed before BFF support was added,
run `./cloudbank-v6/deploy/obaas/deploy-azn-server_v1.sh redeploy` once to register the
client. Otherwise no separate Secret setup is needed. The BFF deploy script
checks the registration and reports what is missing.

## BFF deployment

**Pre-requisites**: **Node.js 22.12+** is recommended.

From the repository root, run:

```bash
cd ./cloudbank-v6
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
cd ./cloudbank-v6
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

Then run `./cloudbank-v6/deploy/obaas/deploy-gateway-bff.sh render` and
`./cloudbank-v6/deploy/obaas/deploy-gateway-bff.sh deploy`, restart the BFF port-forward after
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
cd ./cloudbank-v6/src/cloudbank_ui && npm ci && npm run dev
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