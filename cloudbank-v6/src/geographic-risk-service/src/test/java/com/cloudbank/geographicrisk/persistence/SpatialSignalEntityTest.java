// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.geographicrisk.persistence;

import com.cloudbank.geographicrisk.domain.RoutingEffect;
import com.cloudbank.geographicrisk.domain.SignalResult;
import com.cloudbank.geographicrisk.domain.SpatialSignalDraft;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class SpatialSignalEntityTest {

    @Test
    void createsBoundedDeterministicIdForMissingCoordinatesSignal() {
        SpatialSignalDraft signal = new SpatialSignalDraft(
                "ADDRESS_COORDINATES_MISSING", "JURISDICTION_ELIGIBILITY",
                "Address coordinates are missing", SignalResult.NOT_EVALUATED,
                RoutingEffect.NONE, null, null, null, null);
        String evaluationId = "GEO-EVAL-12345678-1234-1234-1234-123456789abc";

        SpatialSignalEntity first = new SpatialSignalEntity(101, 202, evaluationId, signal);
        SpatialSignalEntity second = new SpatialSignalEntity(101, 202, evaluationId, signal);

        assertThat(first.signalId()).startsWith("GEO-SIG-").hasSize(72);
        assertThat(second.signalId()).isEqualTo(first.signalId());
    }
}
