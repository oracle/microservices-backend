// Copyright (c) 2026, Oracle and/or its affiliates.

package com.example.common.security;

import java.time.Instant;

import org.springframework.http.MediaType;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.StringUtils;
import org.springframework.web.client.RestClient;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;

public class CloudBankServiceTokenProvider {

    private final CloudBankServiceTokenProperties properties;
    private final RestClient tokenClient;
    private final ObjectMapper objectMapper;
    private volatile AccessToken currentToken;

    /**
     * Creates a client-credentials service token provider.
     *
     * @param properties service token configuration.
     * @param restClientBuilder builder used for token endpoint calls.
     * @param objectMapper JSON parser for token responses.
     */
    public CloudBankServiceTokenProvider(CloudBankServiceTokenProperties properties,
            RestClient.Builder restClientBuilder, ObjectMapper objectMapper) {
        this.properties = properties;
        this.tokenClient = restClientBuilder.build();
        this.objectMapper = objectMapper;
    }

    /**
     * Returns a bearer authorization header value.
     *
     * @return Authorization header value.
     */
    public String getAuthorizationHeader() {
        return "Bearer " + getAccessToken();
    }

    private String getAccessToken() {
        AccessToken token = currentToken;
        if (token != null && token.isUsable()) {
            return token.value();
        }

        synchronized (this) {
            token = currentToken;
            if (token == null || !token.isUsable()) {
                currentToken = requestToken();
            }
            return currentToken.value();
        }
    }

    private AccessToken requestToken() {
        validateConfiguration();

        LinkedMultiValueMap<String, String> form = new LinkedMultiValueMap<>();
        form.add("grant_type", "client_credentials");
        if (StringUtils.hasText(properties.getScope())) {
            form.add("scope", properties.getScope());
        }

        String responseBody = tokenClient.post()
                .uri(properties.getTokenUri())
                .headers(headers -> headers.setBasicAuth(properties.getClientId(), properties.getClientSecret()))
                .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                .body(form)
                .retrieve()
                .body(String.class);

        try {
            JsonNode tokenResponse = objectMapper.readTree(responseBody);
            String accessToken = tokenResponse.required("access_token").asText();
            long expiresIn = tokenResponse.path("expires_in").asLong(300);
            long usableSeconds = Math.max(1, expiresIn - properties.getRefreshSkewSeconds());
            return new AccessToken(accessToken, Instant.now().plusSeconds(usableSeconds));
        } catch (Exception exception) {
            throw new IllegalStateException("Could not parse authorization server token response", exception);
        }
    }

    private void validateConfiguration() {
        if (!StringUtils.hasText(properties.getTokenUri())) {
            throw new IllegalStateException("cloudbank.security.service-token.token-uri must be set");
        }
        if (!StringUtils.hasText(properties.getClientId())) {
            throw new IllegalStateException("cloudbank.security.service-token.client-id must be set");
        }
        if (!StringUtils.hasText(properties.getClientSecret())) {
            throw new IllegalStateException("cloudbank.security.service-token.client-secret must be set");
        }
    }

    private record AccessToken(String value, Instant usableUntil) {
        boolean isUsable() {
            return Instant.now().isBefore(usableUntil);
        }
    }
}
