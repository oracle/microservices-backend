# MicroTx Integration Contract And Developer Handoff

## Purpose

This document describes how `loan-application-service` currently starts Oracle Transaction Manager for Microservices (MicroTx) Workflows, what data it sends, what it expects in return, which components must already be deployed, and what remains to be implemented before live MicroTx mode can be considered complete.

It is written as a handoff for a developer who has no prior CloudBank context. Treat the sections labelled **Current implementation** as descriptions of code that exists today. Treat sections labelled **Required follow-up** as work that is not yet delivered.

The authoritative Java entry points are:

- `LoanApplicationService`, which commits the application and workflow-start request.
- `WorkflowOutboxDispatcher`, which claims durable workflow-start requests.
- `MicroTxWorkflowStarter`, which obtains separate MicroTx and CloudBank task tokens and sends the start request.
- `WorkflowStarter`, which is the engine-neutral adapter contract.

## Executive Summary

Yes, live mode assumes a workflow definition has already been created and saved in MicroTx. The configured defaults are:

```text
Workflow name:    cloudbank-loan-origination
Workflow version: 1
```

`loan-application-service` does not deploy or define that workflow. It only:

1. Commits loan intake and a durable workflow-start outbox row in Oracle.
2. Waits until the request is eligible for dispatch.
3. Claims the outbox row in a short database transaction.
4. Obtains a dedicated OAuth2 MicroTx access token and a separate CloudBank workflow-task token.
5. Calls the configured MicroTx start endpoint.
6. Stores the returned MicroTx workflow execution ID.
7. Retries transient failures without creating a second logical workflow.

The repository contains `src/workflows/cloudbank-loan-origination/`, including
the sole supported version `1` definition in local/Minikube and OBaaS/OKE URL
variants, task definitions, deployment automation, verification script, sample
input, and operator documentation. The current REST path and response mapping
must still be verified against the exact deployed MicroTx 26.1 environment.

## Terminology And Ownership

| Term | Meaning and owner |
| --- | --- |
| Loan application | Canonical intake aggregate owned by `loan-application-service`. |
| Workflow-start request | Durable Oracle outbox row in `CB_WORKFLOW_START_REQUEST`. |
| Workflow definition | Versioned MicroTx blueprint containing inputs, tasks, transitions, timeouts, and metadata. Deployed independently of this service. |
| Workflow execution | One running or completed instance created from a workflow definition. |
| Workflow ID | Execution identifier returned by MicroTx and stored in CloudBank correlation tables. |
| Application ID | Stable `APP-<UUID>` identifier used as the workflow idempotency key. |
| Task worker | A CloudBank service or built-in MicroTx task that performs one workflow step. |

Oracle describes a workflow definition as the blueprint for an execution. Definitions can be authored visually or as JSON and must be saved before they can be executed:

- [Manage Workflow Definitions](https://docs.oracle.com/en/database/oracle/transaction-manager-for-microservices/26.1/aiwfg/manage-workflow-definitions.html)
- [Define a Workflow Using JSON](https://docs.oracle.com/en/database/oracle/transaction-manager-for-microservices/26.1/aiwfg/define-workflow-using-json.html)

## End-To-End Sequence

The applicant reaches the loan API through the planned Backend for Frontend (BFF).
The BFF is the browser-safe boundary; it is not the OAuth client used by the
workflow dispatcher.

```text
Applicant -> BFF
    |
    | POST /api/v1/loan-applications
    v
loan-application-service
    |
    | one Oracle transaction
    |-- CB_APPLICANT
    |-- CB_LOAN_APPLICATION
    |-- CB_DOCUMENT
    |-- CB_WORKFLOW_START_REQUEST
    |-- CB_AUDIT_EVENT
    `-- CB_TELEMETRY_CORRELATION
    |
    | transaction commits before any remote call
    v
WorkflowOutboxDispatcher
    |
    | atomically claims one PENDING or retryable request
    | obtains isolated OAuth2 client-credentials tokens
    v
MicroTx Workflows
    |
    | starts predeployed cloudbank-loan-origination version 1
    | returns workflow execution ID
    v
loan-application-service
    |
    | marks outbox STARTED
    `-- creates CB_WORKFLOW_INSTANCE correlation row
```

The database commit and MicroTx call are deliberately separate. A remote workflow cannot participate atomically in the intake transaction. The transactional outbox prevents a committed application from being lost when MicroTx is unavailable.

## When A Workflow Request Becomes Eligible

An intake request contains `workflowStartMode=AUTO|DEFERRED`.

| Intake state | Initial dispatch status | Dispatch behavior |
| --- | --- | --- |
| `AUTO`, all required documents received | `PENDING` | Eligible for background dispatch. |
| `AUTO`, at least one required document is only expected | `WAITING_FOR_DOCUMENTS` | Not dispatched until document metadata is promoted to received. |
| `DEFERRED` | `DEFERRED` | Not dispatched until explicitly released through the workflow-start API. |

The dispatcher only claims `PENDING` or `FAILED_RETRYABLE` rows whose `next_attempt_at` has arrived. It changes the row to `IN_PROGRESS` before making the remote call. Multiple service replicas use an atomic database update and unique claim token so only one replica owns a dispatch attempt.

## Current OAuth2 Exchange

### Configuration

Live mode requires:

```text
WORKFLOW_MODE=microtx
MICROTX_WORKFLOW_URL=<MicroTx workflow service base URL>
MICROTX_WORKFLOW_NAME=cloudbank-loan-origination
MICROTX_TOKEN_URI=<OAuth2 token endpoint>
MICROTX_CLIENT_ID=microtx-workflow-client
MICROTX_CLIENT_SECRET=<secret supplied through the deployment secret store>
MICROTX_SCOPE=microtx.workflow
WORKFLOW_TASK_TOKEN_URI=<OAuth2 token endpoint; defaults to MICROTX_TOKEN_URI>
WORKFLOW_TASK_CLIENT_ID=cloudbank-service-client
WORKFLOW_TASK_CLIENT_SECRET=<separate secret supplied through the deployment secret store>
WORKFLOW_TASK_SCOPE=cloudbank.internal
```

Workflow version `1` is a compile-time application constant. It is not an
environment setting and cannot be redirected to another saved version.

### Token request

The adapter requires complete credentials for both trust domains in MicroTx mode. It first requests the token used only for the secured Workflow API:

```http
POST <MICROTX_TOKEN_URI>
Authorization: Basic base64(<MICROTX_CLIENT_ID>:<MICROTX_CLIENT_SECRET>)
Content-Type: application/x-www-form-urlencoded

grant_type=client_credentials&scope=microtx.workflow
```

That token must contain `aud=microtx-workflow` and the configured MicroTx conductor roles. The adapter independently requests a `cloudbank.internal` token from `cloudbank-service-client`; only that second token is injected into the workflow input as `workflowTaskAuthorization` for extraction and document review. Both token responses must contain a non-empty `access_token`. Missing or partial configuration for either identity is invalid in MicroTx mode.

### Security requirements

- Store the client secret in the OBaaS/Kubernetes secret facility; never place it in Git, workflow JSON, logs, or telemetry.
- Use TLS for deployed token and workflow endpoints.
- Confirm that the MicroTx installation trusts the token issuer and authorizes the configured client to start the named workflow.
- Do not reuse the browser-facing BFF client for workflow startup.
- Do not log token responses, bearer tokens, Basic authorization values, or MicroTx error bodies. NOTICE: Not possible at the moment to set a LOG Level to avoid verbose/credentials logs.  

## Current Workflow Start Request

### Assumed endpoint

The adapter currently calls:

```http
POST <MICROTX_WORKFLOW_URL>/api/workflow/{workflowName}?version={workflowVersion}&correlationId={applicationId}&idempotencyKey={applicationId}
```

With defaults, that resolves to:

```text
POST <MICROTX_WORKFLOW_URL>/api/workflow/cloudbank-loan-origination?version=1&correlationId=APP-12345678-1234-1234-1234-123456789abc&idempotencyKey=APP-12345678-1234-1234-1234-123456789abc
```

This path uses the MicroTx/Conductor start-by-name request shape. If a target MicroTx installation exposes a different gateway prefix, set `MICROTX_WORKFLOW_URL` to the base path immediately before `/api`.
Use the MicroTx `idempotencyKey` query parameter for this endpoint. Do not replace it with `requestId`; `requestId` belongs to other Conductor request shapes and will not provide the same start-by-name idempotency behavior.

### Headers

```http
Content-Type: application/json
traceparent: 00-<32-character trace ID>-0000000000000001-01
```

The application ID is stable across retries and is sent as both `correlationId` and `idempotencyKey` query parameters. The W3C `traceparent` value connects the loan intake trace with the workflow execution. The request also includes `Authorization: Bearer <microtx-workflow access token>`.

### Body

The current request body is:

```json
{
  "applicationId": "APP-12345678-1234-1234-1234-123456789abc",
  "traceId": "0123456789abcdef0123456789abcdef",
  "workflowTaskAuthorization": "Bearer <short-lived-service-access-token>",
  "scenarioId": "SMOKE-20260629T180000Z",
  "scenarioName": "Loan Intake Smoke Test",
  "documentCount": 2
}
```

This body is the raw workflow input map. Do not wrap it under `input` for the `POST /api/workflow/{workflowName}` endpoint; MicroTx expects the input map directly for this request shape. The persisted loan outbox payload contains only the non-secret fields. Immediately before calling MicroTx, `MicroTxWorkflowStarter` injects `workflowTaskAuthorization` from a separate short-lived CloudBank service token, so the workflow can call protected document-ingest and document-review endpoints without receiving the MicroTx API token. The adapter validates that the persisted payload is a JSON object and sends raw JSON, not a Jackson `JsonNode` or another intermediate representation that could serialize as node metadata.

When the request is accepted correctly, MicroTx execution details may show an additional engine-owned `variables` object next to the CloudBank inputs:

```json
{
  "input": {
    "documentCount": 2,
    "variables": {},
    "applicationId": "APP-12345678-1234-1234-1234-123456789abc",
    "traceId": "0123456789abcdef0123456789abcdef",
    "workflowTaskAuthorization": "***",
    "scenarioId": "SMOKE-20260629T180000Z",
    "scenarioName": "Loan Intake Smoke Test"
  }
}
```

`variables` is normal MicroTx workflow state and is not sent by
`loan-application-service`. Workflow tasks read CloudBank values from
`${workflow.input.applicationId}`, `${workflow.input.traceId}`,
`${workflow.input.workflowTaskAuthorization}`,
`${workflow.input.scenarioId}`, `${workflow.input.scenarioName}`, and
`${workflow.input.documentCount}`. Treat `workflowTaskAuthorization` as
sensitive even though it is short-lived; it must not be logged or committed.
Because MicroTx may retain input in execution state or history, live acceptance
must verify access controls and redaction on every operator/API surface. It must
also verify delayed or retried task behavior after token expiry. Version 1
copies this input to a masked runtime variable and refreshes it after a HUMAN
task. The interim token should be removed when a platform-managed
task-authentication mechanism is verified.

### Data deliberately excluded

The start request does not contain:

- PDF or ZIP bytes.
- Object-store credentials or signed download URLs.
- Applicant name, email, phone, address, income, or other PII.
- Document hashes or extraction JSON.
- Policy evidence, model prompts, AI output, decisions, or manual-review data.
- OAuth secrets or database credentials.

Workflow tasks receive the application ID and retrieve only the data they are authorized to access from the owning services. MicroTx should coordinate capabilities, not become a duplicate system of record.

## Expected MicroTx Response

The adapter currently accepts a plain/string workflow ID response:

```json
"microtx-execution-id"
```

It also accepts either object response form:

```json
{
  "workflowId": "microtx-execution-id",
  "status": "STARTED"
}
```

`status` is optional in the current adapter and defaults to `STARTED`. A missing body is treated as a retryable empty-response failure. A JSON object body without either workflow ID field is treated as a final invalid-response failure.

The returned execution ID is stored in:

- `CB_WORKFLOW_START_REQUEST.engine_workflow_id`.
- `CB_WORKFLOW_INSTANCE.workflow_id`.
- API responses under `workflow.workflowId`.

## Idempotency And Retry Behavior

MicroTx 26.1 identifies an idempotent workflow request using workflow name, workflow version, and caller-provided idempotency key. CloudBank uses the application ID as that key. See [About Idempotent Workflows and Tasks](https://docs.oracle.com/en/database/oracle/transaction-manager-for-microservices/26.1/aiwfg/idempotent-tasks-microtx-workflows.html).

| Failure | Current classification | Outbox result |
| --- | --- | --- |
| Connection failure or timeout | Retryable | `FAILED_RETRYABLE`; schedule another attempt. |
| HTTP `429` | Retryable | `FAILED_RETRYABLE`. |
| HTTP `5xx` | Retryable | `FAILED_RETRYABLE`. |
| Other HTTP `4xx` | Final | `FAILED_FINAL`. |
| Empty MicroTx response | Retryable | `FAILED_RETRYABLE`. |
| Response without workflow ID | Final | `FAILED_FINAL`. |
| Invalid stored workflow payload | Final | `FAILED_FINAL`. |

Retry delay is bounded exponential backoff, capped at 30 seconds. Persisted errors use safe internal codes and generic messages. Remote response bodies are not stored.

### Required follow-up: duplicate reconciliation

The adapter does not yet reconcile MicroTx's possible "already running", "already completed", or duplicate-idempotency responses. The live adapter must map the actual MicroTx response/status codes as follows:

- Existing running execution: retrieve or accept the existing execution ID and mark the outbox `STARTED`.
- Existing completed execution: store the existing execution ID and mark the outbox `STARTED` or reconciled.
- Existing failed/terminated execution: mark final or expose an explicit recovery operation according to the agreed business policy.

Do not generate a new idempotency key during reconciliation.

## Required Predeployed Workflow Definition

Create this repository structure:

```text
src/workflows/cloudbank-loan-origination/
  workflow-v1.json
  workflow-v1-obaas.json
  review-documents-task-def.json
  refresh-workflow-authorization-task-def.json
  sample-input.json
  README.md
  deploy.sh
  verify.sh
```

The workflow definition must use:

```json
{
  "name": "cloudbank-loan-origination",
  "version": 1
}
```

At minimum, define and validate these input parameters:

| Input | Type | Required | Purpose |
| --- | --- | --- | --- |
| `applicationId` | string | Yes | Canonical correlation and service lookup key. |
| `traceId` | string | Yes | W3C trace ID without separators, used for workflow-to-service callbacks. |
| `workflowTaskAuthorization` | string | Yes | Short-lived `Bearer ...` value shared by protected workflow callbacks and refreshed after HUMAN review. |
| `scenarioId` | string | Yes | Synthetic demo-scenario correlation. |
| `scenarioName` | string | Yes | Plain-language operational label. |
| `documentCount` | integer | Yes | Intake inventory count for validation/telemetry only. |

For the saved MicroTx workflow definition, declare these fields at the workflow root:

```json
"inputParameters": [
  "applicationId",
  "traceId",
  "workflowTaskAuthorization",
  "scenarioId",
  "scenarioName",
  "documentCount"
],
"inputTemplate": {
  "applicationId": "",
  "traceId": "",
  "workflowTaskAuthorization": "",
  "scenarioId": "",
  "scenarioName": "",
  "documentCount": 0
},
"enforceSchema": true,
"maskedFields": [
  "workflowTaskAuthorization",
  "Authorization"
]
```

Map the same values into any task that must display or use them. For example:

```json
"inputParameters": {
  "applicationId": "${workflow.input.applicationId}",
  "traceId": "${workflow.input.traceId}",
  "scenarioId": "${workflow.input.scenarioId}",
  "scenarioName": "${workflow.input.scenarioName}",
  "documentCount": "${workflow.input.documentCount}"
}
```

Version 1 includes an `extract_documents` HTTP task in a bounded extraction/review loop that posts the workflow correlation envelope to `document-ingest`:

```json
{
  "name": "extract_documents",
  "taskReferenceName": "extract_documents",
  "inputParameters": {
    "method": "POST",
    "uri": "${workflow.variables.documentIngestBaseUrl}/internal/api/v1/document-extractions",
    "headers": {
      "Content-Type": "application/json",
      "Authorization": "${workflow.variables.workflowTaskAuthorization}",
      "Idempotency-Key": "extract:${workflow.input.applicationId}:${workflow.workflowId}"
    },
    "body": {
      "applicationId": "${workflow.input.applicationId}",
      "workflowId": "${workflow.workflowId}",
      "taskReference": "extract_documents",
      "traceId": "${workflow.input.traceId}"
    }
  },
  "type": "HTTP"
}
```

The workflow variable `documentIngestBaseUrl` defaults to `http://host.minikube.internal:8082` for the local Minikube-to-host setup, where MicroTx runs in Kubernetes and `document-ingest` runs on the host. Use `http://host.docker.internal:8082` for Docker Desktop container-to-host access, or `http://document-ingest:8082` when MicroTx runs on the same Compose network as the CloudBank services. Do not commit bearer tokens or client secrets into workflow variables; the authorization value must be short-lived and supplied at workflow start time or by a secret-bearing platform integration.

For the start-by-name API, keep the adapter request as the raw input map described above. If a future implementation switches to `POST /api/workflow` or `POST /api/workflow/execute/{name}/{version}`, then and only then wrap the same logical inputs under the request's `input` field.

## Intended Version-1 Workflow

The planned workflow phases are:

1. Validate intake correlation and mark the application `PROCESSING`.
2. Invoke `document-ingest-service` with the application/workflow correlation envelope. The worker retrieves each registered PDF through the loan service and persists structured JSON.
3. Invoke `document-review-service` for completeness, issue codes, and manual-review routing signals.
4. Invoke `ai-agent-service` for the governed document-evidence summary.
5. Invoke `policy-retrieval-service` for authorized policy evidence.
6. Invoke `ai-agent-service` for governed policy-evidence support.
7. Invoke `geographic-risk-service` for deterministic Oracle Spatial signals,
   then extend the phase with the planned relationship, graph, and identity
   risk capabilities. Workflow version 1 now implements the protected
   `evaluate_geographic_risk` HTTP task and exposes its evaluation ID and
   disposition for downstream decisioning.
8. Invoke `decision-service` for the initial deterministic policy decision and
   route `APPROVED`, `REJECTED`, or `MANUAL_REVIEW`.
9. If required, invoke `ai-agent-service` for manual-review assistance, pause
   at the built-in HUMAN task, refresh workflow authorization, and invoke
   `decision-service` again for the underwriter-backed manual-final decision.
10. Invoke `ai-agent-service` for an explanation draft after deterministic decision facts exist.
11. Invoke audit and observability correlation tasks.
12. Complete or compensate retryable side effects.

The current version 1 definition implements phases 2 through 9, including
initial and manual-final deterministic decisions, durable decision evidence,
outcome routing, and canonical application-state transitions. Post-decision
explanation, explicit audit/correlation tasks, broader relationship risk, and
compensation remain to be implemented and validated on the target Workflow
Server.

AI tasks must never approve or reject a loan, override deterministic policy, or bypass required human review.

## Document Extraction Task Contract

MicroTx sends correlation data, not document bytes:

```http
POST <document-ingest-service>/internal/api/v1/document-extractions
Authorization: Bearer <allow-listed workflow service token>
Idempotency-Key: extract:<applicationId>:<workflowId>
Content-Type: application/json

{
  "applicationId": "APP-12345678-1234-1234-1234-123456789abc",
  "workflowId": "microtx-execution-id",
  "taskReference": "extract-documents",
  "traceId": "0123456789abcdef0123456789abcdef"
}
```

`document-ingest-service` then uses its own `cloudbank-document-ingest-client` client-credentials token to call the loan service:

```text
GET /internal/api/v1/loan-applications/{applicationId}/documents
GET /internal/api/v1/loan-applications/{applicationId}/documents/{documentId}/content
POST /internal/api/v1/loan-applications/{applicationId}/documents/{documentId}/status-transitions
```

The manifest contains document ID, type, file name, status, media type, byte length, and SHA-256 digest. The content response is `application/pdf`. The ingest worker verifies length and digest before parsing, writes the JSON result to `CB_DOCUMENT_EXTRACTION` through its least-privilege Oracle account, and acknowledges `RECEIVED -> EXTRACTED` with a deterministic event ID. Replays reuse the same extraction row and status event.

This pull model keeps PDFs out of workflow state and logs, leaves access control at the document owner, and avoids passing database or object-storage credentials through MicroTx. Version 1 processes PDFs individually; ZIP input remains available only through the ingest service’s diagnostic extraction adapter and is not part of this workflow contract.

## Workflow-To-Service Callback Contract

Workflow tasks that change the canonical application status must call:

```http
POST /internal/api/v1/loan-applications/{applicationId}/status-transitions
Authorization: Bearer <allow-listed service token>
Content-Type: application/json
```

Example:

```json
{
  "eventId": "microtx:<workflowId>:<taskReference>:<attempt>",
  "expectedStatus": "SUBMITTED",
  "targetStatus": "PROCESSING",
  "reasonCode": "WORKFLOW_PROCESSING_STARTED",
  "workflowId": "microtx-execution-id",
  "taskReference": "validate_intake",
  "traceId": "0123456789abcdef0123456789abcdef"
}
```

Requirements:

- Token scope must contain `cloudbank.internal`.
- `token_kind` must be `service`.
- `client_id` must be present in `LOAN_INTERNAL_CLIENT_IDS`.
- The Oracle service principal must resolve to `svc-cloudbank-service-client` with active `SERVICE` role.
- `eventId` must be stable across retries; repeating it returns the existing result.
- `expectedStatus` provides optimistic concurrency. A stale transition returns `409`.
- Workflow and task references must be included for audit correlation.

MicroTx task retries do not automatically make arbitrary worker side effects idempotent. Every CloudBank worker endpoint must implement its own stable event or idempotency key.

## Observability Contract

Safe correlation fields are:

- Application ID.
- Workflow-start request ID.
- MicroTx workflow execution ID.
- Workflow name and version.
- Task reference name.
- Trace ID.
- Sanitized failure code.

Do not emit applicant fields, document contents, document hashes, source references, OAuth material, workflow input bodies, or remote error bodies into logs or traces.

The MicroTx execution should be discoverable in the MicroTx console by workflow name/version and correlated back to `CB_WORKFLOW_START_REQUEST` and `CB_WORKFLOW_INSTANCE`.

## Local And Test Modes

`WORKFLOW_MODE=fake` is the default. It produces a deterministic workflow ID derived from the application ID and performs no network call. Use it for root Maven tests and local development.

The smoke test supports:

- `deferred`: leave the outbox deferred; no workflow backend is contacted.
- `fake`: exercise dispatch and require a `fake-` workflow ID.
- `microtx`: exercise the live adapter and require a non-fake workflow ID.

Do not make root `mvn test` depend on a live MicroTx installation.

## Live Deployment Checklist

Before enabling `WORKFLOW_MODE=microtx`:

- [ ] Install and configure the target MicroTx Workflows version.
- [ ] Verify the workflow REST API or SDK contract for that exact build.
- [ ] Create and save `cloudbank-loan-origination` version `1`.
- [ ] Validate its input schema against the request documented above.
- [ ] Register required task definitions and worker endpoints.
- [ ] Configure service discovery or stable internal URLs.
- [ ] Configure TLS trust and network policy in both directions.
- [ ] Configure OAuth issuer trust, client credentials, scopes, and RBAC.
- [ ] Store all secrets in the deployment secret manager.
- [ ] Confirm status callbacks can obtain an allow-listed service token.
- [ ] Confirm application ID idempotency behavior for running, completed, and failed executions.
- [ ] Confirm trace propagation into MicroTx and every worker.
- [ ] Confirm workflow and task logs redact protected data.
- [ ] Run the conditional live adapter integration tests.
- [ ] Run `smoke-test.sh` in `microtx` mode.
- [ ] Verify the same execution in MicroTx UI, CloudBank API, Oracle correlation tables, and telemetry.

## Required Tests Before Declaring Live Integration Complete

### Adapter contract tests

- Successful token exchange and workflow start.
- Correct workflow name, version, headers, input, and idempotency key.
- Token failure and malformed token response.
- Network timeout and connection refusal.
- HTTP `429`, representative `4xx`, and `5xx` responses.
- Empty and malformed workflow responses.
- Duplicate/running/completed workflow reconciliation.
- Redaction of secrets and remote bodies from persisted errors and logs.

### Oracle/outbox integration tests

- Intake and outbox creation commit atomically.
- Rollback leaves neither application nor workflow-start request.
- Document readiness promotes exactly one waiting request.
- Concurrent dispatchers cannot claim the same request.
- Retry attempts retain the same application idempotency key.
- Successful dispatch writes one `CB_WORKFLOW_INSTANCE` row.
- The runtime user cannot access unrelated schemas or tables.

### Conditional live test

Against a predeployed test workflow:

1. Submit a synthetic application.
2. Verify one MicroTx execution is created.
3. Retry the same logical start and verify no duplicate execution.
4. Verify the workflow ID and trace ID in Oracle.
5. Verify an idempotent status callback.
6. Verify task history in the MicroTx console.

## Known Gaps At Handoff

The following are not complete:

- The complete version-1 control flow, including post-HUMAN authorization
  refresh and manual-final decisioning, still requires automated validation on
  the target MicroTx/OBaaS runtime.
- Conditional live integration coverage does not yet assert terminal task
  history for all decision, remediation, and retry paths.
- Broader relationship risk, decision explanation, explicit audit/correlation,
  compensation, notification, and optional loan delivery remain planned.
- No deployed environment has demonstrated every canonical workflow path
  through its final downstream phases.

Do not remove fake mode while these gaps remain. Do not enable live mode merely because the adapter compiles or the application starts.

## Definition Of Done

Live MicroTx integration is complete only when:

1. The workflow definition and task assets are version controlled and reproducibly deployed.
2. The adapter contract matches the installed MicroTx release.
3. OAuth, RBAC, TLS, and secret handling pass security review.
4. Duplicate start behavior is reconciled safely.
5. A synthetic application completes the expected workflow path.
6. Status callbacks update canonical application state idempotently.
7. MicroTx UI, Oracle rows, API responses, audit records, and traces share the same identifiers.
8. Fake-mode and root tests remain deterministic and independent of MicroTx.
