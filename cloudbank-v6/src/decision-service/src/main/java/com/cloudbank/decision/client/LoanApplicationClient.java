// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.

package com.cloudbank.decision.client;

import java.util.LinkedHashMap;
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

    public void transitionStatus(String applicationId, String expectedStatus, String targetStatus, String eventId,
            String reasonCode, String workflowId, String taskReference, String traceId) {
        Map<String, String> body = new LinkedHashMap<>();
        body.put("eventId", eventId);
        body.put("expectedStatus", expectedStatus);
        body.put("targetStatus", targetStatus);
        body.put("reasonCode", reasonCode);
        body.put("workflowId", workflowId);
        body.put("taskReference", taskReference);
        body.put("traceId", traceId);
        client.post().uri("/internal/api/v1/loan-applications/{applicationId}/status-transitions", applicationId)
                .contentType(MediaType.APPLICATION_JSON).body(body).retrieve().toBodilessEntity();
    }
}
