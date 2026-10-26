// Copyright (c) 2026, Oracle and/or its affiliates.
//
// Licensed under the Universal Permissive License v 1.0 as shown at
// https://oss.oracle.com/licenses/upl/.
//

package com.cloudbank.aiagent.api;

import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.util.List;

public final class AiAgentApiModels {
    private AiAgentApiModels() {
    }

    public record DocumentEvidenceSummaryRequest(
            @NotBlank @Pattern(regexp = "APP-[A-Za-z0-9][A-Za-z0-9-]{0,35}") String applicationId,
            @NotBlank @Size(max = 100) String workflowId,
            @NotBlank @Pattern(regexp = "ai_document_evidence_summary") String taskReference,
            @NotBlank @Pattern(regexp = "[0-9a-fA-F]{32}") String traceId,
            @NotBlank @Pattern(regexp = "DREV-[0-9a-fA-F]{32}") String reviewId,
            @NotBlank @Pattern(regexp = "UNDERWRITER") String audience) {
    }

    public record EvidenceItem(String sourceType, String sourceId, String description) {
    }

    public record SourceReference(String sourceType, String sourceId) {
    }

    public record MaterialDocumentIssue(String issueCode, String severity, String routingEffect,
            List<String> documentIds) {
    }

    public record DocumentEvidenceSummaryResponse(String summaryId, String status, String provider, String model,
            String applicationId, String workflowId, String taskReference, String traceId, String reviewId,
            String audience, String summary, List<MaterialDocumentIssue> materialIssues,
            List<EvidenceItem> evidenceToInspect,
            List<SourceReference> sourceReferences, String guardrailStatus, List<String> reviewNotes) {
    }

    public record PolicyEvidenceInput(
            @NotBlank @Size(max = 80) String policyDocumentId,
            @NotBlank @Size(max = 40) String policyCode,
            @NotBlank @Size(max = 40) String policyVersion,
            @NotBlank @Size(max = 100) String chunkId,
            @NotBlank @Size(max = 80) String sectionRef,
            @NotBlank @Size(max = 200) String heading,
            @NotBlank @Size(max = 4000) String content,
            @DecimalMin("-1.0") @DecimalMax("1.0") double vectorScore) {
    }

    public record PolicyEvidenceSupportRequest(
            @NotBlank @Pattern(regexp = "APP-[A-Za-z0-9][A-Za-z0-9-]{0,35}") String applicationId,
            @NotBlank @Size(max = 100) String workflowId,
            @NotBlank @Pattern(regexp = "ai_policy_evidence_support") String taskReference,
            @NotBlank @Pattern(regexp = "[0-9a-fA-F]{32}") String traceId,
            @NotBlank @Pattern(regexp = "DREV-[0-9a-fA-F]{32}") String reviewId,
            @NotNull @Pattern(regexp = "(?:AISUM-[0-9a-fA-F]{32})?") String documentSummaryId,
            @NotBlank @Pattern(regexp = "UNDERWRITER") String audience,
            @NotNull @Size(max = 3) List<@Valid PolicyEvidenceInput> policyEvidence) {
    }

    public record PolicyCitation(String policyDocumentId, String policyCode, String policyVersion, String chunkId,
            String sectionRef, String heading) {
    }

    public record PolicyEvidenceSupportResponse(String policySupportId, String status, String provider, String model,
            String applicationId, String workflowId, String taskReference, String traceId, String reviewId,
            String documentSummaryId, String audience, String evidenceStatus, String summary,
            List<PolicyCitation> citations, List<String> supportNotes, List<SourceReference> sourceReferences,
            String guardrailStatus) {
    }

    public record ManualReviewAssistanceRequest(
            @NotBlank @Pattern(regexp = "APP-[A-Za-z0-9][A-Za-z0-9-]{0,35}") String applicationId,
            @NotBlank @Size(max = 100) String workflowId,
            @NotBlank @Pattern(regexp = "ai_manual_review_assistant") String taskReference,
            @NotBlank @Pattern(regexp = "[0-9a-fA-F]{32}") String traceId,
            @NotBlank @Pattern(regexp = "DREV-[0-9a-fA-F]{32}") String reviewId,
            @NotNull @Pattern(regexp = "(?:AISUM-[0-9a-fA-F]{32})?") String documentSummaryId,
            @NotBlank @Pattern(regexp = "UNDERWRITER") String audience) {
    }

    public record ManualReviewAssistanceResponse(String assistanceId, String status, String provider, String model,
            String applicationId, String workflowId, String taskReference, String traceId, String reviewId,
            String documentSummaryId, String audience, List<String> checklist, List<String> clarificationQuestions,
            List<SourceReference> sourceReferences, String guardrailStatus) {
    }

    public record ErrorResponse(String code, String message, String correlationId, boolean retryable) {
    }
}
