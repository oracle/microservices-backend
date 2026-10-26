// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.aznserver.integration;

import java.util.Map;

import com.cloudbank.aznserver.repository.UserRepository;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpStatus;
import org.springframework.boot.resttestclient.autoconfigure.AutoConfigureRestTestClient;
import org.springframework.http.MediaType;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.client.RestTestClient;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@AutoConfigureRestTestClient
@TestPropertySource(properties = "azn.authorization-server.default-client.enabled=true")
class UserApiOracleIT extends OracleIntegrationTestSupport {

    @Autowired
    private RestTestClient restTestClient;

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
        Map<String, String> request = Map.of(
                "username", "api-user",
                "password", "StrongPass123!",
                "roles", "ROLE_USER",
                "email", "api-user@example.com");

        restTestClient.post()
                .uri("/user/api/v1/createUser")
                .headers(headers -> headers.setBasicAuth("obaas-admin", BOOTSTRAP_PASSWORD))
                .contentType(MediaType.APPLICATION_JSON)
                .body(request)
                .exchange()
                .expectStatus().isCreated()
                .expectBody(String.class)
                .value(body -> assertThat(body).contains("api-user").doesNotContain("StrongPass123!"));

        restTestClient.get()
                .uri("/user/api/v1/findUser?username=api-user")
                .headers(headers -> headers.setBasicAuth("obaas-admin", BOOTSTRAP_PASSWORD))
                .exchange()
                .expectStatus().isOk()
                .expectBody(String.class)
                .value(body -> assertThat(body)
                        .contains("api-user")
                        .doesNotContain("StrongPass123!")
                        .doesNotContain("otp"));
        assertThat(userRepository.findByUsername("api-user"))
                .hasValueSatisfying(user -> {
                    assertThat(user.getPassword()).isNotEqualTo("StrongPass123!").matches("[0-9a-f]{96}");
                    assertThat(passwordEncoder.matches("StrongPass123!", user.getPassword())).isTrue();
                    assertThat(passwordEncoder.matches("WrongPass123!", user.getPassword())).isFalse();
                });
    }

    @Test
    void forgotFlowDoesNotDiscloseOtpAndAllowsPasswordReset() {
        restTestClient.post()
                .uri("/user/api/v1/createUser")
                .headers(headers -> headers.setBasicAuth("obaas-admin", BOOTSTRAP_PASSWORD))
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of(
                        "username", "reset-user",
                        "password", "StrongPass123!",
                        "roles", "ROLE_USER",
                        "email", "reset-user@example.com"))
                .exchange()
                .expectStatus().isCreated();

        restTestClient.post()
                .uri("/user/api/v1/forgot")
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of(
                        "username", "reset-user",
                        "otp", "123456"))
                .exchange()
                .expectStatus().isUnauthorized();

        restTestClient.post()
                .uri("/user/api/v1/forgot")
                .headers(headers -> headers.setBasicAuth("obaas-admin", BOOTSTRAP_PASSWORD))
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of(
                        "username", "reset-user",
                        "otp", "123456"))
                .exchange()
                .expectStatus().isOk();

        assertThat(userRepository.findByUsername("reset-user"))
                .hasValueSatisfying(user -> {
                    assertThat(user.getOtp()).isNotEqualTo("123456").matches("[0-9a-f]{96}");
                    assertThat(passwordEncoder.matches("123456", user.getOtp())).isTrue();
                    assertThat(passwordEncoder.matches("654321", user.getOtp())).isFalse();
                });

        restTestClient.get()
                .uri("/user/api/v1/forgot?username=reset-user")
                .headers(headers -> headers.setBasicAuth("obaas-admin", BOOTSTRAP_PASSWORD))
                .exchange()
                .expectStatus().isOk()
                .expectBody(String.class)
                .value(body -> assertThat(body)
                        .contains("reset-user")
                        .contains("reset-user@example.com")
                        .doesNotContain("123456")
                        .doesNotContain("password"));

        restTestClient.put()
                .uri("/user/api/v1/forgot")
                .headers(headers -> headers.setBasicAuth("obaas-admin", BOOTSTRAP_PASSWORD))
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of(
                        "username", "reset-user",
                        "otp", "123456",
                        "password", "ResetPass123!"))
                .exchange()
                .expectStatus().isOk();

        restTestClient.get()
                .uri("/user/api/v1/connect")
                .headers(headers -> headers.setBasicAuth("reset-user", "ResetPass123!"))
                .exchange()
                .expectStatus().isOk();

        assertThat(userRepository.findByUsername("reset-user"))
                .hasValueSatisfying(user -> {
                    assertThat(user.getPassword())
                            .isNotEqualTo("StrongPass123!")
                            .isNotEqualTo("ResetPass123!")
                            .matches("[0-9a-f]{96}");
                    assertThat(passwordEncoder.matches("ResetPass123!", user.getPassword())).isTrue();
                    assertThat(passwordEncoder.matches("StrongPass123!", user.getPassword())).isFalse();
                    assertThat(user.getOtp()).isNull();
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

        restTestClient.post()
                .uri("/user/api/v1/createUser")
                .headers(headers -> headers.setBasicAuth("obaas-user", BOOTSTRAP_PASSWORD))
                .contentType(MediaType.APPLICATION_JSON)
                .body(duplicateRequest)
                .exchange()
                .expectStatus().isForbidden();

        restTestClient.post()
                .uri("/user/api/v1/createUser")
                .headers(headers -> headers.setBasicAuth("obaas-admin", BOOTSTRAP_PASSWORD))
                .contentType(MediaType.APPLICATION_JSON)
                .body(weakPasswordRequest)
                .exchange()
                .expectStatus().isEqualTo(HttpStatus.UNPROCESSABLE_CONTENT);

        restTestClient.post()
                .uri("/user/api/v1/createUser")
                .headers(headers -> headers.setBasicAuth("obaas-admin", BOOTSTRAP_PASSWORD))
                .contentType(MediaType.APPLICATION_JSON)
                .body(duplicateRequest)
                .exchange()
                .expectStatus().isCreated();

        restTestClient.post()
                .uri("/user/api/v1/createUser")
                .headers(headers -> headers.setBasicAuth("obaas-admin", BOOTSTRAP_PASSWORD))
                .contentType(MediaType.APPLICATION_JSON)
                .body(duplicateRequest)
                .exchange()
                .expectStatus().isEqualTo(HttpStatus.CONFLICT);
    }
}
