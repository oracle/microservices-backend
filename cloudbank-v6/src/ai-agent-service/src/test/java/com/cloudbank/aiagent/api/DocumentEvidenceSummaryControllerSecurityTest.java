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

import com.cloudbank.aiagent.api.AiAgentApiModels.DocumentEvidenceSummaryResponse;
import com.cloudbank.aiagent.security.InternalAuthorization;
import com.cloudbank.aiagent.security.SecurityConfig;
import com.cloudbank.aiagent.service.GenAIDocumentEvidenceSummaryService;
import com.cloudbank.aiagent.service.ReviewAssistanceException;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(DocumentEvidenceSummaryController.class)
@Import({ ApiExceptionHandler.class, InternalAuthorization.class, SecurityConfig.class })
class DocumentEvidenceSummaryControllerSecurityTest {
    private static final String ENDPOINT = "/internal/api/v1/ai/document-evidence-summaries";
    private static final String REQUEST = """
            {"applicationId":"APP-ONE","workflowId":"WF-ONE","taskReference":"ai_document_evidence_summary","traceId":"0123456789abcdef0123456789abcdef","reviewId":"DREV-00000000000000000000000000000000","audience":"UNDERWRITER"}
            """;

    @Autowired
    private MockMvc mockMvc;

    @MockitoBean
    private GenAIDocumentEvidenceSummaryService service;

    @Test
    void rejectsAnonymousAndUserCallers() throws Exception {
        mockMvc.perform(post(ENDPOINT).header("Idempotency-Key", "ai-summary:APP-ONE:WF-ONE")
                .contentType(MediaType.APPLICATION_JSON).content(REQUEST)).andExpect(status().isUnauthorized());

        mockMvc.perform(post(ENDPOINT).with(token("cloudbank-service-client", "user", "SCOPE_cloudbank.internal"))
                .header("Idempotency-Key", "ai-summary:APP-ONE:WF-ONE").contentType(MediaType.APPLICATION_JSON)
                .content(REQUEST)).andExpect(status().isForbidden());
    }

    @Test
    void rejectsUnknownServicesAndTokensWithoutTheInternalScope() throws Exception {
        mockMvc.perform(post(ENDPOINT).with(token("unknown-client", "service", "SCOPE_cloudbank.internal"))
                .header("Idempotency-Key", "ai-summary:APP-ONE:WF-ONE").contentType(MediaType.APPLICATION_JSON)
                .content(REQUEST)).andExpect(status().isForbidden());

        mockMvc.perform(post(ENDPOINT).with(token("cloudbank-service-client", "service", "SCOPE_cloudbank.read"))
                .header("Idempotency-Key", "ai-summary:APP-ONE:WF-ONE").contentType(MediaType.APPLICATION_JSON)
                .content(REQUEST)).andExpect(status().isForbidden());
    }

    @Test
    void eligibleServiceTokenReceivesTheValidatedSummary() throws Exception {
        when(service.summarize(any(), eq("ai-summary:APP-ONE:WF-ONE"))).thenReturn(response());

        mockMvc.perform(post(ENDPOINT)
                .with(token("cloudbank-service-client", "service", "SCOPE_cloudbank.internal"))
                .header("Idempotency-Key", "ai-summary:APP-ONE:WF-ONE").contentType(MediaType.APPLICATION_JSON)
                .content(REQUEST)).andExpect(status().isOk())
                .andExpect(jsonPath("$.summaryId").value("AISUM-00000000000000000000000000000000"))
                .andExpect(jsonPath("$.status").value("COMPLETED"))
                .andExpect(jsonPath("$.provider").value("oci-genai"))
                .andExpect(jsonPath("$.guardrailStatus").value("PASSED"));

        verify(service).summarize(any(), eq("ai-summary:APP-ONE:WF-ONE"));
    }

    @Test
    void returnsSafeUnavailableAndRejectedOutputErrors() throws Exception {
        when(service.summarize(any(), eq("ai-summary:APP-ONE:WF-ONE")))
                .thenThrow(ReviewAssistanceException.modelUnavailable(new IllegalStateException("sensitive details")));
        mockMvc.perform(post(ENDPOINT)
                .with(token("cloudbank-service-client", "service", "SCOPE_cloudbank.internal"))
                .header("Idempotency-Key", "ai-summary:APP-ONE:WF-ONE").contentType(MediaType.APPLICATION_JSON)
                .content(REQUEST)).andExpect(status().isServiceUnavailable())
                .andExpect(jsonPath("$.code").value("GENAI_UNAVAILABLE"))
                .andExpect(jsonPath("$.retryable").value(true));

        when(service.summarize(any(), eq("ai-summary:APP-ONE:WF-ONE")))
                .thenThrow(ReviewAssistanceException.unsafeModelOutput());
        mockMvc.perform(post(ENDPOINT)
                .with(token("cloudbank-service-client", "service", "SCOPE_cloudbank.internal"))
                .header("Idempotency-Key", "ai-summary:APP-ONE:WF-ONE").contentType(MediaType.APPLICATION_JSON)
                .content(REQUEST)).andExpect(status().isBadGateway())
                .andExpect(jsonPath("$.code").value("GENAI_OUTPUT_REJECTED"));
    }

    @Test
    void rejectsInvalidWorkflowInputWithASafeResponse() throws Exception {
        mockMvc.perform(post(ENDPOINT)
                .with(token("cloudbank-service-client", "service", "SCOPE_cloudbank.internal"))
                .header("Idempotency-Key", "short").contentType(MediaType.APPLICATION_JSON).content("{}"))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.code").value("VALIDATION_FAILED"));
    }

    private static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.JwtRequestPostProcessor token(
            String clientId, String tokenKind, String authority) {
        return jwt().jwt(jwt -> jwt.claim("client_id", clientId).claim("token_kind", tokenKind).claim("scope",
                authority.substring("SCOPE_".length()))).authorities(new SimpleGrantedAuthority(authority));
    }

    private static DocumentEvidenceSummaryResponse response() {
        return new DocumentEvidenceSummaryResponse("AISUM-00000000000000000000000000000000", "COMPLETED",
                "oci-genai", "test-chat-model", "APP-ONE", "WF-ONE",
                "ai_document_evidence_summary", "0123456789abcdef0123456789abcdef",
                "DREV-00000000000000000000000000000000", "UNDERWRITER", "Fixed summary.", List.of(), List.of(),
                List.of(), "PASSED", List.of());
    }
}
