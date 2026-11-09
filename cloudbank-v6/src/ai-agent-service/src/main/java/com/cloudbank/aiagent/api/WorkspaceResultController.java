// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.
package com.cloudbank.aiagent.api;

import com.cloudbank.aiagent.api.AiAgentApiModels.SourceReference;
import com.cloudbank.aiagent.persistence.DocumentSummaryRepository;
import com.cloudbank.aiagent.service.DeterministicPolicyEvidenceSupportService;
import com.cloudbank.aiagent.service.GenAIReviewAssistanceService;
import jakarta.validation.constraints.Pattern;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

/** Reads accepted results only. Never invokes a model or reconstructs a task. */
@RestController
@Validated
public class WorkspaceResultController {
    private final DocumentSummaryRepository summaries;
    private final GenAIReviewAssistanceService assistance;
    private final DeterministicPolicyEvidenceSupportService policy;

    public WorkspaceResultController(DocumentSummaryRepository summaries, GenAIReviewAssistanceService assistance,
            DeterministicPolicyEvidenceSupportService policy) {
        this.summaries = summaries;
        this.assistance = assistance;
        this.policy = policy;
    }

    @GetMapping("/internal/api/v1/workspace/applications/{applicationId}/ai-results/{resultId}")
    @PreAuthorize("@aiAgentAuthorization.isWorkspaceReader(authentication)")
    public ResponseEntity<Result> read(
            @PathVariable @Pattern(regexp = "APP-[A-Za-z0-9][A-Za-z0-9-]{0,35}") String applicationId,
            @PathVariable @Pattern(regexp = "(?:AISUM|AIPOL|AIREV)-[0-9a-fA-F]{32}") String resultId,
            @RequestParam @Pattern(regexp = "[A-Za-z0-9._:-]{1,100}") String workflowId) {
        Result result;
        if (resultId.startsWith("AISUM-")) {
            var value = summaries.readResult(applicationId, workflowId, resultId).orElseThrow(WorkspaceResultController::missing);
            result = new Result(value.applicationId(), value.workflowId(), value.taskReference(), value.summaryId(),
                    value.provider(), value.model(), value.guardrailStatus(), value.summary(), value.reviewNotes(),
                    List.of(), List.of(), value.sourceReferences());
        } else if (resultId.startsWith("AIPOL-")) {
            var value = policy.readResult(resultId).orElseThrow(WorkspaceResultController::missing);
            result = new Result(value.applicationId(), value.workflowId(), value.taskReference(), value.policySupportId(),
                    value.provider(), value.model(), value.guardrailStatus(), value.summary(), value.supportNotes(),
                    List.of(), List.of(), value.sourceReferences());
        } else {
            var value = assistance.readResult(resultId).orElseThrow(WorkspaceResultController::missing);
            result = new Result(value.applicationId(), value.workflowId(), value.taskReference(), value.assistanceId(),
                    value.provider(), value.model(), value.guardrailStatus(), null, List.of(), value.checklist(),
                    value.clarificationQuestions(), value.sourceReferences());
        }
        if (!applicationId.equals(result.applicationId()) || !workflowId.equals(result.workflowId())) throw missing();
        if (!"PASSED".equals(result.guardrailStatus())) throw new ResponseStatusException(HttpStatus.BAD_GATEWAY);
        return ResponseEntity.ok().header("Cache-Control", "private, no-store").body(result);
    }

    private static ResponseStatusException missing() {
        return new ResponseStatusException(HttpStatus.NOT_FOUND);
    }

    public record Result(String applicationId, String workflowId, String taskReference, String resultId,
            String provider, String model, String guardrailStatus, String summary, List<String> notes,
            List<String> checklist, List<String> clarificationQuestions, List<SourceReference> sourceReferences) { }
}
