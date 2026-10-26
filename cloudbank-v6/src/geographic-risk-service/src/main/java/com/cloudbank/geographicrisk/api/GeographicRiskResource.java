// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.geographicrisk.api;

import com.cloudbank.geographicrisk.application.GeographicRiskService;

import io.helidon.security.annotations.Authenticated;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.validation.Valid;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.HeaderParam;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;

import java.util.logging.Logger;

@Path("/")
@ApplicationScoped
@Authenticated
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
public class GeographicRiskResource {

    private static final Logger LOGGER = Logger.getLogger(GeographicRiskResource.class.getName());

    private final GeographicRiskService service;

    @Inject
    public GeographicRiskResource(GeographicRiskService service) {
        this.service = service;
    }

    @POST
    @Path("/internal/api/v1/geographic-risk/evaluations")
    public GeographicRiskResponse evaluate(@HeaderParam("Idempotency-Key") String idempotencyKey,
            @Valid GeographicRiskRequest request) {
        LOGGER.info(() -> "geographic risk evaluation requested applicationId=" + request.applicationId()
                + " workflowId=" + request.workflowId() + " taskReference=" + request.taskReference());
        try {
            return service.evaluate(request, idempotencyKey);
        } catch (RuntimeException exception) {
            throw new GeographicRiskApiException(exception);
        }
    }

    @GET
    @Path("/internal/api/v1/applications/{applicationId}/geographic-risk")
    public ApplicationGeographicRiskResponse latest(@PathParam("applicationId") String applicationId) {
        LOGGER.info(() -> "latest geographic risk requested applicationId=" + applicationId);
        try {
            return service.latest(applicationId);
        } catch (RuntimeException exception) {
            throw new GeographicRiskApiException(exception);
        }
    }
}
