-- CloudBank AI 2026.0
-- 008-loan-application-intake.sql
-- Durable application intake, document readiness, and workflow-start outbox.

ALTER TABLE cb_loan_application ADD (
  scenario_name VARCHAR2(200),
  row_version NUMBER(18,0) DEFAULT 0 NOT NULL,
  submitted_by_principal_id VARCHAR2(80),
  submitted_by_issuer VARCHAR2(300),
  submitted_by_subject VARCHAR2(300),
  intake_idempotency_key VARCHAR2(200),
  intake_request_hash VARCHAR2(64)
);

UPDATE cb_loan_application SET scenario_name = scenario_id WHERE scenario_name IS NULL;
ALTER TABLE cb_loan_application MODIFY scenario_name NOT NULL;
ALTER TABLE cb_loan_application MODIFY expected_outcome NULL;
ALTER TABLE cb_loan_application ADD CONSTRAINT cb_loan_app_version_ck CHECK (row_version >= 0);
ALTER TABLE cb_loan_application ADD CONSTRAINT cb_loan_app_intake_hash_ck CHECK (
  intake_request_hash IS NULL OR REGEXP_LIKE(intake_request_hash, '^[[:xdigit:]]{64}$')
);
ALTER TABLE cb_loan_application ADD CONSTRAINT cb_loan_app_idempotency_uk
  UNIQUE (submitted_by_principal_id, intake_idempotency_key);

ALTER TABLE cb_document DROP CONSTRAINT cb_document_status_ck;
ALTER TABLE cb_document MODIFY content_sha256 NULL;
ALTER TABLE cb_document MODIFY source_packet_path NULL;
ALTER TABLE cb_document ADD (
  required_flag VARCHAR2(5) DEFAULT 'true' NOT NULL,
  media_type VARCHAR2(120),
  content_length_bytes NUMBER(18,0)
);
ALTER TABLE cb_document ADD CONSTRAINT cb_document_status_ck CHECK (
  document_status IN ('EXPECTED','RECEIVED','EXTRACTED','VALIDATED','NEEDS_REVIEW','FAILED_RETRYABLE','FAILED_FINAL')
);
ALTER TABLE cb_document ADD CONSTRAINT cb_document_required_ck CHECK (required_flag IN ('true','false'));
ALTER TABLE cb_document ADD CONSTRAINT cb_document_length_ck CHECK (
  content_length_bytes IS NULL OR content_length_bytes >= 0
);
ALTER TABLE cb_document ADD CONSTRAINT cb_document_received_metadata_ck CHECK (
  document_status = 'EXPECTED'
  OR (content_sha256 IS NOT NULL AND source_packet_path IS NOT NULL)
);

CREATE TABLE cb_workflow_start_request (
  workflow_start_request_sk NUMBER(18,0) GENERATED ALWAYS AS IDENTITY,
  application_sk NUMBER(18,0) NOT NULL,
  request_id VARCHAR2(100) NOT NULL,
  workflow_name VARCHAR2(120) DEFAULT 'cloudbank-loan-origination' NOT NULL,
  workflow_version NUMBER(8,0) DEFAULT 1 NOT NULL,
  start_mode VARCHAR2(20) DEFAULT 'AUTO' NOT NULL,
  dispatch_status VARCHAR2(40) NOT NULL,
  request_payload JSON NOT NULL,
  attempt_count NUMBER(4,0) DEFAULT 0 NOT NULL,
  next_attempt_at TIMESTAMP WITH LOCAL TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  claimed_at TIMESTAMP WITH LOCAL TIME ZONE,
  claimed_by VARCHAR2(120),
  engine_workflow_id VARCHAR2(100),
  trace_id VARCHAR2(80) NOT NULL,
  last_error_code VARCHAR2(80),
  last_error_message VARCHAR2(500),
  created_at TIMESTAMP WITH LOCAL TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  updated_at TIMESTAMP WITH LOCAL TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  dispatched_at TIMESTAMP WITH LOCAL TIME ZONE,
  CONSTRAINT cb_workflow_start_request_pk PRIMARY KEY (workflow_start_request_sk),
  CONSTRAINT cb_workflow_start_request_uk UNIQUE (request_id),
  CONSTRAINT cb_workflow_start_app_uk UNIQUE (application_sk, workflow_name, workflow_version),
  CONSTRAINT cb_workflow_start_app_fk FOREIGN KEY (application_sk) REFERENCES cb_loan_application (application_sk),
  CONSTRAINT cb_workflow_start_mode_ck CHECK (start_mode IN ('AUTO','DEFERRED')),
  CONSTRAINT cb_workflow_start_status_ck CHECK (dispatch_status IN (
    'WAITING_FOR_DOCUMENTS','DEFERRED','PENDING','IN_PROGRESS','STARTED','FAILED_RETRYABLE','FAILED_FINAL','CANCELLED'
  )),
  CONSTRAINT cb_workflow_start_attempt_ck CHECK (attempt_count BETWEEN 0 AND 99),
  CONSTRAINT cb_workflow_start_dates_ck CHECK (updated_at >= created_at)
);

CREATE TABLE cb_document_registration_request (
  document_registration_request_sk NUMBER(18,0) GENERATED ALWAYS AS IDENTITY,
  application_sk NUMBER(18,0) NOT NULL,
  principal_id VARCHAR2(80) NOT NULL,
  idempotency_key VARCHAR2(200) NOT NULL,
  request_hash VARCHAR2(64) NOT NULL,
  created_at TIMESTAMP WITH LOCAL TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT cb_document_registration_pk PRIMARY KEY (document_registration_request_sk),
  CONSTRAINT cb_document_registration_uk UNIQUE (application_sk, principal_id, idempotency_key),
  CONSTRAINT cb_document_registration_app_fk FOREIGN KEY (application_sk)
    REFERENCES cb_loan_application (application_sk),
  CONSTRAINT cb_document_registration_hash_ck CHECK (
    REGEXP_LIKE(request_hash, '^[[:xdigit:]]{64}$')
  )
);

ALTER TABLE cb_workflow_instance ADD workflow_start_request_sk NUMBER(18,0);
ALTER TABLE cb_workflow_instance ADD CONSTRAINT cb_workflow_instance_start_fk
  FOREIGN KEY (workflow_start_request_sk) REFERENCES cb_workflow_start_request (workflow_start_request_sk);
ALTER TABLE cb_workflow_instance ADD CONSTRAINT cb_workflow_instance_start_uk UNIQUE (workflow_start_request_sk);

ALTER TABLE cb_app_principal ADD external_issuer VARCHAR2(300);
CREATE UNIQUE INDEX cb_principal_external_uk ON cb_app_principal (external_issuer, external_subject);

CREATE INDEX cb_loan_app_submitter_ix ON cb_loan_application (submitted_by_principal_id, created_at);
CREATE INDEX cb_workflow_start_ready_ix ON cb_workflow_start_request (dispatch_status, next_attempt_at);
CREATE INDEX cb_workflow_start_trace_ix ON cb_workflow_start_request (trace_id);

MERGE INTO cb_app_principal target
USING (
  SELECT 'svc-loan-application' principal_id, 'SERVICE' principal_type,
         'Loan Application Service' display_name,
         'cloudbank-internal' external_issuer,
         'cloudbank-service-client' external_subject
  FROM dual
) source
ON (target.principal_id = source.principal_id)
WHEN NOT MATCHED THEN INSERT (
  principal_id, principal_type, display_name, external_issuer, external_subject
) VALUES (
  source.principal_id, source.principal_type, source.display_name,
  source.external_issuer, source.external_subject
);

MERGE INTO cb_app_role_grant target
USING (
  SELECT principal_sk FROM cb_app_principal WHERE principal_id = 'svc-loan-application'
) source
ON (target.principal_sk = source.principal_sk AND target.role_code = 'SERVICE')
WHEN NOT MATCHED THEN INSERT (principal_sk, role_code, granted_by)
VALUES (source.principal_sk, 'SERVICE', 'schema-migration');

CREATE ROLE cb_loan_application_runtime;
GRANT CREATE SESSION TO cb_loan_application_runtime;
GRANT SELECT, INSERT, UPDATE ON cb_applicant TO cb_loan_application_runtime;
GRANT SELECT, INSERT, UPDATE ON cb_loan_application TO cb_loan_application_runtime;
GRANT SELECT, INSERT, UPDATE ON cb_document TO cb_loan_application_runtime;
GRANT SELECT, INSERT ON cb_document_registration_request TO cb_loan_application_runtime;
GRANT SELECT, INSERT, UPDATE ON cb_workflow_start_request TO cb_loan_application_runtime;
GRANT SELECT, INSERT ON cb_workflow_instance TO cb_loan_application_runtime;
GRANT SELECT, INSERT ON cb_audit_event TO cb_loan_application_runtime;
GRANT SELECT, INSERT ON cb_telemetry_correlation TO cb_loan_application_runtime;
GRANT SELECT ON cb_app_principal TO cb_loan_application_runtime;
GRANT SELECT ON cb_app_role_grant TO cb_loan_application_runtime;
GRANT SELECT ON cb_data_grant TO cb_loan_application_runtime;
