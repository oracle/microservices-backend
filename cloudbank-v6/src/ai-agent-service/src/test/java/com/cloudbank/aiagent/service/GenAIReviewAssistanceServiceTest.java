// Copyright (c) 2026, Oracle and/or its affiliates.
//
// Licensed under the Universal Permissive License v 1.0 as shown at
// https://oss.oracle.com/licenses/upl/.
//

package com.cloudbank.aiagent.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.cloudbank.aiagent.api.AiAgentApiModels.ManualReviewAssistanceRequest;
import com.cloudbank.aiagent.client.DocumentReviewClient;
import com.cloudbank.aiagent.client.DocumentReviewEvidence;
import com.cloudbank.aiagent.client.DocumentReviewEvidence.DocumentCounts;
import com.cloudbank.aiagent.client.DocumentReviewEvidence.ReviewIssue;
import com.cloudbank.aiagent.config.ReviewAssistanceProperties;
import com.cloudbank.aiagent.service.SpringAiReviewAssistanceModel.ReviewAssistanceModelOutput;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.springframework.boot.test.system.CapturedOutput;
import org.springframework.boot.test.system.OutputCaptureExtension;
import tools.jackson.databind.ObjectMapper;

@ExtendWith(OutputCaptureExtension.class)
class GenAIReviewAssistanceServiceTest {
    private final DocumentReviewClient documentReviewClient = mock(DocumentReviewClient.class);
    private final SpringAiReviewAssistanceModel model = mock(SpringAiReviewAssistanceModel.class);
    private GenAIReviewAssistanceService service;

    @BeforeEach
    void setUp() {
        ReviewAssistanceProperties properties = new ReviewAssistanceProperties("cohere.command-a-03-2025", 100,
                "system", "{evidence}");
        service = new GenAIReviewAssistanceService(documentReviewClient, model, properties, new ObjectMapper());
    }

    @Test
    void retrievesBoundedEvidenceAndCachesAnIdempotentReplay(CapturedOutput logs) {
        when(documentReviewClient.get(request().reviewId(), request().traceId())).thenReturn(evidence());
        when(model.generate(anyString())).thenReturn(new ReviewAssistanceModelOutput(
                List.of("Verify the income inconsistency using an authorized source."),
                List.of("Which authorized evidence resolves the income inconsistency?")));

        var first = service.assist(request(), "manual-review:APP-ONE:WF-ONE");
        var replay = service.assist(request(), "manual-review:APP-ONE:WF-ONE");

        assertThat(replay).isEqualTo(first);
        assertThat(first.assistanceId()).matches("AIREV-[0-9a-f]{32}");
        assertThat(first.provider()).isEqualTo("oci-genai");
        assertThat(first.model()).isEqualTo("cohere.command-a-03-2025");
        assertThat(first.sourceReferences()).extracting(source -> source.sourceType())
                .containsExactly("DOCUMENT_REVIEW", "AI_DOCUMENT_SUMMARY", "DOCUMENT");
        assertThat(first.guardrailStatus()).isEqualTo("PASSED");
        verify(documentReviewClient, times(1)).get(request().reviewId(), request().traceId());
        verify(model, times(1)).generate(anyString());

        ArgumentCaptor<String> promptEvidence = ArgumentCaptor.forClass(String.class);
        verify(model).generate(promptEvidence.capture());
        assertThat(promptEvidence.getValue()).contains("INCOME_INCONSISTENCY", "DOC-001")
                .doesNotContain("Untrusted free-form review message", "APP-ONE", "WF-ONE");
        assertThat(logs).contains("OCI GenAI chat model call completed", "outcome=ACCEPTED",
                "schemaValidated=true", "guardrailStatus=PASSED", "checklistItemCount=1",
                "clarificationQuestionCount=1")
                .doesNotContain("Verify the income inconsistency", "Which authorized evidence", "APP-ONE",
                        "DREV-00000000000000000000000000000000", "INCOME_INCONSISTENCY", "DOC-001");
    }

    @Test
    void assistsWithoutAFabricatedSummaryReferenceWhenTheSummaryIsUnavailable() {
        var request = request();
        var withoutSummary = new ManualReviewAssistanceRequest(request.applicationId(), request.workflowId(),
                request.taskReference(), request.traceId(), request.reviewId(), "", request.audience());
        when(documentReviewClient.get(request.reviewId(), request.traceId())).thenReturn(evidence());
        when(model.generate(anyString())).thenReturn(new ReviewAssistanceModelOutput(
                List.of("Inspect authorized income evidence."), List.of("Which evidence resolves the inconsistency?")));
        var result = service.assist(withoutSummary, "manual-review:APP-ONE:no-summary");
        assertThat(result.documentSummaryId()).isEmpty();
        assertThat(result.sourceReferences()).noneMatch(source -> "AI_DOCUMENT_SUMMARY".equals(source.sourceType()));
    }

    @Test
    void rejectsEvidenceThatDoesNotMatchTheRequest() {
        DocumentReviewEvidence mismatched = new DocumentReviewEvidence(request().reviewId(), "APP-OTHER", "WF-ONE",
                "document_review", "COMPLETED", "MANUAL_REVIEW", "v1", new DocumentCounts(1, 0, 1, 0, 0),
                List.of(), request().traceId());
        when(documentReviewClient.get(request().reviewId(), request().traceId())).thenReturn(mismatched);

        assertThatThrownBy(() -> service.assist(request(), "manual-review:APP-ONE:mismatch"))
                .isInstanceOf(ReviewAssistanceException.class)
                .extracting(exception -> ((ReviewAssistanceException) exception).code())
                .isEqualTo("REVIEW_EVIDENCE_MISMATCH");
    }

    @Test
    void rejectsDecisionLanguageFromTheModel() {
        when(documentReviewClient.get(request().reviewId(), request().traceId())).thenReturn(evidence());
        when(model.generate(anyString())).thenReturn(new ReviewAssistanceModelOutput(
                List.of("Approve the application."), List.of("Is the evidence current?")));

        assertThatThrownBy(() -> service.assist(request(), "manual-review:APP-ONE:unsafe"))
                .isInstanceOf(ReviewAssistanceException.class)
                .extracting(exception -> ((ReviewAssistanceException) exception).code())
                .isEqualTo("GENAI_OUTPUT_REJECTED");
    }

    @Test
    void rejectsSensitiveDataFromTheModel(CapturedOutput logs) {
        when(documentReviewClient.get(request().reviewId(), request().traceId())).thenReturn(evidence());
        when(model.generate(anyString())).thenReturn(new ReviewAssistanceModelOutput(
                List.of("Contact reviewer@example.test."), List.of("Is the evidence current?")));

        assertThatThrownBy(() -> service.assist(request(), "manual-review:APP-ONE:sensitive"))
                .isInstanceOf(ReviewAssistanceException.class)
                .extracting(exception -> ((ReviewAssistanceException) exception).code())
                .isEqualTo("GENAI_OUTPUT_REJECTED");
        assertThat(logs).contains("outcome=REJECTED", "errorCode=GENAI_OUTPUT_REJECTED")
                .doesNotContain("reviewer@example.test", "Is the evidence current?");
    }

    @Test
    void rejectsUnboundedStructuredOutput() {
        when(documentReviewClient.get(request().reviewId(), request().traceId())).thenReturn(evidence());
        when(model.generate(anyString())).thenReturn(new ReviewAssistanceModelOutput(
                List.of("One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten",
                        "Eleven", "Twelve", "Thirteen"),
                List.of("Is the evidence current?")));

        assertThatThrownBy(() -> service.assist(request(), "manual-review:APP-ONE:unbounded"))
                .isInstanceOf(ReviewAssistanceException.class)
                .extracting(exception -> ((ReviewAssistanceException) exception).code())
                .isEqualTo("GENAI_OUTPUT_REJECTED");
    }

    @Test
    void reportsWorkloadIdentityInitializationFailureAsModelUnavailable(CapturedOutput logs) {
        when(documentReviewClient.get(request().reviewId(), request().traceId())).thenReturn(evidence());
        when(model.generate(anyString())).thenThrow(new IllegalStateException("workload identity unavailable"));

        assertThatThrownBy(() -> service.assist(request(), "manual-review:APP-ONE:identity"))
                .isInstanceOf(ReviewAssistanceException.class)
                .extracting(exception -> ((ReviewAssistanceException) exception).code())
                .isEqualTo("GENAI_UNAVAILABLE");
        assertThat(logs).contains("outcome=FAILED", "errorCode=GENAI_UNAVAILABLE")
                .doesNotContain("workload identity unavailable");
    }

    private static DocumentReviewEvidence evidence() {
        return new DocumentReviewEvidence(request().reviewId(), request().applicationId(), request().workflowId(),
                "document_review", "COMPLETED", "MANUAL_REVIEW", "v1",
                new DocumentCounts(2, 1, 1, 0, 0),
                List.of(new ReviewIssue("INCOME_INCONSISTENCY", "REVIEW", "MANUAL_REVIEW",
                        List.of("DOC-001", "DOC-001"), "Untrusted free-form review message")), request().traceId());
    }

    private static ManualReviewAssistanceRequest request() {
        return new ManualReviewAssistanceRequest("APP-ONE", "WF-ONE", "ai_manual_review_assistant",
                "0123456789abcdef0123456789abcdef", "DREV-00000000000000000000000000000000",
                "AISUM-00000000000000000000000000000000", "UNDERWRITER");
    }
}
