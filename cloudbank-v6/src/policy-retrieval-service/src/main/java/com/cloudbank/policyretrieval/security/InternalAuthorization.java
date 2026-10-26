// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.policyretrieval.security;

import java.util.Set;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.core.Authentication;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.stereotype.Component;

@Component("policyRetrievalAuthorization")
public class InternalAuthorization {
    private final Set<String> clientIds;

    public InternalAuthorization(
            @Value("${cloudbank.security.internal-client-ids:cloudbank-service-client}") Set<String> clientIds) {
        this.clientIds = Set.copyOf(clientIds);
    }

    public boolean isInternal(Authentication authentication) {
        return authentication instanceof JwtAuthenticationToken jwt
                && "service".equals(jwt.getToken().getClaimAsString("token_kind"))
                && clientIds.contains(jwt.getToken().getClaimAsString("client_id"))
                && authentication.getAuthorities().stream()
                        .anyMatch(authority -> "SCOPE_cloudbank.internal".equals(authority.getAuthority()));
    }
}
