// Copyright (c) 2026, Oracle and/or its affiliates.

package com.example.common.security;

import java.net.URI;

import feign.RequestInterceptor;
import feign.RequestTemplate;
import org.junit.jupiter.api.Test;
import org.springframework.boot.restclient.RestTemplateCustomizer;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.mock.http.client.MockClientHttpRequest;
import org.springframework.mock.http.client.MockClientHttpResponse;
import org.springframework.web.client.RestTemplate;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class CloudBankServiceTokenInterceptorTest {

    @Test
    void restTemplateInterceptorDoesNotOverwriteExistingAuthorizationHeader() throws Exception {
        CloudBankServiceTokenProvider tokenProvider = mock(CloudBankServiceTokenProvider.class);
        RestTemplateCustomizer customizer = new CloudBankSecurityAutoConfiguration()
                .cloudBankServiceTokenRestTemplateCustomizer(tokenProvider);
        RestTemplate restTemplate = new RestTemplate();
        customizer.customize(restTemplate);
        MockClientHttpRequest request = new MockClientHttpRequest(HttpMethod.GET, URI.create("http://account"));
        request.getHeaders().setBearerAuth("caller-token");

        restTemplate.getInterceptors().getFirst().intercept(request, new byte[0], (httpRequest, body) -> {
            assertThat(httpRequest.getHeaders().getFirst(HttpHeaders.AUTHORIZATION))
                    .isEqualTo("Bearer caller-token");
            return new MockClientHttpResponse(new byte[0], HttpStatus.OK);
        });

        verify(tokenProvider, never()).getAuthorizationHeader();
    }

    @Test
    void restTemplateInterceptorAddsServiceTokenWhenAuthorizationHeaderIsAbsent() throws Exception {
        CloudBankServiceTokenProvider tokenProvider = mock(CloudBankServiceTokenProvider.class);
        when(tokenProvider.getAuthorizationHeader()).thenReturn("Bearer service-token");
        RestTemplateCustomizer customizer = new CloudBankSecurityAutoConfiguration()
                .cloudBankServiceTokenRestTemplateCustomizer(tokenProvider);
        RestTemplate restTemplate = new RestTemplate();
        customizer.customize(restTemplate);
        MockClientHttpRequest request = new MockClientHttpRequest(HttpMethod.GET, URI.create("http://account"));

        restTemplate.getInterceptors().getFirst().intercept(request, new byte[0], (httpRequest, body) -> {
            assertThat(httpRequest.getHeaders().getFirst(HttpHeaders.AUTHORIZATION))
                    .isEqualTo("Bearer service-token");
            return new MockClientHttpResponse(new byte[0], HttpStatus.OK);
        });
    }

    @Test
    void feignInterceptorDoesNotOverwriteExistingAuthorizationHeader() {
        CloudBankServiceTokenProvider tokenProvider = mock(CloudBankServiceTokenProvider.class);
        RequestInterceptor interceptor = new CloudBankSecurityAutoConfiguration()
                .cloudBankServiceTokenFeignRequestInterceptor(tokenProvider);
        RequestTemplate requestTemplate = new RequestTemplate();
        requestTemplate.header(HttpHeaders.AUTHORIZATION, "Bearer caller-token");

        interceptor.apply(requestTemplate);

        assertThat(requestTemplate.headers().get(HttpHeaders.AUTHORIZATION)).containsExactly("Bearer caller-token");
        verify(tokenProvider, never()).getAuthorizationHeader();
    }

    @Test
    void feignInterceptorAddsServiceTokenWhenAuthorizationHeaderIsAbsent() {
        CloudBankServiceTokenProvider tokenProvider = mock(CloudBankServiceTokenProvider.class);
        when(tokenProvider.getAuthorizationHeader()).thenReturn("Bearer service-token");
        RequestInterceptor interceptor = new CloudBankSecurityAutoConfiguration()
                .cloudBankServiceTokenFeignRequestInterceptor(tokenProvider);
        RequestTemplate requestTemplate = new RequestTemplate();

        interceptor.apply(requestTemplate);

        assertThat(requestTemplate.headers().get(HttpHeaders.AUTHORIZATION)).containsExactly("Bearer service-token");
    }
}
