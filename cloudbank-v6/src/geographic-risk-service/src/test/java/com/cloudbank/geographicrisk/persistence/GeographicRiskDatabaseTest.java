// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.geographicrisk.persistence;

import com.cloudbank.geographicrisk.domain.ApplicationAddress;
import com.cloudbank.geographicrisk.domain.GeocodingStatus;
import com.cloudbank.geographicrisk.domain.ZoneMatch;

import org.junit.jupiter.api.Test;

import javax.sql.DataSource;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.logging.Handler;
import java.util.logging.Level;
import java.util.logging.LogRecord;
import java.util.logging.Logger;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class GeographicRiskDatabaseTest {

    private final DataSource dataSource = mock(DataSource.class);
    private final Connection connection = mock(Connection.class);
    private final PreparedStatement statement = mock(PreparedStatement.class);
    private final ResultSet resultSet = mock(ResultSet.class);
    private final GeographicRiskDatabase database = new GeographicRiskDatabase(dataSource);

    @Test
    void availableReturnsTrueWhenValidationQueryReturnsRow() throws Exception {
        prepareQuery();
        when(resultSet.next()).thenReturn(true);

        assertThat(database.available()).isTrue();
    }

    @Test
    void availableReturnsFalseWhenDatasourceFails() throws Exception {
        when(dataSource.getConnection()).thenThrow(new SQLException("down"));

        assertThat(database.available()).isFalse();
    }

    @Test
    void findApplicationAddressMapsAddressRow() throws Exception {
        prepareQuery();
        when(resultSet.next()).thenReturn(true);
        when(resultSet.getObject("address_sk")).thenReturn(202L);
        when(resultSet.getLong("application_sk")).thenReturn(101L);
        when(resultSet.getLong("address_sk")).thenReturn(202L);
        when(resultSet.getString("jurisdiction_code")).thenReturn("CB-NY");
        when(resultSet.getObject("longitude")).thenReturn(-75.835D);
        when(resultSet.getObject("latitude")).thenReturn(38.93D);

        Optional<ApplicationAddress> address = database.findApplicationAddress("APP-RISK-005");

        assertThat(address).isPresent();
        assertThat(address.get().applicationSk()).isEqualTo(101L);
        assertThat(address.get().addressSk()).isEqualTo(202L);
        assertThat(address.get().jurisdictionCode()).isEqualTo("CB-NY");
        assertThat(address.get().hasLocation()).isTrue();
        assertThat(address.get().longitude()).isEqualTo(-75.835D);
        assertThat(address.get().latitude()).isEqualTo(38.93D);
        assertThat(address.get().geocodingStatus()).isEqualTo(GeocodingStatus.STORED);
        verify(statement).setString(1, "APP-RISK-005");
    }

    @Test
    void findApplicationAddressUsesGcdRWhenStoredGeometryIsMissing() throws Exception {
        prepareQuery();
        when(resultSet.next()).thenReturn(true, true);
        when(resultSet.getObject("address_sk")).thenReturn(202L);
        when(resultSet.getLong("application_sk")).thenReturn(101L);
        when(resultSet.getLong("address_sk")).thenReturn(202L);
        when(resultSet.getString("jurisdiction_code")).thenReturn("IT-ROMA");
        when(resultSet.getObject("longitude")).thenReturn(null, 12.4828D);
        when(resultSet.getObject("latitude")).thenReturn(null, 41.8933D);
        when(resultSet.getString("address_line")).thenReturn("Via del Corso 1");
        when(resultSet.getString("locality")).thenReturn("Roma");
        when(resultSet.getString("postal_code")).thenReturn("00186");
        when(resultSet.getString("country_code")).thenReturn("IT");

        Optional<ApplicationAddress> address = database.findApplicationAddress("APP-ROME-001");

        assertThat(address).isPresent();
        assertThat(address.get().hasLocation()).isTrue();
        assertThat(address.get().longitude()).isEqualTo(12.4828D);
        assertThat(address.get().latitude()).isEqualTo(41.8933D);
        assertThat(address.get().geocodingStatus()).isEqualTo(GeocodingStatus.RESOLVED);
        verify(statement).setString(1, "Via del Corso 1, Roma, 00186, IT");
    }

    @Test
    void geocodingDetailsLogAddressAndCoordinatesOnlyWhenEnabled() throws Exception {
        prepareQuery();
        when(resultSet.next()).thenReturn(true, true);
        when(resultSet.getObject("address_sk")).thenReturn(202L);
        when(resultSet.getLong("application_sk")).thenReturn(101L);
        when(resultSet.getLong("address_sk")).thenReturn(202L);
        when(resultSet.getString("jurisdiction_code")).thenReturn("DEMO");
        when(resultSet.getObject("longitude")).thenReturn(null, 12.5D);
        when(resultSet.getObject("latitude")).thenReturn(null, 41.9D);
        when(resultSet.getString("address_line")).thenReturn("1 Demo Street");
        when(resultSet.getString("locality")).thenReturn("Testville");
        when(resultSet.getString("postal_code")).thenReturn("12345");
        when(resultSet.getString("country_code")).thenReturn("IT");

        List<String> messages = captureGeocodingLogs(
                () -> new GeographicRiskDatabase(dataSource, true).findApplicationAddress("APP-DEMO-001"));

        assertThat(messages).anyMatch(message -> message.contains("requestedAddress=\"1 Demo Street, Testville, 12345, IT\"")
                && message.contains("longitude=12.5") && message.contains("latitude=41.9")
                && message.contains("status=RESOLVED"));
    }

    @Test
    void geocodingDetailsDoNotLogAddressOrCoordinatesByDefault() throws Exception {
        prepareQuery();
        when(resultSet.next()).thenReturn(true, true);
        when(resultSet.getObject("address_sk")).thenReturn(202L);
        when(resultSet.getLong("application_sk")).thenReturn(101L);
        when(resultSet.getLong("address_sk")).thenReturn(202L);
        when(resultSet.getString("jurisdiction_code")).thenReturn("DEMO");
        when(resultSet.getObject("longitude")).thenReturn(null, 12.5D);
        when(resultSet.getObject("latitude")).thenReturn(null, 41.9D);
        when(resultSet.getString("address_line")).thenReturn("1 Demo Street");
        when(resultSet.getString("locality")).thenReturn("Testville");

        List<String> messages = captureGeocodingLogs(
                () -> database.findApplicationAddress("APP-DEMO-001"));

        assertThat(messages).noneMatch(message -> message.contains("requestedAddress=")
                || message.contains("longitude="));
    }

    @Test
    void findApplicationAddressReportsNoMatchWhenGcdRReturnsNoGeometry() throws Exception {
        prepareQuery();
        when(resultSet.next()).thenReturn(true, false);
        when(resultSet.getObject("address_sk")).thenReturn(202L);
        when(resultSet.getLong("application_sk")).thenReturn(101L);
        when(resultSet.getLong("address_sk")).thenReturn(202L);
        when(resultSet.getString("jurisdiction_code")).thenReturn("IT-ROMA");
        when(resultSet.getObject("longitude")).thenReturn(null);
        when(resultSet.getObject("latitude")).thenReturn(null);
        when(resultSet.getString("address_line")).thenReturn("Unknown Street 999");
        when(resultSet.getString("locality")).thenReturn("Unknown City");

        Optional<ApplicationAddress> address = database.findApplicationAddress("APP-NO-MATCH");

        assertThat(address).isPresent();
        assertThat(address.get().hasLocation()).isFalse();
        assertThat(address.get().geocodingStatus()).isEqualTo(GeocodingStatus.NO_MATCH);
    }

    @Test
    void findApplicationAddressReportsUnavailableWhenGcdRQueryFails() throws Exception {
        prepareQuery();
        when(statement.executeQuery()).thenReturn(resultSet).thenThrow(new SQLException("GCDR unavailable"));
        when(resultSet.next()).thenReturn(true);
        when(resultSet.getObject("address_sk")).thenReturn(202L);
        when(resultSet.getLong("application_sk")).thenReturn(101L);
        when(resultSet.getLong("address_sk")).thenReturn(202L);
        when(resultSet.getString("jurisdiction_code")).thenReturn("IT-ROMA");
        when(resultSet.getObject("longitude")).thenReturn(null);
        when(resultSet.getObject("latitude")).thenReturn(null);
        when(resultSet.getString("address_line")).thenReturn("Via del Corso 1");
        when(resultSet.getString("locality")).thenReturn("Roma");

        Optional<ApplicationAddress> address = database.findApplicationAddress("APP-GCDR-DOWN");

        assertThat(address).isPresent();
        assertThat(address.get().hasLocation()).isFalse();
        assertThat(address.get().geocodingStatus()).isEqualTo(GeocodingStatus.UNAVAILABLE);
    }

    @Test
    void findApplicationAddressReturnsEmptyWhenNoRowExists() throws Exception {
        prepareQuery();
        when(resultSet.next()).thenReturn(false);

        assertThat(database.findApplicationAddress("APP-MISSING")).isEmpty();
    }

    @Test
    void findApplicationAddressReturnsEmptyWhenAddressIsNull() throws Exception {
        prepareQuery();
        when(resultSet.next()).thenReturn(true);
        when(resultSet.getObject("address_sk")).thenReturn(null);

        assertThat(database.findApplicationAddress("APP-NO-ADDRESS")).isEmpty();
    }

    @Test
    void findInsideZonesMapsAllRows() throws Exception {
        prepareQuery();
        when(resultSet.next()).thenReturn(true, true, false);
        when(resultSet.getLong("jurisdiction_zone_sk")).thenReturn(301L, 302L);
        when(resultSet.getString("zone_id")).thenReturn("ZONE-SERVICE", "ZONE-RISK");
        when(resultSet.getString("zone_name")).thenReturn("Normal service area", "Synthetic risk area");
        when(resultSet.getString("zone_type")).thenReturn("ELIGIBLE_SERVICE_AREA", "FRAUD_REVIEW_AREA");

        List<ZoneMatch> zones = database.findInsideZones(202, "CB-NY");

        assertThat(zones).hasSize(2);
        assertThat(zones).extracting(ZoneMatch::zoneId).containsExactly("ZONE-SERVICE", "ZONE-RISK");
        assertThat(zones).extracting(ZoneMatch::zoneType)
                .containsExactly("ELIGIBLE_SERVICE_AREA", "FRAUD_REVIEW_AREA");
        verify(statement).setLong(1, 202);
        verify(statement).setString(2, "CB-NY");
    }

    @Test
    void findInsideZonesUsesResolvedCoordinates() throws Exception {
        prepareQuery();
        when(resultSet.next()).thenReturn(true, false);
        when(resultSet.getLong("jurisdiction_zone_sk")).thenReturn(301L);
        when(resultSet.getString("zone_id")).thenReturn("ZONE-SERVICE");
        when(resultSet.getString("zone_name")).thenReturn("Normal service area");
        when(resultSet.getString("zone_type")).thenReturn("ELIGIBLE_SERVICE_AREA");

        List<ZoneMatch> zones = database.findInsideZones(202, "CB-NY", -75.835, 38.93);

        assertThat(zones).singleElement().extracting(ZoneMatch::zoneId).isEqualTo("ZONE-SERVICE");
        verify(statement).setLong(1, 202);
        verify(statement).setString(2, "CB-NY");
        verify(statement).setDouble(3, -75.835);
        verify(statement).setDouble(4, 38.93);
    }

    @Test
    void findBoundaryZonesMapsDistance() throws Exception {
        prepareQuery();
        when(resultSet.next()).thenReturn(true, false);
        when(resultSet.getLong("jurisdiction_zone_sk")).thenReturn(303L);
        when(resultSet.getString("zone_id")).thenReturn("ZONE-BOUNDARY");
        when(resultSet.getString("zone_name")).thenReturn("Boundary review area");
        when(resultSet.getString("zone_type")).thenReturn("BOUNDARY_REVIEW");
        when(resultSet.getDouble("distance_m")).thenReturn(82.4);

        List<ZoneMatch> zones = database.findBoundaryZones(202, "CB-NY", 100);

        assertThat(zones).singleElement().satisfies(zone -> {
            assertThat(zone.jurisdictionZoneSk()).isEqualTo(303L);
            assertThat(zone.zoneId()).isEqualTo("ZONE-BOUNDARY");
            assertThat(zone.distanceToBoundaryMeters()).isEqualTo(82.4);
        });
        verify(statement).setLong(1, 202);
        verify(statement).setString(2, "CB-NY");
        verify(statement).setDouble(3, 100);
    }

    @Test
    void findBoundaryZonesUsesResolvedCoordinates() throws Exception {
        prepareQuery();
        when(resultSet.next()).thenReturn(true, false);
        when(resultSet.getLong("jurisdiction_zone_sk")).thenReturn(303L);
        when(resultSet.getString("zone_id")).thenReturn("ZONE-BOUNDARY");
        when(resultSet.getString("zone_name")).thenReturn("Boundary review area");
        when(resultSet.getString("zone_type")).thenReturn("BOUNDARY_REVIEW");
        when(resultSet.getDouble("distance_m")).thenReturn(82.4);

        List<ZoneMatch> zones = database.findBoundaryZones(202, "CB-NY", 100, -75.835, 38.93);

        assertThat(zones).singleElement().extracting(ZoneMatch::distanceToBoundaryMeters).isEqualTo(82.4);
        verify(statement).setDouble(1, -75.835);
        verify(statement).setDouble(2, 38.93);
        verify(statement).setLong(3, 202);
        verify(statement).setString(4, "CB-NY");
        verify(statement).setDouble(5, -75.835);
        verify(statement).setDouble(6, 38.93);
        verify(statement).setDouble(7, 100);
    }

    @Test
    void findZoneBySkReturnsEmptyWhenInputIsNull() {
        assertThat(database.findZoneBySk(null)).isEmpty();
    }

    @Test
    void findZoneBySkMapsRow() throws Exception {
        prepareQuery();
        when(resultSet.next()).thenReturn(true);
        when(resultSet.getLong("jurisdiction_zone_sk")).thenReturn(303L);
        when(resultSet.getString("zone_id")).thenReturn("ZONE-BOUNDARY");
        when(resultSet.getString("zone_name")).thenReturn("Boundary review area");
        when(resultSet.getString("zone_type")).thenReturn("BOUNDARY_REVIEW");

        Optional<ZoneMatch> zone = database.findZoneBySk(303L);

        assertThat(zone).isPresent();
        assertThat(zone.get().zoneId()).isEqualTo("ZONE-BOUNDARY");
        verify(statement).setLong(1, 303L);
    }

    @Test
    void findZoneBySkReturnsEmptyWhenNoRowExists() throws Exception {
        prepareQuery();
        when(resultSet.next()).thenReturn(false);

        assertThat(database.findZoneBySk(999L)).isEmpty();
    }

    @Test
    void queryMethodsWrapSqlExceptions() throws Exception {
        when(dataSource.getConnection()).thenThrow(new SQLException("boom"));

        assertThatThrownBy(() -> database.findApplicationAddress("APP-RISK-005"))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("Unable to load application address");
        assertThatThrownBy(() -> database.findInsideZones(202, "CB-NY"))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("Unable to evaluate spatial zone intersections");
        assertThatThrownBy(() -> database.findBoundaryZones(202, "CB-NY", 100))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("Unable to evaluate boundary proximity");
        assertThatThrownBy(() -> database.findZoneBySk(303L))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("Unable to load geographic zone");
    }

    @Test
    void methodsFailFastWithoutDatasource() {
        GeographicRiskDatabase unavailable = new GeographicRiskDatabase((DataSource) null);

        assertThat(unavailable.available()).isFalse();
        assertThatThrownBy(() -> unavailable.findApplicationAddress("APP-RISK-005"))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("Oracle datasource 'geographic-risk' is not available");
    }

    private void prepareQuery() throws Exception {
        when(dataSource.getConnection()).thenReturn(connection);
        when(connection.prepareStatement(anyString())).thenReturn(statement);
        when(statement.executeQuery()).thenReturn(resultSet);
    }

    private List<String> captureGeocodingLogs(Runnable operation) {
        Logger logger = Logger.getLogger(GeographicRiskDatabase.class.getName());
        Level originalLevel = logger.getLevel();
        List<String> messages = new ArrayList<>();
        Handler handler = new Handler() {
            @Override
            public void publish(LogRecord record) {
                messages.add(record.getMessage());
            }

            @Override
            public void flush() {
            }

            @Override
            public void close() {
            }
        };
        logger.setLevel(Level.INFO);
        logger.addHandler(handler);
        try {
            operation.run();
        } finally {
            logger.removeHandler(handler);
            logger.setLevel(originalLevel);
        }
        return messages;
    }
}
