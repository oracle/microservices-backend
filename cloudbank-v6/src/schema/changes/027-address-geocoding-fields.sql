-- CloudBank AI 2026.0
-- 027-address-geocoding-fields.sql
-- Optional address parts used to build a complete input for Oracle GCDR.

ALTER TABLE cb_address ADD (
  country_code VARCHAR2(2),
  postal_code VARCHAR2(20),
  CONSTRAINT cb_address_country_ck CHECK (
    country_code IS NULL OR REGEXP_LIKE(country_code, '^[A-Z]{2}$')
  )
);

COMMENT ON COLUMN cb_address.country_code IS
  'Optional ISO 3166-1 alpha-2 country code used for address geocoding.';
COMMENT ON COLUMN cb_address.postal_code IS
  'Optional postal code used for address geocoding.';
