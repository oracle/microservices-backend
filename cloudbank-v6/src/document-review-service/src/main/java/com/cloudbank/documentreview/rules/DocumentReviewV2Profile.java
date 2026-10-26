// Copyright (c) 2026, Oracle and/or its affiliates.
//
// Licensed under the Universal Permissive License v 1.0 as shown at
// https://oss.oracle.com/licenses/upl/.
//

package com.cloudbank.documentreview.rules;

import com.cloudbank.documentreview.domain.ReviewModels.DocumentCounts;
import com.cloudbank.documentreview.domain.ReviewModels.DocumentManifest;
import com.cloudbank.documentreview.domain.ReviewModels.ExtractedFacts;
import com.cloudbank.documentreview.domain.ReviewModels.ExtractionDocument;
import com.cloudbank.documentreview.domain.ReviewModels.ExtractionReviewInput;
import com.cloudbank.documentreview.domain.ReviewModels.IssueSeverity;
import com.cloudbank.documentreview.domain.ReviewModels.ManifestDocument;
import com.cloudbank.documentreview.domain.ReviewModels.ReviewDisposition;
import com.cloudbank.documentreview.domain.ReviewModels.ReviewIssue;
import com.cloudbank.documentreview.domain.ReviewModels.ReviewResult;
import com.cloudbank.documentreview.domain.ReviewModels.ReviewStatus;
import com.cloudbank.documentreview.domain.ReviewModels.ReviewedDocument;
import com.cloudbank.documentreview.domain.ReviewModels.RoutingEffect;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.function.Predicate;
import java.util.stream.Collectors;
import org.springframework.stereotype.Component;

@Component
public class DocumentReviewV2Profile {
    public static final String VERSION = "document-review-v2";
    private static final Set<String> SUPPORTED = Set.of("LOAN_APPLICATION", "DISCLOSURE_CONSENT", "IDENTITY_SUMMARY",
            "ADDRESS_VERIFICATION", "INCOME_VALIDATION", "PAY_STATEMENT", "DEPOSIT_SUMMARY", "ACCOUNT_ACTIVITY",
            "CONTRACTOR_INCOME", "LIABILITY_SCHEDULE", "PAYMENT_CALCULATION", "CLARIFICATION_REQUEST",
            "DOCUMENT_RECEIPT", "RELATIONSHIP_SIGNAL");

    public ReviewResult evaluate(String reviewId, String applicationId, String workflowId, String taskReference,
            String traceId, DocumentManifest manifest, ExtractionReviewInput input) {
        List<ReviewIssue> issues = new ArrayList<>();
        List<ManifestDocument> documents = manifest.documents() == null ? List.of() : manifest.documents();
        Map<String, ExtractionDocument> extractions = (input.documents() == null ? List.<ExtractionDocument> of()
                : input.documents()).stream().collect(
                        Collectors.toMap(ExtractionDocument::documentId, value -> value, (left, right) -> left));
        for (ManifestDocument document : documents) {
            if (!SUPPORTED.contains(document.documentType()))
                issue(issues, "UNSUPPORTED_DOCUMENT_TYPE", IssueSeverity.WARNING, RoutingEffect.MANUAL_REVIEW,
                        List.of(document.documentId()), "The review profile does not support this document type.");
            if (document.required() && "EXPECTED".equals(document.status()))
                issue(issues, "MISSING_REQUIRED_DOCUMENT", IssueSeverity.BLOCKING, RoutingEffect.BLOCKED,
                        List.of(document.documentId()), "Required document content is unavailable.");
            ExtractionDocument extraction = extractions.get(document.documentId());
            if (document.required() && extraction == null) {
                issue(issues, "MISSING_REQUIRED_EXTRACTION", IssueSeverity.WARNING, RoutingEffect.RETRY_EXTRACTION,
                        List.of(document.documentId()), "Required document extraction is missing.");
                continue;
            }
            if (extraction == null)
                continue;
            String status = extraction.extractionStatus();
            if ("FAILED_RETRYABLE".equals(status))
                issue(issues, "EXTRACTION_FAILED_RETRYABLE", IssueSeverity.WARNING, RoutingEffect.RETRY_EXTRACTION,
                        List.of(document.documentId()), "Extraction failed and can be retried.");
            if ("FAILED_FINAL".equals(status))
                issue(issues, "EXTRACTION_FAILED_FINAL", IssueSeverity.BLOCKING, RoutingEffect.BLOCKED,
                        List.of(document.documentId()), "Extraction failed finally.");
            if ("LOW_CONFIDENCE".equals(status) || below(extraction.confidenceScore(), new BigDecimal("0.85")))
                issue(issues, "LOW_EXTRACTION_CONFIDENCE", IssueSeverity.REVIEW, RoutingEffect.MANUAL_REVIEW,
                        List.of(document.documentId()), "Extraction confidence requires human review.");
            if (isStatistical(extraction.provider()) && extraction.confidenceScore() == null)
                issue(issues, "EXTRACTION_CONFIDENCE_UNAVAILABLE", IssueSeverity.REVIEW, RoutingEffect.MANUAL_REVIEW,
                        List.of(document.documentId()), "Statistical extraction confidence is unavailable.");
            if (contains(extraction.validationSignals(), "income_clarification_required")
                    || contains(extraction.warnings(), "income_clarification_required"))
                issue(issues, "INCOME_CLARIFICATION_REQUIRED", IssueSeverity.REVIEW, RoutingEffect.MANUAL_REVIEW,
                        List.of(document.documentId()), "Income clarification is required.");
        }
        List<ExtractionDocument> extracted = new ArrayList<>(extractions.values());
        ExtractedFacts facts = extracted.stream().map(ExtractionDocument::facts).filter(java.util.Objects::nonNull)
                .findFirst().orElse(null);
        if (facts != null) {
            if (varianceOver(facts.statedGrossMonthlyIncome(), facts.verifiedGrossMonthlyIncome()))
                issue(issues, "INCOME_DIFFERENCE_OVER_10_PERCENT", IssueSeverity.REVIEW, RoutingEffect.MANUAL_REVIEW,
                        ids(extracted), "Verified income differs from submitted evidence by more than 10 percent.");
            if (varianceOver(facts.payStatementMonthlyGross(), facts.verifiedGrossMonthlyIncome()))
                issue(issues, "PAY_AND_VERIFIED_INCOME_DIFFERENCE_OVER_10_PERCENT", IssueSeverity.REVIEW,
                        RoutingEffect.MANUAL_REVIEW, ids(extracted),
                        "Pay-document and verified income differ by more than 10 percent.");
        }
        inconsistent(extracted, item -> item.facts() == null ? null : item.facts().employerName(),
                "EMPLOYER_INCONSISTENCY", "Employer evidence is inconsistent.", issues);
        inconsistent(extracted, item -> item.facts() == null ? null : item.facts().identityOutcome(),
                "APPLICANT_IDENTITY_INCONSISTENCY", "Applicant identity evidence is inconsistent.", issues);
        ReviewDisposition disposition = issues.stream().map(ReviewIssue::routingEffect)
                .map(DocumentReviewV2Profile::disposition).max(Comparator.comparingInt(DocumentReviewV2Profile::rank))
                .orElse(ReviewDisposition.CLEAR);
        int total = documents.size();
        int retry = count(issues, RoutingEffect.RETRY_EXTRACTION);
        int blocked = count(issues, RoutingEffect.BLOCKED);
        int review = count(issues, RoutingEffect.MANUAL_REVIEW);
        List<ReviewedDocument> acknowledgements = documents.stream().filter(d -> "EXTRACTED".equals(d.status()))
                .map(d -> new ReviewedDocument(d.documentId(), disposition == ReviewDisposition.CLEAR ? "VALIDATED"
                        : disposition == ReviewDisposition.RETRY_EXTRACTION ? "FAILED_RETRYABLE" : "NEEDS_REVIEW"))
                .toList();
        return new ReviewResult(reviewId, applicationId, workflowId, taskReference, ReviewStatus.ACK_PENDING,
                disposition, VERSION,
                new DocumentCounts(total, disposition == ReviewDisposition.CLEAR ? total : 0, review, retry, blocked),
                List.copyOf(issues), traceId, acknowledgements);
    }

    private static void inconsistent(List<ExtractionDocument> docs,
            java.util.function.Function<ExtractionDocument, String> value, String code, String message,
            List<ReviewIssue> issues) {
        Set<String> values = docs.stream().map(value).map(DocumentReviewV2Profile::normalized)
                .filter(java.util.Objects::nonNull).collect(Collectors.toSet());
        if (values.size() > 1)
            issue(issues, code, IssueSeverity.REVIEW, RoutingEffect.MANUAL_REVIEW, ids(docs), message);
    }

    private static boolean isStatistical(String provider) {
        return provider != null && !"DOCUMENT_INGEST".equals(provider) && !"RULE_BASED".equals(provider)
                && !"local_pdf_text".equalsIgnoreCase(provider);
    }

    private static boolean contains(List<String> signals, String expected) {
        return signals != null && signals.stream().anyMatch(value -> expected.equals(normalized(value)));
    }

    private static String normalized(String value) {
        return value == null || value.isBlank() ? null : value.trim().replaceAll("\\s+", " ").toLowerCase(Locale.ROOT);
    }

    private static boolean below(BigDecimal value, BigDecimal boundary) {
        return value != null && value.compareTo(boundary) < 0;
    }

    static boolean varianceOver(BigDecimal reference, BigDecimal comparison) {
        return reference != null && comparison != null && reference.compareTo(BigDecimal.ZERO) > 0
                && reference.subtract(comparison).abs().divide(reference.abs(), 12, RoundingMode.HALF_UP)
                        .multiply(BigDecimal.valueOf(100)).compareTo(BigDecimal.TEN) > 0;
    }

    private static void issue(List<ReviewIssue> issues, String code, IssueSeverity severity, RoutingEffect effect,
            List<String> documentIds, String message) {
        if (issues.stream().noneMatch(issue -> issue.issueCode().equals(code)))
            issues.add(new ReviewIssue(code, severity, effect, documentIds, message));
    }

    private static List<String> ids(List<ExtractionDocument> docs) {
        return docs.stream().map(ExtractionDocument::documentId).sorted().toList();
    }

    private static int count(List<ReviewIssue> issues, RoutingEffect effect) {
        return (int) issues.stream().filter(issue -> issue.routingEffect() == effect).count();
    }

    private static ReviewDisposition disposition(RoutingEffect effect) {
        return switch (effect) {
            case BLOCKED -> ReviewDisposition.BLOCKED;
            case RETRY_EXTRACTION -> ReviewDisposition.RETRY_EXTRACTION;
            case MANUAL_REVIEW -> ReviewDisposition.MANUAL_REVIEW;
        };
    }

    private static int rank(ReviewDisposition value) {
        return switch (value) {
            case CLEAR -> 0;
            case MANUAL_REVIEW -> 1;
            case RETRY_EXTRACTION -> 2;
            case BLOCKED -> 3;
        };
    }
}
