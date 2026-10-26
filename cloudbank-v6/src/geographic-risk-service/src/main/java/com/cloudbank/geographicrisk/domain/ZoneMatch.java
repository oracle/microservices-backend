// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.geographicrisk.domain;

public record ZoneMatch(
        Long jurisdictionZoneSk,
        String zoneId,
        String zoneName,
        String zoneType,
        Double distanceToBoundaryMeters) {
}
