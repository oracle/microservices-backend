-- CloudBank AI 2026.0
-- Durable workflow correlation and idempotency metadata for decision-service.

ALTER TABLE cb_decision ADD (
  workflow_id VARCHAR2(100),
  task_reference VARCHAR2(120),
  idempotency_key_hash VARCHAR2(64),
  request_hash VARCHAR2(64),
  trace_id VARCHAR2(80),
  CONSTRAINT cb_decision_idem_hash_ck CHECK (
    idempotency_key_hash IS NULL OR REGEXP_LIKE(idempotency_key_hash, '^[[:xdigit:]]{64}$')
  ),
  CONSTRAINT cb_decision_req_hash_ck CHECK (
    request_hash IS NULL OR REGEXP_LIKE(request_hash, '^[[:xdigit:]]{64}$')
  )
);

COMMENT ON COLUMN cb_decision.workflow_id IS
  'MicroTx workflow execution identifier; safe correlation metadata.';
COMMENT ON COLUMN cb_decision.task_reference IS
  'Stable MicroTx task reference that produced the decision.';
COMMENT ON COLUMN cb_decision.idempotency_key_hash IS
  'SHA-256 digest of the caller idempotency key; the original key is never stored.';
COMMENT ON COLUMN cb_decision.request_hash IS
  'SHA-256 digest of the canonical decision request used for conflict detection.';
COMMENT ON COLUMN cb_decision.trace_id IS
  'Trace correlation identifier; must not contain authentication material.';

CREATE UNIQUE INDEX cb_decision_idempotency_uk
  ON cb_decision (idempotency_key_hash);

CREATE INDEX cb_decision_workflow_ix
  ON cb_decision (workflow_id, task_reference);
