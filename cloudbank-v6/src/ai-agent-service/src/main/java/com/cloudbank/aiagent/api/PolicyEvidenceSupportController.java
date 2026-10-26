// Copyright (c) 2026, Oracle and/or its affiliates.
//
// Licensed under the Universal Permissive License v 1.0 as shown at
// https://oss.oracle.com/licenses/upl/.

package com.cloudbank.aiagent.api;

import com.cloudbank.aiagent.api.AiAgentApiModels.PolicyEvidenceSupportRequest;
import com.cloudbank.aiagent.api.AiAgentApiModels.PolicyEvidenceSupportResponse;
import com.cloudbank.aiagent.service.DeterministicPolicyEvidenceSupportService;
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
public class PolicyEvidenceSupportController {
    private static final String IDEMPOTENCY_PATTERN = "[A-Za-z0-9._:-]{8,200}";
    private final DeterministicPolicyEvidenceSupportService service;

    public PolicyEvidenceSupportController(DeterministicPolicyEvidenceSupportService service) {
        this.service = service;
    }

    @PostMapping("/policy-evidence-summaries")
    @PreAuthorize("@aiAgentAuthorization.isInternal(authentication)")
    public PolicyEvidenceSupportResponse summarize(
            @RequestHeader("Idempotency-Key") @Pattern(regexp = IDEMPOTENCY_PATTERN) String idempotencyKey,
            @Valid @RequestBody PolicyEvidenceSupportRequest request) {
        return service.summarize(request, idempotencyKey);
    }
}
