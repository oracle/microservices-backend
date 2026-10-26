// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.

package com.cloudbank.decision.rules;

import com.cloudbank.decision.api.DecisionApiModels.DecisionRequest;
import com.cloudbank.decision.domain.DecisionModels.DecisionFacts;
import com.cloudbank.decision.domain.DecisionModels.DecisionOutcome;
import com.cloudbank.decision.domain.DecisionModels.RiskBand;
import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import com.cloudbank.decision.service.DecisionServiceException;

@Component
public class DecisionRulesV1 {
    public static final String VERSION = "decision-rules-v1";
    private static final BigDecimal MINIMUM_AUTO_INCOME = new BigDecimal("2500.00");
    private static final BigDecimal AUTO_DTI = new BigDecimal("36.0");
    private static final BigDecimal CONDITIONAL_AUTO_DTI = new BigDecimal("43.0");
    private static final BigDecimal HARD_REJECT_DTI = new BigDecimal("50.0");

    public RuleEvaluation evaluate(DecisionRequest request, DecisionFacts facts) {
        if ("BLOCKED".equals(request.evidence().geographicRiskDisposition()))
            throw new DecisionServiceException("GEOGRAPHIC_RISK_BLOCKED", HttpStatus.UNPROCESSABLE_CONTENT,
                    "Geographic-risk remediation is required before deterministic decisioning.", false);
        BigDecimal evaluatedDti = evaluatedDti(facts);
        RiskBand band = capacityBand(evaluatedDti);
        List<String> hardRejects = hardRejectReasons(facts, evaluatedDti);

        if (!hardRejects.isEmpty())
            return new RuleEvaluation(DecisionOutcome.REJECTED, band, hardRejects, evaluatedDti);

        if (request.decisionType().name().equals("MANUAL_FINAL")) {
            if (request.manualReview() == null)
                throw new DecisionServiceException("MANUAL_RESOLUTION_REQUIRED", HttpStatus.UNPROCESSABLE_CONTENT,
                        "A manual-final decision requires an underwriter resolution.", false);
            if (request.manualReview().outcome() == DecisionOutcome.MANUAL_REVIEW)
                throw new DecisionServiceException("FINAL_OUTCOME_REQUIRED", HttpStatus.UNPROCESSABLE_CONTENT,
                        "A manual-final decision must approve or reject the application.", false);
            return new RuleEvaluation(request.manualReview().outcome(), band,
                    List.of("UNDERWRITER_" + request.manualReview().reasonCode()), evaluatedDti);
        }

        if (request.manualReview() != null)
            throw new DecisionServiceException("MANUAL_RESOLUTION_NOT_ALLOWED", HttpStatus.UNPROCESSABLE_CONTENT,
                    "An initial decision cannot contain a manual resolution.", false);

        List<String> manualReasons = manualReasons(request, facts, evaluatedDti);
        if (!manualReasons.isEmpty())
            return new RuleEvaluation(DecisionOutcome.MANUAL_REVIEW, band, manualReasons, evaluatedDti);

        return new RuleEvaluation(DecisionOutcome.APPROVED, band, List.of("ALL_DETERMINISTIC_RULES_PASSED"),
                evaluatedDti);
    }

    private List<String> hardRejectReasons(DecisionFacts facts, BigDecimal evaluatedDti) {
        List<String> reasons = new ArrayList<>();
        if (evaluatedDti != null && evaluatedDti.compareTo(HARD_REJECT_DTI) > 0)
            reasons.add("DTI_EXCEEDS_HARD_REJECT_THRESHOLD");
        if ("RECENT_SEVERE".equals(facts.delinquency()))
            reasons.add("RECENT_SEVERE_DELINQUENCY");
        if ("OPEN".equals(facts.bankruptcy()))
            reasons.add("OPEN_BANKRUPTCY");
        if ("FAILED".equals(facts.paymentCalculationStatus()))
            reasons.add("PAYMENT_CALCULATION_FAILED");
        return reasons;
    }

    private List<String> manualReasons(DecisionRequest request, DecisionFacts facts, BigDecimal evaluatedDti) {
        List<String> reasons = new ArrayList<>();
        if (!"CLEAR".equals(request.evidence().documentDisposition()))
            reasons.add("DOCUMENT_REVIEW_REQUIRED");
        if (!"GROUNDED".equals(request.evidence().policyEvidenceStatus()))
            reasons.add("POLICY_EVIDENCE_INSUFFICIENT");
        if (!"CLEAR".equals(request.evidence().geographicRiskDisposition()))
            reasons.add("GEOGRAPHIC_RISK_" + request.evidence().geographicRiskDisposition());
        if (facts.verifiedMonthlyIncome() == null)
            reasons.add("VERIFIED_INCOME_MISSING");
        else if (facts.verifiedMonthlyIncome().compareTo(MINIMUM_AUTO_INCOME) < 0)
            reasons.add("VERIFIED_INCOME_BELOW_AUTO_THRESHOLD");
        if (!"CONSISTENT_WITHIN_10_PERCENT".equals(facts.incomeConsistency()))
            reasons.add("INCOME_NOT_CONSISTENT_FOR_AUTOMATION");
        if (!("HIGH".equals(facts.extractionConfidence()) || "HIGH_AFTER_RETRY".equals(facts.extractionConfidence())))
            reasons.add("INCOME_CONFIDENCE_BELOW_AUTO_THRESHOLD");
        if (!("PASS".equals(facts.documentValidationStatus())
                || "PASS_AFTER_RETRY".equals(facts.documentValidationStatus())))
            reasons.add("INCOME_DOCUMENT_NOT_VALIDATED");
        if (evaluatedDti == null || facts.existingMonthlyDebt() == null
                || facts.proposedMonthlyPayment() == null)
            reasons.add("CAPACITY_FACTS_MISSING");
        else if (evaluatedDti.compareTo(CONDITIONAL_AUTO_DTI) > 0)
            reasons.add("DTI_IN_MANUAL_REVIEW_BAND");
        if (evaluatedDti != null && facts.debtToIncomePct() != null
                && evaluatedDti.subtract(facts.debtToIncomePct()).abs().compareTo(new BigDecimal("0.1")) > 0)
            reasons.add("DTI_CALCULATION_MISMATCH");
        if (facts.paymentCalculationStatus() == null || facts.monthlyPayment() == null)
            reasons.add("PAYMENT_FACTS_MISSING");
        else if (!"CALCULATED".equals(facts.paymentCalculationStatus()))
            reasons.add("PAYMENT_NOT_CALCULATED");
        if (facts.proposedMonthlyPayment() != null && facts.monthlyPayment() != null
                && facts.proposedMonthlyPayment().subtract(facts.monthlyPayment()).abs()
                        .compareTo(new BigDecimal("0.01")) > 0)
            reasons.add("PAYMENT_PROJECTION_MISMATCH");
        if (facts.evaluatedAmount() != null && facts.requestedAmount().compareTo(facts.evaluatedAmount()) != 0)
            reasons.add("EVALUATED_AMOUNT_MISMATCH");
        if (facts.paymentTermMonths() != null && facts.requestedTermMonths() != facts.paymentTermMonths())
            reasons.add("PAYMENT_TERM_MISMATCH");
        if ("RECENT_MINOR".equals(facts.delinquency()) || "UNKNOWN".equals(facts.delinquency()))
            reasons.add("DELINQUENCY_REQUIRES_REVIEW");
        if ("DISCHARGED".equals(facts.bankruptcy()) || "UNKNOWN".equals(facts.bankruptcy()))
            reasons.add("BANKRUPTCY_REQUIRES_REVIEW");
        if ("LESS_THAN_6_MONTHS".equals(facts.tenureBand()) || "VARIABLE".equals(facts.tenureBand()))
            reasons.add("EMPLOYMENT_TENURE_REQUIRES_REVIEW");
        if (facts.employmentStatus() == null || "UNKNOWN".equals(facts.employmentStatus()))
            reasons.add("EMPLOYMENT_STATUS_REQUIRES_REVIEW");
        return reasons.stream().distinct().toList();
    }

    private BigDecimal evaluatedDti(DecisionFacts facts) {
        BigDecimal payment = facts.monthlyPayment() != null ? facts.monthlyPayment()
                : facts.proposedMonthlyPayment();
        if (facts.verifiedMonthlyIncome() == null || facts.verifiedMonthlyIncome().signum() <= 0
                || facts.existingMonthlyDebt() == null || payment == null)
            return facts.debtToIncomePct();
        return facts.existingMonthlyDebt().add(payment)
                .multiply(new BigDecimal("100"))
                .divide(facts.verifiedMonthlyIncome(), 4, java.math.RoundingMode.HALF_UP);
    }

    private RiskBand capacityBand(BigDecimal dti) {
        if (dti == null)
            return RiskBand.NOT_SCORED;
        if (dti.compareTo(AUTO_DTI) <= 0)
            return RiskBand.CB_A;
        if (dti.compareTo(CONDITIONAL_AUTO_DTI) <= 0)
            return RiskBand.CB_B;
        if (dti.compareTo(HARD_REJECT_DTI) <= 0)
            return RiskBand.CB_C;
        return RiskBand.CB_X;
    }

    public record RuleEvaluation(DecisionOutcome outcome, RiskBand riskBand, List<String> reasonCodes,
            BigDecimal evaluatedDebtToIncomePct) {
        public RuleEvaluation {
            reasonCodes = List.copyOf(reasonCodes);
        }
    }
}
