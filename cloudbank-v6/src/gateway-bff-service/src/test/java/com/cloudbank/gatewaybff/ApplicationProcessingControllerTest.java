// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.

package com.cloudbank.gatewaybff;

import jakarta.servlet.http.HttpServletRequest;
import java.io.ByteArrayInputStream;
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

import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.not;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.client.ExpectedCount.twice;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.content;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.header;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withStatus;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

class ApplicationProcessingControllerTest {
    private static final byte[] PDF = "%PDF-1.7\nSynthetic test content".getBytes(StandardCharsets.UTF_8);
    private static final String UPLOAD = "/bff/api/v1/applications/APP-new/documents/DOC-new/content";
    private static final String LOAN_UPLOAD = "http://loan.example/api/v1/loan-applications/APP-new/documents/DOC-new/content";
    private static final String START = "/bff/api/v1/applications/APP-new/workflow-start";
    private static final String LOAN_START = "http://loan.example/api/v1/loan-applications/APP-new/workflow-start";
    private static final String START_RESULT = """
            {"applicationId":"APP-new","scenarioId":"SCN-new","scenarioName":"Synthetic application",
             "status":"SUBMITTED","documents":[{"documentId":"DOC-new","documentType":"LOAN_APPLICATION",
               "fileName":"loan.pdf","required":true,"status":"RECEIVED"}],
             "workflow":{"startRequestId":"WFR-new","workflowName":"cloudbank-loan-origination",
               "workflowVersion":1,"dispatchStatus":"PENDING","workflowId":null,"lastErrorMessage":"secret"}}
            """;
    private SessionIdentity identity;
    private MockRestServiceServer upstream;
    private MockMvc mvc;
    private ApplicationProcessingController controller;

    @BeforeEach
    void setup() {
        identity = mock(SessionIdentity.class);
        when(identity.requireWrite(any(), any(HttpServletRequest.class)))
                .thenReturn(new SessionIdentity.AuthorizedUser("obaas-admin", "server-held-token", null));
        RestClient.Builder builder = RestClient.builder();
        upstream = MockRestServiceServer.bindTo(builder).build();
        controller = new ApplicationProcessingController(identity, "http://loan.example", builder);
        mvc = MockMvcBuilders.standaloneSetup(controller)
                .setControllerAdvice(new BffErrorHandler()).build();
    }

    @Test
    void forwardsOnlyPdfBytesToTheAuthorizedLoanBoundaryAndSupportsIdenticalRetry() throws Exception {
        upstream.expect(twice(), requestTo(LOAN_UPLOAD)).andExpect(method(HttpMethod.PUT))
                .andExpect(header("Authorization", "Bearer server-held-token"))
                .andExpect(header("Idempotency-Key", "upload-operation-1"))
                .andExpect(header("X-Correlation-ID", org.hamcrest.Matchers.matchesPattern("[0-9a-f-]{36}")))
                .andExpect(content().contentType(MediaType.APPLICATION_PDF)).andExpect(content().bytes(PDF))
                .andRespond(withSuccess(uploadResult(PDF.length), MediaType.APPLICATION_JSON));
        for (int i = 0; i < 2; i++) {
            mvc.perform(put(UPLOAD).header("Idempotency-Key", "upload-operation-1")
                    .contentType(MediaType.APPLICATION_PDF).content(PDF))
                    .andExpect(status().isOk()).andExpect(jsonPath("$.documentId").value("DOC-new"))
                    .andExpect(jsonPath("$.status").value("RECEIVED"))
                    .andExpect(jsonPath("$.contentLengthBytes").value(PDF.length))
                    .andExpect(jsonPath("$.correlationId").isNotEmpty())
                    .andExpect(org.springframework.test.web.servlet.result.MockMvcResultMatchers.content()
                            .string(not(containsString("secret"))));
        }
        upstream.verify();
    }

    @ParameterizedTest
    @ValueSource(ints = {1, 25 * 1024 * 1024})
    void acceptsBothDocumentSizeBoundaries(int size) throws Exception {
        byte[] bytes = new byte[size];
        upstream.expect(requestTo(LOAN_UPLOAD)).andExpect(content().bytes(bytes))
                .andRespond(withSuccess(uploadResult(size), MediaType.APPLICATION_JSON));
        mvc.perform(put(UPLOAD).header("Idempotency-Key", "upload-operation-1")
                .contentType(MediaType.APPLICATION_PDF).content(bytes)).andExpect(status().isOk());
        upstream.verify();
    }

    @Test
    void rejectsOversizedStreamEvenWhenContentLengthIsUnknown() throws Exception {
        HttpServletRequest request = mock(HttpServletRequest.class);
        when(request.getContentLengthLong()).thenReturn(-1L);
        when(request.getInputStream()).thenReturn(new org.springframework.mock.web.DelegatingServletInputStream(
                new ByteArrayInputStream(new byte[25 * 1024 * 1024 + 1])));
        assertThatThrownBy(() -> controller.upload("APP-new", "DOC-new", "upload-operation-1",
                "application/pdf", null, request))
                .isInstanceOfSatisfying(ResponseStatusException.class,
                        error -> org.assertj.core.api.Assertions.assertThat(error.getStatusCode().value()).isEqualTo(413));
        upstream.verify();
    }

    @Test
    void rejectsEmptyAndUnsupportedContentWithoutCallingLoan() throws Exception {
        mvc.perform(put(UPLOAD).header("Idempotency-Key", "upload-operation-1")
                .contentType(MediaType.APPLICATION_PDF).content(new byte[0])).andExpect(status().is(413));
        mvc.perform(put(UPLOAD).header("Idempotency-Key", "upload-operation-1")
                .contentType(MediaType.TEXT_PLAIN).content(PDF)).andExpect(status().isUnsupportedMediaType());
        upstream.verify();
    }

    @Test
    void normalizesPdfMediaTypeParametersBeforeForwarding() throws Exception {
        upstream.expect(requestTo(LOAN_UPLOAD))
                .andExpect(content().contentType(MediaType.APPLICATION_PDF))
                .andRespond(withSuccess(uploadResult(PDF.length), MediaType.APPLICATION_JSON));
        mvc.perform(put(UPLOAD).header("Idempotency-Key", "upload-operation-1")
                .contentType("application/pdf;charset=UTF-8").content(PDF)).andExpect(status().isOk());
        upstream.verify();
    }

    @ParameterizedTest
    @ValueSource(strings = {"text/plain", "application/*", "*/*"})
    void rejectsOtherOrWildcardMediaTypes(String mediaType) throws Exception {
        mvc.perform(put(UPLOAD).header("Idempotency-Key", "upload-operation-1")
                .contentType(mediaType).content(PDF)).andExpect(status().isUnsupportedMediaType());
        upstream.verify();
    }

    @Test
    void requiresValidPathAndIdempotencyKey() throws Exception {
        mvc.perform(put(UPLOAD).header("Idempotency-Key", "bad!")
                .contentType(MediaType.APPLICATION_PDF).content(PDF)).andExpect(status().isBadRequest());
        mvc.perform(put(UPLOAD.replace("DOC-new", "invalid" )).header("Idempotency-Key", "upload-operation-1")
                .contentType(MediaType.APPLICATION_PDF).content(PDF)).andExpect(status().isBadRequest());
        upstream.verify();
    }

    @ParameterizedTest
    @ValueSource(ints = {403, 404, 409, 413, 415, 503})
    void preservesSafeOwnerRejections(int code) throws Exception {
        upstream.expect(requestTo(LOAN_UPLOAD))
                .andRespond(withStatus(HttpStatus.valueOf(code)).body("secret SQL and bearer credentials"));
        mvc.perform(put(UPLOAD).header("Idempotency-Key", "upload-operation-1")
                .contentType(MediaType.APPLICATION_PDF).content(PDF)).andExpect(status().is(code))
                .andExpect(jsonPath("$.correlationId").isNotEmpty())
                .andExpect(org.springframework.test.web.servlet.result.MockMvcResultMatchers.content()
                        .string(not(containsString("secret"))));
        upstream.verify();
    }

    @Test
    void rejectsAReceiptForAnotherDocument() throws Exception {
        upstream.expect(requestTo(LOAN_UPLOAD))
                .andRespond(withSuccess(uploadResult(PDF.length).replace("DOC-new", "DOC-other"), MediaType.APPLICATION_JSON));
        mvc.perform(put(UPLOAD).header("Idempotency-Key", "upload-operation-1")
                .contentType(MediaType.APPLICATION_PDF).content(PDF)).andExpect(status().isBadGateway());
        upstream.verify();
    }

    @Test
    void releasesOnlyThroughLoanWithAnEmptyBodyAndNoWorkflowCredentials() throws Exception {
        upstream.expect(twice(), requestTo(LOAN_START)).andExpect(method(HttpMethod.POST))
                .andExpect(header("Authorization", "Bearer server-held-token"))
                .andExpect(content().string(""))
                .andRespond(withSuccess(START_RESULT, MediaType.APPLICATION_JSON));
        for (int i = 0; i < 2; i++) {
            mvc.perform(post(START)).andExpect(status().isAccepted())
                    .andExpect(jsonPath("$.workflow.dispatchStatus").value("PENDING"))
                    .andExpect(jsonPath("$.correlationId").isNotEmpty())
                    .andExpect(org.springframework.test.web.servlet.result.MockMvcResultMatchers.content()
                            .string(not(containsString("secret"))));
        }
        upstream.verify();
    }

    @Test
    void rejectsStartPayloadAndMismatchedOwnerResponse() throws Exception {
        mvc.perform(post(START).contentType(MediaType.APPLICATION_JSON).content("{\"workflowStartMode\":\"AUTO\"}"))
                .andExpect(status().isBadRequest());
        upstream.expect(requestTo(LOAN_START))
                .andRespond(withSuccess(START_RESULT.replace("APP-new", "APP-other"), MediaType.APPLICATION_JSON));
        mvc.perform(post(START)).andExpect(status().isBadGateway());
        upstream.verify();
    }

    @Test
    void upstreamUnauthorizedDoesNotExpireTheBrowserSession() throws Exception {
        upstream.expect(requestTo(LOAN_START)).andRespond(withStatus(HttpStatus.UNAUTHORIZED));
        mvc.perform(post(START)).andExpect(status().isBadGateway())
                .andExpect(jsonPath("$.authorizationStatus").value("AUTHENTICATED"));
        upstream.verify();
    }

    @Test
    void readOnlyIdentityCannotUploadOrRelease() throws Exception {
        when(identity.requireWrite(any(), any(HttpServletRequest.class)))
                .thenThrow(new ResponseStatusException(HttpStatus.FORBIDDEN));
        mvc.perform(put(UPLOAD).header("Idempotency-Key", "upload-operation-1")
                .contentType(MediaType.APPLICATION_PDF).content(PDF)).andExpect(status().isForbidden());
        mvc.perform(post(START)).andExpect(status().isForbidden());
        upstream.verify();
    }

    private static String uploadResult(int length) {
        return """
                {"documentId":"DOC-new","status":"RECEIVED","mediaType":"application/pdf",
                 "contentLengthBytes":%d,"contentSha256":"%s","internal":"secret"}
                """.formatted(length, "a".repeat(64));
    }
}
