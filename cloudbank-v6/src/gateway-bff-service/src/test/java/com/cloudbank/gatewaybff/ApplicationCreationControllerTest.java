// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.

package com.cloudbank.gatewaybff;

import jakarta.servlet.http.HttpServletRequest;
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

import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.not;
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
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

class ApplicationCreationControllerTest {
    private static final String INPUT = """
            {"scenarioId":"SCN-NEW","scenarioName":"Synthetic Applicant",
             "applicant":{"displayName":"Synthetic Applicant","phoneToken":"PHONE-SYNTH",
               "emailToken":"EMAIL-SYNTH","ageBand":"35-44","address":{"addressLine":"10 Demo Avenue",
               "locality":"Demo City","jurisdictionCode":"US-CA","addressToken":"ADDR-SYNTH",
               "countryCode":"","postalCode":""}},
             "loan":{"requestedAmount":"12000.00","requestedTermMonths":"36",
               "purposeCode":"HOME_IMPROVEMENT","policyVersion":""},
             "documents":[{"documentType":"LOAN_APPLICATION","fileName":"synthetic.pdf","required":true}]}
            """;
    private static final String RESULT = """
            {"applicationId":"APP-NEW-1","scenarioId":"SCN-NEW","scenarioName":"Synthetic Applicant",
             "status":"SUBMITTED","requestedAmount":12000.00,"requestedTermMonths":36,
             "purposeCode":"HOME_IMPROVEMENT","createdAt":"2026-10-15T09:00:00Z",
             "documents":[{"documentId":"DOC-1","documentType":"LOAN_APPLICATION","fileName":"synthetic.pdf",
               "documentLabel":"Loan application","required":true,"status":"EXPECTED","rawContent":"secret"}],
             "workflow":{"startRequestId":"WFR-1","workflowName":"cloudbank-loan-origination",
               "workflowVersion":1,"dispatchStatus":"DEFERRED","workflowId":null,"lastErrorMessage":"secret"},
             "traceId":"trace-1","internalField":"secret"}
            """;
    private MockRestServiceServer upstream;
    private MockMvc mvc;

    @BeforeEach
    void setup() {
        SessionIdentity identity = mock(SessionIdentity.class);
        when(identity.requireWrite(any(), any(HttpServletRequest.class)))
                .thenReturn(new SessionIdentity.AuthorizedUser("obaas-admin", "server-held-token", null));
        RestClient.Builder builder = RestClient.builder();
        upstream = MockRestServiceServer.bindTo(builder).build();
        mvc = MockMvcBuilders.standaloneSetup(new ApplicationCreationController(identity, "http://loan.example", builder))
                .setControllerAdvice(new BffErrorHandler()).build();
    }

    @Test
    void createsOnlyDeferredMetadataAndReusesTheLoanIdempotencyBoundary() throws Exception {
        upstream.expect(twice(), requestTo("http://loan.example/api/v1/loan-applications"))
                .andExpect(method(HttpMethod.POST)).andExpect(header("Authorization", "Bearer server-held-token"))
                .andExpect(header("Idempotency-Key", "create-operation-1"))
                .andExpect(header("X-Correlation-ID", org.hamcrest.Matchers.matchesPattern("[0-9a-f-]{36}")))
                .andExpect(content().json(INPUT.replace("\"requestedAmount\":\"12000.00\"", "\"requestedAmount\":12000.00")
                        .replace("\"requestedTermMonths\":\"36\"", "\"requestedTermMonths\":36")
                        .replace("\"policyVersion\":\"\"", "\"policyVersion\":null")
                        .replace("\"countryCode\":\"\"", "\"countryCode\":null")
                        .replace("\"postalCode\":\"\"", "\"postalCode\":null")
                        .replace("\"required\":true", "\"required\":true,\"status\":\"EXPECTED\"")
                        .replace("\"scenarioId\":", "\"workflowStartMode\":\"DEFERRED\",\"scenarioId\":"),
                        org.springframework.test.json.JsonCompareMode.STRICT))
                .andRespond(withSuccess(RESULT, MediaType.APPLICATION_JSON));
        for (int attempt = 0; attempt < 2; attempt++) {
            mvc.perform(post("/bff/api/v1/applications").header("Idempotency-Key", "create-operation-1")
                    .contentType(MediaType.APPLICATION_JSON).content(INPUT))
                    .andExpect(status().isAccepted())
                    .andExpect(org.springframework.test.web.servlet.result.MockMvcResultMatchers.header()
                            .string("Location", "/bff/api/v1/applications/APP-NEW-1"))
                    .andExpect(jsonPath("$.workflow.dispatchStatus").value("DEFERRED"))
                    .andExpect(jsonPath("$.documents[0].status").value("EXPECTED"))
                    .andExpect(jsonPath("$.correlationId").isNotEmpty())
                    .andExpect(org.springframework.test.web.servlet.result.MockMvcResultMatchers.content()
                            .string(not(containsString("secret"))));
        }
        upstream.verify();
    }

    @ParameterizedTest
    @ValueSource(strings = {"not-a-number", "NaN", "Infinity", ""})
    void rejectsUnparseableAmountsWithoutCallingLoan(String amount) throws Exception {
        mvc.perform(post("/bff/api/v1/applications").header("Idempotency-Key", "create-operation-1")
                .contentType(MediaType.APPLICATION_JSON).content(INPUT.replace("12000.00", amount)))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.code").value("BAD_REQUEST"));
        upstream.verify();
    }

    @ParameterizedTest
    @ValueSource(strings = {"workflowStartMode", "applicationId", "reviewerPrincipalId"})
    void rejectsBrowserSuppliedTechnicalFields(String field) throws Exception {
        mvc.perform(post("/bff/api/v1/applications").header("Idempotency-Key", "create-operation-1")
                .contentType(MediaType.APPLICATION_JSON).content(INPUT.replace("\"scenarioId\":", "\"" + field + "\":\"AUTO\",\"scenarioId\":")))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.code").value("BAD_REQUEST"));
        upstream.verify();
    }

    @Test
    void rejectsBrowserSuppliedDocumentStatus() throws Exception {
        mvc.perform(post("/bff/api/v1/applications").header("Idempotency-Key", "create-operation-1")
                .contentType(MediaType.APPLICATION_JSON).content(INPUT.replace("\"required\":true", "\"required\":true,\"status\":\"RECEIVED\"")))
                .andExpect(status().isBadRequest());
        upstream.verify();
    }

    @ParameterizedTest
    @ValueSource(ints = {400, 403, 409, 422, 503})
    void preservesDownstreamRejectionsWithoutEchoingTheResponse(int code) throws Exception {
        upstream.expect(requestTo("http://loan.example/api/v1/loan-applications"))
                .andRespond(withStatus(HttpStatus.valueOf(code)).body("secret SQL or submitted value"));
        mvc.perform(post("/bff/api/v1/applications").header("Idempotency-Key", "create-operation-1")
                .contentType(MediaType.APPLICATION_JSON).content(INPUT))
                .andExpect(status().is(code)).andExpect(jsonPath("$.correlationId").isNotEmpty())
                .andExpect(org.springframework.test.web.servlet.result.MockMvcResultMatchers.content().string(not(containsString("secret"))));
        upstream.verify();
    }

    @Test
    void rejectsMissingIdempotencyKeyWithSafeEnvelope() throws Exception {
        mvc.perform(post("/bff/api/v1/applications").contentType(MediaType.APPLICATION_JSON).content(INPUT))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.code").value("BAD_REQUEST"));
        upstream.verify();
    }
}
