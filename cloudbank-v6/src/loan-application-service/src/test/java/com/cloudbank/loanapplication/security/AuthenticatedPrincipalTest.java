// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.loanapplication.security;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.security.oauth2.jwt.Jwt;

class AuthenticatedPrincipalTest {

    @Test
    void readsOnlySignedIdentityAndRoleClaims() {
        Jwt jwt = new Jwt("token", Instant.now(), Instant.now().plusSeconds(60),
                Map.of("alg", "RS256"), Map.of(
                        "iss", "https://auth.cloudbank.test",
                        "sub", "applicant-1",
                        "cb_principal_id", "principal-1",
                        "token_kind", "user",
                        "roles", List.of("ROLE_APPLICANT")));

        AuthenticatedPrincipal principal = AuthenticatedPrincipal.from(jwt);

        assertThat(principal.principalId()).isEqualTo("principal-1");
        assertThat(principal.issuer()).isEqualTo("https://auth.cloudbank.test");
        assertThat(principal.hasRole("ROLE_APPLICANT")).isTrue();
    }

    @Test
    void derivesServicePrincipalFromAuthorizedClientIdentity() {
        Jwt jwt = new Jwt("token", Instant.now(), Instant.now().plusSeconds(60),
                Map.of("alg", "RS256"), Map.of(
                        "iss", "https://auth.cloudbank.test",
                        "sub", "cloudbank-service-client",
                        "client_id", "cloudbank-service-client",
                        "token_kind", "service",
                        "roles", List.of()));

        assertThat(AuthenticatedPrincipal.from(jwt).principalId())
                .isEqualTo("svc-cloudbank-service-client");
    }
}
