// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.

package com.cloudbank.gatewaybff;

import com.fasterxml.jackson.annotation.JsonAnySetter;
import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import jakarta.servlet.http.HttpServletRequest;
import java.math.BigDecimal;
import java.net.URI;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestClientResponseException;
import org.springframework.web.server.ResponseStatusException;

@RestController
class ApplicationCreationController {
    private final SessionIdentity identity;
    private final RestClient loan;

    ApplicationCreationController(SessionIdentity identity,
            @Value("${cloudbank.bff.loan-base-url}") String loanBaseUrl, RestClient.Builder builder) {
        this.identity = identity;
        this.loan = builder.baseUrl(loanBaseUrl).build();
    }

    @PostMapping(path = "/bff/api/v1/applications", consumes = MediaType.APPLICATION_JSON_VALUE)
    ResponseEntity<CreationResponse> create(@RequestHeader("Idempotency-Key") String key,
            @RequestBody CreationRequest input, Authentication authentication, HttpServletRequest request) {
        String token = identity.requireWrite(authentication, request).accessToken();
        String correlationId = UUID.randomUUID().toString();
        request.setAttribute("bffCorrelationId", correlationId);
        if (!key.matches("[A-Za-z0-9._:-]{8,200}") || input.applicant() == null
                || input.applicant().address() == null || input.loan() == null || input.documents() == null
                || input.documents().stream().anyMatch(document -> document == null)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST);
        }
        LoanRequest parsed;
        try {
            parsed = new LoanRequest(new BigDecimal(input.loan().requestedAmount()),
                    Integer.valueOf(input.loan().requestedTermMonths()), input.loan().purposeCode(),
                    optional(input.loan().policyVersion()));
        } catch (IllegalArgumentException | NullPointerException invalid) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST);
        }
        Address address = input.applicant().address();
        Applicant applicant = new Applicant(input.applicant().displayName(), input.applicant().phoneToken(),
                input.applicant().emailToken(), input.applicant().ageBand(),
                new Address(address.addressLine(), address.locality(), address.jurisdictionCode(),
                        address.addressToken(), optional(address.countryCode()), optional(address.postalCode())));
        LoanCreation command = new LoanCreation(input.scenarioId(), input.scenarioName(), applicant, parsed,
                input.documents().stream().map(doc -> new ExpectedDocument(doc.documentType(), doc.fileName(),
                        doc.required(), "EXPECTED")).toList(), "DEFERRED");
        try {
            LoanCreationResponse result = loan.post().uri("/api/v1/loan-applications")
                    .headers(headers -> headers.setBearerAuth(token))
                    .header("Idempotency-Key", key).header("X-Correlation-ID", correlationId)
                    .contentType(MediaType.APPLICATION_JSON).body(command)
                    .retrieve().body(LoanCreationResponse.class);
            if (result == null || result.applicationId() == null
                    || !result.applicationId().matches("APP-[A-Za-z0-9][A-Za-z0-9-]{0,35}")
                    || result.documents() == null || result.workflow() == null || result.status() == null) {
                throw new ResponseStatusException(HttpStatus.BAD_GATEWAY);
            }
            return ResponseEntity.accepted()
                    .location(URI.create("/bff/api/v1/applications/" + result.applicationId()))
                    .header("X-Correlation-ID", correlationId).header("Cache-Control", "no-store")
                    .body(new CreationResponse(result.applicationId(), result.scenarioId(), result.scenarioName(),
                            result.status(), result.requestedAmount(), result.requestedTermMonths(),
                            result.purposeCode(), result.createdAt(), result.documents(), result.workflow(),
                            result.traceId(), correlationId));
        } catch (RestClientResponseException upstream) {
            HttpStatus status = switch (upstream.getStatusCode().value()) {
                case 400 -> HttpStatus.BAD_REQUEST;
                case 403 -> HttpStatus.FORBIDDEN;
                case 409 -> HttpStatus.CONFLICT;
                case 422 -> HttpStatus.UNPROCESSABLE_CONTENT;
                case 503 -> HttpStatus.SERVICE_UNAVAILABLE;
                default -> HttpStatus.BAD_GATEWAY;
            };
            throw new ResponseStatusException(status);
        } catch (RestClientException upstream) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE);
        }
    }

    private static String optional(String value) {
        return value == null || value.isBlank() ? null : value;
    }

    record CreationRequest(String scenarioId, String scenarioName, Applicant applicant,
            BrowserLoan loan, List<BrowserDocument> documents) {
        @JsonAnySetter
        void rejectUnknown(String name, Object value) { throw new IllegalArgumentException("Unsupported field"); }
    }

    record Applicant(String displayName, String phoneToken, String emailToken, String ageBand, Address address) {
        @JsonAnySetter
        void rejectUnknown(String name, Object value) { throw new IllegalArgumentException("Unsupported field"); }
    }

    record Address(String addressLine, String locality, String jurisdictionCode, String addressToken,
            String countryCode, String postalCode) {
        @JsonAnySetter
        void rejectUnknown(String name, Object value) { throw new IllegalArgumentException("Unsupported field"); }
    }

    record BrowserLoan(String requestedAmount, String requestedTermMonths, String purposeCode, String policyVersion) {
        @JsonAnySetter
        void rejectUnknown(String name, Object value) { throw new IllegalArgumentException("Unsupported field"); }
    }

    record BrowserDocument(String documentType, String fileName, boolean required) {
        @JsonAnySetter
        void rejectUnknown(String name, Object value) { throw new IllegalArgumentException("Unsupported field"); }
    }

    record LoanRequest(BigDecimal requestedAmount, Integer requestedTermMonths, String purposeCode,
            String policyVersion) { }

    record ExpectedDocument(String documentType, String fileName, boolean required, String status) { }

    record LoanCreation(String scenarioId, String scenarioName, Applicant applicant, LoanRequest loan,
            List<ExpectedDocument> documents, String workflowStartMode) { }

    @JsonIgnoreProperties(ignoreUnknown = true)
    record LoanCreationResponse(String applicationId, String scenarioId, String scenarioName, String status,
            BigDecimal requestedAmount, Integer requestedTermMonths, String purposeCode, Instant createdAt,
            List<Document> documents, Workflow workflow, String traceId) { }

    @JsonIgnoreProperties(ignoreUnknown = true)
    record Document(String documentId, String documentType, String documentLabel, String fileName,
            boolean required, String status) { }

    @JsonIgnoreProperties(ignoreUnknown = true)
    record Workflow(String startRequestId, String workflowName, int workflowVersion, String dispatchStatus,
            String workflowId) { }

    record CreationResponse(String applicationId, String scenarioId, String scenarioName, String status,
            BigDecimal requestedAmount, Integer requestedTermMonths, String purposeCode, Instant createdAt,
            List<Document> documents, Workflow workflow, String traceId, String correlationId) { }
}
