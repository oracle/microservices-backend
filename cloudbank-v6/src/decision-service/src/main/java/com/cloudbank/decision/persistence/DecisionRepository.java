// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.

package com.cloudbank.decision.persistence;

import com.cloudbank.decision.api.DecisionApiModels.PolicyCitation;
import com.cloudbank.decision.api.DecisionApiModels.ManualReviewResolution;
import com.cloudbank.decision.domain.DecisionModels.DecisionFactSnapshot;
import com.cloudbank.decision.domain.DecisionModels.DecisionFacts;
import com.cloudbank.decision.domain.DecisionModels.DecisionPersistencePayload;
import com.cloudbank.decision.domain.DecisionModels.DecisionResult;
import com.cloudbank.decision.domain.DecisionModels.StoredDecision;
import java.util.Optional;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;
import tools.jackson.core.JacksonException;
import tools.jackson.databind.ObjectMapper;

@Repository
public class DecisionRepository {
    private final JdbcClient jdbc;
    private final SqlNames names;
    private final ObjectMapper json;

    public DecisionRepository(JdbcClient jdbc, SqlNames names, ObjectMapper json) {
        this.jdbc = jdbc;
        this.names = names;
        this.json = json;
    }

    public Optional<DecisionFacts> findFacts(String applicationId) {
        return jdbc.sql("""
                SELECT a.application_sk, a.application_id, a.application_status, a.requested_amount,
                       a.requested_term_months, a.purpose_code, a.policy_version,
                       e.employment_status, e.tenure_band,
                       i.verified_gross_monthly_income, i.income_consistency_result,
                       i.extraction_confidence, i.document_validation_status,
                       l.existing_monthly_debt, l.proposed_monthly_payment, l.debt_to_income_pct,
                       l.recent_delinquency_indicator, l.bankruptcy_indicator,
                       p.evaluated_amount, p.term_months payment_term_months,
                       p.monthly_payment, p.calculation_status
                  FROM %s a
                  LEFT JOIN %s e ON e.application_sk = a.application_sk
                  LEFT JOIN %s i ON i.application_sk = a.application_sk
                  LEFT JOIN %s l ON l.application_sk = a.application_sk
                  LEFT JOIN %s p ON p.application_sk = a.application_sk
                 WHERE a.application_id = :applicationId
                """.formatted(names.table("CB_LOAN_APPLICATION"), names.table("CB_EMPLOYMENT"),
                names.table("CB_INCOME_EVIDENCE"), names.table("CB_LIABILITY_SNAPSHOT"),
                names.table("CB_PAYMENT_CALCULATION")))
                .param("applicationId", applicationId)
                .query((rs, row) -> new DecisionFacts(rs.getLong("application_sk"), rs.getString("application_id"),
                        rs.getString("application_status"), rs.getBigDecimal("requested_amount"),
                        rs.getInt("requested_term_months"), rs.getString("purpose_code"),
                        rs.getString("policy_version"), rs.getString("employment_status"),
                        rs.getString("tenure_band"), rs.getBigDecimal("verified_gross_monthly_income"),
                        rs.getString("income_consistency_result"), rs.getString("extraction_confidence"),
                        rs.getString("document_validation_status"), rs.getBigDecimal("existing_monthly_debt"),
                        rs.getBigDecimal("proposed_monthly_payment"), rs.getBigDecimal("debt_to_income_pct"),
                        rs.getString("recent_delinquency_indicator"), rs.getString("bankruptcy_indicator"),
                        rs.getBigDecimal("evaluated_amount"), integer(rs, "payment_term_months"),
                        rs.getBigDecimal("monthly_payment"), rs.getString("calculation_status")))
                .optional();
    }

    private Integer integer(java.sql.ResultSet resultSet, String column) throws java.sql.SQLException {
        int value = resultSet.getInt(column);
        return resultSet.wasNull() ? null : value;
    }

    public Optional<StoredDecision> findByIdempotencyHash(String hash) {
        return jdbc.sql("SELECT decision_payload, request_hash FROM " + names.table("CB_DECISION")
                + " WHERE idempotency_key_hash = :hash")
                .param("hash", hash)
                .query((rs, row) -> new StoredDecision(read(rs.getString("decision_payload")),
                        rs.getString("request_hash")))
                .optional();
    }

    public Optional<DecisionResult> findByDecisionId(String decisionId) {
        return jdbc.sql("SELECT decision_payload FROM " + names.table("CB_DECISION")
                + " WHERE decision_id = :decisionId AND request_hash IS NOT NULL")
                .param("decisionId", decisionId).query((rs, row) -> read(rs.getString("decision_payload"))).optional();
    }

    public Optional<DecisionResult> findByApplicationAndType(String applicationId, String decisionType) {
        return jdbc.sql("SELECT d.decision_payload FROM " + names.table("CB_DECISION") + " d JOIN "
                + names.table("CB_LOAN_APPLICATION")
                + " a ON a.application_sk = d.application_sk WHERE a.application_id = :applicationId"
                + " AND d.decision_type = :decisionType AND d.request_hash IS NOT NULL")
                .param("applicationId", applicationId).param("decisionType", decisionType)
                .query((rs, row) -> read(rs.getString("decision_payload"))).optional();
    }

    public boolean existsByApplicationAndType(String applicationId, String decisionType) {
        return jdbc.sql("SELECT COUNT(*) FROM " + names.table("CB_DECISION") + " d JOIN "
                + names.table("CB_LOAN_APPLICATION")
                + " a ON a.application_sk = d.application_sk WHERE a.application_id = :applicationId"
                + " AND d.decision_type = :decisionType")
                .param("applicationId", applicationId).param("decisionType", decisionType)
                .query(Integer.class).single() > 0;
    }

    public void persist(DecisionResult result, DecisionFacts facts, java.math.BigDecimal evaluatedDti,
            ManualReviewResolution manualReview, String idempotencyHash, String requestHash) {
        jdbc.sql("""
                INSERT INTO %s (application_sk, decision_id, decision_type, decision_outcome, risk_band,
                    policy_version, decision_payload, decided_by, workflow_id, task_reference,
                    idempotency_key_hash, request_hash, trace_id)
                SELECT application_sk, :decisionId, :decisionType, :outcome, :riskBand,
                    :policyVersion, :payload, 'decision-service', :workflowId, :taskReference,
                    :idempotencyHash, :requestHash, :traceId
                  FROM %s WHERE application_id = :applicationId
                """.formatted(names.table("CB_DECISION"), names.table("CB_LOAN_APPLICATION")))
                .param("decisionId", result.decisionId()).param("decisionType", result.decisionType().name())
                .param("outcome", result.outcome().name()).param("riskBand", result.riskBand())
                .param("policyVersion", result.policyVersion())
                .param("payload", write(new DecisionPersistencePayload(result,
                        DecisionFactSnapshot.from(facts, evaluatedDti), manualReview)))
                .param("workflowId", result.workflowId()).param("taskReference", result.taskReference())
                .param("idempotencyHash", idempotencyHash).param("requestHash", requestHash)
                .param("traceId", result.traceId()).param("applicationId", result.applicationId()).update();

        long decisionSk = jdbc.sql("SELECT decision_sk FROM " + names.table("CB_DECISION")
                + " WHERE decision_id = :decisionId").param("decisionId", result.decisionId())
                .query(Long.class).single();
        int ordinal = 0;
        for (PolicyCitation citation : result.policyCitations()) {
            String evidenceId = result.decisionId() + "-" + (++ordinal);
            jdbc.sql("""
                    INSERT INTO %s (decision_sk, policy_chunk_sk, evidence_id, policy_code, section_ref,
                        evidence_role, evidence_summary)
                    VALUES (:decisionSk, (SELECT MAX(policy_chunk_sk) FROM %s WHERE chunk_id = :chunkId),
                        :evidenceId, :policyCode, :sectionRef, 'ROUTING',
                        'Authorized policy citation used by deterministic decision rules.')
                    """.formatted(names.table("CB_DECISION_POLICY_EVIDENCE"), names.table("CB_POLICY_CHUNK")))
                    .param("decisionSk", decisionSk).param("chunkId", citation.chunkId())
                    .param("evidenceId", evidenceId).param("policyCode", citation.policyCode())
                    .param("sectionRef", citation.sectionRef()).update();
        }
    }

    private String write(DecisionPersistencePayload payload) {
        try {
            return json.writeValueAsString(payload);
        } catch (JacksonException exception) {
            throw new IllegalStateException("Decision result could not be serialized", exception);
        }
    }

    private DecisionResult read(String payload) {
        try {
            DecisionPersistencePayload stored = json.readValue(payload, DecisionPersistencePayload.class);
            if (stored.result() == null)
                throw new IllegalStateException("Stored decision payload has no result");
            return stored.result();
        } catch (JacksonException exception) {
            throw new IllegalStateException("Stored decision payload is invalid", exception);
        }
    }
}
