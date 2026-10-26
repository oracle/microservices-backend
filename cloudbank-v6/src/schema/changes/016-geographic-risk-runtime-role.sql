-- CloudBank AI 2026.0
-- 016-geographic-risk-runtime-role.sql
-- Least-privilege runtime role and service principal for geographic-risk-service.

BEGIN
  BEGIN
    EXECUTE IMMEDIATE 'CREATE ROLE cb_geographic_risk_runtime';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLCODE != -1921 THEN
        RAISE;
      END IF;
  END;

  EXECUTE IMMEDIATE 'GRANT CREATE SESSION TO cb_geographic_risk_runtime';
  EXECUTE IMMEDIATE 'GRANT SELECT ON cb_loan_application TO cb_geographic_risk_runtime';
  EXECUTE IMMEDIATE 'GRANT SELECT ON cb_applicant TO cb_geographic_risk_runtime';
  EXECUTE IMMEDIATE 'GRANT SELECT ON cb_address TO cb_geographic_risk_runtime';
  EXECUTE IMMEDIATE 'GRANT SELECT ON cb_jurisdiction_zone TO cb_geographic_risk_runtime';
  EXECUTE IMMEDIATE 'GRANT SELECT, INSERT ON cb_geographic_risk_evaluation TO cb_geographic_risk_runtime';
  EXECUTE IMMEDIATE 'GRANT SELECT, INSERT ON cb_spatial_signal TO cb_geographic_risk_runtime';

  MERGE INTO cb_app_principal target
  USING (
    SELECT 'svc-geographic-risk-service' principal_id, 'SERVICE' principal_type,
           'Geographic Risk Service' display_name,
           'cloudbank-internal' external_issuer,
           'svc-geographic-risk-service' external_subject
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
    WHERE principal_id = 'svc-geographic-risk-service'
  ) source
  ON (target.principal_sk = source.principal_sk AND target.role_code = source.role_code)
  WHEN MATCHED THEN UPDATE SET target.grant_status = 'ACTIVE'
  WHEN NOT MATCHED THEN INSERT (principal_sk, role_code, granted_by)
  VALUES (source.principal_sk, source.role_code, 'schema-migration');
END;
/
