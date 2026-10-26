-- CloudBank AI 2026.0
-- Security bridge for authenticated loan intake and pooled database sessions.

CREATE OR REPLACE PACKAGE cb_application_security_pkg AUTHID DEFINER AS
  PROCEDURE ensure_applicant_principal(
    p_principal_id IN VARCHAR2,
    p_issuer       IN VARCHAR2,
    p_subject      IN VARCHAR2,
    p_display_name IN VARCHAR2
  );

  PROCEDURE grant_application_owner(
    p_application_id IN VARCHAR2,
    p_principal_id   IN VARCHAR2
  );
END cb_application_security_pkg;
/

CREATE OR REPLACE PACKAGE BODY cb_application_security_pkg AS
  PROCEDURE ensure_applicant_principal(
    p_principal_id IN VARCHAR2,
    p_issuer       IN VARCHAR2,
    p_subject      IN VARCHAR2,
    p_display_name IN VARCHAR2
  ) IS
    l_principal_sk NUMBER;
  BEGIN
    MERGE INTO cb_app_principal target
    USING (
      SELECT p_principal_id principal_id, p_issuer external_issuer,
             p_subject external_subject, p_display_name display_name
      FROM dual
    ) source
    ON (target.principal_id = source.principal_id)
    WHEN MATCHED THEN UPDATE SET
      target.external_issuer = source.external_issuer,
      target.external_subject = source.external_subject,
      target.display_name = source.display_name
    WHEN NOT MATCHED THEN INSERT (
      principal_id, principal_type, display_name, external_issuer, external_subject
    ) VALUES (
      source.principal_id, 'APPLICANT', source.display_name,
      source.external_issuer, source.external_subject
    );

    SELECT principal_sk INTO l_principal_sk
    FROM cb_app_principal
    WHERE principal_id = p_principal_id
      AND external_issuer = p_issuer
      AND external_subject = p_subject
      AND status = 'ACTIVE';

    MERGE INTO cb_app_role_grant target
    USING (SELECT l_principal_sk principal_sk FROM dual) source
    ON (target.principal_sk = source.principal_sk AND target.role_code = 'APPLICANT')
    WHEN MATCHED THEN UPDATE SET target.grant_status = 'ACTIVE'
    WHEN NOT MATCHED THEN INSERT (principal_sk, role_code, granted_by)
      VALUES (source.principal_sk, 'APPLICANT', 'loan-application-service');
  END ensure_applicant_principal;

  PROCEDURE grant_application_owner(
    p_application_id IN VARCHAR2,
    p_principal_id   IN VARCHAR2
  ) IS
    l_principal_sk NUMBER;
    l_application_sk NUMBER;
  BEGIN
    SELECT principal_sk INTO l_principal_sk
    FROM cb_app_principal
    WHERE principal_id = p_principal_id AND status = 'ACTIVE';

    SELECT application_sk INTO l_application_sk
    FROM cb_loan_application
    WHERE application_id = p_application_id
      AND submitted_by_principal_id = p_principal_id;

    MERGE INTO cb_data_grant target
    USING (SELECT l_principal_sk principal_sk, l_application_sk application_sk FROM dual) source
    ON (target.principal_sk = source.principal_sk
        AND target.application_sk = source.application_sk
        AND target.grant_scope = 'APPLICATION')
    WHEN MATCHED THEN UPDATE SET target.grant_status = 'ACTIVE'
    WHEN NOT MATCHED THEN INSERT (
      principal_sk, application_sk, grant_scope, grant_reason
    ) VALUES (
      source.principal_sk, source.application_sk, 'APPLICATION', 'Application owner'
    );
  END grant_application_owner;
END cb_application_security_pkg;
/

BEGIN
  EXECUTE IMMEDIATE 'GRANT EXECUTE ON cb_application_security_pkg TO cb_loan_application_runtime';
END;
/
