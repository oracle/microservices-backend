# CloudBank Gateway BFF

Copyright (c) 2026, Oracle and/or its affiliates. Licensed under UPL 1.0.

This Spring Boot service implements authentication/session, the authorized
application list, deferred application creation, individual PDF upload, and
explicit workflow release, and HUMAN manual review from
[the browser API specification](../../docs/ui/minimum-bff-api.md).
The live Vite UI supports creation, upload, and start for a new application in
one page flow. Existing applications open the nine-tab workspace with Overview,
Documents/PDF preview, three AI task results, Decision, Policy Evidence,
geographic Risk Signals, Workflow, recorded application Audit events and Trace
correlation/span reads. Additional document registration remains planned.
Explanation Draft is excluded. The Vite development
proxy makes `/bff` available on the same origin.

| Browser endpoint | Behavior |
| --- | --- |
| `GET /bff/auth/login` | Starts authorization-code login with PKCE. |
| `GET /bff/auth/callback` | OIDC callback; checks the signed access token, the existing `obaas-admin` identity, `ROLE_ADMIN`, principal mapping, and read scope. Redirects to `/demo`. |
| `GET /bff/api/v1/session` | Returns the safe profile, session expiry, and session-bound CSRF token. |
| `POST /bff/auth/logout` | Requires CSRF; invalidates the session and clears `CBBFFSESSION`. |
| `GET /bff/api/v1/applications` | Relays the server-held user token to `loan-application-service`; returns only approved list fields. |
| `POST /bff/api/v1/applications` | Requires CSRF, write scope, and `Idempotency-Key`; creates metadata with `DEFERRED` workflow start and `EXPECTED` documents. Returns `202`, safe IDs/correlation, and a browser-relative Location. |
| `PUT /bff/api/v1/applications/{applicationId}/documents/{documentId}/content` | Requires CSRF, write scope, and `Idempotency-Key`; forwards one raw PDF body to its authorized loan-service document ID. Returns stored length, digest, status, and correlation. |
| `GET /bff/api/v1/applications/{applicationId}` | Requires the admitted session and read scope. Checks application access through the loan owner, then composes all nine sections, including Audit and Trace. Trace uses only the owner-correlated ID and has independent span availability. Independent read failures stay within their section. |
| `GET /bff/api/v1/applications/{applicationId}/documents/{documentId}/content` | Requires the admitted session and read scope. Returns a bounded immutable PDF through the user-authorized loan endpoint, with inline filename and private/no-store headers. |
| `POST /bff/api/v1/applications/{applicationId}/workflow-start` | Requires CSRF, write scope, and an empty body; releases the existing loan outbox. Returns `202` and the canonical dispatch summary. |
| `GET /bff/api/v1/manual-review/tasks` | Authorized pending CloudBank v1 HUMAN queue; pagination after filtering. |
| `GET /bff/api/v1/manual-review/tasks/{taskId}` | Rechecks the task, workflow and authorized application; returns bounded details, outcomes and form defaults. |
| `POST /bff/api/v1/manual-review/tasks/{taskId}/resolution` | Requires CSRF, write scope, explicit UNDERWRITER role and `Idempotency-Key`; completes the HUMAN task with server-derived reviewer identity. |

Creation forwards only the documented input fields and rejects extra technical
fields. Amount and term are parsed on the server; optional blank country,
postal code, and policy version become absent values. Loan-service validation
remains authoritative, including its requirement for at least one document
metadata row. Creation accepts metadata only and leaves workflow dispatch deferred.
Retries forward the same logical idempotency key to the loan owner. Downstream
errors are mapped to fixed safe messages; raw response bodies are excluded.

Upload reads at most 25 MiB plus one overflow byte, including requests with no
Content-Length. Empty and oversized bodies return `413`; unsupported media types
return `415`. The loan service owns authorization, durable PDF BLOBs, digest,
and immutable-content handling. Identical retries succeed; different replacement
bytes conflict. The BFF never sends PDFs to MicroTx or performs extraction.
Workflow release calls only the loan-service boundary. Acceptance is scheduling,
not execution completion or a lending outcome. Repeated release reconciles an
already pending, dispatching, retrying, or started outbox without duplicate starts.

The BFF keeps the OAuth client secret and user tokens on the server. Sessions
are in pod memory, so the OKE chart uses one replica and a deployment restart
signs users out. Cookie settings are HttpOnly, SameSite=Lax, Secure by default;
set `BFF_COOKIE_SECURE=false` only for local HTTP port-forward testing.
The BFF access token lasts at most 30 minutes. The session response reports
the earlier of its HTTP-session expiry and token expiry; expired tokens require
a fresh login.
The service exposes only an internal ClusterIP Service. It does not route the
authorization server's `/user/api/v1*` endpoints to the browser.

The OIDC client is registered in `azn-server` only when both
`AZN_AUTHORIZATION_SERVER_BFF_CLIENT_SECRET` and
`AZN_AUTHORIZATION_SERVER_BFF_CLIENT_REDIRECT_URI` are configured. It uses
`cloudbank-bff-client`, the exact callback URI, `openid`, `cloudbank.read`, and `cloudbank.write`,
client-secret basic authentication, and required PKCE. The server's deployed
issuer must equal `BFF_ISSUER_URI`. The browser must reach
`BFF_AUTHORIZATION_URI`; token, JWKS, and UserInfo URIs are cluster-internal.
Deploy the updated authorization server and BFF together, then sign in again
to obtain the write scope; existing read-only sessions cannot create records.

Run the module tests with `mvn -f src/gateway-bff-service/pom.xml test`.
For OKE publication and repeatable deployment, see
[the BFF runbook](../../deploy/obaas/gateway-bff-runbook.md).

## HUMAN manual review

The form submits exactly `decisionOutcome` (`APPROVED` or `REJECTED`),
`reasonCode` (`[A-Z0-9_:-]{3,120}`), and `policySection`
(`CBPL-[0-9]{3}-S[0-9]+`). The BFF rejects unknown fields, verifies the signed
`ROLE_UNDERWRITER` grant, derives `reviewerPrincipalId` from `cb_principal_id`,
and adds `reviewerRole=UNDERWRITER`. Both outcomes use MicroTx task status
`COMPLETED`. Defaults match `complete-manual-review.sh`.

Configure `BFF_MICROTX_BASE_URL` with the full cluster-reachable `/workflow-server/api`
base, `BFF_MICROTX_TOKEN_URI` with the internal token endpoint,
`BFF_MICROTX_CLIENT_ID` (default `microtx-workflow-client`) and
`BFF_MICROTX_CLIENT_SECRET` through a Kubernetes Secret. Client-credentials tokens
are cached/refreshed server-side with scope `microtx.workflow`. The initial
integration reuses the existing MicroTx operator client; browser authorization
is independently enforced by the BFF. Missing MicroTx configuration affects only
review operations, which return a safe `503`.

Every detail/submission verifies task type/reference, actual workflow name/version,
task/workflow application IDs, the loan service's current workflow link, and the
session user's authorized loan read. Only explicitly projected fields leave
the BFF; raw notification/task/workflow input, tokens and history are excluded.
The queue scans at most 1000 notification rows, then paginates the authorized
pending results; exceeding the limit returns `503` instead of partial counts.
The selected application workspace resolves accepted AI results and bounded evidence; the queue/detail remain metadata-only.

The single-replica chart serializes same-task writes in the BFF. Session-bound
operation keys reject changed submissions (up to 100 keys/session), and durable
MicroTx completion output reconciles identical retries after browser/process
restarts. A timeout triggers a task read; an unconfirmed completion returns a
retryable error. A conflicting completion or closed task returns `409`. Multi-replica
browser sessions and distributed submission coordination are outside this increment.
`202` confirms HUMAN completion acceptance, not final loan approval. The workflow
refreshes service authorization and runs its deterministic manual-final decision.

## Workspace evidence reads (2026-11-05)

Rebuild/redeploy `azn-server`, AI, decision, geographic risk, BFF and the SPA.
The updated authorization server registers `cloudbank-bff-client-read` alongside
the existing login client, sharing its server-held Secret/rotation lifecycle.
The machine registration has only `cloudbank.workspace.read`, no user roles,
and cannot call workflow-task POSTs. No new secret value or database migration
is required. Non-default BFF client IDs require CLOUDBANK_WORKSPACE_READER_CLIENT_ID on each owner to match the login client ID plus -read.

The BFF checks the user's application access before internal composition and
rechecks the runtime application/workflow/name/version relationship. Base URLs:
`BFF_AI_BASE_URL`, `BFF_DECISION_BASE_URL`, `BFF_GEOGRAPHIC_BASE_URL`, defaulting
to the same-namespace service names on port 8080. Host-based runs should set
them to ports 8085, 8088 and 8083 respectively (or the actual deployed ports).
MicroTx uses the existing independent `BFF_MICROTX_*` settings.

AI summary reads are durable. Policy-support and manual-assistance reads use
bounded process-local caches: restart, eviction or another replica can make
those results unavailable. A GET never repopulates them. Policy Evidence uses
only this execution's already retrieved authorized chunks (three at most),
with excerpts limited to 1000 characters. Decision payment facts are projected
from its own stored snapshot. Workflow returns at most 100 timeline entries
and excludes raw input/output, authorization, prompts and failure messages.
Missing/failed capabilities do not hide Overview/Documents or other results.

This increment was compiled/built locally; automated behavioral tests and
target-runtime verification have not been run for it.


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
