// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.policyretrieval.security;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Instant;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.security.authentication.AbstractAuthenticationToken;
import org.springframework.security.oauth2.jwt.Jwt;

class SecurityConfigTest {

    @Test
    void mapsCloudBankRolesAndScopesToAuthorities() {
        Jwt jwt = Jwt.withTokenValue("token")
                .header("alg", "none")
                .issuedAt(Instant.now())
                .expiresAt(Instant.now().plusSeconds(60))
                .claim("scope", "cloudbank.read")
                .claim("roles", List.of("ROLE_LOAN_OFFICER", "ROLE_UNDERWRITER", "ROLE_USER"))
                .build();

        AbstractAuthenticationToken authentication = new SecurityConfig()
                .policyRetrievalJwtAuthenticationConverter()
                .convert(jwt);

        assertThat(authentication.getAuthorities())
                .extracting(authority -> authority.getAuthority())
                .contains("SCOPE_cloudbank.read", "ROLE_LOAN_OFFICER", "ROLE_UNDERWRITER", "ROLE_USER");
    }
}
