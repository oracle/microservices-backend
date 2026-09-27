// Copyright (c) 2026, Oracle and/or its affiliates.

package oracle.obaas.aznserver.integration;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.resttestclient.TestRestTemplate;
import org.springframework.boot.resttestclient.autoconfigure.AutoConfigureTestRestTemplate;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.context.TestPropertySource;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@AutoConfigureTestRestTemplate
@TestPropertySource("classpath:authorization-server-it.properties")
class AuthorizationServerIT extends OracleIntegrationTestSupport {

    @LocalServerPort
    private int port;

    @Autowired
    private TestRestTemplate restTemplate;

    @DynamicPropertySource
    static void oracleProperties(DynamicPropertyRegistry registry) {
        configureOracleProperties(registry);
    }

    @Test
    void exposesAuthorizationServerMetadataAndJwks() {
        ResponseEntity<String> metadata = restTemplate.getForEntity(
                url("/.well-known/oauth-authorization-server"), String.class);
        ResponseEntity<String> jwks = restTemplate.getForEntity(url("/oauth2/jwks"), String.class);

        assertThat(metadata.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(metadata.getBody()).contains("authorization_endpoint", "token_endpoint", "jwks_uri");
        assertThat(jwks.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(jwks.getBody()).contains("\"keys\"");
    }

    @Test
    void issuesClientCredentialsAccessToken() {
        HttpHeaders headers = new HttpHeaders();
        headers.setBasicAuth("integration-client", "integration-secret");
        headers.setContentType(MediaType.APPLICATION_FORM_URLENCODED);
        MultiValueMap<String, String> body = new LinkedMultiValueMap<>();
        body.add("grant_type", "client_credentials");
        body.add("scope", "user.read");

        ResponseEntity<String> response = restTemplate.postForEntity(url("/oauth2/token"),
                new HttpEntity<>(body, headers), String.class);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).contains("access_token", "Bearer");
    }

    private String url(String path) {
        return "http://localhost:" + port + path;
    }
}
