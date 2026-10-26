// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.

package com.cloudbank.gatewaybff;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.oauth2.client.OAuth2AuthorizedClient;
import org.springframework.security.oauth2.client.authentication.OAuth2AuthenticationToken;
import org.springframework.security.oauth2.client.registration.ClientRegistration;
import org.springframework.security.oauth2.client.web.OAuth2AuthorizedClientRepository;
import org.springframework.security.oauth2.core.OAuth2AccessToken;
import org.springframework.security.oauth2.core.user.DefaultOAuth2User;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.web.server.ResponseStatusException;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class SessionIdentityTest {
    @Test
    void humanCompletionRequiresExplicitUnderwriterRoleAndUsesTheSignedPrincipal() {
        OAuth2AuthorizedClientRepository clients = mock(OAuth2AuthorizedClientRepository.class);
        JwtDecoder decoder = mock(JwtDecoder.class);
        SessionIdentity identity = new SessionIdentity(clients, decoder, "obaas-admin");
        var authentication = authentication();
        var request = new MockHttpServletRequest();
        when(clients.loadAuthorizedClient(eq("cloudbank-bff"), eq(authentication), eq(request)))
                .thenReturn(authorizedClient(Set.of("cloudbank.read", "cloudbank.write")));
        when(decoder.decode("signed-access-token")).thenReturn(token("obaas-admin", List.of("ROLE_ADMIN")));
        assertThatThrownBy(() -> identity.requireReviewer(authentication, request))
                .isInstanceOfSatisfying(ResponseStatusException.class,
                        error -> assertThat(error.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN));
        when(decoder.decode("signed-access-token"))
                .thenReturn(token("obaas-admin", List.of("ROLE_ADMIN", "ROLE_UNDERWRITER")));
        assertThat(identity.requireReviewer(authentication, request).principalId()).isEqualTo("demo-admin");
    }

    @Test
    void admitsOnlyTheConfiguredAdminUserWithReadScope() {
        OAuth2AuthorizedClientRepository clients = mock(OAuth2AuthorizedClientRepository.class);
        JwtDecoder decoder = mock(JwtDecoder.class);
        SessionIdentity identity = new SessionIdentity(clients, decoder, "obaas-admin");
        OAuth2AuthenticationToken authentication = authentication();
        MockHttpServletRequest request = new MockHttpServletRequest();
        OAuth2AuthorizedClient client = authorizedClient(Set.of("openid", "cloudbank.read"));
        when(clients.loadAuthorizedClient(eq("cloudbank-bff"), eq(authentication), eq(request))).thenReturn(client);
        when(decoder.decode("signed-access-token")).thenReturn(token("obaas-admin", List.of("ROLE_ADMIN")));

        assertThat(identity.require(authentication, request).username()).isEqualTo("obaas-admin");
        assertThat(identity.require(authentication, request).accessToken()).isEqualTo("signed-access-token");
    }

    @Test
    void readOnlySessionCannotCreateApplications() {
        OAuth2AuthorizedClientRepository clients = mock(OAuth2AuthorizedClientRepository.class);
        JwtDecoder decoder = mock(JwtDecoder.class);
        SessionIdentity identity = new SessionIdentity(clients, decoder, "obaas-admin");
        OAuth2AuthenticationToken authentication = authentication();
        MockHttpServletRequest request = new MockHttpServletRequest();
        when(clients.loadAuthorizedClient(eq("cloudbank-bff"), eq(authentication), eq(request)))
                .thenReturn(authorizedClient(Set.of("cloudbank.read")));
        when(decoder.decode("signed-access-token")).thenReturn(token("obaas-admin", List.of("ROLE_ADMIN")));
        assertThatThrownBy(() -> identity.requireWrite(authentication, request))
                .isInstanceOfSatisfying(ResponseStatusException.class,
                        error -> assertThat(error.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN));
    }

    @Test
    void admitsWriteSessionForCreation() {
        OAuth2AuthorizedClientRepository clients = mock(OAuth2AuthorizedClientRepository.class);
        JwtDecoder decoder = mock(JwtDecoder.class);
        SessionIdentity identity = new SessionIdentity(clients, decoder, "obaas-admin");
        OAuth2AuthenticationToken authentication = authentication();
        MockHttpServletRequest request = new MockHttpServletRequest();
        when(clients.loadAuthorizedClient(eq("cloudbank-bff"), eq(authentication), eq(request)))
                .thenReturn(authorizedClient(Set.of("cloudbank.read", "cloudbank.write")));
        when(decoder.decode("signed-access-token")).thenReturn(token("obaas-admin", List.of("ROLE_ADMIN")));
        assertThat(identity.requireWrite(authentication, request).username()).isEqualTo("obaas-admin");
    }

    @Test
    void rejectsDifferentUserEvenWithAdminRole() {
        OAuth2AuthorizedClientRepository clients = mock(OAuth2AuthorizedClientRepository.class);
        JwtDecoder decoder = mock(JwtDecoder.class);
        SessionIdentity identity = new SessionIdentity(clients, decoder, "obaas-admin");
        OAuth2AuthenticationToken authentication = authentication();
        MockHttpServletRequest request = new MockHttpServletRequest();
        when(clients.loadAuthorizedClient(eq("cloudbank-bff"), eq(authentication), eq(request)))
                .thenReturn(authorizedClient(Set.of("cloudbank.read")));
        when(decoder.decode("signed-access-token")).thenReturn(token("another-admin", List.of("ROLE_ADMIN")));

        assertThatThrownBy(() -> identity.require(authentication, request))
                .isInstanceOfSatisfying(ResponseStatusException.class,
                        error -> assertThat(error.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN));
    }

    private OAuth2AuthenticationToken authentication() {
        var authority = new SimpleGrantedAuthority("OIDC_USER");
        var user = new DefaultOAuth2User(List.of(authority), Map.of("sub", "obaas-admin"), "sub");
        return new OAuth2AuthenticationToken(user, List.of(authority), "cloudbank-bff");
    }

    private OAuth2AuthorizedClient authorizedClient(Set<String> scopes) {
        ClientRegistration registration = mock(ClientRegistration.class);
        OAuth2AccessToken token = new OAuth2AccessToken(OAuth2AccessToken.TokenType.BEARER,
                "signed-access-token", Instant.now().minusSeconds(5), Instant.now().plusSeconds(300), scopes);
        return new OAuth2AuthorizedClient(registration, "obaas-admin", token);
    }

    private Jwt token(String subject, List<String> roles) {
        return Jwt.withTokenValue("signed-access-token")
                .header("alg", "RS256").subject(subject)
                .issuedAt(Instant.now().minusSeconds(5)).expiresAt(Instant.now().plusSeconds(300))
                .claim("token_kind", "user").claim("cb_principal_id", "demo-admin")
                .claim("roles", roles).build();
    }
}
