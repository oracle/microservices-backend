# Build `loan-application-service`

> Implementation status: the secured service, transactional outbox, `azn-server` JWT integration, interim service-side ownership/role/data-grant access checks (ADR 0013 removed the earlier VPD policy), least-privilege runtime roles, immutable Oracle BLOB upload, authenticated document-ingest handoff, deterministic workflow adapter, provisional two-token MicroTx adapter, versioned workflow definition, and deploy/verify scripts are implemented. Live MicroTx integration is not complete: duplicate reconciliation, validation against the target Workflow API and security configuration, and safe replacement of the interim workflow-input task token remain outstanding. See `README.md` for delivered behavior and `MICROTX_INTEGRATION.md` for the detailed handoff.

## Summary

Create a Java 25/Spring Boot module at `src/loan-application-service` and add it to the root Maven reactor. The service will durably create applications, maintain document inventory and canonical status, and atomically create workflow-start, audit, and telemetry anchors in Oracle.

Workflow startup uses a transactional outbox. A provisional MicroTx 26.1 adapter and deterministic local/test adapter implement the same port. The service owns immutable PDF storage and authorized delivery as part of intake, but never parses document content or writes extraction/review results.

## Service and persistence implementation

- Use package root `com.cloudbank.loanapplication` with API, application, domain, persistence, workflow, security, and configuration layers.
- Add Spring MVC, validation, Data JPA, OAuth2 resource-server/client, actuator, UCP/wallet, Eureka, Config Client, OpenAPI, Prometheus, Testcontainers, and JKube support.
- Keep schema management centralized under `src/schema`; production Hibernate uses `ddl-auto: validate`.
- Add an ordered schema migration that:
  - Adds `scenario_name`, optimistic-lock version, submitter subject, intake idempotency key, and request hash to `CB_LOAN_APPLICATION`.
  - Makes `expected_outcome` optional because it is demo metadata, not an intake decision.
  - Extends `CB_DOCUMENT` for `EXPECTED` metadata and received-document fields such as media type and content length; hash and source reference are required only after receipt.
  - Creates `CB_WORKFLOW_START_REQUEST` with start mode, dispatch state, attempt count, next attempt, sanitized failure details, trace ID, and a unique application/workflow-version identity.
  - Links `CB_WORKFLOW_INSTANCE` to its start request once MicroTx accepts it.
  - Adds indexes for idempotency lookup, ready outbox work, application status, and document inventory.
- Create a database runtime role with narrowly scoped DML privileges on application, applicant, document, workflow, audit, and telemetry objects. Provision the runtime user externally; do not embed credentials or let it connect as schema owner.
- Persist intake, documents, an `INTAKE_CREATED` audit event, safe telemetry correlation, and the workflow-start request in one Oracle transaction.

## Public contracts and behavior

- `POST /api/v1/loan-applications`
  - Requires `Idempotency-Key` and `cloudbank.write`.
  - Accepts a general DTO containing scenario ID/name, tokenized applicant details, loan amount/term/purpose, document metadata, and `workflowStartMode=AUTO|DEFERRED`.
  - Generates `APP-<UUID>` and applicant/document identifiers server-side.
  - Never accepts expected outcomes, extraction JSON, AI results, or decisions. PDF bytes are accepted only by the separate content-upload endpoint.
  - Returns `202 Accepted`, `Location`, application status, document inventory, workflow-start-request state, nullable MicroTx workflow ID, and trace ID.
  - Repeating the same key, subject, and request hash returns the existing result; reusing the key with different content returns `409`.
- `GET /api/v1/loan-applications/{applicationId}` and paginated `GET /api/v1/loan-applications`
  - Require `cloudbank.read`.
  - Return canonical status, scenario label, loan summary, document inventory, workflow correlation, and safe timestamps.
  - Support status and scenario filters with bounded page sizes.
  - Return list results in the stable CloudBank `content` and `page` envelope; do not serialize Spring Data `PageImpl`.
- `POST /api/v1/loan-applications/{applicationId}/documents`
  - Requires `cloudbank.write` and idempotency.
  - Registers expected metadata only; never transfers or parses file bytes.
  - Promotes an AUTO workflow request from waiting to pending when all required documents are received.
- `PUT /api/v1/loan-applications/{applicationId}/documents/{documentId}/content`
  - Requires `cloudbank.write`, an idempotency key, and an authorized applicant/loan-officer/admin role.
  - Accepts one `application/pdf` body up to 25 MiB, computes its SHA-256 digest, and stores it once in an Oracle SecureFiles BLOB.
  - Moves the document from `EXPECTED` to `RECEIVED`; the same bytes can be replayed safely and different bytes conflict.
- Internal document APIs
  - Require an allow-listed `azn-server` service token with `cloudbank.internal`.
  - Return a processable manifest, return an authorized PDF, and apply idempotent document status transitions.
  - Allow `document-ingest-service` to retrieve content without giving its database account direct BLOB access.
- `POST /api/v1/loan-applications/{applicationId}/workflow-start`
  - Requires `cloudbank.write`.
  - Releases a DEFERRED request only when required document metadata is ready; duplicate calls remain idempotent.
- `POST /internal/api/v1/loan-applications/{applicationId}/status-transitions`
  - Requires `cloudbank.internal`.
  - Accepts a unique event ID, expected current status, target status, reason code, workflow/task reference, and correlation IDs.
  - Enforces the application state machine and records an audit event atomically; stale or illegal transitions return `409`.
- Use a common safe error body: `code`, `message`, `correlationId`, `retryable`, `authorizationStatus`, and optional field errors.

## Workflow, security, and observability

- Define a `WorkflowStarter` port returning the engine workflow ID and initial state.
- The MicroTx adapter submits workflow name `cloudbank-loan-origination`, version `1`, application ID, trace ID, scenario ID/name, document count, and the application ID as the stable workflow idempotency key. It sends no file content or applicant PII. Immediately before dispatch, it injects a short-lived `workflowTaskAuthorization` token from the separate CloudBank workflow-task identity. Its REST path, response mapping, workflow-state visibility, redaction, and token-expiry behavior must be verified against the deployed MicroTx 26.1 contract.
- Dispatch pending rows with short transactions and Oracle row locking suitable for multiple replicas. Retry timeouts, connection failures, `429`, and `5xx` with bounded exponential backoff; reconcile duplicate/in-progress responses using the same MicroTx idempotency key.
- Mark non-retryable client/configuration failures as `FAILED_FINAL`; expose them through health/metrics without leaking response bodies or credentials.
- Provide a deterministic fake adapter for local and test profiles. The provisional live adapter fails startup when MicroTx URL or OAuth client configuration is missing. Deployment validation must additionally prove that the configured workflow name/version exists before enabling live traffic.
- Obtain two isolated OAuth2 client-credentials tokens through secret-backed configuration: `microtx-workflow-client` with the MicroTx audience/scope/roles for the Workflow API, and `cloudbank-service-client` with the CloudBank audience/scope for the document-ingest task. Never reuse either token across the other trust domain.
- Validate inbound JWTs from `azn-server` using configured issuer/JWKS metadata. Map scopes to `SCOPE_cloudbank.read`, `.write`, `.internal`, and `.admin`.
- Disable browser-oriented login, sessions, and permissive CORS; the future Backend for Frontend (BFF) remains the browser boundary.
- Propagate W3C trace context and log application ID, workflow-start-request ID, workflow ID, and trace ID only. Never log tokens, document references, hashes, applicant fields, request bodies, or workflow credentials.

## Testing and acceptance

- Unit-test request validation, ID generation, request hashing, document readiness, legal status transitions, retry classification, and payload redaction.
- MVC/security tests cover missing or malformed JWTs, scope enforcement, validation errors, idempotency conflicts, pagination, and internal endpoint isolation.
- Oracle Testcontainers tests apply the central changelog and verify:
  - Atomic creation of application, inventory, outbox, audit, and telemetry rows.
  - Rollback leaves no partial intake.
  - Same-key retries return one application and changed payloads conflict.
  - Expected documents can later become received.
  - Multiple dispatcher instances cannot claim the same outbox row.
  - The loan runtime cannot write extraction/review/decision/auth tables, and the ingest runtime cannot read BLOBs directly or mutate application lifecycle state.
- Implemented: deterministic adapter tests cover separate token requests, correct token placement, success, token failures, malformed responses, and configuration validation.
- Pending: live coverage for timeout/retry behavior, duplicate reconciliation, Workflow API contract differences, workflow-state redaction, and task-token expiry.
- Pending: conditional live integration coverage against a predeployed MicroTx workflow; root `mvn test` must remain deterministic through the fake adapter.
- Verify OpenAPI examples, actuator health, Prometheus metrics, Eureka registration, container image creation, and the complete root Maven build.
- Update the service-boundary, workflow, observability, backend-readiness, and root documentation; add an ADR recording transactional-outbox workflow startup.

## Assumptions and boundaries

- Target MicroTx Workflows 26.1, whose workflow-level idempotency uses the workflow name, version, and caller-provided key ([Oracle documentation](https://docs.oracle.com/en/database/oracle/transaction-manager-for-microservices/26.1/aiwfg/idempotent-tasks-microtx-workflows.html)).
- The workflow definition is deployed independently; this module owns only startup and correlation.
- The versioned workflow definition, sample input, and deploy/verify scripts live under `src/workflows/cloudbank-loan-origination/`; they require validation against the target deployment.
- AUTO requests wait for all required documents; DEFERRED requests additionally require the explicit start call.
- `document-ingest-service` owns `CB_DOCUMENT_EXTRACTION`; `document-review-service` owns facts, issues, completeness, and routing signals.
- Decisions, AI tasks, manual-review tasks, browser authentication, and BFF composition are outside this module. Immutable uploaded PDF storage is deliberately inside this module because it belongs to the intake aggregate.
