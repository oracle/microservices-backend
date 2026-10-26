// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.aznserver.securityconfig;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.security.KeyFactory;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.interfaces.RSAPrivateKey;
import java.security.interfaces.RSAPublicKey;
import java.security.spec.PKCS8EncodedKeySpec;
import java.security.spec.X509EncodedKeySpec;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Base64;
import java.util.List;
import java.util.UUID;

import com.nimbusds.jose.jwk.JWKSet;
import com.nimbusds.jose.jwk.RSAKey;
import com.nimbusds.jose.jwk.source.JWKSource;
import com.nimbusds.jose.proc.SecurityContext;
import com.cloudbank.aznserver.model.SecurityUser;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnMissingBean;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.security.autoconfigure.actuate.web.servlet.EndpointRequest;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.annotation.Order;
import org.springframework.http.MediaType;
import org.springframework.security.access.hierarchicalroles.RoleHierarchy;
import org.springframework.security.access.hierarchicalroles.RoleHierarchyImpl;
import org.springframework.security.authentication.dao.DaoAuthenticationProvider;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.method.configuration.EnableMethodSecurity;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.crypto.password.Pbkdf2PasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.oauth2.core.AuthorizationGrantType;
import org.springframework.security.oauth2.core.ClientAuthenticationMethod;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.server.authorization.client.InMemoryRegisteredClientRepository;
import org.springframework.security.oauth2.server.authorization.client.RegisteredClient;
import org.springframework.security.oauth2.server.authorization.client.RegisteredClientRepository;
import org.springframework.security.config.annotation.web.configuration.OAuth2AuthorizationServerConfiguration;
import org.springframework.security.config.annotation.web.configurers.oauth2.server.authorization.OAuth2AuthorizationServerConfigurer;
import org.springframework.security.oauth2.server.authorization.settings.AuthorizationServerSettings;
import org.springframework.security.oauth2.server.authorization.settings.ClientSettings;
import org.springframework.security.oauth2.server.authorization.settings.TokenSettings;
import org.springframework.security.oauth2.server.authorization.token.JwtEncodingContext;
import org.springframework.security.oauth2.server.authorization.token.OAuth2TokenCustomizer;
import org.springframework.security.oauth2.server.authorization.OAuth2TokenType;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.LoginUrlAuthenticationEntryPoint;
import org.springframework.security.web.util.matcher.MediaTypeRequestMatcher;
import org.springframework.util.StringUtils;

@Configuration
@EnableWebSecurity(debug = false)
@EnableMethodSecurity
public class SecurityConfig {

    private static final Logger log = LoggerFactory.getLogger(SecurityConfig.class);

    private static final String DEFAULT_CLIENT_ID = "cloudbank-client";
    private static final String DEFAULT_CLIENT_SCOPES = "openid,cloudbank.read,cloudbank.write,cloudbank.transfer";
    private static final String DEFAULT_SERVICE_CLIENT_ID = "cloudbank-service-client";
    private static final String DEFAULT_SERVICE_CLIENT_SCOPES = "cloudbank.internal";
    private static final String DEFAULT_DOCUMENT_INGEST_CLIENT_ID = "cloudbank-document-ingest-client";
    private static final String DEFAULT_DOCUMENT_REVIEW_CLIENT_ID = "cloudbank-document-review-client";
    private static final String DEFAULT_AI_AGENT_CLIENT_ID = "cloudbank-ai-agent-client";
    private static final String DEFAULT_TEST_CLIENT_ID = "cloudbank-test-client";
    private static final String DEFAULT_TEST_CLIENT_SCOPES = "cloudbank.test";
    private static final String DEFAULT_ADMIN_CLIENT_ID = "cloudbank-admin-client";
    private static final String DEFAULT_ADMIN_CLIENT_SCOPES = "cloudbank.admin";
    private static final String DEFAULT_MICROTX_CLIENT_ID = "microtx-workflow-client";
    private static final String DEFAULT_MICROTX_CLIENT_SCOPES = "microtx.workflow";
    private static final String DEFAULT_MICROTX_ROLES = "microtx-conductor-user,microtx-conductor-worker";
    private static final String DEFAULT_MICROTX_CONSOLE_CLIENT_ID = "microtx-console-client";
    private static final String DEFAULT_MICROTX_CONSOLE_CLIENT_SCOPES = "openid,cloudbank.read,cloudbank.write";
    private static final String DEFAULT_MICROTX_CONSOLE_REDIRECT_URI = "http://localhost/console/oidc/redirect";
    private static final String DEFAULT_MICROTX_CONSOLE_POST_LOGOUT_REDIRECT_URI = "http://localhost/consoleui/index.html";
    private static final String DEFAULT_BFF_CLIENT_ID = "cloudbank-bff-client";
    private static final String MICROTX_LOCAL_ALIAS_REDIRECT_URI = "http://host.minikube.internal/console/oidc/redirect";
    private static final String MICROTX_LOCAL_ALIAS_POST_LOGOUT_REDIRECT_URI = "http://host.minikube.internal/consoleui/index.html";

    public static final String ROLE_HIERARCHY = "ROLE_ADMIN > ROLE_USER\n" + "ROLE_ADMIN > ROLE_CONFIG_EDITOR\n"
            + "ROLE_CONFIG_EDITOR > ROLE_USER";

    /**
     * Configure a role hierarchy such that ADMIN "includes"/implies USER.
     *
     * @return the hierarchy.
     */

    @Bean
    public RoleHierarchy roleHierarchy() {
        return RoleHierarchyImpl.fromHierarchy(ROLE_HIERARCHY);
    }

    /**
     * Authorization Server endpoints use their own filter chain so OAuth protocol
     * handling does not inherit API-specific stateless settings.
     *
     * @return the SecurityFilterChain.
     *
     * @throws Exception
     *             if unable to create the chain.
     */
    @Bean
    @Order(1)
    public SecurityFilterChain authorizationServerSecurityFilterChain(HttpSecurity http) throws Exception {
        log.debug("In authorizationServerSecurityFilterChain");
        OAuth2AuthorizationServerConfigurer authorizationServerConfigurer = new OAuth2AuthorizationServerConfigurer();

        http.securityMatcher(authorizationServerConfigurer.getEndpointsMatcher())
                .with(authorizationServerConfigurer,
                        authorizationServer -> authorizationServer.oidc(Customizer.withDefaults()))
                .authorizeHttpRequests((authorize) -> authorize.requestMatchers("/.well-known/**", "/oauth2/jwks")
                        .permitAll().anyRequest().authenticated())
                .csrf((csrf) -> csrf.ignoringRequestMatchers(authorizationServerConfigurer.getEndpointsMatcher()))
                .exceptionHandling((exceptions) -> exceptions.defaultAuthenticationEntryPointFor(
                        new LoginUrlAuthenticationEntryPoint("/login"),
                        new MediaTypeRequestMatcher(MediaType.TEXT_HTML)));
        return http.build();
    }

    /**
     * Create a SecurityFilterChain to allow anonymous access to actuator endpoints.
     *
     * @param http
     *            HttpSecurity injected by Spring.
     *
     * @return the SecurityFilterChain.
     *
     * @throws Exception
     *             if unable to create the chain.
     */
    @Bean
    @Order(2)
    public SecurityFilterChain actuatorSecurityFilterChain(HttpSecurity http) throws Exception {
        log.debug("In actuatorSecurityFilterChain");
        http.securityMatcher(EndpointRequest.toAnyEndpoint()).authorizeHttpRequests((authorize) -> authorize
                .requestMatchers(EndpointRequest.to("health", "info")).permitAll().anyRequest().hasRole("ACTUATOR"))
                .httpBasic(Customizer.withDefaults());
        return http.build();
    }

    /**
     * Create a SecurityFilterChain for the user-management API.
     *
     * @param http
     *            HttpSecurity injected by Spring.
     * @param userDetailsService
     *            the JPA-backed user details service.
     *
     * @return the SecurityFilterChain.
     *
     * @throws Exception
     *             if unable to create the chain.
     */
    @Bean
    @Order(3)
    public SecurityFilterChain apiSecurityFilterChain(HttpSecurity http, UserDetailsService userDetailsService)
            throws Exception {
        log.debug("In apiSecurityFilterChain");
        http.securityMatcher("/user/api/**", "/error/**")
                .authorizeHttpRequests((authorize) -> authorize.requestMatchers("/error/**").permitAll()
                        .requestMatchers("/user/api/v1/ping").permitAll().anyRequest().authenticated())
                .sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .httpBasic(Customizer.withDefaults()).userDetailsService(userDetailsService);
        // The user-management API is stateless and does not use browser sessions or cookies.
        http.csrf(csrf -> csrf.disable());
        return http.build();
    }

    /**
     * Create the fallback browser login chain used by authorization-code flows.
     *
     * @param http
     *            HttpSecurity injected by Spring.
     *
     * @return the SecurityFilterChain.
     *
     * @throws Exception
     *             if unable to create the chain.
     */
    @Bean
    @Order(4)
    public SecurityFilterChain defaultSecurityFilterChain(HttpSecurity http) throws Exception {
        log.debug("In defaultSecurityFilterChain");
        http.authorizeHttpRequests((authorize) -> authorize.anyRequest().authenticated())
                .formLogin(Customizer.withDefaults()).httpBasic(Customizer.withDefaults());
        return http.build();
    }

    /**
     * Create an Authentication Provider for our UserDetailsService.
     *
     * @param userDetailsService
     *            the JPA-backed user details service.
     * @param passwordEncoder
     *            password encoder for stored password hashes.
     *
     * @return the AuthenticationProvider.
     */
    @Bean
    public DaoAuthenticationProvider authenticationProvider(UserDetailsService userDetailsService,
            PasswordEncoder passwordEncoder) {
        DaoAuthenticationProvider auth = new DaoAuthenticationProvider(userDetailsService);
        auth.setPasswordEncoder(passwordEncoder);
        return auth;
    }

    /**
     * Create an opt-in local client for test and developer-only contexts. Production deployments should configure
     * registered clients explicitly using Spring Boot's authorization-server client properties.
     *
     * @param passwordEncoder
     *            password encoder for the client secret.
     * @param clientId
     *            configured client id.
     * @param clientSecret
     *            configured client secret.
     * @param redirectUri
     *            configured authorization-code redirect URI.
     * @param clientScopes
     *            comma-delimited OAuth scopes granted to the default client.
     * @param serviceClientId
     *            service-to-service OAuth client id.
     * @param serviceClientSecret
     *            service-to-service OAuth client secret.
     * @param serviceClientScopes
     *            comma-delimited OAuth scopes granted to the service client.
     * @param documentIngestClientId
     *            document-ingest OAuth client id.
     * @param documentIngestClientSecret
     *            document-ingest OAuth client secret.
     * @param documentIngestClientScopes
     *            scopes granted to the document-ingest client.
     * @param testClientId
     *            test OAuth client id.
     * @param testClientSecret
     *            test OAuth client secret.
     * @param testClientScopes
     *            comma-delimited OAuth scopes granted to the test client.
     * @param adminClientId
     *            admin OAuth client id.
     * @param adminClientSecret
     *            admin OAuth client secret.
     * @param adminClientScopes
     *            comma-delimited OAuth scopes granted to the admin client.
     * @param microtxClientId
     *            MicroTx Workflow OAuth client id.
     * @param microtxClientSecret
     *            MicroTx Workflow OAuth client secret.
     * @param microtxClientScopes
     *            scopes granted to the MicroTx Workflow client.
     * @param microtxConsoleClientId
     *            MicroTx Console OIDC client id.
     * @param microtxConsoleClientSecret
     *            MicroTx Console OIDC client secret.
     * @param microtxConsoleClientScopes
     *            comma-delimited OAuth scopes granted to the MicroTx Console client.
     * @param microtxConsoleRedirectUri
     *            MicroTx Console authorization-code redirect URI.
     * @param microtxConsolePostLogoutRedirectUri
     *            MicroTx Console post-logout redirect URI.
     *
     * @return a local RegisteredClientRepository.
     */
    @Bean
    @ConditionalOnMissingBean
    @ConditionalOnProperty(prefix = "azn.authorization-server.default-client", name = "enabled", havingValue = "true")
    public RegisteredClientRepository localRegisteredClientRepository(PasswordEncoder passwordEncoder,
            @Value("${azn.authorization-server.default-client.id:" + DEFAULT_CLIENT_ID + "}") String clientId,
            @Value("${azn.authorization-server.default-client.secret:}") String clientSecret,
            @Value("${azn.authorization-server.default-client.redirect-uri:"
                    + "http://127.0.0.1:8080/login/oauth2/code/" + DEFAULT_CLIENT_ID + "}") String redirectUri,
            @Value("${azn.authorization-server.default-client.scopes:" + DEFAULT_CLIENT_SCOPES
                    + "}") String clientScopes,
            @Value("${azn.authorization-server.service-client.id:" + DEFAULT_SERVICE_CLIENT_ID
                    + "}") String serviceClientId,
            @Value("${azn.authorization-server.service-client.secret:}") String serviceClientSecret,
            @Value("${azn.authorization-server.service-client.scopes:" + DEFAULT_SERVICE_CLIENT_SCOPES
                    + "}") String serviceClientScopes,
            @Value("${azn.authorization-server.document-ingest-client.id:" + DEFAULT_DOCUMENT_INGEST_CLIENT_ID
                    + "}") String documentIngestClientId,
            @Value("${azn.authorization-server.document-ingest-client.secret:}") String documentIngestClientSecret,
            @Value("${azn.authorization-server.document-ingest-client.scopes:" + DEFAULT_SERVICE_CLIENT_SCOPES
                    + "}") String documentIngestClientScopes,
            @Value("${azn.authorization-server.document-review-client.id:" + DEFAULT_DOCUMENT_REVIEW_CLIENT_ID
                    + "}") String documentReviewClientId,
            @Value("${azn.authorization-server.document-review-client.secret:}") String documentReviewClientSecret,
            @Value("${azn.authorization-server.document-review-client.scopes:" + DEFAULT_SERVICE_CLIENT_SCOPES
                    + "}") String documentReviewClientScopes,
            @Value("${azn.authorization-server.ai-agent-client.id:" + DEFAULT_AI_AGENT_CLIENT_ID
                    + "}") String aiAgentClientId,
            @Value("${azn.authorization-server.ai-agent-client.secret:}") String aiAgentClientSecret,
            @Value("${azn.authorization-server.ai-agent-client.scopes:" + DEFAULT_SERVICE_CLIENT_SCOPES
                    + "}") String aiAgentClientScopes,
            @Value("${azn.authorization-server.test-client.id:" + DEFAULT_TEST_CLIENT_ID + "}") String testClientId,
            @Value("${azn.authorization-server.test-client.secret:}") String testClientSecret,
            @Value("${azn.authorization-server.test-client.scopes:" + DEFAULT_TEST_CLIENT_SCOPES
                    + "}") String testClientScopes,
            @Value("${azn.authorization-server.admin-client.id:" + DEFAULT_ADMIN_CLIENT_ID + "}") String adminClientId,
            @Value("${azn.authorization-server.admin-client.secret:}") String adminClientSecret,
            @Value("${azn.authorization-server.admin-client.scopes:" + DEFAULT_ADMIN_CLIENT_SCOPES
                    + "}") String adminClientScopes,
            @Value("${azn.authorization-server.microtx-client.id:" + DEFAULT_MICROTX_CLIENT_ID
                    + "}") String microtxClientId,
            @Value("${azn.authorization-server.microtx-client.secret:}") String microtxClientSecret,
            @Value("${azn.authorization-server.microtx-client.scopes:" + DEFAULT_MICROTX_CLIENT_SCOPES
                    + "}") String microtxClientScopes,
            @Value("${azn.authorization-server.microtx-console-client.id:" + DEFAULT_MICROTX_CONSOLE_CLIENT_ID
                    + "}") String microtxConsoleClientId,
            @Value("${azn.authorization-server.microtx-console-client.secret:}") String microtxConsoleClientSecret,
            @Value("${azn.authorization-server.microtx-console-client.scopes:"
                    + DEFAULT_MICROTX_CONSOLE_CLIENT_SCOPES + "}") String microtxConsoleClientScopes,
            @Value("${azn.authorization-server.microtx-console-client.redirect-uri:"
                    + DEFAULT_MICROTX_CONSOLE_REDIRECT_URI + "}") String microtxConsoleRedirectUri,
            @Value("${azn.authorization-server.microtx-console-client.post-logout-redirect-uri:"
                    + DEFAULT_MICROTX_CONSOLE_POST_LOGOUT_REDIRECT_URI + "}") String microtxConsolePostLogoutRedirectUri,
            @Value("${azn.authorization-server.microtx-console-client.access-token-time-to-live:PT8H}")
            Duration microtxConsoleAccessTokenTimeToLive,
            @Value("${azn.authorization-server.microtx-console-client.refresh-token-time-to-live:PT24H}")
            Duration microtxConsoleRefreshTokenTimeToLive,
            @Value("${azn.authorization-server.bff-client.id:" + DEFAULT_BFF_CLIENT_ID + "}") String bffClientId,
            @Value("${azn.authorization-server.bff-client.secret:}") String bffClientSecret,
            @Value("${azn.authorization-server.bff-client.redirect-uri:}") String bffRedirectUri) {
        if (!StringUtils.hasText(clientSecret)) {
            throw new IllegalStateException("azn.authorization-server.default-client.secret must be set when "
                    + "azn.authorization-server.default-client.enabled=true");
        }
        List<RegisteredClient> registeredClients = new ArrayList<>();
        RegisteredClient.Builder registeredClient = RegisteredClient.withId(UUID.randomUUID().toString())
                .clientId(clientId).clientSecret(passwordEncoder.encode(clientSecret))
                .clientAuthenticationMethod(ClientAuthenticationMethod.CLIENT_SECRET_BASIC)
                .authorizationGrantType(AuthorizationGrantType.AUTHORIZATION_CODE)
                .authorizationGrantType(AuthorizationGrantType.REFRESH_TOKEN).redirectUri(redirectUri)
                .clientSettings(ClientSettings.builder().requireProofKey(true).build());

        Arrays.stream(clientScopes.split(",")).map(String::trim).filter(StringUtils::hasText)
                .forEach(registeredClient::scope);
        registeredClients.add(registeredClient.build());

        addClientCredentialsClient(registeredClients, passwordEncoder, serviceClientId, serviceClientSecret,
                serviceClientScopes);
        addClientCredentialsClient(registeredClients, passwordEncoder, documentIngestClientId,
                documentIngestClientSecret, documentIngestClientScopes);
        addClientCredentialsClient(registeredClients, passwordEncoder, documentReviewClientId,
                documentReviewClientSecret, documentReviewClientScopes);
        addClientCredentialsClient(registeredClients, passwordEncoder, aiAgentClientId, aiAgentClientSecret,
                aiAgentClientScopes);
        addClientCredentialsClient(registeredClients, passwordEncoder, testClientId, testClientSecret,
                testClientScopes);
        addClientCredentialsClient(registeredClients, passwordEncoder, adminClientId, adminClientSecret,
                adminClientScopes);
        addClientCredentialsClient(registeredClients, passwordEncoder, microtxClientId, microtxClientSecret,
                microtxClientScopes);
        addConsoleAuthorizationCodeClient(registeredClients, passwordEncoder, microtxConsoleClientId,
                microtxConsoleClientSecret, microtxConsoleClientScopes, microtxConsoleRedirectUri,
                microtxConsolePostLogoutRedirectUri, microtxConsoleAccessTokenTimeToLive,
                microtxConsoleRefreshTokenTimeToLive);

        if (StringUtils.hasText(bffClientSecret) != StringUtils.hasText(bffRedirectUri)) {
            throw new IllegalStateException("BFF OAuth client secret and exact redirect URI must be configured together");
        }
        if (StringUtils.hasText(bffClientSecret)) {
            RegisteredClient.Builder bffClient = RegisteredClient.withId(UUID.randomUUID().toString())
                    .clientId(bffClientId).clientSecret(passwordEncoder.encode(bffClientSecret))
                    .clientAuthenticationMethod(ClientAuthenticationMethod.CLIENT_SECRET_BASIC)
                    .authorizationGrantType(AuthorizationGrantType.AUTHORIZATION_CODE)
                    .redirectUri(bffRedirectUri)
                    .scope("openid").scope("cloudbank.read").scope("cloudbank.write")
                    .clientSettings(ClientSettings.builder().requireProofKey(true).build())
                    .tokenSettings(TokenSettings.builder().accessTokenTimeToLive(Duration.ofMinutes(30)).build());
            registeredClients.add(bffClient.build());
        }

        return new InMemoryRegisteredClientRepository(registeredClients);
    }

    /**
     * Create an instance of AuthorizationServerSettings to configure Spring Authorization Server.
     *
     * @return the AuthorizationServerSettings
     */
    @Bean
    public AuthorizationServerSettings authorizationServerSettings(
            @Value("${azn.authorization-server.issuer:http://127.0.0.1:8080}") String issuer) {
        if (!StringUtils.hasText(issuer)) {
            throw new IllegalStateException("azn.authorization-server.issuer must not be blank");
        }
        return AuthorizationServerSettings.builder().issuer(issuer).build();
    }

    /**
     * Add only stable, authorization-relevant CloudBank claims to access tokens. Passwords, email addresses, OTPs, and
     * other profile fields are deliberately excluded.
     */
    @Bean
    public OAuth2TokenCustomizer<JwtEncodingContext> cloudBankAccessTokenCustomizer(
            @Value("${azn.authorization-server.audience:cloudbank-api}") String audience,
            @Value("${azn.authorization-server.microtx-client.id:" + DEFAULT_MICROTX_CLIENT_ID
                    + "}") String microtxClientId,
            @Value("${azn.authorization-server.microtx-client.roles:" + DEFAULT_MICROTX_ROLES
                    + "}") String microtxRoles,
            @Value("${azn.authorization-server.microtx-client.audience:microtx-workflow}") String microtxAudience) {
        List<String> configuredMicrotxRoles = Arrays.stream(microtxRoles.split(",")).map(String::trim)
                .filter(StringUtils::hasText).toList();
        return context -> {
            if (!OAuth2TokenType.ACCESS_TOKEN.equals(context.getTokenType())) {
                return;
            }
            String registeredClientId = context.getRegisteredClient().getClientId();
            boolean microtxClient = microtxClientId.equals(registeredClientId);
            context.getClaims().audience(List.of(microtxClient ? microtxAudience : audience));
            context.getClaims().claim("client_id", registeredClientId);
            context.getClaims().claim("token_kind",
                    AuthorizationGrantType.CLIENT_CREDENTIALS.equals(context.getAuthorizationGrantType()) ? "service"
                            : "user");

            if (microtxClient) {
                context.getClaims().claim("roles", configuredMicrotxRoles);
                return;
            }

            Object principal = context.getPrincipal() == null ? null : context.getPrincipal().getPrincipal();
            if (principal instanceof SecurityUser securityUser) {
                context.getClaims().claim("cb_principal_id", securityUser.getPrincipalId());
                context.getClaims().claim("roles", securityUser.getAuthorities().stream()
                        .map(authority -> authority.getAuthority()).sorted().toList());
            } else {
                context.getClaims().claim("roles", List.of());
            }
        };
    }

    /**
     * Provide persistent signing keys when a deployment mounts key material.
     *
     * @param privateKeyPath
     *            path to a PKCS#8 PEM-encoded RSA private key.
     * @param publicKeyPath
     *            path to an X.509 PEM-encoded RSA public key.
     * @param keyId
     *            stable key id to publish in the JWK set and token headers.
     *
     * @return the JWK source.
     */
    @Bean
    @ConditionalOnProperty(prefix = "azn.authorization-server.signing-key", name = "private-key-path")
    public JWKSource<SecurityContext> persistentJwkSource(
            @Value("${azn.authorization-server.signing-key.private-key-path}") String privateKeyPath,
            @Value("${azn.authorization-server.signing-key.public-key-path:}") String publicKeyPath,
            @Value("${azn.authorization-server.signing-key.key-id:cloudbank-v5}") String keyId) {
        if (!StringUtils.hasText(publicKeyPath)) {
            throw new IllegalStateException("azn.authorization-server.signing-key.public-key-path must be set when "
                    + "azn.authorization-server.signing-key.private-key-path is set");
        }
        if (!StringUtils.hasText(keyId)) {
            throw new IllegalStateException("azn.authorization-server.signing-key.key-id must not be blank");
        }

        RSAKey rsaKey = loadRsa(privateKeyPath, publicKeyPath, keyId);
        log.info("Using persistent RSA signing key with key id '{}'", keyId);
        return jwkSourceFor(rsaKey);
    }

    /**
     * Provide process-local signing keys for development and tests. Production deployments should replace this bean
     * with persistent key material so tokens remain verifiable across restarts and rolling deploys.
     *
     * @return the JWK source.
     */
    @Bean
    @ConditionalOnMissingBean
    public JWKSource<SecurityContext> jwkSource(
            @Value("${azn.authorization-server.signing-key.required:false}") boolean persistentKeyRequired) {
        if (persistentKeyRequired) {
            throw new IllegalStateException("Persistent authorization-server signing keys are required");
        }
        log.warn("Using process-local generated RSA signing keys. Configure a persistent JWKSource bean for "
                + "production so issued tokens remain verifiable across restarts and rolling deploys.");
        RSAKey rsaKey = generateRsa();
        return jwkSourceFor(rsaKey);
    }

    @Bean
    @ConditionalOnMissingBean
    public JwtDecoder jwtDecoder(JWKSource<SecurityContext> jwkSource) {
        return OAuth2AuthorizationServerConfiguration.jwtDecoder(jwkSource);
    }

    @Bean
    public PasswordEncoder passwordEncoder() {
        return Pbkdf2PasswordEncoder.defaultsForSpringSecurity_v5_8();
    }

    private static void addClientCredentialsClient(List<RegisteredClient> registeredClients,
            PasswordEncoder passwordEncoder, String clientId, String clientSecret, String clientScopes) {
        if (!StringUtils.hasText(clientSecret)) {
            return;
        }

        RegisteredClient.Builder registeredClient = RegisteredClient.withId(UUID.randomUUID().toString())
                .clientId(clientId).clientSecret(passwordEncoder.encode(clientSecret))
                .clientAuthenticationMethod(ClientAuthenticationMethod.CLIENT_SECRET_BASIC)
                .authorizationGrantType(AuthorizationGrantType.CLIENT_CREDENTIALS);

        Arrays.stream(clientScopes.split(",")).map(String::trim).filter(StringUtils::hasText)
                .forEach(registeredClient::scope);

        registeredClients.add(registeredClient.build());
    }

    private static void addConsoleAuthorizationCodeClient(List<RegisteredClient> registeredClients,
            PasswordEncoder passwordEncoder, String clientId, String clientSecret, String clientScopes,
            String redirectUri, String postLogoutRedirectUri, Duration accessTokenTimeToLive,
            Duration refreshTokenTimeToLive) {
        if (!StringUtils.hasText(clientSecret)) {
            return;
        }
        if (!StringUtils.hasText(redirectUri) || !StringUtils.hasText(postLogoutRedirectUri)) {
            throw new IllegalStateException("MicroTx Console redirect URIs must not be blank");
        }
        if (accessTokenTimeToLive.isZero() || accessTokenTimeToLive.isNegative()
                || refreshTokenTimeToLive.isZero() || refreshTokenTimeToLive.isNegative()) {
            throw new IllegalStateException("MicroTx Console token lifetimes must be positive durations");
        }

        RegisteredClient.Builder client = RegisteredClient.withId(UUID.randomUUID().toString()).clientId(clientId)
                .clientSecret(passwordEncoder.encode(clientSecret))
                .clientAuthenticationMethod(ClientAuthenticationMethod.CLIENT_SECRET_BASIC)
                // MicroTx Console 26.1.1 packages Helidon OIDC 4.1.4. Its
                // HTTP/1 code-exchange path has interoperability issues with
                // Azn, so also permit the standard request-body method for
                // this Console client only.
                .clientAuthenticationMethod(ClientAuthenticationMethod.CLIENT_SECRET_POST)
                .authorizationGrantType(AuthorizationGrantType.AUTHORIZATION_CODE)
                .authorizationGrantType(AuthorizationGrantType.REFRESH_TOKEN).redirectUri(redirectUri)
                .postLogoutRedirectUri(postLogoutRedirectUri)
                .clientSettings(ClientSettings.builder().requireProofKey(false).build())
                .tokenSettings(TokenSettings.builder().accessTokenTimeToLive(accessTokenTimeToLive)
                        .refreshTokenTimeToLive(refreshTokenTimeToLive).build());
        if (!MICROTX_LOCAL_ALIAS_REDIRECT_URI.equals(redirectUri)) {
            client.redirectUri(MICROTX_LOCAL_ALIAS_REDIRECT_URI);
        }
        if (!MICROTX_LOCAL_ALIAS_POST_LOGOUT_REDIRECT_URI.equals(postLogoutRedirectUri)) {
            client.postLogoutRedirectUri(MICROTX_LOCAL_ALIAS_POST_LOGOUT_REDIRECT_URI);
        }
        Arrays.stream(clientScopes.split(",")).map(String::trim).filter(StringUtils::hasText).forEach(client::scope);
        registeredClients.add(client.build());
    }

    private static RSAKey generateRsa() {
        KeyPair keyPair = generateRsaKeyPair();
        RSAPublicKey publicKey = (RSAPublicKey) keyPair.getPublic();
        RSAPrivateKey privateKey = (RSAPrivateKey) keyPair.getPrivate();
        return new RSAKey.Builder(publicKey).privateKey(privateKey).keyID(UUID.randomUUID().toString()).build();
    }

    private static RSAKey loadRsa(String privateKeyPath, String publicKeyPath, String keyId) {
        return new RSAKey.Builder(readRsaPublicKey(publicKeyPath)).privateKey(readRsaPrivateKey(privateKeyPath))
                .keyID(keyId).build();
    }

    private static RSAPrivateKey readRsaPrivateKey(String privateKeyPath) {
        try {
            byte[] keyBytes = readPem(privateKeyPath);
            return (RSAPrivateKey) KeyFactory.getInstance("RSA").generatePrivate(new PKCS8EncodedKeySpec(keyBytes));
        } catch (Exception exception) {
            throw new IllegalStateException(
                    "Unable to load authorization server RSA private key from " + privateKeyPath, exception);
        }
    }

    private static RSAPublicKey readRsaPublicKey(String publicKeyPath) {
        try {
            byte[] keyBytes = readPem(publicKeyPath);
            return (RSAPublicKey) KeyFactory.getInstance("RSA").generatePublic(new X509EncodedKeySpec(keyBytes));
        } catch (Exception exception) {
            throw new IllegalStateException("Unable to load authorization server RSA public key from " + publicKeyPath,
                    exception);
        }
    }

    private static byte[] readPem(String keyPath) throws Exception {
        String pem = Files.readString(Path.of(keyPath), StandardCharsets.UTF_8);
        String base64Key = pem.replaceAll("-----BEGIN [A-Z ]+-----", "").replaceAll("-----END [A-Z ]+-----", "")
                .replaceAll("\\s", "");
        return Base64.getDecoder().decode(base64Key);
    }

    private static JWKSource<SecurityContext> jwkSourceFor(RSAKey rsaKey) {
        JWKSet jwkSet = new JWKSet(rsaKey);
        return (jwkSelector, securityContext) -> jwkSelector.select(jwkSet);
    }

    private static KeyPair generateRsaKeyPair() {
        try {
            KeyPairGenerator keyPairGenerator = KeyPairGenerator.getInstance("RSA");
            keyPairGenerator.initialize(3072);
            return keyPairGenerator.generateKeyPair();
        } catch (Exception exception) {
            throw new IllegalStateException("Unable to generate authorization server RSA key", exception);
        }
    }

}
