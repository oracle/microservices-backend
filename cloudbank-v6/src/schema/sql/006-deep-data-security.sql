-- CloudBank AI 2026.0
-- 006-deep-data-security.sql
-- Future Oracle Deep Data Security policy catalog.
--
-- Deep Data Security is the preferred enforcement layer for CloudBank because
-- the demo must apply authorization before SQL, document chunk, vector, graph,
-- and AI retrieval results leave the database. This catalog records the intended
-- policies in schema-owned data until Deep Data Security is enabled.

CREATE TABLE cb_security_policy_catalog (
  security_policy_sk NUMBER(18,0) GENERATED ALWAYS AS IDENTITY,
  security_policy_id VARCHAR2(80) NOT NULL,
  protected_object VARCHAR2(128) NOT NULL,
  protected_operation VARCHAR2(40) NOT NULL,
  enforcement_layer VARCHAR2(40) NOT NULL,
  minimum_role VARCHAR2(40) NOT NULL,
  policy_expression VARCHAR2(2000) NOT NULL,
  verification_query VARCHAR2(2000),
  policy_status VARCHAR2(40) DEFAULT 'PLANNED' NOT NULL,
  created_at TIMESTAMP WITH LOCAL TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT cb_security_policy_catalog_pk PRIMARY KEY (security_policy_sk),
  CONSTRAINT cb_security_policy_catalog_uk UNIQUE (security_policy_id),
  CONSTRAINT cb_sec_policy_operation_ck CHECK (protected_operation IN ('SELECT','INSERT','UPDATE','DELETE','VECTOR_SEARCH','GRAPH_QUERY','SPATIAL_QUERY')),
  CONSTRAINT cb_sec_policy_layer_ck CHECK (enforcement_layer IN ('DEEP_DATA_SECURITY')),
  CONSTRAINT cb_sec_policy_role_ck CHECK (minimum_role IN ('APPLICANT','LOAN_OFFICER','UNDERWRITER','AUDITOR','ADMIN','SERVICE')),
  CONSTRAINT cb_sec_policy_status_ck CHECK (policy_status IN ('PLANNED','IMPLEMENTED','DISABLED'))
);

COMMENT ON TABLE cb_security_policy_catalog IS 'Schema-owned catalog of intended Deep Data Security authorization policies.';
COMMENT ON COLUMN cb_security_policy_catalog.policy_expression IS 'Human-readable policy expression for review, security tests, and implementation mapping.';

ALTER TABLE cb_security_policy_catalog ANNOTATIONS (
  ADD Domain 'Security',
  ADD Entity 'Security Policy Catalog',
  ADD OwnerService 'authorization-service',
  ADD SecurityModel 'Deep Data Security',
  ADD DataClassification 'internal'
);

MERGE INTO cb_security_policy_catalog t
USING (
  SELECT 'DDS-POLICY-CHUNK-001' security_policy_id,
         'CB_POLICY_CHUNK' protected_object,
         'VECTOR_SEARCH' protected_operation,
         'DEEP_DATA_SECURITY' enforcement_layer,
         'LOAN_OFFICER' minimum_role,
         'Filter policy chunks by principal role before vector similarity search.' policy_expression,
         NULL verification_query,
         'PLANNED' policy_status
  FROM dual
  UNION ALL
  SELECT 'DDS-DOCUMENT-CHUNK-001',
         'CB_DOCUMENT_CHUNK',
         'VECTOR_SEARCH',
         'DEEP_DATA_SECURITY',
         'LOAN_OFFICER',
         'Filter document chunks by principal role and application data grant before vector similarity search.',
         NULL,
         'PLANNED'
  FROM dual
  UNION ALL
  SELECT 'DDS-APPLICATION-001',
         'CB_LOAN_APPLICATION',
         'SELECT',
         'DEEP_DATA_SECURITY',
         'LOAN_OFFICER',
         'Restrict application rows to assigned applicants, granted loan officers, underwriters, auditors, admins, and services.',
         NULL,
         'PLANNED'
  FROM dual
) s
ON (t.security_policy_id = s.security_policy_id)
WHEN MATCHED THEN UPDATE SET
  t.protected_object = s.protected_object,
  t.protected_operation = s.protected_operation,
  t.enforcement_layer = s.enforcement_layer,
  t.minimum_role = s.minimum_role,
  t.policy_expression = s.policy_expression,
  t.verification_query = s.verification_query,
  t.policy_status = s.policy_status
WHEN NOT MATCHED THEN INSERT (
  security_policy_id,
  protected_object,
  protected_operation,
  enforcement_layer,
  minimum_role,
  policy_expression,
  verification_query,
  policy_status
) VALUES (
  s.security_policy_id,
  s.protected_object,
  s.protected_operation,
  s.enforcement_layer,
  s.minimum_role,
  s.policy_expression,
  s.verification_query,
  s.policy_status
);
