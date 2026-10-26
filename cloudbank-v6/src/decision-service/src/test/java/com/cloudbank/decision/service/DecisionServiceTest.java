// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.

package com.cloudbank.decision.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.cloudbank.decision.api.DecisionApiModels.DecisionRequest;
import com.cloudbank.decision.api.DecisionApiModels.EvidenceReferences;
import com.cloudbank.decision.api.DecisionApiModels.PolicyCitation;
import com.cloudbank.decision.client.LoanApplicationClient;
import com.cloudbank.decision.domain.DecisionModels.DecisionFacts;
import com.cloudbank.decision.domain.DecisionModels.DecisionOutcome;
import com.cloudbank.decision.domain.DecisionModels.DecisionResult;
import com.cloudbank.decision.domain.DecisionModels.DecisionType;
import com.cloudbank.decision.domain.DecisionModels.RiskBand;
import com.cloudbank.decision.domain.DecisionModels.StoredDecision;
import com.cloudbank.decision.persistence.DecisionRepository;
import com.cloudbank.decision.rules.DecisionRulesV1;
import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;
import org.testng.annotations.BeforeMethod;
import org.testng.annotations.Test;
import tools.jackson.databind.ObjectMapper;

public class DecisionServiceTest {
    private DecisionRepository repository;
    private DecisionRulesV1 rules;
    private LoanApplicationClient loan;

    private DecisionFingerprintService fingerprints;
    private ObjectMapper json;
    private DecisionService service;

    @BeforeMethod
    public void setUp() {
        repository = mock(DecisionRepository.class);
        rules = mock(DecisionRulesV1.class);
        loan = mock(LoanApplicationClient.class);
        fingerprints = new DecisionFingerprintService();
        json = new ObjectMapper();
        service = new DecisionService(repository, rules, fingerprints, loan, json);
    }

    @Test
    public void persistsDecisionAndUpdatesCanonicalApplicationState() {
        DecisionRequest request = request();
        DecisionFacts facts = facts("DOCUMENTS_RECEIVED");
        when(repository.findByIdempotencyHash(anyString())).thenReturn(Optional.empty());
        when(repository.findFacts("APP-ONE")).thenReturn(Optional.of(facts), Optional.of(facts));
        when(repository.existsByApplicationAndType("APP-ONE", "INITIAL")).thenReturn(false);
        when(rules.evaluate(request, facts)).thenReturn(new DecisionRulesV1.RuleEvaluation(DecisionOutcome.APPROVED,
                RiskBand.CB_A, List.of("ALL_DETERMINISTIC_RULES_PASSED"), new BigDecimal("18.9444")));

        DecisionResult result = service.decide(request, "decision:initial:APP-ONE:WF-ONE");

        assertThat(result.outcome()).isEqualTo(DecisionOutcome.APPROVED);
        assertThat(result.decisionSource()).isEqualTo("DETERMINISTIC_POLICY_RULES");
        verify(repository).persist(any(), any(), any(), any(), anyString(), anyString());
        verify(loan).transitionStatus("APP-ONE", "DOCUMENTS_RECEIVED", "PROCESSING",
                result.decisionId() + "-PROCESSING", "DETERMINISTIC_DECISION_STARTED", "WF-ONE",
                "deterministic_initial_decision", "0123456789abcdef0123456789abcdef");
        verify(loan).transitionStatus("APP-ONE", "PROCESSING", "APPROVED",
                result.decisionId() + "-OUTCOME", "DETERMINISTIC_DECISION_APPROVED", "WF-ONE",
                "deterministic_initial_decision", "0123456789abcdef0123456789abcdef");
    }

    @Test
    public void replaysAnIdenticalIdempotentRequestWithoutReevaluatingRules() throws Exception {
        DecisionRequest request = request();
        String idempotencyKey = "decision:initial:APP-ONE:WF-ONE";
        DecisionResult stored = result();
        String requestHash = fingerprints.sha256(json.writeValueAsString(request));
        when(repository.findByIdempotencyHash(fingerprints.sha256(idempotencyKey)))
                .thenReturn(Optional.of(new StoredDecision(stored, requestHash)));
        when(repository.findFacts("APP-ONE")).thenReturn(Optional.of(facts("APPROVED")));

        assertThat(service.decide(request, idempotencyKey)).isEqualTo(stored);

        verify(rules, never()).evaluate(any(), any());
        verify(repository, never()).persist(any(), any(), any(), any(), anyString(), anyString());
        verify(loan, never()).transitionStatus(anyString(), anyString(), anyString(), anyString(), anyString(),
                anyString(), anyString(), anyString());
    }

    private DecisionRequest request() {
        var evidence = new EvidenceReferences("DREV-0123456789abcdef0123456789abcdef", "CLEAR", "AIPOL-ONE",
                "GROUNDED", List.of(new PolicyCitation("CBPL-130-S5-C01", "CBPL-130", "S5")), "GEO-ONE",
                "CLEAR");
        return new DecisionRequest("APP-ONE", "WF-ONE", "deterministic_initial_decision",
                "0123456789abcdef0123456789abcdef", DecisionType.INITIAL, evidence, null);
    }

    private DecisionFacts facts(String status) {
        return new DecisionFacts(1, "APP-ONE", status, new BigDecimal("16000"), 36, "MAJOR_PURCHASE", "2026.0",
                "ACTIVE", "12_PLUS_MONTHS", new BigDecimal("7200"), "CONSISTENT_WITHIN_10_PERCENT", "HIGH",
                "PASS", new BigDecimal("850"), new BigDecimal("514"), new BigDecimal("18.9"), "NONE", "NONE",
                new BigDecimal("16000"), 36, new BigDecimal("514"), "CALCULATED");
    }

    private DecisionResult result() {
        return new DecisionResult("DEC-00000000000000000000000000000000", "APP-ONE", "WF-ONE",
                "deterministic_initial_decision", DecisionType.INITIAL, DecisionOutcome.APPROVED, "CB-A", "2026.0",
                "decision-rules-v1", "DETERMINISTIC_POLICY_RULES", List.of("ALL_DETERMINISTIC_RULES_PASSED"),
                List.of(), "0123456789abcdef0123456789abcdef");
    }
}
