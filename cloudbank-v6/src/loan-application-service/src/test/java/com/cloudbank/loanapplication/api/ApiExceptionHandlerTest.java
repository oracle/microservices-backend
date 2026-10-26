// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.loanapplication.api;

import static org.assertj.core.api.Assertions.assertThat;

import com.cloudbank.loanapplication.api.ApplicationApiModels.ErrorResponse;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.web.servlet.resource.NoResourceFoundException;

class ApiExceptionHandlerTest {

    private final ApiExceptionHandler handler = new ApiExceptionHandler();

    @Test
    void mapsMethodSecurityDenialToForbiddenResponse() {
        ResponseEntity<ErrorResponse> response = handler.accessDenied(new AccessDeniedException("denied"));

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
        assertThat(response.getBody()).isNotNull();
        assertThat(response.getBody().code()).isEqualTo("ACCESS_DENIED");
        assertThat(response.getBody().authorizationStatus()).isEqualTo("denied");
        assertThat(response.getBody().retryable()).isFalse();
        assertThat(response.getBody().correlationId()).isNotBlank();
    }

    @Test
    void mapsMissingResourceToNotFoundResponse() {
        ResponseEntity<ErrorResponse> response = handler.resourceNotFound(
                new NoResourceFoundException(HttpMethod.GET, "/api/v1/applications/APP-MR-002", null));

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
        assertThat(response.getBody()).isNotNull();
        assertThat(response.getBody().code()).isEqualTo("RESOURCE_NOT_FOUND");
        assertThat(response.getBody().retryable()).isFalse();
        assertThat(response.getBody().correlationId()).isNotBlank();
    }
}
