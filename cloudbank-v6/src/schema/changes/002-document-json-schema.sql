-- CloudBank AI 2026.0
-- 002-document-json-schema.sql
-- Document inventory, extraction JSON, promoted facts, validation issues, and RAG chunks.

CREATE TABLE cb_document (
  document_sk NUMBER(18,0) GENERATED ALWAYS AS IDENTITY,
  application_sk NUMBER(18,0) NOT NULL,
  document_id VARCHAR2(60) NOT NULL,
  document_type VARCHAR2(60) NOT NULL,
  file_name VARCHAR2(260) NOT NULL,
  content_sha256 VARCHAR2(64) NOT NULL,
  source_packet_path VARCHAR2(500) NOT NULL,
  document_status VARCHAR2(40) DEFAULT 'RECEIVED' NOT NULL,
  min_role VARCHAR2(40) DEFAULT 'LOAN_OFFICER' NOT NULL,
  data_classification VARCHAR2(40) DEFAULT 'restricted_customer' NOT NULL,
  received_at TIMESTAMP WITH LOCAL TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT cb_document_pk PRIMARY KEY (document_sk),
  CONSTRAINT cb_document_uk UNIQUE (document_id),
  CONSTRAINT cb_document_app_file_uk UNIQUE (application_sk, file_name),
  CONSTRAINT cb_document_app_fk FOREIGN KEY (application_sk) REFERENCES cb_loan_application (application_sk),
  CONSTRAINT cb_document_sha_ck CHECK (REGEXP_LIKE(content_sha256, '^[[:xdigit:]]{64}$')),
  CONSTRAINT cb_document_type_ck CHECK (document_type IN (
    'LOAN_APPLICATION','DISCLOSURE_CONSENT','IDENTITY_SUMMARY','ADDRESS_VERIFICATION',
    'INCOME_VALIDATION','PAY_STATEMENT','DEPOSIT_SUMMARY','ACCOUNT_ACTIVITY',
    'CONTRACTOR_INCOME','LIABILITY_SCHEDULE','PAYMENT_CALCULATION',
    'CLARIFICATION_REQUEST','DOCUMENT_RECEIPT','RELATIONSHIP_SIGNAL'
  )),
  CONSTRAINT cb_document_status_ck CHECK (document_status IN ('RECEIVED','EXTRACTED','VALIDATED','NEEDS_REVIEW','FAILED_RETRYABLE','FAILED_FINAL')),
  CONSTRAINT cb_document_role_ck CHECK (min_role IN ('APPLICANT','LOAN_OFFICER','UNDERWRITER','AUDITOR','ADMIN')),
  CONSTRAINT cb_document_class_ck CHECK (data_classification IN ('public_demo','internal','restricted_customer','restricted_policy'))
);

CREATE TABLE cb_document_extraction (
  extraction_sk NUMBER(18,0) GENERATED ALWAYS AS IDENTITY,
  document_sk NUMBER(18,0) NOT NULL,
  application_sk NUMBER(18,0) NOT NULL,
  extraction_id VARCHAR2(80) NOT NULL,
  provider VARCHAR2(60) NOT NULL,
  extraction_model VARCHAR2(120),
  extraction_status VARCHAR2(40) NOT NULL,
  extraction_payload JSON NOT NULL,
  raw_text_line_count NUMBER(8,0) DEFAULT 0 NOT NULL,
  confidence_score NUMBER(5,4),
  retry_count NUMBER(3,0) DEFAULT 0 NOT NULL,
  trace_id VARCHAR2(80),
  created_at TIMESTAMP WITH LOCAL TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT cb_document_extraction_pk PRIMARY KEY (extraction_sk),
  CONSTRAINT cb_document_extraction_uk UNIQUE (extraction_id),
  CONSTRAINT cb_doc_extract_doc_fk FOREIGN KEY (document_sk) REFERENCES cb_document (document_sk),
  CONSTRAINT cb_doc_extract_app_fk FOREIGN KEY (application_sk) REFERENCES cb_loan_application (application_sk),
  CONSTRAINT cb_doc_extract_status_ck CHECK (extraction_status IN ('PENDING','SUCCEEDED','LOW_CONFIDENCE','FAILED_RETRYABLE','FAILED_FINAL','RECOVERED')),
  CONSTRAINT cb_doc_extract_provider_ck CHECK (provider IN ('DOCUMENT_INGEST','OCI_VISION','OCI_GENERATIVE_AI','LLM_ASSISTED','RULE_BASED')),
  CONSTRAINT cb_doc_extract_conf_ck CHECK (confidence_score IS NULL OR confidence_score BETWEEN 0 AND 1),
  CONSTRAINT cb_doc_extract_line_ck CHECK (raw_text_line_count >= 0),
  CONSTRAINT cb_doc_extract_retry_ck CHECK (retry_count BETWEEN 0 AND 9)
);

CREATE TABLE cb_document_fact (
  document_fact_sk NUMBER(18,0) GENERATED ALWAYS AS IDENTITY,
  application_sk NUMBER(18,0) NOT NULL,
  document_sk NUMBER(18,0),
  fact_name VARCHAR2(100) NOT NULL,
  fact_value_text VARCHAR2(1000),
  fact_value_number NUMBER(18,4),
  fact_value_date DATE,
  confidence_score NUMBER(5,4),
  source_field_path VARCHAR2(300),
  created_at TIMESTAMP WITH LOCAL TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT cb_document_fact_pk PRIMARY KEY (document_fact_sk),
  CONSTRAINT cb_document_fact_app_name_uk UNIQUE (application_sk, fact_name),
  CONSTRAINT cb_doc_fact_app_fk FOREIGN KEY (application_sk) REFERENCES cb_loan_application (application_sk),
  CONSTRAINT cb_doc_fact_doc_fk FOREIGN KEY (document_sk) REFERENCES cb_document (document_sk),
  CONSTRAINT cb_doc_fact_value_ck CHECK (
    fact_value_text IS NOT NULL OR fact_value_number IS NOT NULL OR fact_value_date IS NOT NULL
  ),
  CONSTRAINT cb_doc_fact_conf_ck CHECK (confidence_score IS NULL OR confidence_score BETWEEN 0 AND 1)
);

CREATE TABLE cb_document_issue (
  document_issue_sk NUMBER(18,0) GENERATED ALWAYS AS IDENTITY,
  application_sk NUMBER(18,0) NOT NULL,
  document_sk NUMBER(18,0),
  issue_code VARCHAR2(120) NOT NULL,
  issue_severity VARCHAR2(40) NOT NULL,
  routing_effect VARCHAR2(60) NOT NULL,
  policy_hint VARCHAR2(80),
  issue_detail VARCHAR2(1000),
  detected_at TIMESTAMP WITH LOCAL TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT cb_document_issue_pk PRIMARY KEY (document_issue_sk),
  CONSTRAINT cb_doc_issue_uk UNIQUE (application_sk, issue_code),
  CONSTRAINT cb_doc_issue_app_fk FOREIGN KEY (application_sk) REFERENCES cb_loan_application (application_sk),
  CONSTRAINT cb_doc_issue_doc_fk FOREIGN KEY (document_sk) REFERENCES cb_document (document_sk),
  CONSTRAINT cb_doc_issue_sev_ck CHECK (issue_severity IN ('INFO','WARNING','REVIEW','BLOCKING')),
  CONSTRAINT cb_doc_issue_route_ck CHECK (routing_effect IN ('NONE','MANUAL_REVIEW','REJECT','RETRY','RECOVERED'))
);

CREATE TABLE cb_document_chunk (
  document_chunk_sk NUMBER(18,0) GENERATED ALWAYS AS IDENTITY,
  document_sk NUMBER(18,0) NOT NULL,
  application_sk NUMBER(18,0) NOT NULL,
  chunk_id VARCHAR2(80) NOT NULL,
  chunk_ordinal NUMBER(8,0) NOT NULL,
  chunk_text CLOB NOT NULL,
  chunk_metadata JSON,
  min_role VARCHAR2(40) DEFAULT 'LOAN_OFFICER' NOT NULL,
  access_label VARCHAR2(80) DEFAULT 'customer_document' NOT NULL,
  embedding VECTOR(*, FLOAT32),
  created_at TIMESTAMP WITH LOCAL TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT cb_document_chunk_pk PRIMARY KEY (document_chunk_sk),
  CONSTRAINT cb_document_chunk_uk UNIQUE (chunk_id),
  CONSTRAINT cb_doc_chunk_doc_ord_uk UNIQUE (document_sk, chunk_ordinal),
  CONSTRAINT cb_doc_chunk_doc_fk FOREIGN KEY (document_sk) REFERENCES cb_document (document_sk),
  CONSTRAINT cb_doc_chunk_app_fk FOREIGN KEY (application_sk) REFERENCES cb_loan_application (application_sk),
  CONSTRAINT cb_doc_chunk_ord_ck CHECK (chunk_ordinal >= 1),
  CONSTRAINT cb_doc_chunk_role_ck CHECK (min_role IN ('APPLICANT','LOAN_OFFICER','UNDERWRITER','AUDITOR','ADMIN'))
);

CREATE TABLE cb_income_evidence (
  income_evidence_sk NUMBER(18,0) GENERATED ALWAYS AS IDENTITY,
  application_sk NUMBER(18,0) NOT NULL,
  document_sk NUMBER(18,0),
  stated_gross_monthly_income NUMBER(12,2) NOT NULL,
  pay_document_monthly_income NUMBER(12,2),
  verified_gross_monthly_income NUMBER(12,2) NOT NULL,
  income_consistency_result VARCHAR2(80) NOT NULL,
  extraction_confidence VARCHAR2(40) NOT NULL,
  document_validation_status VARCHAR2(40) NOT NULL,
  evidence_timestamp TIMESTAMP WITH LOCAL TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT cb_income_evidence_pk PRIMARY KEY (income_evidence_sk),
  CONSTRAINT cb_income_evidence_app_uk UNIQUE (application_sk),
  CONSTRAINT cb_income_evidence_app_fk FOREIGN KEY (application_sk) REFERENCES cb_loan_application (application_sk),
  CONSTRAINT cb_income_evidence_doc_fk FOREIGN KEY (document_sk) REFERENCES cb_document (document_sk),
  CONSTRAINT cb_income_amt_ck CHECK (
    stated_gross_monthly_income >= 0
    AND verified_gross_monthly_income >= 0
    AND (pay_document_monthly_income IS NULL OR pay_document_monthly_income >= 0)
  ),
  CONSTRAINT cb_income_consistency_ck CHECK (income_consistency_result IN (
    'CONSISTENT_WITHIN_10_PERCENT','INCONSISTENT_OVER_20_PERCENT',
    'INSUFFICIENT_STABLE_RECURRING_EVIDENCE','NOT_EVALUATED'
  )),
  CONSTRAINT cb_income_conf_ck CHECK (extraction_confidence IN ('HIGH','HIGH_AFTER_RETRY','MEDIUM','LOW','FAILED')),
  CONSTRAINT cb_income_doc_status_ck CHECK (document_validation_status IN ('PASS','PASS_AFTER_RETRY','REVIEW','FAIL','NOT_EVALUATED'))
);

CREATE INDEX cb_document_app_ix ON cb_document (application_sk, document_type);
CREATE INDEX cb_document_role_ix ON cb_document (min_role, data_classification);
CREATE INDEX cb_doc_extract_app_ix ON cb_document_extraction (application_sk, extraction_status, created_at);
CREATE INDEX cb_doc_extract_trace_ix ON cb_document_extraction (trace_id);
