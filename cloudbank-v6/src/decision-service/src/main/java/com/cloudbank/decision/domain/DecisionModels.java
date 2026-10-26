// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.

package com.cloudbank.decision.domain;

import com.cloudbank.decision.api.DecisionApiModels.PolicyCitation;
import com.cloudbank.decision.api.DecisionApiModels.ManualReviewResolution;
import java.math.BigDecimal;
import java.util.List;

public final class DecisionModels {
    private DecisionModels() {
    }

    public enum DecisionType {
        INITIAL, MANUAL_FINAL
    }

    public enum DecisionOutcome {
        APPROVED, REJECTED, MANUAL_REVIEW
    }

    public enum RiskBand {
        CB_A("CB-A"), CB_B("CB-B"), CB_C("CB-C"), CB_X("CB-X"), NOT_SCORED("NOT_SCORED");

        private final String databaseValue;

        RiskBand(String databaseValue) {
            this.databaseValue = databaseValue;
        }

        public String databaseValue() {
            return databaseValue;
        }
    }

    public record DecisionFacts(long applicationSk, String applicationId, String applicationStatus,
            BigDecimal requestedAmount, int requestedTermMonths, String purposeCode, String policyVersion,
            String employmentStatus, String tenureBand, BigDecimal verifiedMonthlyIncome,
            String incomeConsistency, String extractionConfidence, String documentValidationStatus,
            BigDecimal existingMonthlyDebt, BigDecimal proposedMonthlyPayment, BigDecimal debtToIncomePct,
            String delinquency, String bankruptcy, BigDecimal evaluatedAmount, Integer paymentTermMonths,
            BigDecimal monthlyPayment, String paymentCalculationStatus) {
    }

    public record DecisionResult(String decisionId, String applicationId, String workflowId, String taskReference,
            DecisionType decisionType, DecisionOutcome outcome, String riskBand, String policyVersion,
            String ruleProfileVersion, String decisionSource, List<String> reasonCodes,
            List<PolicyCitation> policyCitations, String traceId) {
        public DecisionResult {
            reasonCodes = List.copyOf(reasonCodes);
            policyCitations = List.copyOf(policyCitations);
        }
    }

    /**
     * Restricted database payload used to reconstruct a decision. It is never
     * returned by the REST API or written to application logs.
     */
    public record DecisionPersistencePayload(DecisionResult result, DecisionFactSnapshot facts,
            ManualReviewResolution manualReview) {
    }

    public record DecisionFactSnapshot(BigDecimal requestedAmount, int requestedTermMonths, String purposeCode,
            String policyVersion, String employmentStatus, String tenureBand, BigDecimal verifiedMonthlyIncome,
            String incomeConsistency, String extractionConfidence, String documentValidationStatus,
            BigDecimal existingMonthlyDebt, BigDecimal proposedMonthlyPayment, BigDecimal storedDebtToIncomePct,
            BigDecimal evaluatedDebtToIncomePct, String delinquency, String bankruptcy,
            BigDecimal evaluatedAmount, Integer paymentTermMonths, BigDecimal monthlyPayment,
            String paymentCalculationStatus) {

        public static DecisionFactSnapshot from(DecisionFacts facts, BigDecimal evaluatedDebtToIncomePct) {
            return new DecisionFactSnapshot(facts.requestedAmount(), facts.requestedTermMonths(), facts.purposeCode(),
                    facts.policyVersion(), facts.employmentStatus(), facts.tenureBand(),
                    facts.verifiedMonthlyIncome(), facts.incomeConsistency(), facts.extractionConfidence(),
                    facts.documentValidationStatus(), facts.existingMonthlyDebt(), facts.proposedMonthlyPayment(),
                    facts.debtToIncomePct(), evaluatedDebtToIncomePct, facts.delinquency(), facts.bankruptcy(),
                    facts.evaluatedAmount(), facts.paymentTermMonths(), facts.monthlyPayment(),
                    facts.paymentCalculationStatus());
        }
    }

    public record StoredDecision(DecisionResult result, String requestHash) {
    }
}
