-- CloudBank AI 2026.0
-- Keep document-quality processing outcomes distinct from lending decisions.

ALTER TABLE cb_document_issue DROP CONSTRAINT cb_doc_issue_route_ck;

ALTER TABLE cb_document_issue ADD CONSTRAINT cb_doc_issue_route_ck
  CHECK (routing_effect IN ('NONE','MANUAL_REVIEW','BLOCKED','RETRY','RECOVERED'));

ALTER TABLE cb_income_evidence DROP CONSTRAINT cb_income_consistency_ck;

ALTER TABLE cb_income_evidence ADD CONSTRAINT cb_income_consistency_ck CHECK (
  income_consistency_result IN (
    'CONSISTENT_WITHIN_10_PERCENT',
    'INCONSISTENT_OVER_10_PERCENT',
    'INCONSISTENT_OVER_20_PERCENT',
    'INSUFFICIENT_STABLE_RECURRING_EVIDENCE',
    'NOT_EVALUATED'
  )
);
