// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.geographicrisk.application;

import com.cloudbank.geographicrisk.api.ApplicationGeographicRiskResponse;
import com.cloudbank.geographicrisk.api.GeographicRiskRequest;
import com.cloudbank.geographicrisk.api.GeographicRiskResponse;
import com.cloudbank.geographicrisk.api.GeographicSignalResponse;
import com.cloudbank.geographicrisk.domain.ApplicationAddress;
import com.cloudbank.geographicrisk.domain.Disposition;
import com.cloudbank.geographicrisk.domain.GeocodingStatus;
import com.cloudbank.geographicrisk.domain.RoutingEffect;
import com.cloudbank.geographicrisk.domain.SignalResult;
import com.cloudbank.geographicrisk.domain.SpatialSignalDraft;
import com.cloudbank.geographicrisk.domain.ZoneMatch;
import com.cloudbank.geographicrisk.persistence.GeographicRiskDatabase;
import com.cloudbank.geographicrisk.persistence.GeographicRiskEvaluationEntity;
import com.cloudbank.geographicrisk.persistence.GeographicRiskEvaluationRepository;
import com.cloudbank.geographicrisk.persistence.LatestGeographicRiskEvaluation;
import com.cloudbank.geographicrisk.persistence.SpatialSignalEntity;
import com.cloudbank.geographicrisk.persistence.SpatialSignalRepository;

import jakarta.ws.rs.BadRequestException;
import jakarta.ws.rs.NotFoundException;
import jakarta.ws.rs.WebApplicationException;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.slf4j.MDC;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.sql.SQLException;
import java.util.HexFormat;
import java.util.List;
import java.util.Optional;
import java.util.concurrent.CyclicBarrier;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyDouble;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.when;
import static org.mockito.Mockito.times;

@ExtendWith(MockitoExtension.class)
class GeographicRiskServiceTest {

    private static final GeographicRiskRequest REQUEST = new GeographicRiskRequest(
            "APP-RISK-005",
            "WF-APP-RISK-005",
            "evaluate-geographic-risk",
            "0123456789abcdef0123456789abcdef");

    @Mock
    private GeographicRiskDatabase database;

    @Mock
    private GeographicRiskEvaluationRepository evaluationRepository;

    @Mock
    private SpatialSignalRepository signalRepository;

    private GeographicRiskService service;

    @BeforeEach
    void setUp() {
        service = new GeographicRiskService(database, evaluationRepository, signalRepository, 100);
    }

    @AfterEach
    void tearDown() {
        MDC.clear();
    }

    @Test
    void evaluatePersistsClearResultForServiceArea() {
        when(database.findApplicationAddress("APP-RISK-005"))
                .thenReturn(Optional.of(address(true)));
        when(evaluationRepository.findByIdempotency(101, "idem-key-001"))
                .thenReturn(Optional.empty());
        when(database.findInsideZones(202, "CB-NY"))
                .thenReturn(List.of(zone(301, "ZONE-SERVICE", "Normal service area", "ELIGIBLE_SERVICE_AREA", null)));
        when(database.findBoundaryZones(202, "CB-NY", 100))
                .thenReturn(List.of());

        GeographicRiskResponse response = service.evaluate(REQUEST, "idem-key-001");

        assertThat(response.applicationId()).isEqualTo("APP-RISK-005");
        assertThat(response.service()).isEqualTo("geographic-risk-service");
        assertThat(response.disposition()).isEqualTo(Disposition.CLEAR);
        assertThat(response.signals()).singleElement().satisfies(signal -> {
            assertThat(signal.signalCode()).isEqualTo("LOCATION_IN_SERVICE_AREA");
            assertThat(signal.signalResult()).isEqualTo(SignalResult.PASS);
            assertThat(signal.routingEffect()).isEqualTo(RoutingEffect.NONE);
            assertThat(signal.zoneId()).isEqualTo("ZONE-SERVICE");
        });
        assertThat(MDC.get("cloudbank.application_id")).isEqualTo("APP-RISK-005");
        assertThat(MDC.get("cloudbank.workflow_id")).isEqualTo("WF-APP-RISK-005");
        assertThat(MDC.get("trace_id")).isEqualTo("0123456789abcdef0123456789abcdef");

        ArgumentCaptor<GeographicRiskEvaluationEntity> evaluation =
                ArgumentCaptor.forClass(GeographicRiskEvaluationEntity.class);
        verify(evaluationRepository).insert(evaluation.capture());
        assertThat(evaluation.getValue().disposition()).isEqualTo(Disposition.CLEAR);
        assertThat(evaluation.getValue().idempotencyKey()).isEqualTo("idem-key-001");

        ArgumentCaptor<SpatialSignalEntity> signal = ArgumentCaptor.forClass(SpatialSignalEntity.class);
        verify(signalRepository).insert(signal.capture());
        assertThat(signal.getValue().signalType()).isEqualTo("JURISDICTION_ELIGIBILITY");
        assertThat(signal.getValue().signalResult()).isEqualTo(SignalResult.PASS);
        assertThat(signal.getValue().routingEffect()).isEqualTo(RoutingEffect.NONE);
    }

    @Test
    void evaluateUsesCoordinatesResolvedByGcdRForSpatialChecks() {
        ApplicationAddress address = new ApplicationAddress(101, 202, "CB-NY", true,
                -75.835D, 38.93D, GeocodingStatus.RESOLVED);
        when(database.findApplicationAddress("APP-RISK-005")).thenReturn(Optional.of(address));
        when(evaluationRepository.findByIdempotency(101, "idem-key-geocoded")).thenReturn(Optional.empty());
        when(database.findInsideZones(202, "CB-NY", -75.835D, 38.93D))
                .thenReturn(List.of(zone(301, "ZONE-SERVICE", "Normal service area", "ELIGIBLE_SERVICE_AREA", null)));
        when(database.findBoundaryZones(202, "CB-NY", 100, -75.835D, 38.93D)).thenReturn(List.of());

        GeographicRiskResponse response = service.evaluate(REQUEST, "idem-key-geocoded");

        assertThat(response.disposition()).isEqualTo(Disposition.CLEAR);
        verify(database).findInsideZones(202, "CB-NY", -75.835D, 38.93D);
        verify(database).findBoundaryZones(202, "CB-NY", 100, -75.835D, 38.93D);
        verify(database, never()).findInsideZones(202, "CB-NY");
        verify(database, never()).findBoundaryZones(202, "CB-NY", 100);
    }

    @Test
    void evaluateRoutesUnavailableGeocodingToManualReview() {
        ApplicationAddress address = new ApplicationAddress(101, 202, "CB-NY", false,
                null, null, GeocodingStatus.UNAVAILABLE);
        when(database.findApplicationAddress("APP-RISK-005")).thenReturn(Optional.of(address));
        when(evaluationRepository.findByIdempotency(101, "idem-key-geocode-unavailable"))
                .thenReturn(Optional.empty());

        GeographicRiskResponse response = service.evaluate(REQUEST, "idem-key-geocode-unavailable");

        assertThat(response.disposition()).isEqualTo(Disposition.MANUAL_REVIEW);
        assertThat(response.signals()).singleElement().satisfies(signal -> {
            assertThat(signal.signalCode()).isEqualTo("SPATIAL_EVALUATION_UNAVAILABLE");
            assertThat(signal.signalResult()).isEqualTo(SignalResult.NOT_EVALUATED);
            assertThat(signal.routingEffect()).isEqualTo(RoutingEffect.MANUAL_REVIEW);
        });
    }

    @Test
    void evaluateReturnsManualReviewWhenRiskZoneOrBoundaryMatches() {
        when(database.findApplicationAddress("APP-RISK-005"))
                .thenReturn(Optional.of(address(true)));
        when(evaluationRepository.findByIdempotency(101, "idem-key-002"))
                .thenReturn(Optional.empty());
        when(database.findInsideZones(202, "CB-NY"))
                .thenReturn(List.of(
                        zone(301, "ZONE-SERVICE", "Normal service area", "ELIGIBLE_SERVICE_AREA", null),
                        zone(302, "ZONE-RISK", "Synthetic risk area", "FRAUD_REVIEW_AREA", null)));
        when(database.findBoundaryZones(202, "CB-NY", 100))
                .thenReturn(List.of(zone(303, "ZONE-BOUNDARY", "Boundary review area", "BOUNDARY_REVIEW", 82.4)));

        GeographicRiskResponse response = service.evaluate(REQUEST, "idem-key-002");

        assertThat(response.disposition()).isEqualTo(Disposition.MANUAL_REVIEW);
        assertThat(response.signals()).extracting(GeographicSignalResponse::signalCode)
                .containsExactly("LOCATION_IN_SERVICE_AREA", "LOCATION_RISK_REVIEW", "BOUNDARY_REVIEW_REQUIRED");
        assertThat(response.signals()).extracting(GeographicSignalResponse::routingEffect)
                .contains(RoutingEffect.MANUAL_REVIEW);
    }

    @Test
    void evaluateBlocksWhenAddressIsOutsideServiceArea() {
        when(database.findApplicationAddress("APP-RISK-005"))
                .thenReturn(Optional.of(address(true)));
        when(evaluationRepository.findByIdempotency(101, "idem-key-003"))
                .thenReturn(Optional.empty());
        when(database.findInsideZones(202, "CB-NY")).thenReturn(List.of());
        when(database.findBoundaryZones(202, "CB-NY", 100)).thenReturn(List.of());

        GeographicRiskResponse response = service.evaluate(REQUEST, "idem-key-003");

        assertThat(response.disposition()).isEqualTo(Disposition.BLOCKED);
        assertThat(response.signals()).singleElement().satisfies(signal -> {
            assertThat(signal.signalCode()).isEqualTo("LOCATION_EXCLUDED");
            assertThat(signal.signalResult()).isEqualTo(SignalResult.FAIL);
            assertThat(signal.routingEffect()).isEqualTo(RoutingEffect.BLOCKED);
        });
    }

    @Test
    void evaluateBlocksWhenExcludedZoneMatches() {
        when(database.findApplicationAddress("APP-RISK-005"))
                .thenReturn(Optional.of(address(true)));
        when(evaluationRepository.findByIdempotency(101, "idem-key-004"))
                .thenReturn(Optional.empty());
        when(database.findInsideZones(202, "CB-NY"))
                .thenReturn(List.of(
                        zone(301, "ZONE-SERVICE", "Normal service area", "ELIGIBLE_SERVICE_AREA", null),
                        zone(304, "ZONE-EXCLUDED", "Excluded area", "EXCLUDED_AREA", null)));
        when(database.findBoundaryZones(202, "CB-NY", 100)).thenReturn(List.of());

        GeographicRiskResponse response = service.evaluate(REQUEST, "idem-key-004");

        assertThat(response.disposition()).isEqualTo(Disposition.BLOCKED);
        assertThat(response.signals()).extracting(GeographicSignalResponse::signalCode)
                .contains("LOCATION_IN_SERVICE_AREA", "LOCATION_EXCLUDED");
    }

    @Test
    void evaluateReturnsNotEvaluatedWhenCoordinatesAreMissing() {
        when(database.findApplicationAddress("APP-RISK-005"))
                .thenReturn(Optional.of(address(false)));
        when(evaluationRepository.findByIdempotency(101, "idem-key-005"))
                .thenReturn(Optional.empty());

        GeographicRiskResponse response = service.evaluate(REQUEST, "idem-key-005");

        assertThat(response.disposition()).isEqualTo(Disposition.NOT_EVALUATED);
        assertThat(response.signals()).singleElement().satisfies(signal -> {
            assertThat(signal.signalCode()).isEqualTo("ADDRESS_COORDINATES_MISSING");
            assertThat(signal.signalResult()).isEqualTo(SignalResult.NOT_EVALUATED);
            assertThat(signal.routingEffect()).isEqualTo(RoutingEffect.NONE);
        });
        verify(database, never()).findInsideZones(anyLong(), anyString());
        verify(database, never()).findBoundaryZones(anyLong(), anyString(), anyDouble());
    }

    @Test
    void evaluateReturnsExistingIdempotentResult() {
        when(database.findApplicationAddress("APP-RISK-005"))
                .thenReturn(Optional.of(address(true)));
        GeographicRiskEvaluationEntity existing = new GeographicRiskEvaluationEntity(
                "GEO-EVAL-EXISTING",
                101,
                REQUEST.workflowId(),
                REQUEST.taskReference(),
                REQUEST.traceId(),
                "idem-key-006",
                requestHash(REQUEST),
                Disposition.MANUAL_REVIEW);
        when(evaluationRepository.findByIdempotency(101, "idem-key-006"))
                .thenReturn(Optional.of(existing));
        when(signalRepository.listByEvaluation("GEO-EVAL-EXISTING"))
                .thenReturn(List.of(new SpatialSignalEntity(101, 202, "GEO-EVAL-EXISTING",
                        new SpatialSignalDraft("BOUNDARY_REVIEW_REQUIRED", "BOUNDARY_PROXIMITY",
                                "Address near configured review boundary", SignalResult.REVIEW,
                                RoutingEffect.MANUAL_REVIEW, 303L, "ZONE-BOUNDARY",
                                "Boundary review area", 82.4))));
        when(database.findZoneBySk(303L))
                .thenReturn(Optional.of(zone(303, "ZONE-BOUNDARY", "Boundary review area", "BOUNDARY_REVIEW", null)));

        GeographicRiskResponse response = service.evaluate(REQUEST, "idem-key-006");

        assertThat(response.evaluationId()).isEqualTo("GEO-EVAL-EXISTING");
        assertThat(response.disposition()).isEqualTo(Disposition.MANUAL_REVIEW);
        assertThat(response.signals()).singleElement().satisfies(signal -> {
            assertThat(signal.signalCode()).isEqualTo("BOUNDARY_REVIEW_REQUIRED");
            assertThat(signal.zoneId()).isEqualTo("ZONE-BOUNDARY");
        });
        verify(evaluationRepository, never()).insert(any());
        verify(signalRepository, never()).insert(any());
    }

    @Test
    void evaluateRejectsIdempotencyKeyConflict() {
        when(database.findApplicationAddress("APP-RISK-005"))
                .thenReturn(Optional.of(address(true)));
        GeographicRiskEvaluationEntity existing = new GeographicRiskEvaluationEntity(
                "GEO-EVAL-EXISTING", 101, REQUEST.workflowId(), REQUEST.taskReference(), REQUEST.traceId(),
                "idem-key-007", "deadbeef", Disposition.CLEAR);
        when(evaluationRepository.findByIdempotency(101, "idem-key-007"))
                .thenReturn(Optional.of(existing));

        assertThatThrownBy(() -> service.evaluate(REQUEST, "idem-key-007"))
                .isInstanceOf(WebApplicationException.class)
                .satisfies(exception -> assertThat(((WebApplicationException) exception).getResponse().getStatus())
                        .isEqualTo(409));
    }

    @Test
    void evaluateRejectsMissingOrUnsafeIdempotencyKey() {
        assertThatThrownBy(() -> service.evaluate(REQUEST, null))
                .isInstanceOf(BadRequestException.class);
        assertThatThrownBy(() -> service.evaluate(REQUEST, "bad"))
                .isInstanceOf(BadRequestException.class);
        assertThatThrownBy(() -> service.evaluate(REQUEST, "not safe spaces"))
                .isInstanceOf(BadRequestException.class);
    }

    @Test
    void evaluateReturnsNotFoundWhenApplicationAddressIsMissing() {
        when(database.findApplicationAddress("APP-RISK-005")).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.evaluate(REQUEST, "idem-key-008"))
                .isInstanceOf(NotFoundException.class);
    }

    @Test
    void latestReturnsMostRecentEvaluationSummary() {
        when(database.findApplicationAddress("APP-RISK-005"))
                .thenReturn(Optional.of(address(true)));
        when(database.findLatestEvaluation(101))
                .thenReturn(Optional.of(new LatestGeographicRiskEvaluation("GEO-EVAL-LATEST", Disposition.CLEAR)));
        when(signalRepository.listByEvaluation("GEO-EVAL-LATEST"))
                .thenReturn(List.of(new SpatialSignalEntity(101, 202, "GEO-EVAL-LATEST",
                        new SpatialSignalDraft("LOCATION_IN_SERVICE_AREA", "JURISDICTION_ELIGIBILITY",
                                "Address is inside a configured service area", SignalResult.PASS,
                                RoutingEffect.NONE, 301L, "ZONE-SERVICE", "Normal service area", null))));
        when(database.findZoneBySk(301L))
                .thenReturn(Optional.of(zone(301, "ZONE-SERVICE", "Normal service area", "ELIGIBLE_SERVICE_AREA", null)));

        ApplicationGeographicRiskResponse response = service.latest("APP-RISK-005");

        assertThat(response.applicationId()).isEqualTo("APP-RISK-005");
        assertThat(response.latestEvaluationId()).isEqualTo("GEO-EVAL-LATEST");
        assertThat(response.disposition()).isEqualTo(Disposition.CLEAR);
        assertThat(response.signalCount()).isEqualTo(1);
        assertThat(response.signals()).singleElement()
                .extracting(GeographicSignalResponse::signalCode)
                .isEqualTo("LOCATION_IN_SERVICE_AREA");
    }

    @Test
    void latestReturnsNotFoundWhenNoEvaluationExists() {
        when(database.findApplicationAddress("APP-RISK-005"))
                .thenReturn(Optional.of(address(true)));
        when(database.findLatestEvaluation(101)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.latest("APP-RISK-005"))
                .isInstanceOf(NotFoundException.class);
    }

    @Test
    void readyReflectsDatabaseAvailability() {
        when(database.available()).thenReturn(true, false);

        assertThat(service.ready()).isTrue();
        assertThat(service.ready()).isFalse();
    }

    private static ApplicationAddress address(boolean hasLocation) {
        return new ApplicationAddress(101, 202, "CB-NY", hasLocation);
    }

    @Test
    void concurrentRequestsReturnTheSameEvaluationWithoutDuplicateSignals() throws Exception {
        when(database.findApplicationAddress(REQUEST.applicationId())).thenReturn(Optional.of(address(false)));
        CyclicBarrier bothReadMissing = new CyclicBarrier(2);
        AtomicInteger reads = new AtomicInteger();
        AtomicReference<GeographicRiskEvaluationEntity> winner = new AtomicReference<>();
        when(evaluationRepository.findByIdempotency(101, "idem-concurrent"))
                .thenAnswer(invocation -> {
                    if (reads.incrementAndGet() <= 2) {
                        bothReadMissing.await(5, TimeUnit.SECONDS);
                        return Optional.empty();
                    }
                    return Optional.of(winner.get());
                });
        when(evaluationRepository.insert(any())).thenAnswer(invocation -> {
            GeographicRiskEvaluationEntity evaluation = invocation.getArgument(0);
            if (!winner.compareAndSet(null, evaluation)) {
                throw collision("CB_GEO_RISK_EVAL_IDEM_UK");
            }
            return evaluation;
        });
        when(signalRepository.listByEvaluation(anyString())).thenAnswer(invocation -> List.of(
                new SpatialSignalEntity(101, 202, invocation.getArgument(0),
                        new SpatialSignalDraft("ADDRESS_COORDINATES_MISSING", "JURISDICTION_ELIGIBILITY",
                                "Address coordinates are missing", SignalResult.NOT_EVALUATED,
                                RoutingEffect.NONE, null, null, null, null))));
        try (var executor = Executors.newFixedThreadPool(2)) {
            var first = executor.submit(() -> service.evaluate(REQUEST, "idem-concurrent"));
            var second = executor.submit(() -> service.evaluate(REQUEST, "idem-concurrent"));
            GeographicRiskResponse a = first.get(10, TimeUnit.SECONDS);
            GeographicRiskResponse b = second.get(10, TimeUnit.SECONDS);
            assertThat(a).isEqualTo(b);
            assertThat(a.evaluationId()).isEqualTo(winner.get().evaluationId());
        }
        verify(signalRepository, times(1)).insert(any());
    }

    @Test
    void collisionWithDifferentRequestReturnsConflictAfterRollback() {
        when(database.findApplicationAddress(REQUEST.applicationId())).thenReturn(Optional.of(address(false)));
        var existing = new GeographicRiskEvaluationEntity("GEO-EVAL-WINNER", 101,
                REQUEST.workflowId(), REQUEST.taskReference(), REQUEST.traceId(), "idem-collision",
                "different-request-hash", Disposition.CLEAR);
        when(evaluationRepository.findByIdempotency(101, "idem-collision"))
                .thenReturn(Optional.empty(), Optional.of(existing), Optional.of(existing));
        when(evaluationRepository.insert(any())).thenThrow(collision("CB_GEO_RISK_EVAL_IDEM_UK"));

        assertThatThrownBy(() -> service.evaluate(REQUEST, "idem-collision"))
                .isInstanceOf(WebApplicationException.class)
                .satisfies(error -> assertThat(((WebApplicationException) error).getResponse().getStatus())
                        .isEqualTo(409));
        verify(signalRepository, never()).insert(any());
    }

    @Test
    void collisionWithoutVisibleWinnerReturnsRetryableUnavailable() {
        when(database.findApplicationAddress(REQUEST.applicationId())).thenReturn(Optional.of(address(false)));
        when(evaluationRepository.findByIdempotency(101, "idem-collision"))
                .thenReturn(Optional.empty());
        when(evaluationRepository.insert(any())).thenThrow(collision("CB_GEO_RISK_EVAL_IDEM_UK"));

        assertThatThrownBy(() -> service.evaluate(REQUEST, "idem-collision"))
                .isInstanceOf(WebApplicationException.class)
                .satisfies(error -> assertThat(((WebApplicationException) error).getResponse().getStatus())
                        .isEqualTo(503));
    }

    @Test
    void unrelatedUniqueConstraintIsNotTreatedAsIdempotentReplay() {
        when(database.findApplicationAddress(REQUEST.applicationId())).thenReturn(Optional.of(address(false)));
        when(evaluationRepository.findByIdempotency(101, "idem-unrelated"))
                .thenReturn(Optional.empty());
        when(evaluationRepository.insert(any())).thenThrow(collision("CB_OTHER_UK"));

        assertThatThrownBy(() -> service.evaluate(REQUEST, "idem-unrelated"))
                .hasRootCauseInstanceOf(SQLException.class);
        verify(evaluationRepository, times(1)).findByIdempotency(101, "idem-unrelated");
        verify(signalRepository, never()).insert(any());
    }

    private static RuntimeException collision(String constraint) {
        return new jakarta.persistence.RollbackException("Insert failed",
                new SQLException("ORA-00001: unique constraint (CLOUDBANK." + constraint + ") violated",
                        "23000", 1));
    }

    private static ZoneMatch zone(long sk, String id, String name, String type, Double distance) {
        return new ZoneMatch(sk, id, name, type, distance);
    }

    private static String requestHash(GeographicRiskRequest request) {
        String source = request.applicationId() + "\n" + request.workflowId() + "\n"
                + request.taskReference() + "\n" + request.traceId();
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256")
                    .digest(source.getBytes(StandardCharsets.UTF_8)));
        } catch (Exception exception) {
            throw new IllegalStateException(exception);
        }
    }
}
