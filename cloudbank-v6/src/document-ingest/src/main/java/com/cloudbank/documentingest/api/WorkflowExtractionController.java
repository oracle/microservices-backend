// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.documentingest.api;

import com.cloudbank.documentingest.model.WorkflowExtractionModels.WorkflowExtractionRequest;
import com.cloudbank.documentingest.model.WorkflowExtractionModels.WorkflowExtractionResponse;
import com.cloudbank.documentingest.service.WorkflowExtractionService;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Pattern;
import java.io.IOException;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@Validated
@RequestMapping("/internal/api/v1/document-extractions")
public class WorkflowExtractionController {

    private static final String IDEMPOTENCY_PATTERN = "[A-Za-z0-9._:-]{8,200}";

    private final WorkflowExtractionService service;

    public WorkflowExtractionController(WorkflowExtractionService service) {
        this.service = service;
    }

    @PostMapping
    @PreAuthorize("@documentIngestAuthorization.isInternal(authentication)")
    public WorkflowExtractionResponse extract(
            @RequestHeader("Idempotency-Key") @Pattern(regexp = IDEMPOTENCY_PATTERN) String idempotencyKey,
            @Valid @RequestBody WorkflowExtractionRequest request) throws IOException {
        return service.extract(request, idempotencyKey);
    }
}
