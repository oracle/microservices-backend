-- CloudBank AI 2026.0
-- 014-document-content-and-ingest-grants.sql

COMMENT ON TABLE cb_document_content IS
  'Immutable PDF content uploaded for a CloudBank loan application document.';
COMMENT ON COLUMN cb_document_content.file_content IS
  'Oracle SecureFiles BLOB containing the uploaded synthetic or customer PDF.';
COMMENT ON COLUMN cb_document_content.content_sha256 IS
  'Lowercase SHA-256 digest used to verify immutable content before extraction.';
COMMENT ON COLUMN cb_document_content.upload_idempotency_key IS
  'Caller key that prevents duplicate content creation within an application.';

GRANT CREATE SESSION TO cb_document_ingest_runtime;
GRANT SELECT ON cb_loan_application TO cb_document_ingest_runtime;
GRANT SELECT ON cb_document TO cb_document_ingest_runtime;
GRANT SELECT, INSERT, UPDATE ON cb_document_extraction TO cb_document_ingest_runtime;

GRANT SELECT, INSERT ON cb_document_content TO cb_loan_application_runtime;

MERGE INTO cb_app_principal target
USING (
  SELECT 'svc-cloudbank-document-ingest-client' principal_id, 'SERVICE' principal_type,
         'CloudBank Document Ingest Service' display_name,
         'cloudbank-internal' external_issuer,
         'cloudbank-document-ingest-client' external_subject
  FROM dual
) source
ON (target.principal_id = source.principal_id)
WHEN MATCHED THEN UPDATE SET
  target.principal_type = source.principal_type,
  target.display_name = source.display_name,
  target.external_issuer = source.external_issuer,
  target.external_subject = source.external_subject,
  target.status = 'ACTIVE'
WHEN NOT MATCHED THEN INSERT (
  principal_id, principal_type, display_name, external_issuer, external_subject
) VALUES (
  source.principal_id, source.principal_type, source.display_name,
  source.external_issuer, source.external_subject
);

MERGE INTO cb_app_role_grant target
USING (
  SELECT principal_sk, 'SERVICE' role_code
  FROM cb_app_principal
  WHERE principal_id = 'svc-cloudbank-document-ingest-client'
) source
ON (target.principal_sk = source.principal_sk AND target.role_code = source.role_code)
WHEN MATCHED THEN UPDATE SET target.grant_status = 'ACTIVE'
WHEN NOT MATCHED THEN INSERT (principal_sk, role_code, granted_by)
VALUES (source.principal_sk, source.role_code, 'schema-migration');
