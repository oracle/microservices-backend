// Copyright (c) 2026, Oracle and/or its affiliates.
//
// Licensed under the Universal Permissive License v 1.0 as shown at
// https://oss.oracle.com/licenses/upl/.
//

package com.cloudbank.documentreview.api;

import com.cloudbank.documentreview.api.DocumentReviewApiModels.DocumentReviewRequest;
import com.cloudbank.documentreview.domain.ReviewModels.ReviewResult;
import com.cloudbank.documentreview.service.DocumentReviewService;
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
public class DocumentReviewController {
    private static final String IDEMPOTENCY_PATTERN = "[A-Za-z0-9._:-]{8,200}";
    private final DocumentReviewService service;

    public DocumentReviewController(DocumentReviewService service) {
        this.service = service;
    }

    @PostMapping("/document-reviews")
    @PreAuthorize("@documentReviewAuthorization.isInternal(authentication)")
    public ReviewResult review(
            @RequestHeader("Idempotency-Key") @Pattern(regexp = IDEMPOTENCY_PATTERN) String idempotencyKey,
            @Valid @RequestBody DocumentReviewRequest request) {
        return service.review(request, idempotencyKey);
    }

    @GetMapping("/document-reviews/{reviewId}")
    @PreAuthorize("@documentReviewAuthorization.isInternal(authentication)")
    public ReviewResult get(@PathVariable @Pattern(regexp = "DREV-[0-9a-f]{32}") String reviewId) {
        return service.get(reviewId);
    }

    @GetMapping("/applications/{applicationId}/document-reviews/latest")
    @PreAuthorize("@documentReviewAuthorization.isInternal(authentication)")
    public ReviewResult latest(
            @PathVariable @Pattern(regexp = "APP-[A-Za-z0-9][A-Za-z0-9-]{0,35}") String applicationId) {
        return service.latest(applicationId);
    }
}
