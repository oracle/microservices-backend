// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.geographicrisk.persistence;

import com.cloudbank.geographicrisk.domain.ApplicationAddress;
import com.cloudbank.geographicrisk.domain.Disposition;
import com.cloudbank.geographicrisk.domain.GeocodingStatus;
import com.cloudbank.geographicrisk.domain.ZoneMatch;

import org.eclipse.microprofile.config.inject.ConfigProperty;

import jakarta.annotation.PostConstruct;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Any;
import jakarta.enterprise.inject.Instance;
import jakarta.enterprise.inject.literal.NamedLiteral;
import jakarta.inject.Inject;

import javax.sql.DataSource;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.StringJoiner;
import java.util.logging.Level;
import java.util.logging.Logger;

@ApplicationScoped
public class GeographicRiskDatabase {

    private static final Logger LOGGER = Logger.getLogger(GeographicRiskDatabase.class.getName());
    private static final String DATASOURCE_NAME = "geographic-risk";

    private final Instance<DataSource> dataSources;
    private final boolean logGeocodingDetails;
    private DataSource dataSource;

    @Inject
    public GeographicRiskDatabase(@Any Instance<DataSource> dataSources,
            @ConfigProperty(name = "geographic-risk.geocoding.log-details", defaultValue = "false")
            boolean logGeocodingDetails) {
        this.dataSources = dataSources;
        this.logGeocodingDetails = logGeocodingDetails;
    }

    GeographicRiskDatabase(DataSource dataSource) {
        this(dataSource, false);
    }

    GeographicRiskDatabase(DataSource dataSource, boolean logGeocodingDetails) {
        this.dataSources = null;
        this.dataSource = dataSource;
        this.logGeocodingDetails = logGeocodingDetails;
    }

    @PostConstruct
    void init() {
        Instance<DataSource> selected = dataSources.select(NamedLiteral.of(DATASOURCE_NAME));
        if (!selected.isResolvable()) {
            LOGGER.info("Oracle datasource '" + DATASOURCE_NAME + "' not available");
            return;
        }
        dataSource = selected.get();
        LOGGER.info("Oracle datasource '" + DATASOURCE_NAME + "' available");
    }

    public boolean available() {
        if (dataSource == null) {
            return false;
        }
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement("SELECT 1 FROM dual");
                ResultSet resultSet = statement.executeQuery()) {
            return resultSet.next();
        } catch (SQLException exception) {
            LOGGER.log(Level.WARNING, "Oracle datasource '" + DATASOURCE_NAME
                    + "' readiness check failed", exception);
            return false;
        }
    }

    public Optional<ApplicationAddress> findApplicationAddress(String applicationId) {
        requireDataSource();
        String sql = """
                SELECT la.application_sk,
                       ad.address_sk,
                       ad.jurisdiction_code,
                       CASE WHEN ad.location_geom IS NULL THEN NULL ELSE ad.location_geom.SDO_POINT.X END AS longitude,
                       CASE WHEN ad.location_geom IS NULL THEN NULL ELSE ad.location_geom.SDO_POINT.Y END AS latitude,
                       ad.address_line,
                       ad.locality,
                       ad.country_code,
                       ad.postal_code
                FROM CLOUDBANK.cb_loan_application la
                JOIN CLOUDBANK.cb_applicant ap ON ap.applicant_sk = la.applicant_sk
                LEFT JOIN CLOUDBANK.cb_address ad ON ad.applicant_sk = ap.applicant_sk
                WHERE la.application_id = ?
                ORDER BY ad.created_at DESC
                FETCH FIRST 1 ROW ONLY
                """;
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(sql)) {
            statement.setString(1, applicationId);
            try (ResultSet resultSet = statement.executeQuery()) {
                if (!resultSet.next() || resultSet.getObject("address_sk") == null) {
                    return Optional.empty();
                }
                long applicationSk = resultSet.getLong("application_sk");
                long addressSk = resultSet.getLong("address_sk");
                String jurisdictionCode = resultSet.getString("jurisdiction_code");
                Double longitude = nullableDouble(resultSet, "longitude");
                Double latitude = nullableDouble(resultSet, "latitude");
                if (longitude != null && latitude != null) {
                    return Optional.of(new ApplicationAddress(applicationSk, addressSk, jurisdictionCode,
                            true, longitude, latitude, GeocodingStatus.STORED));
                }
                String addressLine = resultSet.getString("address_line");
                String locality = resultSet.getString("locality");
                String postalCode = resultSet.getString("postal_code");
                String countryCode = resultSet.getString("country_code");
                resultSet.close();
                GeocodingCoordinates coordinates = geocode(connection, addressSk,
                        addressLine, locality, postalCode, countryCode);
                return Optional.of(new ApplicationAddress(applicationSk, addressSk, jurisdictionCode,
                        coordinates.longitude() != null && coordinates.latitude() != null,
                        coordinates.longitude(), coordinates.latitude(), coordinates.status()));
            }
        } catch (SQLException exception) {
            throw new IllegalStateException("Unable to load application address", exception);
        }
    }

    private GeocodingCoordinates geocode(Connection connection, long addressSk, String addressLine,
            String locality, String postalCode, String countryCode) {
        String address = formattedAddress(addressLine, locality, postalCode, countryCode);
        String sql = """
                SELECT result.geocoded.SDO_POINT.X AS longitude,
                       result.geocoded.SDO_POINT.Y AS latitude
                FROM (
                    SELECT SDO_GCDR.ELOC_GEOCODE_AS_GEOM(?) AS geocoded
                    FROM dual
                ) result
                """;
        try (PreparedStatement statement = connection.prepareStatement(sql)) {
            statement.setString(1, address);
            try (ResultSet resultSet = statement.executeQuery()) {
                if (!resultSet.next()) {
                    return geocodingResult(addressSk, address, null, null, GeocodingStatus.NO_MATCH);
                }
                Double longitude = nullableDouble(resultSet, "longitude");
                Double latitude = nullableDouble(resultSet, "latitude");
                if (longitude == null || latitude == null) {
                    return geocodingResult(addressSk, address, null, null, GeocodingStatus.NO_MATCH);
                }
                return geocodingResult(addressSk, address, longitude, latitude, GeocodingStatus.RESOLVED);
            }
        } catch (SQLException exception) {
            LOGGER.log(Level.WARNING, "Oracle GCDR geocoding failed for address_sk=" + addressSk, exception);
            return geocodingResult(addressSk, address, null, null, GeocodingStatus.UNAVAILABLE);
        }
    }

    private GeocodingCoordinates geocodingResult(long addressSk, String address, Double longitude,
            Double latitude, GeocodingStatus status) {
        if (logGeocodingDetails) {
            String safeAddress = address.replaceAll("\\p{Cntrl}", " ").replace("\\", "\\\\")
                    .replace("\"", "\\\"");
            LOGGER.info(() -> "Oracle GCDR geocoding address_sk=" + addressSk
                    + " requestedAddress=\"" + safeAddress + "\" longitude=" + longitude
                    + " latitude=" + latitude + " status=" + status);
        }
        return new GeocodingCoordinates(longitude, latitude, status);
    }

    private static String formattedAddress(String addressLine, String locality, String postalCode,
            String countryCode) {
        StringJoiner joiner = new StringJoiner(", ");
        addIfPresent(joiner, addressLine);
        addIfPresent(joiner, locality);
        addIfPresent(joiner, postalCode);
        addIfPresent(joiner, countryCode);
        return joiner.toString();
    }

    private static void addIfPresent(StringJoiner joiner, String value) {
        if (value != null && !value.isBlank()) {
            joiner.add(value.trim());
        }
    }

    private static Double nullableDouble(ResultSet resultSet, String column) throws SQLException {
        Object value = resultSet.getObject(column);
        return value instanceof Number number ? number.doubleValue() : null;
    }

    public List<ZoneMatch> findInsideZones(long addressSk, String jurisdictionCode) {
        requireDataSource();
        String sql = """
                SELECT z.jurisdiction_zone_sk,
                       z.zone_id,
                       z.zone_name,
                       z.zone_type
                FROM CLOUDBANK.cb_address ad
                JOIN CLOUDBANK.cb_jurisdiction_zone z ON z.jurisdiction_code = ad.jurisdiction_code
                 AND z.zone_status = 'ACTIVE'
                WHERE ad.address_sk = ?
                  AND ad.jurisdiction_code = ?
                  AND ad.location_geom IS NOT NULL
                  AND SDO_RELATE(ad.location_geom, z.zone_geom, 'mask=INSIDE') = 'TRUE'
                ORDER BY z.zone_type, z.zone_name
                """;
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(sql)) {
            statement.setLong(1, addressSk);
            statement.setString(2, jurisdictionCode);
            try (ResultSet resultSet = statement.executeQuery()) {
                List<ZoneMatch> matches = new ArrayList<>();
                while (resultSet.next()) {
                    matches.add(new ZoneMatch(
                            resultSet.getLong("jurisdiction_zone_sk"),
                            resultSet.getString("zone_id"),
                            resultSet.getString("zone_name"),
                            resultSet.getString("zone_type"),
                            null));
                }
                return matches;
            }
        } catch (SQLException exception) {
            throw new IllegalStateException("Unable to evaluate spatial zone intersections", exception);
        }
    }

    public List<ZoneMatch> findInsideZones(long addressSk, String jurisdictionCode,
            double longitude, double latitude) {
        requireDataSource();
        String sql = """
                SELECT z.jurisdiction_zone_sk,
                       z.zone_id,
                       z.zone_name,
                       z.zone_type
                FROM CLOUDBANK.cb_address ad
                JOIN CLOUDBANK.cb_jurisdiction_zone z ON z.jurisdiction_code = ad.jurisdiction_code
                 AND z.zone_status = 'ACTIVE'
                WHERE ad.address_sk = ?
                  AND ad.jurisdiction_code = ?
                  AND SDO_RELATE(
                        MDSYS.SDO_GEOMETRY(2001, 4326,
                            MDSYS.SDO_POINT_TYPE(?, ?, NULL), NULL, NULL),
                        z.zone_geom, 'mask=INSIDE') = 'TRUE'
                ORDER BY z.zone_type, z.zone_name
                """;
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(sql)) {
            statement.setLong(1, addressSk);
            statement.setString(2, jurisdictionCode);
            statement.setDouble(3, longitude);
            statement.setDouble(4, latitude);
            try (ResultSet resultSet = statement.executeQuery()) {
                return zoneMatches(resultSet, false);
            }
        } catch (SQLException exception) {
            throw new IllegalStateException("Unable to evaluate geocoded spatial zone intersections", exception);
        }
    }

    public List<ZoneMatch> findBoundaryZones(long addressSk, String jurisdictionCode, double distanceMeters) {
        requireDataSource();
        String sql = """
                SELECT z.jurisdiction_zone_sk,
                       z.zone_id,
                       z.zone_name,
                       z.zone_type,
                       SDO_GEOM.SDO_DISTANCE(ad.location_geom, z.zone_geom, 0.005, 'unit=M') AS distance_m
                FROM CLOUDBANK.cb_address ad
                JOIN CLOUDBANK.cb_jurisdiction_zone z ON z.jurisdiction_code = ad.jurisdiction_code
                 AND z.zone_status = 'ACTIVE'
                 AND z.zone_type = 'BOUNDARY_REVIEW'
                WHERE ad.address_sk = ?
                  AND ad.jurisdiction_code = ?
                  AND ad.location_geom IS NOT NULL
                  AND SDO_WITHIN_DISTANCE(ad.location_geom, z.zone_geom, 'distance=' || ? || ' unit=M') = 'TRUE'
                ORDER BY distance_m, z.zone_name
                """;
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(sql)) {
            statement.setLong(1, addressSk);
            statement.setString(2, jurisdictionCode);
            statement.setDouble(3, distanceMeters);
            try (ResultSet resultSet = statement.executeQuery()) {
                List<ZoneMatch> matches = new ArrayList<>();
                while (resultSet.next()) {
                    matches.add(new ZoneMatch(
                            resultSet.getLong("jurisdiction_zone_sk"),
                            resultSet.getString("zone_id"),
                            resultSet.getString("zone_name"),
                            resultSet.getString("zone_type"),
                            resultSet.getDouble("distance_m")));
                }
                return matches;
            }
        } catch (SQLException exception) {
            throw new IllegalStateException("Unable to evaluate boundary proximity", exception);
        }
    }

    public List<ZoneMatch> findBoundaryZones(long addressSk, String jurisdictionCode, double distanceMeters,
            double longitude, double latitude) {
        requireDataSource();
        String sql = """
                SELECT z.jurisdiction_zone_sk,
                       z.zone_id,
                       z.zone_name,
                       z.zone_type,
                       SDO_GEOM.SDO_DISTANCE(
                           MDSYS.SDO_GEOMETRY(2001, 4326,
                               MDSYS.SDO_POINT_TYPE(?, ?, NULL), NULL, NULL),
                           z.zone_geom, 0.005, 'unit=M') AS distance_m
                FROM CLOUDBANK.cb_address ad
                JOIN CLOUDBANK.cb_jurisdiction_zone z ON z.jurisdiction_code = ad.jurisdiction_code
                 AND z.zone_status = 'ACTIVE'
                 AND z.zone_type = 'BOUNDARY_REVIEW'
                WHERE ad.address_sk = ?
                  AND ad.jurisdiction_code = ?
                  AND SDO_WITHIN_DISTANCE(
                        MDSYS.SDO_GEOMETRY(2001, 4326,
                            MDSYS.SDO_POINT_TYPE(?, ?, NULL), NULL, NULL),
                        z.zone_geom, 'distance=' || ? || ' unit=M') = 'TRUE'
                ORDER BY distance_m, z.zone_name
                """;
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(sql)) {
            statement.setDouble(1, longitude);
            statement.setDouble(2, latitude);
            statement.setLong(3, addressSk);
            statement.setString(4, jurisdictionCode);
            statement.setDouble(5, longitude);
            statement.setDouble(6, latitude);
            statement.setDouble(7, distanceMeters);
            try (ResultSet resultSet = statement.executeQuery()) {
                return zoneMatches(resultSet, true);
            }
        } catch (SQLException exception) {
            throw new IllegalStateException("Unable to evaluate geocoded boundary proximity", exception);
        }
    }

    private static List<ZoneMatch> zoneMatches(ResultSet resultSet, boolean withDistance) throws SQLException {
        List<ZoneMatch> matches = new ArrayList<>();
        while (resultSet.next()) {
            matches.add(new ZoneMatch(
                    resultSet.getLong("jurisdiction_zone_sk"),
                    resultSet.getString("zone_id"),
                    resultSet.getString("zone_name"),
                    resultSet.getString("zone_type"),
                    withDistance ? resultSet.getDouble("distance_m") : null));
        }
        return matches;
    }

    public Optional<ZoneMatch> findZoneBySk(Long zoneSk) {
        if (zoneSk == null) {
            return Optional.empty();
        }
        requireDataSource();
        String sql = """
                SELECT jurisdiction_zone_sk, zone_id, zone_name, zone_type
                FROM CLOUDBANK.cb_jurisdiction_zone
                WHERE jurisdiction_zone_sk = ?
                """;
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(sql)) {
            statement.setLong(1, zoneSk);
            try (ResultSet resultSet = statement.executeQuery()) {
                if (!resultSet.next()) {
                    return Optional.empty();
                }
                return Optional.of(new ZoneMatch(
                        resultSet.getLong("jurisdiction_zone_sk"),
                        resultSet.getString("zone_id"),
                        resultSet.getString("zone_name"),
                        resultSet.getString("zone_type"),
                        null));
            }
        } catch (SQLException exception) {
            throw new IllegalStateException("Unable to load geographic zone", exception);
        }
    }

    public Optional<LatestGeographicRiskEvaluation> findLatestEvaluation(long applicationSk) {
        requireDataSource();
        String sql = """
                SELECT evaluation_id, disposition
                FROM CLOUDBANK.cb_geographic_risk_evaluation
                WHERE application_sk = ?
                ORDER BY created_at DESC, evaluation_id DESC
                FETCH FIRST 1 ROW ONLY
                """;
        try (Connection connection = dataSource.getConnection();
                PreparedStatement statement = connection.prepareStatement(sql)) {
            statement.setLong(1, applicationSk);
            try (ResultSet resultSet = statement.executeQuery()) {
                if (!resultSet.next()) {
                    return Optional.empty();
                }
                return Optional.of(new LatestGeographicRiskEvaluation(
                        resultSet.getString("evaluation_id"),
                        Disposition.valueOf(resultSet.getString("disposition"))));
            }
        } catch (SQLException exception) {
            throw new IllegalStateException("Unable to load latest geographic risk evaluation", exception);
        }
    }

    private void requireDataSource() {
        if (dataSource == null) {
            throw new IllegalStateException("Oracle datasource '" + DATASOURCE_NAME + "' is not available");
        }
    }

    private record GeocodingCoordinates(Double longitude, Double latitude, GeocodingStatus status) {
    }
}
