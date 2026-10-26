-- CloudBank lab owner provisioning. Run only through the deployment bootstrap.
-- Bind variables contain the exact identity resolved from azn-server's admin API.
-- The caller commits on success; a failed assertion rolls back this operation.
-- No other identity, role grant, or per-application grant is changed.

SAVEPOINT lab_admin_access;

DECLARE
  l_id       VARCHAR2(80) := :lab_admin_principal_id;
  l_issuer   VARCHAR2(300) := :lab_admin_issuer;
  l_sk       NUMBER;
  l_status   VARCHAR2(20);
  l_subject  VARCHAR2(300);
  l_existing_issuer VARCHAR2(300);
  l_count    PLS_INTEGER;
  l_total    NUMBER;
  l_visible  NUMBER;
BEGIN
  IF l_id IS NULL OR NOT REGEXP_LIKE(l_id, '^[A-Za-z0-9_-]{1,80}$')
     OR l_issuer IS NULL
     OR NOT REGEXP_LIKE(l_issuer, '^https?://[A-Za-z0-9.-]+(:[0-9]+)?$') THEN
    RAISE_APPLICATION_ERROR(-20101, 'Invalid lab owner identity');
  END IF;

  SELECT COUNT(*) INTO l_count FROM cloudbank.cb_app_principal
  WHERE external_subject = 'obaas-admin' AND principal_id != l_id;
  IF l_count != 0 THEN
    RAISE_APPLICATION_ERROR(-20102, 'Lab owner identity migration requires explicit reconciliation');
  END IF;

  MERGE INTO cloudbank.cb_app_principal target
  USING (SELECT l_id principal_id FROM dual) source
  ON (target.principal_id = source.principal_id)
  WHEN NOT MATCHED THEN INSERT (
    principal_id, principal_type, display_name, external_issuer, external_subject
  ) VALUES (
    l_id, 'ADMIN', 'Lab owner', l_issuer, 'obaas-admin'
  );

  SELECT principal_sk, status, external_issuer, external_subject
  INTO l_sk, l_status, l_existing_issuer, l_subject
  FROM cloudbank.cb_app_principal WHERE principal_id = l_id FOR UPDATE;
  IF l_status != 'ACTIVE' OR l_existing_issuer IS NULL OR l_subject IS NULL
     OR l_existing_issuer != l_issuer OR l_subject != 'obaas-admin' THEN
    RAISE_APPLICATION_ERROR(-20103, 'Lab owner identity is inactive or does not match Azn');
  END IF;

  SELECT COUNT(*) INTO l_count FROM cloudbank.cb_app_role_grant
  WHERE principal_sk = l_sk AND role_code = 'ADMIN'
    AND (grant_status != 'ACTIVE' OR expires_at <= SYSTIMESTAMP);
  IF l_count != 0 THEN
    RAISE_APPLICATION_ERROR(-20104, 'Lab owner ADMIN grant is revoked or expired');
  END IF;

  MERGE INTO cloudbank.cb_app_role_grant target
  USING (SELECT l_sk principal_sk FROM dual) source
  ON (target.principal_sk = source.principal_sk AND target.role_code = 'ADMIN')
  WHEN NOT MATCHED THEN INSERT (principal_sk, role_code, granted_by)
    VALUES (l_sk, 'ADMIN', 'lab-bootstrap');

  -- Same visibility predicate used by LoanApplicationRepository. Count both
  -- projections in one statement so concurrent intake cannot skew the check.
  SELECT COUNT(*), NVL(SUM(CASE WHEN la.submitted_by_principal_id = l_id
    OR EXISTS (
      SELECT 1 FROM cloudbank.cb_app_principal p
      JOIN cloudbank.cb_app_role_grant r ON r.principal_sk = p.principal_sk
      WHERE p.principal_id = l_id AND p.status = 'ACTIVE' AND r.grant_status = 'ACTIVE'
        AND (r.expires_at IS NULL OR r.expires_at > SYSTIMESTAMP)
        AND r.role_code IN ('ADMIN', 'SERVICE'))
    OR EXISTS (
      SELECT 1 FROM cloudbank.cb_app_principal p
      JOIN cloudbank.cb_data_grant d ON d.principal_sk = p.principal_sk
      WHERE p.principal_id = l_id AND p.status = 'ACTIVE'
        AND d.application_sk = la.application_sk AND d.grant_status = 'ACTIVE'
        AND d.grant_scope IN ('ALL', 'APPLICATION', 'DOCUMENT')
        AND (d.expires_at IS NULL OR d.expires_at > SYSTIMESTAMP))
    THEN 1 ELSE 0 END), 0)
  INTO l_total, l_visible FROM cloudbank.cb_loan_application la;
  IF l_total != l_visible THEN
    RAISE_APPLICATION_ERROR(-20105, 'Lab owner visibility verification failed');
  END IF;
  SELECT COUNT(*) INTO l_count FROM cloudbank.cb_app_role_grant
  WHERE principal_sk = l_sk AND role_code = 'ADMIN' AND grant_status = 'ACTIVE'
    AND (expires_at IS NULL OR expires_at > SYSTIMESTAMP);
  IF l_count != 1 THEN
    RAISE_APPLICATION_ERROR(-20105, 'Lab owner ADMIN grant verification failed');
  END IF;
  DBMS_OUTPUT.PUT_LINE('LAB_ADMIN_APPLICATIONS_TOTAL=' || l_total);
  DBMS_OUTPUT.PUT_LINE('LAB_ADMIN_APPLICATIONS_VISIBLE=' || l_visible);
EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK TO lab_admin_access;
    RAISE;
END;
/
