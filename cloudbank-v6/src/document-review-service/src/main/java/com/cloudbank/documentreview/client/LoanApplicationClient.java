// Copyright (c) 2026, Oracle and/or its affiliates.
//
// Licensed under the Universal Permissive License v 1.0 as shown at
// https://oss.oracle.com/licenses/upl/.
//

package com.cloudbank.documentreview.client;

import com.cloudbank.documentreview.domain.ReviewModels.DocumentManifest;
import java.util.Map;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.security.oauth2.client.OAuth2AuthorizedClientManager;
import org.springframework.security.oauth2.client.OAuth2AuthorizedClientService;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

@Component
public class LoanApplicationClient {
    private final RestClient client;

    public LoanApplicationClient(RestClient.Builder builder, OAuth2AuthorizedClientManager manager,
            OAuth2AuthorizedClientService service, @Value("${cloudbank.loan-application.base-url}") String baseUrl) {
        client = AuthenticatedRestClientFactory.create(builder, manager, service, baseUrl);
    }

    public DocumentManifest manifest(String applicationId) {
        return client.get().uri("/internal/api/v1/loan-applications/{applicationId}/documents", applicationId)
                .retrieve().body(DocumentManifest.class);
    }

    public void transitionStatus(String applicationId, String documentId, String expectedStatus, String targetStatus,
            String eventId, String traceId) {
        client.post()
                .uri("/internal/api/v1/loan-applications/{applicationId}/documents/{documentId}/status-transitions",
                        applicationId, documentId)
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("eventId", eventId, "expectedStatus", expectedStatus, "targetStatus", targetStatus,
                        "reasonCode", "DOCUMENT_REVIEW_" + targetStatus, "traceId", traceId))
                .retrieve().toBodilessEntity();
    }
}
