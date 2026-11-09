// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.
package com.cloudbank.decision.api;

import com.cloudbank.decision.domain.DecisionModels.WorkspaceDecision;
import com.cloudbank.decision.persistence.DecisionRepository;
import jakarta.validation.constraints.Pattern;
import java.util.List;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@Validated
public class WorkspaceDecisionController {
    private final DecisionRepository repository;

    public WorkspaceDecisionController(DecisionRepository repository) { this.repository = repository; }

    @GetMapping("/internal/api/v1/workspace/applications/{applicationId}/decisions")
    @PreAuthorize("@decisionAuthorization.isWorkspaceReader(authentication)")
    public ResponseEntity<Results> read(
            @PathVariable @Pattern(regexp = "APP-[A-Za-z0-9][A-Za-z0-9-]{0,35}") String applicationId,
            @RequestParam @Pattern(regexp = "[A-Za-z0-9._:-]{1,100}") String workflowId) {
        var entries = repository.workspace(applicationId, workflowId);
        return ResponseEntity.ok().header("Cache-Control", "private, no-store")
                .body(new Results(applicationId, workflowId, entries.stream().limit(2).toList(), entries.size() > 2));
    }

    public record Results(String applicationId, String workflowId, List<WorkspaceDecision> items, boolean truncated) { }
}
