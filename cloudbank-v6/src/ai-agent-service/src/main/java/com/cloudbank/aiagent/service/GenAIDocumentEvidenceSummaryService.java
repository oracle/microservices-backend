// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.

package com.cloudbank.aiagent.service;

import com.cloudbank.aiagent.api.AiAgentApiModels.DocumentEvidenceSummaryRequest;
import com.cloudbank.aiagent.api.AiAgentApiModels.DocumentEvidenceSummaryResponse;
import com.cloudbank.aiagent.api.AiAgentApiModels.EvidenceItem;
import com.cloudbank.aiagent.api.AiAgentApiModels.MaterialDocumentIssue;
import com.cloudbank.aiagent.api.AiAgentApiModels.SourceReference;
import com.cloudbank.aiagent.client.DocumentIngestClient;
import com.cloudbank.aiagent.client.DocumentReviewClient;
import com.cloudbank.aiagent.client.DocumentReviewEvidence;
import com.cloudbank.aiagent.client.ExtractionReviewEvidence;
import com.cloudbank.aiagent.config.DocumentSummaryProperties;
import com.cloudbank.aiagent.persistence.DocumentSummaryRepository;
import com.cloudbank.aiagent.service.DocumentEvidenceSummaryModel.DocumentSummaryModelOutput;
import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.HexFormat;
import java.util.List;
import java.util.Objects;
import java.util.Set;
import java.util.concurrent.TimeUnit;
import java.util.regex.Pattern;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import tools.jackson.databind.ObjectMapper;

@Service
public class GenAIDocumentEvidenceSummaryService {
    private static final Logger LOGGER = LoggerFactory.getLogger(GenAIDocumentEvidenceSummaryService.class);
    private static final Set<String> ISSUE_CODES = Set.of("UNSUPPORTED_DOCUMENT_TYPE", "MISSING_REQUIRED_DOCUMENT",
            "MISSING_REQUIRED_EXTRACTION", "EXTRACTION_FAILED_RETRYABLE", "EXTRACTION_FAILED_FINAL",
            "APPLICATION_ID_MISMATCH", "LOW_EXTRACTION_CONFIDENCE", "EXTRACTION_CONFIDENCE_UNAVAILABLE",
            "MISSING_CRITICAL_EXTRACTED_FACT", "INCOME_CLARIFICATION_REQUIRED", "INCOME_DIFFERENCE_OVER_10_PERCENT",
            "PAY_AND_VERIFIED_INCOME_DIFFERENCE_OVER_10_PERCENT", "EMPLOYER_INCONSISTENCY",
            "APPLICANT_IDENTITY_INCONSISTENCY");
    private static final Set<String> SIGNAL_CODES = Set.of("income_clarification_required",
            "income_evidence_requires_clarification", "shared_attribute_signal_requires_review",
            "document_processing_retry_possible", "additional_review_indicated", "recurring_contract_evidence_unavailable");
    private static final Set<String> DOCUMENT_TYPES = Set.of("LOAN_APPLICATION", "DISCLOSURE_CONSENT",
            "IDENTITY_SUMMARY", "ADDRESS_VERIFICATION", "INCOME_VALIDATION", "PAY_STATEMENT", "DEPOSIT_SUMMARY",
            "ACCOUNT_ACTIVITY", "CONTRACTOR_INCOME", "LIABILITY_SCHEDULE", "PAYMENT_CALCULATION",
            "CLARIFICATION_REQUEST", "DOCUMENT_RECEIPT", "RELATIONSHIP_SIGNAL");
    private static final Set<String> EXTRACTION_STATUSES = Set.of("SUCCEEDED", "EXTRACTED", "LOW_CONFIDENCE",
            "FAILED_RETRYABLE", "FAILED_FINAL");
    private static final Pattern DOCUMENT_ID = Pattern.compile("DOC-[A-Za-z0-9][A-Za-z0-9-]{0,95}");
    private static final Pattern EXTRACTION_ID = Pattern.compile("EXT-[A-Za-z0-9][A-Za-z0-9-]{0,95}");
    private static final Pattern FORBIDDEN = Pattern.compile(
            "\\b(approv(?:e|ed|al)|reject(?:ed)?|declin(?:e|ed)|pric(?:e|ing)|credit score|risk score|loan score|"
                    + "score (?:the )?(?:loan|application|applicant)|interest rate|final decision|"
                    + "override|bypass|skip human|complete the task|change (?:application|workflow)|"
                    + "policy|CBPL-[A-Z0-9-]+)\\b", Pattern.CASE_INSENSITIVE);
    private static final Pattern SENSITIVE = Pattern.compile(
            "(-----BEGIN|\\bBearer\\s+\\S+|\\beyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\b|"
                    + "\\b(?:password|secret|token|credential|otp)\\s*[:=]|"
                    + "\\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}\\b|\\b\\d{3}-\\d{2}-\\d{4}\\b|"
                    + "\\bocid1\\.|https?://|[<>]|(?:[$€£]|\\b(?:USD|EUR|GBP)\\s*)\\s*\\d|"
                    + "\\b\\d{3}[- .]\\d{3}[- .]\\d{4}\\b|\\b[A-Z]{2}\\d{2}[A-Z0-9]{11,30}\\b)", Pattern.CASE_INSENSITIVE);
    private static final Pattern OUTPUT_REFERENCE = Pattern.compile("\\b(?:DOC|EXT|DREV|APP|WF|AISUM)-[A-Za-z0-9-]+\\b");

    private final DocumentReviewClient reviews;
    private final DocumentIngestClient extractions;
    private final DocumentEvidenceSummaryModel model;
    private final DocumentSummaryProperties properties;
    private final DocumentSummaryRepository repository;
    private final ObjectMapper json;

    public GenAIDocumentEvidenceSummaryService(DocumentReviewClient reviews, DocumentIngestClient extractions,
            DocumentEvidenceSummaryModel model, DocumentSummaryProperties properties,
            DocumentSummaryRepository repository, ObjectMapper json) {
        this.reviews = reviews;
        this.extractions = extractions;
        this.model = model;
        this.properties = properties;
        this.repository = repository;
        this.json = json;
    }

    public DocumentEvidenceSummaryResponse summarize(DocumentEvidenceSummaryRequest request, String idempotencyKey) {
        String keyHash = digest(idempotencyKey);
        String requestHash = digest(json.writeValueAsString(request));
        var stored = repository.find(keyHash);
        if (stored.isPresent()) {
            return stored.get().replay(requestHash);
        }
        long started = System.nanoTime();
        try {
            DocumentReviewEvidence review = reviews.get(request.reviewId(), request.traceId());
            validateCorrelation(request, review);
            ExtractionReviewEvidence extraction = extractions.get(request.applicationId(), request.traceId());
            BoundedEvidence evidence = minimize(request, review, extraction);
            long retrievalDurationMs = elapsed(started);
            long modelStarted = System.nanoTime();
            DocumentSummaryModelOutput output;
            try {
                output = model.generate(json.writeValueAsString(evidence));
            } catch (ReviewAssistanceException exception) {
                throw exception;
            } catch (RuntimeException exception) {
                throw ReviewAssistanceException.modelUnavailable(exception);
            }
            List<String> documents = evidence.documents().stream().map(BoundedDocument::documentId).toList();
            Set<String> knownReferences = new HashSet<>(documents);
            evidence.documents().stream().map(BoundedDocument::extractionId).filter(Objects::nonNull)
                    .forEach(knownReferences::add);
            evidence.issues().forEach(issue -> knownReferences.addAll(issue.documentIds()));
            knownReferences.add(review.reviewId());
            String summary = validateText(output == null ? null : output.summary(), 1500, knownReferences);
            if (output.reviewNotes() == null || output.reviewNotes().size() > 8
                    || output.evidenceDocumentIds() == null || output.evidenceDocumentIds().size() > properties.maximumDocuments()
                    || output.evidenceDocumentIds().stream().anyMatch(id -> id == null || !knownReferences.contains(id)
                            || !DOCUMENT_ID.matcher(id).matches())) {
                throw ReviewAssistanceException.unsafeModelOutput();
            }
            List<String> notes = output.reviewNotes().stream()
                    .map(note -> validateText(note, 500, knownReferences)).distinct().toList();
            // Include all authoritative issues and source references even if the model omits one.
            List<SourceReference> sources = new ArrayList<>();
            sources.add(new SourceReference("DOCUMENT_REVIEW", request.reviewId()));
            evidence.documents().forEach(document -> {
                sources.add(new SourceReference("DOCUMENT", document.documentId()));
                if (document.extractionId() != null) {
                    sources.add(new SourceReference("DOCUMENT_EXTRACTION", document.extractionId()));
                }
            });
            evidence.issues().stream().flatMap(issue -> issue.documentIds().stream()).distinct()
                    .map(id -> new SourceReference("DOCUMENT", id)).forEach(sources::add);
            List<EvidenceItem> inspect = knownReferences.stream().filter(id -> DOCUMENT_ID.matcher(id).matches())
                    .sorted().map(id -> new EvidenceItem("DOCUMENT", id,
                            "Inspect authorized document-review and bounded extraction evidence.")).toList();
            var response = new DocumentEvidenceSummaryResponse("AISUM-" + digest(keyHash + requestHash).substring(0, 32),
                    "COMPLETED", "oci-genai", properties.model(), request.applicationId(), request.workflowId(),
                    request.taskReference(), request.traceId(), request.reviewId(), request.audience(), summary,
                    evidence.issues(), inspect, sources.stream().distinct().toList(), "PASSED", notes);
            response = repository.save(keyHash, requestHash, response);
            LOGGER.info("OCI GenAI document summary provider=oci-genai model={} outcome=ACCEPTED "
                            + "schemaValidated=true guardrailStatus=PASSED documentCount={} issueCount={} "
                            + "retrievalDurationMs={} modelDurationMs={} durationMs={}",
                    properties.model(), documents.size(), evidence.issues().size(),
                    retrievalDurationMs, elapsed(modelStarted), elapsed(started));
            return response;
        } catch (ReviewAssistanceException exception) {
            LOGGER.warn("OCI GenAI document summary provider=oci-genai model={} outcome=FAILED errorCode={} durationMs={}",
                    properties.model(), exception.code(), elapsed(started));
            throw exception;
        }
    }

    private static void validateCorrelation(DocumentEvidenceSummaryRequest request, DocumentReviewEvidence review) {
        if (review == null || !Objects.equals(request.reviewId(), review.reviewId())
                || !Objects.equals(request.applicationId(), review.applicationId())
                || !Objects.equals(request.workflowId(), review.workflowId())
                || !Objects.equals(request.traceId(), review.traceId())
                || !"COMPLETED".equals(review.reviewStatus())
                || review.disposition() == null || !Set.of("CLEAR", "MANUAL_REVIEW").contains(review.disposition())) {
            throw ReviewAssistanceException.evidenceMismatch();
        }
    }

    private BoundedEvidence minimize(DocumentEvidenceSummaryRequest request, DocumentReviewEvidence review,
            ExtractionReviewEvidence extraction) {
        if (extraction == null || !Objects.equals(request.applicationId(), extraction.applicationId())
                || extraction.documents() == null || extraction.documents().isEmpty()
                || extraction.documents().size() > properties.maximumDocuments()
                || review.issues() == null || review.issues().size() > properties.maximumIssues()
                || review.profileVersion() == null || !review.profileVersion().matches("[A-Za-z0-9._-]{1,40}")
                || review.documentCounts() == null || review.documentCounts().total() < 1
                || review.documentCounts().total() > properties.maximumDocuments()) {
            throw ReviewAssistanceException.invalidEvidence();
        }
        var counts = review.documentCounts();
        if (counts.validated() < 0 || counts.validated() > properties.maximumDocuments()
                || counts.needsReview() < 0 || counts.needsReview() > properties.maximumIssues()
                || counts.retryRequired() < 0 || counts.retryRequired() > properties.maximumIssues()
                || counts.blocked() < 0 || counts.blocked() > properties.maximumIssues()) {
            throw ReviewAssistanceException.invalidEvidence();
        }
        List<MaterialDocumentIssue> issues = review.issues().stream().map(issue -> {
            if (issue == null || issue.issueCode() == null || !ISSUE_CODES.contains(issue.issueCode())
                    || issue.severity() == null || !Set.of("WARNING", "REVIEW", "BLOCKING").contains(issue.severity())
                    || issue.routingEffect() == null || !Set.of("RETRY_EXTRACTION", "MANUAL_REVIEW", "BLOCKED").contains(issue.routingEffect())
                    || issue.documentIds() == null || issue.documentIds().size() > properties.maximumDocuments()
                    || issue.documentIds().stream().anyMatch(id -> id == null || !DOCUMENT_ID.matcher(id).matches())) {
                throw ReviewAssistanceException.invalidEvidence();
            }
            return new MaterialDocumentIssue(issue.issueCode(), issue.severity(), issue.routingEffect(),
                    issue.documentIds().stream().distinct().sorted().toList());
        }).toList();
        Set<String> documentIds = new HashSet<>();
        List<BoundedDocument> documents = extraction.documents().stream().map(document -> {
            if (document == null || document.documentId() == null || !DOCUMENT_ID.matcher(document.documentId()).matches()
                    || !documentIds.add(document.documentId()) || document.documentType() == null
                    || document.extractionStatus() == null || !EXTRACTION_STATUSES.contains(document.extractionStatus())
                    || (document.extractionId() != null && !EXTRACTION_ID.matcher(document.extractionId()).matches())
                    || (document.confidenceScore() != null && (document.confidenceScore().signum() < 0
                            || document.confidenceScore().compareTo(BigDecimal.ONE) > 0))) {
                throw ReviewAssistanceException.invalidEvidence();
            }
            String type = DOCUMENT_TYPES.contains(document.documentType()) ? document.documentType() : "UNSUPPORTED";
            String identity = document.facts() == null ? null : document.facts().identityOutcome();
            // Free-form identity text never reaches the model. Unknown outcomes become unavailable.
            identity = identity != null && Set.of("VERIFIED", "PASS", "PASSED", "MATCH", "REVIEW_REQUIRED",
                    "FAILED", "NOT_VERIFIED").contains(identity) ? identity : "UNAVAILABLE";
            return new BoundedDocument(document.documentId(), type, document.extractionId(), document.extractionStatus(),
                    document.confidenceScore(), identity, safeSignals(document.validationSignals()), safeSignals(document.warnings()),
                    hasWithheldSignals(document.validationSignals()) || hasWithheldSignals(document.warnings()));
        }).toList();
        return new BoundedEvidence(review.reviewId(), review.disposition(), review.profileVersion(), request.audience(),
                review.documentCounts(), issues, documents);
    }

    private static List<String> safeSignals(List<String> signals) {
        if (signals == null) {
            return List.of();
        }
        if (signals.size() > 32) {
            throw ReviewAssistanceException.invalidEvidence();
        }
        return signals.stream().filter(Objects::nonNull).filter(SIGNAL_CODES::contains).distinct().sorted().toList();
    }

    private static boolean hasWithheldSignals(List<String> signals) {
        return signals != null && signals.stream().anyMatch(signal -> signal == null || !SIGNAL_CODES.contains(signal));
    }

    private static String validateText(String value, int maximum, Set<String> references) {
        if (value == null || value.isBlank() || value.length() > maximum || FORBIDDEN.matcher(value).find()
                || SENSITIVE.matcher(value).find()) {
            throw ReviewAssistanceException.unsafeModelOutput();
        }
        var matcher = OUTPUT_REFERENCE.matcher(value);
        while (matcher.find()) {
            if (!references.contains(matcher.group())) {
                throw ReviewAssistanceException.unsafeModelOutput();
            }
        }
        return value.strip();
    }

    private static String digest(String value) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(value.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException("SHA-256 is unavailable", exception);
        }
    }

    private static long elapsed(long started) {
        return TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - started);
    }

    record BoundedEvidence(String reviewId, String disposition, String profileVersion, String audience,
            DocumentReviewEvidence.DocumentCounts documentCounts, List<MaterialDocumentIssue> issues,
            List<BoundedDocument> documents) {
    }

    record BoundedDocument(String documentId, String documentType, String extractionId, String extractionStatus,
            BigDecimal confidenceScore, String identityOutcome, List<String> validationSignals, List<String> warnings,
            boolean unrecognizedSignalsWithheld) {
    }
}
