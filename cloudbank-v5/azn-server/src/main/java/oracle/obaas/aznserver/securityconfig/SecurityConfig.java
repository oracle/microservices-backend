// Copyright (c) 2023, 2026, Oracle and/or its affiliates.

package oracle.obaas.aznserver.securityconfig;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
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
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnMissingBean;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.security.autoconfigure.actuate.web.servlet.EndpointRequest;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.annotation.Order;
import org.springframework.http.MediaType;
import org.springframework.security.access.expression.method.DefaultMethodSecurityExpressionHandler;
import org.springframework.security.access.expression.method.MethodSecurityExpressionHandler;
import org.springframework.security.access.hierarchicalroles.RoleHierarchy;
import org.springframework.security.access.hierarchicalroles.RoleHierarchyImpl;
import org.springframework.security.authentication.dao.DaoAuthenticationProvider;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.method.configuration.EnableMethodSecurity;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.annotation.web.configuration.OAuth2AuthorizationServerConfiguration;
import org.springframework.security.config.annotation.web.configurers.oauth2.server.authorization.OAuth2AuthorizationServerConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.oauth2.core.AuthorizationGrantType;
import org.springframework.security.oauth2.core.ClientAuthenticationMethod;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.server.authorization.OAuth2TokenType;
import org.springframework.security.oauth2.server.authorization.client.InMemoryRegisteredClientRepository;
import org.springframework.security.oauth2.server.authorization.client.RegisteredClient;
import org.springframework.security.oauth2.server.authorization.client.RegisteredClientRepository;
import org.springframework.security.oauth2.server.authorization.settings.AuthorizationServerSettings;
import org.springframework.security.oauth2.server.authorization.settings.ClientSettings;
import org.springframework.security.oauth2.server.authorization.token.JwtEncodingContext;
import org.springframework.security.oauth2.server.authorization.token.OAuth2TokenCustomizer;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.LoginUrlAuthenticationEntryPoint;
import org.springframework.security.web.util.matcher.MediaTypeRequestMatcher;
import org.springframework.util.StringUtils;

@Configuration
@EnableWebSecurity(debug = false)
@EnableMethodSecurity
@Slf4j
public class SecurityConfig {

    private static final String DEFAULT_CLIENT_ID = "cloudbank-client";
    private static final String DEFAULT_CLIENT_SCOPES = "openid,cloudbank.read,cloudbank.write,cloudbank.transfer";
    private static final String DEFAULT_SERVICE_CLIENT_ID = "cloudbank-service-client";
    private static final String DEFAULT_SERVICE_CLIENT_SCOPES = "cloudbank.internal";
    private static final String DEFAULT_TEST_CLIENT_ID = "cloudbank-test-client";
    private static final String DEFAULT_TEST_CLIENT_SCOPES = "cloudbank.test";
    private static final String DEFAULT_ADMIN_CLIENT_ID = "cloudbank-admin-client";
    private static final String DEFAULT_ADMIN_CLIENT_SCOPES = "cloudbank.admin";
    private static final String DEFAULT_MICROTX_CLIENT_ID = "microtx-workflow-client";
    private static final String DEFAULT_MICROTX_CLIENT_SCOPES = "microtx.workflow";
    private static final String DEFAULT_MICROTX_ROLES = "microtx-conductor-user,microtx-conductor-worker";

    public static final String ROLE_HIERARCHY = "ROLE_ADMIN > ROLE_USER\n"
            + "ROLE_ADMIN > ROLE_CONFIG_EDITOR\n"
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
     * Configure method security to use the role hierarchy.
     * 
     * @param roleHierarchy injected by Spring.
     * @return The MethodSecurityExpressionHandler.
     */
    @Bean
    public MethodSecurityExpressionHandler methodSecurityExpressionHandler(RoleHierarchy roleHierarchy) {
        DefaultMethodSecurityExpressionHandler expressionHandler = new DefaultMethodSecurityExpressionHandler();
        expressionHandler.setRoleHierarchy(roleHierarchy);
        return expressionHandler;
    }
    
    /**
     * Authorization Server endpoints use their own filter chain so OAuth protocol
     * handling does not inherit API-specific stateless settings.
     *
     * @param http HttpSecurity injected by Spring.
     * @return the SecurityFilterChain.
     * @throws Exception if unable to create the chain.
     */
    @Bean
    @Order(1)
    public SecurityFilterChain authorizationServerSecurityFilterChain(HttpSecurity http)
            throws Exception {
        log.debug("In authorizationServerSecurityFilterChain");
        OAuth2AuthorizationServerConfigurer authorizationServerConfigurer =
                new OAuth2AuthorizationServerConfigurer();

        http
            .securityMatcher(authorizationServerConfigurer.getEndpointsMatcher())
            .with(authorizationServerConfigurer, authorizationServer ->
                authorizationServer.oidc(Customizer.withDefaults()))
            .authorizeHttpRequests((authorize) -> authorize
                .requestMatchers("/.well-known/**", "/oauth2/jwks").permitAll()
                .anyRequest().authenticated())
            .csrf((csrf) -> csrf.ignoringRequestMatchers(authorizationServerConfigurer.getEndpointsMatcher()))
            .exceptionHandling((exceptions) -> exceptions.defaultAuthenticationEntryPointFor(
                new LoginUrlAuthenticationEntryPoint("/login"),
                new MediaTypeRequestMatcher(MediaType.TEXT_HTML)));
        return http.build();
    }

    /** Create a SecurityFilterChain to allow anonymous access to actuator endpoints.
     * @param http HttpSecurity injected by Spring. 
     * @return the SecurityFilterChain.
     * @throws Exception if unable to create the chain.
     */
    @Bean
    @Order(2)
    public SecurityFilterChain actuatorSecurityFilterChain(HttpSecurity http)
        throws Exception {
        log.debug("In actuatorSecurityFilterChain");
        http
            .securityMatcher(EndpointRequest.toAnyEndpoint())
            .authorizeHttpRequests((authorize) -> authorize
                .requestMatchers(EndpointRequest.to("health", "info")).permitAll()
                .anyRequest().hasRole("ACTUATOR"))
            .httpBasic(Customizer.withDefaults());
        return http.build();
    }

    /**
     * Create a SecurityFilterChain for the user-management API.
     * @param http HttpSecurity injected by Spring. 
     * @param userDetailsService the JPA-backed user details service.
     * @return the SecurityFilterChain.
     * @throws Exception if unable to create the chain.
     */
    @Bean
    @Order(3)
    public SecurityFilterChain apiSecurityFilterChain(HttpSecurity http, UserDetailsService userDetailsService)
            throws Exception {
        log.debug("In apiSecurityFilterChain");
        http
            .securityMatcher("/user/api/**", "/error/**")
            .authorizeHttpRequests((authorize) -> authorize
                .requestMatchers("/error/**").permitAll()
                .requestMatchers("/user/api/v1/ping").permitAll()
                .anyRequest().authenticated()
            )
            .sessionManagement(session ->
                session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .httpBasic(Customizer.withDefaults())
            .userDetailsService(userDetailsService);
        // The user-management API is stateless and does not use browser sessions or cookies.
        http.csrf(csrf -> csrf.disable());
        return http.build();
    }

    /**
     * Create the fallback browser login chain used by authorization-code flows.
     * @param http HttpSecurity injected by Spring.
     * @return the SecurityFilterChain.
     * @throws Exception if unable to create the chain.
     */
    @Bean
    @Order(4)
    public SecurityFilterChain defaultSecurityFilterChain(HttpSecurity http)
            throws Exception {
        log.debug("In defaultSecurityFilterChain");
        http
            .authorizeHttpRequests((authorize) -> authorize.anyRequest().authenticated())
            .formLogin(Customizer.withDefaults())
            .httpBasic(Customizer.withDefaults());
        return http.build();
    }

    /**
     * Create an Authentication Provider for our UserDetailsService.
     * @param userDetailsService the JPA-backed user details service.
     * @param passwordEncoder password encoder for stored password hashes.
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
     * Create an opt-in local client for test and developer-only contexts.
     *
     * Production deployments should configure registered clients explicitly using
     * Spring Boot's authorization-server client properties.
     *
     * @param passwordEncoder password encoder for the client secret.
     * @param clientId configured client id.
     * @param clientSecret configured client secret.
     * @param redirectUri configured authorization-code redirect URI.
     * @param clientScopes comma-delimited OAuth scopes granted to the default client.
     * @param serviceClientId service-to-service OAuth client id.
     * @param serviceClientSecret service-to-service OAuth client secret.
     * @param serviceClientScopes comma-delimited OAuth scopes granted to the service client.
     * @param testClientId test OAuth client id.
     * @param testClientSecret test OAuth client secret.
     * @param testClientScopes comma-delimited OAuth scopes granted to the test client.
     * @param adminClientId admin OAuth client id.
     * @param adminClientSecret admin OAuth client secret.
     * @param adminClientScopes comma-delimited OAuth scopes granted to the admin client.
     * @return a local RegisteredClientRepository.
     */
    @Bean
    @ConditionalOnMissingBean
    @ConditionalOnProperty(prefix = "azn.authorization-server.default-client", name = "enabled",
            havingValue = "true")
    public RegisteredClientRepository localRegisteredClientRepository(PasswordEncoder passwordEncoder,
            @Value("${azn.authorization-server.default-client.id:" + DEFAULT_CLIENT_ID + "}") String clientId,
            @Value("${azn.authorization-server.default-client.secret:}") String clientSecret,
            @Value("${azn.authorization-server.default-client.redirect-uri:"
                    + "http://127.0.0.1:8080/login/oauth2/code/" + DEFAULT_CLIENT_ID + "}") String redirectUri,
            @Value("${azn.authorization-server.default-client.scopes:" + DEFAULT_CLIENT_SCOPES + "}")
                    String clientScopes,
            @Value("${azn.authorization-server.service-client.id:" + DEFAULT_SERVICE_CLIENT_ID + "}")
                    String serviceClientId,
            @Value("${azn.authorization-server.service-client.secret:}") String serviceClientSecret,
            @Value("${azn.authorization-server.service-client.scopes:" + DEFAULT_SERVICE_CLIENT_SCOPES + "}")
                    String serviceClientScopes,
            @Value("${azn.authorization-server.test-client.id:" + DEFAULT_TEST_CLIENT_ID + "}") String testClientId,
            @Value("${azn.authorization-server.test-client.secret:}") String testClientSecret,
            @Value("${azn.authorization-server.test-client.scopes:" + DEFAULT_TEST_CLIENT_SCOPES + "}")
                    String testClientScopes,
            @Value("${azn.authorization-server.admin-client.id:" + DEFAULT_ADMIN_CLIENT_ID + "}") String adminClientId,
            @Value("${azn.authorization-server.admin-client.secret:}") String adminClientSecret,
            @Value("${azn.authorization-server.admin-client.scopes:" + DEFAULT_ADMIN_CLIENT_SCOPES + "}")
                    String adminClientScopes,
            @Value("${azn.authorization-server.microtx-client.id:" + DEFAULT_MICROTX_CLIENT_ID + "}")
                    String microtxClientId,
            @Value("${azn.authorization-server.microtx-client.secret:}") String microtxClientSecret,
            @Value("${azn.authorization-server.microtx-client.scopes:" + DEFAULT_MICROTX_CLIENT_SCOPES + "}")
                    String microtxClientScopes) {
        if (!StringUtils.hasText(clientSecret)) {
            throw new IllegalStateException("azn.authorization-server.default-client.secret must be set when "
                    + "azn.authorization-server.default-client.enabled=true");
        }
        List<RegisteredClient> registeredClients = new ArrayList<>();
        RegisteredClient.Builder registeredClient = RegisteredClient.withId(UUID.randomUUID().toString())
                .clientId(clientId)
                .clientSecret(passwordEncoder.encode(clientSecret))
                .clientAuthenticationMethod(ClientAuthenticationMethod.CLIENT_SECRET_BASIC)
                .authorizationGrantType(AuthorizationGrantType.CLIENT_CREDENTIALS)
                .authorizationGrantType(AuthorizationGrantType.AUTHORIZATION_CODE)
                .authorizationGrantType(AuthorizationGrantType.REFRESH_TOKEN)
                .redirectUri(redirectUri)
                .clientSettings(ClientSettings.builder().requireProofKey(true).build());

        Arrays.stream(clientScopes.split(","))
                .map(String::trim)
                .filter(StringUtils::hasText)
                .forEach(registeredClient::scope);
        registeredClients.add(registeredClient.build());

        addClientCredentialsClient(registeredClients, passwordEncoder,
                serviceClientId, serviceClientSecret, serviceClientScopes);
        addClientCredentialsClient(registeredClients, passwordEncoder,
                testClientId, testClientSecret, testClientScopes);
        addClientCredentialsClient(registeredClients, passwordEncoder,
                adminClientId, adminClientSecret, adminClientScopes);
        addClientCredentialsClient(registeredClients, passwordEncoder,
                microtxClientId, microtxClientSecret, microtxClientScopes);

        return new InMemoryRegisteredClientRepository(registeredClients);
    }

    /**
     * Create an instance of AuthorizationServerSettings to configure Spring Authorization Server.
     * @return the AuthorizationServerSettings
     */
    @Bean
    public AuthorizationServerSettings authorizationServerSettings(
            @Value("${azn.authorization-server.issuer:http://localhost:8080}") String issuer) {
        return AuthorizationServerSettings.builder().issuer(issuer).build();
    }

    /**
     * Add the role claim expected by MicroTx Workflows to the dedicated client token.
     *
     * @param microtxClientId configured MicroTx client id.
     * @param microtxRoles comma-delimited role names.
     * @return token customizer.
     */
    @Bean
    public OAuth2TokenCustomizer<JwtEncodingContext> jwtTokenCustomizer(
            @Value("${azn.authorization-server.microtx-client.id:" + DEFAULT_MICROTX_CLIENT_ID + "}")
                    String microtxClientId,
            @Value("${azn.authorization-server.microtx-client.roles:" + DEFAULT_MICROTX_ROLES + "}")
                    String microtxRoles,
            @Value("${azn.authorization-server.microtx-client.audience:microtx-workflow}")
                    String microtxAudience) {
        List<String> roles = Arrays.stream(microtxRoles.split(","))
                .map(String::trim)
                .filter(StringUtils::hasText)
                .toList();
        return context -> {
            if (OAuth2TokenType.ACCESS_TOKEN.equals(context.getTokenType())
                && microtxClientId.equals(context.getRegisteredClient().getClientId())) {
                context.getClaims().claim("roles", roles);
                context.getClaims().audience(List.of(microtxAudience));
            }
        };
    }

    /**
     * Provide persistent signing keys when a deployment mounts key material.
     *
     * @param privateKeyPath path to a PKCS#8 PEM-encoded RSA private key.
     * @param publicKeyPath path to an X.509 PEM-encoded RSA public key.
     * @param keyId stable key id to publish in the JWK set and token headers.
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
     * Provide process-local signing keys for development and tests.
     *
     * Production deployments should replace this bean with persistent key material
     * so tokens remain verifiable across restarts and rolling deploys.
     *
     * @return the JWK source.
     */
    @Bean
    @ConditionalOnMissingBean
    public JWKSource<SecurityContext> jwkSource() {
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
        return new BCryptPasswordEncoder();
    }

    private static void addClientCredentialsClient(List<RegisteredClient> registeredClients,
            PasswordEncoder passwordEncoder, String clientId, String clientSecret, String clientScopes) {
        if (!StringUtils.hasText(clientSecret)) {
            return;
        }

        RegisteredClient.Builder registeredClient = RegisteredClient.withId(UUID.randomUUID().toString())
                .clientId(clientId)
                .clientSecret(passwordEncoder.encode(clientSecret))
                .clientAuthenticationMethod(ClientAuthenticationMethod.CLIENT_SECRET_BASIC)
                .authorizationGrantType(AuthorizationGrantType.CLIENT_CREDENTIALS);

        Arrays.stream(clientScopes.split(","))
                .map(String::trim)
                .filter(StringUtils::hasText)
                .forEach(registeredClient::scope);

        registeredClients.add(registeredClient.build());
    }

    private static RSAKey generateRsa() {
        KeyPair keyPair = generateRsaKeyPair();
        RSAPublicKey publicKey = (RSAPublicKey) keyPair.getPublic();
        RSAPrivateKey privateKey = (RSAPrivateKey) keyPair.getPrivate();
        return new RSAKey.Builder(publicKey)
                .privateKey(privateKey)
                .keyID(UUID.randomUUID().toString())
                .build();
    }

    private static RSAKey loadRsa(String privateKeyPath, String publicKeyPath, String keyId) {
        return new RSAKey.Builder(readRsaPublicKey(publicKeyPath))
                .privateKey(readRsaPrivateKey(privateKeyPath))
                .keyID(keyId)
                .build();
    }

    private static RSAPrivateKey readRsaPrivateKey(String privateKeyPath) {
        try {
            byte[] keyBytes = readPem(privateKeyPath);
            return (RSAPrivateKey) KeyFactory.getInstance("RSA")
                    .generatePrivate(new PKCS8EncodedKeySpec(keyBytes));
        } catch (Exception exception) {
            throw new IllegalStateException("Unable to load authorization server RSA private key from "
                    + privateKeyPath, exception);
        }
    }

    private static RSAPublicKey readRsaPublicKey(String publicKeyPath) {
        try {
            byte[] keyBytes = readPem(publicKeyPath);
            return (RSAPublicKey) KeyFactory.getInstance("RSA")
                    .generatePublic(new X509EncodedKeySpec(keyBytes));
        } catch (Exception exception) {
            throw new IllegalStateException("Unable to load authorization server RSA public key from "
                    + publicKeyPath, exception);
        }
    }

    private static byte[] readPem(String keyPath) throws Exception {
        String pem = Files.readString(Path.of(keyPath), StandardCharsets.UTF_8);
        String base64Key = pem
                .replaceAll("-----BEGIN [A-Z ]+-----", "")
                .replaceAll("-----END [A-Z ]+-----", "")
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
