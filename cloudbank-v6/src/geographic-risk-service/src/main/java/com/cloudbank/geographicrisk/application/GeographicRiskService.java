// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.geographicrisk.application;

import com.cloudbank.geographicrisk.api.ApplicationGeographicRiskResponse;
import com.cloudbank.geographicrisk.api.GeographicRiskRequest;
import com.cloudbank.geographicrisk.api.GeographicRiskResponse;
import com.cloudbank.geographicrisk.api.GeographicSignalResponse;
import com.cloudbank.geographicrisk.domain.ApplicationAddress;
import com.cloudbank.geographicrisk.domain.Disposition;
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

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import io.helidon.transaction.Tx;
import io.helidon.transaction.TxException;
import jakarta.ws.rs.BadRequestException;
import jakarta.ws.rs.NotFoundException;
import jakarta.ws.rs.WebApplicationException;
import jakarta.ws.rs.core.Response;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.slf4j.MDC;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.sql.SQLException;
import java.util.Collections;
import java.util.IdentityHashMap;
import java.util.Set;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HexFormat;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.Callable;

@ApplicationScoped
public class GeographicRiskService {

    private static final String SERVICE_NAME = "geographic-risk-service";

    private final GeographicRiskDatabase database;
    private final GeographicRiskEvaluationRepository evaluationRepository;
    private final SpatialSignalRepository signalRepository;
    private final double boundaryDistanceMeters;

    @Inject
    public GeographicRiskService(GeographicRiskDatabase database,
            GeographicRiskEvaluationRepository evaluationRepository,
            SpatialSignalRepository signalRepository,
            @ConfigProperty(name = "geographic-risk.boundary-distance-meters", defaultValue = "100")
                    double boundaryDistanceMeters) {
        this.database = database;
        this.evaluationRepository = evaluationRepository;
        this.signalRepository = signalRepository;
        this.boundaryDistanceMeters = boundaryDistanceMeters;
    }

    public GeographicRiskResponse evaluate(GeographicRiskRequest request, String idempotencyKey) {
        requireIdempotencyKey(idempotencyKey);
        try {
            return inNewTransaction(() -> evaluateInTransaction(request, idempotencyKey));
        } catch (RuntimeException exception) {
            if (!isIdempotencyCollision(exception)) {
                throw exception;
            }
            // The losing transaction has rolled back. Read the winner using a fresh
            // EntityManager, including its committed signals and request hash.
            return inNewTransaction(() -> {
                ApplicationAddress address = database.findApplicationAddress(request.applicationId())
                        .orElseThrow(() -> new NotFoundException("Application address was not found"));
                if (evaluationRepository.findByIdempotency(address.applicationSk(), idempotencyKey).isEmpty()) {
                    throw new WebApplicationException("Evaluation is not yet available; retry the request",
                            Response.Status.SERVICE_UNAVAILABLE);
                }
                return evaluateInTransaction(request, idempotencyKey);
            });
        }
    }

    private static GeographicRiskResponse inNewTransaction(Callable<GeographicRiskResponse> action) {
        try {
            return Tx.transaction(Tx.Type.NEW, action);
        } catch (TxException exception) {
            Set<Throwable> visited = Collections.newSetFromMap(new IdentityHashMap<>());
            for (Throwable cause = exception; cause != null && visited.add(cause); cause = cause.getCause()) {
                if (cause instanceof WebApplicationException web) {
                    throw web;
                }
            }
            throw exception;
        }
    }

    private GeographicRiskResponse evaluateInTransaction(GeographicRiskRequest request, String idempotencyKey) {
        withMdc(request.applicationId(), request.workflowId(), request.taskReference(), request.traceId(), null);
        ApplicationAddress address = database.findApplicationAddress(request.applicationId())
                .orElseThrow(() -> new NotFoundException("Application address was not found"));
        String requestHash = hash(request);
        Optional<GeographicRiskEvaluationEntity> existing =
                evaluationRepository.findByIdempotency(address.applicationSk(), idempotencyKey);
        if (existing.isPresent()) {
            GeographicRiskEvaluationEntity evaluation = existing.get();
            if (!evaluation.requestHash().equalsIgnoreCase(requestHash)) {
                throw new WebApplicationException("Idempotency key was already used for a different request",
                        Response.Status.CONFLICT);
            }
            withMdc(request.applicationId(), request.workflowId(), request.taskReference(),
                    request.traceId(), evaluation.evaluationId());
            List<GeographicSignalResponse> signals = signalResponses(evaluation.evaluationId());
            if (signals.isEmpty()) {
                List<SpatialSignalDraft> drafts = evaluateSignals(address);
                persistSignals(address, evaluation.evaluationId(), drafts);
                signals = drafts.stream().map(SpatialSignalDraft::toResponse).toList();
            }
            return response(request.applicationId(), evaluation, signals);
        }

        List<SpatialSignalDraft> drafts = evaluateSignals(address);
        Disposition disposition = disposition(drafts);
        String evaluationId = "GEO-EVAL-" + UUID.randomUUID();
        withMdc(request.applicationId(), request.workflowId(), request.taskReference(), request.traceId(),
                evaluationId);
        GeographicRiskEvaluationEntity evaluation = new GeographicRiskEvaluationEntity(
                evaluationId, address.applicationSk(), request.workflowId(), request.taskReference(),
                request.traceId(), idempotencyKey, requestHash, disposition);
        evaluationRepository.insert(evaluation);
        persistSignals(address, evaluationId, drafts);
        return response(request.applicationId(), evaluation, drafts.stream().map(SpatialSignalDraft::toResponse).toList());
    }

    private static boolean isIdempotencyCollision(Throwable exception) {
        Set<Throwable> visited = Collections.newSetFromMap(new IdentityHashMap<>());
        for (Throwable cause = exception; cause != null && visited.add(cause); cause = cause.getCause()) {
            if (cause instanceof SQLException sql) {
                Set<SQLException> sqlVisited = Collections.newSetFromMap(new IdentityHashMap<>());
                for (SQLException current = sql; current != null && sqlVisited.add(current);
                        current = current.getNextException()) {
                    if (current.getErrorCode() == 1 && current.getMessage() != null
                            && current.getMessage().toUpperCase(java.util.Locale.ROOT)
                                    .contains("CB_GEO_RISK_EVAL_IDEM_UK")) {
                        return true;
                    }
                }
            }
        }
        return false;
    }

    public ApplicationGeographicRiskResponse latest(String applicationId) {
        ApplicationAddress address = database.findApplicationAddress(applicationId)
                .orElseThrow(() -> new NotFoundException("Application address was not found"));
        LatestGeographicRiskEvaluation evaluation = database.findLatestEvaluation(address.applicationSk())
                .orElseThrow(() -> new NotFoundException("Geographic risk evaluation was not found"));
        List<GeographicSignalResponse> signals = signalResponses(evaluation.evaluationId());
        return new ApplicationGeographicRiskResponse(applicationId, evaluation.evaluationId(),
                evaluation.disposition(), signals.size(), signals);
    }

    public boolean ready() {
        return database.available();
    }

    private List<SpatialSignalDraft> evaluateSignals(ApplicationAddress address) {
        List<SpatialSignalDraft> signals = new ArrayList<>();
        if (!address.hasLocation()) {
            boolean unavailable = address.geocodingUnavailable();
            signals.add(new SpatialSignalDraft(
                    unavailable ? "SPATIAL_EVALUATION_UNAVAILABLE" : "ADDRESS_COORDINATES_MISSING",
                    "JURISDICTION_ELIGIBILITY",
                    unavailable ? "Address geocoding is unavailable" : "Address coordinates are missing",
                    SignalResult.NOT_EVALUATED,
                    unavailable ? RoutingEffect.MANUAL_REVIEW : RoutingEffect.NONE,
                    null, null, null, null));
            return signals;
        }

        List<ZoneMatch> insideZones;
        List<ZoneMatch> boundaryZones;
        if (address.hasCoordinates()) {
            insideZones = database.findInsideZones(address.addressSk(), address.jurisdictionCode(),
                    address.longitude(), address.latitude());
            boundaryZones = database.findBoundaryZones(address.addressSk(), address.jurisdictionCode(),
                    boundaryDistanceMeters, address.longitude(), address.latitude());
        } else {
            insideZones = database.findInsideZones(address.addressSk(), address.jurisdictionCode());
            boundaryZones = database.findBoundaryZones(address.addressSk(), address.jurisdictionCode(),
                    boundaryDistanceMeters);
        }

        insideZones.stream()
                .filter(zone -> "ELIGIBLE_SERVICE_AREA".equals(zone.zoneType()))
                .findFirst()
                .ifPresentOrElse(
                        zone -> signals.add(signal("LOCATION_IN_SERVICE_AREA", "JURISDICTION_ELIGIBILITY",
                                "Address is inside a configured service area", SignalResult.PASS,
                                RoutingEffect.NONE, zone)),
                        () -> signals.add(new SpatialSignalDraft("LOCATION_EXCLUDED", "JURISDICTION_ELIGIBILITY",
                                "Address is not inside a configured service area", SignalResult.FAIL,
                                RoutingEffect.BLOCKED, null, null, null, null)));

        insideZones.stream()
                .filter(zone -> "EXCLUDED_AREA".equals(zone.zoneType()))
                .findFirst()
                .ifPresent(zone -> signals.add(signal("LOCATION_EXCLUDED", "JURISDICTION_ELIGIBILITY",
                        "Address is inside a configured excluded area", SignalResult.FAIL,
                        RoutingEffect.BLOCKED, zone)));

        insideZones.stream()
                .filter(zone -> "FRAUD_REVIEW_AREA".equals(zone.zoneType()))
                .findFirst()
                .ifPresent(zone -> signals.add(signal("LOCATION_RISK_REVIEW", "RISK_ZONE_INTERSECTION",
                        "Address is inside a synthetic location-risk zone", SignalResult.REVIEW,
                        RoutingEffect.MANUAL_REVIEW, zone)));

        boundaryZones.stream()
                .min(Comparator.comparing(ZoneMatch::distanceToBoundaryMeters,
                        Comparator.nullsLast(Comparator.naturalOrder())))
                .ifPresent(zone -> signals.add(signal("BOUNDARY_REVIEW_REQUIRED", "BOUNDARY_PROXIMITY",
                        "Address near configured review boundary", SignalResult.REVIEW,
                        RoutingEffect.MANUAL_REVIEW, zone)));

        return signals;
    }

    private SpatialSignalDraft signal(String code, String type, String label, SignalResult result,
            RoutingEffect effect, ZoneMatch zone) {
        return new SpatialSignalDraft(code, type, label, result, effect, zone.jurisdictionZoneSk(),
                zone.zoneId(), zone.zoneName(), zone.distanceToBoundaryMeters());
    }

    private void persistSignals(ApplicationAddress address, String evaluationId, List<SpatialSignalDraft> drafts) {
        drafts.forEach(signal -> signalRepository.insert(
                new SpatialSignalEntity(address.applicationSk(), address.addressSk(), evaluationId, signal)));
    }

    private Disposition disposition(List<SpatialSignalDraft> signals) {
        if (signals.stream().anyMatch(signal -> signal.routingEffect() == RoutingEffect.BLOCKED)) {
            return Disposition.BLOCKED;
        }
        if (signals.stream().anyMatch(signal -> signal.routingEffect() == RoutingEffect.MANUAL_REVIEW)) {
            return Disposition.MANUAL_REVIEW;
        }
        if (signals.stream().allMatch(signal -> signal.signalResult() == SignalResult.NOT_EVALUATED)) {
            return Disposition.NOT_EVALUATED;
        }
        return Disposition.CLEAR;
    }

    private List<GeographicSignalResponse> signalResponses(String evaluationId) {
        return signalRepository.listByEvaluation(evaluationId).stream()
                .map(signal -> {
                    Optional<ZoneMatch> zone = database.findZoneBySk(signal.jurisdictionZoneSk());
                    String signalCode = signalCode(signal);
                    String label = label(signalCode);
                    return new GeographicSignalResponse(signalCode, label, signal.signalResult(),
                            signal.routingEffect(), zone.map(ZoneMatch::zoneId).orElse(null),
                            zone.map(ZoneMatch::zoneName).orElse(null), signal.distanceToBoundaryMeters());
                })
                .toList();
    }

    private String signalCode(SpatialSignalEntity signal) {
        if (signal.signalCode() != null) {
            return signal.signalCode();
        }
        if (signal.signalResult() == SignalResult.NOT_EVALUATED) {
            return "ADDRESS_COORDINATES_MISSING";
        }
        if ("BOUNDARY_PROXIMITY".equals(signal.signalType())) {
            return "BOUNDARY_REVIEW_REQUIRED";
        }
        if ("RISK_ZONE_INTERSECTION".equals(signal.signalType())) {
            return "LOCATION_RISK_REVIEW";
        }
        if (signal.signalResult() == SignalResult.FAIL) {
            return "LOCATION_EXCLUDED";
        }
        return "LOCATION_IN_SERVICE_AREA";
    }

    private String label(String signalCode) {
        return switch (signalCode) {
            case "LOCATION_IN_SERVICE_AREA" -> "Address is inside a configured service area";
            case "LOCATION_EXCLUDED" -> "Address is not eligible for automatic location processing";
            case "BOUNDARY_REVIEW_REQUIRED" -> "Address near configured review boundary";
            case "LOCATION_RISK_REVIEW" -> "Address is inside a synthetic location-risk zone";
            case "ADDRESS_COORDINATES_MISSING" -> "Address coordinates are missing";
            case "SPATIAL_EVALUATION_UNAVAILABLE" -> "Address geocoding is unavailable";
            default -> "Geographic signal";
        };
    }

    private GeographicRiskResponse response(String applicationId, GeographicRiskEvaluationEntity evaluation,
            List<GeographicSignalResponse> signals) {
        return new GeographicRiskResponse(applicationId, evaluation.workflowId(), evaluation.taskReference(),
                SERVICE_NAME, evaluation.evaluationId(), evaluation.disposition(), signals, evaluation.traceId());
    }

    private static void requireIdempotencyKey(String idempotencyKey) {
        if (idempotencyKey == null || !idempotencyKey.matches("[A-Za-z0-9._:-]{8,200}")) {
            throw new BadRequestException("Idempotency-Key must contain 8 to 200 safe characters");
        }
    }

    private static String hash(GeographicRiskRequest request) {
        String source = request.applicationId() + "\n" + request.workflowId() + "\n"
                + request.taskReference() + "\n" + request.traceId();
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256")
                    .digest(source.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException("SHA-256 is unavailable", exception);
        }
    }

    private static void withMdc(String applicationId, String workflowId, String taskReference,
            String traceId, String evaluationId) {
        MDC.put("cloudbank.application_id", applicationId);
        MDC.put("cloudbank.workflow_id", workflowId);
        MDC.put("cloudbank.task_reference", taskReference);
        MDC.put("trace_id", traceId);
        if (evaluationId != null) {
            MDC.put("cloudbank.geographic_evaluation_id", evaluationId);
        }
    }
}
