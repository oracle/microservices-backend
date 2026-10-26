-- CloudBank AI 2026.0
-- 003-policy-vector-schema.sql
-- Policy corpus metadata and authorized RAG chunks.

CREATE TABLE cb_policy_document (
  policy_document_sk NUMBER(18,0) GENERATED ALWAYS AS IDENTITY,
  policy_document_id VARCHAR2(80) NOT NULL,
  policy_code VARCHAR2(40) NOT NULL,
  policy_title VARCHAR2(300) NOT NULL,
  policy_version VARCHAR2(20) DEFAULT '2026.0' NOT NULL,
  source_path VARCHAR2(500) NOT NULL,
  effective_date DATE NOT NULL,
  review_status VARCHAR2(40) DEFAULT 'APPROVED' NOT NULL,
  owner_role VARCHAR2(40) DEFAULT 'UNDERWRITER' NOT NULL,
  data_classification VARCHAR2(40) DEFAULT 'restricted_policy' NOT NULL,
  metadata_json JSON,
  created_at TIMESTAMP WITH LOCAL TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT cb_policy_document_pk PRIMARY KEY (policy_document_sk),
  CONSTRAINT cb_policy_document_uk UNIQUE (policy_document_id),
  CONSTRAINT cb_policy_code_version_uk UNIQUE (policy_code, policy_version),
  CONSTRAINT cb_policy_review_ck CHECK (review_status IN ('DRAFT','APPROVED','RETIRED')),
  CONSTRAINT cb_policy_owner_role_ck CHECK (owner_role IN ('LOAN_OFFICER','UNDERWRITER','AUDITOR','ADMIN')),
  CONSTRAINT cb_policy_class_ck CHECK (data_classification IN ('public_demo','internal','restricted_customer','restricted_policy'))
);

CREATE TABLE cb_policy_chunk (
  policy_chunk_sk NUMBER(18,0) GENERATED ALWAYS AS IDENTITY,
  policy_document_sk NUMBER(18,0) NOT NULL,
  chunk_id VARCHAR2(100) NOT NULL,
  section_ref VARCHAR2(80) NOT NULL,
  heading VARCHAR2(300) NOT NULL,
  chunk_ordinal NUMBER(8,0) NOT NULL,
  chunk_text CLOB NOT NULL,
  chunk_metadata JSON,
  min_role VARCHAR2(40) DEFAULT 'LOAN_OFFICER' NOT NULL,
  access_label VARCHAR2(80) DEFAULT 'policy' NOT NULL,
  ai_use VARCHAR2(60) DEFAULT 'retrieval' NOT NULL,
  embedding VECTOR(*, FLOAT32),
  created_at TIMESTAMP WITH LOCAL TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT cb_policy_chunk_pk PRIMARY KEY (policy_chunk_sk),
  CONSTRAINT cb_policy_chunk_uk UNIQUE (chunk_id),
  CONSTRAINT cb_policy_chunk_doc_ord_uk UNIQUE (policy_document_sk, chunk_ordinal),
  CONSTRAINT cb_policy_chunk_doc_fk FOREIGN KEY (policy_document_sk) REFERENCES cb_policy_document (policy_document_sk),
  CONSTRAINT cb_policy_chunk_ord_ck CHECK (chunk_ordinal >= 1),
  CONSTRAINT cb_policy_chunk_role_ck CHECK (min_role IN ('LOAN_OFFICER','UNDERWRITER','AUDITOR','ADMIN')),
  CONSTRAINT cb_policy_chunk_ai_ck CHECK (ai_use IN ('none','retrieval','structured facts only','explanation grounding'))
);

CREATE INDEX cb_policy_doc_code_ix ON cb_policy_document (policy_code, policy_version, review_status);
CREATE INDEX cb_policy_doc_role_ix ON cb_policy_document (owner_role, data_classification);
CREATE INDEX cb_policy_chunk_doc_ix ON cb_policy_chunk (policy_document_sk, section_ref);
CREATE INDEX cb_policy_chunk_role_ix ON cb_policy_chunk (min_role, access_label, ai_use);
