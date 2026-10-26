// Copyright (c) 2026, Oracle and/or its affiliates.
//
// Licensed under the Universal Permissive License v 1.0 as shown at
// https://oss.oracle.com/licenses/upl/.
//

package com.cloudbank.documentreview.security;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.junit.jupiter.api.Test;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;

class InternalAuthorizationTest {
    private final InternalAuthorization authorization = new InternalAuthorization(
            Set.of("cloudbank-service-client", "microtx-workflow-client"));

    @Test
    void acceptsOnlyAllowListedServiceTokensWithTheInternalScope() {
        assertThat(authorization
                .isInternal(authentication("cloudbank-service-client", "service", "SCOPE_cloudbank.internal")))
                        .isTrue();
        assertThat(authorization
                .isInternal(authentication("microtx-workflow-client", "service", "SCOPE_cloudbank.internal"))).isTrue();
        assertThat(authorization.isInternal(authentication("unknown-client", "service", "SCOPE_cloudbank.internal")))
                .isFalse();
        assertThat(authorization
                .isInternal(authentication("cloudbank-service-client", "user", "SCOPE_cloudbank.internal"))).isFalse();
        assertThat(
                authorization.isInternal(authentication("cloudbank-service-client", "service", "SCOPE_cloudbank.read")))
                        .isFalse();
    }

    @Test
    void rejectsMissingSecurityClaims() {
        Jwt jwt = new Jwt("token", Instant.now(), Instant.now().plusSeconds(60), Map.of("alg", "RS256"),
                Map.of("iss", "https://auth.cloudbank.test"));

        assertThat(authorization.isInternal(
                new JwtAuthenticationToken(jwt, List.of(new SimpleGrantedAuthority("SCOPE_cloudbank.internal")))))
                        .isFalse();
    }

    private static JwtAuthenticationToken authentication(String clientId, String tokenKind, String authority) {
        Jwt jwt = new Jwt("token", Instant.now(), Instant.now().plusSeconds(60), Map.of("alg", "RS256"),
                Map.of("iss", "https://auth.cloudbank.test", "sub", clientId, "client_id", clientId, "token_kind",
                        tokenKind, "roles", List.of()));
        return new JwtAuthenticationToken(jwt, List.of(new SimpleGrantedAuthority(authority)));
    }
}
