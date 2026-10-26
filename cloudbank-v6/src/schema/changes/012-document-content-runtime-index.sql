-- CloudBank AI 2026.0
-- 012-document-content-runtime-index.sql

CREATE INDEX cb_document_content_app_ix ON cb_document_content (application_sk, document_sk);
