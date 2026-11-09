// Copyright (c) 2026, Oracle and/or its affiliates.
package com.cloudbank.loanapplication.api;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.cloudbank.loanapplication.config.SecurityConfig;
import com.cloudbank.loanapplication.security.LoanAuthorization;
import com.cloudbank.loanapplication.service.LoanApplicationService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.RequestPostProcessor;

@WebMvcTest(LoanApplicationController.class)
@Import({SecurityConfig.class, LoanAuthorization.class})
class LoanPreviewSecurityTest {
    @Autowired private MockMvc mvc;
    @MockitoBean private LoanApplicationService service;
    @MockitoBean private JwtDecoder decoder;
    private static final String CONTENT = "/api/v1/loan-applications/APP-test/documents/DOC-test/content";

    private RequestPostProcessor user(String scope) {
        return jwt().jwt(j -> j.claim("token_kind", "user").claim("cb_principal_id", "synthetic-user"))
                .authorities(new SimpleGrantedAuthority("SCOPE_" + scope), new SimpleGrantedAuthority("ROLE_APPLICANT"));
    }

    @Test
    void readOnlyUserCanPreviewWithoutWriteScopeAndWithSafeInlineHeaders() throws Exception {
        byte[] bytes = {1, 2, 3, 4};
        when(service.previewDocument(anyString(), anyString(), any())).thenReturn(
                new ApplicationApiModels.DocumentPreview("../synthetic\r\nname.pdf", bytes));
        mvc.perform(get(CONTENT).with(user("cloudbank.read"))).andExpect(status().isOk())
                .andExpect(content().bytes(bytes)).andExpect(content().contentType(MediaType.APPLICATION_PDF))
                .andExpect(header().string("Cache-Control", "private, no-store"))
                .andExpect(header().string("X-Content-Type-Options", "nosniff"))
                .andExpect(header().string("Content-Disposition", org.hamcrest.Matchers.startsWith("inline;")));
    }

    @Test
    void requiresReadScopeAndUserIdentityAndPreservesWorkerOnlyBoundary() throws Exception {
        mvc.perform(get(CONTENT)).andExpect(status().isUnauthorized());
        mvc.perform(get(CONTENT).with(user("cloudbank.write"))).andExpect(status().isForbidden());
        mvc.perform(get(CONTENT).with(jwt().jwt(j -> j.claim("token_kind", "service"))
                .authorities(new SimpleGrantedAuthority("SCOPE_cloudbank.read"), new SimpleGrantedAuthority("ROLE_ADMIN"))))
                .andExpect(status().isForbidden());
        mvc.perform(get("/internal" + CONTENT).with(user("cloudbank.read"))).andExpect(status().isForbidden());
        mvc.perform(get("/api/v1/loan-applications/APP-test/workspace").with(user("cloudbank.write")))
                .andExpect(status().isForbidden());
    }
}
