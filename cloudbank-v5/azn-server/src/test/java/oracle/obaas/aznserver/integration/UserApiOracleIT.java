// Copyright (c) 2026, Oracle and/or its affiliates.

package oracle.obaas.aznserver.integration;

import java.util.Map;

import oracle.obaas.aznserver.repository.UserRepository;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.resttestclient.TestRestTemplate;
import org.springframework.boot.resttestclient.autoconfigure.AutoConfigureTestRestTemplate;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.context.TestPropertySource;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@AutoConfigureTestRestTemplate
@TestPropertySource(properties = "azn.authorization-server.default-client.enabled=true")
class UserApiOracleIT extends OracleIntegrationTestSupport {

    @LocalServerPort
    private int port;

    @Autowired
    private TestRestTemplate restTemplate;

    @Autowired
    private UserRepository userRepository;

    @Autowired
    private PasswordEncoder passwordEncoder;

    @DynamicPropertySource
    static void oracleProperties(DynamicPropertyRegistry registry) {
        configureOracleProperties(registry);
    }

    @Test
    void adminCanCreateAndFindUserWithoutLeakingSecrets() {
        TestRestTemplate admin = restTemplate.withBasicAuth("obaas-admin", BOOTSTRAP_PASSWORD);
        Map<String, String> request = Map.of(
                "username", "api-user",
                "password", "StrongPass123!",
                "roles", "ROLE_USER",
                "email", "api-user@example.com");

        ResponseEntity<String> createResponse = admin.postForEntity(url("/user/api/v1/createUser"),
                request, String.class);
        ResponseEntity<String> findResponse = admin.getForEntity(url("/user/api/v1/findUser?username=api-user"),
                String.class);

        assertThat(createResponse.getStatusCode()).isEqualTo(HttpStatus.CREATED);
        assertThat(createResponse.getBody()).contains("api-user").doesNotContain("StrongPass123!");
        assertThat(findResponse.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(findResponse.getBody())
                .contains("api-user")
                .doesNotContain("StrongPass123!")
                .doesNotContain("otp");
        assertThat(userRepository.findByUsername("api-user"))
                .hasValueSatisfying(user -> {
                    assertThat(user.getPassword()).isNotEqualTo("StrongPass123!").startsWith("$2");
                    assertThat(passwordEncoder.matches("StrongPass123!", user.getPassword())).isTrue();
                });
    }

    @Test
    void forgotFlowDoesNotDiscloseOtpAndAllowsPasswordReset() {
        TestRestTemplate admin = restTemplate.withBasicAuth("obaas-admin", BOOTSTRAP_PASSWORD);
        admin.postForEntity(url("/user/api/v1/createUser"), Map.of(
                "username", "reset-user",
                "password", "StrongPass123!",
                "roles", "ROLE_USER",
                "email", "reset-user@example.com"), String.class);

        ResponseEntity<String> anonymousCreateOtpResponse = restTemplate.postForEntity(
                url("/user/api/v1/forgot"),
                Map.of(
                        "username", "reset-user",
                        "otp", "123456"),
                String.class);
        ResponseEntity<String> createOtpResponse = admin.postForEntity(url("/user/api/v1/forgot"), Map.of(
                "username", "reset-user",
                "otp", "123456"), String.class);
        ResponseEntity<String> forgotResponse = admin.getForEntity(
                url("/user/api/v1/forgot?username=reset-user"), String.class);
        ResponseEntity<String> resetResponse = admin.exchange(url("/user/api/v1/forgot"),
                HttpMethod.PUT,
                new HttpEntity<>(Map.of(
                        "username", "reset-user",
                        "otp", "123456",
                        "password", "ResetPass123!")),
                String.class);
        ResponseEntity<String> connectResponse = restTemplate.withBasicAuth("reset-user", "ResetPass123!")
                .getForEntity(url("/user/api/v1/connect"), String.class);

        assertThat(anonymousCreateOtpResponse.getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
        assertThat(createOtpResponse.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(forgotResponse.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(forgotResponse.getBody())
                .contains("reset-user")
                .contains("reset-user@example.com")
                .doesNotContain("123456")
                .doesNotContain("password");
        assertThat(resetResponse.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(connectResponse.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(userRepository.findByUsername("reset-user"))
                .hasValueSatisfying(user -> {
                    assertThat(user.getPassword())
                            .isNotEqualTo("StrongPass123!")
                            .isNotEqualTo("ResetPass123!")
                            .startsWith("$2");
                    assertThat(passwordEncoder.matches("ResetPass123!", user.getPassword())).isTrue();
                });
    }

    @Test
    void userCreationRejectsUnauthorizedWeakPasswordAndDuplicateRequests() {
        Map<String, String> weakPasswordRequest = Map.of(
                "username", "weak-password-user",
                "password", "weak",
                "roles", "ROLE_USER");
        Map<String, String> duplicateRequest = Map.of(
                "username", "duplicate-api-user",
                "password", "StrongPass123!",
                "roles", "ROLE_USER",
                "email", "duplicate-api-user@example.com");

        ResponseEntity<String> forbiddenResponse = restTemplate.withBasicAuth("obaas-user", BOOTSTRAP_PASSWORD)
                .postForEntity(url("/user/api/v1/createUser"), duplicateRequest, String.class);
        TestRestTemplate admin = restTemplate.withBasicAuth("obaas-admin", BOOTSTRAP_PASSWORD);
        ResponseEntity<String> weakPasswordResponse = admin.postForEntity(url("/user/api/v1/createUser"),
                weakPasswordRequest, String.class);
        ResponseEntity<String> firstCreateResponse = admin.postForEntity(url("/user/api/v1/createUser"),
                duplicateRequest, String.class);
        ResponseEntity<String> duplicateResponse = admin.postForEntity(url("/user/api/v1/createUser"),
                duplicateRequest, String.class);

        assertThat(forbiddenResponse.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
        assertThat(weakPasswordResponse.getStatusCode()).isEqualTo(HttpStatus.UNPROCESSABLE_CONTENT);
        assertThat(firstCreateResponse.getStatusCode()).isEqualTo(HttpStatus.CREATED);
        assertThat(duplicateResponse.getStatusCode()).isEqualTo(HttpStatus.CONFLICT);
    }

    private String url(String path) {
        return "http://localhost:" + port + path;
    }
}
