// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.

package com.cloudbank.decision.rules;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.cloudbank.decision.api.DecisionApiModels.DecisionRequest;
import com.cloudbank.decision.api.DecisionApiModels.EvidenceReferences;
import com.cloudbank.decision.api.DecisionApiModels.ManualReviewResolution;
import com.cloudbank.decision.api.DecisionApiModels.PolicyCitation;
import com.cloudbank.decision.domain.DecisionModels.DecisionFacts;
import com.cloudbank.decision.domain.DecisionModels.DecisionOutcome;
import com.cloudbank.decision.domain.DecisionModels.DecisionType;
import com.cloudbank.decision.service.DecisionServiceException;
import java.math.BigDecimal;
import java.util.List;
import org.testng.annotations.Test;

public class DecisionRulesV1Test {
    private final DecisionRulesV1 rules = new DecisionRulesV1();

    @Test
    public void approvesOnlyCompleteClearLowDtiEvidence() {
        var result = rules.evaluate(request(DecisionType.INITIAL, clearEvidence(), null), facts("18.9", "NONE", "NONE"));

        assertThat(result.outcome()).isEqualTo(DecisionOutcome.APPROVED);
        assertThat(result.riskBand().databaseValue()).isEqualTo("CB-A");
        assertThat(result.reasonCodes()).containsExactly("ALL_DETERMINISTIC_RULES_PASSED");
    }

    @Test
    public void rejectsDtiAboveHardThresholdBeforeManualSignals() {
        EvidenceReferences manualEvidence = new EvidenceReferences("DREV-0123456789abcdef0123456789abcdef",
                "MANUAL_REVIEW", "AIPOL-1", "INSUFFICIENT_EVIDENCE", List.of(), "GEO-1", "NOT_EVALUATED");

        var result = rules.evaluate(request(DecisionType.INITIAL, manualEvidence, null),
                facts("50.1", "NONE", "NONE", "3100", "514"));

        assertThat(result.outcome()).isEqualTo(DecisionOutcome.REJECTED);
        assertThat(result.reasonCodes()).containsExactly("DTI_EXCEEDS_HARD_REJECT_THRESHOLD");
    }

    @Test
    public void routesIncompleteCapacityFactsToManualReview() {
        DecisionFacts incomplete = new DecisionFacts(1, "APP-TEST-1", "PROCESSING", new BigDecimal("16000"), 36,
                "MAJOR_PURCHASE", "2026.0", "ACTIVE", "12_PLUS_MONTHS", new BigDecimal("7200"),
                "CONSISTENT_WITHIN_10_PERCENT", "HIGH", "PASS", null, null, null, null, null, null, null, null,
                null);

        var result = rules.evaluate(request(DecisionType.INITIAL, clearEvidence(), null), incomplete);

        assertThat(result.outcome()).isEqualTo(DecisionOutcome.MANUAL_REVIEW);
        assertThat(result.reasonCodes()).contains("CAPACITY_FACTS_MISSING", "PAYMENT_FACTS_MISSING");
    }

    @Test
    public void acceptsUnderwriterFinalApprovalWhenNoHardRejectExists() {
        ManualReviewResolution resolution = new ManualReviewResolution(DecisionOutcome.APPROVED, "UNDERWRITER",
                "underwriter-demo", "VERIFIED_EXCEPTION", "CBPL-150-S4");

        var result = rules.evaluate(request(DecisionType.MANUAL_FINAL, clearEvidence(), resolution),
                facts("47.9", "NONE", "NONE", "2934", "514"));

        assertThat(result.outcome()).isEqualTo(DecisionOutcome.APPROVED);
        assertThat(result.reasonCodes()).containsExactly("UNDERWRITER_VERIFIED_EXCEPTION");
    }

    @Test
    public void refusesManualFinalWithoutResolution() {
        assertThatThrownBy(() -> rules.evaluate(request(DecisionType.MANUAL_FINAL, clearEvidence(), null),
                facts("47.9", "NONE", "NONE")))
                .isInstanceOf(DecisionServiceException.class)
                .hasMessageContaining("requires an underwriter resolution");
    }

    private DecisionRequest request(DecisionType type, EvidenceReferences evidence, ManualReviewResolution resolution) {
        return new DecisionRequest("APP-TEST-1", "workflow-1", "deterministic_decision",
                "0123456789abcdef0123456789abcdef", type, evidence, resolution);
    }

    private EvidenceReferences clearEvidence() {
        return new EvidenceReferences("DREV-0123456789abcdef0123456789abcdef", "CLEAR", "AIPOL-1", "GROUNDED",
                List.of(new PolicyCitation("CBPL-130-S3-C01", "CBPL-130", "3")), "GEO-1", "CLEAR");
    }

    private DecisionFacts facts(String dti, String delinquency, String bankruptcy) {
        return facts(dti, delinquency, bankruptcy, "850", "514");
    }

    private DecisionFacts facts(String dti, String delinquency, String bankruptcy, String debt, String payment) {
        return new DecisionFacts(1, "APP-TEST-1", "PROCESSING", new BigDecimal("16000"), 36, "MAJOR_PURCHASE",
                "2026.0", "ACTIVE", "12_PLUS_MONTHS", new BigDecimal("7200"),
                "CONSISTENT_WITHIN_10_PERCENT", "HIGH", "PASS", new BigDecimal(debt), new BigDecimal(payment),
                new BigDecimal(dti), delinquency, bankruptcy, new BigDecimal("16000"), 36,
                new BigDecimal(payment), "CALCULATED");
    }
}
