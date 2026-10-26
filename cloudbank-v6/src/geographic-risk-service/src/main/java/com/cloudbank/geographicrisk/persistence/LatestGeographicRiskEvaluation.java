// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.geographicrisk.persistence;

import com.cloudbank.geographicrisk.domain.Disposition;

public record LatestGeographicRiskEvaluation(
        String evaluationId,
        Disposition disposition) {
}
