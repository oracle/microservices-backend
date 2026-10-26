-- CloudBank AI 2026.0
-- 007-seed-staging.sql
-- Staging table for structured JSON seed documents.

CREATE TABLE cb_seed_payload (
  seed_name VARCHAR2(120) NOT NULL,
  payload JSON NOT NULL,
  payload_sha256 VARCHAR2(64),
  loaded_at TIMESTAMP WITH LOCAL TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
  loaded_by VARCHAR2(80) DEFAULT USER NOT NULL,
  CONSTRAINT cb_seed_payload_pk PRIMARY KEY (seed_name),
  CONSTRAINT cb_seed_payload_sha_ck CHECK (payload_sha256 IS NULL OR REGEXP_LIKE(payload_sha256, '^[[:xdigit:]]{64}$'))
);

COMMENT ON TABLE cb_seed_payload IS 'Structured JSON seed payloads loaded by CB_SEED_LOADER; avoids long insert scripts.';
COMMENT ON COLUMN cb_seed_payload.payload IS 'JSON document from src/schema/seeds/seed-data.json.';

ALTER TABLE cb_seed_payload ANNOTATIONS (
  ADD Domain 'Seed Data',
  ADD Entity 'Seed Payload',
  ADD OwnerService 'schema-loader',
  ADD OracleFeature 'Native JSON',
  ADD DataClassification 'internal'
);
