// Copyright (c) 2026, Oracle and/or its affiliates.
//
// Licensed under the Universal Permissive License v 1.0 as shown at
// https://oss.oracle.com/licenses/upl/.
//

package com.cloudbank.aiagent.api;

import com.cloudbank.aiagent.api.AiAgentApiModels.ManualReviewAssistanceRequest;
import com.cloudbank.aiagent.api.AiAgentApiModels.ManualReviewAssistanceResponse;
import com.cloudbank.aiagent.service.GenAIReviewAssistanceService;
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
public class ManualReviewAssistanceController {
    private static final String IDEMPOTENCY_PATTERN = "[A-Za-z0-9._:-]{8,200}";
    private final GenAIReviewAssistanceService service;

    public ManualReviewAssistanceController(GenAIReviewAssistanceService service) {
        this.service = service;
    }

    @PostMapping("/manual-review-assistances")
    @PreAuthorize("@aiAgentAuthorization.isInternal(authentication)")
    public ManualReviewAssistanceResponse assist(
            @RequestHeader("Idempotency-Key") @Pattern(regexp = IDEMPOTENCY_PATTERN) String idempotencyKey,
            @Valid @RequestBody ManualReviewAssistanceRequest request) {
        return service.assist(request, idempotencyKey);
    }
}
