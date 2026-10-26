// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.geographicrisk.api;

import jakarta.ws.rs.WebApplicationException;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import org.junit.jupiter.api.Test;

import java.sql.SQLException;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

class GeographicRiskExceptionMapperTest {
    private final GeographicRiskExceptionMapper mapper = new GeographicRiskExceptionMapper();

    @Test
    void databaseFailureReturnsBoundedJsonWithoutSqlOrRequestValues() {
        var error = new jakarta.persistence.RollbackException("internal detail",
                new SQLException("ORA-00001: synthetic private request and SQL values", "23000", 1));
        try (Response response = mapper.toResponse(new GeographicRiskApiException(error))) {
            assertThat(response.getStatus()).isEqualTo(500);
            assertThat(response.getMediaType()).isEqualTo(MediaType.APPLICATION_JSON_TYPE);
            assertThat(response.getEntity()).isEqualTo(Map.of("code", "EVALUATION_FAILED",
                    "message", "Geographic risk request could not be processed"));
        }
    }

    @Test
    void transactionWrappedConflictRetains409() {
        var error = new RuntimeException("transaction failed",
                new WebApplicationException("sensitive detail", Response.Status.CONFLICT));
        try (Response response = mapper.toResponse(new GeographicRiskApiException(error))) {
            assertThat(response.getStatus()).isEqualTo(409);
            assertThat(((Map<?, ?>) response.getEntity()).get("code")).isEqualTo("IDEMPOTENCY_CONFLICT");
        }
    }

    @Test
    void unavailableResponseIncludesRetryAfter() {
        try (Response response = mapper.toResponse(new GeographicRiskApiException(
                new WebApplicationException(Response.Status.SERVICE_UNAVAILABLE)))) {
            assertThat(response.getStatus()).isEqualTo(503);
            assertThat(response.getHeaderString("Retry-After")).isEqualTo("1");
            assertThat(((Map<?, ?>) response.getEntity()).get("code")).isEqualTo("EVALUATION_UNAVAILABLE");
        }
    }
}
