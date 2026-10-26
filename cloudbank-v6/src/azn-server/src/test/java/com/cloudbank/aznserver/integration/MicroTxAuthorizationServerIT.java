// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.aznserver.integration;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.resttestclient.autoconfigure.AutoConfigureRestTestClient;
import org.springframework.http.MediaType;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.client.RestTestClient;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@AutoConfigureRestTestClient
class MicroTxAuthorizationServerIT extends OracleIntegrationTestSupport {

    private static final String MICROTX_SECRET = "MicroTxIntegrationSecret123!";

    @Autowired
    private RestTestClient restTestClient;

    @Autowired
    private ObjectMapper objectMapper;

    @DynamicPropertySource
    static void oracleProperties(DynamicPropertyRegistry registry) {
        configureOracleProperties(registry);
        registry.add("azn.authorization-server.default-client.enabled", () -> "true");
        registry.add("azn.authorization-server.microtx-client.secret", () -> MICROTX_SECRET);
    }

    @Test
    void issuesMicrotxClientCredentialsTokenWithDedicatedClaims() {
        MultiValueMap<String, String> body = new LinkedMultiValueMap<>();
        body.add("grant_type", "client_credentials");
        body.add("scope", "microtx.workflow");

        restTestClient.post()
                .uri("/oauth2/token")
                .headers(headers -> headers.setBasicAuth("microtx-workflow-client", MICROTX_SECRET))
                .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                .body(body)
                .exchange()
                .expectStatus().isOk()
                .expectBody(String.class)
                .value(responseBody -> {
                    try {
                        JsonNode tokenResponse = objectMapper.readTree(responseBody);
                        String[] jwt = tokenResponse.path("access_token").asText().split("\\.");
                        JsonNode claims = objectMapper.readTree(new String(
                                Base64.getUrlDecoder().decode(jwt[1]), StandardCharsets.UTF_8));

                        assertThat(claims.path("iss").asText()).isEqualTo("http://127.0.0.1:8080");
                        assertThat(claims.path("aud").toString()).contains("microtx-workflow");
                        assertThat(objectMapper.convertValue(
                                claims.path("scope"), new TypeReference<List<String>>() { }))
                                .containsExactly("microtx.workflow");
                        assertThat(claims.path("client_id").asText()).isEqualTo("microtx-workflow-client");
                        assertThat(claims.path("token_kind").asText()).isEqualTo("service");
                        assertThat(objectMapper.convertValue(
                                claims.path("roles"), new TypeReference<List<String>>() { }))
                                .containsExactlyInAnyOrder(
                                        "microtx-conductor-user", "microtx-conductor-worker");
                    } catch (Exception exception) {
                        throw new AssertionError("Unable to decode issued MicroTx JWT", exception);
                    }
                });
    }
}
