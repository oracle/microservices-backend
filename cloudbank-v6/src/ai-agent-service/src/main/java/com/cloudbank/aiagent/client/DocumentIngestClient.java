// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.

package com.cloudbank.aiagent.client;

import static org.springframework.security.oauth2.client.web.client.RequestAttributeClientRegistrationIdResolver.clientRegistrationId;
import static org.springframework.security.oauth2.client.web.client.RequestAttributePrincipalResolver.principal;

import com.cloudbank.aiagent.service.ReviewAssistanceException;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.oauth2.client.OAuth2AuthorizedClientManager;
import org.springframework.security.oauth2.client.OAuth2AuthorizedClientService;
import org.springframework.security.oauth2.client.web.client.OAuth2ClientHttpRequestInterceptor;
import org.springframework.security.oauth2.client.web.client.RequestAttributePrincipalResolver;
import org.springframework.security.oauth2.core.OAuth2AuthorizationException;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

@Component
public class DocumentIngestClient {
    private final RestClient client;

    public DocumentIngestClient(RestClient.Builder builder, OAuth2AuthorizedClientManager manager,
            OAuth2AuthorizedClientService authorizedClientService,
            @Value("${cloudbank.document-ingest.base-url}") String baseUrl) {
        OAuth2ClientHttpRequestInterceptor oauth2 = new OAuth2ClientHttpRequestInterceptor(manager);
        oauth2.setPrincipalResolver(new RequestAttributePrincipalResolver());
        oauth2.setAuthorizationFailureHandler(
                OAuth2ClientHttpRequestInterceptor.authorizationFailureHandler(authorizedClientService));
        // Reuse the manual-review OAuth registration: the same AI service identity,
        // with a service principal independent of the inbound workflow JWT.
        client = builder.baseUrl(baseUrl)
                .defaultRequest(request -> request.attributes(clientRegistrationId("document-review"))
                        .attributes(principal("ai-agent-service")))
                .requestInterceptor(oauth2).build();
    }

    public ExtractionReviewEvidence get(String applicationId, String traceId) {
        try {
            ExtractionReviewEvidence evidence = client.get()
                    .uri("/internal/api/v1/applications/{applicationId}/extractions/review-input", applicationId)
                    .header("X-Trace-Id", traceId)
                    .header("traceparent", "00-" + traceId + "-" + UUID.randomUUID().toString().replace("-", "").substring(0, 16) + "-01")
                    .retrieve().body(ExtractionReviewEvidence.class);
            if (evidence == null) {
                throw ReviewAssistanceException.extractionsUnavailable(null);
            }
            return evidence;
        } catch (RestClientException | OAuth2AuthorizationException exception) {
            throw ReviewAssistanceException.extractionsUnavailable(exception);
        }
    }
}
