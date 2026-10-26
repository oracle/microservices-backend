// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.

package com.cloudbank.documentingest.api;

import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.cloudbank.documentingest.model.ReviewInputModels.ReviewInputResponse;
import com.cloudbank.documentingest.security.InternalAuthorization;
import com.cloudbank.documentingest.security.SecurityConfig;
import com.cloudbank.documentingest.service.ReviewInputService;
import com.cloudbank.documentingest.service.WorkflowExtractionService;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest({ReviewInputController.class, WorkflowExtractionController.class})
@Import({InternalAuthorization.class, SecurityConfig.class})
class ReviewInputControllerSecurityTest {
    private static final String ENDPOINT = "/internal/api/v1/applications/APP-ONE/extractions/review-input";
    @Autowired
    private MockMvc mvc;
    @MockitoBean
    private ReviewInputService reviewInput;
    @MockitoBean
    private WorkflowExtractionService extraction;

    @Test
    void allowsAiIdentityToReadOnlyTheBoundedProjection() throws Exception {
        when(reviewInput.reviewInput("APP-ONE")).thenReturn(new ReviewInputResponse("APP-ONE", List.of()));
        mvc.perform(get(ENDPOINT).with(serviceToken("cloudbank-ai-agent-client"))).andExpect(status().isOk());
        mvc.perform(post("/internal/api/v1/document-extractions").with(serviceToken("cloudbank-ai-agent-client"))
                .header("Idempotency-Key", "synthetic:test:extract").contentType(MediaType.APPLICATION_JSON)
                .content("""
                        {"applicationId":"APP-ONE","workflowId":"WF-ONE","taskReference":"extract_documents","traceId":"0123456789abcdef0123456789abcdef"}
                        """))
                .andExpect(status().isForbidden());
    }

    @Test
    void rejectsAnonymousUnknownAndUserCallers() throws Exception {
        mvc.perform(get(ENDPOINT)).andExpect(status().isUnauthorized());
        mvc.perform(get(ENDPOINT).with(serviceToken("unknown-client"))).andExpect(status().isForbidden());
        mvc.perform(get(ENDPOINT).with(jwt().jwt(token -> token.claim("client_id", "cloudbank-ai-agent-client")
                        .claim("token_kind", "user"))
                .authorities(new SimpleGrantedAuthority("SCOPE_cloudbank.internal"))))
                .andExpect(status().isForbidden());
    }

    private static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.JwtRequestPostProcessor serviceToken(String id) {
        return jwt().jwt(token -> token.claim("client_id", id).claim("token_kind", "service"))
                .authorities(new SimpleGrantedAuthority("SCOPE_cloudbank.internal"));
    }
}
