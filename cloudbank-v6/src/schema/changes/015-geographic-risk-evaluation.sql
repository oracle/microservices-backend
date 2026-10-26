-- CloudBank AI 2026.0
-- 015-geographic-risk-evaluation.sql
-- Evaluation envelope for the Helidon geographic-risk-service.

CREATE TABLE cb_geographic_risk_evaluation (
  evaluation_id VARCHAR2(80) NOT NULL,
  application_sk NUMBER(18,0) NOT NULL,
  workflow_id VARCHAR2(100) NOT NULL,
  task_reference VARCHAR2(120) NOT NULL,
  trace_id VARCHAR2(32) NOT NULL,
  idempotency_key VARCHAR2(200) NOT NULL,
  request_hash VARCHAR2(64) NOT NULL,
  disposition VARCHAR2(40) NOT NULL,
  service_name VARCHAR2(80) DEFAULT 'geographic-risk-service' NOT NULL,
  created_at TIMESTAMP WITH LOCAL TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  updated_at TIMESTAMP WITH LOCAL TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT cb_geo_risk_eval_pk PRIMARY KEY (evaluation_id),
  CONSTRAINT cb_geo_risk_eval_app_fk FOREIGN KEY (application_sk) REFERENCES cb_loan_application (application_sk),
  CONSTRAINT cb_geo_risk_eval_idem_uk UNIQUE (application_sk, idempotency_key),
  CONSTRAINT cb_geo_risk_eval_disp_ck CHECK (disposition IN ('CLEAR','MANUAL_REVIEW','BLOCKED','NOT_EVALUATED')),
  CONSTRAINT cb_geo_risk_eval_trace_ck CHECK (REGEXP_LIKE(trace_id, '^[0-9a-fA-F]{32}$')),
  CONSTRAINT cb_geo_risk_eval_hash_ck CHECK (REGEXP_LIKE(request_hash, '^[0-9a-fA-F]{64}$'))
);

ALTER TABLE cb_spatial_signal ADD geographic_evaluation_id VARCHAR2(80);

ALTER TABLE cb_spatial_signal ADD CONSTRAINT cb_spatial_signal_geo_eval_fk
  FOREIGN KEY (geographic_evaluation_id) REFERENCES cb_geographic_risk_evaluation (evaluation_id);

ALTER TABLE cb_spatial_signal DROP CONSTRAINT cb_spatial_signal_route_ck;

ALTER TABLE cb_spatial_signal ADD CONSTRAINT cb_spatial_signal_route_ck
  CHECK (routing_effect IN ('NONE','MANUAL_REVIEW','BLOCKED'));

CREATE INDEX cb_geo_risk_eval_app_ix ON cb_geographic_risk_evaluation (application_sk, created_at);
CREATE INDEX cb_geo_risk_eval_trace_ix ON cb_geographic_risk_evaluation (trace_id);
CREATE INDEX cb_spatial_signal_eval_ix ON cb_spatial_signal (geographic_evaluation_id);

COMMENT ON TABLE cb_geographic_risk_evaluation IS
  'Workflow-correlated evaluation envelope produced by the geographic-risk-service.';
COMMENT ON COLUMN cb_geographic_risk_evaluation.evaluation_id IS
  'Stable geographic risk evaluation identifier returned by the service API.';
COMMENT ON COLUMN cb_geographic_risk_evaluation.workflow_id IS
  'MicroTx workflow execution identifier supplied to the geographic risk task.';
COMMENT ON COLUMN cb_geographic_risk_evaluation.task_reference IS
  'MicroTx workflow task reference for the geographic risk evaluation.';
COMMENT ON COLUMN cb_geographic_risk_evaluation.trace_id IS
  'Trace-safe 32-character OpenTelemetry trace identifier.';
COMMENT ON COLUMN cb_geographic_risk_evaluation.idempotency_key IS
  'Caller-supplied key that makes workflow retries safe for the same application.';
COMMENT ON COLUMN cb_geographic_risk_evaluation.disposition IS
  'Overall geographic workflow disposition; BLOCKED is not a loan rejection.';
