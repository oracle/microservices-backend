-- CloudBank AI 2026.0
-- 028-spatial-signal-code.sql
-- Preserve the externally meaningful geographic signal code independently of
-- the bounded database signal type.

ALTER TABLE cb_spatial_signal ADD signal_code VARCHAR2(80);

UPDATE cb_spatial_signal
SET signal_code = CASE
  WHEN signal_result = 'NOT_EVALUATED' THEN 'ADDRESS_COORDINATES_MISSING'
  WHEN signal_type = 'BOUNDARY_PROXIMITY' THEN 'BOUNDARY_REVIEW_REQUIRED'
  WHEN signal_type = 'RISK_ZONE_INTERSECTION' THEN 'LOCATION_RISK_REVIEW'
  WHEN signal_result = 'FAIL' THEN 'LOCATION_EXCLUDED'
  ELSE 'LOCATION_IN_SERVICE_AREA'
END
WHERE signal_code IS NULL;

ALTER TABLE cb_spatial_signal MODIFY signal_code VARCHAR2(80) NOT NULL;

COMMENT ON COLUMN cb_spatial_signal.signal_code IS
  'Stable API signal code, including geocoding and spatial-evaluation outcomes.';
