// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.documentingest.client;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.http.HttpHeaders.AUTHORIZATION;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.header;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withUnauthorizedRequest;

import com.cloudbank.documentingest.model.WorkflowExtractionModels.LoanDocumentManifest;
import java.time.Instant;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.security.oauth2.client.OAuth2AuthorizeRequest;
import org.springframework.security.oauth2.client.OAuth2AuthorizedClient;
import org.springframework.security.oauth2.client.OAuth2AuthorizedClientManager;
import org.springframework.security.oauth2.client.OAuth2AuthorizedClientService;
import org.springframework.security.oauth2.client.registration.ClientRegistration;
import org.springframework.security.oauth2.core.AuthorizationGrantType;
import org.springframework.security.oauth2.core.OAuth2AccessToken;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.RestClient;

class LoanApplicationClientTest {

    private static final String BASE_URL = "https://loan-application.test";

    private OAuth2AuthorizedClientManager authorizedClientManager;
    private OAuth2AuthorizedClientService authorizedClientService;
    private MockRestServiceServer server;
    private LoanApplicationClient client;

    @BeforeEach
    void setUp() {
        RestClient.Builder builder = RestClient.builder();
        server = MockRestServiceServer.bindTo(builder).build();
        authorizedClientManager = mock(OAuth2AuthorizedClientManager.class);
        authorizedClientService = mock(OAuth2AuthorizedClientService.class);
        when(authorizedClientManager.authorize(any())).thenReturn(authorizedClient());
        client = new LoanApplicationClient(
                builder, authorizedClientManager, authorizedClientService, BASE_URL);
    }

    @Test
    void attachesSpringSecurityManagedBearerToken() {
        server.expect(requestTo(BASE_URL + "/internal/api/v1/loan-applications/APP-TEST/documents"))
                .andExpect(header(AUTHORIZATION, "Bearer service-token"))
                .andRespond(withSuccess("{\"applicationId\":\"APP-TEST\",\"documents\":[]}",
                        MediaType.APPLICATION_JSON));

        LoanDocumentManifest manifest = client.manifest("APP-TEST");

        assertThat(manifest.applicationId()).isEqualTo("APP-TEST");
        assertThat(manifest.documents()).isEmpty();
        verify(authorizedClientManager).authorize(any(OAuth2AuthorizeRequest.class));
        server.verify();
    }

    @Test
    void removesAuthorizedClientAfterUnauthorizedResponse() {
        server.expect(requestTo(BASE_URL + "/internal/api/v1/loan-applications/APP-TEST/documents"))
                .andRespond(withUnauthorizedRequest());

        assertThatThrownBy(() -> client.manifest("APP-TEST"))
                .isInstanceOf(HttpClientErrorException.Unauthorized.class);

        verify(authorizedClientService)
                .removeAuthorizedClient("loan-application", "document-ingest-service");
        server.verify();
    }

    private static OAuth2AuthorizedClient authorizedClient() {
        ClientRegistration registration = ClientRegistration.withRegistrationId("loan-application")
                .clientId("cloudbank-document-ingest-client")
                .clientSecret("secret")
                .authorizationGrantType(AuthorizationGrantType.CLIENT_CREDENTIALS)
                .tokenUri("https://authorization-server.test/oauth2/token")
                .build();
        Instant issuedAt = Instant.now();
        OAuth2AccessToken accessToken = new OAuth2AccessToken(OAuth2AccessToken.TokenType.BEARER,
                "service-token", issuedAt, issuedAt.plusSeconds(300));
        return new OAuth2AuthorizedClient(registration, "document-ingest-service", accessToken);
    }
}
