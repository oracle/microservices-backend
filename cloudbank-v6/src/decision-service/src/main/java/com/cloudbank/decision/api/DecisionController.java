// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.

package com.cloudbank.decision.api;

import com.cloudbank.decision.api.DecisionApiModels.DecisionRequest;
import com.cloudbank.decision.domain.DecisionModels.DecisionResult;
import com.cloudbank.decision.service.DecisionService;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Pattern;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@Validated
@RequestMapping("/internal/api/v1")
public class DecisionController {
    private static final String IDEMPOTENCY_PATTERN = "[A-Za-z0-9._:-]{8,200}";
    private final DecisionService service;

    public DecisionController(DecisionService service) {
        this.service = service;
    }

    @PostMapping("/decisions")
    @PreAuthorize("@decisionAuthorization.isInternal(authentication)")
    public DecisionResult decide(
            @RequestHeader("Idempotency-Key") @Pattern(regexp = IDEMPOTENCY_PATTERN) String idempotencyKey,
            @Valid @RequestBody DecisionRequest request) {
        return service.decide(request, idempotencyKey);
    }

    @GetMapping("/decisions/{decisionId}")
    @PreAuthorize("@decisionAuthorization.isInternal(authentication)")
    public DecisionResult get(@PathVariable @Pattern(regexp = "DEC-[0-9a-f]{32}") String decisionId) {
        return service.get(decisionId);
    }

    @GetMapping("/applications/{applicationId}/decisions/latest")
    @PreAuthorize("@decisionAuthorization.isInternal(authentication)")
    public DecisionResult latest(
            @PathVariable @Pattern(regexp = "APP-[A-Za-z0-9][A-Za-z0-9-]{0,35}") String applicationId) {
        return service.latest(applicationId);
    }
}
