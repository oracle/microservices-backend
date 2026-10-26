// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.

package com.cloudbank.gatewaybff;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import java.util.List;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.security.oauth2.client.AuthorizedClientServiceOAuth2AuthorizedClientManager;
import org.springframework.security.oauth2.client.InMemoryOAuth2AuthorizedClientService;
import org.springframework.security.oauth2.client.OAuth2AuthorizeRequest;
import org.springframework.security.oauth2.client.OAuth2AuthorizedClientManager;
import org.springframework.security.oauth2.client.OAuth2AuthorizedClientProviderBuilder;
import org.springframework.security.oauth2.client.registration.ClientRegistration;
import org.springframework.security.oauth2.client.registration.InMemoryClientRegistrationRepository;
import org.springframework.security.oauth2.core.AuthorizationGrantType;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.server.ResponseStatusException;

/** MicroTx credentials and runtime payloads stay on the server. No generic browser proxy. */
@Component
class MicroTxClient {
    private static final String REGISTRATION = "bff-microtx";
    private final RestClient client;
    private final OAuth2AuthorizedClientManager authorization;

    MicroTxClient(RestClient.Builder builder,
            @Value("${cloudbank.bff.microtx.base-url:}") String baseUrl,
            @Value("${cloudbank.bff.microtx.token-uri:}") String tokenUri,
            @Value("${cloudbank.bff.microtx.client-id:microtx-workflow-client}") String clientId,
            @Value("${cloudbank.bff.microtx.client-secret:}") String secret) {
        client = builder.clone().baseUrl(baseUrl.replaceAll("/+$", "")).build();
        if (baseUrl.isBlank() || tokenUri.isBlank() || secret.isBlank()) {
            authorization = null;
        } else {
            var registration = ClientRegistration.withRegistrationId(REGISTRATION)
                    .clientId(clientId).clientSecret(secret)
                    .authorizationGrantType(AuthorizationGrantType.CLIENT_CREDENTIALS)
                    .tokenUri(tokenUri).scope("microtx.workflow").build();
            var registrations = new InMemoryClientRegistrationRepository(registration);
            var manager = new AuthorizedClientServiceOAuth2AuthorizedClientManager(registrations,
                    new InMemoryOAuth2AuthorizedClientService(registrations));
            manager.setAuthorizedClientProvider(OAuth2AuthorizedClientProviderBuilder.builder()
                    .clientCredentials().build());
            authorization = manager;
        }
    }

    HumanTaskSearch pending(int start, int size, String correlation) {
        return client.get().uri(uri -> uri.path("/notifications/human-tasks")
                        .queryParam("start", start).queryParam("size", size).build())
                .headers(headers -> headers.setBearerAuth(accessToken()))
                .header("X-Correlation-ID", correlation).retrieve().body(HumanTaskSearch.class);
    }

    Task task(String taskId, String correlation) {
        return client.get().uri("/tasks/{taskId}", taskId)
                .headers(headers -> headers.setBearerAuth(accessToken()))
                .header("X-Correlation-ID", correlation).retrieve().body(Task.class);
    }

    Workflow workflow(String workflowId, String correlation) {
        return client.get().uri("/workflow/{id}?includeTasks=false", workflowId)
                .headers(headers -> headers.setBearerAuth(accessToken()))
                .header("X-Correlation-ID", correlation).retrieve().body(Workflow.class);
    }

    void complete(String workflowId, Completion completion, String key, String correlation) {
        client.post().uri("/tasks/{workflowId}/human_task_manual_review/COMPLETED", workflowId)
                .headers(headers -> headers.setBearerAuth(accessToken()))
                .header("Idempotency-Key", key).header("X-Correlation-ID", correlation)
                .contentType(MediaType.APPLICATION_JSON).body(completion).retrieve().toBodilessEntity();
    }

    private synchronized String accessToken() {
        if (authorization == null) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE);
        }
        try {
            var authorized = authorization.authorize(OAuth2AuthorizeRequest
                    .withClientRegistrationId(REGISTRATION).principal("gateway-bff-service").build());
            if (authorized == null) throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE);
            return authorized.getAccessToken().getTokenValue();
        } catch (org.springframework.security.oauth2.core.OAuth2AuthorizationException unavailable) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE);
        }
    }

    @JsonIgnoreProperties(ignoreUnknown = true)
    record HumanTaskSearch(long totalHits, List<Notification> results) { }
    @JsonIgnoreProperties(ignoreUnknown = true)
    record Notification(String taskId, String status, String taskDefName,
            String workflowInstanceId, String workflowName) { }
    @JsonIgnoreProperties(ignoreUnknown = true)
    record Task(String taskId, String taskType, String referenceTaskName, String status,
            String workflowInstanceId, HumanInput inputData, Completion outputData,
            long scheduledTime, long updateTime) { }
    @JsonIgnoreProperties(ignoreUnknown = true)
    record HumanInput(String applicationId, String reviewRouteReason, String reviewId,
            String documentSummaryId, String manualReviewAssistanceId, String initialDecisionId) { }
    @JsonIgnoreProperties(ignoreUnknown = true)
    record Workflow(String workflowId, String workflowName, int workflowVersion, String status,
            WorkflowInput input) { }
    @JsonIgnoreProperties(ignoreUnknown = true)
    record WorkflowInput(String applicationId) { }
    @JsonIgnoreProperties(ignoreUnknown = true)
    record Completion(String decisionOutcome, String reviewerRole, String reviewerPrincipalId,
            String reasonCode, String policySection) { }
}
