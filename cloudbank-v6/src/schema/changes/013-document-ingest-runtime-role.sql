-- CloudBank AI 2026.0
-- 013-document-ingest-runtime-role.sql

BEGIN
  EXECUTE IMMEDIATE 'CREATE ROLE cb_document_ingest_runtime';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE != -1921 THEN
      RAISE;
    END IF;
END;
/
