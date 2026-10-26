// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.

package com.cloudbank.decision.service;

import com.cloudbank.decision.api.DecisionApiModels.DecisionRequest;
import com.cloudbank.decision.api.DecisionApiModels.PolicyCitation;
import com.cloudbank.decision.client.LoanApplicationClient;
import com.cloudbank.decision.domain.DecisionModels.DecisionFacts;
import com.cloudbank.decision.domain.DecisionModels.DecisionOutcome;
import com.cloudbank.decision.domain.DecisionModels.DecisionResult;
import com.cloudbank.decision.domain.DecisionModels.DecisionType;
import com.cloudbank.decision.persistence.DecisionRepository;
import com.cloudbank.decision.rules.DecisionRulesV1;
import java.util.ArrayList;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import tools.jackson.core.JacksonException;
import tools.jackson.databind.ObjectMapper;

@Service
public class DecisionService {
    private static final Logger log = LoggerFactory.getLogger(DecisionService.class);
    private final DecisionRepository repository;
    private final DecisionRulesV1 rules;
    private final DecisionFingerprintService fingerprints;
    private final LoanApplicationClient loan;
    private final ObjectMapper json;

    public DecisionService(DecisionRepository repository, DecisionRulesV1 rules,
            DecisionFingerprintService fingerprints, LoanApplicationClient loan, ObjectMapper json) {
        this.repository = repository;
        this.rules = rules;
        this.fingerprints = fingerprints;
        this.loan = loan;
        this.json = json;
    }

    @Transactional
    public DecisionResult decide(DecisionRequest request, String idempotencyKey) {
        String idempotencyHash = fingerprints.sha256(idempotencyKey);
        String requestHash = fingerprints.sha256(canonical(request));
        var existing = repository.findByIdempotencyHash(idempotencyHash);
        if (existing.isPresent()) {
            if (!existing.get().requestHash().equals(requestHash))
                throw new DecisionServiceException("IDEMPOTENCY_KEY_CONFLICT", HttpStatus.CONFLICT,
                        "Idempotency key was used with a different decision request.", false);
            synchronizeApplicationStatus(existing.get().result());
            return existing.get().result();
        }

        DecisionFacts facts = repository.findFacts(request.applicationId())
                .orElseThrow(() -> new DecisionServiceException("APPLICATION_NOT_FOUND", HttpStatus.NOT_FOUND,
                        "Loan application was not found.", false));
        if (repository.existsByApplicationAndType(request.applicationId(), request.decisionType().name()))
            throw new DecisionServiceException("DECISION_ALREADY_EXISTS", HttpStatus.CONFLICT,
                    "A decision of this type already exists for the application.", false);
        validateManualSequence(request);
        var evaluation = rules.evaluate(request, facts);
        List<PolicyCitation> citations = citations(request, evaluation.reasonCodes());
        String decisionId = fingerprints.decisionId(request.applicationId(), request.decisionType().name(),
                idempotencyKey);
        DecisionResult result = new DecisionResult(decisionId, request.applicationId(), request.workflowId(),
                request.taskReference(), request.decisionType(), evaluation.outcome(),
                evaluation.riskBand().databaseValue(), facts.policyVersion(), DecisionRulesV1.VERSION,
                "DETERMINISTIC_POLICY_RULES", evaluation.reasonCodes(), citations, request.traceId());
        repository.persist(result, facts, evaluation.evaluatedDebtToIncomePct(), request.manualReview(),
                idempotencyHash, requestHash);
        synchronizeApplicationStatus(result);
        log.info("Deterministic decision completed decisionId={} applicationId={} type={} outcome={} riskBand={} reasonCount={} citationCount={}",
                result.decisionId(), result.applicationId(), result.decisionType(), result.outcome(), result.riskBand(),
                result.reasonCodes().size(), result.policyCitations().size());
        return result;
    }

    @Transactional(readOnly = true)
    public DecisionResult get(String decisionId) {
        return repository.findByDecisionId(decisionId)
                .orElseThrow(() -> new DecisionServiceException("DECISION_NOT_FOUND", HttpStatus.NOT_FOUND,
                        "Decision was not found.", false));
    }

    @Transactional(readOnly = true)
    public DecisionResult latest(String applicationId) {
        return repository.findByApplicationAndType(applicationId, DecisionType.MANUAL_FINAL.name())
                .or(() -> repository.findByApplicationAndType(applicationId, DecisionType.INITIAL.name()))
                .orElseThrow(() -> new DecisionServiceException("DECISION_NOT_FOUND", HttpStatus.NOT_FOUND,
                        "Decision was not found.", false));
    }

    private void validateManualSequence(DecisionRequest request) {
        if (request.decisionType() != DecisionType.MANUAL_FINAL)
            return;
        DecisionResult initial = repository.findByApplicationAndType(request.applicationId(), DecisionType.INITIAL.name())
                .orElseThrow(() -> new DecisionServiceException("INITIAL_DECISION_REQUIRED", HttpStatus.CONFLICT,
                        "A manual-final decision requires an initial decision.", false));
        if (initial.outcome() != DecisionOutcome.MANUAL_REVIEW)
            throw new DecisionServiceException("MANUAL_REVIEW_NOT_OPEN", HttpStatus.CONFLICT,
                    "The initial decision did not route this application to manual review.", false);
    }

    private void synchronizeApplicationStatus(DecisionResult result) {
        DecisionFacts facts = repository.findFacts(result.applicationId())
                .orElseThrow(() -> new DecisionServiceException("APPLICATION_NOT_FOUND", HttpStatus.NOT_FOUND,
                        "Loan application was not found.", false));
        String current = facts.applicationStatus();
        String target = result.outcome().name();
        if (current.equals(target))
            return;

        if (result.decisionType() == DecisionType.INITIAL
                && ("SUBMITTED".equals(current) || "DOCUMENTS_RECEIVED".equals(current))) {
            loan.transitionStatus(result.applicationId(), current, "PROCESSING", result.decisionId() + "-PROCESSING",
                    "DETERMINISTIC_DECISION_STARTED", result.workflowId(), result.taskReference(), result.traceId());
            current = "PROCESSING";
        }
        String expected = result.decisionType() == DecisionType.MANUAL_FINAL ? "MANUAL_REVIEW" : "PROCESSING";
        if (!current.equals(expected))
            throw new DecisionServiceException("APPLICATION_STATUS_CONFLICT", HttpStatus.CONFLICT,
                    "Application state is incompatible with the deterministic decision.", false);
        loan.transitionStatus(result.applicationId(), expected, target, result.decisionId() + "-OUTCOME",
                "DETERMINISTIC_DECISION_" + target, result.workflowId(), result.taskReference(), result.traceId());
    }

    private List<PolicyCitation> citations(DecisionRequest request, List<String> reasons) {
        List<PolicyCitation> citations = new ArrayList<>();
        if (reasons.contains("ALL_DETERMINISTIC_RULES_PASSED")) {
            addIfMissing(citations, new PolicyCitation("CBPL-100-S3-C01", "CBPL-100", "S3"));
            addIfMissing(citations, new PolicyCitation("CBPL-130-S5-C01", "CBPL-130", "S5"));
        }
        if (reasons.stream().anyMatch(reason -> reason.contains("DTI_EXCEEDS")
                || reason.contains("SEVERE_DELINQUENCY") || reason.contains("OPEN_BANKRUPTCY")
                || reason.contains("PAYMENT_CALCULATION_FAILED")))
            addIfMissing(citations, new PolicyCitation("CBPL-130-S4-C01", "CBPL-130", "S4"));
        if (reasons.stream().anyMatch(reason -> reason.contains("DTI_") || reason.contains("CAPACITY")))
            addIfMissing(citations, new PolicyCitation("CBPL-130-S3-C01", "CBPL-130", "S3"));
        if (reasons.stream().anyMatch(reason -> reason.contains("INCOME") || reason.contains("EMPLOYMENT")))
            addIfMissing(citations, new PolicyCitation("CBPL-120-S4-C01", "CBPL-120", "S4-S8"));
        if (reasons.stream().anyMatch(reason -> reason.contains("PAYMENT") || reason.contains("AMOUNT")
                || reason.contains("TERM")))
            addIfMissing(citations, new PolicyCitation("CBPL-140-S5-C01", "CBPL-140", "S5"));
        if (reasons.stream().anyMatch(reason -> reason.contains("REVIEW") || reason.contains("EVIDENCE")
                || reason.contains("RISK") || reason.contains("MISSING") || reason.startsWith("UNDERWRITER_")))
            addIfMissing(citations, new PolicyCitation("CBPL-150-S2-C01", "CBPL-150", "S2"));
        if (request.manualReview() != null) {
            String section = request.manualReview().policySection();
            int sectionMarker = section.lastIndexOf("-S");
            addIfMissing(citations, new PolicyCitation(section + "-C01", section.substring(0, sectionMarker),
                    section.substring(sectionMarker + 1)));
        }
        request.evidence().policyCitations().forEach(citation -> addIfMissing(citations, citation));
        return citations.stream().limit(10).toList();
    }

    private void addIfMissing(List<PolicyCitation> citations, PolicyCitation wanted) {
        if (citations.stream().noneMatch(value -> value.chunkId().equals(wanted.chunkId())))
            citations.add(wanted);
    }

    private String canonical(Object value) {
        try {
            return json.writeValueAsString(value);
        } catch (JacksonException exception) {
            throw new IllegalStateException("Decision request could not be serialized", exception);
        }
    }
}
