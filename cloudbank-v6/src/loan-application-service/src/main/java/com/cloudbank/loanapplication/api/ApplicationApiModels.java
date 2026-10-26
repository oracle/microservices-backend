// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.loanapplication.api;

import com.cloudbank.loanapplication.domain.ApplicationStatus;
import com.cloudbank.loanapplication.domain.DocumentStatus;
import com.cloudbank.loanapplication.domain.WorkflowDispatchStatus;
import com.cloudbank.loanapplication.domain.WorkflowStartMode;
import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.PositiveOrZero;
import jakarta.validation.constraints.Size;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;

public final class ApplicationApiModels {

    private ApplicationApiModels() {
    }

    public record CreateApplicationRequest(@NotBlank @Size(max = 80) String scenarioId,
            @NotBlank @Size(max = 200) String scenarioName, @Valid @NotNull ApplicantRequest applicant,
            @Valid @NotNull LoanRequest loan, @Valid @NotEmpty @Size(max = 50) List<DocumentRequest> documents,
            @NotNull WorkflowStartMode workflowStartMode) {
    }

    public record ApplicantRequest(@NotBlank @Size(max = 200) String displayName,
            @NotBlank @Size(max = 80) String phoneToken, @NotBlank @Size(max = 160) String emailToken,
            @NotBlank @Pattern(regexp = "18-24|25-34|35-44|45-54|55-64|65_PLUS") String ageBand,
            @Valid @NotNull AddressRequest address) {
    }

    public record AddressRequest(@NotBlank @Size(max = 300) String addressLine,
            @NotBlank @Size(max = 120) String locality,
            @NotBlank @Pattern(regexp = "[A-Z0-9_-]{2,20}") String jurisdictionCode,
            @NotBlank @Size(max = 80) String addressToken,
            @Pattern(regexp = "[A-Z]{2}") String countryCode,
            @Size(max = 20) String postalCode) {

        public AddressRequest(String addressLine, String locality, String jurisdictionCode, String addressToken) {
            this(addressLine, locality, jurisdictionCode, addressToken, null, null);
        }
    }

    public record LoanRequest(@NotNull @DecimalMin("1000.00") @DecimalMax("35000.00") BigDecimal requestedAmount,
            @NotNull Integer requestedTermMonths, @NotBlank @Size(max = 40) String purposeCode,
            @Size(max = 20) String policyVersion) {
    }

    public record DocumentRequest(@NotBlank @Size(max = 60) String documentType,
            @NotBlank @Size(max = 260) String fileName, @NotNull DocumentStatus status, boolean required,
            @Pattern(regexp = "[0-9a-fA-F]{64}") String contentSha256, @Size(max = 500) String sourceReference,
            @Size(max = 120) String mediaType, @PositiveOrZero Long contentLengthBytes) {
    }

    public record RegisterDocumentsRequest(@Valid @NotEmpty @Size(max = 50) List<DocumentRequest> documents) {
    }

    public record DocumentUploadResponse(String documentId, DocumentStatus status, String mediaType,
            long contentLengthBytes, String contentSha256) {
    }

    public record DocumentManifestResponse(String applicationId, List<ProcessingDocument> documents) {
    }

    public record ProcessingDocument(String documentId, String documentType, String fileName, DocumentStatus status,
            String mediaType, Long contentLengthBytes, String contentSha256, boolean required) {
    }

    public record DocumentStatusTransitionRequest(@NotBlank @Size(max = 100) String eventId,
            @NotNull DocumentStatus expectedStatus, @NotNull DocumentStatus targetStatus,
            @NotBlank @Size(max = 120) String reasonCode, @Size(max = 80) String traceId) {
    }

    public record StatusTransitionRequest(@NotBlank @Size(max = 100) String eventId,
            @NotNull ApplicationStatus expectedStatus, @NotNull ApplicationStatus targetStatus,
            @NotBlank @Size(max = 120) String reasonCode, @Size(max = 100) String workflowId,
            @Size(max = 120) String taskReference, @Size(max = 80) String traceId) {
    }

    public record ApplicationResponse(String applicationId, String scenarioId, String scenarioName,
            ApplicationStatus status, BigDecimal requestedAmount, Integer requestedTermMonths, String purposeCode,
            List<DocumentResponse> documents, WorkflowResponse workflow, String traceId, Instant createdAt,
            Instant updatedAt) {
    }

    public record ApplicationPageResponse(List<ApplicationResponse> content, PageMetadata page) {
    }

    public record PageMetadata(int number, int size, long totalElements, long totalPages) {
    }

    public record DocumentResponse(String documentId, String documentType, String documentLabel, String fileName,
            DocumentStatus status, boolean required) {
    }

    public record WorkflowResponse(String startRequestId, String workflowName, int workflowVersion,
            WorkflowDispatchStatus dispatchStatus, String workflowId, String lastErrorCode, String lastErrorMessage) {
    }

    public record ErrorResponse(String code, String message, String correlationId, boolean retryable,
            String authorizationStatus, List<FieldError> fieldErrors) {
    }

    public record FieldError(String field, String message) {
    }
}
