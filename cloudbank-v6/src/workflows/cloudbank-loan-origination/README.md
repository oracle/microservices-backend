# CloudBank Loan Origination Workflow
The workflow `cloudbank-loan-origination` version `1` is in:
- `workflow-v1.json` is the local/Minikube MicroTx definition.
- `workflow-v1-obaas.json` is the OBaaS/OKE.

The two version 1 files have identical control flow and
differ only in the task-service base URLs. 

Version 1 initializes `${workflow.variables.workflowTaskAuthorization}` from the workflow input and
uses that masked runtime variable for every protected HTTP task. 

It runs extraction and review in a bounded `DO_WHILE` loop with at most three
extraction attempts. `BLOCKED` and exhausted `RETRY_EXTRACTION` results
terminate for remediation. `CLEAR` and `MANUAL_REVIEW` document results both
continue through document-summary support, bounded policy retrieval, policy
support, and deterministic geographic-risk evaluation. The workflow then
derives one combined evidence disposition. Geographic `BLOCKED` terminates for
operational remediation. Every other bounded evidence combination proceeds to
the mandatory deterministic initial decision; document, policy, geographic,
income, payment, or capacity facts can produce `MANUAL_REVIEW`.

Only an initial decision outcome of `MANUAL_REVIEW` invokes
`ai_manual_review_assistant` and then pauses at the mandatory HUMAN task. The
assistant call is retried three times. If OCI GenAI remains unavailable, the
optional call is normalized to `AI_ASSISTANCE_UNAVAILABLE` and HUMAN review
continues without an AI checklist, as required by the service specification.
After authorized HUMAN completion, MicroTx schedules the
`refresh_workflow_authorization` SIMPLE task; the worker obtains a fresh
CloudBank service token and `use_refreshed_authorization` replaces the runtime
variable before the protected manual-final decision task. The HUMAN completion
must provide an `APPROVED` or `REJECTED` outcome, underwriter identity, stable
reason code, and cited policy section. Version 1 validates these
fields before refreshing authorization or invoking `decision-service`. A HUMAN
task completed with an empty or invalid body terminates the workflow as
`FAILED` with `MANUAL_REVIEW_COMPLETION_INVALID`; it is never interpreted as an
approval or rejection.

The Loan Application Service starts the
selected version through a durable transactional outbox.

It calls:

```text
POST ${workflow.variables.aiAgentBaseUrl}/internal/api/v1/ai/document-evidence-summaries
```

and then retrieves bounded policy evidence through:

```text
GET ${workflow.variables.policyRetrievalBaseUrl}/internal/api/v1/policy-evidence?query=loan%20underwriting%20income%20affordability
```

It projects at most three authorized retrieval results and calls:

```text
POST ${workflow.variables.aiAgentBaseUrl}/internal/api/v1/ai/policy-evidence-summaries
```

The resulting policy support is followed by the protected geographic-risk
evaluation and then the initial deterministic decision:

```text
POST ${workflow.variables.geographicRiskBaseUrl}/internal/api/v1/geographic-risk/evaluations
POST ${workflow.variables.decisionBaseUrl}/internal/api/v1/decisions
```

MicroTx sends only the application, workflow, task, and trace identifiers. The
service evaluates Oracle Spatial evidence deterministically and returns an
evaluation ID, disposition, and bounded signal list. The workflow uses the
evaluation ID and disposition as bounded decision evidence; it does not
convert geographic `BLOCKED` into a loan rejection. `decision-service` reads
typed facts, applies `decision-rules-v1`, stores the result and citations, and
updates canonical application state through `loan-application-service`.

For `MANUAL_REVIEW`, it next calls:

```text
POST ${workflow.variables.aiAgentBaseUrl}/internal/api/v1/ai/manual-review-assistances
```

before creating `human_task_manual_review`. The HUMAN input also includes the
combined route reason, policy-support ID/status, geographic-risk evaluation
ID/disposition, and normalized assistant availability. Extending the assistant
request itself with policy, risk, and audit references remains a separate API
contract change.

Complete the HUMAN task through the authenticated MicroTx API with all five
required fields. Merely selecting `COMPLETED` in a client that sends an empty
body is not sufficient:

```bash
./src/workflows/cloudbank-loan-origination/complete-manual-review.sh \
  "$WORKFLOW_ID" \
  --outcome APPROVED \
  --from-env
```

The helper checks that `human_task_manual_review` is pending, validates the
payload against the `decision-service` contract, asks for confirmation, and
waits for the terminal workflow status. It uses `MICROTX_BEARER_TOKEN` when
present; otherwise `--from-env` reads only
`AZN_AUTHORIZATION_SERVER_MICROTX_CLIENT_SECRET` from the repository `.env`.
An `APPROVED` human resolution does not override deterministic hard-reject
rules; the final workflow outcome remains owned by `decision-service`.
For OKE, first expose Workflow Server on `127.0.0.1:9010` and `azn-server` on
`127.0.0.1:8080`, or pass their reachable URLs with `--server-url` and
`--token-uri`. Use `--reason-code`, `--policy-section`, and
`--reviewer-principal-id` when the defaults do not describe the actual review.

The equivalent raw API request is:

```bash
curl --silent --show-error --fail-with-body \
  --request POST \
  --header "Authorization: Bearer $MICROTX_BEARER_TOKEN" \
  --header 'Content-Type: application/json' \
  --data '{
    "decisionOutcome": "APPROVED",
    "reviewerRole": "UNDERWRITER",
    "reviewerPrincipalId": "underwriter-demo",
    "reasonCode": "DOCUMENT_EXCEPTION_RESOLVED",
    "policySection": "CBPL-150-S4"
  }' \
  "$CONDUCTOR_SERVER_URL/tasks/$WORKFLOW_ID/human_task_manual_review/COMPLETED"
```

`CONDUCTOR_SERVER_URL` must end in `/workflow-server/api`. Use `REJECTED`
instead of `APPROVED` when that is the underwriter's actual determination; the
workflow never supplies a default lending outcome.

After the human task completes, the
workflow schedules:

```text
refresh_workflow_authorization (SIMPLE)
```

The external `workflow-token-refresh-worker` polls this queue and returns a
fresh masked `workflowTaskAuthorization`. The following
`use_refreshed_authorization` `SET_VARIABLE` task copies that value to
`${workflow.variables.workflowTaskAuthorization}`. The protected
`deterministic_manual_final_decision` call then uses the refreshed value. When
the initial decision bypasses HUMAN review, the runtime variable retains the
token copied from workflow input.

`evaluate_geographic_risk` runs before manual-review routing. Its idempotency
key is stable for the application and workflow execution:
`geo-risk:<applicationId>:<workflowId>`. Its HTTP task does not set
`Content-Type` explicitly: MicroTx selects `application/json` for the object
body, avoiding a duplicate content-type header at the Helidon boundary.

`deploy.sh` accepts exactly one version-1 definition (`workflow-v1.json` or
`workflow-v1-obaas.json`), then creates or updates both `review_documents` and
`refresh_workflow_authorization` task definitions before saving workflow.

It passes only the application, workflow, task, trace, review, and audience
references defined by the `ai-agent-service` boundary. The default local
`aiAgentBaseUrl` is `http://host.minikube.internal:8085` and must be changed in
the workflow definition when the service uses another reachable address.

`src/ai-agent-service` exposes three protected AI endpoints. Document-evidence
and policy-evidence support are deterministic; manual-review assistance uses
Spring AI with OCI GenAI and OKE Workload Identity.
`./run-compose.sh up` starts
it on host port `8085`, which matches the version 1 default when MicroTx runs in
Minikube. Every endpoint preserves workflow correlation, idempotent replay, and
the bounded evidence boundary. None reads PDFs or makes a lending decision.

The policy task uses the same masked `workflowTaskAuthorization`; the internal
endpoint validates the service token kind, `cloudbank.internal` scope, and
allow-listed client ID. It forwards only a fixed, non-sensitive policy query
plus the trace header, and the service caps retrieval at three
`UNDERWRITER`-visible chunks marked for retrieval. Its default
`policyRetrievalBaseUrl` is `http://host.minikube.internal:8086`, which lets a
Workflow Server running in Minikube reach the Compose service through its host
port. Policy Retrieval listens on port `8086` both inside and outside its
container. When it is deployed in Kubernetes, replace the workflow variable
with its cluster-reachable Service DNS.

The default `geographicRiskBaseUrl` is
`http://host.minikube.internal:8083`, matching the Compose host port for the
Helidon `geographic-risk-service`. When both services run in Kubernetes,
replace it with the cluster-reachable Service DNS and port.

The default local `decisionBaseUrl` is
`http://host.minikube.internal:8088`; the OBaaS definition uses
`http://decision-service:8080`. Both initial and manual-final calls are
mandatory, idempotent, and retried three times. Exhausting those retries fails
the workflow rather than proceeding without a deterministic result.

`prepare_policy_evidence_support` projects the retrieval response before it
crosses the AI boundary. It keeps only document/chunk identifiers, policy code
and version, section, heading, bounded content, and vector score. Embeddings,
metadata, source paths, database keys, role internals, and timestamps are not
sent to `ai-agent-service`. An empty projected list is valid and produces
`evidenceStatus: INSUFFICIENT_EVIDENCE` without fabricated citations.


### 1. OBaaS-OKE deployment

Use this procedure for an OBaaS installation at version 2.1.0 or later,
secured by `azn-server` deployed following:
[`deploy/microtx/oke-obaas/README.md`](../../../deploy/microtx/oke-obaas/README.md).
It deploys MicroTx metadata through workstation port-forwards; it does not
install OBaaS, MicroTx, `azn-server`, or any CloudBank application service.

The OBaaS definition contains no credentials. It expects the Workflow Server
and all task services in the same Kubernetes namespace and uses these private
ClusterIP endpoints:

| Workflow variable | Required Kubernetes Service |
| --- | --- |
| `documentIngestBaseUrl` | `http://document-ingest:8080` |
| `documentReviewBaseUrl` | `http://document-review-service:8080` |
| `aiAgentBaseUrl` | `http://ai-agent-service:8080` |
| `policyRetrievalBaseUrl` | `http://policy-retrieval-service:8080` |
| `geographicRiskBaseUrl` | `http://geographic-risk-service:8080` |

`workflow-token-refresh-worker` is also required for the post-HUMAN
authorization refresh, although it has no base URL in the workflow definition.
The application Service port is `8080`; its target port may differ inside the
container. Use the exact Service names above when deploying the corresponding
OBaaS application releases.

Start in the repository root and select the same context and namespace used by
the OBaaS installation:

```bash
export KUBE_CONTEXT="$(kubectl config current-context)"
export MICROTX_NAMESPACE=<CLOUDBANKAI_NAMESPACE>

test -n "$KUBE_CONTEXT"
kubectl --context "$KUBE_CONTEXT" get namespace "$MICROTX_NAMESPACE"
kubectl --context "$KUBE_CONTEXT" --namespace "$MICROTX_NAMESPACE" get \
  service/azn-server \
  service/obaas-otmm-workflow-server
```

Before executing a workflow, all task services and the refresh worker must
exist. This check is deliberately explicit and must not be skipped:

```bash
kubectl --context "$KUBE_CONTEXT" --namespace "$MICROTX_NAMESPACE" get \
  service/document-ingest \
  service/document-review-service \
  service/ai-agent-service \
  service/policy-retrieval-service \
  service/geographic-risk-service \
  deployment/workflow-token-refresh-worker
```

If any resource is missing, stop. The workflow metadata can be saved, but a
loan execution cannot complete until every referenced service is deployed and
ready.

Open two additional terminals and keep these private port-forwards running.
They bind only to the workstation loopback interface.

Terminal 1 — Azn:

```bash
export KUBE_CONTEXT="$(kubectl config current-context)"
export MICROTX_NAMESPACE=<CLOUDBANKAI_NAMESPACE>

kubectl --context "$KUBE_CONTEXT" --namespace "$MICROTX_NAMESPACE" \
  port-forward --address 127.0.0.1 service/azn-server 8080:8080
```

Terminal 2 — Workflow Server:

```bash
export KUBE_CONTEXT="$(kubectl config current-context)"
export MICROTX_NAMESPACE=<CLOUDBANKAI_NAMESPACE>

kubectl --context "$KUBE_CONTEXT" --namespace "$MICROTX_NAMESPACE" \
  port-forward --address 127.0.0.1 service/obaas-otmm-workflow-server 9010:9010
```

Back in the repository-root terminal, deploy the OBaaS definition:

```bash
MICROTX_WORKFLOW_URL='http://127.0.0.1:9010/workflow-server' \
MICROTX_OPERATOR_AUTH_SERVER_URL='http://127.0.0.1:8080' \
MICROTX_DEPLOY_AUTH_MODE=operator \
  ./src/workflows/cloudbank-loan-origination/deploy.sh \
  ./src/workflows/cloudbank-loan-origination/workflow-v1-obaas.json
```

The script uses the same OAuth + PKCE operator flow documented in Section 2.1.
Open the generated authorization URL in a new private browser window, sign in
as `obaas-admin` or `obaas-config`, and paste only the one-time `code` value at
the hidden terminal prompt. A `404` on the manual callback is expected. Do not
reuse or share the callback URL.

The deployer itself needs no OCI-specific code: `MICROTX_WORKFLOW_URL` and
`MICROTX_OPERATOR_AUTH_SERVER_URL` are workstation port-forward endpoints,
while every URL embedded in `workflow-v1-obaas.json` is private and resolvable
from the Workflow Server pod. Successful output ends with:

```text
Workflow cloudbank-loan-origination version 1 deployed successfully.
```

To start a new synthetic application with a real address but no stored
coordinates, use the OKE helper after deploying the workflow and the `full-demo`
schema (including `SDO_GCDR` access for `CB_GEOGRAPHIC_RISK_APP`):

```bash
./src/workflows/start-geocoded-loan-oke.sh "$KUBE_CONTEXT" \
  --namespace "$MICROTX_NAMESPACE"
```

The helper reads the shared
[`application.json`](../../../synthetic_data/customer_packets/demo_geocoded_loan/application.json)
and its existing sibling PDFs; `--application-file FILE` selects another packet.
It prints the packet address. Use `--address-file FILE` to supply an explicit
five-field address override, such as `src/workflows/geocoded-loan-address.json`.
It never asks for longitude or latitude. It reads the deployed demo OAuth
credentials from the environment or the repository `.env` without prompting;
`CLOUDBANK_ENV_FILE` can select another credential file. It creates a durable
synthetic application, uploads synthetic PDFs, and reports the application and
workflow IDs after MicroTx dispatch reaches `STARTED`. The loan service starts
the workflow; MicroTx subsequently invokes `ai-agent-service` and
`geographic-risk-service`. The helper waits for the geographic-risk evaluation
and requires a resolved location signal. Reaching that task implies the two
preceding AI evidence tasks ran, but it does not prove that the entire workflow
completed. `LOAN_SMOKE_GEO_WAIT_SECONDS` can extend the default 180-second
wait. An address outside the configured CloudBank service zones can legitimately
produce `LOCATION_EXCLUDED` even when geocoding succeeds; that disposition
blocks further automatic workflow progress and is not a loan rejection.




### 2. Run the Loan Application Service on local minikube/Rancher

#### 2.1 Configuration

Set these values once in the repository-root ignored `.env`:

```dotenv
WORKFLOW_MODE=microtx
MICROTX_WORKFLOW_NAME=cloudbank-loan-origination

# URL reachable from inside loan-application-service, not from the host shell.
# Rancher Desktop with the direct 9010 port-forward described below:
MICROTX_WORKFLOW_URL=http://host.rancher-desktop.internal:9010/workflow-server

# OAuth defaults used inside the Compose network.
MICROTX_TOKEN_URI=http://azn-server:8080/oauth2/token
MICROTX_CLIENT_ID=microtx-workflow-client
MICROTX_SCOPE=microtx.workflow
WORKFLOW_TASK_TOKEN_URI=http://azn-server:8080/oauth2/token
WORKFLOW_TASK_CLIENT_ID=cloudbank-service-client
WORKFLOW_TASK_SCOPE=cloudbank.internal
```

For Docker Desktop, `host.docker.internal` may be the correct host gateway.
Use an address that returns the MicroTx response from inside the container.
Never use `127.0.0.1` for `MICROTX_WORKFLOW_URL` inside the container because
that points back to `loan-application-service` itself. Compose obtains the two
client secrets from the corresponding `AZN_AUTHORIZATION_SERVER_*` entries in
`.env`; do not duplicate their values under additional keys unless an external
authorization server requires explicit overrides.

Recreate the application containers after changing `.env`:

```bash
unset MICROTX_WORKFLOW_URL
./run-compose.sh up
```

#### 2.2 Deploy And Activate The Workflow

Run all commands in this section from the repository root. The workstation
needs `curl`, `jq`, `openssl`, and access to the target MicroTx Workflow Server.
The CloudBank authorization server must be running when the Workflow Server is
secured.

Deployment saves three MicroTx metadata resources. Select exactly one workflow
definition when invoking `deploy.sh`:

- `review_documents`, from `review-documents-task-def.json`, including three
  retries with exponential backoff;
- `refresh_workflow_authorization`, from
  `refresh-workflow-authorization-task-def.json`, for the post-human-task token
  refresh worker;
- `cloudbank-loan-origination` version `1`, from `workflow-v1.json` for local
  Minikube or `workflow-v1-obaas.json` for OBaaS/OKE.

The workflow JSON file on disk is not executable until these resources have
been saved in MicroTx.


To use a direct Workflow Server port-forward instead, keep this command running in another terminal:

```bash
kubectl --context <minikube_context> --namespace otmm \
  port-forward --address 0.0.0.0 service/workflow-server 9010:9010
```

Binding to `0.0.0.0` is required when a Compose container must reach the
forwarded port through the container runtime's host gateway. Use it only on a
trusted local network and stop the port-forward after the test. For this setup,
the host shell and Compose container use different URLs:

```text
# Rancher Desktop: in the repository-root .env, consumed by the container:
MICROTX_WORKFLOW_URL=http://host.rancher-desktop.internal:9010/workflow-server

# Docker Desktop: in the repository-root .env, consumed by the container:
MICROTX_WORKFLOW_URL=http://host.docker.internal:9010/workflow-server

# In the host shell, used only as the operator-facing URL:
MICROTX_OPERATOR_URL=http://127.0.0.1:9010/workflow-server
```

Check the active runtime with `docker context show`. Do not use
`host.docker.internal` merely because the workload is a Docker container: with
Rancher Desktop it can resolve to the VM bridge gateway rather than the macOS
host and return a connection-refused `000` result.

`MICROTX_WORKFLOW_URL` is the container-facing Compose setting and belongs in
the repository-root `.env`. `MICROTX_OPERATOR_URL` is a host-shell helper for
the local tunnel. Do not export the operator URL as `MICROTX_WORKFLOW_URL` in a
shell that will later run `run-compose.sh`: shell variables take precedence
over `.env` during Compose interpolation, and `127.0.0.1` would then point back
to the application container itself.

To open the workflow console separately:

```bash
kubectl --context <minikube_context> \
  --namespace otmm \
  port-forward service/otmm-console 5002:5002
```

Then configure the host-side deployment URL in the original terminal. Keep it
as a shell variable; `deploy.sh` receives it as `MICROTX_WORKFLOW_URL` only for
the duration of its command:

```bash
MICROTX_OPERATOR_URL='http://127.0.0.1:9010/workflow-server'
```

Start the authenticated deployment:
```bash
MICROTX_WORKFLOW_URL="$MICROTX_OPERATOR_URL" \
MICROTX_DEPLOY_AUTH_MODE=operator \
  ./src/workflows/cloudbank-loan-origination/deploy.sh \
  ./src/workflows/cloudbank-loan-origination/workflow-v1.json
```

The script will print an authorization URL and then wait at:
```bash
Authorization code:
```
Follow these steps:
1. Copy the complete authorization URL printed by the script.

2. Open it in a private/incognito browser window.

3. Sign in as obaas-admin: use the password from AZN_BOOTSTRAP_USERS_ADMIN_PASSWORD.

4. After login, the callback may show a 404 page. This is expected.

5. In the browser address bar, locate:

```bash
?code=<authorization-code>
```

6. Copy only the value of code, stopping before &state= or any other parameter.

7. Paste the code into the terminal and press Enter. The input is intentionally hidden. The authorization code is single-use and expires quickly.

8. Confirm successful deployment.

  The script automatically:
  - Probes anonymous workflow validation.
  - Detects that authentication is required.
  - Obtains an operator token using OAuth + PKCE.
  - Validates the selected version-1 definition and rejects every other file
    name, workflow name, or workflow version.
  - Creates or updates the review_documents Task Definition.
  - Creates or updates the refresh_workflow_authorization Task Definition.
  - Upserts cloudbank-loan-origination version 1.
  - Reads the saved metadata using the same token.
  - Confirms version 1 exists.

Successful output ends with:
 ```bash
Verifying saved workflow definition...
Workflow cloudbank-loan-origination version 1 deployed successfully.
```

No separate `verify.sh` call is necessary because authenticated verification is built into deploy.sh.

### 2.3 Test The Workflow Through Loan Application Service

The smoke test targets `cloudbank-loan-origination` version `1`. Before running
it, confirm that version 1 is saved in MicroTx and that the running Loan
Application Service was built from the current source and redeployed. Version
`1` is fixed in the service and has no environment override.

#### 2.3.1 No-interactive test
From the repository root, use this:

```bash
WORKFLOW_MODE=microtx \
  ./src/loan-application-service/smoke-test.sh --non-interactive
```

To create deterministic conflicting employer evidence and route the execution
through `MANUAL_REVIEW`, `ai_manual_review_assistant`, and
`human_task_manual_review`, run:

```bash
WORKFLOW_MODE=microtx \
  ./src/loan-application-service/smoke-test.sh --non-interactive --manual-review
```

The standard invocation retains the `CLEAR` fixture. The smoke test confirms
workflow dispatch; use the MicroTx execution view to confirm the asynchronous
manual-review and HUMAN tasks.

The smoke test expects `cloudbank-loan-origination` version `1` by default. It
checks the `workflowName` and `workflowVersion` returned by Loan Application
Service before uploading the documents. If the service returns another
version, the test stops and requires rebuilding and redeploying the service.
With `--non-interactive`, it reads these mappings from the repository-root
`.env` without sourcing the file:

| Smoke-test value | Root `.env` source |
| --- | --- |
| `USER_PASSWORD` | `AZN_BOOTSTRAP_USERS_USER_PASSWORD` |
| `BROWSER_CLIENT_SECRET` | `AZN_AUTHORIZATION_SERVER_DEFAULT_CLIENT_SECRET` |
| `SERVICE_CLIENT_SECRET` | `AZN_AUTHORIZATION_SERVER_SERVICE_CLIENT_SECRET` |

Explicit smoke-test environment variables take precedence over `.env`. 

#### 2.3.2 Interactive test
For an interactive request, run:

```bash
./src/loan-application-service/smoke-test.sh
```

and use the following value or `.env` source:

| Script request | Value to enter | Script variable | `.env` source |
| --- | --- | --- | --- |
| Loan Application Service base URL | Press Enter for `http://127.0.0.1:8081` | `LOAN_BASE_URL` | Not secret; no root `.env` entry is required. |
| azn-server base URL | Press Enter for `http://127.0.0.1:8080` | `AZN_BASE_URL` | Local equivalent of `AZN_ISSUER_URI`. Keep the registered redirect host consistent. |
| Demo username | Press Enter for `obaas-user` | `USERNAME` | Fixed local bootstrap username. |
| Demo user password | Value of `AZN_BOOTSTRAP_USERS_USER_PASSWORD` | `USER_PASSWORD` | `AZN_BOOTSTRAP_USERS_USER_PASSWORD` |
| Browser OAuth client ID | Press Enter for `cloudbank-client` | `BROWSER_CLIENT_ID` | Fixed local client ID. |
| Browser OAuth client secret | Value of `AZN_AUTHORIZATION_SERVER_DEFAULT_CLIENT_SECRET` | `BROWSER_CLIENT_SECRET` | `AZN_AUTHORIZATION_SERVER_DEFAULT_CLIENT_SECRET` |
| Registered redirect URI | Press Enter for `http://127.0.0.1:8080/login/oauth2/code/cloudbank-client` | `REDIRECT_URI` | Registered by `azn-server`; it must match exactly. |
| Service OAuth client ID | Press Enter for `cloudbank-service-client` | `SERVICE_CLIENT_ID` | Fixed local client ID. |
| Service OAuth client secret | Value of `AZN_AUTHORIZATION_SERVER_SERVICE_CLIENT_SECRET` | `SERVICE_CLIENT_SECRET` | `AZN_AUTHORIZATION_SERVER_SERVICE_CLIENT_SECRET` |
| Workflow mode | Enter `microtx` | `WORKFLOW_MODE` | `WORKFLOW_MODE=microtx` |
| Workflow polling timeout | Press Enter for `30`, or use `60` on a slow machine | `WORKFLOW_TIMEOUT` | Optional script-only value; no root `.env` entry is required. |


The test authenticates a user and an internal service, creates a unique durable
loan application from the shared ready packet, uploads its existing loan and
pay-statement PDFs using canonical IDs returned by intake,
and waits for the durable MicroTx dispatch status to reach `STARTED`. A
successful assignment check prints:

```text
PASS: Workflow assignment is cloudbank-loan-origination version 1
```

The application remains in Oracle for auditability; temporary authentication
files are removed on exit. Checked-in PDFs are unchanged and reusable; they
contain no runtime application ID. Active ingest/review deployments must use
the new context-based association and `document-review-v2` profile.

### 2.4. Check on MicroTx Workflow Console
- Check in a separate shell:
```bash

kubectl --context <minikube_context> \
  --namespace otmm \
  port-forward service/otmm-console 5002:5002
```
if is still running.

- In an incognito Browser window, call:  
```bash
http://localhost:5002/consoleui/
```

- Authenticate with obaas-admin/<AZN_BOOTSTRAP_USERS_ADMIN_PASSWORD> and look at `Executions` tab.



### 3. Common failures

| Error | Resolution |
| --- | --- |
| Token exchange returns `400` | The code expired, was reused, the redirect URI differs, or it belongs to another PKCE verifier. Run `deploy.sh` again and repeat the browser login. |
| Workflow API returns `401` | Clear `MICROTX_BEARER_TOKEN`, verify the authorization server is running, and start a new operator login. |
| Workflow API returns `403` | Log in as `obaas-admin` or `obaas-config`, not `obaas-user`. Confirm MicroTx maps `ROLE_CONFIG_EDITOR` to its metadata-manager role. |
| Callback displays `404` | Expected for this manual local OAuth flow. Copy the `code` from the address bar. |
| Redirect URI mismatch | Keep the default authorization host as `127.0.0.1`, not `localhost`, unless the OAuth registration was changed. |
| Workflow file not accepted | Pass exactly one readable version-1 definition to `deploy.sh`: `workflow-v1.json` locally or `workflow-v1-obaas.json` on OBaaS/OKE. |
| Smoke test reports another workflow version | Rebuild and redeploy Loan Application Service from the current source, where version `1` is fixed. Existing applications retain the workflow version stored when they were created; the smoke test creates a new application. |
| Workflow version 1 is rejected or not found | Deploy the appropriate version-1 definition with `deploy.sh` and confirm the deployment ends with `Workflow cloudbank-loan-origination version 1 deployed successfully.` |
| Geographic-risk HTTP task returns `400 Bad Request` with no body | Confirm the saved version 1 definition does not set `Content-Type` in `evaluate_geographic_risk.headers`, redeploy `workflow-v1.json`, and start a new smoke test. MicroTx supplies the JSON content type for the object body. |

## Governed document-summary availability

`ai_document_evidence_summary` invokes Spring AI/OCI through the protected AI
service. It uses three retries and is optional so exhausted failures do not
block deterministic decisioning. `normalize_document_summary` accepts
only a successful, completed, guardrail-passed response with a valid summary
ID; otherwise it emits `AI_DOCUMENT_SUMMARY_UNAVAILABLE` and an empty reference.
Policy support and manual-review assistance accept the empty reference.

An initial MANUAL_REVIEW decision follows `human_task_manual_review`, whose
input includes document-summary availability. An initial APPROVED or REJECTED
decision proceeds directly through `route_initial_decision`, even when the
summary is unavailable. Missing AI assistance does not open an additional HUMAN
task or change the deterministic outcome. The workflow returns document-summary
availability with its final output. Validate this revised definition and exercise
unavailable summaries for final and MANUAL_REVIEW decisions on the target
MicroTx environment before publication.

Local expression checks:

```bash
node --test src/workflows/cloudbank-loan-origination/tests/document-summary-fallback.test.mjs
```
