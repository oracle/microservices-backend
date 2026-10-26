// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.

package com.cloudbank.gatewaybff;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.context.bean.override.mockito.MockitoBean;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.csrf;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.oauth2Login;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

@SpringBootTest(properties = {
        "BFF_OAUTH_CLIENT_SECRET=test-only-client-secret",
        "BFF_CALLBACK_URI=http://127.0.0.1:5173/bff/auth/callback",
        "BFF_ISSUER_URI=http://issuer.example",
        "BFF_AUTHORIZATION_URI=http://issuer.example/oauth2/authorize",
        "BFF_TOKEN_URI=http://issuer.example/oauth2/token",
        "BFF_JWK_SET_URI=http://issuer.example/oauth2/jwks",
        "BFF_USERINFO_URI=http://issuer.example/userinfo",
        "BFF_LOAN_BASE_URL=http://loan.example"
})
@AutoConfigureMockMvc
class BffHttpSecurityTest {
    @Autowired
    private MockMvc mvc;
    @MockitoBean
    private SessionIdentity identity;

    @Test
    void anonymousBrowserGetsSafeSessionError() throws Exception {
        mvc.perform(get("/bff/api/v1/session"))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("UNAUTHENTICATED"));
    }

    @Test
    void loginStartsTheServerSideAuthorizationFlow() throws Exception {
        mvc.perform(get("/bff/auth/login"))
                .andExpect(status().isFound())
                .andExpect(header().string("Location", "/oauth2/authorization/cloudbank-bff"));
    }

    @Test
    void applicationCreationRequiresCsrfEvenForAuthenticatedBrowser() throws Exception {
        mvc.perform(post("/bff/api/v1/applications").with(oauth2Login())
                .contentType("application/json").content("{}"))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.authorizationStatus").value("DENIED"));
    }

    @Test
    void applicationCreationRequiresAuthenticationEvenWithCsrf() throws Exception {
        mvc.perform(post("/bff/api/v1/applications").with(csrf())
                .contentType("application/json").content("{}"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void uploadAndStartRequireCsrfForAuthenticatedBrowsers() throws Exception {
        mvc.perform(put("/bff/api/v1/applications/APP-new/documents/DOC-new/content").with(oauth2Login())
                .contentType("application/pdf").content("%PDF synthetic"))
                .andExpect(status().isForbidden()).andExpect(jsonPath("$.authorizationStatus").value("DENIED"));
        mvc.perform(post("/bff/api/v1/applications/APP-new/workflow-start").with(oauth2Login()))
                .andExpect(status().isForbidden()).andExpect(jsonPath("$.authorizationStatus").value("DENIED"));
    }

    @Test
    void uploadAndStartRequireLoginEvenWithCsrf() throws Exception {
        mvc.perform(put("/bff/api/v1/applications/APP-new/documents/DOC-new/content").with(csrf())
                .contentType("application/pdf").content("%PDF synthetic"))
                .andExpect(status().isUnauthorized());
        mvc.perform(post("/bff/api/v1/applications/APP-new/workflow-start").with(csrf()))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void admittedSessionWithCsrfReachesTheUploadBoundary() throws Exception {
        when(identity.requireWrite(any(), any())).thenReturn(
                new SessionIdentity.AuthorizedUser("obaas-admin", "server-held-test-token", null));
        mvc.perform(put("/bff/api/v1/applications/APP-new/documents/DOC-new/content")
                .with(oauth2Login()).with(csrf()).header("Idempotency-Key", "upload-test-key")
                .contentType("application/pdf"))
                .andExpect(status().is(413)).andExpect(jsonPath("$.code").value("DOCUMENT_SIZE_INVALID"));
    }

    @Test
    void admittedSessionWithCsrfReachesTheExplicitStartBoundary() throws Exception {
        when(identity.requireWrite(any(), any())).thenReturn(
                new SessionIdentity.AuthorizedUser("obaas-admin", "server-held-test-token", null));
        mvc.perform(post("/bff/api/v1/applications/APP-new/workflow-start")
                .with(oauth2Login()).with(csrf()).contentType("application/json").content("{}"))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.code").value("BAD_REQUEST"));
    }

    @Test
    void logoutRequiresCsrf() throws Exception {
        mvc.perform(post("/bff/auth/logout"))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.authorizationStatus").value("DENIED"));
    }

    @Test
    void humanTaskRoutesRequireLoginAndResolutionRequiresCsrf() throws Exception {
        mvc.perform(get("/bff/api/v1/manual-review/tasks")).andExpect(status().isUnauthorized());
        mvc.perform(get("/bff/api/v1/manual-review/tasks/task-one")).andExpect(status().isUnauthorized());
        mvc.perform(post("/bff/api/v1/manual-review/tasks/task-one/resolution").with(csrf())
                .contentType("application/json").content("{}"))
                .andExpect(status().isUnauthorized());
        mvc.perform(post("/bff/api/v1/manual-review/tasks/task-one/resolution").with(oauth2Login())
                .contentType("application/json").content("{}"))
                .andExpect(status().isForbidden()).andExpect(jsonPath("$.authorizationStatus").value("DENIED"));
    }

    @Test
    void csrfProtectedHumanCompletionReachesTheController() throws Exception {
        when(identity.requireReviewer(any(), any())).thenReturn(new SessionIdentity.AuthorizedReviewer(
                new SessionIdentity.AuthorizedUser("obaas-admin", "synthetic-token", null), "signed-reviewer"));
        mvc.perform(post("/bff/api/v1/manual-review/tasks/task-one/resolution").with(oauth2Login()).with(csrf())
                .header("Idempotency-Key", "resolution-one").contentType("application/json").content("{}"))
                .andExpect(status().isBadRequest());
    }
}
