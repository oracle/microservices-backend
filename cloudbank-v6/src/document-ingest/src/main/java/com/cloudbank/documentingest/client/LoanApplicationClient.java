// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.documentingest.client;

import static org.springframework.security.oauth2.client.web.client.RequestAttributeClientRegistrationIdResolver
        .clientRegistrationId;
import static org.springframework.security.oauth2.client.web.client.RequestAttributePrincipalResolver.principal;

import com.cloudbank.documentingest.model.WorkflowExtractionModels.LoanDocument;
import com.cloudbank.documentingest.model.WorkflowExtractionModels.LoanDocumentManifest;
import java.util.Map;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.security.oauth2.client.OAuth2AuthorizedClientManager;
import org.springframework.security.oauth2.client.OAuth2AuthorizedClientService;
import org.springframework.security.oauth2.client.web.client.OAuth2ClientHttpRequestInterceptor;
import org.springframework.security.oauth2.client.web.client.RequestAttributePrincipalResolver;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

@Component
public class LoanApplicationClient {

    private static final String CLIENT_REGISTRATION_ID = "loan-application";
    private static final String SERVICE_PRINCIPAL = "document-ingest-service";

    private final RestClient loanClient;

    public LoanApplicationClient(RestClient.Builder builder,
            OAuth2AuthorizedClientManager authorizedClientManager,
            OAuth2AuthorizedClientService authorizedClientService,
            @Value("${cloudbank.loan-application.base-url}") String baseUrl) {
        OAuth2ClientHttpRequestInterceptor oauth2 =
                new OAuth2ClientHttpRequestInterceptor(authorizedClientManager);
        oauth2.setPrincipalResolver(new RequestAttributePrincipalResolver());
        oauth2.setAuthorizationFailureHandler(
                OAuth2ClientHttpRequestInterceptor.authorizationFailureHandler(authorizedClientService));
        this.loanClient = builder.baseUrl(baseUrl)
                .defaultRequest(request -> request
                        .attributes(clientRegistrationId(CLIENT_REGISTRATION_ID))
                        .attributes(principal(SERVICE_PRINCIPAL)))
                .requestInterceptor(oauth2)
                .build();
    }

    public LoanDocumentManifest manifest(String applicationId) {
        return loanClient.get()
                .uri("/internal/api/v1/loan-applications/{applicationId}/documents", applicationId)
                .retrieve().body(LoanDocumentManifest.class);
    }

    public byte[] content(String applicationId, LoanDocument document) {
        return loanClient.get()
                .uri("/internal/api/v1/loan-applications/{applicationId}/documents/{documentId}/content",
                        applicationId, document.documentId())
                .accept(MediaType.APPLICATION_PDF)
                .retrieve().body(byte[].class);
    }

    public void transitionStatus(String applicationId, LoanDocument document, String eventId,
            String targetStatus, String reasonCode, String traceId) {
        loanClient.post()
                .uri("/internal/api/v1/loan-applications/{applicationId}/documents/{documentId}/status-transitions",
                        applicationId, document.documentId())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("eventId", eventId, "expectedStatus", document.status(),
                        "targetStatus", targetStatus, "reasonCode", reasonCode,
                        "traceId", traceId))
                .retrieve().toBodilessEntity();
    }
}
