// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.documentingest.persistence;

import com.cloudbank.documentingest.model.ExtractionModels.ExtractionResponse;
import com.cloudbank.documentingest.model.ReviewInputModels.ReviewFacts;
import com.cloudbank.documentingest.model.ReviewInputModels.ReviewInputDocument;
import java.util.List;
import tools.jackson.core.JacksonException;
import tools.jackson.databind.ObjectMapper;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

@Repository
public class ExtractionRepository {

    private final JdbcClient jdbc;
    private final SqlNames names;
    private final ObjectMapper objectMapper;

    public ExtractionRepository(JdbcClient jdbc, SqlNames names, ObjectMapper objectMapper) {
        this.jdbc = jdbc;
        this.names = names;
        this.objectMapper = objectMapper;
    }

    @Transactional
    public String persist(String applicationId, String documentId, String contentSha256, ExtractionResponse extraction,
            String traceId) {
        String extractionId = "EXT-" + documentId + "-" + contentSha256.substring(0, 16);
        int lineCount = extraction.packets().stream().flatMap(packet -> packet.getDocuments().stream())
                .mapToInt(document -> document.textLineCount()).sum();
        jdbc.sql("""
                MERGE INTO %s target
                USING (
                  SELECT d.document_sk, d.application_sk, :extractionId extraction_id,
                         :payload extraction_payload, :lineCount raw_text_line_count, :traceId trace_id
                  FROM %s d JOIN %s a ON a.application_sk = d.application_sk
                  WHERE a.application_id = :applicationId AND d.document_id = :documentId
                ) source
                ON (target.extraction_id = source.extraction_id)
                WHEN NOT MATCHED THEN INSERT (
                  document_sk, application_sk, extraction_id, provider, extraction_model,
                  extraction_status, extraction_payload, raw_text_line_count, retry_count, trace_id
                ) VALUES (
                  source.document_sk, source.application_sk, source.extraction_id,
                  'DOCUMENT_INGEST', 'local_pdf_text', 'SUCCEEDED', source.extraction_payload,
                  source.raw_text_line_count, 0, source.trace_id
                )
                """.formatted(names.table("CB_DOCUMENT_EXTRACTION"), names.table("CB_DOCUMENT"),
                names.table("CB_LOAN_APPLICATION"))).param("extractionId", extractionId)
                .param("payload", json(extraction)).param("lineCount", lineCount).param("traceId", traceId)
                .param("applicationId", applicationId).param("documentId", documentId).update();
        boolean persisted = jdbc
                .sql("SELECT COUNT(*) FROM " + names.table("CB_DOCUMENT_EXTRACTION")
                        + " WHERE extraction_id = :extractionId")
                .param("extractionId", extractionId).query(Integer.class).single() == 1;
        if (!persisted) {
            throw new IllegalStateException("Document metadata was not accessible for extraction persistence");
        }
        return extractionId;
    }

    /** Returns a deliberately bounded projection; it never exposes PDF bytes, raw text, or tokens. */
    public List<ReviewInputDocument> reviewInput(String applicationId) {
        return jdbc
                .sql(reviewInputSql(names))
                .param("applicationId", applicationId)
                .query((rs, row) -> new ReviewInputDocument(rs.getString("document_id"), rs.getString("document_type"),
                        rs.getString("extraction_id"), rs.getString("extraction_status"), rs.getString("provider"),
                        rs.getString("extraction_model"), rs.getBigDecimal("confidence_score"),
                        new ReviewFacts(null, rs.getString("employer_name"),
                                rs.getBigDecimal("stated_income"), rs.getBigDecimal("pay_income"),
                                rs.getBigDecimal("verified_income"), rs.getString("identity_outcome"),
                                rs.getBigDecimal("existing_debt"), rs.getBigDecimal("proposed_payment"),
                                rs.getBigDecimal("dti_pct")),
                        List.of(), List.of()))
                .list();
    }

    static String reviewInputSql(SqlNames names) {
        return """
                        SELECT d.document_id, d.document_type, e.extraction_id, e.extraction_status,
                               e.provider, e.extraction_model, e.confidence_score,
                               JSON_VALUE(e.extraction_payload, '$.packets[0].employment.employer') employer_name,
                               JSON_VALUE(e.extraction_payload, '$.packets[0].income.statedGrossMonthlyIncome' RETURNING NUMBER) stated_income,
                               JSON_VALUE(e.extraction_payload, '$.packets[0].income.payStatementMonthlyGross' RETURNING NUMBER) pay_income,
                               JSON_VALUE(e.extraction_payload, '$.packets[0].income.verifiedGrossMonthlyIncome' RETURNING NUMBER) verified_income,
                               JSON_VALUE(e.extraction_payload, '$.packets[0].identity.outcome') identity_outcome,
                               JSON_VALUE(e.extraction_payload, '$.packets[0].liabilities.existingMonthlyDebt' RETURNING NUMBER) existing_debt,
                               JSON_VALUE(e.extraction_payload, '$.packets[0].liabilities.proposedMonthlyPayment' RETURNING NUMBER) proposed_payment,
                               TO_NUMBER(REPLACE(JSON_VALUE(e.extraction_payload,
                                 '$.packets[0].liabilities.debtToIncome' RETURNING VARCHAR2(40)), '%%', '')) dti_pct
                        FROM %s d JOIN %s a ON a.application_sk = d.application_sk
                        LEFT JOIN %s e ON e.extraction_sk = (
                          SELECT MAX(candidate.extraction_sk) FROM %s candidate WHERE candidate.document_sk = d.document_sk
                        ) WHERE a.application_id = :applicationId ORDER BY d.received_at, d.document_id
                        """
                .formatted(names.table("CB_DOCUMENT"), names.table("CB_LOAN_APPLICATION"),
                        names.table("CB_DOCUMENT_EXTRACTION"), names.table("CB_DOCUMENT_EXTRACTION"));
    }

    private String json(ExtractionResponse extraction) {
        try {
            return objectMapper.writeValueAsString(extraction);
        } catch (JacksonException exception) {
            throw new IllegalStateException("Extraction response could not be serialized", exception);
        }
    }
}
