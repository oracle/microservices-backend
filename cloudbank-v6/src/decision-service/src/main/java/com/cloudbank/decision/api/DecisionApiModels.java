// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.

package com.cloudbank.decision.api;

import com.cloudbank.decision.domain.DecisionModels.DecisionOutcome;
import com.cloudbank.decision.domain.DecisionModels.DecisionType;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.util.List;

public final class DecisionApiModels {
    private DecisionApiModels() {
    }

    public record DecisionRequest(
            @NotBlank @Pattern(regexp = "APP-[A-Za-z0-9][A-Za-z0-9-]{0,35}") String applicationId,
            @NotBlank @Size(max = 100) String workflowId,
            @NotBlank @Size(max = 120) String taskReference,
            @NotBlank @Pattern(regexp = "[0-9a-fA-F]{32}") String traceId,
            @NotNull DecisionType decisionType,
            @Valid @NotNull EvidenceReferences evidence,
            @Valid ManualReviewResolution manualReview) {
    }

    public record EvidenceReferences(
            @NotBlank @Pattern(regexp = "DREV-[0-9a-f]{32}") String documentReviewId,
            @NotBlank @Pattern(regexp = "CLEAR|MANUAL_REVIEW") String documentDisposition,
            @NotBlank @Size(max = 80) String policySupportId,
            @NotBlank @Pattern(regexp = "GROUNDED|INSUFFICIENT_EVIDENCE") String policyEvidenceStatus,
            @Valid @NotNull @Size(max = 10) List<@NotNull PolicyCitation> policyCitations,
            @NotBlank @Size(max = 100) String geographicRiskEvaluationId,
            @NotBlank @Pattern(regexp = "CLEAR|MANUAL_REVIEW|NOT_EVALUATED|BLOCKED") String geographicRiskDisposition) {
    }

    public record PolicyCitation(
            @NotBlank @Size(max = 100) String chunkId,
            @NotBlank @Pattern(regexp = "[A-Z0-9-]{3,40}") String policyCode,
            @NotBlank @Size(max = 80) String sectionRef) {
    }

    public record ManualReviewResolution(
            @NotNull DecisionOutcome outcome,
            @NotBlank @Pattern(regexp = "UNDERWRITER") String reviewerRole,
            @NotBlank @Size(max = 80) String reviewerPrincipalId,
            @NotBlank @Pattern(regexp = "[A-Z0-9_:-]{3,120}") String reasonCode,
            @NotBlank @Pattern(regexp = "CBPL-[0-9]{3}-S[0-9]+") String policySection) {
    }

    public record FieldError(String field, String message) {
    }

    public record ErrorResponse(String code, String message, String correlationId, boolean retryable,
            String authorizationStatus, List<FieldError> fieldErrors) {
    }
}
