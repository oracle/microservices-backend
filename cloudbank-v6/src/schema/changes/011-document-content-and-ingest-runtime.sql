-- CloudBank AI 2026.0
-- 011-document-content-and-ingest-runtime.sql
-- Durable PDF content owned by loan application and least-privilege extraction persistence.

CREATE TABLE cb_document_content (
  document_content_sk NUMBER(18,0) GENERATED ALWAYS AS IDENTITY,
  document_sk NUMBER(18,0) NOT NULL,
  application_sk NUMBER(18,0) NOT NULL,
  content_sha256 VARCHAR2(64) NOT NULL,
  content_length_bytes NUMBER(18,0) NOT NULL,
  media_type VARCHAR2(120) NOT NULL,
  upload_idempotency_key VARCHAR2(200) NOT NULL,
  file_content BLOB NOT NULL,
  created_at TIMESTAMP WITH LOCAL TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT cb_document_content_pk PRIMARY KEY (document_content_sk),
  CONSTRAINT cb_document_content_doc_uk UNIQUE (document_sk),
  CONSTRAINT cb_document_content_idem_uk UNIQUE (application_sk, upload_idempotency_key),
  CONSTRAINT cb_document_content_doc_fk FOREIGN KEY (document_sk) REFERENCES cb_document (document_sk),
  CONSTRAINT cb_document_content_app_fk FOREIGN KEY (application_sk) REFERENCES cb_loan_application (application_sk),
  CONSTRAINT cb_document_content_sha_ck CHECK (REGEXP_LIKE(content_sha256, '^[[:xdigit:]]{64}$')),
  CONSTRAINT cb_document_content_len_ck CHECK (content_length_bytes BETWEEN 1 AND 26214400),
  CONSTRAINT cb_document_content_media_ck CHECK (media_type = 'application/pdf')
)
LOB (file_content) STORE AS SECUREFILE (ENABLE STORAGE IN ROW NOCACHE);
