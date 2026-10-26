// Copyright (c) 2026, Oracle and/or its affiliates.
//
// Licensed under the Universal Permissive License v 1.0 as shown at
// https://oss.oracle.com/licenses/upl/.
//

package com.cloudbank.documentreview.rules;

import static org.assertj.core.api.Assertions.assertThat;

import com.cloudbank.documentreview.domain.ReviewModels.DocumentManifest;
import com.cloudbank.documentreview.domain.ReviewModels.ExtractedFacts;
import com.cloudbank.documentreview.domain.ReviewModels.ExtractionDocument;
import com.cloudbank.documentreview.domain.ReviewModels.ExtractionReviewInput;
import com.cloudbank.documentreview.domain.ReviewModels.ManifestDocument;
import com.cloudbank.documentreview.domain.ReviewModels.ReviewDisposition;
import com.cloudbank.documentreview.domain.ReviewModels.ReviewIssue;
import com.cloudbank.documentreview.domain.ReviewModels.ReviewResult;
import java.math.BigDecimal;
import java.util.List;
import org.junit.jupiter.api.Test;

class DocumentReviewV2ProfileTest {
    private final DocumentReviewV2Profile profile = new DocumentReviewV2Profile();

    @Test
    void routesIncomeVarianceAboveTenPercentToManualReview() {
        assertThat(review("APP-ONE", new BigDecimal("100"), new BigDecimal("89"), "SUCCEEDED").disposition())
                .isEqualTo(ReviewDisposition.MANUAL_REVIEW);
    }

    @Test
    void exactTenPercentVarianceRemainsClear() {
        assertThat(review("APP-ONE", new BigDecimal("100"), new BigDecimal("90"), "SUCCEEDED").disposition())
                .isEqualTo(ReviewDisposition.CLEAR);
    }

    @Test
    void missingRequiredExtractionRoutesToRetry() {
        ReviewResult result = profile.evaluate("DREV-00000000000000000000000000000000", "APP-ONE", "WF-1",
                "review_documents", "0123456789abcdef0123456789abcdef",
                new DocumentManifest("APP-ONE",
                        List.of(new ManifestDocument("DOC-1", "LOAN_APPLICATION", "EXTRACTED", true))),
                new ExtractionReviewInput("APP-ONE", List.of()));
        assertThat(result.disposition()).isEqualTo(ReviewDisposition.RETRY_EXTRACTION);
    }

    @Test
    void legacyDocumentReferenceDoesNotOverrideTheApplicationContext() {
        ReviewResult result = review("APP-ONE", new BigDecimal("100"), new BigDecimal("100"), "SUCCEEDED", "APP-OTHER");
        assertThat(result.disposition()).isEqualTo(ReviewDisposition.CLEAR);
        assertThat(result.applicationId()).isEqualTo("APP-ONE");
        assertThat(result.profileVersion()).isEqualTo("document-review-v2");
        assertThat(result.issues()).extracting(ReviewIssue::issueCode).doesNotContain("APPLICATION_ID_MISMATCH");
    }

    @Test
    void loanApplicationWithoutAnEmbeddedApplicationIdCanBeClear() {
        ReviewResult result = review("APP-ONE", new BigDecimal("100"), new BigDecimal("100"), "SUCCEEDED", null);

        assertThat(result.disposition()).isEqualTo(ReviewDisposition.CLEAR);
        assertThat(result.issues()).extracting(ReviewIssue::issueCode)
                .doesNotContain("MISSING_CRITICAL_EXTRACTED_FACT", "APPLICATION_ID_MISMATCH");
    }

    @Test
    void payStatementDoesNotRequireAnApplicationId() {
        ExtractionDocument loanApplication = extraction("DOC-LOAN", "LOAN_APPLICATION", "APP-ONE", "SUCCEEDED",
                new BigDecimal("0.99"), List.of(), List.of());
        ExtractionDocument payStatement = extraction("DOC-PAY", "PAY_STATEMENT", null, "SUCCEEDED",
                new BigDecimal("0.99"), List.of(), List.of());
        ReviewResult result = profile.evaluate("DREV-00000000000000000000000000000000", "APP-ONE", "WF-1",
                "review_documents", "0123456789abcdef0123456789abcdef",
                new DocumentManifest("APP-ONE",
                        List.of(new ManifestDocument("DOC-LOAN", "LOAN_APPLICATION", "EXTRACTED", true),
                                new ManifestDocument("DOC-PAY", "PAY_STATEMENT", "EXTRACTED", true))),
                new ExtractionReviewInput("APP-ONE", List.of(loanApplication, payStatement)));

        assertThat(result.disposition()).isEqualTo(ReviewDisposition.CLEAR);
        assertThat(result.issues()).extracting(ReviewIssue::issueCode)
                .doesNotContain("APPLICATION_ID_MISMATCH", "MISSING_CRITICAL_EXTRACTED_FACT");
    }

    @Test
    void requiredExpectedDocumentBlocksProcessing() {
        ReviewResult result = profile.evaluate("DREV-00000000000000000000000000000000", "APP-ONE", "WF-1",
                "review_documents", "0123456789abcdef0123456789abcdef",
                new DocumentManifest("APP-ONE",
                        List.of(new ManifestDocument("DOC-1", "LOAN_APPLICATION", "EXPECTED", true))),
                new ExtractionReviewInput("APP-ONE", List.of()));

        assertThat(result.disposition()).isEqualTo(ReviewDisposition.BLOCKED);
        assertThat(result.issues()).extracting(ReviewIssue::issueCode).contains("MISSING_REQUIRED_DOCUMENT");
    }

    @Test
    void finalExtractionFailureBlocksWhileRetryableFailureRequestsRetry() {
        assertThat(review("APP-ONE", new BigDecimal("100"), new BigDecimal("100"), "FAILED_FINAL").disposition())
                .isEqualTo(ReviewDisposition.BLOCKED);
        assertThat(review("APP-ONE", new BigDecimal("100"), new BigDecimal("100"), "FAILED_RETRYABLE").disposition())
                .isEqualTo(ReviewDisposition.RETRY_EXTRACTION);
    }

    @Test
    void lowConfidenceAndRequiredClarificationNeedManualReview() {
        ExtractionDocument lowConfidence = extraction("DOC-1", "APP-ONE", "LOW_CONFIDENCE", new BigDecimal("0.70"),
                List.of(), List.of());
        ExtractionDocument clarification = extraction("DOC-2", "APP-ONE", "SUCCEEDED", new BigDecimal("0.99"),
                List.of("income_clarification_required"), List.of());
        ReviewResult result = profile.evaluate("DREV-00000000000000000000000000000000", "APP-ONE", "WF-1",
                "review_documents", "0123456789abcdef0123456789abcdef",
                new DocumentManifest("APP-ONE",
                        List.of(new ManifestDocument("DOC-1", "LOAN_APPLICATION", "EXTRACTED", true),
                                new ManifestDocument("DOC-2", "PAY_STATEMENT", "EXTRACTED", true))),
                new ExtractionReviewInput("APP-ONE", List.of(lowConfidence, clarification)));

        assertThat(result.disposition()).isEqualTo(ReviewDisposition.MANUAL_REVIEW);
        assertThat(result.issues()).extracting(ReviewIssue::issueCode).contains("LOW_EXTRACTION_CONFIDENCE",
                "INCOME_CLARIFICATION_REQUIRED");
        assertThat(result.acknowledgements()).extracting(value -> value.targetStatus()).containsOnly("NEEDS_REVIEW");
    }

    @Test
    void inconsistentEmployerEvidenceNeedsManualReview() {
        ExtractionDocument first = extraction("DOC-1", "APP-ONE", "SUCCEEDED", new BigDecimal("0.99"), List.of(),
                List.of());
        ExtractionDocument second = new ExtractionDocument("DOC-2", "PAY_STATEMENT", "EXT-2", "SUCCEEDED",
                "DOCUMENT_INGEST", "local_pdf_text", new BigDecimal("0.99"), new ExtractedFacts("APP-ONE",
                        "Other Employer", new BigDecimal("100"), new BigDecimal("100"), new BigDecimal("100"),
                        "MATCH", null, null, null),
                List.of(), List.of());
        ReviewResult result = profile.evaluate("DREV-00000000000000000000000000000000", "APP-ONE", "WF-1",
                "review_documents", "0123456789abcdef0123456789abcdef",
                new DocumentManifest("APP-ONE",
                        List.of(new ManifestDocument("DOC-1", "LOAN_APPLICATION", "EXTRACTED", true),
                                new ManifestDocument("DOC-2", "PAY_STATEMENT", "EXTRACTED", true))),
                new ExtractionReviewInput("APP-ONE", List.of(first, second)));

        assertThat(result.disposition()).isEqualTo(ReviewDisposition.MANUAL_REVIEW);
        assertThat(result.issues()).extracting(ReviewIssue::issueCode).contains("EMPLOYER_INCONSISTENCY");
    }

    private ReviewResult review(String applicationId, BigDecimal stated, BigDecimal verified, String status) {
        return review(applicationId, stated, verified, status, applicationId);
    }

    private ReviewResult review(String applicationId, BigDecimal stated, BigDecimal verified, String status,
            String extractedApplicationId) {
        ManifestDocument document = new ManifestDocument("DOC-1", "LOAN_APPLICATION", "EXTRACTED", true);
        ExtractionDocument extraction = new ExtractionDocument("DOC-1", "LOAN_APPLICATION", "EXT-1", status,
                "DOCUMENT_INGEST", "local_pdf_text", new BigDecimal("0.99"),
                new ExtractedFacts(extractedApplicationId, "  North   Star ", stated, stated, verified, "MATCH",
                        null, null, null),
                List.of(), List.of());
        return profile.evaluate("DREV-00000000000000000000000000000000", applicationId, "WF-1", "review_documents",
                "0123456789abcdef0123456789abcdef", new DocumentManifest(applicationId, List.of(document)),
                new ExtractionReviewInput(applicationId, List.of(extraction)));
    }

    private static ExtractionDocument extraction(String documentId, String applicationId, String status,
            BigDecimal confidence, List<String> validationSignals, List<String> warnings) {
        return extraction(documentId, "LOAN_APPLICATION", applicationId, status, confidence, validationSignals,
                warnings);
    }

    private static ExtractionDocument extraction(String documentId, String documentType, String applicationId,
            String status, BigDecimal confidence, List<String> validationSignals, List<String> warnings) {
        return new ExtractionDocument(documentId, documentType, "EXT-" + documentId, status, "DOCUMENT_INGEST",
                "local_pdf_text", confidence, new ExtractedFacts(applicationId, "North Star", new BigDecimal("100"),
                        new BigDecimal("100"), new BigDecimal("100"), "MATCH", null, null, null),
                validationSignals, warnings);
    }
}
