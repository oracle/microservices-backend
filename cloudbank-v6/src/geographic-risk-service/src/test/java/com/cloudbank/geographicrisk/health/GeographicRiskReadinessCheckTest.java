// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.geographicrisk.health;

import com.cloudbank.geographicrisk.application.GeographicRiskService;

import org.eclipse.microprofile.health.HealthCheckResponse;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class GeographicRiskReadinessCheckTest {

    private final GeographicRiskService service = mock(GeographicRiskService.class);
    private final GeographicRiskReadinessCheck check = new GeographicRiskReadinessCheck(service);

    @Test
    void reportsUpWhenServiceIsReady() {
        when(service.ready()).thenReturn(true);

        HealthCheckResponse response = check.call();

        assertThat(response.getName()).isEqualTo("geographic-risk-database");
        assertThat(response.getStatus()).isEqualTo(HealthCheckResponse.Status.UP);
    }

    @Test
    void reportsDownWhenServiceIsNotReady() {
        when(service.ready()).thenReturn(false);

        HealthCheckResponse response = check.call();

        assertThat(response.getName()).isEqualTo("geographic-risk-database");
        assertThat(response.getStatus()).isEqualTo(HealthCheckResponse.Status.DOWN);
    }
}
