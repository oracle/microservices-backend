// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.

package com.cloudbank.decision.security;

import java.util.Set;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.core.Authentication;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.stereotype.Component;

@Component("decisionAuthorization")
public class InternalAuthorization {
    @Value("${CLOUDBANK_WORKSPACE_READER_CLIENT_ID:cloudbank-bff-client-read}")
    private String workspaceReaderClientId = "cloudbank-bff-client-read";
    public boolean isWorkspaceReader(Authentication authentication) {
        return authentication instanceof JwtAuthenticationToken jwt
                && "service".equals(jwt.getToken().getClaimAsString("token_kind"))
                && workspaceReaderClientId.equals(jwt.getToken().getClaimAsString("client_id"))
                && authentication.getAuthorities().stream().anyMatch(authority ->
                        "SCOPE_cloudbank.workspace.read".equals(authority.getAuthority()));
    }

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
