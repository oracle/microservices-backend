// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.

package com.cloudbank.decision.security;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.testng.annotations.Test;

public class InternalAuthorizationTest {
    private final InternalAuthorization authorization = new InternalAuthorization(Set.of("cloudbank-service-client"));

    @Test
    public void acceptsOnlyAllowListedServiceClientWithInternalScope() {
        assertThat(authorization.isInternal(token("cloudbank-service-client", "service",
                List.of(new SimpleGrantedAuthority("SCOPE_cloudbank.internal"))))).isTrue();
        assertThat(authorization.isInternal(token("other-client", "service",
                List.of(new SimpleGrantedAuthority("SCOPE_cloudbank.internal"))))).isFalse();
        assertThat(authorization.isInternal(token("cloudbank-service-client", "user",
                List.of(new SimpleGrantedAuthority("SCOPE_cloudbank.internal"))))).isFalse();
        assertThat(authorization.isInternal(token("cloudbank-service-client", "service", List.of()))).isFalse();
    }

    private JwtAuthenticationToken token(String clientId, String tokenKind,
            List<SimpleGrantedAuthority> authorities) {
        Jwt jwt = new Jwt("token", Instant.now(), Instant.now().plusSeconds(60), Map.of("alg", "none"),
                Map.of("sub", clientId, "client_id", clientId, "token_kind", tokenKind));
        return new JwtAuthenticationToken(jwt, authorities);
    }
}
