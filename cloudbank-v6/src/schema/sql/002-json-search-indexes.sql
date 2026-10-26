-- CloudBank AI 2026.0
-- Optional JSON search indexes. These require the Oracle Text/Search component
-- and are not required by loan-application-service at runtime.

CREATE SEARCH INDEX cb_doc_extract_payload_jsx
  ON cb_document_extraction (extraction_payload) FOR JSON;

CREATE SEARCH INDEX cb_policy_doc_metadata_jsx
  ON cb_policy_document (metadata_json) FOR JSON;

CREATE SEARCH INDEX cb_policy_chunk_metadata_jsx
  ON cb_policy_chunk (chunk_metadata) FOR JSON;

CREATE SEARCH INDEX cb_decision_payload_jsx
  ON cb_decision (decision_payload) FOR JSON;
