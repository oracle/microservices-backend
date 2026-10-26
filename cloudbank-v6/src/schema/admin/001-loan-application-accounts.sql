-- CloudBank database account bootstrap.
-- Run as a privileged PDB administrator through setup-local-db.sh.
-- Positional arguments are supplied over SQLcl standard input, never as OS process arguments.

SET DEFINE ON
SET VERIFY OFF
SET ECHO OFF
SET FEEDBACK OFF

DEFINE owner_password = '&1'
DEFINE runtime_password = '&2'
DEFINE ingest_runtime_password = '&3'
DEFINE schema_profile = '&4'
DEFINE geographic_runtime_password = '&5'
DEFINE review_runtime_password = '&6'
DEFINE policy_runtime_password = '&7'
DEFINE policy_loader_password = '&8'
DEFINE decision_runtime_password = '&9'
DEFINE ai_runtime_password = '&10'

DECLARE
  l_owner_password   VARCHAR2(128) := '&&owner_password';
  l_runtime_password VARCHAR2(128) := '&&runtime_password';
  l_ingest_runtime_password VARCHAR2(128) := '&&ingest_runtime_password';
  l_geographic_runtime_password VARCHAR2(128) := '&&geographic_runtime_password';
  l_review_runtime_password VARCHAR2(128) := '&&review_runtime_password';
  l_policy_runtime_password VARCHAR2(128) := '&&policy_runtime_password';
  l_policy_loader_password VARCHAR2(128) := '&&policy_loader_password';
  l_decision_runtime_password VARCHAR2(128) := '&&decision_runtime_password';
  l_ai_runtime_password VARCHAR2(128) := '&&ai_runtime_password';
  l_schema_profile    VARCHAR2(20) := LOWER('&&schema_profile');
  l_data_tablespace   VARCHAR2(261);

  PROCEDURE assert_password(p_name VARCHAR2, p_value VARCHAR2) IS
  BEGIN
    IF LENGTH(p_value) < 12
       OR LENGTH(p_value) > 128
       OR NOT REGEXP_LIKE(p_value, '^[A-Za-z0-9#!?$%^*_-]+$')
       OR NOT REGEXP_LIKE(p_value, '[A-Z]')
       OR NOT REGEXP_LIKE(p_value, '[a-z]')
       OR NOT REGEXP_LIKE(p_value, '[0-9]')
       OR NOT REGEXP_LIKE(p_value, '[#!?$%^*_-]') THEN
      RAISE_APPLICATION_ERROR(-20001,
        p_name || ' must be 12-128 characters with upper, lower, number, and #!?$%^*_-');
    END IF;
  END;

  PROCEDURE reconcile_user(p_username VARCHAR2, p_password VARCHAR2) IS
    l_count           PLS_INTEGER;
    l_quoted_username VARCHAR2(261);
  BEGIN
    l_quoted_username := DBMS_ASSERT.ENQUOTE_NAME(UPPER(p_username), FALSE);

    SELECT COUNT(*)
    INTO l_count
    FROM dba_users
    WHERE username = UPPER(p_username);

    IF l_count = 0 THEN
      EXECUTE IMMEDIATE
        'CREATE USER ' || l_quoted_username || ' IDENTIFIED BY "' || p_password ||
        '" DEFAULT TABLESPACE ' || l_data_tablespace;
    ELSE
      BEGIN
        EXECUTE IMMEDIATE
          'ALTER USER ' || l_quoted_username || ' IDENTIFIED BY "' || p_password || '"';
      EXCEPTION
        WHEN OTHERS THEN
          -- ADB password history rejects assigning the current password again.
          -- The caller subsequently authenticates with the supplied owner and
          -- runtime credentials, so a genuinely different password still fails.
          IF SQLCODE != -28007 THEN
            RAISE;
          END IF;
      END;
    END IF;

    EXECUTE IMMEDIATE 'ALTER USER ' || l_quoted_username || ' ACCOUNT UNLOCK';
    EXECUTE IMMEDIATE
      'ALTER USER ' || l_quoted_username || ' DEFAULT TABLESPACE ' || l_data_tablespace;
  END;
BEGIN
  SELECT property_value
  INTO l_data_tablespace
  FROM database_properties
  WHERE property_name = 'DEFAULT_PERMANENT_TABLESPACE';
  IF UPPER(l_data_tablespace) IN ('SYSTEM', 'SYSAUX') THEN
    RAISE_APPLICATION_ERROR(-20008,
      'CloudBank requires a non-system default permanent tablespace');
  END IF;
  l_data_tablespace := DBMS_ASSERT.ENQUOTE_NAME(l_data_tablespace, FALSE);

  assert_password('CLOUDBANK owner password', l_owner_password);
  assert_password('CB_LOAN_APPLICATION_APP password', l_runtime_password);
  assert_password('CB_DOCUMENT_INGEST_APP password', l_ingest_runtime_password);
  assert_password('CB_DOCUMENT_REVIEW_APP password', l_review_runtime_password);
  assert_password('CB_DECISION_APP password', l_decision_runtime_password);
  assert_password('CB_AI_AGENT_APP password', l_ai_runtime_password);
  IF l_schema_profile = 'full-demo' THEN
    assert_password('CB_GEOGRAPHIC_RISK_APP password', l_geographic_runtime_password);
    assert_password('CB_POLICY_APPLICATION_APP password', l_policy_runtime_password);
    assert_password('CB_POLICY_LOADER_APP password', l_policy_loader_password);
  END IF;

  IF l_owner_password IN (l_runtime_password, l_ingest_runtime_password, l_review_runtime_password,
                          l_decision_runtime_password, l_ai_runtime_password)
     OR (l_schema_profile = 'full-demo' AND (l_owner_password = l_geographic_runtime_password
         OR l_owner_password = l_policy_runtime_password
         OR l_owner_password = l_policy_loader_password)) THEN
    RAISE_APPLICATION_ERROR(-20002,
      'CLOUDBANK owner password must differ from runtime passwords');
  END IF;

  reconcile_user('CLOUDBANK', l_owner_password);
  EXECUTE IMMEDIATE 'ALTER USER CLOUDBANK QUOTA 500M ON ' || l_data_tablespace;

  reconcile_user('CB_LOAN_APPLICATION_APP', l_runtime_password);
  reconcile_user('CB_DOCUMENT_INGEST_APP', l_ingest_runtime_password);
  reconcile_user('CB_DOCUMENT_REVIEW_APP', l_review_runtime_password);
  reconcile_user('CB_DECISION_APP', l_decision_runtime_password);
  reconcile_user('CB_AI_AGENT_APP', l_ai_runtime_password);

  IF l_schema_profile = 'full-demo' THEN
    reconcile_user('CB_GEOGRAPHIC_RISK_APP', l_geographic_runtime_password);
    reconcile_user('CB_POLICY_APPLICATION_APP', l_policy_runtime_password);
    reconcile_user('CB_POLICY_LOADER_APP', l_policy_loader_password);
  END IF;

  EXECUTE IMMEDIATE 'GRANT CREATE SESSION TO CLOUDBANK WITH ADMIN OPTION';
  EXECUTE IMMEDIATE
    'GRANT CREATE TABLE, CREATE VIEW, CREATE SEQUENCE, CREATE PROCEDURE, ' ||
    'CREATE TRIGGER, CREATE TYPE, CREATE ROLE, CREATE ANY CONTEXT TO CLOUDBANK';

  IF l_schema_profile = 'full-demo' THEN
    EXECUTE IMMEDIATE 'GRANT CREATE PROPERTY GRAPH TO CLOUDBANK';
  ELSIF l_schema_profile != 'runtime' THEN
    RAISE_APPLICATION_ERROR(-20006, 'Schema profile must be runtime or full-demo');
  END IF;
END;
/

UNDEFINE owner_password
UNDEFINE runtime_password
UNDEFINE ingest_runtime_password
UNDEFINE schema_profile
UNDEFINE geographic_runtime_password
UNDEFINE review_runtime_password
UNDEFINE policy_runtime_password
UNDEFINE policy_loader_password
UNDEFINE decision_runtime_password
UNDEFINE ai_runtime_password
