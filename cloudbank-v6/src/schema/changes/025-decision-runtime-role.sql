-- CloudBank AI 2026.0
-- Least-privilege database role for decision-service. Outbound calls reuse the
-- existing cloudbank-service-client application principal.

BEGIN
  BEGIN
    EXECUTE IMMEDIATE 'CREATE ROLE cb_decision_runtime';
  EXCEPTION WHEN OTHERS THEN
    IF SQLCODE != -1921 THEN RAISE; END IF;
  END;

  EXECUTE IMMEDIATE 'GRANT CREATE SESSION TO cb_decision_runtime';
  EXECUTE IMMEDIATE 'GRANT SELECT ON cb_loan_application TO cb_decision_runtime';
  EXECUTE IMMEDIATE 'GRANT SELECT ON cb_employment TO cb_decision_runtime';
  EXECUTE IMMEDIATE 'GRANT SELECT ON cb_income_evidence TO cb_decision_runtime';
  EXECUTE IMMEDIATE 'GRANT SELECT ON cb_liability_snapshot TO cb_decision_runtime';
  EXECUTE IMMEDIATE 'GRANT SELECT ON cb_payment_calculation TO cb_decision_runtime';
  EXECUTE IMMEDIATE 'GRANT SELECT ON cb_policy_chunk TO cb_decision_runtime';
  EXECUTE IMMEDIATE 'GRANT SELECT, INSERT ON cb_decision TO cb_decision_runtime';
  EXECUTE IMMEDIATE 'GRANT SELECT, INSERT ON cb_decision_policy_evidence TO cb_decision_runtime';

  MERGE INTO cb_app_role_grant target
  USING (SELECT principal_sk, 'SERVICE' role_code
           FROM cb_app_principal
          WHERE principal_id = 'svc-cloudbank-service-client') source
     ON (target.principal_sk = source.principal_sk AND target.role_code = source.role_code)
  WHEN MATCHED THEN UPDATE SET target.grant_status = 'ACTIVE'
  WHEN NOT MATCHED THEN INSERT (principal_sk, role_code, granted_by)
       VALUES (source.principal_sk, source.role_code, 'schema-migration');
END;
/
