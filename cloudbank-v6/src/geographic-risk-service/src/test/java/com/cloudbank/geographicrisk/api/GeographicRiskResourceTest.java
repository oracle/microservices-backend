// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.geographicrisk.api;

import com.cloudbank.geographicrisk.application.GeographicRiskService;
import com.cloudbank.geographicrisk.domain.Disposition;

import org.junit.jupiter.api.Test;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class GeographicRiskResourceTest {

    private final GeographicRiskService service = mock(GeographicRiskService.class);
    private final GeographicRiskResource resource = new GeographicRiskResource(service);

    @Test
    void evaluateDelegatesToService() {
        GeographicRiskRequest request = request();
        GeographicRiskResponse expected = new GeographicRiskResponse(
                "APP-RISK-005", "WF-APP-RISK-005", "evaluate-geographic-risk",
                "geographic-risk-service", "GEO-EVAL-1", Disposition.CLEAR, List.of(),
                "0123456789abcdef0123456789abcdef");
        when(service.evaluate(request, "idem-key-001")).thenReturn(expected);

        GeographicRiskResponse response = resource.evaluate("idem-key-001", request);

        assertThat(response).isSameAs(expected);
        verify(service).evaluate(request, "idem-key-001");
    }

    @Test
    void latestDelegatesToService() {
        ApplicationGeographicRiskResponse expected = new ApplicationGeographicRiskResponse(
                "APP-RISK-005", "GEO-EVAL-1", Disposition.CLEAR, 0, List.of());
        when(service.latest("APP-RISK-005")).thenReturn(expected);

        ApplicationGeographicRiskResponse response = resource.latest("APP-RISK-005");

        assertThat(response).isSameAs(expected);
        verify(service).latest("APP-RISK-005");
    }

    private static GeographicRiskRequest request() {
        return new GeographicRiskRequest("APP-RISK-005", "WF-APP-RISK-005",
                "evaluate-geographic-risk", "0123456789abcdef0123456789abcdef");
    }
}
