// Copyright (c) 2026, Oracle and/or its affiliates.
//
// Licensed under the Universal Permissive License v 1.0 as shown at
// https://oss.oracle.com/licenses/upl/.
//

package com.cloudbank.documentingest.api;

import com.cloudbank.documentingest.model.ReviewInputModels.ReviewInputResponse;
import com.cloudbank.documentingest.service.ReviewInputService;
import jakarta.validation.constraints.Pattern;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@Validated
@RequestMapping("/internal/api/v1/applications")
public class ReviewInputController {
    private final ReviewInputService service;

    public ReviewInputController(ReviewInputService service) {
        this.service = service;
    }

    @GetMapping("/{applicationId}/extractions/review-input")
    @PreAuthorize("@documentIngestAuthorization.isReviewInputReader(authentication)")
    public ReviewInputResponse reviewInput(
            @PathVariable @Pattern(regexp = "APP-[A-Za-z0-9][A-Za-z0-9-]{0,35}") String applicationId) {
        return service.reviewInput(applicationId);
    }
}
