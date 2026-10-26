-- CloudBank AI 2026.0
-- 006-security-roles-and-views.sql
-- Application principals, grants, and role-aware views.

CREATE TABLE cb_app_principal (
  principal_sk NUMBER(18,0) GENERATED ALWAYS AS IDENTITY,
  principal_id VARCHAR2(80) NOT NULL,
  principal_type VARCHAR2(40) NOT NULL,
  display_name VARCHAR2(200) NOT NULL,
  external_subject VARCHAR2(300),
  status VARCHAR2(20) DEFAULT 'ACTIVE' NOT NULL,
  created_at TIMESTAMP WITH LOCAL TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT cb_app_principal_pk PRIMARY KEY (principal_sk),
  CONSTRAINT cb_app_principal_uk UNIQUE (principal_id),
  CONSTRAINT cb_app_principal_type_ck CHECK (principal_type IN ('APPLICANT','EMPLOYEE','SERVICE','AUDITOR','ADMIN')),
  CONSTRAINT cb_app_principal_status_ck CHECK (status IN ('ACTIVE','DISABLED','LOCKED'))
);

CREATE TABLE cb_app_role_grant (
  role_grant_sk NUMBER(18,0) GENERATED ALWAYS AS IDENTITY,
  principal_sk NUMBER(18,0) NOT NULL,
  role_code VARCHAR2(40) NOT NULL,
  grant_status VARCHAR2(20) DEFAULT 'ACTIVE' NOT NULL,
  granted_by VARCHAR2(80) DEFAULT 'seed-loader' NOT NULL,
  granted_at TIMESTAMP WITH LOCAL TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  expires_at TIMESTAMP WITH LOCAL TIME ZONE,
  CONSTRAINT cb_app_role_grant_pk PRIMARY KEY (role_grant_sk),
  CONSTRAINT cb_app_role_grant_uk UNIQUE (principal_sk, role_code),
  CONSTRAINT cb_role_grant_principal_fk FOREIGN KEY (principal_sk) REFERENCES cb_app_principal (principal_sk),
  CONSTRAINT cb_role_grant_code_ck CHECK (role_code IN ('APPLICANT','LOAN_OFFICER','UNDERWRITER','AUDITOR','ADMIN','SERVICE')),
  CONSTRAINT cb_role_grant_status_ck CHECK (grant_status IN ('ACTIVE','REVOKED','EXPIRED')),
  CONSTRAINT cb_role_grant_dates_ck CHECK (expires_at IS NULL OR expires_at > granted_at)
);

CREATE TABLE cb_data_grant (
  data_grant_sk NUMBER(18,0) GENERATED ALWAYS AS IDENTITY,
  principal_sk NUMBER(18,0) NOT NULL,
  application_sk NUMBER(18,0),
  grant_scope VARCHAR2(40) NOT NULL,
  grant_reason VARCHAR2(200) NOT NULL,
  grant_status VARCHAR2(20) DEFAULT 'ACTIVE' NOT NULL,
  granted_at TIMESTAMP WITH LOCAL TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  expires_at TIMESTAMP WITH LOCAL TIME ZONE,
  CONSTRAINT cb_data_grant_pk PRIMARY KEY (data_grant_sk),
  CONSTRAINT cb_data_grant_uk UNIQUE (principal_sk, application_sk, grant_scope),
  CONSTRAINT cb_data_grant_principal_fk FOREIGN KEY (principal_sk) REFERENCES cb_app_principal (principal_sk),
  CONSTRAINT cb_data_grant_app_fk FOREIGN KEY (application_sk) REFERENCES cb_loan_application (application_sk),
  CONSTRAINT cb_data_grant_scope_ck CHECK (grant_scope IN ('ALL','APPLICATION','DOCUMENT','POLICY','AUDIT')),
  CONSTRAINT cb_data_grant_status_ck CHECK (grant_status IN ('ACTIVE','REVOKED','EXPIRED')),
  CONSTRAINT cb_data_grant_dates_ck CHECK (expires_at IS NULL OR expires_at > granted_at)
);

CREATE INDEX cb_principal_subject_ix ON cb_app_principal (external_subject);
CREATE INDEX cb_role_grant_role_ix ON cb_app_role_grant (role_code, grant_status);
CREATE INDEX cb_data_grant_app_ix ON cb_data_grant (application_sk, grant_scope, grant_status);

CREATE OR REPLACE VIEW cb_v_application_summary AS
SELECT
  la.application_id,
  a.applicant_id,
  a.display_name AS applicant_name,
  ad.locality,
  ad.jurisdiction_code,
  ad.jurisdiction_status,
  la.scenario_id,
  la.policy_version,
  la.requested_amount,
  la.requested_term_months,
  la.purpose_code,
  la.application_status,
  la.expected_outcome,
  ie.verified_gross_monthly_income,
  ls.debt_to_income_pct,
  d.decision_outcome,
  d.risk_band,
  la.created_at,
  la.updated_at
FROM cb_loan_application la
JOIN cb_applicant a ON a.applicant_sk = la.applicant_sk
LEFT JOIN cb_address ad ON ad.applicant_sk = a.applicant_sk
LEFT JOIN cb_income_evidence ie ON ie.application_sk = la.application_sk
LEFT JOIN cb_liability_snapshot ls ON ls.application_sk = la.application_sk
LEFT JOIN cb_decision d ON d.application_sk = la.application_sk
 AND d.decision_type IN ('INITIAL','RECOVERED','MANUAL_FINAL');

CREATE OR REPLACE VIEW cb_v_application_decision_facts AS
SELECT
  la.application_id,
  la.scenario_id,
  la.expected_outcome,
  e.employment_status,
  e.tenure_band,
  e.income_source_type,
  e.pay_frequency,
  ie.stated_gross_monthly_income,
  ie.verified_gross_monthly_income,
  ie.income_consistency_result,
  ie.extraction_confidence,
  ie.document_validation_status,
  ls.existing_monthly_debt,
  ls.proposed_monthly_payment,
  ls.total_obligations,
  ls.debt_to_income_pct,
  ls.recent_delinquency_indicator,
  ls.bankruptcy_indicator,
  pc.apr_text,
  pc.monthly_payment,
  d.decision_outcome,
  d.risk_band,
  d.policy_version
FROM cb_loan_application la
LEFT JOIN cb_employment e ON e.application_sk = la.application_sk
LEFT JOIN cb_income_evidence ie ON ie.application_sk = la.application_sk
LEFT JOIN cb_liability_snapshot ls ON ls.application_sk = la.application_sk
LEFT JOIN cb_payment_calculation pc ON pc.application_sk = la.application_sk
LEFT JOIN cb_decision d ON d.application_sk = la.application_sk
 AND d.decision_type IN ('INITIAL','RECOVERED','MANUAL_FINAL');

CREATE OR REPLACE VIEW cb_v_manual_review_queue AS
SELECT
  t.task_id,
  la.application_id,
  a.display_name AS applicant_name,
  la.scenario_id,
  t.task_type,
  t.task_status,
  t.priority,
  t.reason_code,
  t.assigned_to_principal_id,
  t.due_at,
  t.created_at,
  t.updated_at
FROM cb_manual_review_task t
JOIN cb_loan_application la ON la.application_sk = t.application_sk
JOIN cb_applicant a ON a.applicant_sk = la.applicant_sk
WHERE t.task_status IN ('OPEN','ASSIGNED','IN_PROGRESS');
