-- CloudBank AI 2026.0
-- Verify comments and Oracle annotations coverage.

SELECT table_name
FROM user_tab_comments
WHERE table_name LIKE 'CB\_%' ESCAPE '\'
  AND comments IS NULL
ORDER BY table_name;

SELECT table_name, column_name
FROM user_col_comments
WHERE table_name LIKE 'CB\_%' ESCAPE '\'
  AND comments IS NULL
  AND column_name IN (
    'APPLICATION_ID',
    'APPLICANT_ID',
    'DOCUMENT_ID',
    'CHUNK_ID',
    'EXTRACTION_PAYLOAD',
    'EMBEDDING',
    'LOCATION_GEOM',
    'ZONE_GEOM',
    'DECISION_ID',
    'WORKFLOW_ID',
    'TRACE_ID'
  )
ORDER BY table_name, column_name;

SELECT object_name, object_type, column_name, annotation_name, annotation_value
FROM user_annotations_usage
WHERE object_name LIKE 'CB\_%' ESCAPE '\'
ORDER BY object_name, column_name, annotation_name;
