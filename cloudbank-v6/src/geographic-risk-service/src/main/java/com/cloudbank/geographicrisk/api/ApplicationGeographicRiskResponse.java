// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.geographicrisk.api;

import com.cloudbank.geographicrisk.domain.Disposition;

import java.util.List;

public record ApplicationGeographicRiskResponse(
        String applicationId,
        String latestEvaluationId,
        Disposition disposition,
        int signalCount,
        List<GeographicSignalResponse> signals) {
}
