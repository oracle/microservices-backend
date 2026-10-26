-- CloudBank AI 2026.0
-- Runtime indexes separated from table creation so an interrupted Oracle DDL
-- migration can resume without dropping the already-created document tables.

CREATE INDEX cb_doc_fact_number_ix
  ON cb_document_fact (fact_name, fact_value_number);

CREATE INDEX cb_doc_issue_app_route_ix
  ON cb_document_issue (application_sk, routing_effect, issue_severity);

CREATE INDEX cb_doc_chunk_app_role_ix
  ON cb_document_chunk (application_sk, min_role, access_label);
