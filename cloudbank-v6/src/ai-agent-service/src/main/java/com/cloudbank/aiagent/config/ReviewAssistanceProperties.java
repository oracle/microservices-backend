// Copyright (c) 2026, Oracle and/or its affiliates.
//
// Licensed under the Universal Permissive License v 1.0 as shown at
// https://oss.oracle.com/licenses/upl/.
//

package com.cloudbank.aiagent.config;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.validation.annotation.Validated;

@Validated
@ConfigurationProperties(prefix = "cloudbank.ai.manual-review")
public record ReviewAssistanceProperties(@NotBlank String model,
        @Min(1) @Max(10000) long cacheMaximumSize,
        @NotBlank String systemPrompt,
        @NotBlank String evidencePrompt) {
}
