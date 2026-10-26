// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.aznserver.integration;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.nio.charset.StandardCharsets;
import java.util.Base64;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.resttestclient.autoconfigure.AutoConfigureRestTestClient;
import org.springframework.http.MediaType;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.client.RestTestClient;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@AutoConfigureRestTestClient
@TestPropertySource("classpath:authorization-server-it.properties")
class AuthorizationServerIT extends OracleIntegrationTestSupport {

    @Autowired
    private RestTestClient restTestClient;

    @Autowired
    private ObjectMapper objectMapper;

    @DynamicPropertySource
    static void oracleProperties(DynamicPropertyRegistry registry) {
        configureOracleProperties(registry);
        // Keep the test-only integration client authoritative even when a developer
        // has exported the runtime local-client settings in their shell.
        registry.add("azn.authorization-server.default-client.enabled", () -> "false");
    }

    @Test
    void exposesAuthorizationServerMetadataAndJwks() {
        restTestClient.get()
                .uri("/.well-known/oauth-authorization-server")
                .exchange()
                .expectStatus().isOk()
                .expectBody(String.class)
                .value(body -> assertThat(body).contains(
                        "authorization_endpoint", "token_endpoint", "jwks_uri"));

        restTestClient.get()
                .uri("/oauth2/jwks")
                .exchange()
                .expectStatus().isOk()
                .expectBody(String.class)
                .value(body -> assertThat(body).contains("\"keys\""));
    }

    @Test
    void issuesClientCredentialsAccessToken() {
        MultiValueMap<String, String> body = new LinkedMultiValueMap<>();
        body.add("grant_type", "client_credentials");
        body.add("scope", "user.read");

        restTestClient.post()
                .uri("/oauth2/token")
                .headers(headers -> headers.setBasicAuth("integration-client", "integration-secret"))
                .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                .body(body)
                .exchange()
                .expectStatus().isOk()
                .expectBody(String.class)
                .value(responseBody -> {
                    assertThat(responseBody).contains("access_token", "Bearer");
                    try {
                        JsonNode tokenResponse = objectMapper.readTree(responseBody);
                        String[] jwt = tokenResponse.path("access_token").asText().split("\\.");
                        JsonNode claims = objectMapper.readTree(new String(
                                Base64.getUrlDecoder().decode(jwt[1]), StandardCharsets.UTF_8));
                        assertThat(claims.path("aud").toString()).contains("cloudbank-api");
                        assertThat(claims.path("token_kind").asText()).isEqualTo("service");
                        assertThat(claims.path("roles").isArray()).isTrue();
                    } catch (Exception exception) {
                        throw new AssertionError("Unable to decode issued JWT", exception);
                    }
                });
    }
}
