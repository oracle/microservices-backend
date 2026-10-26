# CloudBank AI deployment on OBaaS

This directory contains CloudBank AI-owned deployment overlays. It does not modify the OBaaS chart source or the CloudBank v5 application.

The combined CloudBank deployment requires an installed OBaaS release with a
semantic `appVersion` of 2.1.0 or later. The Azn and services helpers select
`obaas-sample-app` with that exact `appVersion`, including any prerelease or
build suffix, and stop if no matching chart is available or the chart/resource
validation fails. On redeploy, older
CloudBank application charts can move to the platform's current version;
automatic chart downgrades are rejected. MicroTx resource, authentication, and
workflow validation still apply to each target release.

The [gateway BFF runbook](gateway-bff-runbook.md) and
[`deploy-gateway-bff.sh`](deploy-gateway-bff.sh) deploy only the Spring Boot
browser BFF. Repeated runs reconcile its own Helm release.

## Start here: first deployment of `azn-server`

Use the [azn-server deployment runbook](azn-server-runbook.md) to configure the
minimal OCI inputs in `.env`, generate `NEW_IMAGE_TAG`, and run the unified
[`deploy-azn-server_v1.sh`](deploy-azn-server_v1.sh) helper. It performs the
OKE, OCIR, image publication, dry-run, confirmation, deployment, and
verification stages, followed by automatic MicroTx OIDC configuration. Both
first deployment and redeploy use the `.env` issuer in Helm and wait for Azn
and the OIDC bridge before starting the Console.

## Re-deploy `azn-server`

Use the `redeploy` mode documented in the same
[runbook](azn-server-runbook.md#2-run-the-unified-deployment) only when
`azn-server` is already installed. It requires a different image tag and does
not replace application Secrets or signing keys.

## Deploy the remaining CloudBank services

After `azn-server` is healthy, use the [services deployment
runbook](services-runbook.md) and [`deploy-services.sh`](deploy-services.sh).
The services helper accepts only `first-deploy` or `redeploy`, reads its
configuration exclusively from the repository-root `.env`, generates a fresh
immutable image tag, runs its preflight automatically, and asks for
confirmation before making changes.
The helper builds and publishes the eight non-authorization-service Docker
targets plus the `cloudbank-schema-init` and `policy-loader` targets to private
OCIR repositories.
For a fresh installation it generates missing ADB-compatible CloudBank
credentials, creates only the missing schema-owner, per-service DB, and
image-pull Secrets, and runs the same full-demo SQLcl/Liquibase bootstrap used
by local Compose directly against the target ADB. It then runs the one-shot
lab-owner access bootstrap, granting the existing `obaas-admin` account
visibility over all current and future loan applications, followed by the
policy loader with the same OCI GenAI configuration and Workload Identity as
`policy-retrieval-service`. Only after all bootstrap Jobs succeed does it install the
services with the version-matched `obaas-sample-app` chart
and the checked-in database-optional compatibility patch,
auto-detect the internal MicroTx Workflow Server URL from the running OBaaS
Service, and wait for ready Deployments and EndpointSlices. It does not deploy
workflow definitions or create public gateway routes. `run-compose.sh` and the
local database are not used by this services deployment path.

The [lab owner runbook](lab-owner-runbook.md) describes the automatic identity
mapping and the standalone [`provision-lab-admin.sh`](provision-lab-admin.sh)
repair command. Other users retain their existing ownership and grant limits.

The loader introduces no additional IAM operation. Its artifact and recovery
delta is documented in
[`src/policy-loader/README.md`](../../src/policy-loader/README.md); shared
platform and policy-service prerequisites remain in the services runbook.

## Deployment helper

[`deploy-azn-server_v1.sh`](deploy-azn-server_v1.sh) is the public deployment
entry point. It accepts only `first-deploy` or `redeploy`; configuration comes
from `.env`, while the immutable tag comes from `NEW_IMAGE_TAG`. The lower-level
[`deploy-azn-server.sh`](deploy-azn-server.sh) Helm helper is invoked internally
with the same single mode argument.

[`deploy-services.sh`](deploy-services.sh) is the public entry point for all
remaining services. It also accepts only `first-deploy` or `redeploy`; all of
its operator-supplied values come from `.env`, and its image tag is generated
internally for each run.

## Authorization contract

Deploy `azn-server` with a stable issuer appropriate for the selected access
profile and persistent RSA signing keys. `deploy-services.sh` reads that issuer
from the live `azn-server` Deployment; application Pods use the internal
Kubernetes Service URL separately for token and JWKS access. On the first
deployment the helper provisions
`cloudbank-ai-azn-auth`, including the `microtx-client-secret`,
and `service-client-secret` keys, from the ignored local configuration
initialized by `run-compose.sh`. The deployment helper generates
`ai-agent-client-secret` directly and also adds it idempotently when redeploying
an older Secret that lacks that key. Never place those values in a committed
values file, manifest, command argument, or shell history.

Use the same Secret keys for the corresponding authorization-server
registration and loan-service client authentication:

| Secret key | Consumer | Environment variable |
| --- | --- | --- |
| `microtx-client-secret` | `azn-server` | `AZN_AUTHORIZATION_SERVER_MICROTX_CLIENT_SECRET` |
| `microtx-client-secret` | `loan-application-service` | `MICROTX_CLIENT_SECRET` |
| `service-client-secret` | `azn-server` | `AZN_AUTHORIZATION_SERVER_SERVICE_CLIENT_SECRET` |
| `service-client-secret` | `loan-application-service` | `WORKFLOW_TASK_CLIENT_SECRET` |

Map every secret through `valueFrom.secretKeyRef`. The following `env` entries
are fragments to merge into the respective application deployments, not a
standalone manifest:

```yaml
# azn-server
- name: AZN_AUTHORIZATION_SERVER_MICROTX_CLIENT_SECRET
  valueFrom:
    secretKeyRef:
      name: cloudbank-ai-azn-auth
      key: microtx-client-secret
- name: AZN_AUTHORIZATION_SERVER_SERVICE_CLIENT_SECRET
  valueFrom:
    secretKeyRef:
      name: cloudbank-ai-azn-auth
      key: service-client-secret

# loan-application-service
- name: MICROTX_CLIENT_SECRET
  valueFrom:
    secretKeyRef:
      name: cloudbank-ai-azn-auth
      key: microtx-client-secret
- name: WORKFLOW_TASK_CLIENT_SECRET
  valueFrom:
    secretKeyRef:
      name: cloudbank-ai-azn-auth
      key: service-client-secret

# geographic-risk-service (no client secret is needed for inbound JWT validation)
- name: AZN_ISSUER_URI
  value: <live-azn-issuer-uri>
- name: AZN_JWK_SET_URI
  value: http://azn-server.<application-namespace>.svc.cluster.local:8080/oauth2/jwks
- name: AZN_AUDIENCE
  value: cloudbank-api
- name: GEOGRAPHIC_RISK_CALLER_CLIENT_IDS
  value: cloudbank-service-client
```

Also set non-secret configuration:

```text
AZN_AUTHORIZATION_SERVER_DEFAULT_CLIENT_ENABLED=true
AZN_ISSUER_URI=<live-azn-issuer-uri>
AZN_PERSISTENT_SIGNING_KEY_REQUIRED=true
```

The application chart must mount the existing persistent signing-key Secret;
do not place signing material or OAuth secret values directly in Helm
arguments or committed values files.

## OBaaS overlay

Copy `values-microtx-security.example.yaml` to an environment-specific untracked or securely managed values file, replace `<application-namespace>` and `<live-azn-issuer-uri>`, and layer it into the CloudBank AI OBaaS installation. Render and install with the exact pinned `helm/infra-charts/obaas` chart checkout used by the project; do not assume compatibility from a generic version label.

Before installation, confirm that the overlay issuer exactly matches `AZN_ISSUER_URI` and that the Workflow Server can resolve and reach both the issuer metadata and JWKS URLs.

## Token contract check

Request a token without printing the secret:

```bash
curl --silent --show-error --fail \
  --user 'microtx-workflow-client:<microtx-client-secret>' \
  --data-urlencode 'grant_type=client_credentials' \
  --data-urlencode 'scope=microtx.workflow' \
  'http://azn-server.<application-namespace>.svc.cluster.local:8080/oauth2/token'
```

The access token must contain:

```json
{
  "aud": ["microtx-workflow"],
  "scope": ["microtx.workflow"],
  "client_id": "microtx-workflow-client",
  "token_kind": "service",
  "roles": ["microtx-conductor-user", "microtx-conductor-worker"]
}
```

## Interim task authorization

The loan service obtains a second token with `cloudbank-service-client` and
`cloudbank.internal`. Only this CloudBank-audience token is injected into
workflow input as `workflowTaskAuthorization`; the dedicated MicroTx token
must never be sent to a CloudBank resource service. The current document
ingest, document review, and geographic-risk task endpoints allow-list this
interim caller identity.

This is an interim, sensitive integration mechanism. A Workflow Server may
retain input in execution state or history, and delayed or retried tasks may
outlive the token. Before enabling live traffic, verify:

- who can read workflow input and history and whether authorization values are
  redacted from APIs, Workbench, logs, traces, and telemetry;
- whether the document-ingest task starts within the token lifetime and how
  expiration is handled during delay or retry;
- that a fresh CloudBank task token is accepted by document ingest and the
  MicroTx-audience token is rejected there; and
- whether the deployed platform provides a managed task-authentication
  mechanism that can replace `documentIngestAuthorization`.

Retain the input token only until such a replacement is verified.

## Live acceptance

Live Workflow API acceptance is deferred until the MicroTx environment is
available. At that point verify that the Workflow Server retrieves the issuer
metadata and `/oauth2/jwks`, rejects an unauthenticated API request with `401`,
enforces the configured audience and conductor roles, and accepts the dedicated
token for the intended Workflow API operation.

## Expose the MicroTx Workflow Console through APISIX

This procedure exposes the MicroTx Workflow Console at
`http://<gateway-host>/consoleui/` through the OBaaS APISIX gateway. It applies
to the console Service named `obaas-otmm-console` in the `<CLOUDBANKAI_NAMESPACE>`
namespace. Replace the example gateway host with the stable DNS name or public
IP address used by the browser.

The console UI and its workflow API use different paths:

| Browser path | Backend Service |
| --- | --- |
| `/consoleui` and `/consoleui/*` | `obaas-otmm-console:5002` |
| `/workflow-fb` and `/workflow-fb/*` | `obaas-otmm-console:5002` |

The second route is required. Workflow definitions are loaded from
`/workflow-fb/api/metadata/workflow`; routing only `/consoleui` serves the
page but leaves its definitions view empty. The console does not use the
generic `/api/*` path for this request.

### Temporary runtime configuration

Use this only to test the external endpoint. It updates the live Deployment
and survives a Pod restart, but a Helm upgrade or rollback can overwrite it.

```bash
export GATEWAY_ORIGIN='http://<gateway-host>'

kubectl -n <CLOUDBANKAI_NAMESPACE> set env deployment/obaas-otmm-console \
  CONDUCTOR_FRONTEND_ENDPOINT="$GATEWAY_ORIGIN" \
  SECURITY_PROPERTIES_FRONTEND_URI="$GATEWAY_ORIGIN"
```

`CONDUCTOR_FRONTEND_ENDPOINT` must be the browser-visible APISIX origin, not
`http://localhost:5002` and not a Kubernetes Service address. Do not append
`/consoleui`: the workflow API is rooted at `/workflow-fb`.

Obtain the APISIX administrative key without printing it, while a separate
terminal port-forwards the Admin service:

```bash
kubectl -n <CLOUDBANKAI_NAMESPACE> port-forward svc/obaas-apisix-admin 9180:9180

export APISIX_ADMIN_KEY="$({ kubectl -n <CLOUDBANKAI_NAMESPACE> get configmap obaas-apisix \
  -o jsonpath='{.data.config\\.yaml}' | grep -A5 'name: "admin"' | \
  awk '/key:/ {print $2; exit}'; })"
```

Create the UI and workflow API routes. Keep the key out of shell history and
do not commit it.

```bash
curl --fail-with-body http://localhost:9180/apisix/admin/routes/otmm-console \
  -H "X-API-KEY: $APISIX_ADMIN_KEY" \
  -H 'Content-Type: application/json' \
  -X PUT \
  -d '{
    "name": "otmm-console",
    "uris": ["/consoleui", "/consoleui/*"],
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "obaas-otmm-console.<CLOUDBANKAI_NAMESPACE>.svc.cluster.local:5002": 1
      }
    }
  }'

curl --fail-with-body http://localhost:9180/apisix/admin/routes/otmm-console-workflow-api \
  -H "X-API-KEY: $APISIX_ADMIN_KEY" \
  -H 'Content-Type: application/json' \
  -X PUT \
  -d '{
    "name": "otmm-console-workflow-api",
    "uris": ["/workflow-fb", "/workflow-fb/*"],
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "obaas-otmm-console.<CLOUDBANKAI_NAMESPACE>.svc.cluster.local:5002": 1
      }
    }
  }'
```

Verify the API before opening the UI:

```bash
curl --fail-with-body "$GATEWAY_ORIGIN/workflow-fb/api/metadata/workflow"
```

The response is a JSON array of definitions. Then open a private browser
window at:

```text
http://<gateway-host>/consoleui/workflow/index.html?ojr=definitions
```

### Permanent Helm configuration

Put the public origin in the environment-specific OBaaS values overlay used
to install the `obaas` release:

```yaml
otmm:
  commonConfiguration:
    externalURL:
      protocol: http
      host: <gateway-host>
```

Re-run the project's normal, pinned `helm upgrade --install` command with that
overlay. Do not use `kubectl set env` as the permanent source of truth. The
OBaaS console chart renders `CONDUCTOR_FRONTEND_ENDPOINT` from
`otmm.commonConfiguration.externalURL`.

The APISIX routes are created through the APISIX Admin API and are not part of
that Helm value. Reapply them through an operator script or approved APISIX
configuration process after an APISIX data-store reset or platform rebuild.

### Troubleshooting

- If the page loads but shows no definitions, request
  `/workflow-fb/api/metadata/workflow` through the public gateway. A `404 Route
  Not Found` means the `/workflow-fb/*` APISIX route is missing.
- If browser developer tools show calls to `localhost:5002`, the console still
  has its local frontend endpoint. Check the live Deployment environment and
  restart or redeploy it with the correct Helm overlay.
- If the request succeeds directly through a port-forward but fails through
  APISIX, inspect the APISIX route and gateway logs; do not expose the console
  Service directly as a workaround.
- Prefer HTTPS and a stable DNS name for any non-development exposure. If OIDC
  security is enabled, update the registered redirect and post-logout URLs to
  the same public origin before enabling browser sign-in.
