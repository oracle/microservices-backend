// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.documentingest.model;

import com.cloudbank.documentingest.model.ExtractionModels.ExtractionResponse;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.util.List;

public final class WorkflowExtractionModels {

    private WorkflowExtractionModels() {
    }

    public record WorkflowExtractionRequest(
            @NotBlank @Size(max = 80) String applicationId,
            @NotBlank @Size(max = 100) String workflowId,
            @NotBlank @Size(max = 120) String taskReference,
            @NotBlank @Pattern(regexp = "[0-9a-fA-F]{32}") String traceId) {
    }

    public record LoanDocumentManifest(String applicationId, List<LoanDocument> documents) {
    }

    public record LoanDocument(
            String documentId,
            String documentType,
            String fileName,
            String status,
            String mediaType,
            Long contentLengthBytes,
            String contentSha256) {
    }

    public record DocumentExtractionResult(
            String documentId,
            String extractionId,
            ExtractionResponse extraction) {
    }

    public record WorkflowExtractionResponse(
            String applicationId,
            String workflowId,
            String taskReference,
            List<DocumentExtractionResult> results) {
    }
}
