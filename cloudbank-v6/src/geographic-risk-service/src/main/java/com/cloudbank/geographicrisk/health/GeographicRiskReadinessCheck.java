// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.geographicrisk.health;

import com.cloudbank.geographicrisk.application.GeographicRiskService;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import org.eclipse.microprofile.health.HealthCheck;
import org.eclipse.microprofile.health.HealthCheckResponse;
import org.eclipse.microprofile.health.Readiness;

@Readiness
@ApplicationScoped
public class GeographicRiskReadinessCheck implements HealthCheck {

    private final GeographicRiskService service;

    @Inject
    public GeographicRiskReadinessCheck(GeographicRiskService service) {
        this.service = service;
    }

    @Override
    public HealthCheckResponse call() {
        return HealthCheckResponse.named("geographic-risk-database")
                .status(service.ready())
                .build();
    }
}
