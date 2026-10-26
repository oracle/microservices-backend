// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.geographicrisk.api;

import jakarta.ws.rs.WebApplicationException;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import jakarta.ws.rs.ext.ExceptionMapper;
import jakarta.ws.rs.ext.Provider;

import java.util.Collections;
import java.util.IdentityHashMap;
import java.util.Map;
import java.util.Set;

/** Keeps database errors and request identifiers out of HTTP error responses. */
@Provider
public class GeographicRiskExceptionMapper implements ExceptionMapper<GeographicRiskApiException> {
    @Override
    public Response toResponse(GeographicRiskApiException exception) {
        int status = 500;
        Set<Throwable> visited = Collections.newSetFromMap(new IdentityHashMap<>());
        for (Throwable cause = exception; cause != null && visited.add(cause); cause = cause.getCause()) {
            if (cause instanceof WebApplicationException web) {
                status = web.getResponse().getStatus();
                break;
            }
        }
        String code = switch (status) {
            case 400 -> "INVALID_REQUEST";
            case 401 -> "UNAUTHORIZED";
            case 403 -> "FORBIDDEN";
            case 404 -> "NOT_FOUND";
            case 409 -> "IDEMPOTENCY_CONFLICT";
            case 503 -> "EVALUATION_UNAVAILABLE";
            default -> "EVALUATION_FAILED";
        };
        Response.ResponseBuilder response = Response.status(status).type(MediaType.APPLICATION_JSON_TYPE)
                .entity(Map.of("code", code, "message", "Geographic risk request could not be processed"));
        if (status == 503) {
            response.header("Retry-After", "1");
        }
        return response.build();
    }
}
