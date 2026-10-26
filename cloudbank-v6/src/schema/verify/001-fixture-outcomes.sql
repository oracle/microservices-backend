-- CloudBank AI 2026.0
-- Verify deterministic fixture outcomes after CB_SEED_LOADER.LOAD.

SELECT
  application_id,
  scenario_id,
  application_status,
  expected_outcome
FROM cb_loan_application
WHERE application_id IN (
  'APP-APR-001',
  'APP-MR-002',
  'APP-REJ-003',
  'APP-OPFAIL-004',
  'APP-RISK-005'
)
ORDER BY application_id;

SELECT application_id, expected_outcome
FROM cb_loan_application
WHERE (application_id = 'APP-APR-001' AND expected_outcome != 'APPROVED')
   OR (application_id = 'APP-MR-002' AND expected_outcome != 'MANUAL_REVIEW')
   OR (application_id = 'APP-REJ-003' AND expected_outcome != 'REJECTED')
   OR (application_id = 'APP-OPFAIL-004' AND expected_outcome != 'FAILED_RETRYABLE_RECOVERED')
   OR (application_id = 'APP-RISK-005' AND expected_outcome != 'MANUAL_REVIEW');

SELECT
  application_id,
  verified_gross_monthly_income,
  debt_to_income_pct,
  decision_outcome,
  risk_band
FROM cb_v_application_decision_facts
WHERE application_id IN (
  'APP-APR-001',
  'APP-MR-002',
  'APP-REJ-003',
  'APP-OPFAIL-004',
  'APP-RISK-005'
)
ORDER BY application_id;

SELECT
  la.application_id,
  COUNT(e.decision_evidence_sk) AS evidence_count
FROM cb_loan_application la
JOIN cb_decision d ON d.application_sk = la.application_sk
LEFT JOIN cb_decision_policy_evidence e ON e.decision_sk = d.decision_sk
GROUP BY la.application_id
ORDER BY la.application_id;
