-- Verify optional database components required before applying full-demo changes.
-- Run as the provisioning administrator in the target PDB.

SET SERVEROUTPUT ON
SET FEEDBACK OFF

DECLARE
  l_count PLS_INTEGER;

  PROCEDURE assert_true(p_condition BOOLEAN, p_message VARCHAR2) IS
  BEGIN
    IF NOT p_condition THEN
      RAISE_APPLICATION_ERROR(-20200, p_message);
    END IF;
  END;
BEGIN
  SELECT COUNT(*) INTO l_count
  FROM dba_registry
  WHERE comp_id = 'SDO'
    AND status = 'VALID';
  assert_true(l_count = 1,
    'full-demo requires a valid Oracle Spatial component; use a regular or full Oracle Free image');

  SELECT COUNT(*) INTO l_count
  FROM dba_registry
  WHERE comp_id = 'CONTEXT'
    AND status = 'VALID';
  assert_true(l_count = 1,
    'full-demo requires a valid Oracle Text component; do not use the slim Oracle Free image');

  SELECT COUNT(*) INTO l_count
  FROM dba_objects
  WHERE owner = 'MDSYS'
    AND object_name = 'SDO_GEOMETRY'
    AND object_type = 'TYPE'
    AND status = 'VALID';
  assert_true(l_count = 1, 'MDSYS.SDO_GEOMETRY is unavailable or invalid');

  DBMS_OUTPUT.PUT_LINE('Full-demo Spatial and Text capabilities verified.');
END;
/
