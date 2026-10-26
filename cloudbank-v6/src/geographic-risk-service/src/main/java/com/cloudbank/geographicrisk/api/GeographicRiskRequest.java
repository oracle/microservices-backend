// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.geographicrisk.api;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

public record GeographicRiskRequest(
        @NotBlank @Size(max = 80) String applicationId,
        @NotBlank @Size(max = 100) String workflowId,
        @NotBlank @Size(max = 120) String taskReference,
        @NotBlank @Pattern(regexp = "[0-9a-fA-F]{32}") String traceId) {
}
