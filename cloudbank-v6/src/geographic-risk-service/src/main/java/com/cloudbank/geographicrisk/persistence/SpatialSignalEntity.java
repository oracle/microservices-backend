// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.geographicrisk.persistence;

import com.cloudbank.geographicrisk.domain.RoutingEffect;
import com.cloudbank.geographicrisk.domain.SignalResult;
import com.cloudbank.geographicrisk.domain.SpatialSignalDraft;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;

@Entity
@Table(schema = "CLOUDBANK", name = "cb_spatial_signal")
public class SpatialSignalEntity {

    @Column(name = "spatial_signal_sk", insertable = false, updatable = false)
    private Long spatialSignalSk;

    @Column(name = "application_sk", nullable = false)
    private long applicationSk;

    @Column(name = "address_sk", nullable = false)
    private long addressSk;

    @Column(name = "jurisdiction_zone_sk")
    private Long jurisdictionZoneSk;

    @Column(name = "geographic_evaluation_id", length = 80)
    private String geographicEvaluationId;

    @Id
    @Column(name = "signal_id", length = 80, nullable = false)
    private String signalId;

    @Column(name = "signal_code", length = 80)
    private String signalCode;

    @Column(name = "signal_type", length = 60, nullable = false)
    private String signalType;

    @Enumerated(EnumType.STRING)
    @Column(name = "signal_result", length = 60, nullable = false)
    private SignalResult signalResult;

    @Column(name = "distance_to_boundary_m")
    private Double distanceToBoundaryMeters;

    @Enumerated(EnumType.STRING)
    @Column(name = "routing_effect", length = 60, nullable = false)
    private RoutingEffect routingEffect;

    public SpatialSignalEntity() {
    }

    public SpatialSignalEntity(long applicationSk, long addressSk, String evaluationId, SpatialSignalDraft signal) {
        this.applicationSk = applicationSk;
        this.addressSk = addressSk;
        this.jurisdictionZoneSk = signal.jurisdictionZoneSk();
        this.geographicEvaluationId = evaluationId;
        this.signalId = signalId(evaluationId, signal.signalCode());
        this.signalCode = signal.signalCode();
        this.signalType = signal.signalType();
        this.signalResult = signal.signalResult();
        this.distanceToBoundaryMeters = signal.distanceToBoundaryMeters();
        this.routingEffect = signal.routingEffect();
    }

    public String geographicEvaluationId() {
        return geographicEvaluationId;
    }

    public String signalId() {
        return signalId;
    }

    public String signalCode() {
        return signalCode;
    }

    public String signalType() {
        return signalType;
    }

    public SignalResult signalResult() {
        return signalResult;
    }

    public RoutingEffect routingEffect() {
        return routingEffect;
    }

    public Long jurisdictionZoneSk() {
        return jurisdictionZoneSk;
    }

    public Double distanceToBoundaryMeters() {
        return distanceToBoundaryMeters;
    }

    private static String signalId(String evaluationId, String signalCode) {
        try {
            byte[] source = (evaluationId + ":" + signalCode).getBytes(StandardCharsets.UTF_8);
            return "GEO-SIG-" + HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(source));
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException("SHA-256 is unavailable", exception);
        }
    }
}
