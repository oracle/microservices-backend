// Copyright (c) 2026, Oracle and/or its affiliates.
//
// Licensed under the Universal Permissive License v 1.0 as shown at
// https://oss.oracle.com/licenses/upl/.
//

package com.cloudbank.documentreview.api;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.cloudbank.documentreview.domain.ReviewModels.DocumentCounts;
import com.cloudbank.documentreview.domain.ReviewModels.ReviewDisposition;
import com.cloudbank.documentreview.domain.ReviewModels.ReviewResult;
import com.cloudbank.documentreview.domain.ReviewModels.ReviewStatus;
import com.cloudbank.documentreview.security.InternalAuthorization;
import com.cloudbank.documentreview.security.SecurityConfig;
import com.cloudbank.documentreview.service.DocumentReviewService;
import com.cloudbank.documentreview.service.ReviewServiceException;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.oauth2.client.OAuth2AuthorizedClientService;
import org.springframework.security.oauth2.client.registration.ClientRegistrationRepository;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(DocumentReviewController.class)
@Import({ ApiExceptionHandler.class, InternalAuthorization.class, SecurityConfig.class })
class DocumentReviewControllerSecurityTest {
    @Autowired
    private MockMvc mockMvc;

    @MockitoBean
    private DocumentReviewService service;

    @MockitoBean
    private ClientRegistrationRepository registrations;

    @MockitoBean
    private OAuth2AuthorizedClientService clients;

    @Test
    void internalEndpointsRejectAnAnonymousCaller() throws Exception {
        mockMvc.perform(get("/internal/api/v1/document-reviews/DREV-00000000000000000000000000000000"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void internalEndpointsRejectAUserTokenAndAnUnknownServiceClient() throws Exception {
        mockMvc.perform(get("/internal/api/v1/document-reviews/DREV-00000000000000000000000000000000")
                .with(token("cloudbank-service-client", "user", "SCOPE_cloudbank.internal")))
                .andExpect(status().isForbidden());

        mockMvc.perform(get("/internal/api/v1/document-reviews/DREV-00000000000000000000000000000000")
                .with(token("unknown-client", "service", "SCOPE_cloudbank.internal")))
                .andExpect(status().isForbidden());
    }

    @Test
    void internalEndpointsRejectAServiceTokenWithoutTheInternalScope() throws Exception {
        mockMvc.perform(get("/internal/api/v1/document-reviews/DREV-00000000000000000000000000000000")
                .with(token("cloudbank-service-client", "service", "SCOPE_cloudbank.read")))
                .andExpect(status().isForbidden());
    }

    @Test
    void eligibleServiceTokenCanStartAReview() throws Exception {
        when(service.review(any(), eq("review:APP-ONE:WF-ONE"))).thenReturn(review());

        mockMvc.perform(post("/internal/api/v1/document-reviews")
                .with(token("cloudbank-service-client", "service", "SCOPE_cloudbank.internal"))
                .header("Idempotency-Key", "review:APP-ONE:WF-ONE").contentType(MediaType.APPLICATION_JSON).content(
                        """
                                {"applicationId":"APP-ONE","workflowId":"WF-ONE","taskReference":"review_documents","traceId":"0123456789abcdef0123456789abcdef"}
                                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.reviewId").value("DREV-00000000000000000000000000000000"))
                .andExpect(jsonPath("$.disposition").value("CLEAR"));

        verify(service).review(any(), eq("review:APP-ONE:WF-ONE"));
    }

    @Test
    void requestValidationAndDomainErrorsUseSafeResponses() throws Exception {
        mockMvc.perform(post("/internal/api/v1/document-reviews")
                .with(token("cloudbank-service-client", "service", "SCOPE_cloudbank.internal"))
                .header("Idempotency-Key", "short").contentType(MediaType.APPLICATION_JSON).content("{}"))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.code").value("VALIDATION_FAILED"));

        when(service.get("DREV-00000000000000000000000000000000")).thenThrow(new ReviewServiceException(
                "DOCUMENT_REVIEW_NOT_FOUND", HttpStatus.NOT_FOUND, "Document review was not found.", false));

        mockMvc.perform(get("/internal/api/v1/document-reviews/DREV-00000000000000000000000000000000")
                .with(token("cloudbank-service-client", "service", "SCOPE_cloudbank.internal")))
                .andExpect(status().isNotFound()).andExpect(jsonPath("$.code").value("DOCUMENT_REVIEW_NOT_FOUND"))
                .andExpect(jsonPath("$.retryable").value(false));
    }

    private static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.JwtRequestPostProcessor token(
            String clientId, String tokenKind, String authority) {
        return jwt().jwt(jwt -> jwt.claim("client_id", clientId).claim("token_kind", tokenKind).claim("scope",
                authority.substring("SCOPE_".length()))).authorities(new SimpleGrantedAuthority(authority));
    }

    private static ReviewResult review() {
        return new ReviewResult("DREV-00000000000000000000000000000000", "APP-ONE", "WF-ONE", "review_documents",
                ReviewStatus.COMPLETED, ReviewDisposition.CLEAR, "document-review-v1",
                new DocumentCounts(1, 1, 0, 0, 0), List.of(), "0123456789abcdef0123456789abcdef", List.of());
    }
}
