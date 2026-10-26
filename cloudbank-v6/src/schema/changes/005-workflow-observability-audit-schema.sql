-- CloudBank AI 2026.0
-- 005-workflow-observability-audit-schema.sql
-- Decisioning, explanations, manual review, MicroTx Workflow state, telemetry, and audit.

CREATE TABLE cb_decision (
  decision_sk NUMBER(18,0) GENERATED ALWAYS AS IDENTITY,
  application_sk NUMBER(18,0) NOT NULL,
  decision_id VARCHAR2(80) NOT NULL,
  decision_type VARCHAR2(40) NOT NULL,
  decision_outcome VARCHAR2(40) NOT NULL,
  risk_band VARCHAR2(20),
  policy_version VARCHAR2(20) DEFAULT '2026.0' NOT NULL,
  decision_payload JSON,
  decided_by VARCHAR2(80) DEFAULT 'decision-service' NOT NULL,
  decided_at TIMESTAMP WITH LOCAL TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT cb_decision_pk PRIMARY KEY (decision_sk),
  CONSTRAINT cb_decision_uk UNIQUE (decision_id),
  CONSTRAINT cb_decision_app_type_uk UNIQUE (application_sk, decision_type),
  CONSTRAINT cb_decision_app_fk FOREIGN KEY (application_sk) REFERENCES cb_loan_application (application_sk),
  CONSTRAINT cb_decision_type_ck CHECK (decision_type IN ('INITIAL','RECOVERED','MANUAL_FINAL','ADVERSE')),
  CONSTRAINT cb_decision_outcome_ck CHECK (decision_outcome IN ('APPROVED','REJECTED','MANUAL_REVIEW','FAILED_RETRYABLE','RECOVERED')),
  CONSTRAINT cb_decision_risk_ck CHECK (risk_band IS NULL OR risk_band IN ('CB-A','CB-B','CB-C','CB-X','NOT_SCORED'))
);

CREATE TABLE cb_decision_policy_evidence (
  decision_evidence_sk NUMBER(18,0) GENERATED ALWAYS AS IDENTITY,
  decision_sk NUMBER(18,0) NOT NULL,
  policy_chunk_sk NUMBER(18,0),
  evidence_id VARCHAR2(100) NOT NULL,
  policy_code VARCHAR2(40) NOT NULL,
  section_ref VARCHAR2(80) NOT NULL,
  evidence_role VARCHAR2(40) NOT NULL,
  evidence_summary VARCHAR2(1000) NOT NULL,
  created_at TIMESTAMP WITH LOCAL TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT cb_decision_evidence_pk PRIMARY KEY (decision_evidence_sk),
  CONSTRAINT cb_decision_evidence_uk UNIQUE (evidence_id),
  CONSTRAINT cb_dec_evidence_decision_fk FOREIGN KEY (decision_sk) REFERENCES cb_decision (decision_sk),
  CONSTRAINT cb_dec_evidence_chunk_fk FOREIGN KEY (policy_chunk_sk) REFERENCES cb_policy_chunk (policy_chunk_sk),
  CONSTRAINT cb_dec_evidence_role_ck CHECK (evidence_role IN ('ELIGIBILITY','INCOME','CAPACITY','PRICING','ROUTING','ADVERSE_ACTION','SECURITY'))
);

CREATE TABLE cb_explanation (
  explanation_sk NUMBER(18,0) GENERATED ALWAYS AS IDENTITY,
  decision_sk NUMBER(18,0) NOT NULL,
  explanation_id VARCHAR2(80) NOT NULL,
  audience VARCHAR2(40) NOT NULL,
  explanation_status VARCHAR2(40) DEFAULT 'READY' NOT NULL,
  explanation_text CLOB NOT NULL,
  explanation_payload JSON,
  created_at TIMESTAMP WITH LOCAL TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT cb_explanation_pk PRIMARY KEY (explanation_sk),
  CONSTRAINT cb_explanation_uk UNIQUE (explanation_id),
  CONSTRAINT cb_explanation_dec_aud_uk UNIQUE (decision_sk, audience),
  CONSTRAINT cb_explanation_decision_fk FOREIGN KEY (decision_sk) REFERENCES cb_decision (decision_sk),
  CONSTRAINT cb_explanation_aud_ck CHECK (audience IN ('APPLICANT','LOAN_OFFICER','UNDERWRITER','AUDITOR')),
  CONSTRAINT cb_explanation_status_ck CHECK (explanation_status IN ('DRAFT','READY','SUPPRESSED','ARCHIVED'))
);

CREATE TABLE cb_manual_review_task (
  review_task_sk NUMBER(18,0) GENERATED ALWAYS AS IDENTITY,
  application_sk NUMBER(18,0) NOT NULL,
  task_id VARCHAR2(80) NOT NULL,
  task_type VARCHAR2(60) NOT NULL,
  task_status VARCHAR2(40) DEFAULT 'OPEN' NOT NULL,
  priority VARCHAR2(20) DEFAULT 'NORMAL' NOT NULL,
  assigned_to_principal_id VARCHAR2(80),
  due_at TIMESTAMP WITH LOCAL TIME ZONE,
  reason_code VARCHAR2(120) NOT NULL,
  task_payload JSON,
  created_at TIMESTAMP WITH LOCAL TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  updated_at TIMESTAMP WITH LOCAL TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT cb_manual_review_task_pk PRIMARY KEY (review_task_sk),
  CONSTRAINT cb_manual_review_task_uk UNIQUE (task_id),
  CONSTRAINT cb_review_task_app_fk FOREIGN KEY (application_sk) REFERENCES cb_loan_application (application_sk),
  CONSTRAINT cb_review_task_type_ck CHECK (task_type IN ('INCOME_REVIEW','IDENTITY_REVIEW','OPERATIONAL_RETRY','ADVERSE_REVIEW','GENERAL_REVIEW')),
  CONSTRAINT cb_review_task_status_ck CHECK (task_status IN ('OPEN','ASSIGNED','IN_PROGRESS','COMPLETED','CANCELLED')),
  CONSTRAINT cb_review_task_priority_ck CHECK (priority IN ('LOW','NORMAL','HIGH','URGENT')),
  CONSTRAINT cb_review_task_dates_ck CHECK (updated_at >= created_at)
);

CREATE TABLE cb_workflow_instance (
  workflow_instance_sk NUMBER(18,0) GENERATED ALWAYS AS IDENTITY,
  application_sk NUMBER(18,0) NOT NULL,
  workflow_id VARCHAR2(80) NOT NULL,
  workflow_name VARCHAR2(120) DEFAULT 'cloudbank-loan-origination' NOT NULL,
  workflow_engine VARCHAR2(80) DEFAULT 'MicroTx Workflow' NOT NULL,
  workflow_status VARCHAR2(40) NOT NULL,
  trace_id VARCHAR2(80) NOT NULL,
  started_at TIMESTAMP WITH LOCAL TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  completed_at TIMESTAMP WITH LOCAL TIME ZONE,
  workflow_payload JSON,
  CONSTRAINT cb_workflow_instance_pk PRIMARY KEY (workflow_instance_sk),
  CONSTRAINT cb_workflow_instance_uk UNIQUE (workflow_id),
  CONSTRAINT cb_workflow_app_fk FOREIGN KEY (application_sk) REFERENCES cb_loan_application (application_sk),
  CONSTRAINT cb_workflow_status_ck CHECK (workflow_status IN ('STARTED','RUNNING','WAITING','FAILED_RETRYABLE','RECOVERED','COMPLETED','CANCELLED')),
  CONSTRAINT cb_workflow_dates_ck CHECK (completed_at IS NULL OR completed_at >= started_at)
);

CREATE TABLE cb_workflow_event (
  workflow_event_sk NUMBER(18,0) GENERATED ALWAYS AS IDENTITY,
  workflow_instance_sk NUMBER(18,0) NOT NULL,
  event_id VARCHAR2(100) NOT NULL,
  event_type VARCHAR2(80) NOT NULL,
  event_status VARCHAR2(40) NOT NULL,
  service_name VARCHAR2(120) NOT NULL,
  event_payload JSON,
  trace_id VARCHAR2(80) NOT NULL,
  span_id VARCHAR2(80),
  event_at TIMESTAMP WITH LOCAL TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT cb_workflow_event_pk PRIMARY KEY (workflow_event_sk),
  CONSTRAINT cb_workflow_event_uk UNIQUE (event_id),
  CONSTRAINT cb_workflow_event_inst_fk FOREIGN KEY (workflow_instance_sk) REFERENCES cb_workflow_instance (workflow_instance_sk),
  CONSTRAINT cb_workflow_event_status_ck CHECK (event_status IN ('STARTED','SUCCEEDED','FAILED_RETRYABLE','FAILED_FINAL','SKIPPED'))
);

CREATE TABLE cb_telemetry_correlation (
  telemetry_correlation_sk NUMBER(18,0) GENERATED ALWAYS AS IDENTITY,
  application_sk NUMBER(18,0) NOT NULL,
  correlation_id VARCHAR2(100) NOT NULL,
  trace_id VARCHAR2(80) NOT NULL,
  span_id VARCHAR2(80),
  service_name VARCHAR2(120) NOT NULL,
  telemetry_kind VARCHAR2(40) NOT NULL,
  safe_attributes_json JSON,
  created_at TIMESTAMP WITH LOCAL TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT cb_telemetry_correlation_pk PRIMARY KEY (telemetry_correlation_sk),
  CONSTRAINT cb_telemetry_correlation_uk UNIQUE (correlation_id),
  CONSTRAINT cb_telemetry_app_fk FOREIGN KEY (application_sk) REFERENCES cb_loan_application (application_sk),
  CONSTRAINT cb_telemetry_kind_ck CHECK (telemetry_kind IN ('TRACE','METRIC','LOG','AUDIT'))
);

CREATE TABLE cb_audit_event (
  audit_event_sk NUMBER(18,0) GENERATED ALWAYS AS IDENTITY,
  application_sk NUMBER(18,0),
  audit_event_id VARCHAR2(100) NOT NULL,
  principal_id VARCHAR2(80),
  event_action VARCHAR2(80) NOT NULL,
  event_outcome VARCHAR2(40) NOT NULL,
  object_type VARCHAR2(80) NOT NULL,
  object_id VARCHAR2(100),
  trace_id VARCHAR2(80),
  redaction_applied VARCHAR2(5) DEFAULT 'true' NOT NULL,
  event_payload JSON,
  created_at TIMESTAMP WITH LOCAL TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT cb_audit_event_pk PRIMARY KEY (audit_event_sk),
  CONSTRAINT cb_audit_event_uk UNIQUE (audit_event_id),
  CONSTRAINT cb_audit_event_app_fk FOREIGN KEY (application_sk) REFERENCES cb_loan_application (application_sk),
  CONSTRAINT cb_audit_event_outcome_ck CHECK (event_outcome IN ('SUCCESS','DENIED','ERROR')),
  CONSTRAINT cb_audit_redaction_ck CHECK (redaction_applied IN ('true','false'))
);

CREATE INDEX cb_decision_app_outcome_ix ON cb_decision (application_sk, decision_outcome, decided_at);
CREATE INDEX cb_dec_evidence_dec_ix ON cb_decision_policy_evidence (decision_sk, policy_code, section_ref);
CREATE INDEX cb_review_queue_ix ON cb_manual_review_task (task_status, priority, created_at);
CREATE INDEX cb_review_app_ix ON cb_manual_review_task (application_sk, task_status);
CREATE INDEX cb_workflow_app_ix ON cb_workflow_instance (application_sk, workflow_status);
CREATE INDEX cb_workflow_trace_ix ON cb_workflow_instance (trace_id);
CREATE INDEX cb_workflow_event_inst_ix ON cb_workflow_event (workflow_instance_sk, event_at);
CREATE INDEX cb_workflow_event_trace_ix ON cb_workflow_event (trace_id, span_id);
CREATE INDEX cb_telemetry_app_trace_ix ON cb_telemetry_correlation (application_sk, trace_id);
CREATE INDEX cb_audit_app_trace_ix ON cb_audit_event (application_sk, trace_id, created_at);
CREATE INDEX cb_audit_principal_ix ON cb_audit_event (principal_id, created_at);
