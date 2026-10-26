// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.geographicrisk.api;

import com.cloudbank.geographicrisk.domain.RoutingEffect;
import com.cloudbank.geographicrisk.domain.SignalResult;

public record GeographicSignalResponse(
        String signalCode,
        String label,
        SignalResult signalResult,
        RoutingEffect routingEffect,
        String zoneId,
        String zoneName,
        Double distanceToBoundaryMeters) {
}
