// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.

package com.cloudbank.gatewaybff;

import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.not;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.header;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withStatus;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.nio.charset.StandardCharsets;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.client.RestClient;
import org.springframework.web.server.ResponseStatusException;

class ApplicationWorkspaceControllerTest {
    private static final String PATH = "/bff/api/v1/applications/APP-test";
    private static final String CONTENT = PATH + "/documents/DOC-test/content";
    private static final String OWNER = "http://loan.example/api/v1/loan-applications/APP-test";
    private static final String WORKSPACE = """
            {"applicationId":"APP-test","scenarioName":"Synthetic application","status":"PROCESSING",
             "overview":{"applicant":{"displayName":"Synthetic Applicant","password":"withheld"},
                         "loan":{"requestedAmount":5000,"requestedTermMonths":24}},
             "workflow":{"workflowId":"WF-test","dispatchStatus":"STARTED","lastErrorMessage":"withheld"},
             "documents":[{"documentId":"DOC-test","documentType":"LOAN_APPLICATION","fileName":"loan.pdf",
               "status":"VALIDATED","required":true,"contentAvailable":true,"mediaType":"application/pdf",
               "contentLengthBytes":16,"rawText":"withheld","fileContent":"withheld"}],
             "workflowTaskAuthorization":"withheld","documentsTruncated":false}
            """;
    private SessionIdentity identity;
    private MockRestServiceServer upstream;
    private MockMvc mvc;

    @BeforeEach
    void setup() {
        identity = mock(SessionIdentity.class);
        when(identity.require(any(), any())).thenReturn(
                new SessionIdentity.AuthorizedUser("obaas-admin", "synthetic-server-token", null));
        RestClient.Builder builder = RestClient.builder();
        upstream = MockRestServiceServer.bindTo(builder).build();
        WorkspaceReadService reads = mock(WorkspaceReadService.class);
        when(reads.compose(any(), any(), any(), any())).thenReturn(new WorkspaceReadService.Sections(
                ApplicationWorkspaceController.Section.unavailable("Not configured in the controller fixture."),
                ApplicationWorkspaceController.Section.unavailable("Not configured in the controller fixture."),
                ApplicationWorkspaceController.Section.unavailable("Not configured in the controller fixture."),
                ApplicationWorkspaceController.Section.unavailable("Not configured in the controller fixture."),
                ApplicationWorkspaceController.Section.unavailable("Not configured in the controller fixture.")));
        TraceReadService traces = mock(TraceReadService.class);
        when(traces.compose(any(), any(), any())).thenReturn(
                ApplicationWorkspaceController.Section.unavailable("Not configured in the controller fixture."));
        mvc = MockMvcBuilders.standaloneSetup(new ApplicationWorkspaceController(identity, "http://loan.example", builder, reads, traces))
                .setControllerAdvice(new BffErrorHandler()).build();
    }

    @Test
    void composesNineSectionsAndProjectsOnlyAuthorizedOwnerFieldsWithoutLoadingPdf() throws Exception {
        upstream.expect(requestTo(OWNER + "/workspace")).andExpect(method(HttpMethod.GET))
                .andExpect(header("Authorization", "Bearer synthetic-server-token"))
                .andExpect(header("X-Correlation-ID", org.hamcrest.Matchers.matchesPattern("[0-9a-f-]{36}")))
                .andRespond(withSuccess(WORKSPACE, MediaType.APPLICATION_JSON));
        upstream.expect(requestTo(OWNER + "/audit")).andExpect(method(HttpMethod.GET))
                .andRespond(withSuccess("""
                        {"applicationId":"APP-test","items":[],"truncated":false}
                        """, MediaType.APPLICATION_JSON));
        mvc.perform(get(PATH)).andExpect(status().isOk())
                .andExpect(jsonPath("$.source").value("LIVE"))
                .andExpect(jsonPath("$.overview.data.applicant.displayName").value("Synthetic Applicant"))
                .andExpect(jsonPath("$.documents.data.items[0].contentAvailable").value(true))
                .andExpect(jsonPath("$.aiWorkflowTasks.availability").value("UNAVAILABLE"))
                .andExpect(jsonPath("$.decision.availability").value("UNAVAILABLE"))
                .andExpect(jsonPath("$.policyEvidence.availability").value("UNAVAILABLE"))
                .andExpect(jsonPath("$.riskSignals.availability").value("UNAVAILABLE"))
                .andExpect(jsonPath("$.workflow.availability").value("UNAVAILABLE"))
                .andExpect(jsonPath("$.audit.availability").value("AVAILABLE"))
                .andExpect(jsonPath("$.trace.availability").value("UNAVAILABLE"))
                .andExpect(content().string(not(containsString("withheld"))))
                .andExpect(org.springframework.test.web.servlet.result.MockMvcResultMatchers.header()
                        .string("Cache-Control", "private, no-store"));
        upstream.verify();
    }

    @Test
    void streamsPdfUsingUserAuthorizationAndRebuildsSafeHeaders() throws Exception {
        byte[] pdf = "%PDF-1.7\nSynthetic".getBytes(StandardCharsets.UTF_8);
        upstream.expect(requestTo(OWNER + "/documents/DOC-test/content"))
                .andExpect(header("Authorization", "Bearer synthetic-server-token"))
                .andExpect(header("Accept", "application/pdf"))
                .andRespond(withSuccess(pdf, MediaType.APPLICATION_PDF)
                        .header("Content-Disposition", "inline; filename=loan.pdf")
                        .header("Set-Cookie", "do-not-forward")
                        .header("Content-Length", String.valueOf(pdf.length)));
        mvc.perform(get(CONTENT)).andExpect(status().isOk()).andExpect(content().bytes(pdf))
                .andExpect(content().contentType(MediaType.APPLICATION_PDF))
                .andExpect(org.springframework.test.web.servlet.result.MockMvcResultMatchers.header()
                        .string("Cache-Control", "private, no-store"))
                .andExpect(org.springframework.test.web.servlet.result.MockMvcResultMatchers.header()
                        .string("X-Content-Type-Options", "nosniff"))
                .andExpect(org.springframework.test.web.servlet.result.MockMvcResultMatchers.header().doesNotExist("Set-Cookie"));
        upstream.verify();
    }

    @ParameterizedTest
    @ValueSource(ints = {403, 404, 503})
    void preservesSafeAccessAndMissingContentErrors(int code) throws Exception {
        upstream.expect(requestTo(OWNER + "/documents/DOC-test/content"))
                .andRespond(withStatus(HttpStatus.valueOf(code)).body("withheld upstream detail"));
        mvc.perform(get(CONTENT)).andExpect(status().is(code))
                .andExpect(content().string(not(containsString("withheld"))));
        upstream.verify();
    }

    @Test
    void upstreamTokenFailureDoesNotImpersonateAnExpiredBrowserSession() throws Exception {
        upstream.expect(requestTo(OWNER + "/documents/DOC-test/content"))
                .andRespond(withStatus(HttpStatus.UNAUTHORIZED));
        mvc.perform(get(CONTENT)).andExpect(status().isBadGateway());
        upstream.verify();
    }

    @Test
    void rejectsMismatchedApplicationAndUnsupportedPdfResponse() throws Exception {
        upstream.expect(requestTo(OWNER + "/workspace"))
                .andRespond(withSuccess(WORKSPACE.replace("APP-test", "APP-other"), MediaType.APPLICATION_JSON));
        upstream.expect(requestTo(OWNER + "/documents/DOC-test/content"))
                .andRespond(withSuccess("withheld", MediaType.TEXT_HTML));
        mvc.perform(get(PATH)).andExpect(status().isBadGateway());
        mvc.perform(get(CONTENT)).andExpect(status().isBadGateway());
        upstream.verify();
    }

    @ParameterizedTest
    @ValueSource(ints = {0, 25 * 1024 * 1024 + 1})
    void rejectsEmptyOrOversizedPdfWithoutTrustingDeclaredLength(int size) throws Exception {
        upstream.expect(requestTo(OWNER + "/documents/DOC-test/content"))
                .andRespond(withSuccess(new byte[size], MediaType.APPLICATION_PDF));
        mvc.perform(get(CONTENT)).andExpect(status().isBadGateway());
        upstream.verify();
    }

    @Test
    void rejectsInvalidIdsAndDeniedSessionBeforeContactingOwner() throws Exception {
        mvc.perform(get(PATH + "/documents/invalid/content")).andExpect(status().isBadRequest());
        when(identity.require(any(), any())).thenThrow(new ResponseStatusException(HttpStatus.UNAUTHORIZED));
        mvc.perform(get(PATH)).andExpect(status().isUnauthorized());
        mvc.perform(get(CONTENT)).andExpect(status().isUnauthorized());
        upstream.verify();
    }
}
