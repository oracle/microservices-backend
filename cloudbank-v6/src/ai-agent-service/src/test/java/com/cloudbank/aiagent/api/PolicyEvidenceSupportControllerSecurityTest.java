// Copyright (c) 2026, Oracle and/or its affiliates.
//
// Licensed under the Universal Permissive License v 1.0 as shown at
// https://oss.oracle.com/licenses/upl/.

package com.cloudbank.aiagent.api;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.cloudbank.aiagent.api.AiAgentApiModels.PolicyEvidenceSupportResponse;
import com.cloudbank.aiagent.security.InternalAuthorization;
import com.cloudbank.aiagent.security.SecurityConfig;
import com.cloudbank.aiagent.service.DeterministicPolicyEvidenceSupportService;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(PolicyEvidenceSupportController.class)
@Import({ ApiExceptionHandler.class, InternalAuthorization.class, SecurityConfig.class })
class PolicyEvidenceSupportControllerSecurityTest {
    private static final String ENDPOINT = "/internal/api/v1/ai/policy-evidence-summaries";
    private static final String REQUEST = """
            {
              "applicationId":"APP-ONE",
              "workflowId":"WF-ONE",
              "taskReference":"ai_policy_evidence_support",
              "traceId":"0123456789abcdef0123456789abcdef",
              "reviewId":"DREV-00000000000000000000000000000000",
              "documentSummaryId":"AISUM-00000000000000000000000000000000",
              "audience":"UNDERWRITER",
              "policyEvidence":[{
                "policyDocumentId":"POLICY-DOC-001",
                "policyCode":"CB-PL-001",
                "policyVersion":"2026.0",
                "chunkId":"CHUNK-INCOME-1",
                "sectionRef":"SEC-INCOME",
                "heading":"Verified income",
                "content":"Use verified income evidence for affordability checks.",
                "vectorScore":0.93
              }]
            }
            """;

    @Autowired
    private MockMvc mockMvc;

    @MockitoBean
    private DeterministicPolicyEvidenceSupportService service;

    @Test
    void rejectsAnonymousAndUnauthorizedCallers() throws Exception {
        mockMvc.perform(post(ENDPOINT).header("Idempotency-Key", "ai-policy:APP-ONE:WF-ONE")
                .contentType(MediaType.APPLICATION_JSON).content(REQUEST)).andExpect(status().isUnauthorized());

        mockMvc.perform(post(ENDPOINT).with(token("unknown-client", "service", "SCOPE_cloudbank.internal"))
                .header("Idempotency-Key", "ai-policy:APP-ONE:WF-ONE").contentType(MediaType.APPLICATION_JSON)
                .content(REQUEST)).andExpect(status().isForbidden());

        mockMvc.perform(post(ENDPOINT)
                .with(token("cloudbank-service-client", "service", "SCOPE_cloudbank.read"))
                .header("Idempotency-Key", "ai-policy:APP-ONE:WF-ONE").contentType(MediaType.APPLICATION_JSON)
                .content(REQUEST)).andExpect(status().isForbidden());
    }

    @Test
    void eligibleServiceTokenReceivesGroundedPolicySupport() throws Exception {
        when(service.summarize(any(), eq("ai-policy:APP-ONE:WF-ONE"))).thenReturn(response());

        mockMvc.perform(post(ENDPOINT)
                .with(token("cloudbank-service-client", "service", "SCOPE_cloudbank.internal"))
                .header("Idempotency-Key", "ai-policy:APP-ONE:WF-ONE").contentType(MediaType.APPLICATION_JSON)
                .content(REQUEST)).andExpect(status().isOk())
                .andExpect(jsonPath("$.policySupportId").value("AIPOL-00000000000000000000000000000000"))
                .andExpect(jsonPath("$.status").value("COMPLETED"))
                .andExpect(jsonPath("$.evidenceStatus").value("GROUNDED"))
                .andExpect(jsonPath("$.guardrailStatus").value("PASSED"));

        verify(service).summarize(any(), eq("ai-policy:APP-ONE:WF-ONE"));
    }

    @Test
    void rejectsInvalidOrUnboundedEvidenceWithASafeResponse() throws Exception {
        String invalidRequest = REQUEST.replace(
                "\"content\":\"Use verified income evidence for affordability checks.\"",
                "\"content\":\"\"");
        mockMvc.perform(post(ENDPOINT)
                .with(token("cloudbank-service-client", "service", "SCOPE_cloudbank.internal"))
                .header("Idempotency-Key", "ai-policy:APP-ONE:WF-ONE").contentType(MediaType.APPLICATION_JSON)
                .content(invalidRequest)).andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("VALIDATION_FAILED"));
    }

    private static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.JwtRequestPostProcessor token(
            String clientId, String tokenKind, String authority) {
        return jwt().jwt(jwt -> jwt.claim("client_id", clientId).claim("token_kind", tokenKind).claim("scope",
                authority.substring("SCOPE_".length()))).authorities(new SimpleGrantedAuthority(authority));
    }

    private static PolicyEvidenceSupportResponse response() {
        return new PolicyEvidenceSupportResponse("AIPOL-00000000000000000000000000000000", "COMPLETED",
                "deterministic-fixture", "fixed-response-v1", "APP-ONE", "WF-ONE",
                "ai_policy_evidence_support", "0123456789abcdef0123456789abcdef",
                "DREV-00000000000000000000000000000000", "AISUM-00000000000000000000000000000000",
                "UNDERWRITER", "GROUNDED", "Fixed policy support.", List.of(), List.of(), List.of(), "PASSED");
    }
}
