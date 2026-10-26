// Copyright (c) 2026, Oracle and/or its affiliates.
//
// Licensed under the Universal Permissive License v 1.0 as shown at
// https://oss.oracle.com/licenses/upl/.
//

package com.cloudbank.aiagent.api;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.cloudbank.aiagent.api.AiAgentApiModels.ManualReviewAssistanceResponse;
import com.cloudbank.aiagent.security.InternalAuthorization;
import com.cloudbank.aiagent.security.SecurityConfig;
import com.cloudbank.aiagent.service.GenAIReviewAssistanceService;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(ManualReviewAssistanceController.class)
@Import({ ApiExceptionHandler.class, InternalAuthorization.class, SecurityConfig.class })
class ManualReviewAssistanceControllerSecurityTest {
    private static final String ENDPOINT = "/internal/api/v1/ai/manual-review-assistances";
    private static final String REQUEST = """
            {"applicationId":"APP-ONE","workflowId":"WF-ONE","taskReference":"ai_manual_review_assistant","traceId":"0123456789abcdef0123456789abcdef","reviewId":"DREV-00000000000000000000000000000000","documentSummaryId":"AISUM-00000000000000000000000000000000","audience":"UNDERWRITER"}
            """;

    @Autowired
    private MockMvc mockMvc;

    @MockitoBean
    private GenAIReviewAssistanceService service;

    @Test
    void rejectsAnonymousAndUserCallers() throws Exception {
        mockMvc.perform(post(ENDPOINT).header("Idempotency-Key", "manual-review:APP-ONE:WF-ONE")
                .contentType(MediaType.APPLICATION_JSON).content(REQUEST)).andExpect(status().isUnauthorized());

        mockMvc.perform(post(ENDPOINT).with(token("cloudbank-service-client", "user", "SCOPE_cloudbank.internal"))
                .header("Idempotency-Key", "manual-review:APP-ONE:WF-ONE").contentType(MediaType.APPLICATION_JSON)
                .content(REQUEST)).andExpect(status().isForbidden());
    }

    @Test
    void eligibleServiceTokenReceivesTheGeneratedResult() throws Exception {
        when(service.assist(any(), eq("manual-review:APP-ONE:WF-ONE"))).thenReturn(response());

        mockMvc.perform(post(ENDPOINT)
                .with(token("cloudbank-service-client", "service", "SCOPE_cloudbank.internal"))
                .header("Idempotency-Key", "manual-review:APP-ONE:WF-ONE").contentType(MediaType.APPLICATION_JSON)
                .content(REQUEST)).andExpect(status().isOk())
                .andExpect(jsonPath("$.assistanceId").value("AIREV-00000000000000000000000000000000"))
                .andExpect(jsonPath("$.status").value("COMPLETED"))
                .andExpect(jsonPath("$.checklist.length()").value(1))
                .andExpect(jsonPath("$.clarificationQuestions.length()").value(1))
                .andExpect(jsonPath("$.guardrailStatus").value("PASSED"));

        verify(service).assist(any(), eq("manual-review:APP-ONE:WF-ONE"));
    }

    @Test
    void rejectsInvalidWorkflowInputWithASafeResponse() throws Exception {
        mockMvc.perform(post(ENDPOINT)
                .with(token("cloudbank-service-client", "service", "SCOPE_cloudbank.internal"))
                .header("Idempotency-Key", "short").contentType(MediaType.APPLICATION_JSON).content("{}"))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.code").value("VALIDATION_FAILED"));
    }

    @Test
    void reportsAnUnknownAiResourceAsNotFoundInsteadOfMockFailure() throws Exception {
        mockMvc.perform(post("/internal/api/v1/ai/unknown-resource")
                .with(token("cloudbank-service-client", "service", "SCOPE_cloudbank.internal"))
                .contentType(MediaType.APPLICATION_JSON).content("{}"))
                .andExpect(status().isNotFound()).andExpect(jsonPath("$.code").value("RESOURCE_NOT_FOUND"));
    }

    private static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.JwtRequestPostProcessor token(
            String clientId, String tokenKind, String authority) {
        return jwt().jwt(jwt -> jwt.claim("client_id", clientId).claim("token_kind", tokenKind).claim("scope",
                authority.substring("SCOPE_".length()))).authorities(new SimpleGrantedAuthority(authority));
    }

    private static ManualReviewAssistanceResponse response() {
        return new ManualReviewAssistanceResponse("AIREV-00000000000000000000000000000000", "COMPLETED",
                "oci-genai", "cohere.command-a-03-2025", "APP-ONE", "WF-ONE",
                "ai_manual_review_assistant", "0123456789abcdef0123456789abcdef",
                "DREV-00000000000000000000000000000000", "AISUM-00000000000000000000000000000000",
                "UNDERWRITER", List.of("Review evidence."), List.of("What resolves the issue?"), List.of(),
                "PASSED");
    }
}
