// Copyright (c) 2026, Oracle and/or its affiliates.
//
// Licensed under the Universal Permissive License v 1.0 as shown at
// https://oss.oracle.com/licenses/upl/.
//

package com.cloudbank.documentreview.client;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;
import java.io.IOException;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.oauth2.client.OAuth2AuthorizedClient;
import org.springframework.security.oauth2.client.OAuth2AuthorizedClientManager;
import org.springframework.security.oauth2.client.OAuth2AuthorizedClientService;
import org.springframework.security.oauth2.client.registration.ClientRegistration;
import org.springframework.security.oauth2.core.AuthorizationGrantType;
import org.springframework.security.oauth2.core.OAuth2AccessToken;
import org.springframework.web.client.RestClient;

@ExtendWith(MockitoExtension.class)
class DocumentReviewClientsTest {
    @Mock
    private OAuth2AuthorizedClientManager manager;
    @Mock
    private OAuth2AuthorizedClientService authorizedClients;

    private HttpServer server;
    private String baseUrl;
    private final AtomicReference<String> authorization = new AtomicReference<>();
    private final AtomicReference<String> requestBody = new AtomicReference<>();

    @BeforeEach
    void startServer() throws IOException {
        server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/internal/api/v1/applications/APP-ONE/extractions/review-input",
                exchange -> response(exchange, 200, "{\"applicationId\":\"APP-ONE\",\"documents\":[]}"));
        server.createContext("/internal/api/v1/loan-applications/APP-ONE/documents",
                exchange -> response(exchange, 200, "{\"applicationId\":\"APP-ONE\",\"documents\":[]}"));
        server.createContext("/internal/api/v1/loan-applications/APP-ONE/documents/DOC-ONE/status-transitions",
                exchange -> {
                    authorization.set(exchange.getRequestHeaders().getFirst("Authorization"));
                    requestBody.set(new String(exchange.getRequestBody().readAllBytes(), StandardCharsets.UTF_8));
                    response(exchange, 204, "");
                });
        server.start();
        baseUrl = "http://127.0.0.1:" + server.getAddress().getPort();

        ClientRegistration registration = ClientRegistration.withRegistrationId("cloudbank-service")
                .clientId("cloudbank-document-review-client")
                .authorizationGrantType(AuthorizationGrantType.CLIENT_CREDENTIALS)
                .tokenUri("https://auth.cloudbank.test/oauth2/token").build();
        OAuth2AccessToken token = new OAuth2AccessToken(OAuth2AccessToken.TokenType.BEARER, "service-token",
                Instant.now(), Instant.now().plusSeconds(60));
        when(manager.authorize(any()))
                .thenReturn(new OAuth2AuthorizedClient(registration, "document-review-service", token));
    }

    @AfterEach
    void stopServer() {
        server.stop(0);
    }

    @Test
    void fetchesOnlyTheBoundedReviewInputWithAServiceToken() {
        DocumentIngestClient client = new DocumentIngestClient(RestClient.builder(), manager, authorizedClients,
                baseUrl);

        assertThat(client.reviewInput("APP-ONE").documents()).isEmpty();
    }

    @Test
    void postsAStatusTransitionWithTheDeterministicEventAndTrace() {
        LoanApplicationClient client = new LoanApplicationClient(RestClient.builder(), manager, authorizedClients,
                baseUrl);

        assertThat(client.manifest("APP-ONE").documents()).isEmpty();
        client.transitionStatus("APP-ONE", "DOC-ONE", "EXTRACTED", "NEEDS_REVIEW", "DREVSTAT-hash", "trace-001");

        assertThat(authorization.get()).isEqualTo("Bearer service-token");
        assertThat(requestBody.get()).contains("DREVSTAT-hash", "EXTRACTED", "NEEDS_REVIEW", "trace-001",
                "DOCUMENT_REVIEW_NEEDS_REVIEW");
    }

    private static void response(HttpExchange exchange, int status, String body) throws IOException {
        byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
        exchange.getResponseHeaders().set("Content-Type", "application/json");
        exchange.sendResponseHeaders(status, bytes.length);
        exchange.getResponseBody().write(bytes);
        exchange.close();
    }
}
