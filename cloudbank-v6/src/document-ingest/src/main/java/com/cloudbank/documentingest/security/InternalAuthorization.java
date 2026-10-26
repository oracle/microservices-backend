// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.documentingest.security;

import java.util.Set;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.core.Authentication;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.stereotype.Component;

@Component("documentIngestAuthorization")
public class InternalAuthorization {

    private final Set<String> clientIds;
    private final Set<String> reviewInputClientIds;

    public InternalAuthorization(@Value("${cloudbank.security.internal-client-ids:cloudbank-service-client}")
            Set<String> clientIds,
            @Value("${cloudbank.security.review-input-client-ids:cloudbank-ai-agent-client}")
            Set<String> reviewInputClientIds) {
        this.clientIds = Set.copyOf(clientIds);
        this.reviewInputClientIds = Set.copyOf(reviewInputClientIds);
    }

    public boolean isInternal(Authentication authentication) {
        return authorized(authentication, clientIds);
    }

    public boolean isReviewInputReader(Authentication authentication) {
        return isInternal(authentication) || authorized(authentication, reviewInputClientIds);
    }

    private boolean authorized(Authentication authentication, Set<String> allowedClients) {
        if (!(authentication instanceof JwtAuthenticationToken jwt)) {
            return false;
        }
        return "service".equals(jwt.getToken().getClaimAsString("token_kind"))
                && allowedClients.contains(jwt.getToken().getClaimAsString("client_id"))
                && authentication.getAuthorities().stream()
                        .anyMatch(authority -> "SCOPE_cloudbank.internal".equals(authority.getAuthority()));
    }
}
