-- CloudBank AI 2026.0
-- Allow document-review-service to promote vetted capacity and payment facts.

GRANT SELECT, INSERT, UPDATE ON cb_liability_snapshot TO cb_document_review_runtime;
GRANT SELECT, INSERT, UPDATE ON cb_payment_calculation TO cb_document_review_runtime;
