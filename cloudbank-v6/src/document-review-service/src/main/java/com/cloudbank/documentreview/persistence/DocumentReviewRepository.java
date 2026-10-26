// Copyright (c) 2026, Oracle and/or its affiliates.
//
// Licensed under the Universal Permissive License v 1.0 as shown at
// https://oss.oracle.com/licenses/upl/.
//

package com.cloudbank.documentreview.persistence;

import com.cloudbank.documentreview.domain.ReviewModels.ExtractedFacts;
import com.cloudbank.documentreview.domain.ReviewModels.ExtractionDocument;
import com.cloudbank.documentreview.domain.ReviewModels.ExtractionReviewInput;
import com.cloudbank.documentreview.domain.ReviewModels.ReviewDisposition;
import com.cloudbank.documentreview.domain.ReviewModels.ReviewIssue;
import com.cloudbank.documentreview.domain.ReviewModels.ReviewResult;
import com.cloudbank.documentreview.domain.ReviewModels.ReviewStatus;
import com.cloudbank.documentreview.domain.ReviewModels.RoutingEffect;
import com.cloudbank.documentreview.domain.ReviewModels.StoredReview;
import tools.jackson.core.JacksonException;
import tools.jackson.databind.ObjectMapper;
import java.util.List;
import java.util.Optional;
import java.util.function.Function;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

@Repository
public class DocumentReviewRepository {
    private final JdbcClient jdbc;
    private final SqlNames names;
    private final ObjectMapper json;

    public DocumentReviewRepository(JdbcClient jdbc, SqlNames names, ObjectMapper json) {
        this.jdbc = jdbc;
        this.names = names;
        this.json = json;
    }

    public Optional<StoredReview> findByIdempotencyHash(String hash) {
        return jdbc
                .sql("SELECT result_payload, request_hash FROM " + names.table("CB_DOCUMENT_REVIEW")
                        + " WHERE idempotency_key_hash = :hash")
                .param("hash", hash).query((rs, row) -> new StoredReview(read(rs.getString(1)), rs.getString(2)))
                .optional();
    }

    public Optional<ReviewResult> findByReviewId(String reviewId) {
        return jdbc
                .sql("SELECT result_payload FROM " + names.table("CB_DOCUMENT_REVIEW") + " WHERE review_id = :reviewId")
                .param("reviewId", reviewId).query((rs, row) -> read(rs.getString(1))).optional();
    }

    public Optional<ReviewResult> findLatest(String applicationId) {
        return jdbc.sql("SELECT result_payload FROM " + names.table("CB_DOCUMENT_REVIEW") + " r JOIN "
                + names.table("CB_LOAN_APPLICATION")
                + " a ON a.application_sk = r.application_sk WHERE a.application_id = :applicationId ORDER BY r.created_at DESC FETCH FIRST 1 ROW ONLY")
                .param("applicationId", applicationId).query((rs, row) -> read(rs.getString(1))).optional();
    }

    public void persist(ReviewResult result, String idempotencyHash, String requestHash, String fingerprint) {
        String payload = write(result);
        jdbc.sql(
                """
                        MERGE INTO %s target USING (SELECT a.application_sk, :reviewId review_id, :workflowId workflow_id, :taskReference task_reference, :idempotencyHash idempotency_key_hash, :requestHash request_hash, :fingerprint input_fingerprint, :profileVersion profile_version, :reviewStatus review_status, :disposition disposition, :payload result_payload, :traceId trace_id FROM %s a WHERE a.application_id = :applicationId) source ON (target.idempotency_key_hash = source.idempotency_key_hash)
                        WHEN NOT MATCHED THEN INSERT (application_sk, review_id, workflow_id, task_reference, idempotency_key_hash, request_hash, input_fingerprint, profile_version, review_status, disposition, result_payload, trace_id, completed_at) VALUES (source.application_sk, source.review_id, source.workflow_id, source.task_reference, source.idempotency_key_hash, source.request_hash, source.input_fingerprint, source.profile_version, source.review_status, source.disposition, source.result_payload, source.trace_id, CASE WHEN source.review_status = 'COMPLETED' THEN SYSTIMESTAMP END)
                        """
                        .formatted(names.table("CB_DOCUMENT_REVIEW"), names.table("CB_LOAN_APPLICATION")))
                .param("reviewId", result.reviewId()).param("workflowId", result.workflowId())
                .param("taskReference", result.taskReference()).param("idempotencyHash", idempotencyHash)
                .param("requestHash", requestHash).param("fingerprint", fingerprint)
                .param("profileVersion", result.profileVersion()).param("reviewStatus", result.reviewStatus().name())
                .param("disposition", result.disposition().name()).param("payload", payload)
                .param("traceId", result.traceId()).param("applicationId", result.applicationId()).update();
    }

    public void persistProjections(ReviewResult result, ExtractionReviewInput input) {
        for (ReviewIssue issue : result.issues()) {
            String documentId = issue.documentIds().isEmpty() ? null : issue.documentIds().getFirst();
            String routing = switch (issue.routingEffect()) {
                case RETRY_EXTRACTION -> "RETRY";
                case MANUAL_REVIEW -> "MANUAL_REVIEW";
                case BLOCKED -> "BLOCKED";
            };
            jdbc.sql(
                    """
                            MERGE INTO %s target USING (SELECT a.application_sk, d.document_sk, :code issue_code, :severity issue_severity, :routing routing_effect, :detail issue_detail FROM %s a LEFT JOIN %s d ON d.application_sk = a.application_sk AND d.document_id = :documentId WHERE a.application_id = :applicationId) source
                            ON (target.application_sk = source.application_sk AND target.issue_code = source.issue_code)
                            WHEN MATCHED THEN UPDATE SET target.document_sk = source.document_sk, target.issue_severity = source.issue_severity, target.routing_effect = source.routing_effect, target.issue_detail = source.issue_detail, target.detected_at = SYSTIMESTAMP
                            WHEN NOT MATCHED THEN INSERT (application_sk, document_sk, issue_code, issue_severity, routing_effect, policy_hint, issue_detail) VALUES (source.application_sk, source.document_sk, source.issue_code, source.issue_severity, source.routing_effect, 'DOCUMENT_REVIEW', source.issue_detail)
                            """
                            .formatted(names.table("CB_DOCUMENT_ISSUE"), names.table("CB_LOAN_APPLICATION"),
                                    names.table("CB_DOCUMENT")))
                    .param("code", issue.issueCode()).param("severity", issue.severity().name())
                    .param("routing", routing).param("detail", issue.message()).param("documentId", documentId)
                    .param("applicationId", result.applicationId()).update();
        }
        if (input.documents() == null || input.documents().isEmpty())
            return;
        java.math.BigDecimal stated = firstFact(input, ExtractedFacts::statedGrossMonthlyIncome);
        java.math.BigDecimal pay = firstFact(input, ExtractedFacts::payStatementMonthlyGross);
        java.math.BigDecimal verified = firstFact(input, ExtractedFacts::verifiedGrossMonthlyIncome);
        java.math.BigDecimal existingDebt = firstFact(input, ExtractedFacts::existingMonthlyDebt);
        java.math.BigDecimal proposedPayment = firstFact(input, ExtractedFacts::proposedMonthlyPayment);
        java.math.BigDecimal dti = firstFact(input, ExtractedFacts::debtToIncomePct);
        String incomeDocumentId = firstDocumentId(input, facts -> facts.verifiedGrossMonthlyIncome());

        promoteFact(result.applicationId(), incomeDocumentId, "statedGrossMonthlyIncome", stated, result.profileVersion());
        promoteFact(result.applicationId(), incomeDocumentId, "payStatementMonthlyGross", pay, result.profileVersion());
        promoteFact(result.applicationId(), incomeDocumentId, "verifiedGrossMonthlyIncome", verified, result.profileVersion());
        if (stated != null && verified != null)
            jdbc.sql(
                    """
                            MERGE INTO %s target USING (SELECT a.application_sk, d.document_sk FROM %s a LEFT JOIN %s d ON d.application_sk = a.application_sk AND d.document_id = :documentId WHERE a.application_id = :applicationId) source ON (target.application_sk = source.application_sk)
                            WHEN MATCHED THEN UPDATE SET target.document_sk = source.document_sk, stated_gross_monthly_income = :stated, pay_document_monthly_income = :pay, verified_gross_monthly_income = :verified, income_consistency_result = :consistency, extraction_confidence = :confidence, document_validation_status = :validation, evidence_timestamp = SYSTIMESTAMP
                            WHEN NOT MATCHED THEN INSERT (application_sk, document_sk, stated_gross_monthly_income, pay_document_monthly_income, verified_gross_monthly_income, income_consistency_result, extraction_confidence, document_validation_status) VALUES (source.application_sk, source.document_sk, :stated, :pay, :verified, :consistency, :confidence, :validation)
                            """
                            .formatted(names.table("CB_INCOME_EVIDENCE"), names.table("CB_LOAN_APPLICATION"),
                                    names.table("CB_DOCUMENT")))
                    .param("documentId", incomeDocumentId).param("applicationId", result.applicationId())
                    .param("stated", stated).param("pay", pay).param("verified", verified)
                    .param("consistency",
                            result.issues().stream().anyMatch(issue -> issue.issueCode().contains("INCOME_DIFFERENCE"))
                                    ? "INCONSISTENT_OVER_10_PERCENT"
                                    : "CONSISTENT_WITHIN_10_PERCENT")
                    .param("confidence",
                            maximumConfidence(input) != null && maximumConfidence(input).doubleValue() >= .85
                                    ? "HIGH"
                                    : "LOW")
                    .param("validation", result.disposition() == ReviewDisposition.CLEAR ? "PASS" : "REVIEW").update();
        if (existingDebt != null && proposedPayment != null && dti != null) {
            jdbc.sql("""
                    MERGE INTO %s target USING (SELECT application_sk FROM %s WHERE application_id = :applicationId) source
                    ON (target.application_sk = source.application_sk)
                    WHEN MATCHED THEN UPDATE SET existing_monthly_debt = :existingDebt,
                        proposed_monthly_payment = :proposedPayment, debt_to_income_pct = :dti,
                        captured_at = SYSTIMESTAMP
                    WHEN NOT MATCHED THEN INSERT (application_sk, existing_monthly_debt,
                        proposed_monthly_payment, debt_to_income_pct)
                        VALUES (source.application_sk, :existingDebt, :proposedPayment, :dti)
                    """.formatted(names.table("CB_LIABILITY_SNAPSHOT"), names.table("CB_LOAN_APPLICATION")))
                    .param("applicationId", result.applicationId()).param("existingDebt", existingDebt)
                    .param("proposedPayment", proposedPayment).param("dti", dti).update();
            jdbc.sql("""
                    MERGE INTO %s target USING (SELECT application_sk, requested_amount,
                        requested_term_months, policy_version FROM %s WHERE application_id = :applicationId) source
                    ON (target.application_sk = source.application_sk)
                    WHEN MATCHED THEN UPDATE SET requested_amount = source.requested_amount,
                        evaluated_amount = source.requested_amount, term_months = source.requested_term_months,
                        apr_text = 'NOT_EVALUATED', monthly_payment = :proposedPayment,
                        calculation_status = 'CALCULATED', calculation_timestamp = SYSTIMESTAMP,
                        policy_version = source.policy_version
                    WHEN NOT MATCHED THEN INSERT (application_sk, requested_amount, evaluated_amount,
                        term_months, apr_text, monthly_payment, calculation_status, policy_version)
                        VALUES (source.application_sk, source.requested_amount, source.requested_amount,
                        source.requested_term_months, 'NOT_EVALUATED', :proposedPayment, 'CALCULATED',
                        source.policy_version)
                    """.formatted(names.table("CB_PAYMENT_CALCULATION"), names.table("CB_LOAN_APPLICATION")))
                    .param("applicationId", result.applicationId()).param("proposedPayment", proposedPayment).update();
        }
    }

    private <T> T firstFact(ExtractionReviewInput input, Function<ExtractedFacts, T> mapper) {
        return input.documents().stream().map(ExtractionDocument::facts).filter(java.util.Objects::nonNull)
                .map(mapper).filter(java.util.Objects::nonNull).findFirst().orElse(null);
    }

    private String firstDocumentId(ExtractionReviewInput input,
            Function<ExtractedFacts, java.math.BigDecimal> mapper) {
        return input.documents().stream().filter(document -> document.facts() != null)
                .filter(document -> mapper.apply(document.facts()) != null).map(ExtractionDocument::documentId)
                .findFirst().orElse(null);
    }

    private java.math.BigDecimal maximumConfidence(ExtractionReviewInput input) {
        return input.documents().stream().map(ExtractionDocument::confidenceScore).filter(java.util.Objects::nonNull)
                .max(java.math.BigDecimal::compareTo).orElse(null);
    }

    private void promoteFact(String applicationId, String documentId, String name, java.math.BigDecimal value,
            String profileVersion) {
        if (value == null)
            return;
        jdbc.sql(
                """
                        MERGE INTO %s target USING (SELECT a.application_sk, d.document_sk, :name fact_name, :value fact_value_number FROM %s a LEFT JOIN %s d ON d.application_sk = a.application_sk AND d.document_id = :documentId WHERE a.application_id = :applicationId) source ON (target.application_sk = source.application_sk AND target.fact_name = source.fact_name)
                        WHEN MATCHED THEN UPDATE SET target.document_sk = source.document_sk, target.fact_value_number = source.fact_value_number, fact_value_text = NULL, fact_value_date = NULL, source_field_path = :profileVersion
                        WHEN NOT MATCHED THEN INSERT (application_sk, document_sk, fact_name, fact_value_number, source_field_path) VALUES (source.application_sk, source.document_sk, source.fact_name, source.fact_value_number, :profileVersion)
                        """
                        .formatted(names.table("CB_DOCUMENT_FACT"), names.table("CB_LOAN_APPLICATION"),
                                names.table("CB_DOCUMENT")))
                .param("name", name).param("value", value).param("documentId", documentId)
                .param("applicationId", applicationId).param("profileVersion", profileVersion).update();
    }

    public void markCompleted(ReviewResult result) {
        ReviewResult completed = new ReviewResult(result.reviewId(), result.applicationId(), result.workflowId(),
                result.taskReference(), ReviewStatus.COMPLETED, result.disposition(), result.profileVersion(),
                result.documentCounts(), result.issues(), result.traceId(), result.acknowledgements());
        jdbc.sql("UPDATE " + names.table("CB_DOCUMENT_REVIEW")
                + " SET review_status = 'COMPLETED', result_payload = :payload, completed_at = SYSTIMESTAMP, updated_at = SYSTIMESTAMP WHERE review_id = :reviewId")
                .param("payload", write(completed)).param("reviewId", result.reviewId()).update();
    }

    private String write(ReviewResult result) {
        try {
            return json.writeValueAsString(result);
        } catch (JacksonException exception) {
            throw new IllegalStateException("Review result could not be serialized", exception);
        }
    }

    private ReviewResult read(String value) {
        try {
            return json.readValue(value, ReviewResult.class);
        } catch (JacksonException exception) {
            throw new IllegalStateException("Stored review payload is invalid", exception);
        }
    }
}
