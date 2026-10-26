-- Assert the CloudBank full-demo feature contract.
-- Run as CLOUDBANK after migration, before the owner is locked.

SET SERVEROUTPUT ON
SET FEEDBACK OFF

DECLARE
  l_count PLS_INTEGER;

  PROCEDURE assert_true(p_condition BOOLEAN, p_message VARCHAR2) IS
  BEGIN
    IF NOT p_condition THEN
      RAISE_APPLICATION_ERROR(-20210, p_message);
    END IF;
  END;
BEGIN
  SELECT COUNT(*) INTO l_count
  FROM user_tab_columns
  WHERE table_name = 'CB_ADDRESS'
    AND column_name = 'LOCATION_GEOM'
    AND data_type = 'SDO_GEOMETRY';
  assert_true(l_count = 1, 'CB_ADDRESS.LOCATION_GEOM is missing');

  SELECT COUNT(*) INTO l_count
  FROM user_tables
  WHERE table_name IN (
    'CB_RELATIONSHIP_EDGE', 'CB_JURISDICTION_ZONE', 'CB_SPATIAL_SIGNAL',
    'CB_GEOGRAPHIC_RISK_EVALUATION'
  );
  assert_true(l_count = 4, 'Full-demo risk and Spatial tables are missing');

  SELECT COUNT(*) INTO l_count
  FROM user_tables
  WHERE table_name = 'CB_POLICY_CORPUS_LOAD';
  assert_true(l_count = 1, 'Policy corpus load table is missing');

  SELECT COUNT(*) INTO l_count
  FROM user_indexes
  WHERE index_name IN (
    'CB_POLICY_CHUNK_EMBEDDING_VIX', 'CB_DOCUMENT_CHUNK_EMBEDDING_VIX',
    'CB_ADDRESS_LOCATION_SX', 'CB_JURIS_ZONE_GEOM_SX'
  )
    AND status = 'VALID';
  assert_true(l_count = 4, 'Vector or Spatial indexes are missing or invalid');

  SELECT COUNT(*) INTO l_count
  FROM user_indexes
  WHERE index_name IN (
    'CB_REL_EDGE_METADATA_JSX', 'CB_DOC_EXTRACT_PAYLOAD_JSX',
    'CB_POLICY_DOC_METADATA_JSX', 'CB_POLICY_CHUNK_METADATA_JSX',
    'CB_DECISION_PAYLOAD_JSX'
  )
    AND status = 'VALID';
  assert_true(l_count = 5, 'Oracle Text JSON search indexes are missing or invalid');

  SELECT COUNT(*) INTO l_count
  FROM user_sdo_geom_metadata
  WHERE table_name IN ('CB_ADDRESS', 'CB_JURISDICTION_ZONE')
    AND srid = 4326;
  assert_true(l_count = 2, 'Spatial metadata is incomplete');

  SELECT COUNT(*) INTO l_count
  FROM user_objects
  WHERE object_name IN ('CB_RISK_GRAPH', 'CB_RISK_GRAPH_NODE')
    AND status = 'VALID';
  assert_true(l_count = 2, 'Risk property graph objects are missing or invalid');

  SELECT COUNT(*) INTO l_count
  FROM user_annotations_usage
  WHERE object_name LIKE 'CB\_%' ESCAPE '\';
  assert_true(l_count > 0, 'CloudBank schema annotations are missing');

  SELECT COUNT(*) INTO l_count
  FROM user_tab_privs_made
  WHERE grantee = 'CB_GEOGRAPHIC_RISK_RUNTIME'
    AND table_name IN (
      'CB_LOAN_APPLICATION', 'CB_APPLICANT', 'CB_ADDRESS',
      'CB_JURISDICTION_ZONE', 'CB_GEOGRAPHIC_RISK_EVALUATION',
      'CB_SPATIAL_SIGNAL'
    );
  assert_true(l_count >= 6, 'Geographic risk runtime role grants are missing');

  SELECT COUNT(*) INTO l_count
  FROM user_tab_columns
  WHERE table_name = 'CB_SPATIAL_SIGNAL'
    AND column_name = 'SIGNAL_CODE';
  assert_true(l_count = 1, 'Geographic signal code column is missing');

  SELECT COUNT(*) INTO l_count
  FROM user_tab_privs_made
  WHERE grantee = 'CB_POLICY_LOADER_RUNTIME'
    AND table_name IN ('CB_POLICY_DOCUMENT', 'CB_POLICY_CHUNK', 'CB_POLICY_CORPUS_LOAD')
    AND privilege IN ('SELECT', 'INSERT');
  assert_true(l_count = 6, 'Policy loader runtime role grants are missing');

  SELECT COUNT(*) INTO l_count
  FROM cb_app_principal p
  JOIN cb_app_role_grant rg ON rg.principal_sk = p.principal_sk
  WHERE p.principal_id = 'svc-geographic-risk-service'
    AND p.status = 'ACTIVE'
    AND rg.role_code = 'SERVICE'
    AND rg.grant_status = 'ACTIVE';
  assert_true(l_count = 1, 'Geographic risk service principal is missing');

  SELECT COUNT(*) INTO l_count
  FROM cb_loan_application la
  JOIN cb_applicant applicant ON applicant.applicant_sk = la.applicant_sk
  JOIN cb_address address ON address.applicant_sk = applicant.applicant_sk
  WHERE la.application_id = 'APP-RISK-005'
    AND address.address_id = 'ADDR-RSK-005'
    AND address.location_geom IS NOT NULL;
  assert_true(l_count = 1, 'APP-RISK-005 geographic fixture is missing');

  DBMS_OUTPUT.PUT_LINE('Full-demo feature contract verified.');
END;
/
