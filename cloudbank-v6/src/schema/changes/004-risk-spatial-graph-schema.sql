-- CloudBank AI 2026.0
-- 004-risk-spatial-graph-schema.sql
-- Optional shared-attribute relationship signals, jurisdiction zones, and spatial signal results.
-- This migration requires Oracle Spatial (MDSYS); the core loan schema does not.

ALTER TABLE cb_address ADD location_geom MDSYS.SDO_GEOMETRY;

CREATE TABLE cb_relationship_edge (
  relationship_edge_sk NUMBER(18,0) GENERATED ALWAYS AS IDENTITY,
  edge_id VARCHAR2(80) NOT NULL,
  application_sk NUMBER(18,0) NOT NULL,
  source_entity_type VARCHAR2(40) NOT NULL,
  source_entity_id VARCHAR2(80) NOT NULL,
  target_entity_type VARCHAR2(40) NOT NULL,
  target_entity_id VARCHAR2(80) NOT NULL,
  relationship_type VARCHAR2(60) NOT NULL,
  evidence_strength NUMBER(5,4) DEFAULT 1 NOT NULL,
  signal_status VARCHAR2(40) DEFAULT 'OPEN' NOT NULL,
  metadata_json JSON,
  created_at TIMESTAMP WITH LOCAL TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT cb_relationship_edge_pk PRIMARY KEY (relationship_edge_sk),
  CONSTRAINT cb_relationship_edge_uk UNIQUE (edge_id),
  CONSTRAINT cb_rel_edge_app_fk FOREIGN KEY (application_sk) REFERENCES cb_loan_application (application_sk),
  CONSTRAINT cb_rel_edge_strength_ck CHECK (evidence_strength BETWEEN 0 AND 1),
  CONSTRAINT cb_rel_edge_entity_ck CHECK (
    source_entity_type IN ('APPLICANT','ADDRESS','EMPLOYER','DEVICE','EMAIL','PHONE','APPLICATION')
    AND target_entity_type IN ('APPLICANT','ADDRESS','EMPLOYER','DEVICE','EMAIL','PHONE','APPLICATION')
  ),
  CONSTRAINT cb_rel_edge_type_ck CHECK (relationship_type IN (
    'USES_ADDRESS','USES_EMPLOYER','USES_DEVICE','SHARES_ADDRESS','SHARES_DEVICE',
    'SHARES_PHONE','SHARES_EMAIL','NEAR_BOUNDARY','RELATED_APPLICATION'
  )),
  CONSTRAINT cb_rel_edge_status_ck CHECK (signal_status IN ('OPEN','REVIEW_REQUIRED','CLEARED','CONFIRMED_RISK'))
);

CREATE TABLE cb_jurisdiction_zone (
  jurisdiction_zone_sk NUMBER(18,0) GENERATED ALWAYS AS IDENTITY,
  zone_id VARCHAR2(80) NOT NULL,
  jurisdiction_code VARCHAR2(20) NOT NULL,
  zone_name VARCHAR2(160) NOT NULL,
  zone_type VARCHAR2(40) NOT NULL,
  zone_status VARCHAR2(40) NOT NULL,
  zone_geom MDSYS.SDO_GEOMETRY NOT NULL,
  metadata_json JSON,
  effective_at TIMESTAMP WITH LOCAL TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT cb_jurisdiction_zone_pk PRIMARY KEY (jurisdiction_zone_sk),
  CONSTRAINT cb_jurisdiction_zone_uk UNIQUE (zone_id),
  CONSTRAINT cb_juris_zone_code_uk UNIQUE (jurisdiction_code, zone_name, zone_type),
  CONSTRAINT cb_juris_zone_type_ck CHECK (zone_type IN ('ELIGIBLE_SERVICE_AREA','BOUNDARY_REVIEW','EXCLUDED_AREA','FRAUD_REVIEW_AREA')),
  CONSTRAINT cb_juris_zone_status_ck CHECK (zone_status IN ('ACTIVE','INACTIVE','RETIRED'))
);

CREATE TABLE cb_spatial_signal (
  spatial_signal_sk NUMBER(18,0) GENERATED ALWAYS AS IDENTITY,
  application_sk NUMBER(18,0) NOT NULL,
  address_sk NUMBER(18,0) NOT NULL,
  jurisdiction_zone_sk NUMBER(18,0),
  signal_id VARCHAR2(80) NOT NULL,
  signal_type VARCHAR2(60) NOT NULL,
  signal_result VARCHAR2(60) NOT NULL,
  distance_to_boundary_m NUMBER(12,2),
  routing_effect VARCHAR2(60) NOT NULL,
  created_at TIMESTAMP WITH LOCAL TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT cb_spatial_signal_pk PRIMARY KEY (spatial_signal_sk),
  CONSTRAINT cb_spatial_signal_uk UNIQUE (signal_id),
  CONSTRAINT cb_spatial_signal_app_fk FOREIGN KEY (application_sk) REFERENCES cb_loan_application (application_sk),
  CONSTRAINT cb_spatial_signal_addr_fk FOREIGN KEY (address_sk) REFERENCES cb_address (address_sk),
  CONSTRAINT cb_spatial_signal_zone_fk FOREIGN KEY (jurisdiction_zone_sk) REFERENCES cb_jurisdiction_zone (jurisdiction_zone_sk),
  CONSTRAINT cb_spatial_signal_type_ck CHECK (signal_type IN ('JURISDICTION_ELIGIBILITY','BOUNDARY_PROXIMITY','RISK_ZONE_INTERSECTION')),
  CONSTRAINT cb_spatial_signal_result_ck CHECK (signal_result IN ('PASS','REVIEW','FAIL','NOT_EVALUATED')),
  CONSTRAINT cb_spatial_signal_route_ck CHECK (routing_effect IN ('NONE','MANUAL_REVIEW','REJECT')),
  CONSTRAINT cb_spatial_signal_dist_ck CHECK (distance_to_boundary_m IS NULL OR distance_to_boundary_m >= 0)
);

CREATE INDEX cb_rel_edge_app_ix ON cb_relationship_edge (application_sk, relationship_type, signal_status);
CREATE INDEX cb_rel_edge_source_ix ON cb_relationship_edge (source_entity_type, source_entity_id);
CREATE INDEX cb_rel_edge_target_ix ON cb_relationship_edge (target_entity_type, target_entity_id);
CREATE SEARCH INDEX cb_rel_edge_metadata_jsx ON cb_relationship_edge (metadata_json) FOR JSON;
CREATE INDEX cb_juris_zone_status_ix ON cb_jurisdiction_zone (jurisdiction_code, zone_type, zone_status);
CREATE INDEX cb_spatial_signal_app_ix ON cb_spatial_signal (application_sk, signal_type, routing_effect);
