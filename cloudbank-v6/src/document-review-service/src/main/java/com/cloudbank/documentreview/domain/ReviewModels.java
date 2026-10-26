// Copyright (c) 2026, Oracle and/or its affiliates.
//
// Licensed under the Universal Permissive License v 1.0 as shown at
// https://oss.oracle.com/licenses/upl/.
//

package com.cloudbank.documentreview.domain;

import java.math.BigDecimal;
import java.util.List;

public final class ReviewModels {
    private ReviewModels() {
    }

    public enum IssueSeverity {
        WARNING, REVIEW, BLOCKING
    }

    public enum RoutingEffect {
        RETRY_EXTRACTION, MANUAL_REVIEW, BLOCKED
    }

    public enum ReviewStatus {
        ACK_PENDING, COMPLETED
    }

    public enum ReviewDisposition {
        CLEAR, MANUAL_REVIEW, RETRY_EXTRACTION, BLOCKED
    }

    public record ManifestDocument(String documentId, String documentType, String status, boolean required) {
    }

    public record DocumentManifest(String applicationId, List<ManifestDocument> documents) {
    }

    /** Legacy applicationIdFromDocument is ignored by v2; runtime IDs come from authorized service metadata. */
    public record ExtractedFacts(String applicationIdFromDocument, String employerName,
            BigDecimal statedGrossMonthlyIncome, BigDecimal payStatementMonthlyGross,
            BigDecimal verifiedGrossMonthlyIncome, String identityOutcome, BigDecimal existingMonthlyDebt,
            BigDecimal proposedMonthlyPayment, BigDecimal debtToIncomePct) {
    }

    public record ExtractionDocument(String documentId, String documentType, String extractionId,
            String extractionStatus, String provider, String model, BigDecimal confidenceScore, ExtractedFacts facts,
            List<String> validationSignals, List<String> warnings) {
    }

    public record ExtractionReviewInput(String applicationId, List<ExtractionDocument> documents) {
    }

    public record ReviewIssue(String issueCode, IssueSeverity severity, RoutingEffect routingEffect,
            List<String> documentIds, String message) {
    }

    public record ReviewedDocument(String documentId, String targetStatus) {
    }

    public record DocumentCounts(int total, int validated, int needsReview, int retryRequired, int blocked) {
    }

    public record ReviewResult(String reviewId, String applicationId, String workflowId, String taskReference,
            ReviewStatus reviewStatus, ReviewDisposition disposition, String profileVersion,
            DocumentCounts documentCounts, List<ReviewIssue> issues, String traceId,
            List<ReviewedDocument> acknowledgements) {
    }

    public record StoredReview(ReviewResult result, String requestHash) {
    }
}
