-- CloudBank AI 2026.0
-- 017-geographic-risk-demo-fixture.sql
-- Minimal APP-RISK-005 fixture for geographic-risk-service smoke testing.

MERGE INTO cb_applicant target
USING (
  SELECT 'APL-CB-RSK-005' applicant_id,
         'Jordan Brooks' display_name,
         'phone_tok_555_0105' phone_token,
         'jordan.brooks.005@example.invalid' email_token,
         '25-34' age_band
  FROM dual
) source
ON (target.applicant_id = source.applicant_id)
WHEN MATCHED THEN UPDATE SET
  target.display_name = source.display_name,
  target.phone_token = source.phone_token,
  target.email_token = source.email_token,
  target.age_band = source.age_band
WHEN NOT MATCHED THEN INSERT (
  applicant_id, display_name, phone_token, email_token, age_band
) VALUES (
  source.applicant_id, source.display_name, source.phone_token,
  source.email_token, source.age_band
);

MERGE INTO cb_address target
USING (
  SELECT applicant.applicant_sk,
         'ADDR-RSK-005' address_id,
         '6 East Orison Crossing' address_line,
         'East Orison' locality,
         'CX' jurisdiction_code,
         'ENABLED_NEAR_BOUNDARY' jurisdiction_status,
         'addr_tok_shared_orison_6' address_token,
         MDSYS.SDO_GEOMETRY(2001, 4326, MDSYS.SDO_POINT_TYPE(-75.835, 38.93, NULL), NULL, NULL) location_geom
  FROM cb_applicant applicant
  WHERE applicant.applicant_id = 'APL-CB-RSK-005'
) source
ON (target.address_id = source.address_id)
WHEN MATCHED THEN UPDATE SET
  target.applicant_sk = source.applicant_sk,
  target.address_line = source.address_line,
  target.locality = source.locality,
  target.jurisdiction_code = source.jurisdiction_code,
  target.jurisdiction_status = source.jurisdiction_status,
  target.address_token = source.address_token,
  target.location_geom = source.location_geom
WHEN NOT MATCHED THEN INSERT (
  applicant_sk, address_id, address_line, locality, jurisdiction_code,
  jurisdiction_status, address_token, location_geom
) VALUES (
  source.applicant_sk, source.address_id, source.address_line, source.locality,
  source.jurisdiction_code, source.jurisdiction_status, source.address_token,
  source.location_geom
);

MERGE INTO cb_jurisdiction_zone target
USING (
  SELECT 'ZONE-CX-ELIGIBLE-001' zone_id,
         'CX' jurisdiction_code,
         'Cobalt Service Area' zone_name,
         'ELIGIBLE_SERVICE_AREA' zone_type,
         'ACTIVE' zone_status,
         SDO_GEOMETRY('POLYGON((-76.20 38.70,-75.80 38.70,-75.80 39.10,-76.20 39.10,-76.20 38.70))', 4326) zone_geom
  FROM dual
) source
ON (target.zone_id = source.zone_id)
WHEN MATCHED THEN UPDATE SET
  target.jurisdiction_code = source.jurisdiction_code,
  target.zone_name = source.zone_name,
  target.zone_type = source.zone_type,
  target.zone_status = source.zone_status,
  target.zone_geom = source.zone_geom
WHEN NOT MATCHED THEN INSERT (
  zone_id, jurisdiction_code, zone_name, zone_type, zone_status, zone_geom
) VALUES (
  source.zone_id, source.jurisdiction_code, source.zone_name,
  source.zone_type, source.zone_status, source.zone_geom
);

MERGE INTO cb_jurisdiction_zone target
USING (
  SELECT 'ZONE-CX-BOUNDARY-001' zone_id,
         'CX' jurisdiction_code,
         'East Boundary Review' zone_name,
         'BOUNDARY_REVIEW' zone_type,
         'ACTIVE' zone_status,
         SDO_GEOMETRY('POLYGON((-75.86 38.72,-75.80 38.72,-75.80 39.08,-75.86 39.08,-75.86 38.72))', 4326) zone_geom
  FROM dual
) source
ON (target.zone_id = source.zone_id)
WHEN MATCHED THEN UPDATE SET
  target.jurisdiction_code = source.jurisdiction_code,
  target.zone_name = source.zone_name,
  target.zone_type = source.zone_type,
  target.zone_status = source.zone_status,
  target.zone_geom = source.zone_geom
WHEN NOT MATCHED THEN INSERT (
  zone_id, jurisdiction_code, zone_name, zone_type, zone_status, zone_geom
) VALUES (
  source.zone_id, source.jurisdiction_code, source.zone_name,
  source.zone_type, source.zone_status, source.zone_geom
);

MERGE INTO cb_loan_application target
USING (
  SELECT applicant.applicant_sk,
         'APP-RISK-005' application_id,
         'SCN-RISK-SIGNAL-005' scenario_id,
         'Relationship And Location Risk' scenario_name,
         12000 requested_amount,
         36 requested_term_months,
         'MAJOR_PURCHASE' purpose_code,
         'MANUAL_REVIEW' application_status,
         'MANUAL_REVIEW' expected_outcome
  FROM cb_applicant applicant
  WHERE applicant.applicant_id = 'APL-CB-RSK-005'
) source
ON (target.application_id = source.application_id)
WHEN MATCHED THEN UPDATE SET
  target.applicant_sk = source.applicant_sk,
  target.scenario_id = source.scenario_id,
  target.scenario_name = source.scenario_name,
  target.requested_amount = source.requested_amount,
  target.requested_term_months = source.requested_term_months,
  target.purpose_code = source.purpose_code,
  target.application_status = source.application_status,
  target.expected_outcome = source.expected_outcome,
  target.updated_at = SYSTIMESTAMP
WHEN NOT MATCHED THEN INSERT (
  application_id, applicant_sk, scenario_id, scenario_name, requested_amount,
  requested_term_months, purpose_code, application_status, expected_outcome
) VALUES (
  source.application_id, source.applicant_sk, source.scenario_id,
  source.scenario_name, source.requested_amount, source.requested_term_months,
  source.purpose_code, source.application_status, source.expected_outcome
);
