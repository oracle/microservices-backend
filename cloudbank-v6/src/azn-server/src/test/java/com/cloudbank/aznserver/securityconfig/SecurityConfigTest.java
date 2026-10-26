// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.aznserver.securityconfig;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.time.Duration;
import java.util.Base64;
import java.util.List;

import com.nimbusds.jose.jwk.JWKMatcher;
import com.nimbusds.jose.jwk.JWKSelector;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.crypto.password.Pbkdf2PasswordEncoder;
import org.springframework.security.oauth2.core.AuthorizationGrantType;
import org.springframework.security.oauth2.core.ClientAuthenticationMethod;
import org.springframework.security.oauth2.jose.jws.SignatureAlgorithm;
import org.springframework.security.oauth2.jwt.JwsHeader;
import org.springframework.security.oauth2.jwt.JwtClaimsSet;
import org.springframework.security.oauth2.server.authorization.OAuth2TokenType;
import org.springframework.security.oauth2.server.authorization.client.RegisteredClient;
import org.springframework.security.oauth2.server.authorization.client.RegisteredClientRepository;
import org.springframework.security.oauth2.server.authorization.token.JwtEncodingContext;

import static org.assertj.core.api.Assertions.assertThat;

class SecurityConfigTest {

    @TempDir
    private Path tempDir;

    @Test
    void defaultClientUsesCloudBankClientAndScopes() {
        SecurityConfig securityConfig = new SecurityConfig();
        PasswordEncoder passwordEncoder = securityConfig.passwordEncoder();
        RegisteredClientRepository repository = securityConfig.localRegisteredClientRepository(passwordEncoder,
                "cloudbank-client", "TestClientSecret123!", "http://127.0.0.1:8080/login/oauth2/code/cloudbank-client",
                "openid,cloudbank.read,cloudbank.transfer", "cloudbank-service-client", "ServiceClientSecret123!",
                "cloudbank.internal", "cloudbank-document-ingest-client", "DocumentIngestSecret123!",
                "cloudbank.internal", "cloudbank-document-review-client", "DocumentReviewSecret123!",
                "cloudbank.internal", "cloudbank-ai-agent-client", "AiAgentSecret123!", "cloudbank.internal",
                "cloudbank-test-client", "TestOnlyClientSecret123!", "cloudbank.test",
                "cloudbank-admin-client", "AdminClientSecret123!", "cloudbank.admin", "microtx-workflow-client",
                "MicroTxClientSecret123!", "microtx.workflow", "microtx-console-client",
                "MicroTxConsoleSecret123!", "openid,cloudbank.read,cloudbank.write",
                "http://localhost/console/oidc/redirect", "http://localhost/consoleui/index.html",
                Duration.ofHours(8), Duration.ofHours(24), "cloudbank-bff-client", "BffClientSecret123!",
                "http://127.0.0.1:5173/bff/auth/callback");

        RegisteredClient client = repository.findByClientId("cloudbank-client");
        RegisteredClient serviceClient = repository.findByClientId("cloudbank-service-client");
        RegisteredClient documentIngestClient = repository.findByClientId("cloudbank-document-ingest-client");
        RegisteredClient documentReviewClient = repository.findByClientId("cloudbank-document-review-client");
        RegisteredClient aiAgentClient = repository.findByClientId("cloudbank-ai-agent-client");
        RegisteredClient testClient = repository.findByClientId("cloudbank-test-client");
        RegisteredClient adminClient = repository.findByClientId("cloudbank-admin-client");
        RegisteredClient microtxClient = repository.findByClientId("microtx-workflow-client");
        RegisteredClient microtxConsoleClient = repository.findByClientId("microtx-console-client");
        RegisteredClient bffClient = repository.findByClientId("cloudbank-bff-client");

        assertThat(client).isNotNull();
        assertThat(client.getScopes()).contains("openid", "cloudbank.read", "cloudbank.transfer");
        assertThat(client.getScopes()).doesNotContain("cloudbank.admin", "cloudbank.internal", "cloudbank.test",
                "azn.users.admin");
        assertThat(client.getAuthorizationGrantTypes()).doesNotContain(AuthorizationGrantType.CLIENT_CREDENTIALS);
        assertThat(passwordEncoder.matches("TestClientSecret123!", client.getClientSecret())).isTrue();
        assertThat(serviceClient).isNotNull();
        assertThat(serviceClient.getScopes()).containsExactlyInAnyOrder("cloudbank.internal");
        assertThat(passwordEncoder.matches("ServiceClientSecret123!", serviceClient.getClientSecret())).isTrue();
        assertThat(documentIngestClient).isNotNull();
        assertThat(documentReviewClient).isNotNull();
        assertThat(documentIngestClient.getScopes()).containsExactlyInAnyOrder("cloudbank.internal");
        assertThat(documentIngestClient.getAuthorizationGrantTypes())
                .containsExactly(AuthorizationGrantType.CLIENT_CREDENTIALS);
        assertThat(passwordEncoder.matches("DocumentIngestSecret123!", documentIngestClient.getClientSecret()))
                .isTrue();
        assertThat(documentReviewClient.getScopes()).containsExactlyInAnyOrder("cloudbank.internal");
        assertThat(documentReviewClient.getAuthorizationGrantTypes())
                .containsExactly(AuthorizationGrantType.CLIENT_CREDENTIALS);
        assertThat(passwordEncoder.matches("DocumentReviewSecret123!", documentReviewClient.getClientSecret()))
                .isTrue();
        assertThat(aiAgentClient).isNotNull();
        assertThat(aiAgentClient.getScopes()).containsExactlyInAnyOrder("cloudbank.internal");
        assertThat(aiAgentClient.getAuthorizationGrantTypes()).containsExactly(AuthorizationGrantType.CLIENT_CREDENTIALS);
        assertThat(passwordEncoder.matches("AiAgentSecret123!", aiAgentClient.getClientSecret())).isTrue();
        assertThat(testClient).isNotNull();
        assertThat(testClient.getScopes()).containsExactlyInAnyOrder("cloudbank.test");
        assertThat(adminClient).isNotNull();
        assertThat(adminClient.getScopes()).containsExactlyInAnyOrder("cloudbank.admin");
        assertThat(microtxClient).isNotNull();
        assertThat(microtxClient.getAuthorizationGrantTypes())
                .containsExactly(AuthorizationGrantType.CLIENT_CREDENTIALS);
        assertThat(microtxClient.getScopes()).containsExactly("microtx.workflow");
        assertThat(passwordEncoder.matches("MicroTxClientSecret123!", microtxClient.getClientSecret())).isTrue();
        assertThat(microtxConsoleClient).isNotNull();
        assertThat(microtxConsoleClient.getClientAuthenticationMethods()).containsExactlyInAnyOrder(
                ClientAuthenticationMethod.CLIENT_SECRET_BASIC, ClientAuthenticationMethod.CLIENT_SECRET_POST);
        assertThat(microtxConsoleClient.getAuthorizationGrantTypes()).containsExactlyInAnyOrder(
                AuthorizationGrantType.AUTHORIZATION_CODE, AuthorizationGrantType.REFRESH_TOKEN);
        assertThat(microtxConsoleClient.getRedirectUris()).containsExactlyInAnyOrder(
                "http://localhost/console/oidc/redirect",
                "http://host.minikube.internal/console/oidc/redirect");
        assertThat(microtxConsoleClient.getPostLogoutRedirectUris())
                .containsExactlyInAnyOrder("http://localhost/consoleui/index.html",
                        "http://host.minikube.internal/consoleui/index.html");
        assertThat(microtxConsoleClient.getClientSettings().isRequireProofKey()).isFalse();
        assertThat(microtxConsoleClient.getTokenSettings().getAccessTokenTimeToLive())
                .isEqualTo(Duration.ofHours(8));
        assertThat(microtxConsoleClient.getTokenSettings().getRefreshTokenTimeToLive())
                .isEqualTo(Duration.ofHours(24));
        assertThat(passwordEncoder.matches("MicroTxConsoleSecret123!", microtxConsoleClient.getClientSecret()))
                .isTrue();
        assertThat(bffClient).isNotNull();
        assertThat(bffClient.getScopes()).containsExactlyInAnyOrder("openid", "cloudbank.read", "cloudbank.write");
        assertThat(bffClient.getAuthorizationGrantTypes()).containsExactly(AuthorizationGrantType.AUTHORIZATION_CODE);
        assertThat(bffClient.getClientSettings().isRequireProofKey()).isTrue();
        assertThat(bffClient.getTokenSettings().getAccessTokenTimeToLive()).isEqualTo(Duration.ofMinutes(30));
        assertThat(bffClient.getRedirectUris()).containsExactly("http://127.0.0.1:5173/bff/auth/callback");
    }

    @Test
    void microtxAccessTokenUsesDedicatedAudienceAndRoles() {
        RegisteredClient client = RegisteredClient.withId("microtx-id").clientId("microtx-workflow-client")
                .authorizationGrantType(AuthorizationGrantType.CLIENT_CREDENTIALS).build();
        JwtEncodingContext context = accessTokenContext(client);

        new SecurityConfig().cloudBankAccessTokenCustomizer("cloudbank-api", "microtx-workflow-client",
                "microtx-conductor-user,microtx-conductor-worker", "microtx-workflow").customize(context);

        JwtClaimsSet claims = context.getClaims().build();
        assertThat(claims.getAudience()).containsExactly("microtx-workflow");
        assertThat((Object) claims.getClaim("roles"))
                .isEqualTo(List.of("microtx-conductor-user", "microtx-conductor-worker"));
        assertThat(claims.getClaimAsString("client_id")).isEqualTo("microtx-workflow-client");
        assertThat(claims.getClaimAsString("token_kind")).isEqualTo("service");
    }

    @Test
    void cloudBankServiceTokenDoesNotReceiveMicrotxClaims() {
        RegisteredClient client = RegisteredClient.withId("service-id").clientId("cloudbank-service-client")
                .authorizationGrantType(AuthorizationGrantType.CLIENT_CREDENTIALS).build();
        JwtEncodingContext context = accessTokenContext(client);

        new SecurityConfig().cloudBankAccessTokenCustomizer("cloudbank-api", "microtx-workflow-client",
                "microtx-conductor-user,microtx-conductor-worker", "microtx-workflow").customize(context);

        JwtClaimsSet claims = context.getClaims().build();
        assertThat(claims.getAudience()).containsExactly("cloudbank-api");
        assertThat((Object) claims.getClaim("roles")).isEqualTo(List.of());
    }

    @Test
    void passwordEncoderUsesSaltedPbkdf2Hashes() {
        PasswordEncoder passwordEncoder = new SecurityConfig().passwordEncoder();

        String firstHash = passwordEncoder.encode("StrongPass123!");
        String secondHash = passwordEncoder.encode("StrongPass123!");

        assertThat(passwordEncoder).isInstanceOf(Pbkdf2PasswordEncoder.class);
        assertThat(firstHash).matches("[0-9a-f]{96}");
        assertThat(secondHash).matches("[0-9a-f]{96}").isNotEqualTo(firstHash);
        assertThat(passwordEncoder.matches("StrongPass123!", firstHash)).isTrue();
        assertThat(passwordEncoder.matches("StrongPass123!", secondHash)).isTrue();
        assertThat(passwordEncoder.matches("WrongPass123!", firstHash)).isFalse();
    }

    @Test
    void persistentJwkSourceLoadsMountedPemKeys() throws Exception {
        SecurityConfig securityConfig = new SecurityConfig();
        KeyPairGenerator generator = KeyPairGenerator.getInstance("RSA");
        generator.initialize(2048);
        KeyPair keyPair = generator.generateKeyPair();
        Path privateKey = tempDir.resolve("private.pem");
        Path publicKey = tempDir.resolve("public.pem");

        Files.writeString(privateKey, pem("PRIVATE KEY", keyPair.getPrivate().getEncoded()), StandardCharsets.UTF_8);
        Files.writeString(publicKey, pem("PUBLIC KEY", keyPair.getPublic().getEncoded()), StandardCharsets.UTF_8);

        JWKSelector selector = new JWKSelector(new JWKMatcher.Builder().keyID("test-key").build());

        assertThat(securityConfig.persistentJwkSource(privateKey.toString(), publicKey.toString(), "test-key")
                .get(selector, null)).hasSize(1);
    }

    private static String pem(String type, byte[] encoded) {
        return "-----BEGIN " + type + "-----\n"
                + Base64.getMimeEncoder(64, "\n".getBytes(StandardCharsets.UTF_8)).encodeToString(encoded)
                + "\n-----END " + type + "-----\n";
    }

    private static JwtEncodingContext accessTokenContext(RegisteredClient client) {
        return JwtEncodingContext.with(JwsHeader.with(SignatureAlgorithm.RS256), JwtClaimsSet.builder())
                .registeredClient(client).authorizationGrantType(AuthorizationGrantType.CLIENT_CREDENTIALS)
                .tokenType(OAuth2TokenType.ACCESS_TOKEN).build();
    }
}
