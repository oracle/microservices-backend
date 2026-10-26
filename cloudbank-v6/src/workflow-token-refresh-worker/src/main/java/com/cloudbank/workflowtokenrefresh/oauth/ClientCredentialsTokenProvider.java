// Copyright (c) 2026, Oracle and/or its affiliates.
//
// Licensed under the Universal Permissive License v 1.0 as shown at
// https://oss.oracle.com/licenses/upl/.

package com.cloudbank.workflowtokenrefresh.oauth;

import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.time.Instant;
import java.util.Base64;
import java.util.Objects;
import org.springframework.http.MediaType;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.StringUtils;
import org.springframework.web.client.RestClient;
import tools.jackson.databind.JsonNode;

public final class ClientCredentialsTokenProvider implements FreshTokenProvider {
    private static final long DEFAULT_EXPIRES_IN_SECONDS = 300;
    private static final long REFRESH_SKEW_SECONDS = 30;

    private final RestClient restClient;
    private final Clock clock;
    private final String tokenUri;
    private final String authorization;
    private final String scope;
    private volatile AccessToken cached;

    public ClientCredentialsTokenProvider(RestClient restClient, Clock clock, String tokenUri, String clientId,
            String clientSecret, String scope) {
        this.restClient = Objects.requireNonNull(restClient, "restClient");
        this.clock = Objects.requireNonNull(clock, "clock");
        this.tokenUri = tokenUri;
        this.authorization = "Basic " + Base64.getEncoder()
                .encodeToString((clientId + ":" + clientSecret).getBytes(StandardCharsets.UTF_8));
        this.scope = scope;
    }

    @Override
    public synchronized AccessToken accessToken() {
        Instant now = clock.instant();
        if (cached != null && now.isBefore(cached.expiresAt().minusSeconds(REFRESH_SKEW_SECONDS))) {
            return cached;
        }

        LinkedMultiValueMap<String, String> form = new LinkedMultiValueMap<>();
        form.add("grant_type", "client_credentials");
        form.add("scope", scope);
        JsonNode response = restClient.post().uri(tokenUri)
                .header("Authorization", authorization)
                .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                .body(form)
                .retrieve()
                .body(JsonNode.class);
        String value = response == null ? null : response.path("access_token").asText(null);
        if (!StringUtils.hasText(value)) {
            throw new TokenAcquisitionException("Authorization server response did not contain an access token");
        }
        long expiresIn = response.path("expires_in").asLong(DEFAULT_EXPIRES_IN_SECONDS);
        if (expiresIn <= 0) {
            expiresIn = DEFAULT_EXPIRES_IN_SECONDS;
        }
        cached = new AccessToken(value, now.plusSeconds(expiresIn));
        return cached;
    }

    @Override
    public synchronized void invalidate() {
        cached = null;
    }

    public static final class TokenAcquisitionException extends RuntimeException {
        public TokenAcquisitionException(String message) {
            super(message);
        }
    }
}
