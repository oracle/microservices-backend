// Copyright (c) 2026, Oracle and/or its affiliates.

package com.example.common.security;

import feign.RequestInterceptor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.AutoConfiguration;
import org.springframework.boot.autoconfigure.condition.ConditionalOnBean;
import org.springframework.boot.autoconfigure.condition.ConditionalOnClass;
import org.springframework.boot.autoconfigure.condition.ConditionalOnMissingBean;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.autoconfigure.condition.ConditionalOnWebApplication;
import org.springframework.boot.autoconfigure.condition.ConditionalOnWebApplication.Type;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.boot.restclient.RestTemplateCustomizer;
import org.springframework.boot.security.autoconfigure.actuate.web.servlet.EndpointRequest;
import org.springframework.context.annotation.Bean;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.web.client.RestClient;
import tools.jackson.databind.ObjectMapper;

@AutoConfiguration
@ConditionalOnClass(SecurityFilterChain.class)
@ConditionalOnWebApplication(type = Type.SERVLET)
@EnableConfigurationProperties(CloudBankServiceTokenProperties.class)
public class CloudBankSecurityAutoConfiguration {

    private static final String READ_SCOPE = "SCOPE_cloudbank.read";
    private static final String WRITE_SCOPE = "SCOPE_cloudbank.write";
    private static final String ADMIN_SCOPE = "SCOPE_cloudbank.admin";
    private static final String TRANSFER_SCOPE = "SCOPE_cloudbank.transfer";
    private static final String INTERNAL_SCOPE = "SCOPE_cloudbank.internal";
    private static final String TEST_SCOPE = "SCOPE_cloudbank.test";

    /**
     * Shared CloudBank HTTP security policy.
     *
     * @param http Spring Security HTTP configuration.
     * @param requireInternalToken protects internal service callback endpoints.
     * @return configured security filter chain.
     * @throws Exception when the filter chain cannot be built.
     */
    @Bean
    @ConditionalOnMissingBean(SecurityFilterChain.class)
    public SecurityFilterChain cloudBankSecurityFilterChain(HttpSecurity http,
            @Value("${cloudbank.security.require-internal-token:true}") boolean requireInternalToken)
            throws Exception {
        http
            .csrf(csrf -> csrf.disable())
            .sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS));

        http
            .authorizeHttpRequests(authorize -> {
                authorize
                    .requestMatchers(EndpointRequest.to("health", "info")).permitAll()
                    .requestMatchers(EndpointRequest.toAnyEndpoint()).authenticated()
                    .requestMatchers("/error", "/error/**").permitAll();

                if (requireInternalToken) {
                    authorizeInternalEndpoints(authorize, INTERNAL_SCOPE);
                } else {
                    permitInternalEndpoints(authorize);
                }

                authorize
                    .requestMatchers(HttpMethod.GET, "/api/v1/accounts").hasAnyAuthority(READ_SCOPE, INTERNAL_SCOPE)
                    .requestMatchers(HttpMethod.GET, "/api/v1/account/**").hasAnyAuthority(READ_SCOPE, INTERNAL_SCOPE)
                    .requestMatchers(HttpMethod.POST, "/api/v1/account").hasAuthority(WRITE_SCOPE)
                    .requestMatchers(HttpMethod.DELETE, "/api/v1/account/**").hasAuthority(ADMIN_SCOPE)
                    .requestMatchers(HttpMethod.GET, "/api/v1/customer/**").hasAnyAuthority(READ_SCOPE, INTERNAL_SCOPE)
                    .requestMatchers(HttpMethod.GET, "/api/v1/customer").hasAnyAuthority(READ_SCOPE, INTERNAL_SCOPE)
                    .requestMatchers(HttpMethod.POST, "/api/v1/customer").hasAuthority(WRITE_SCOPE)
                    .requestMatchers(HttpMethod.POST, "/api/v1/customer/applyLoan/**").hasAuthority(WRITE_SCOPE)
                    .requestMatchers(HttpMethod.PUT, "/api/v1/customer/**").hasAuthority(WRITE_SCOPE)
                    .requestMatchers(HttpMethod.DELETE, "/api/v1/customer/**").hasAuthority(ADMIN_SCOPE)
                    .requestMatchers(HttpMethod.GET, "/api/v1/creditscore").hasAuthority(READ_SCOPE)
                    .requestMatchers(HttpMethod.GET, "/hello").hasAuthority(READ_SCOPE)
                    .requestMatchers(HttpMethod.POST, "/chat").hasAuthority(READ_SCOPE)
                    .requestMatchers(HttpMethod.POST, "/transfer").hasAuthority(TRANSFER_SCOPE)
                    .requestMatchers(HttpMethod.POST, "/api/v1/testrunner/**").hasAuthority(TEST_SCOPE)
                    .anyRequest().authenticated();
            })
            .oauth2ResourceServer(oauth2 -> oauth2.jwt(Customizer.withDefaults()));

        return http.build();
    }

    /**
     * Creates the shared service-token provider.
     *
     * @param properties service-token properties.
     * @param restClientBuilder builder used for token endpoint calls.
     * @param objectMapper JSON parser.
     * @return service-token provider.
     */
    @Bean
    @ConditionalOnProperty(prefix = "cloudbank.security.service-token", name = "enabled", havingValue = "true")
    @ConditionalOnMissingBean
    public CloudBankServiceTokenProvider cloudBankServiceTokenProvider(
            CloudBankServiceTokenProperties properties, RestClient.Builder restClientBuilder,
            ObjectMapper objectMapper) {
        return new CloudBankServiceTokenProvider(properties, restClientBuilder, objectMapper);
    }

    /**
     * Adds service-token authorization to managed RestTemplate clients.
     *
     * @param tokenProvider service-token provider.
     * @return RestTemplate customizer.
     */
    @Bean
    @ConditionalOnBean(CloudBankServiceTokenProvider.class)
    public RestTemplateCustomizer cloudBankServiceTokenRestTemplateCustomizer(
            CloudBankServiceTokenProvider tokenProvider) {
        return restTemplate -> restTemplate.getInterceptors().add((request, body, execution) -> {
            if (request.getHeaders().getFirst(HttpHeaders.AUTHORIZATION) == null) {
                request.getHeaders().set(HttpHeaders.AUTHORIZATION, tokenProvider.getAuthorizationHeader());
            }
            return execution.execute(request, body);
        });
    }

    /**
     * Adds service-token authorization to Feign clients.
     *
     * @param tokenProvider service-token provider.
     * @return Feign request interceptor.
     */
    @Bean
    @ConditionalOnClass(RequestInterceptor.class)
    @ConditionalOnBean(CloudBankServiceTokenProvider.class)
    public RequestInterceptor cloudBankServiceTokenFeignRequestInterceptor(
            CloudBankServiceTokenProvider tokenProvider) {
        return template -> {
            if (!template.headers().containsKey(HttpHeaders.AUTHORIZATION)) {
                template.header(HttpHeaders.AUTHORIZATION, tokenProvider.getAuthorizationHeader());
            }
        };
    }

    private static void authorizeInternalEndpoints(
            org.springframework.security.config.annotation.web.configurers.AuthorizeHttpRequestsConfigurer<
                    HttpSecurity>.AuthorizationManagerRequestMatcherRegistry authorize,
            String scope) {
        authorize
            .requestMatchers(HttpMethod.POST, "/api/v1/account/journal").hasAuthority(scope)
            .requestMatchers(HttpMethod.POST, "/api/v1/account/journal/*/clear").hasAuthority(scope)
            .requestMatchers(HttpMethod.POST, "/deposit", "/withdraw").hasAuthority(scope)
            .requestMatchers(HttpMethod.POST, "/confirm", "/cancel", "/processconfirm", "/processcancel")
            .hasAuthority(scope)
            .requestMatchers("/deposit/**", "/withdraw/**").permitAll();
    }

    private static void permitInternalEndpoints(
            org.springframework.security.config.annotation.web.configurers.AuthorizeHttpRequestsConfigurer<
                    HttpSecurity>.AuthorizationManagerRequestMatcherRegistry authorize) {
        authorize
            .requestMatchers(HttpMethod.POST, "/api/v1/account/journal").permitAll()
            .requestMatchers(HttpMethod.POST, "/api/v1/account/journal/*/clear").permitAll()
            .requestMatchers("/deposit", "/deposit/**", "/withdraw", "/withdraw/**").permitAll()
            .requestMatchers(HttpMethod.POST, "/confirm", "/cancel", "/processconfirm", "/processcancel")
            .permitAll();
    }
}
