// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.
package com.cloudbank.gatewaybff;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.security.oauth2.client.AuthorizedClientServiceOAuth2AuthorizedClientManager;
import org.springframework.security.oauth2.client.InMemoryOAuth2AuthorizedClientService;
import org.springframework.security.oauth2.client.OAuth2AuthorizeRequest;
import org.springframework.security.oauth2.client.OAuth2AuthorizedClientProviderBuilder;
import org.springframework.security.oauth2.client.registration.ClientRegistration;
import org.springframework.security.oauth2.client.registration.InMemoryClientRegistrationRepository;
import org.springframework.security.oauth2.core.AuthorizationGrantType;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.server.ResponseStatusException;
import tools.jackson.databind.ObjectMapper;

/** Dedicated machine identity with read scope only. Called after the loan user-access check. */
@Component
class WorkspaceOwnerClient {
    private final AuthorizedClientServiceOAuth2AuthorizedClientManager authorization;
    private final RestClient ai;
    private final RestClient decision;
    private final RestClient geographic;
    private final ObjectMapper json;

    WorkspaceOwnerClient(RestClient.Builder builder, ObjectMapper json,
            @Value("${BFF_TOKEN_URI}") String tokenUri,
            @Value("${BFF_OAUTH_CLIENT_ID:cloudbank-bff-client}") String clientId,
            @Value("${BFF_OAUTH_CLIENT_SECRET}") String secret,
            @Value("${cloudbank.bff.ai-base-url:http://ai-agent-service:8080}") String aiUrl,
            @Value("${cloudbank.bff.decision-base-url:http://decision-service:8080}") String decisionUrl,
            @Value("${cloudbank.bff.geographic-base-url:http://geographic-risk-service:8080}") String geographicUrl) {
        var registration = ClientRegistration.withRegistrationId("workspace-read")
                .clientId(clientId + "-read").clientSecret(secret).tokenUri(tokenUri)
                .authorizationGrantType(AuthorizationGrantType.CLIENT_CREDENTIALS)
                .scope("cloudbank.workspace.read").build();
        var registrations = new InMemoryClientRegistrationRepository(registration);
        authorization = new AuthorizedClientServiceOAuth2AuthorizedClientManager(registrations,
                new InMemoryOAuth2AuthorizedClientService(registrations));
        authorization.setAuthorizedClientProvider(OAuth2AuthorizedClientProviderBuilder.builder().clientCredentials().build());
        ai = builder.clone().baseUrl(aiUrl).build();
        decision = builder.clone().baseUrl(decisionUrl).build();
        geographic = builder.clone().baseUrl(geographicUrl).build();
        this.json = json;
    }

    <T> T read(String owner, String path, String applicationId, String workflowId, String id,
            String correlation, Class<T> type) {
        var client = switch (owner) { case "ai" -> ai; case "decision" -> decision; case "geographic" -> geographic;
            default -> throw new IllegalArgumentException("Unknown workspace owner"); };
        return client.get().uri(uri -> uri.path("/internal/api/v1/workspace/applications/{applicationId}" + path)
                        .queryParam("workflowId", workflowId).build(path.contains("{id}") ? new Object[] { applicationId, id } : new Object[] { applicationId }))
                .headers(headers -> headers.setBearerAuth(accessToken()))
                .header("X-Correlation-ID", correlation).exchange((request, response) -> {
                    if (response.getStatusCode().value() != 200) {
                        throw new ResponseStatusException(response.getStatusCode());
                    }
                    byte[] bytes = response.getBody().readNBytes(256 * 1024 + 1);
                    if (bytes.length > 256 * 1024) throw new ResponseStatusException(HttpStatus.BAD_GATEWAY);
                    return json.readValue(bytes, type);
                });
    }

    private synchronized String accessToken() {
        try {
            var client = authorization.authorize(OAuth2AuthorizeRequest.withClientRegistrationId("workspace-read")
                    .principal("gateway-bff-service").build());
            if (client != null) return client.getAccessToken().getTokenValue();
        } catch (org.springframework.security.oauth2.core.OAuth2AuthorizationException unavailable) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE);
        }
        throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE);
    }
}
