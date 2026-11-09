# CloudBank Loan Origination Workflow Status

## At-a-Glance Status Flow

`[OK]` means the executable repository implementation exists. `[TO-BE-DONE]`
means the step is absent, incomplete, or still requires target-runtime work.

```text
→ Application Intake [OK]
  → Document Extraction [OK]
  → Document Review [OK]
     └─ RETRY_EXTRACTION → bounded extraction/review loop [OK]
  → AI Document Evidence Summary [OK: governed Spring AI/OCI; target validation pending]
     └─ unavailable → explicit HUMAN evidence inspection without decision override [OK]
  → Policy Evidence Retrieval [OK]
  → AI Policy Evidence Support [OK: deterministic local/test adapter]
  → Risk Signal Evaluation [OK: geographic risk only]
     └─ graph, identity, and relationship signals [TO-BE-DONE]
  → Deterministic Decision [OK: target-runtime validation pending]
     ├─ APPROVED [OK: deterministic outcome and canonical state]
     │  → AI Decision Explanation Draft [TO-BE-DONE]
     │  → Audit and Correlation [TO-BE-DONE: intake anchors exist]
     │  → Loan Amount Transfer through XA [TO-BE-DONE]
     │  → application marked as delivered [TO-BE-DONE]
     │  → workflow completion [TO-BE-DONE]
     │
     ├─ REJECTED [OK: deterministic outcome and canonical state]
     │  → AI Decision Explanation Draft [TO-BE-DONE]
     │  → Audit and Correlation [TO-BE-DONE: intake anchors exist]
     │  → workflow completion [TO-BE-DONE]
     │
     ├─ MANUAL_REVIEW [OK: evidence- or decision-originated route]
     │  → AI Manual Review Assistant [OK: governed OCI GenAI runtime]
     │  → HUMAN Review Gate [OK]
     │  → resume after authorized human action [OK: mechanism implemented;
     │     target-runtime validation TO-BE-DONE]
     │  → Deterministic Decision [OK: mandatory manual-final task;
     │                              target-runtime validation TO-BE-DONE]
     │     ├─ APPROVED → explanation and loan delivery [TO-BE-DONE]
     │     └─ REJECTED → adverse-action explanation [TO-BE-DONE]
     │
     ├─ RETRYABLE_FAILURE [TO-BE-DONE: general decision-stage route]
     │  → retry or compensation [TO-BE-DONE]
     │  → resume deterministic processing [TO-BE-DONE]
     │
     └─ RECOVERED [TO-BE-DONE: end-to-end scenario]
        → continue deterministic processing [TO-BE-DONE]
        → AI Decision Explanation Draft [TO-BE-DONE]
        → Audit and Correlation [TO-BE-DONE: intake anchors exist]
        → completion or loan delivery [TO-BE-DONE]
```

The implemented version-1 `MANUAL_REVIEW` branch is selected by the initial
deterministic decision after document review, document-summary support, policy
evidence/support, and geographic-risk evaluation. It can therefore originate
from upstream evidence or from typed income, employment, payment, and capacity
facts evaluated by `decision-service`.

Assessment date: 2026-09-25  
Basis: comparison of `docs/architecture/microtx-workflow-plan.md` with the repository implementation, especially `cloudbank-loan-origination/workflow-v1.json`, its task definitions and deployment scripts, and the participating service code and tests.

Status labels:

- **OK** — executable implementation and supporting repository assets exist.
- **TO-BE-DONE** — the planned capability is absent, incomplete, production-only work remains, or target-runtime validation is still required.

Overall status: **TO-BE-DONE**. Version 1 implements the journey from durable
application intake through document extraction/review, governed document and
policy support, geographic-risk evaluation, deterministic decisioning, and
optional human review with authorization refresh plus a manual-final decision.
Post-decision explanation, broader risk, explicit audit/correlation,
compensation, and optional loan delivery remain incomplete.

## Synthetic Step Status

### 1. Application Intake

- **OK** — `loan-application-service` creates durable applications and document inventory, owns immutable PDF BLOB content with digest and length, writes intake audit/telemetry anchors, and creates the workflow-start outbox in the intake transaction.
- **OK** — the outbox dispatcher starts `cloudbank-loan-origination` with the application ID as correlation/idempotency input and records the returned workflow ID and trace correlation.
- **TO-BE-DONE** — validate the live MicroTx start adapter and the complete intake-to-execution path in the intended OBaaS/OKE target; repository tests and local tooling do not establish target deployment readiness.

### 2. Document Extraction

- **OK** — workflow v1 calls the protected `document-ingest` workflow endpoint with identifiers rather than PDF content.
- **OK** — the ingest service obtains its own service authorization, retrieves the manifest and PDF from the loan service, checks content length and SHA-256, persists structured extraction data, acknowledges status, and supports idempotent replay.
- **OK** — workflow v1 configures HTTP retries and encloses extraction plus review in a loop capped at three extraction attempts.
- **TO-BE-DONE** — prove the `APP-OPFAIL-004` retry-and-recovery scenario in a deployed MicroTx execution; the fixture and generic retry mechanics exist, but the workflow verification assets do not demonstrate this canonical scenario end to end.

### 3. Document Review

- **OK** — `document-review-service` exposes the protected idempotent review task and receives application, workflow, task, and trace identifiers only.
- **OK** — it fetches document inventory and bounded extraction evidence through owning-service APIs, applies deterministic required-document, extraction-quality, and consistency rules, persists results, and returns `CLEAR`, `MANUAL_REVIEW`, `RETRY_EXTRACTION`, or `BLOCKED`.
- **OK** — workflow v1 normalizes the result, loops on `RETRY_EXTRACTION`, continues `CLEAR` and `MANUAL_REVIEW`, and terminates `BLOCKED`, exhausted retry, and unexpected dispositions for remediation without treating them as loan rejection.
- **TO-BE-DONE** — execute the release-gate validation of the `DO_WHILE` structure and nested output expressions against the actual target Workflow Server.

### 4. AI Document Evidence Summary

- **OK** — workflow v1 invokes the protected `ai_document_evidence_summary` HTTP task with identifiers only. The service reads bounded correlated review and extraction evidence with its own OAuth identity and calls Spring AI/OCI using OKE Workload Identity.
- **OK** — schema and content validation protect the summary, authoritative issues/references are assembled by the service, and validated redacted results are persisted in the AI service's own Oracle result table for durable replay.
- **OK** — after three retries, unavailable summaries are normalized to `AI_DOCUMENT_SUMMARY_UNAVAILABLE`. Existing MANUAL_REVIEW decisions retain their underwriter gate with summary-availability information; already-final decisions continue without an additional HUMAN task or a change to the deterministic outcome.
- **TO-BE-DONE** — validate the migration, live OCI call, and non-blocking summary failures for final and MANUAL_REVIEW decisions against the target OBaaS/MicroTx environment.

### 5. Policy Evidence Retrieval

- **OK** — workflow v1 invokes the protected `policy_evidence_retrieval` task, and `policy-retrieval-service` implements authorized, bounded Oracle vector-backed policy-chunk retrieval.
- **OK** — `prepare_policy_evidence_support` caps and minimizes the retrieval response before it crosses the AI boundary.
- **TO-BE-DONE** — provide and validate the required OCI embedding configuration and cluster-reachable service settings in the target environment.

### 6. AI Policy Evidence Support

- **OK** — workflow v1 invokes `ai_policy_evidence_support` before final evidence routing and uses the active workflow authorization.
- **OK** — `ai-agent-service` implements deterministic typed policy support with bounded citations and an explicit insufficient-evidence result.
- **TO-BE-DONE** — implement and validate governed Spring AI/OCI model execution and production audit/observability for this task.

### 7. Risk Signal Evaluation

- **OK** — workflow v1 invokes the protected, idempotent `evaluate_geographic_risk` task and combines its disposition with document and policy evidence without converting `BLOCKED` into a lending rejection.
- **OK** — the Helidon `geographic-risk-service` implements deterministic Oracle Spatial evaluation, persistence, authorization, correlation, and an `APP-RISK-005` component smoke-test fixture.
- **TO-BE-DONE** — implement the broader `risk-signal-service` for graph, identity, and relationship signals and integrate its bounded result into workflow routing/decisioning.

### 8. Deterministic Decision

- **OK** — `decision-service` exposes protected idempotent create/read APIs,
  applies `decision-rules-v1` to typed facts with a deterministic DTI
  calculation, persists the restricted fact snapshot and policy citations,
  and updates canonical state through `loan-application-service`.
- **OK** — workflow v1 invokes the mandatory initial decision with three
  retries, routes `APPROVED`, `REJECTED`, and `MANUAL_REVIEW`, and invokes a
  mandatory manual-final decision after HUMAN completion and authorization
  refresh.
- **TO-BE-DONE** — deploy and exercise all three decision outcomes and the
  post-HUMAN call against the intended MicroTx/OBaaS target.

### 9. AI Manual Review Assistant

- **OK** — only an initial deterministic `MANUAL_REVIEW` outcome invokes the protected `ai_manual_review_assistant` task before the HUMAN task.
- **OK** — the governed Spring AI/OCI implementation returns a typed checklist and clarification questions without resolving the human task or making a lending decision.
- **OK** — after the configured retries, an unavailable assistance response is normalized to `AI_ASSISTANCE_UNAVAILABLE` and the mandatory HUMAN review still opens, as required by the manual-review specification.
- **TO-BE-DONE** — extend the bounded assistant contract and read APIs with policy, risk, and audit references when those upstream contracts are finalized.

### 10. Human Review Gate

- **OK** — workflow v1 contains `human_task_manual_review` for initial MANUAL_REVIEW outcomes and supplies decision, document, policy, geographic-risk, routing-reason, and assistance-availability references. Final initial outcomes continue without an additional human inspection gate when document-summary assistance is unavailable.
- **OK** — after HUMAN completion it schedules the `refresh_workflow_authorization` SIMPLE task; the implemented worker obtains a fresh short-lived service token, and the following `SET_VARIABLE` task installs it for later protected calls.
- **OK** — the resumed path requires an underwriter outcome, reviewer identifier, stable reason code, and policy section before calling the manual-final decision.
- **TO-BE-DONE** — validate authorized human-task completion, worker polling, token masking/refresh, resume behavior, and the manual-final call in the target MicroTx environment.
- **TO-BE-DONE** — replace the interim bearer token held in workflow state when a verified platform-managed task-authentication mechanism is available; add `manual-review-service` only if a CloudBank-owned review queue/API remains required beyond the built-in HUMAN task UI/API.

### 11. AI Decision Explanation Draft

- **TO-BE-DONE** — add the explanation endpoint and governed AI implementation after deterministic decision facts exist, then add the post-decision MicroTx task with role-specific grounding, citation, and redaction controls.

### 12. Audit and Correlation

- **OK** — intake persists an audit event and telemetry correlation anchor, participating tasks carry stable application/workflow/task/trace identifiers, and service implementations include bounded correlation and idempotency handling.
- **OK** — Oracle schema assets exist for workflow events, audit events, and telemetry correlation.
- **TO-BE-DONE** — implement `audit-service` and `observability-correlation-service`, add explicit workflow tasks/events, and ensure every task handler writes redacted `CB_WORKFLOW_EVENT` and safe `CB_TELEMETRY_CORRELATION` records with end-to-end SigNoz trace linkage.

### 13. Completion or Compensation

- **TO-BE-DONE** — define successful completion semantics, canonical final application-status updates, and compensation for partial acknowledgements, open human tasks, notification attempts, and other side effects. Workflow v1 has no failure workflow or compensation tasks and currently uses terminal failure for remediation cases.

### 14. Loan Amount Transfer

- **TO-BE-DONE** — implement or integrate the Account service XA operations, define the distributed transaction boundary, add the transfer and delivered-status update tasks, and verify rollback/recovery behavior. No Account/XA transfer task exists in workflow v1.

## Cross-Cutting Readiness

- **OK** — versioned workflow and task-definition JSON, authenticated validation/upsert logic, metadata verification, sample input, protected service endpoints, retry/idempotency keys, masked authorization fields, and component tests/smoke tests exist.
- **TO-BE-DONE** — deploy and validate version 1 on the intended MicroTx/OBaaS environment; complete the OBaaS/OKE deployment section, which is currently marked TBD.
- **TO-BE-DONE** — add automated execution assertions that poll MicroTx through terminal or HUMAN state and verify task history/output for `CLEAR`, `MANUAL_REVIEW`, `RETRY_EXTRACTION`, `BLOCKED`, and post-human authorization refresh. The current loan smoke test proves dispatch to `STARTED`, not complete workflow behavior.
- **TO-BE-DONE** — complete all five canonical scenario paths in the target environment. Approval and rejection logic now exist; recovered-failure and relationship-risk coverage plus end-to-end assertions remain incomplete.

## Minimum Remaining Delivery Sequence

1. **TO-BE-DONE** — validate the existing workflow-v1 control flow and post-human token refresh on the target Workflow Server, with automated execution assertions.
2. **TO-BE-DONE** — implement broader graph, identity, and relationship risk signals and feed their bounded dispositions into decisioning.
3. **TO-BE-DONE** — implement the AI decision-explanation task and production Spring AI/OCI adapters for all AI tasks.
4. **TO-BE-DONE** — implement workflow-wide audit/correlation and explicit completion/compensation behavior.
5. **TO-BE-DONE** — implement and validate the optional Account-service XA loan-transfer phase.
