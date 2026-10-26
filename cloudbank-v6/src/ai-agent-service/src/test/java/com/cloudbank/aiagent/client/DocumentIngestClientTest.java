// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.

package com.cloudbank.aiagent.client;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.hamcrest.Matchers.matchesPattern;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.header;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withStatus;

import com.cloudbank.aiagent.service.ReviewAssistanceException;
import java.time.Instant;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.security.oauth2.client.OAuth2AuthorizedClient;
import org.springframework.security.oauth2.client.OAuth2AuthorizedClientManager;
import org.springframework.security.oauth2.client.OAuth2AuthorizedClientService;
import org.springframework.security.oauth2.client.registration.ClientRegistration;
import org.springframework.security.oauth2.core.AuthorizationGrantType;
import org.springframework.security.oauth2.core.OAuth2AccessToken;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

class DocumentIngestClientTest {
    private static final String TRACE = "0123456789abcdef0123456789abcdef";
    private final RestClient.Builder builder = RestClient.builder();
    private final MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
    private final OAuth2AuthorizedClientManager manager = mock(OAuth2AuthorizedClientManager.class);
    private final OAuth2AuthorizedClientService clients = mock(OAuth2AuthorizedClientService.class);

    @Test
    void usesAiServiceClientCredentialsAndOnlyTheBoundedReadEndpoint() {
        configureServiceToken();
        server.expect(requestTo("http://ingest.test/internal/api/v1/applications/APP-ONE/extractions/review-input"))
                .andExpect(method(HttpMethod.GET)).andExpect(header("Authorization", "Bearer synthetic-downstream-token"))
                .andExpect(header("X-Trace-Id", TRACE))
                .andExpect(header("traceparent", matchesPattern("00-" + TRACE + "-[0-9a-f]{16}-01")))
                .andRespond(withSuccess("""
                        {"applicationId":"APP-ONE","documents":[{"documentId":"DOC-ONE","documentType":"PAY_STATEMENT","extractionId":"EXT-ONE","extractionStatus":"SUCCEEDED","confidenceScore":0.9,"provider":"local","model":"parser","facts":{"identityOutcome":"VERIFIED","employerName":"SYNTHETIC_PRIVATE_EMPLOYER","statedGrossMonthlyIncome":12345},"validationSignals":[],"warnings":[]}]}
                        """, MediaType.APPLICATION_JSON));
        var evidence = client().get("APP-ONE", TRACE);
        assertThat(evidence.applicationId()).isEqualTo("APP-ONE");
        assertThat(evidence.documents().getFirst().facts()).isEqualTo(new ExtractionReviewEvidence.ReviewedFacts("VERIFIED"));
        server.verify();
    }

    @Test
    void masksDownstreamFailureDetails() {
        configureServiceToken();
        server.expect(requestTo("http://ingest.test/internal/api/v1/applications/APP-ONE/extractions/review-input"))
                .andRespond(withStatus(HttpStatus.FORBIDDEN).body("sensitive downstream diagnostics"));
        assertThatThrownBy(() -> client().get("APP-ONE", TRACE)).isInstanceOf(ReviewAssistanceException.class)
                .hasMessage("Bounded extraction evidence is temporarily unavailable.");
        server.verify();
    }

    private DocumentIngestClient client() {
        return new DocumentIngestClient(builder, manager, clients, "http://ingest.test");
    }

    private void configureServiceToken() {
        var registration = ClientRegistration.withRegistrationId("document-review")
                .clientId("cloudbank-ai-agent-client").clientSecret("synthetic-test-only")
                .authorizationGrantType(AuthorizationGrantType.CLIENT_CREDENTIALS)
                .tokenUri("http://auth.test/oauth2/token").scope("cloudbank.internal").build();
        when(manager.authorize(any())).thenAnswer(call -> {
            org.springframework.security.oauth2.client.OAuth2AuthorizeRequest request = call.getArgument(0);
            assertThat(request.getClientRegistrationId()).isEqualTo("document-review");
            assertThat(request.getPrincipal().getName()).isEqualTo("ai-agent-service");
            return new OAuth2AuthorizedClient(registration, "ai-agent-service", new OAuth2AccessToken(
                    OAuth2AccessToken.TokenType.BEARER, "synthetic-downstream-token", Instant.now(), Instant.now().plusSeconds(60)));
        });
    }
}
