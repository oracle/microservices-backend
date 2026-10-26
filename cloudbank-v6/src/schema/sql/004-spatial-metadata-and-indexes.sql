-- CloudBank AI 2026.0
-- 004-spatial-metadata-and-indexes.sql
-- Spatial metadata and indexes for applicant locations and jurisdiction zones.

DELETE FROM user_sdo_geom_metadata
WHERE table_name = 'CB_ADDRESS'
  AND column_name = 'LOCATION_GEOM';

INSERT INTO user_sdo_geom_metadata (
  table_name,
  column_name,
  diminfo,
  srid
) VALUES (
  'CB_ADDRESS',
  'LOCATION_GEOM',
  MDSYS.SDO_DIM_ARRAY(
    MDSYS.SDO_DIM_ELEMENT('LONGITUDE', -180, 180, 0.005),
    MDSYS.SDO_DIM_ELEMENT('LATITUDE', -90, 90, 0.005)
  ),
  4326
);

DELETE FROM user_sdo_geom_metadata
WHERE table_name = 'CB_JURISDICTION_ZONE'
  AND column_name = 'ZONE_GEOM';

INSERT INTO user_sdo_geom_metadata (
  table_name,
  column_name,
  diminfo,
  srid
) VALUES (
  'CB_JURISDICTION_ZONE',
  'ZONE_GEOM',
  MDSYS.SDO_DIM_ARRAY(
    MDSYS.SDO_DIM_ELEMENT('LONGITUDE', -180, 180, 0.005),
    MDSYS.SDO_DIM_ELEMENT('LATITUDE', -90, 90, 0.005)
  ),
  4326
);

CREATE INDEX cb_address_location_sx
  ON cb_address (location_geom)
  INDEXTYPE IS MDSYS.SPATIAL_INDEX_V2;

CREATE INDEX cb_juris_zone_geom_sx
  ON cb_jurisdiction_zone (zone_geom)
  INDEXTYPE IS MDSYS.SPATIAL_INDEX_V2;
