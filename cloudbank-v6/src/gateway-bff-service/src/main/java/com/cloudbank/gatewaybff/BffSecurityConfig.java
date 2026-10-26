// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.

package com.cloudbank.gatewaybff;

import jakarta.servlet.http.HttpServletResponse;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.MediaType;
import org.springframework.http.HttpMethod;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.oauth2.client.registration.ClientRegistration;
import org.springframework.security.oauth2.client.registration.ClientRegistrationRepository;
import org.springframework.security.oauth2.client.registration.InMemoryClientRegistrationRepository;
import org.springframework.security.oauth2.client.web.DefaultOAuth2AuthorizationRequestResolver;
import org.springframework.security.oauth2.client.web.HttpSessionOAuth2AuthorizedClientRepository;
import org.springframework.security.oauth2.client.web.OAuth2AuthorizationRequestCustomizers;
import org.springframework.security.oauth2.client.web.OAuth2AuthorizedClientRepository;
import org.springframework.security.oauth2.core.AuthorizationGrantType;
import org.springframework.security.oauth2.core.ClientAuthenticationMethod;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtValidators;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;
import org.springframework.security.oauth2.core.OAuth2TokenValidatorResult;
import org.springframework.security.oauth2.core.OAuth2Error;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.csrf.CsrfTokenRequestAttributeHandler;
import org.springframework.security.web.csrf.HttpSessionCsrfTokenRepository;

@Configuration
class BffSecurityConfig {
    static final String REGISTRATION_ID = "cloudbank-bff";

    @Bean
    ClientRegistrationRepository clientRegistrationRepository(
            @Value("${BFF_OAUTH_CLIENT_ID:cloudbank-bff-client}") String clientId,
            @Value("${BFF_OAUTH_CLIENT_SECRET}") String clientSecret,
            @Value("${BFF_CALLBACK_URI}") String callbackUri,
            @Value("${BFF_ISSUER_URI}") String issuerUri,
            @Value("${BFF_AUTHORIZATION_URI}") String authorizationUri,
            @Value("${BFF_TOKEN_URI}") String tokenUri,
            @Value("${BFF_JWK_SET_URI}") String jwkSetUri,
            @Value("${BFF_USERINFO_URI}") String userInfoUri) {
        ClientRegistration client = ClientRegistration.withRegistrationId(REGISTRATION_ID)
                .clientId(clientId)
                .clientSecret(clientSecret)
                .clientAuthenticationMethod(ClientAuthenticationMethod.CLIENT_SECRET_BASIC)
                .authorizationGrantType(AuthorizationGrantType.AUTHORIZATION_CODE)
                .redirectUri(callbackUri)
                .scope("openid", "cloudbank.read", "cloudbank.write")
                .authorizationUri(authorizationUri)
                .tokenUri(tokenUri)
                .jwkSetUri(jwkSetUri)
                .issuerUri(issuerUri)
                .userInfoUri(userInfoUri)
                .userNameAttributeName("sub")
                .clientName("CloudBank AI BFF")
                .build();
        return new InMemoryClientRegistrationRepository(client);
    }

    @Bean
    OAuth2AuthorizedClientRepository authorizedClientRepository() {
        return new HttpSessionOAuth2AuthorizedClientRepository();
    }

    @Bean
    JwtDecoder accessTokenDecoder(@Value("${cloudbank.bff.jwk-set-uri}") String jwkSetUri,
            @Value("${cloudbank.bff.issuer-uri}") String issuerUri,
            @Value("${cloudbank.bff.audience}") String audience) {
        NimbusJwtDecoder decoder = NimbusJwtDecoder.withJwkSetUri(jwkSetUri).build();
        decoder.setJwtValidator(new org.springframework.security.oauth2.core.DelegatingOAuth2TokenValidator<>(
                JwtValidators.createDefaultWithIssuer(issuerUri),
                jwt -> jwt.getAudience().contains(audience) ? OAuth2TokenValidatorResult.success()
                        : OAuth2TokenValidatorResult.failure(new OAuth2Error("invalid_audience"))));
        return decoder;
    }

    @Bean
    SecurityFilterChain securityFilterChain(HttpSecurity http, ClientRegistrationRepository registrations,
            OAuth2AuthorizedClientRepository authorizedClients, SessionIdentity identity) throws Exception {
        DefaultOAuth2AuthorizationRequestResolver requestResolver =
                new DefaultOAuth2AuthorizationRequestResolver(registrations, "/oauth2/authorization");
        requestResolver.setAuthorizationRequestCustomizer(OAuth2AuthorizationRequestCustomizers.withPkce());
        HttpSessionCsrfTokenRepository csrfRepository = new HttpSessionCsrfTokenRepository();
        csrfRepository.setHeaderName("X-CSRF-TOKEN");

        http.authorizeHttpRequests(auth -> auth
                .requestMatchers("/actuator/health", "/actuator/health/**", "/actuator/info",
                        "/bff/auth/login", "/oauth2/authorization/**", "/bff/auth/callback").permitAll()
                .requestMatchers("/bff/api/v1/session", "/bff/api/v1/applications", "/bff/auth/logout")
                .authenticated()
                .requestMatchers(HttpMethod.PUT, "/bff/api/v1/applications/*/documents/*/content").authenticated()
                .requestMatchers(HttpMethod.POST, "/bff/api/v1/applications/*/workflow-start").authenticated()
                .requestMatchers(HttpMethod.GET, "/bff/api/v1/manual-review/tasks",
                        "/bff/api/v1/manual-review/tasks/*").authenticated()
                .requestMatchers(HttpMethod.POST, "/bff/api/v1/manual-review/tasks/*/resolution").authenticated()
                .anyRequest().denyAll())
                .oauth2Login(oauth -> oauth.authorizedClientRepository(authorizedClients)
                        .loginPage("/bff/auth/login")
                        .authorizationEndpoint(endpoint -> endpoint.authorizationRequestResolver(requestResolver))
                        .redirectionEndpoint(endpoint -> endpoint.baseUri("/bff/auth/callback"))
                        .successHandler((request, response, authentication) -> {
                            try {
                                identity.require(authentication, request);
                                response.sendRedirect("/demo");
                            } catch (RuntimeException denied) {
                                request.getSession().invalidate();
                                response.sendError(HttpServletResponse.SC_FORBIDDEN);
                            }
                        })
                        .failureHandler((request, response, error) -> {
                            if (request.getSession(false) != null) {
                                request.getSession(false).invalidate();
                            }
                            response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
                            response.setContentType(MediaType.APPLICATION_JSON_VALUE);
                            response.getWriter().write("{\"code\":\"LOGIN_FAILED\",\"message\":\"Sign in failed\","
                                    + "\"correlationId\":null,\"retryable\":false,"
                                    + "\"authorizationStatus\":\"UNAUTHENTICATED\"}");
                        }))
                .oauth2Client(client -> client.authorizedClientRepository(authorizedClients))
                .logout(logout -> logout.disable())
                .csrf(csrf -> csrf.csrfTokenRepository(csrfRepository)
                        .csrfTokenRequestHandler(new CsrfTokenRequestAttributeHandler()))
                .exceptionHandling(exceptions -> exceptions.authenticationEntryPoint((request, response, error) -> {
                    response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
                    response.setContentType(MediaType.APPLICATION_JSON_VALUE);
                    response.getWriter().write("{\"code\":\"UNAUTHENTICATED\",\"message\":\"Sign in required\","
                            + "\"correlationId\":null,\"retryable\":false,\"authorizationStatus\":\"UNAUTHENTICATED\"}");
                }).accessDeniedHandler((request, response, error) -> {
                    response.setStatus(HttpServletResponse.SC_FORBIDDEN);
                    response.setContentType(MediaType.APPLICATION_JSON_VALUE);
                    response.getWriter().write("{\"code\":\"FORBIDDEN\",\"message\":\"Access denied\","
                            + "\"correlationId\":null,\"retryable\":false,\"authorizationStatus\":\"DENIED\"}");
                }));
        return http.build();
    }
}
