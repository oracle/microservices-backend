// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.policyretrieval.rest;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.cloudbank.policyretrieval.model.AiUse;
import com.cloudbank.policyretrieval.model.PolicyRole;
import com.cloudbank.policyretrieval.retrieve.PolicyRetrievalService;
import com.cloudbank.policyretrieval.retrieve.RetrievalRequest;
import com.cloudbank.policyretrieval.security.InternalAuthorization;
import com.cloudbank.policyretrieval.security.SecurityConfig;
import com.cloudbank.policyretrieval.vector.EmbeddingModel;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(PolicyRetrievalController.class)
@Import({ AiUseConverter.class, InternalAuthorization.class, SecurityConfig.class })
class PolicyRetrievalControllerSecurityTest {
    private static final String ENDPOINT = "/internal/api/v1/policy-evidence";

    @Autowired
    private MockMvc mockMvc;

    @MockitoBean
    private PolicyRetrievalService policyRetrievalService;

    @MockitoBean
    private EmbeddingModel embeddingModel;

    @Test
    void rejectsAnonymousUserAndUnauthorizedServiceCallers() throws Exception {
        mockMvc.perform(get(ENDPOINT).param("query", "loan underwriting"))
                .andExpect(status().isUnauthorized());

        mockMvc.perform(get(ENDPOINT).param("query", "loan underwriting")
                .with(token("cloudbank-service-client", "user", "SCOPE_cloudbank.internal")))
                .andExpect(status().isForbidden());

        mockMvc.perform(get(ENDPOINT).param("query", "loan underwriting")
                .with(token("unknown-client", "service", "SCOPE_cloudbank.internal")))
                .andExpect(status().isForbidden());

        mockMvc.perform(get(ENDPOINT).param("query", "loan underwriting")
                .with(token("cloudbank-service-client", "service", "SCOPE_cloudbank.read")))
                .andExpect(status().isForbidden());
    }

    @Test
    void serviceTokenReceivesBoundedUnderwriterEvidence() throws Exception {
        when(embeddingModel.embed("loan underwriting")).thenReturn(new float[] { 0.25f });
        when(policyRetrievalService.search(any(), eq(3))).thenReturn(List.of());

        mockMvc.perform(get(ENDPOINT).param("query", "loan underwriting")
                .with(token("cloudbank-service-client", "service", "SCOPE_cloudbank.internal")))
                .andExpect(status().isOk());

        ArgumentCaptor<RetrievalRequest> requestCaptor = ArgumentCaptor.forClass(RetrievalRequest.class);
        verify(policyRetrievalService).search(requestCaptor.capture(), eq(3));
        assertThat(requestCaptor.getValue().content()).isEqualTo("loan underwriting");
        assertThat(requestCaptor.getValue().aiUse()).isEqualTo(AiUse.RETRIEVAL);
        assertThat(requestCaptor.getValue().policyRole()).isEqualTo(PolicyRole.UNDERWRITER);
    }

    private static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.JwtRequestPostProcessor token(
            String clientId, String tokenKind, String authority) {
        return jwt().jwt(jwt -> jwt.claim("client_id", clientId).claim("token_kind", tokenKind).claim("scope",
                authority.substring("SCOPE_".length()))).authorities(new SimpleGrantedAuthority(authority));
    }
}
