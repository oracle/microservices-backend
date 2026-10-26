// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.loanapplication.persistence;

import com.cloudbank.loanapplication.domain.ApplicationStatus;
import com.cloudbank.loanapplication.domain.DocumentStatus;
import com.cloudbank.loanapplication.domain.WorkflowDispatchStatus;
import java.math.BigDecimal;
import java.time.Instant;

public final class LoanRecords {

    private LoanRecords() {
    }

    public record ApplicationRow(long applicationSk, String applicationId, String scenarioId, String scenarioName,
            ApplicationStatus status, BigDecimal requestedAmount, int requestedTermMonths, String purposeCode,
            String requestHash, Instant createdAt, Instant updatedAt) {
    }

    public record DocumentRow(String documentId, String documentType, String fileName, DocumentStatus status,
            boolean required) {
    }

    public record DocumentProcessingRow(long documentSk, long applicationSk, String applicationId, String documentId,
            String documentType, String fileName, DocumentStatus status, String mediaType, Long contentLengthBytes,
            String contentSha256, boolean required) {
    }

    public record DocumentContentRow(String contentSha256, long contentLengthBytes, String mediaType,
            String idempotencyKey, byte[] content) {
    }

    public record WorkflowRow(long requestSk, long applicationSk, String applicationId, String requestId,
            String workflowName, int workflowVersion, WorkflowDispatchStatus status, String payload, int attemptCount,
            String traceId, String engineWorkflowId, String lastErrorCode, String lastErrorMessage) {
    }
}
