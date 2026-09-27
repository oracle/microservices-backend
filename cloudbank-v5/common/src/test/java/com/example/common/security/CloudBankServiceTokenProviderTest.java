// Copyright (c) 2026, Oracle and/or its affiliates.

package com.example.common.security;

import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;
import tools.jackson.databind.ObjectMapper;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.client.ExpectedCount.once;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.header;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

class CloudBankServiceTokenProviderTest {

    @Test
    void returnsCachedBearerToken() {
        RestClient.Builder restClientBuilder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(restClientBuilder).build();
        server.expect(once(), requestTo("http://azn-server/oauth2/token"))
                .andExpect(method(HttpMethod.POST))
                .andExpect(header(HttpHeaders.AUTHORIZATION, "Basic Y2xvdWRiYW5rLXNlcnZpY2UtY2xpZW50OnNlY3JldA=="))
                .andRespond(withSuccess("""
                        {"access_token":"service-token","expires_in":300,"token_type":"Bearer"}
                        """, MediaType.APPLICATION_JSON));

        CloudBankServiceTokenProvider tokenProvider = new CloudBankServiceTokenProvider(
                properties(), restClientBuilder, new ObjectMapper());

        assertThat(tokenProvider.getAuthorizationHeader()).isEqualTo("Bearer service-token");
        assertThat(tokenProvider.getAuthorizationHeader()).isEqualTo("Bearer service-token");
        server.verify();
    }

    private static CloudBankServiceTokenProperties properties() {
        CloudBankServiceTokenProperties properties = new CloudBankServiceTokenProperties();
        properties.setTokenUri("http://azn-server/oauth2/token");
        properties.setClientId("cloudbank-service-client");
        properties.setClientSecret("secret");
        properties.setScope("cloudbank.internal");
        return properties;
    }
}
