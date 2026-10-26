// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.geographicrisk.security;

import jakarta.json.Json;
import org.eclipse.microprofile.jwt.JsonWebToken;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class InternalAuthorizationTest {

    private final InternalAuthorization authorization = new InternalAuthorization("cloudbank-service-client");

    @Test
    void acceptsAllowListedInternalServiceToken() {
        assertThat(authorization.isInternal(token("service", "cloudbank-service-client", "cloudbank.internal")))
                .isTrue();
    }

    @Test
    void acceptsHelidonJsonClaimValues() {
        JsonWebToken token = mock(JsonWebToken.class);
        when(token.getClaim("token_kind")).thenReturn(Json.createValue("service"));
        when(token.getClaim("client_id")).thenReturn(Json.createValue("cloudbank-service-client"));
        when(token.getClaim("scope")).thenReturn(Json.createArrayBuilder().add("cloudbank.internal").build());

        assertThat(authorization.isInternal(token)).isTrue();
    }

    @Test
    void rejectsUserTokensWrongClientsAndMissingScope() {
        assertThat(authorization.isInternal(token("user", "cloudbank-service-client", "cloudbank.internal")))
                .isFalse();
        assertThat(authorization.isInternal(token("service", "cloudbank-client", "cloudbank.internal")))
                .isFalse();
        assertThat(authorization.isInternal(token("service", "cloudbank-service-client", "cloudbank.read")))
                .isFalse();
    }

    private static JsonWebToken token(String tokenKind, String clientId, String scope) {
        JsonWebToken token = mock(JsonWebToken.class);
        when(token.getClaim("token_kind")).thenReturn(tokenKind);
        when(token.getClaim("client_id")).thenReturn(clientId);
        when(token.getClaim("scope")).thenReturn(scope);
        return token;
    }
}
