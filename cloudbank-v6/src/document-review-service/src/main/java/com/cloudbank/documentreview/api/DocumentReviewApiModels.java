// Copyright (c) 2026, Oracle and/or its affiliates.
//
// Licensed under the Universal Permissive License v 1.0 as shown at
// https://oss.oracle.com/licenses/upl/.
//

package com.cloudbank.documentreview.api;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.util.List;

public final class DocumentReviewApiModels {
    private DocumentReviewApiModels() {
    }

    public record DocumentReviewRequest(
            @NotBlank @Pattern(regexp = "APP-[A-Za-z0-9][A-Za-z0-9-]{0,35}") String applicationId,
            @NotBlank @Size(max = 100) String workflowId, @NotBlank @Size(max = 120) String taskReference,
            @NotBlank @Pattern(regexp = "[0-9a-fA-F]{32}") String traceId) {
    }

    public record FieldError(String field, String message) {
    }

    public record ErrorResponse(String code, String message, String correlationId, boolean retryable,
            String authorizationStatus, List<FieldError> fieldErrors) {
    }
}
