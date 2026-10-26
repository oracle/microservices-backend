-- CloudBank AI 2026.0
-- Immutable, redacted document-summary results. No prompts, evidence payloads,
-- raw model responses, reasoning, tokens, or credentials may be stored here.

CREATE TABLE cb_ai_document_summary (
  summary_id VARCHAR2(38) NOT NULL,
  key_hash VARCHAR2(64) NOT NULL,
  request_hash VARCHAR2(64) NOT NULL,
  application_id VARCHAR2(40) NOT NULL,
  workflow_id VARCHAR2(100) NOT NULL,
  task_reference VARCHAR2(80) NOT NULL,
  trace_id VARCHAR2(32) NOT NULL,
  review_id VARCHAR2(37) NOT NULL,
  result_payload JSON NOT NULL,
  created_at TIMESTAMP WITH LOCAL TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT cb_ai_doc_summary_pk PRIMARY KEY (summary_id),
  CONSTRAINT cb_ai_doc_summary_key_uk UNIQUE (key_hash)
);

COMMENT ON TABLE cb_ai_document_summary IS 'ai-agent-service owns validated redacted document-summary results and durable idempotent replay; no lending decisions or raw model material.';
COMMENT ON COLUMN cb_ai_document_summary.result_payload IS 'Validated reviewer-safe response only; excludes prompts, raw evidence, reasoning, credentials and unrestricted applicant facts.';
COMMENT ON COLUMN cb_ai_document_summary.key_hash IS 'SHA-256 of the service idempotency key; never the raw key or authentication material.';
COMMENT ON COLUMN cb_ai_document_summary.summary_id IS 'Opaque durable reviewer-assistance identifier; not a lending outcome.';
COMMENT ON COLUMN cb_ai_document_summary.request_hash IS 'Fingerprint of reference and correlation metadata for conflict detection; contains no source evidence.';
COMMENT ON COLUMN cb_ai_document_summary.application_id IS 'Application reference for workflow correlation; restricted customer metadata.';
COMMENT ON COLUMN cb_ai_document_summary.workflow_id IS 'MicroTx workflow correlation reference for the validated result.';
COMMENT ON COLUMN cb_ai_document_summary.task_reference IS 'Protected document-summary workflow task reference.';
COMMENT ON COLUMN cb_ai_document_summary.trace_id IS 'W3C trace identifier for safe operational correlation.';
COMMENT ON COLUMN cb_ai_document_summary.review_id IS 'Authorized completed deterministic document-review reference.';
COMMENT ON COLUMN cb_ai_document_summary.created_at IS 'Time the validated redacted result became durable.';

ALTER TABLE cb_ai_document_summary ANNOTATIONS (
  ADD OwnerService 'ai-agent-service',
  ADD DataClassification 'restricted_customer',
  ADD AIUsage 'Validated reviewer assistance only; no lending decisions',
  ADD SecurityModel 'Least privilege service-owned immutable result store'
);

ALTER TABLE cb_ai_document_summary MODIFY result_payload ANNOTATIONS (
  ADD DataClassification 'restricted_customer',
  ADD AIUsage 'Redacted validated result only; no prompts or raw responses'
);
