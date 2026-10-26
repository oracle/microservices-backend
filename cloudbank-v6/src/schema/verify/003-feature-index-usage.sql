-- CloudBank AI 2026.0
-- Verify Oracle feature objects and index presence.

SELECT index_name, table_name, index_type, status
FROM user_indexes
WHERE index_name IN (
  'CB_POLICY_CHUNK_EMBEDDING_VIX',
  'CB_DOCUMENT_CHUNK_EMBEDDING_VIX',
  'CB_ADDRESS_LOCATION_SX',
  'CB_JURIS_ZONE_GEOM_SX'
)
ORDER BY table_name, index_name;

SELECT table_name, column_name, srid
FROM user_sdo_geom_metadata
WHERE table_name IN ('CB_ADDRESS','CB_JURISDICTION_ZONE')
ORDER BY table_name;

SELECT object_name, object_type, status
FROM user_objects
WHERE object_name IN ('CB_RISK_GRAPH','CB_RISK_GRAPH_NODE')
ORDER BY object_type, object_name;

EXPLAIN PLAN FOR
SELECT application_id
FROM cb_loan_application
WHERE application_id = 'APP-APR-001';

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);
