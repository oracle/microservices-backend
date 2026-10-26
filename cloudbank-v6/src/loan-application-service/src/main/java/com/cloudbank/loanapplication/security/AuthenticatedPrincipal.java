// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.loanapplication.security;

import java.util.List;
import org.springframework.security.oauth2.jwt.Jwt;

public record AuthenticatedPrincipal(
        String principalId,
        String issuer,
        String subject,
        String displayName,
        String clientId,
        String tokenKind,
        List<String> roles) {

    public static AuthenticatedPrincipal from(Jwt jwt) {
        String tokenKind = jwt.getClaimAsString("token_kind");
        String clientId = jwt.getClaimAsString("client_id");
        String principalId = jwt.getClaimAsString("cb_principal_id");
        if ("service".equals(tokenKind) && (principalId == null || principalId.isBlank())) {
            principalId = "svc-" + (clientId == null ? jwt.getSubject() : clientId);
        }
        List<String> roles = jwt.getClaimAsStringList("roles");
        return new AuthenticatedPrincipal(
                principalId,
                jwt.getIssuer() == null ? null : jwt.getIssuer().toString(),
                jwt.getSubject(),
                jwt.getClaimAsString("name") == null ? jwt.getSubject() : jwt.getClaimAsString("name"),
                clientId,
                tokenKind == null ? "user" : tokenKind,
                roles == null ? List.of() : List.copyOf(roles));
    }

    public boolean hasRole(String role) {
        return roles.contains(role);
    }
}
