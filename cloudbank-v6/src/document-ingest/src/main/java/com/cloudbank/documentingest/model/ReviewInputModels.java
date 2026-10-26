// Copyright (c) 2026, Oracle and/or its affiliates.
//
// Licensed under the Universal Permissive License v 1.0 as shown at
// https://oss.oracle.com/licenses/upl/.
//

package com.cloudbank.documentingest.model;

import java.math.BigDecimal;
import java.util.List;

public final class ReviewInputModels {
    private ReviewInputModels() {
    }

    public record ReviewInputResponse(String applicationId, List<ReviewInputDocument> documents) {
    }

    public record ReviewInputDocument(String documentId, String documentType, String extractionId,
            String extractionStatus, String provider, String model, BigDecimal confidenceScore, ReviewFacts facts,
            List<String> validationSignals, List<String> warnings) {
    }

    /** applicationIdFromDocument is a null legacy field; association belongs to the response envelope. */
    public record ReviewFacts(String applicationIdFromDocument, String employerName,
            BigDecimal statedGrossMonthlyIncome, BigDecimal payStatementMonthlyGross,
            BigDecimal verifiedGrossMonthlyIncome, String identityOutcome, BigDecimal existingMonthlyDebt,
            BigDecimal proposedMonthlyPayment, BigDecimal debtToIncomePct) {
    }
}
