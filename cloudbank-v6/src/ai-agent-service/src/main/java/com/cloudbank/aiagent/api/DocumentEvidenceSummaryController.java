// Copyright (c) 2026, Oracle and/or its affiliates.
//
// Licensed under the Universal Permissive License v 1.0 as shown at
// https://oss.oracle.com/licenses/upl/.
//

package com.cloudbank.aiagent.api;

import com.cloudbank.aiagent.api.AiAgentApiModels.DocumentEvidenceSummaryRequest;
import com.cloudbank.aiagent.api.AiAgentApiModels.DocumentEvidenceSummaryResponse;
import com.cloudbank.aiagent.service.GenAIDocumentEvidenceSummaryService;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Pattern;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@Validated
@RequestMapping("/internal/api/v1/ai")
public class DocumentEvidenceSummaryController {
    private static final String IDEMPOTENCY_PATTERN = "[A-Za-z0-9._:-]{8,200}";
    private final GenAIDocumentEvidenceSummaryService service;

    public DocumentEvidenceSummaryController(GenAIDocumentEvidenceSummaryService service) {
        this.service = service;
    }

    @PostMapping("/document-evidence-summaries")
    @PreAuthorize("@aiAgentAuthorization.isInternal(authentication)")
    public DocumentEvidenceSummaryResponse summarize(
            @RequestHeader("Idempotency-Key") @Pattern(regexp = IDEMPOTENCY_PATTERN) String idempotencyKey,
            @Valid @RequestBody DocumentEvidenceSummaryRequest request) {
        return service.summarize(request, idempotencyKey);
    }
}
