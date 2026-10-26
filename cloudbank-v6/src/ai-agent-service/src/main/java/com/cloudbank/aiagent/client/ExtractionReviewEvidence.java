// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.

package com.cloudbank.aiagent.client;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import java.math.BigDecimal;
import java.util.List;

@JsonIgnoreProperties(ignoreUnknown = true)
public record ExtractionReviewEvidence(String applicationId, List<ExtractionDocument> documents) {
    @JsonIgnoreProperties(ignoreUnknown = true)
    public record ExtractionDocument(String documentId, String documentType, String extractionId,
            String extractionStatus, BigDecimal confidenceScore, ReviewedFacts facts,
            List<String> validationSignals, List<String> warnings) {
    }

    // Deliberately do not deserialize employer names, document application IDs,
    // or monetary amounts. Only these bounded facts can reach the summary model.
    @JsonIgnoreProperties(ignoreUnknown = true)
    public record ReviewedFacts(String identityOutcome) {
    }
}
