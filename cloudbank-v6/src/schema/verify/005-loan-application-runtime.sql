-- Verify the minimum database contract required by loan-application-service.
-- Run as the local provisioning administrator after migrations are finalized.

SET SERVEROUTPUT ON
SET FEEDBACK OFF

DECLARE
  l_count  PLS_INTEGER;
  l_status VARCHAR2(128);

  PROCEDURE assert_true(p_condition BOOLEAN, p_message VARCHAR2) IS
  BEGIN
    IF NOT p_condition THEN
      RAISE_APPLICATION_ERROR(-20100, p_message);
    END IF;
  END;
BEGIN
  SELECT account_status INTO l_status
  FROM dba_users
  WHERE username = 'CLOUDBANK';
  assert_true(l_status LIKE 'LOCKED%', 'CLOUDBANK owner must be locked');

  SELECT account_status INTO l_status
  FROM dba_users
  WHERE username = 'CB_LOAN_APPLICATION_APP';
  assert_true(l_status = 'OPEN', 'CB_LOAN_APPLICATION_APP must be open');

  SELECT account_status INTO l_status
  FROM dba_users
  WHERE username = 'CB_DOCUMENT_INGEST_APP';
  assert_true(l_status = 'OPEN', 'CB_DOCUMENT_INGEST_APP must be open');

  SELECT account_status INTO l_status
  FROM dba_users
  WHERE username = 'CB_DECISION_APP';
  assert_true(l_status = 'OPEN', 'CB_DECISION_APP must be open');

  SELECT account_status INTO l_status
  FROM dba_users WHERE username = 'CB_AI_AGENT_APP';
  assert_true(l_status = 'OPEN', 'CB_AI_AGENT_APP must be open');

  SELECT COUNT(*) INTO l_count FROM dba_tab_privs
  WHERE grantee = 'CB_AI_AGENT_RUNTIME' AND owner = 'CLOUDBANK'
    AND table_name = 'CB_AI_DOCUMENT_SUMMARY' AND privilege IN ('SELECT', 'INSERT');
  assert_true(l_count = 2, 'AI runtime requires immutable result access');

  SELECT COUNT(*) INTO l_count FROM dba_tab_privs
  WHERE grantee = 'CB_AI_AGENT_RUNTIME'
    AND (owner <> 'CLOUDBANK' OR table_name <> 'CB_AI_DOCUMENT_SUMMARY'
         OR privilege NOT IN ('SELECT', 'INSERT'));
  assert_true(l_count = 0, 'AI runtime must not access other service tables or mutate results');

  SELECT COUNT(*) INTO l_count FROM dba_role_privs
  WHERE grantee = 'CB_AI_AGENT_APP' AND granted_role = 'CB_AI_AGENT_RUNTIME';
  assert_true(l_count = 1, 'AI runtime account requires its own least-privilege role');

  SELECT COUNT(DISTINCT object_name) INTO l_count
  FROM dba_objects
  WHERE owner = 'CLOUDBANK'
    AND object_type = 'TABLE'
    AND object_name IN (
      'CB_APPLICANT', 'CB_ADDRESS', 'CB_LOAN_APPLICATION', 'CB_DOCUMENT',
      'CB_DOCUMENT_REGISTRATION_REQUEST', 'CB_WORKFLOW_INSTANCE',
      'CB_WORKFLOW_START_REQUEST', 'CB_AUDIT_EVENT',
      'CB_TELEMETRY_CORRELATION', 'CB_APP_PRINCIPAL',
      'CB_APP_ROLE_GRANT', 'CB_DATA_GRANT', 'CB_DOCUMENT_CONTENT'
    );
  assert_true(l_count = 13, 'Required loan application tables are missing');

  SELECT COUNT(*) INTO l_count
  FROM dba_tab_privs
  WHERE grantee = 'CB_LOAN_APPLICATION_RUNTIME'
    AND owner = 'CLOUDBANK'
    AND table_name = 'CB_ADDRESS'
    AND privilege IN ('SELECT', 'INSERT', 'UPDATE');
  assert_true(l_count = 3, 'Loan runtime lacks applicant-address persistence privileges');

  SELECT COUNT(*) INTO l_count
  FROM dba_tab_columns
  WHERE owner = 'CLOUDBANK'
    AND table_name = 'CB_ADDRESS'
    AND column_name IN ('COUNTRY_CODE', 'POSTAL_CODE');
  assert_true(l_count = 2, 'Address geocoding columns are missing');

  SELECT COUNT(DISTINCT object_name) INTO l_count
  FROM dba_objects
  WHERE owner = 'CLOUDBANK'
    AND object_type = 'PACKAGE'
    AND object_name IN ('CB_APPLICATION_SECURITY_PKG')
    AND status = 'VALID';
  assert_true(l_count = 1, 'Required loan security package is missing or invalid');

  SELECT COUNT(*) INTO l_count
  FROM dba_policies
  WHERE object_owner = 'CLOUDBANK';
  assert_true(l_count = 0, 'CloudBank must not install VPD policies');

  SELECT COUNT(*) INTO l_count
  FROM dba_role_privs
  WHERE grantee = 'CB_LOAN_APPLICATION_APP'
    AND granted_role = 'CB_LOAN_APPLICATION_RUNTIME';
  assert_true(l_count = 1, 'Runtime role is not granted to CB_LOAN_APPLICATION_APP');

  SELECT COUNT(*) INTO l_count
  FROM dba_role_privs
  WHERE grantee = 'CB_DOCUMENT_INGEST_APP'
    AND granted_role = 'CB_DOCUMENT_INGEST_RUNTIME';
  assert_true(l_count = 1, 'Ingest runtime role is not granted to CB_DOCUMENT_INGEST_APP');

  SELECT COUNT(*) INTO l_count
  FROM dba_role_privs
  WHERE grantee = 'CB_DECISION_APP'
    AND granted_role = 'CB_DECISION_RUNTIME';
  assert_true(l_count = 1, 'Decision runtime role is not granted to CB_DECISION_APP');

  SELECT COUNT(*) INTO l_count
  FROM dba_tab_privs
  WHERE grantee = 'CB_DECISION_RUNTIME'
    AND owner = 'CLOUDBANK'
    AND table_name IN ('CB_DECISION', 'CB_DECISION_POLICY_EVIDENCE')
    AND privilege IN ('SELECT', 'INSERT');
  assert_true(l_count = 4, 'Decision runtime lacks decision persistence privileges');

  SELECT COUNT(*) INTO l_count
  FROM dba_tab_privs
  WHERE grantee = 'CB_DECISION_RUNTIME'
    AND owner = 'CLOUDBANK'
    AND table_name IN (
      'CB_LOAN_APPLICATION', 'CB_EMPLOYMENT', 'CB_INCOME_EVIDENCE',
      'CB_LIABILITY_SNAPSHOT', 'CB_PAYMENT_CALCULATION'
    )
    AND privilege = 'SELECT';
  assert_true(l_count = 5, 'Decision runtime lacks typed decision-fact read privileges');

  SELECT COUNT(*) INTO l_count
  FROM dba_tab_privs
  WHERE grantee = 'CB_DECISION_RUNTIME'
    AND owner = 'CLOUDBANK'
    AND privilege IN ('UPDATE', 'DELETE');
  assert_true(l_count = 0, 'Decision runtime must not update or delete owning-service tables');

  SELECT COUNT(*) INTO l_count
  FROM dba_users
  WHERE username = 'CB_GEOGRAPHIC_RISK_APP';

  IF l_count = 1 THEN
    SELECT COUNT(*) INTO l_count
    FROM dba_role_privs
    WHERE grantee = 'CB_GEOGRAPHIC_RISK_APP'
      AND granted_role = 'CB_GEOGRAPHIC_RISK_RUNTIME';
    assert_true(l_count = 1, 'Geographic risk runtime role is not granted to CB_GEOGRAPHIC_RISK_APP');
  END IF;

  SELECT COUNT(*) INTO l_count
  FROM dba_users
  WHERE username = 'CB_POLICY_LOADER_APP';

  IF l_count = 1 THEN
    SELECT COUNT(*) INTO l_count
    FROM dba_role_privs
    WHERE grantee = 'CB_POLICY_LOADER_APP'
      AND granted_role = 'CB_POLICY_LOADER_RUNTIME';
    assert_true(l_count = 1, 'Policy loader runtime role is not granted to CB_POLICY_LOADER_APP');
  END IF;

  SELECT COUNT(*) INTO l_count
  FROM dba_sys_privs
  WHERE grantee = 'CLOUDBANK';
  assert_true(l_count = 0, 'Locked CLOUDBANK owner retains temporary system privileges');

  SELECT COUNT(*) INTO l_count
  FROM dba_objects
  WHERE owner = 'CLOUDBANK'
    AND object_name = 'CB_SECURITY_CTX_PKG';
  assert_true(l_count = 0, 'VPD security context package must not be installed');

  SELECT COUNT(*) INTO l_count
  FROM dba_sys_privs
  WHERE grantee = 'CB_LOAN_APPLICATION_APP'
    AND privilege NOT IN ('CREATE SESSION');
  assert_true(l_count = 0, 'Runtime user has unexpected direct system privileges');

  SELECT COUNT(*) INTO l_count
  FROM dba_tab_privs
  WHERE grantee = 'CB_DOCUMENT_INGEST_RUNTIME'
    AND owner = 'CLOUDBANK'
    AND table_name = 'CB_DOCUMENT_EXTRACTION'
    AND privilege IN ('SELECT', 'INSERT', 'UPDATE');
  assert_true(l_count = 3, 'Ingest runtime lacks extraction persistence privileges');

  SELECT COUNT(*) INTO l_count
  FROM dba_tab_privs
  WHERE grantee = 'CB_DOCUMENT_INGEST_RUNTIME'
    AND owner = 'CLOUDBANK'
    AND table_name = 'CB_DOCUMENT_CONTENT';
  assert_true(l_count = 0, 'Ingest runtime must not access document BLOBs directly');

  DBMS_OUTPUT.PUT_LINE('Loan application database contract verified.');
END;
/
