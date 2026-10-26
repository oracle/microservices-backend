-- CloudBank AI 2026.0
-- Durable deterministic document-review envelope. BLOCKED is a processing outcome, never a loan decision.

CREATE TABLE cb_document_review (
  document_review_sk NUMBER(18,0) GENERATED ALWAYS AS IDENTITY,
  application_sk NUMBER(18,0) NOT NULL,
  review_id VARCHAR2(40) NOT NULL,
  workflow_id VARCHAR2(100) NOT NULL,
  task_reference VARCHAR2(120) NOT NULL,
  idempotency_key_hash VARCHAR2(64) NOT NULL,
  request_hash VARCHAR2(64) NOT NULL,
  input_fingerprint VARCHAR2(64) NOT NULL,
  profile_version VARCHAR2(80) NOT NULL,
  review_status VARCHAR2(20) NOT NULL,
  disposition VARCHAR2(30) NOT NULL,
  result_payload JSON NOT NULL,
  trace_id VARCHAR2(32) NOT NULL,
  created_at TIMESTAMP WITH LOCAL TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  updated_at TIMESTAMP WITH LOCAL TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  completed_at TIMESTAMP WITH LOCAL TIME ZONE,
  CONSTRAINT cb_document_review_pk PRIMARY KEY (document_review_sk),
  CONSTRAINT cb_document_review_id_uk UNIQUE (review_id),
  CONSTRAINT cb_document_review_idem_uk UNIQUE (idempotency_key_hash),
  CONSTRAINT cb_document_review_app_fk FOREIGN KEY (application_sk) REFERENCES cb_loan_application (application_sk),
  CONSTRAINT cb_document_review_status_ck CHECK (review_status IN ('ACK_PENDING','COMPLETED')),
  CONSTRAINT cb_document_review_disp_ck CHECK (disposition IN ('CLEAR','MANUAL_REVIEW','RETRY_EXTRACTION','BLOCKED')),
  CONSTRAINT cb_document_review_trace_ck CHECK (REGEXP_LIKE(trace_id, '^[[:xdigit:]]{32}$')),
  CONSTRAINT cb_document_review_hash_ck CHECK (REGEXP_LIKE(idempotency_key_hash, '^[[:xdigit:]]{64}$') AND REGEXP_LIKE(request_hash, '^[[:xdigit:]]{64}$') AND REGEXP_LIKE(input_fingerprint, '^[[:xdigit:]]{64}$'))
);

CREATE INDEX cb_document_review_app_ix ON cb_document_review (application_sk, created_at);
CREATE INDEX cb_document_review_workflow_ix ON cb_document_review (workflow_id, task_reference);
CREATE INDEX cb_document_review_trace_ix ON cb_document_review (trace_id);

COMMENT ON TABLE cb_document_review IS 'Durable deterministic document-quality reviews. It does not make a lending decision.';
COMMENT ON COLUMN cb_document_review.review_id IS 'Stable DREV identifier returned to workflow callers.';
COMMENT ON COLUMN cb_document_review.idempotency_key_hash IS 'SHA-256 digest of the caller idempotency key; the original key is never stored.';
COMMENT ON COLUMN cb_document_review.input_fingerprint IS 'SHA-256 fingerprint of bounded manifest and extraction review input.';
COMMENT ON COLUMN cb_document_review.result_payload IS 'Bounded immutable review-time evidence and issue result; excludes PDFs and raw extraction payloads.';
COMMENT ON COLUMN cb_document_review.disposition IS 'Workflow document-processing disposition; BLOCKED is not a loan rejection.';

ALTER TABLE cb_document_review ANNOTATIONS (
  ADD classification 'restricted_customer',
  ADD ai_usage 'deterministic_review_only'
);
