// Copyright (c) 2026, Oracle and/or its affiliates.
//
// Licensed under the Universal Permissive License v 1.0 as shown at
// https://oss.oracle.com/licenses/upl/.
//

package com.cloudbank.aiagent.service;

import com.cloudbank.aiagent.api.AiAgentApiModels.ManualReviewAssistanceRequest;
import com.cloudbank.aiagent.api.AiAgentApiModels.ManualReviewAssistanceResponse;
import com.cloudbank.aiagent.api.AiAgentApiModels.SourceReference;
import com.cloudbank.aiagent.client.DocumentReviewClient;
import com.cloudbank.aiagent.client.DocumentReviewEvidence;
import com.cloudbank.aiagent.config.ReviewAssistanceProperties;
import com.cloudbank.aiagent.service.ReviewAssistanceException.OutputField;
import com.cloudbank.aiagent.service.ReviewAssistanceException.OutputValidationReason;
import com.cloudbank.aiagent.service.SpringAiReviewAssistanceModel.ReviewAssistanceModelOutput;
import com.github.benmanes.caffeine.cache.Cache;
import com.github.benmanes.caffeine.cache.Caffeine;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Objects;
import java.util.Set;
import java.util.concurrent.TimeUnit;
import java.util.regex.Pattern;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import tools.jackson.core.JacksonException;
import tools.jackson.databind.ObjectMapper;

@Service
public class GenAIReviewAssistanceService {
    private static final Logger LOGGER = LoggerFactory.getLogger(GenAIReviewAssistanceService.class);
    private static final int MAX_ITEM_LENGTH = 500;
    private static final Pattern FORBIDDEN_DECISION_LANGUAGE = Pattern.compile(
            "\\b(approve|approved|approval|reject|rejected|decline|declined|pricing|interest rate|final decision|bypass|skip human|complete the task)\\b",
            Pattern.CASE_INSENSITIVE);
    private static final Pattern SENSITIVE_OUTPUT = Pattern.compile(
            "(-----BEGIN [A-Z ]*PRIVATE KEY-----|\\bBearer\\s+[A-Za-z0-9._~-]+|\\beyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\b|\\bpassword\\s*[:=]|\\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}\\b|\\b\\d{3}-\\d{2}-\\d{4}\\b)",
            Pattern.CASE_INSENSITIVE);

    private final DocumentReviewClient documentReviewClient;
    private final SpringAiReviewAssistanceModel model;
    private final ReviewAssistanceProperties properties;
    private final ObjectMapper objectMapper;
    private final Cache<String, ManualReviewAssistanceResponse> responses;

    public GenAIReviewAssistanceService(DocumentReviewClient documentReviewClient,
            SpringAiReviewAssistanceModel model, ReviewAssistanceProperties properties, ObjectMapper objectMapper) {
        this.documentReviewClient = documentReviewClient;
        this.model = model;
        this.properties = properties;
        this.objectMapper = objectMapper;
        this.responses = Caffeine.newBuilder().maximumSize(properties.cacheMaximumSize()).build();
    }

    public ManualReviewAssistanceResponse assist(ManualReviewAssistanceRequest request, String idempotencyKey) {
        String assistanceId = "AIREV-" + digest(idempotencyKey, request).substring(0, 32);
        return responses.get(assistanceId, ignored -> createAssistance(assistanceId, request));
    }

    public java.util.Optional<ManualReviewAssistanceResponse> readResult(String id) {
        return java.util.Optional.ofNullable(responses.getIfPresent(id));
    }

    private ManualReviewAssistanceResponse createAssistance(String assistanceId,
            ManualReviewAssistanceRequest request) {
        DocumentReviewEvidence evidence = documentReviewClient.get(request.reviewId(), request.traceId());
        validateCorrelation(request, evidence);
        BoundedReviewEvidence boundedEvidence = minimize(evidence);
        String evidenceJson = toJson(boundedEvidence);
        long modelCallStartedAt = System.nanoTime();
        ReviewAssistanceModelOutput output;
        try {
            output = model.generate(evidenceJson);
        } catch (ReviewAssistanceException exception) {
            logFailedModelCall(exception.code(), request.traceId(), modelCallStartedAt);
            throw exception;
        } catch (RuntimeException exception) {
            logFailedModelCall("GENAI_UNAVAILABLE", request.traceId(), modelCallStartedAt);
            throw ReviewAssistanceException.modelUnavailable(exception);
        }
        List<String> checklist;
        List<String> questions;
        try {
            checklist = validateItems(output == null ? null : output.checklist(), 1, 12, OutputField.CHECKLIST);
            // Clear documents need not invent clarification questions. The checklist
            // remains mandatory; actual document-review issues still require questions.
            int minimumQuestions = "CLEAR".equals(evidence.disposition()) ? 0 : 1;
            questions = validateItems(output == null ? null : output.clarificationQuestions(), minimumQuestions, 8,
                    OutputField.CLARIFICATION_QUESTIONS);
        } catch (ReviewAssistanceException exception) {
            LOGGER.warn(
                    "OCI GenAI chat model call completed provider=oci-genai model={} outcome=REJECTED "
                            + "correlationId={} errorCode={} validationField={} validationReason={} checklistItemCount={} "
                            + "clarificationQuestionCount={} durationMs={}",
                    properties.model(), safeCorrelation(request.traceId()), exception.code(),
                    exception.validationField(), exception.validationReason(),
                    itemCount(output == null ? null : output.checklist()),
                    itemCount(output == null ? null : output.clarificationQuestions()),
                    elapsedMilliseconds(modelCallStartedAt));
            throw exception;
        }
        LOGGER.info(
                "OCI GenAI chat model call completed provider=oci-genai model={} outcome=ACCEPTED "
                        + "correlationId={} schemaValidated=true guardrailStatus=PASSED checklistItemCount={} "
                        + "clarificationQuestionCount={} durationMs={}",
                properties.model(), safeCorrelation(request.traceId()), checklist.size(), questions.size(),
                elapsedMilliseconds(modelCallStartedAt));

        List<SourceReference> sources = new ArrayList<>();
        sources.add(new SourceReference("DOCUMENT_REVIEW", request.reviewId()));
        if (!request.documentSummaryId().isEmpty()) {
            sources.add(new SourceReference("AI_DOCUMENT_SUMMARY", request.documentSummaryId()));
        }
        boundedEvidence.issues().stream().flatMap(issue -> issue.documentIds().stream()).distinct()
                .map(documentId -> new SourceReference("DOCUMENT", documentId)).forEach(sources::add);

        return new ManualReviewAssistanceResponse(assistanceId, "COMPLETED", "oci-genai", properties.model(),
                request.applicationId(), request.workflowId(), request.taskReference(), request.traceId(),
                request.reviewId(), request.documentSummaryId(), request.audience(), checklist, questions,
                List.copyOf(sources), "PASSED");
    }

    private static void validateCorrelation(ManualReviewAssistanceRequest request, DocumentReviewEvidence evidence) {
        // The INITIAL decision owns manual-review routing. A completed CLEAR
        // document review can still need a human for policy, risk or financial
        // evidence; it is a valid bounded input to reviewer assistance.
        if (evidence == null || !Objects.equals(request.reviewId(), evidence.reviewId())
                || !Objects.equals(request.applicationId(), evidence.applicationId())
                || !Objects.equals(request.workflowId(), evidence.workflowId())
                || !Objects.equals(request.traceId(), evidence.traceId())
                || !"COMPLETED".equals(evidence.reviewStatus())
                || evidence.disposition() == null
                || !Set.of("CLEAR", "MANUAL_REVIEW").contains(evidence.disposition())) {
            throw ReviewAssistanceException.evidenceMismatch();
        }
    }

    private static BoundedReviewEvidence minimize(DocumentReviewEvidence evidence) {
        var counts = evidence.documentCounts();
        BoundedDocumentCounts boundedCounts = counts == null ? null
                : new BoundedDocumentCounts(counts.total(), counts.validated(), counts.needsReview(),
                        counts.retryRequired(), counts.blocked());
        List<BoundedReviewIssue> issues = evidence.issues() == null ? List.of()
                : evidence.issues().stream().filter(Objects::nonNull)
                        .map(issue -> new BoundedReviewIssue(issue.issueCode(), issue.severity(),
                                issue.routingEffect(), issue.documentIds() == null ? List.of()
                                        : issue.documentIds().stream().filter(Objects::nonNull).distinct().toList()))
                        .toList();
        return new BoundedReviewEvidence(evidence.reviewId(), evidence.disposition(), evidence.profileVersion(),
                boundedCounts, issues);
    }

    private String toJson(BoundedReviewEvidence evidence) {
        try {
            return objectMapper.writeValueAsString(evidence);
        } catch (JacksonException exception) {
            throw new IllegalStateException("Bounded document-review evidence could not be serialized", exception);
        }
    }

    private static List<String> validateItems(List<String> items, int minimum, int maximum, OutputField field) {
        if (items == null) {
            throw ReviewAssistanceException.unsafeModelOutput(field, OutputValidationReason.MISSING_LIST);
        }
        if (items.size() < minimum) {
            throw ReviewAssistanceException.unsafeModelOutput(field, OutputValidationReason.TOO_FEW_ITEMS);
        }
        if (items.size() > maximum) {
            throw ReviewAssistanceException.unsafeModelOutput(field, OutputValidationReason.TOO_MANY_ITEMS);
        }
        Set<String> normalized = new LinkedHashSet<>();
        for (String item : items) {
            if (item == null) {
                throw ReviewAssistanceException.unsafeModelOutput(field, OutputValidationReason.NULL_ITEM);
            }
            String trimmed = item.strip();
            if (trimmed.isEmpty()) {
                throw ReviewAssistanceException.unsafeModelOutput(field, OutputValidationReason.BLANK_ITEM);
            }
            if (trimmed.length() > MAX_ITEM_LENGTH) {
                throw ReviewAssistanceException.unsafeModelOutput(field, OutputValidationReason.ITEM_TOO_LONG);
            }
            if (FORBIDDEN_DECISION_LANGUAGE.matcher(trimmed).find()) {
                throw ReviewAssistanceException.unsafeModelOutput(field, OutputValidationReason.DECISION_LANGUAGE);
            }
            if (SENSITIVE_OUTPUT.matcher(trimmed).find()) {
                throw ReviewAssistanceException.unsafeModelOutput(field, OutputValidationReason.SENSITIVE_DATA);
            }
            normalized.add(trimmed);
        }
        if (normalized.size() < minimum) {
            throw ReviewAssistanceException.unsafeModelOutput(field, OutputValidationReason.TOO_FEW_DISTINCT_ITEMS);
        }
        return List.copyOf(normalized);
    }

    private void logFailedModelCall(String errorCode, String traceId, long startedAt) {
        LOGGER.warn(
                "OCI GenAI chat model call completed provider=oci-genai model={} outcome=FAILED correlationId={} errorCode={} "
                        + "durationMs={}",
                properties.model(), safeCorrelation(traceId), errorCode, elapsedMilliseconds(startedAt));
    }

    private static String safeCorrelation(String traceId) {
        return traceId != null && traceId.matches("[0-9a-fA-F]{32}") ? traceId : "UNAVAILABLE";
    }

    private static int itemCount(List<String> items) {
        return items == null ? 0 : items.size();
    }

    private static long elapsedMilliseconds(long startedAt) {
        return TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - startedAt);
    }

    private static String digest(String idempotencyKey, ManualReviewAssistanceRequest request) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            String value = String.join("\u0000", idempotencyKey, request.applicationId(), request.workflowId(),
                    request.taskReference(), request.traceId(), request.reviewId(), request.documentSummaryId(),
                    request.audience());
            return HexFormat.of().formatHex(digest.digest(value.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException("SHA-256 is not available", exception);
        }
    }

    record BoundedReviewEvidence(String reviewId, String disposition, String profileVersion,
            BoundedDocumentCounts documentCounts, List<BoundedReviewIssue> issues) {
    }

    record BoundedDocumentCounts(int total, int validated, int needsReview, int retryRequired, int blocked) {
    }

    record BoundedReviewIssue(String issueCode, String severity, String routingEffect, List<String> documentIds) {
    }
}
