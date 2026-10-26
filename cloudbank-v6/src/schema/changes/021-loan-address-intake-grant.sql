-- CloudBank AI 2026.0
-- Allow loan intake to persist the applicant address required by geographic-risk evaluation.

GRANT SELECT, INSERT, UPDATE ON cb_address TO cb_loan_application_runtime;
