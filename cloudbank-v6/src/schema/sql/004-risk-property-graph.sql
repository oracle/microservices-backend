-- CloudBank AI 2026.0
-- 004-risk-property-graph.sql
-- SQL property graph for shared-attribute risk review.
-- Oracle property graph vertex and edge definitions require tables or
-- materialized views, so the unified demo node list is stored in a table.

CREATE TABLE cb_risk_graph_node AS
SELECT
  applicant_id AS node_id,
  'APPLICANT' AS node_type,
  display_name AS display_name
FROM cb_applicant
UNION
SELECT
  address_id AS node_id,
  'ADDRESS' AS node_type,
  locality || ':' || jurisdiction_code AS display_name
FROM cb_address
UNION
SELECT
  employer_id AS node_id,
  'EMPLOYER' AS node_type,
  employer_name AS display_name
FROM cb_employer
UNION
SELECT
  application_id AS node_id,
  'APPLICATION' AS node_type,
  scenario_id AS display_name
FROM cb_loan_application
UNION
SELECT
  source_entity_id AS node_id,
  source_entity_type AS node_type,
  source_entity_type || ':' || source_entity_id AS display_name
FROM cb_relationship_edge
UNION
SELECT
  target_entity_id AS node_id,
  target_entity_type AS node_type,
  target_entity_type || ':' || target_entity_id AS display_name
FROM cb_relationship_edge;

ALTER TABLE cb_risk_graph_node ADD CONSTRAINT cb_risk_graph_node_pk PRIMARY KEY (node_id);

COMMENT ON TABLE cb_risk_graph_node IS 'Unified node table used by CB_RISK_GRAPH over applicants, applications, addresses, employers, and shared attributes.';

CREATE OR REPLACE PROPERTY GRAPH cb_risk_graph
  VERTEX TABLES (
    cb_risk_graph_node
      KEY (node_id)
      LABEL risk_node
      PROPERTIES (node_id, node_type, display_name)
  )
  EDGE TABLES (
    cb_relationship_edge
      KEY (edge_id)
      SOURCE KEY (source_entity_id) REFERENCES cb_risk_graph_node (node_id)
      DESTINATION KEY (target_entity_id) REFERENCES cb_risk_graph_node (node_id)
      LABEL risk_relationship
      PROPERTIES (
        edge_id,
        application_sk,
        source_entity_type,
        target_entity_type,
        relationship_type,
        evidence_strength,
        signal_status,
        created_at
      )
  );
