// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.geographicrisk.security;

import jakarta.annotation.Priority;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.ws.rs.Priorities;
import jakarta.ws.rs.container.ContainerRequestContext;
import jakarta.ws.rs.container.ContainerRequestFilter;
import jakarta.ws.rs.core.Response;
import jakarta.ws.rs.ext.Provider;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.eclipse.microprofile.jwt.JsonWebToken;

@Provider
@ApplicationScoped
@Priority(Priorities.AUTHORIZATION)
public class InternalAuthorizationFilter implements ContainerRequestFilter {

    private static final String INTERNAL_API_PREFIX = "internal/api/v1/";

    private final InternalAuthorization authorization;
    private final JsonWebToken token;

    @Inject
    public InternalAuthorizationFilter(
            @ConfigProperty(name = "geographic-risk.security.internal-client-ids") String clientIds,
            JsonWebToken token) {
        this.authorization = new InternalAuthorization(clientIds);
        this.token = token;
    }

    @Override
    public void filter(ContainerRequestContext requestContext) {
        if (requestContext.getUriInfo().getPath().startsWith(INTERNAL_API_PREFIX)
                && !authorization.isInternal(token)) {
            requestContext.abortWith(Response.status(Response.Status.FORBIDDEN).build());
        }
    }
}
