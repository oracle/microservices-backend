-- CloudBank AI 2026.0
-- 001-core-relational-schema.sql
-- Core personal-loan OLTP tables. Relational state is the system of record.
-- Optional Spatial columns are added by 004-risk-spatial-graph-schema.sql.

CREATE TABLE cb_applicant (
  applicant_sk NUMBER(18,0) GENERATED ALWAYS AS IDENTITY,
  applicant_id VARCHAR2(40) NOT NULL,
  display_name VARCHAR2(200) NOT NULL,
  phone_token VARCHAR2(80) NOT NULL,
  email_token VARCHAR2(160) NOT NULL,
  age_band VARCHAR2(20) NOT NULL,
  data_classification VARCHAR2(40) DEFAULT 'restricted_customer' NOT NULL,
  created_at TIMESTAMP WITH LOCAL TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT cb_applicant_pk PRIMARY KEY (applicant_sk),
  CONSTRAINT cb_applicant_uk UNIQUE (applicant_id),
  CONSTRAINT cb_applicant_age_ck CHECK (age_band IN ('18-24','25-34','35-44','45-54','55-64','65_PLUS')),
  CONSTRAINT cb_applicant_class_ck CHECK (data_classification IN ('public_demo','internal','restricted_customer','restricted_policy'))
);

CREATE TABLE cb_address (
  address_sk NUMBER(18,0) GENERATED ALWAYS AS IDENTITY,
  applicant_sk NUMBER(18,0) NOT NULL,
  address_id VARCHAR2(40) NOT NULL,
  address_line VARCHAR2(300) NOT NULL,
  locality VARCHAR2(120) NOT NULL,
  jurisdiction_code VARCHAR2(20) NOT NULL,
  jurisdiction_status VARCHAR2(40) NOT NULL,
  address_token VARCHAR2(80) NOT NULL,
  created_at TIMESTAMP WITH LOCAL TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT cb_address_pk PRIMARY KEY (address_sk),
  CONSTRAINT cb_address_uk UNIQUE (address_id),
  CONSTRAINT cb_address_app_fk FOREIGN KEY (applicant_sk) REFERENCES cb_applicant (applicant_sk),
  CONSTRAINT cb_address_jur_ck CHECK (jurisdiction_status IN ('ENABLED','ENABLED_NEAR_BOUNDARY','DISABLED','REVIEW'))
);

CREATE TABLE cb_employer (
  employer_sk NUMBER(18,0) GENERATED ALWAYS AS IDENTITY,
  employer_id VARCHAR2(40) NOT NULL,
  employer_name VARCHAR2(220) NOT NULL,
  employer_token VARCHAR2(80) NOT NULL,
  employer_address VARCHAR2(300) NOT NULL,
  status VARCHAR2(20) DEFAULT 'ACTIVE' NOT NULL,
  created_at TIMESTAMP WITH LOCAL TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT cb_employer_pk PRIMARY KEY (employer_sk),
  CONSTRAINT cb_employer_uk UNIQUE (employer_id),
  CONSTRAINT cb_employer_token_uk UNIQUE (employer_token),
  CONSTRAINT cb_employer_status_ck CHECK (status IN ('ACTIVE','INACTIVE','REVIEW'))
);

CREATE TABLE cb_loan_application (
  application_sk NUMBER(18,0) GENERATED ALWAYS AS IDENTITY,
  application_id VARCHAR2(40) NOT NULL,
  applicant_sk NUMBER(18,0) NOT NULL,
  scenario_id VARCHAR2(80) NOT NULL,
  policy_version VARCHAR2(20) DEFAULT '2026.0' NOT NULL,
  requested_amount NUMBER(12,2) NOT NULL,
  requested_term_months NUMBER(3,0) NOT NULL,
  purpose_code VARCHAR2(40) NOT NULL,
  application_status VARCHAR2(40) NOT NULL,
  expected_outcome VARCHAR2(40) NOT NULL,
  application_packet_json JSON,
  data_classification VARCHAR2(40) DEFAULT 'restricted_customer' NOT NULL,
  created_at TIMESTAMP WITH LOCAL TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  updated_at TIMESTAMP WITH LOCAL TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT cb_loan_application_pk PRIMARY KEY (application_sk),
  CONSTRAINT cb_loan_application_uk UNIQUE (application_id),
  CONSTRAINT cb_loan_app_applicant_fk FOREIGN KEY (applicant_sk) REFERENCES cb_applicant (applicant_sk),
  CONSTRAINT cb_loan_app_amount_ck CHECK (requested_amount BETWEEN 1000 AND 35000),
  CONSTRAINT cb_loan_app_term_ck CHECK (requested_term_months IN (24,36,48,60)),
  CONSTRAINT cb_loan_app_purpose_ck CHECK (purpose_code IN (
    'DEBT_CONSOLIDATION','HOME_IMPROVEMENT','MAJOR_PURCHASE','MEDICAL_EXPENSE',
    'HOUSEHOLD_EXPENSE','MOVING_EXPENSE','OTHER_CONSUMER_PURPOSE'
  )),
  CONSTRAINT cb_loan_app_status_ck CHECK (application_status IN (
    'SUBMITTED','DOCUMENTS_RECEIVED','PROCESSING','MANUAL_REVIEW','APPROVED',
    'REJECTED','FAILED_RETRYABLE','RECOVERED','WITHDRAWN','EXPIRED'
  )),
  CONSTRAINT cb_loan_app_outcome_ck CHECK (expected_outcome IN (
    'APPROVED','REJECTED','MANUAL_REVIEW','FAILED_RETRYABLE_RECOVERED'
  )),
  CONSTRAINT cb_loan_app_class_ck CHECK (data_classification IN ('public_demo','internal','restricted_customer','restricted_policy')),
  CONSTRAINT cb_loan_app_dates_ck CHECK (updated_at >= created_at)
);

CREATE TABLE cb_employment (
  employment_sk NUMBER(18,0) GENERATED ALWAYS AS IDENTITY,
  application_sk NUMBER(18,0) NOT NULL,
  employer_sk NUMBER(18,0),
  employment_status VARCHAR2(40) NOT NULL,
  job_title VARCHAR2(160) NOT NULL,
  tenure_text VARCHAR2(80) NOT NULL,
  tenure_band VARCHAR2(40) NOT NULL,
  income_source_type VARCHAR2(80) NOT NULL,
  pay_frequency VARCHAR2(40) NOT NULL,
  created_at TIMESTAMP WITH LOCAL TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT cb_employment_pk PRIMARY KEY (employment_sk),
  CONSTRAINT cb_employment_app_uk UNIQUE (application_sk),
  CONSTRAINT cb_employment_app_fk FOREIGN KEY (application_sk) REFERENCES cb_loan_application (application_sk),
  CONSTRAINT cb_employment_employer_fk FOREIGN KEY (employer_sk) REFERENCES cb_employer (employer_sk),
  CONSTRAINT cb_employment_status_ck CHECK (employment_status IN ('ACTIVE','SELF_EMPLOYED','RETIRED','BENEFITS','UNKNOWN')),
  CONSTRAINT cb_employment_tenure_ck CHECK (tenure_band IN ('12_PLUS_MONTHS','6_TO_11_MONTHS','LESS_THAN_6_MONTHS','VARIABLE')),
  CONSTRAINT cb_employment_pay_ck CHECK (pay_frequency IN ('BIWEEKLY','MONTHLY','WEEKLY','VARIABLE','UNKNOWN'))
);

CREATE TABLE cb_liability_snapshot (
  liability_sk NUMBER(18,0) GENERATED ALWAYS AS IDENTITY,
  application_sk NUMBER(18,0) NOT NULL,
  existing_monthly_debt NUMBER(12,2) NOT NULL,
  proposed_monthly_payment NUMBER(12,2) NOT NULL,
  total_obligations NUMBER(12,2) GENERATED ALWAYS AS (existing_monthly_debt + proposed_monthly_payment) VIRTUAL,
  debt_to_income_pct NUMBER(7,4) NOT NULL,
  recent_delinquency_indicator VARCHAR2(40) DEFAULT 'NONE' NOT NULL,
  bankruptcy_indicator VARCHAR2(40) DEFAULT 'NONE' NOT NULL,
  captured_at TIMESTAMP WITH LOCAL TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT cb_liability_snapshot_pk PRIMARY KEY (liability_sk),
  CONSTRAINT cb_liability_app_uk UNIQUE (application_sk),
  CONSTRAINT cb_liability_app_fk FOREIGN KEY (application_sk) REFERENCES cb_loan_application (application_sk),
  CONSTRAINT cb_liability_amt_ck CHECK (existing_monthly_debt >= 0 AND proposed_monthly_payment >= 0),
  CONSTRAINT cb_liability_dti_ck CHECK (debt_to_income_pct >= 0),
  CONSTRAINT cb_liability_delinq_ck CHECK (recent_delinquency_indicator IN ('NONE','MINOR_RESOLVED','RECENT_MINOR','RECENT_SEVERE','UNKNOWN')),
  CONSTRAINT cb_liability_bankruptcy_ck CHECK (bankruptcy_indicator IN ('NONE','OPEN','DISCHARGED','UNKNOWN'))
);

CREATE TABLE cb_payment_calculation (
  payment_calc_sk NUMBER(18,0) GENERATED ALWAYS AS IDENTITY,
  application_sk NUMBER(18,0) NOT NULL,
  requested_amount NUMBER(12,2) NOT NULL,
  evaluated_amount NUMBER(12,2),
  term_months NUMBER(3,0) NOT NULL,
  apr_text VARCHAR2(30) NOT NULL,
  monthly_payment NUMBER(12,2) NOT NULL,
  calculation_status VARCHAR2(40) NOT NULL,
  calculation_timestamp TIMESTAMP WITH LOCAL TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  policy_version VARCHAR2(20) DEFAULT '2026.0' NOT NULL,
  CONSTRAINT cb_payment_calc_pk PRIMARY KEY (payment_calc_sk),
  CONSTRAINT cb_payment_calc_app_uk UNIQUE (application_sk),
  CONSTRAINT cb_payment_calc_app_fk FOREIGN KEY (application_sk) REFERENCES cb_loan_application (application_sk),
  CONSTRAINT cb_payment_calc_term_ck CHECK (term_months IN (24,36,48,60)),
  CONSTRAINT cb_payment_calc_status_ck CHECK (calculation_status IN ('CALCULATED','FAILED','NOT_APPLICABLE')),
  CONSTRAINT cb_payment_calc_amt_ck CHECK (requested_amount BETWEEN 1000 AND 35000 AND monthly_payment >= 0)
);

CREATE INDEX cb_address_app_ix ON cb_address (applicant_sk);
CREATE INDEX cb_address_jur_ix ON cb_address (jurisdiction_code, jurisdiction_status);
CREATE INDEX cb_applicant_email_fix ON cb_applicant (LOWER(email_token));
CREATE INDEX cb_applicant_phone_fix ON cb_applicant (LOWER(phone_token));
CREATE INDEX cb_loan_app_applicant_ix ON cb_loan_application (applicant_sk, created_at);
CREATE INDEX cb_loan_app_scenario_ix ON cb_loan_application (scenario_id);
CREATE INDEX cb_loan_app_status_ix ON cb_loan_application (application_status, updated_at);
CREATE INDEX cb_employment_employer_ix ON cb_employment (employer_sk);
