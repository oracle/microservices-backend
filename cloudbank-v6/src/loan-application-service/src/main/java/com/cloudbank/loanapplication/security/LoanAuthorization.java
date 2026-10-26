// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.loanapplication.security;

import java.util.Set;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.core.Authentication;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.stereotype.Component;

@Component("loanAuthorization")
public class LoanAuthorization {

    private final Set<String> internalClientIds;

    public LoanAuthorization(@Value("${cloudbank.security.internal-client-ids:cloudbank-service-client}")
            Set<String> internalClientIds) {
        this.internalClientIds = Set.copyOf(internalClientIds);
    }

    public boolean isInternal(Authentication authentication) {
        if (!(authentication instanceof JwtAuthenticationToken jwtAuthentication)) {
            return false;
        }
        AuthenticatedPrincipal principal = AuthenticatedPrincipal.from(jwtAuthentication.getToken());
        return "service".equals(principal.tokenKind())
                && principal.clientId() != null
                && internalClientIds.contains(principal.clientId())
                && authentication.getAuthorities().stream()
                        .anyMatch(authority -> "SCOPE_cloudbank.internal".equals(authority.getAuthority()));
    }
}
