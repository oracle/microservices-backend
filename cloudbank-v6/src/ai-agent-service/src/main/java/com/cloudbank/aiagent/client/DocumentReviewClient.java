// Copyright (c) 2026, Oracle and/or its affiliates.
//
// Licensed under the Universal Permissive License v 1.0 as shown at
// https://oss.oracle.com/licenses/upl/.
//

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
import org.springframework.web.client.RestClientResponseException;

@Component
public class DocumentReviewClient {
    private static final String REGISTRATION_ID = "document-review";
    private static final String SERVICE_PRINCIPAL = "ai-agent-service";
    private final RestClient client;

    public DocumentReviewClient(RestClient.Builder builder, OAuth2AuthorizedClientManager manager,
            OAuth2AuthorizedClientService authorizedClientService,
            @Value("${cloudbank.document-review.base-url}") String baseUrl) {
        OAuth2ClientHttpRequestInterceptor oauth2 = new OAuth2ClientHttpRequestInterceptor(manager);
        oauth2.setPrincipalResolver(new RequestAttributePrincipalResolver());
        oauth2.setAuthorizationFailureHandler(
                OAuth2ClientHttpRequestInterceptor.authorizationFailureHandler(authorizedClientService));
        client = builder.baseUrl(baseUrl)
                .defaultRequest(request -> request.attributes(clientRegistrationId(REGISTRATION_ID))
                        .attributes(principal(SERVICE_PRINCIPAL)))
                .requestInterceptor(oauth2).build();
    }

    public DocumentReviewEvidence get(String reviewId, String traceId) {
        try {
            DocumentReviewEvidence evidence = client.get()
                    .uri("/internal/api/v1/document-reviews/{reviewId}", reviewId)
                    .header("X-Trace-Id", traceId)
                    .header("traceparent", "00-" + traceId + "-" + UUID.randomUUID().toString().replace("-", "").substring(0, 16) + "-01")
                    .retrieve().body(DocumentReviewEvidence.class);
            if (evidence == null) {
                throw ReviewAssistanceException.downstreamUnavailable();
            }
            return evidence;
        } catch (RestClientResponseException exception) {
            if (exception.getStatusCode().value() == 404) {
                throw ReviewAssistanceException.reviewNotFound();
            }
            throw ReviewAssistanceException.downstreamUnavailable(exception);
        } catch (RestClientException | OAuth2AuthorizationException exception) {
            throw ReviewAssistanceException.downstreamUnavailable(exception);
        }
    }
}
