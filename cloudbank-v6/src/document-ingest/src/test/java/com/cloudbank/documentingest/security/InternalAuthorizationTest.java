// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.documentingest.security;

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

    private final InternalAuthorization authorization =
            new InternalAuthorization(Set.of("cloudbank-service-client"), Set.of("cloudbank-ai-agent-client"));

    @Test
    void allowsAiServiceOnlyToReadReviewInput() {
        var aiToken = authentication("cloudbank-ai-agent-client", "service", "SCOPE_cloudbank.internal");
        assertThat(authorization.isReviewInputReader(aiToken)).isTrue();
        assertThat(authorization.isInternal(aiToken)).isFalse();
        assertThat(authorization.isReviewInputReader(authentication(
                "cloudbank-ai-agent-client", "user", "SCOPE_cloudbank.internal"))).isFalse();
        assertThat(authorization.isReviewInputReader(authentication(
                "cloudbank-ai-agent-client", "service", "SCOPE_cloudbank.read"))).isFalse();
        assertThat(authorization.isReviewInputReader(authentication(
                "unknown-client", "service", "SCOPE_cloudbank.internal"))).isFalse();
    }

    @Test
    void acceptsOnlyAllowListedServiceTokensWithInternalScope() {
        assertThat(authorization.isInternal(authentication(
                "cloudbank-service-client", "service", "SCOPE_cloudbank.internal"))).isTrue();
        assertThat(authorization.isInternal(authentication(
                "unknown-client", "service", "SCOPE_cloudbank.internal"))).isFalse();
        assertThat(authorization.isInternal(authentication(
                "cloudbank-service-client", "user", "SCOPE_cloudbank.internal"))).isFalse();
        assertThat(authorization.isInternal(authentication(
                "cloudbank-service-client", "service", "SCOPE_cloudbank.write"))).isFalse();
    }

    private static JwtAuthenticationToken authentication(String clientId, String tokenKind, String authority) {
        Jwt jwt = new Jwt("token", Instant.now(), Instant.now().plusSeconds(60),
                Map.of("alg", "RS256"), Map.of(
                        "iss", "https://auth.cloudbank.test",
                        "sub", clientId,
                        "client_id", clientId,
                        "token_kind", tokenKind,
                        "roles", List.of()));
        return new JwtAuthenticationToken(jwt, List.of(new SimpleGrantedAuthority(authority)));
    }
}
