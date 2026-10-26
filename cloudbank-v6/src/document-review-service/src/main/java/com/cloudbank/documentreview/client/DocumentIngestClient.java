// Copyright (c) 2026, Oracle and/or its affiliates.
//
// Licensed under the Universal Permissive License v 1.0 as shown at
// https://oss.oracle.com/licenses/upl/.
//

package com.cloudbank.documentreview.client;

import com.cloudbank.documentreview.domain.ReviewModels.ExtractionReviewInput;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.oauth2.client.OAuth2AuthorizedClientManager;
import org.springframework.security.oauth2.client.OAuth2AuthorizedClientService;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

@Component
public class DocumentIngestClient {
    private final RestClient client;

    public DocumentIngestClient(RestClient.Builder builder, OAuth2AuthorizedClientManager manager,
            OAuth2AuthorizedClientService service, @Value("${cloudbank.document-ingest.base-url}") String baseUrl) {
        client = AuthenticatedRestClientFactory.create(builder, manager, service, baseUrl);
    }

    public ExtractionReviewInput reviewInput(String applicationId) {
        return client.get().uri("/internal/api/v1/applications/{applicationId}/extractions/review-input", applicationId)
                .retrieve().body(ExtractionReviewInput.class);
    }
}
