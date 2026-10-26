// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.

package com.cloudbank.gatewaybff;

import jakarta.servlet.http.HttpServletRequest;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.Authentication;
import org.springframework.security.oauth2.client.OAuth2AuthorizedClient;
import org.springframework.security.oauth2.client.authentication.OAuth2AuthenticationToken;
import org.springframework.security.oauth2.client.web.OAuth2AuthorizedClientRepository;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.stereotype.Component;
import org.springframework.web.server.ResponseStatusException;

@Component
class SessionIdentity {
    private final OAuth2AuthorizedClientRepository clients;
    private final JwtDecoder decoder;
    private final String allowedUsername;

    SessionIdentity(OAuth2AuthorizedClientRepository clients, JwtDecoder decoder,
            @Value("${cloudbank.bff.allowed-username}") String allowedUsername) {
        this.clients = clients;
        this.decoder = decoder;
        this.allowedUsername = allowedUsername;
    }

    AuthorizedUser require(Authentication authentication, HttpServletRequest request) {
        return require(authentication, request, "cloudbank.read");
    }

    AuthorizedUser requireWrite(Authentication authentication, HttpServletRequest request) {
        return require(authentication, request, "cloudbank.write");
    }

    AuthorizedReviewer requireReviewer(Authentication authentication, HttpServletRequest request) {
        AuthorizedUser user = requireWrite(authentication, request);
        Jwt jwt;
        try {
            jwt = decoder.decode(user.accessToken());
        } catch (RuntimeException expiredOrInvalid) {
            expire(request);
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Session expired");
        }
        String principalId = jwt.getClaimAsString("cb_principal_id");
        if (!jwt.getClaimAsStringList("roles").contains("ROLE_UNDERWRITER")
                || principalId == null || !principalId.matches("[A-Za-z0-9._@:-]{1,80}")) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN);
        }
        return new AuthorizedReviewer(user, principalId);
    }

    record AuthorizedReviewer(AuthorizedUser user, String principalId) { }

    private AuthorizedUser require(Authentication authentication, HttpServletRequest request, String scope) {
        if (!(authentication instanceof OAuth2AuthenticationToken token) || !authentication.isAuthenticated()
                || !BffSecurityConfig.REGISTRATION_ID.equals(token.getAuthorizedClientRegistrationId())) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Sign in required");
        }
        OAuth2AuthorizedClient client = clients.loadAuthorizedClient(BffSecurityConfig.REGISTRATION_ID,
                authentication, request);
        if (client == null || client.getAccessToken() == null) {
            expire(request);
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Session expired");
        }
        Jwt jwt;
        try {
            jwt = decoder.decode(client.getAccessToken().getTokenValue());
        } catch (RuntimeException expiredOrInvalid) {
            expire(request);
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Session expired");
        }
        if (!allowedUsername.equals(jwt.getSubject()) || !"user".equals(jwt.getClaimAsString("token_kind"))
                || jwt.getClaimAsString("cb_principal_id") == null
                || jwt.getClaimAsStringList("roles") == null
                || !jwt.getClaimAsStringList("roles").contains("ROLE_ADMIN")
                || !client.getAccessToken().getScopes().contains("cloudbank.read")
                || !client.getAccessToken().getScopes().contains(scope)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Profile not authorized");
        }
        return new AuthorizedUser(jwt.getSubject(), client.getAccessToken().getTokenValue(),
                client.getAccessToken().getExpiresAt());
    }

    record AuthorizedUser(String username, String accessToken, java.time.Instant tokenExpiresAt) {
        @Override
        public String toString() {
            return "AuthorizedUser[username=" + username + ", accessToken=<redacted>]";
        }
    }

    private void expire(HttpServletRequest request) {
        if (request.getSession(false) != null) {
            request.getSession(false).invalidate();
        }
    }
}
