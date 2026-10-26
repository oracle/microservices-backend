// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.geographicrisk.domain;

import com.cloudbank.geographicrisk.api.GeographicSignalResponse;

public record SpatialSignalDraft(
        String signalCode,
        String signalType,
        String label,
        SignalResult signalResult,
        RoutingEffect routingEffect,
        Long jurisdictionZoneSk,
        String zoneId,
        String zoneName,
        Double distanceToBoundaryMeters) {

    public GeographicSignalResponse toResponse() {
        return new GeographicSignalResponse(signalCode, label, signalResult, routingEffect,
                zoneId, zoneName, distanceToBoundaryMeters);
    }
}
