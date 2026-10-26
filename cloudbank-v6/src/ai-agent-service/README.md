# AI agent service

This Spring Boot service implements the protected CloudBank AI workflow
boundary. Document summaries and manual-review assistance use Spring AI with
OCI Generative AI. Policy support remains a deterministic adapter.

```text
POST /internal/api/v1/ai/document-evidence-summaries
POST /internal/api/v1/ai/policy-evidence-summaries
POST /internal/api/v1/ai/manual-review-assistances
```

The document-summary endpoint accepts identifiers only and reads both
`GET /internal/api/v1/document-reviews/{reviewId}` and
`GET /internal/api/v1/applications/{applicationId}/extractions/review-input`
using the same `cloudbank-ai-agent-client` OAuth registration as manual review.
The ingest permission is limited to review-input reads; it cannot start
extractions or use diagnostic PDF endpoints. Both reads propagate `X-Trace-Id`
and W3C `traceparent`. The service validates application/workflow/trace
correlation and completed review status before any model call.

Document summaries use `cloudbank.ai.document-summary` prompts and the same
OCI `ChatClient`, `AI_OCI_GENAI_CHAT_MODEL`, temperature, and OKE Workload
Identity configuration as manual review. Input is bounded to 32 documents and
32 issues. It contains review disposition, authoritative issue codes, document
IDs/types, extraction references/status/confidence, an allow-listed identity
outcome, and allow-listed validation/warning codes. Names, monetary amounts,
free-form messages, unknown warning text, PDFs, and raw extracted text are
excluded. The model produces `summary`, `reviewNotes`, and supplied document
IDs only. The service validates text bounds, known references, and prohibited
content; authoritative structured `materialIssues`, `evidenceToInspect`, and
`sourceReferences` are built from trusted evidence.

Validated summary responses are persisted in `CLOUDBANK.CB_AI_DOCUMENT_SUMMARY`
using `CB_AI_AGENT_APP`, whose role grants SELECT/INSERT only on that result
table. No other service tables are accessible. Replay survives process restarts
and replicas; reuse of an idempotency key with different request metadata
returns `IDEMPOTENCY_CONFLICT`. Concurrent replicas can both call the provider,
but the unique database key ensures both return the same durable winner.
Failures and rejected output are never persisted as successful summaries.

Workflow v1 retries summary failures three times and normalizes the exhausted
result to `AI_DOCUMENT_SUMMARY_UNAVAILABLE` with an empty summary reference.
Policy support and manual-review requests accept that empty reference. An
initial MANUAL_REVIEW outcome uses the existing underwriter gate, whose input
reports summary availability. A recorded APPROVED/REJECTED outcome continues
without an additional human gate or a change to the deterministic decision.

The manual-review endpoint accepts identifiers only. It obtains a separate
`cloudbank-ai-agent-client` client-credentials token and reads
`GET /internal/api/v1/document-reviews/{reviewId}` itself. It never forwards
the workflow token. Only the review ID, disposition, profile version, document
counts, stable issue codes/severities/routing effects, and document IDs are
sent to the model. Free-form issue messages, PDF content, extracted text,
applicant details, and credentials are excluded.

The system and evidence prompts are configured under
`cloudbank.ai.manual-review` in `application.yaml`. The model returns only a
checklist and clarification questions. The service validates list bounds,
length, decision language, and common secret/PII patterns after the call.
Source references are created from trusted input and evidence, never accepted
from model output.

Each chat-model completion emits one safe operational log with provider,
configured model, outcome, duration, and response-item counts. Accepted results
also report schema and guardrail status; rejected or failed results report only
a stable error code. Prompts, evidence, generated text, application and review
identifiers, exception messages, credentials, and tokens are never logged.

Successful manual-review responses are cached by their deterministic `AIREV-*` idempotency
ID in a bounded, in-process cache. This protects same-pod retries; it is not a
durable or cross-replica result store.

## Configuration

The service supports OCI OKE Workload Identity only. Configure these ignored
`.env` entries:

```text
AI_DATASOURCE_PASSWORD=<dedicated-CB_AI_AGENT_APP-password>
AI_OCI_GENAI_AUTHENTICATION_TYPE=WORKLOAD_IDENTITY
AI_OCI_GENAI_REGION=<oci-region>
AI_OCI_GENAI_CHAT_MODEL=<on-demand-chat-model-id>
OKE_CLUSTER_COMPARTMENT_ID=<oke-cluster-compartment-ocid>
AZN_AUTHORIZATION_SERVER_AI_AGENT_CLIENT_SECRET=<generated-secret>
```

`run-compose.sh init` creates missing keys without overwriting existing
values. Set the empty OCI values before starting the stack. File-based OCI
authentication, config files, profiles, and private-key mounts are not used by
`ai-agent-service`.

OKE assigns the dedicated `ai-agent-service` Kubernetes ServiceAccount and
projects the identity material consumed by the OCI SDK. See the OBaaS services
runbook for the IAM policy and deployment arguments.

Compose and `run-locally.sh` enable lazy Spring initialization so health,
authorization, and non-GenAI tests can run outside OKE. A real manual-review
or document-summary model call cannot authenticate from a workstation or ordinary Compose
container because no OKE workload identity is present. It must be validated in
the target OKE Pod.

To run the process for those non-OCI checks, export the same values plus
`AI_AGENT_CLIENT_SECRET`, then run:

```bash
src/ai-agent-service/run-locally.sh
```

Unit and controller tests do not call OCI:

```bash
mvn -f src/ai-agent-service/pom.xml test
```

The workflow definition is intentionally unchanged by this implementation.

## Verification

Run `mvn -f src/ai-agent-service/pom.xml test` for deterministic model fixtures,
Spring AI prompt/schema handling, OAuth downstream reads, grounding, redaction,
durable replay, and request security. Oracle integration tests apply the actual
summary migration and runtime grants in an isolated Oracle Free container;
they are skipped when Docker is unavailable.

Run `node --test src/workflows/cloudbank-loan-origination/tests/document-summary-fallback.test.mjs`
from the repository root to test both workflow definitions, missing/invalid
responses, non-blocking summary failures, and preservation of deterministic
decisions and the existing manual-review gate.

The default component smoke test is non-mutating: missing review identifiers
must return `DOCUMENT_REVIEW_NOT_FOUND` through the AI service's own downstream
identity. It also checks policy support with an empty summary reference. It
does not perform a live OCI call. To validate deployed GenAI behavior, submit
an identifier-only request referencing a real completed CLEAR/MANUAL_REVIEW
synthetic review from the same workflow and trace, from an authorized caller
in the target OKE environment. Confirm provider `oci-genai`, model configuration,
validated summary/issues/references, durable replay, and unavailable-summary
routing for final and MANUAL_REVIEW decisions; never log prompts, evidence, or
generated text.
