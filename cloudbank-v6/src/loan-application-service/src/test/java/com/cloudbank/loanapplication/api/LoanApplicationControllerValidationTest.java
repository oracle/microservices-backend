// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.loanapplication.api;

import static com.cloudbank.loanapplication.api.ApplicationApiModels.ApplicationResponse;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.cloudbank.loanapplication.config.SecurityConfig;
import com.cloudbank.loanapplication.security.AuthenticatedPrincipal;
import com.cloudbank.loanapplication.service.LoanApplicationService;
import java.util.List;
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
@Import(SecurityConfig.class)
class LoanApplicationControllerValidationTest {

    @Autowired
    private MockMvc mockMvc;

    @MockitoBean
    private LoanApplicationService service;

    @MockitoBean
    private JwtDecoder jwtDecoder;

    @Test
    void createsApplicationAtRenamedResourceLocation() throws Exception {
        when(service.create(any(), anyString(), any(AuthenticatedPrincipal.class)))
                .thenReturn(new ApplicationResponse("APP-NEW-001", null, null, null, null, null,
                        null, null, null, null, null, null));

        mockMvc.perform(post("/api/v1/loan-applications")
                        .with(applicantJwt())
                        .header("Idempotency-Key", "create-key-123")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "scenarioId": "SCENARIO-001",
                                  "scenarioName": "Synthetic application",
                                  "applicant": {
                                    "displayName": "Applicant One",
                                    "phoneToken": "phone-token",
                                    "emailToken": "email-token",
                                    "ageBand": "35-44",
                                    "address": {
                                      "addressLine": "6 East Orison Crossing",
                                      "locality": "East Orison",
                                      "jurisdictionCode": "CX",
                                      "addressToken": "address-token"
                                    }
                                  },
                                  "loan": {
                                    "requestedAmount": 15000.00,
                                    "requestedTermMonths": 36,
                                    "purposeCode": "PERSONAL"
                                  },
                                  "documents": [{
                                    "documentType": "PAY_STUB",
                                    "fileName": "pay-stub.pdf",
                                    "status": "EXPECTED",
                                    "required": true
                                  }],
                                  "workflowStartMode": "AUTO"
                                }
                                """))
                .andExpect(status().isAccepted())
                .andExpect(header().string("Location", "/api/v1/loan-applications/APP-NEW-001"));
    }

    @Test
    void rejectsApplicationWithoutAddressEvidence() throws Exception {
        mockMvc.perform(post("/api/v1/loan-applications")
                        .with(applicantJwt())
                        .header("Idempotency-Key", "create-key-123")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "scenarioId": "SCENARIO-001",
                                  "scenarioName": "Synthetic application",
                                  "applicant": {
                                    "displayName": "Applicant One",
                                    "phoneToken": "phone-token",
                                    "emailToken": "email-token",
                                    "ageBand": "35-44"
                                  },
                                  "loan": {
                                    "requestedAmount": 15000.00,
                                    "requestedTermMonths": 36,
                                    "purposeCode": "PERSONAL"
                                  },
                                  "documents": [{
                                    "documentType": "PAY_STUB",
                                    "fileName": "pay-stub.pdf",
                                    "status": "EXPECTED",
                                    "required": true
                                  }],
                                  "workflowStartMode": "AUTO"
                                }
                                """))
                .andExpect(status().isUnprocessableContent())
                .andExpect(jsonPath("$.code").value("VALIDATION_FAILED"));

        verify(service, never()).create(any(), anyString(), any(AuthenticatedPrincipal.class));
    }

    @Test
    void noLongerMapsLegacyApplicationResource() throws Exception {
        mockMvc.perform(get("/api/v1/applications/{applicationId}", "APP-MR-002")
                        .with(applicantJwt()))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("RESOURCE_NOT_FOUND"));

        verify(service, never()).get(anyString(), any(AuthenticatedPrincipal.class));
    }

    @Test
    void acceptsGeneratedAndSyntheticApplicationIds() throws Exception {
        mockMvc.perform(get("/api/v1/loan-applications/{applicationId}",
                        "APP-123e4567-e89b-12d3-a456-426614174000")
                        .with(applicantJwt()))
                .andExpect(status().isOk());
        mockMvc.perform(get("/api/v1/loan-applications/{applicationId}", "APP-MR-002")
                        .with(applicantJwt()))
                .andExpect(status().isOk());

        verify(service, times(2)).get(anyString(), any(AuthenticatedPrincipal.class));
    }

    @Test
    void rejectsMalformedApplicationIdBeforeCallingService() throws Exception {
        mockMvc.perform(get("/api/v1/loan-applications/{applicationId}", "APP-' OR 1=1--")
                        .with(applicantJwt()))
                .andExpect(status().is(422))
                .andExpect(jsonPath("$.code").value("VALIDATION_FAILED"));
        mockMvc.perform(get("/api/v1/loan-applications/{applicationId}", "APPLICATION-MR-002")
                        .with(applicantJwt()))
                .andExpect(status().is(422))
                .andExpect(jsonPath("$.code").value("VALIDATION_FAILED"));
        mockMvc.perform(get("/api/v1/loan-applications/{applicationId}", "APP-" + "A".repeat(37))
                        .with(applicantJwt()))
                .andExpect(status().is(422))
                .andExpect(jsonPath("$.code").value("VALIDATION_FAILED"));

        verify(service, never()).get(anyString(), any(AuthenticatedPrincipal.class));
    }

    @Test
    void acceptsGeneratedAndSyntheticDocumentIds() throws Exception {
        mockMvc.perform(put("/api/v1/loan-applications/{applicationId}/documents/{documentId}/content",
                        "APP-MR-002", "DOC-123e4567-e89b-12d3-a456-426614174000")
                        .with(applicantJwt())
                        .header("Idempotency-Key", "upload-key-123")
                        .contentType(MediaType.APPLICATION_PDF)
                        .content("%PDF-1.7"))
                .andExpect(status().isOk());
        mockMvc.perform(put("/api/v1/loan-applications/{applicationId}/documents/{documentId}/content",
                        "APP-MR-002", "DOC-MR-006")
                        .with(applicantJwt())
                        .header("Idempotency-Key", "upload-key-456")
                        .contentType(MediaType.APPLICATION_PDF)
                        .content("%PDF-1.7"))
                .andExpect(status().isOk());

        verify(service, times(2)).uploadDocumentContent(anyString(), anyString(), anyString(),
                anyString(), any(byte[].class), any(AuthenticatedPrincipal.class));
    }

    @Test
    void rejectsMalformedAndOversizedDocumentIdsBeforeCallingService() throws Exception {
        mockMvc.perform(put("/api/v1/loan-applications/{applicationId}/documents/{documentId}/content",
                        "APP-MR-002", "DOC_' OR 1=1--")
                        .with(applicantJwt())
                        .header("Idempotency-Key", "upload-key-123")
                        .contentType(MediaType.APPLICATION_PDF)
                        .content("%PDF-1.7"))
                .andExpect(status().is(422))
                .andExpect(jsonPath("$.code").value("VALIDATION_FAILED"));
        mockMvc.perform(put("/api/v1/loan-applications/{applicationId}/documents/{documentId}/content",
                        "APP-MR-002", "DOC-" + "A".repeat(57))
                        .with(applicantJwt())
                        .header("Idempotency-Key", "upload-key-456")
                        .contentType(MediaType.APPLICATION_PDF)
                        .content("%PDF-1.7"))
                .andExpect(status().is(422))
                .andExpect(jsonPath("$.code").value("VALIDATION_FAILED"));

        verify(service, never()).uploadDocumentContent(anyString(), anyString(), anyString(),
                anyString(), any(byte[].class), any(AuthenticatedPrincipal.class));
    }

    private static RequestPostProcessor applicantJwt() {
        return jwt()
                .jwt(token -> token
                        .issuer("https://issuer.example")
                        .subject("applicant-1")
                        .claim("cb_principal_id", "principal-1")
                        .claim("name", "Applicant One")
                        .claim("roles", List.of("ROLE_APPLICANT")))
                .authorities(
                        new SimpleGrantedAuthority("SCOPE_cloudbank.read"),
                        new SimpleGrantedAuthority("SCOPE_cloudbank.write"),
                        new SimpleGrantedAuthority("ROLE_APPLICANT"));
    }
}
