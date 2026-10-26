// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.geographicrisk.api;

import com.cloudbank.geographicrisk.domain.Disposition;

import java.util.List;

public record GeographicRiskResponse(
        String applicationId,
        String workflowId,
        String taskReference,
        String service,
        String evaluationId,
        Disposition disposition,
        List<GeographicSignalResponse> signals,
        String traceId) {
}
