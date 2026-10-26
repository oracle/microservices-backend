// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.

package com.cloudbank.aiagent.persistence;

import com.cloudbank.aiagent.api.AiAgentApiModels.DocumentEvidenceSummaryResponse;
import com.cloudbank.aiagent.service.ReviewAssistanceException;
import java.util.Optional;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.dao.DataAccessException;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;
import tools.jackson.databind.ObjectMapper;

@Repository
public class DocumentSummaryRepository {
    private final JdbcClient jdbc;
    private final ObjectMapper json;
    private final String table;

    public DocumentSummaryRepository(JdbcClient jdbc, ObjectMapper json,
            @Value("${cloudbank.schema:CLOUDBANK}") String schema) {
        if (!schema.matches("[A-Za-z][A-Za-z0-9_$#]{0,127}")) {
            throw new IllegalArgumentException("Invalid AI result schema name");
        }
        this.jdbc = jdbc;
        this.json = json;
        this.table = schema + ".CB_AI_DOCUMENT_SUMMARY";
    }

    public Optional<StoredSummary> find(String keyHash) {
        try {
            return jdbc.sql("SELECT request_hash, result_payload FROM " + table + " WHERE key_hash = :keyHash")
                    .param("keyHash", keyHash)
                    .query((rs, row) -> new StoredSummary(rs.getString("request_hash"),
                            json.readValue(rs.getString("result_payload"), DocumentEvidenceSummaryResponse.class)))
                    .optional();
        } catch (RuntimeException exception) {
            throw ReviewAssistanceException.resultStoreUnavailable(exception);
        }
    }

    public DocumentEvidenceSummaryResponse save(String keyHash, String requestHash,
            DocumentEvidenceSummaryResponse response) {
        try {
            jdbc.sql("""
                    INSERT INTO %s (summary_id, key_hash, request_hash, application_id, workflow_id,
                        task_reference, trace_id, review_id, result_payload)
                    VALUES (:id, :keyHash, :requestHash, :applicationId, :workflowId,
                        :taskReference, :traceId, :reviewId, :payload)
                    """.formatted(table))
                    .param("id", response.summaryId()).param("keyHash", keyHash).param("requestHash", requestHash)
                    .param("applicationId", response.applicationId()).param("workflowId", response.workflowId())
                    .param("taskReference", response.taskReference()).param("traceId", response.traceId())
                    .param("reviewId", response.reviewId()).param("payload", json.writeValueAsString(response))
                    .update();
            return response;
        } catch (DuplicateKeyException exception) {
            // Concurrent replicas may generate simultaneously; all return the durable winner.
            StoredSummary stored = find(keyHash).orElseThrow(() ->
                    ReviewAssistanceException.resultStoreUnavailable(exception));
            return stored.replay(requestHash);
        } catch (DataAccessException exception) {
            throw ReviewAssistanceException.resultStoreUnavailable(exception);
        }
    }

    public record StoredSummary(String requestHash, DocumentEvidenceSummaryResponse response) {
        public DocumentEvidenceSummaryResponse replay(String expectedHash) {
            if (!requestHash.equals(expectedHash)) {
                throw ReviewAssistanceException.idempotencyConflict();
            }
            return response;
        }
    }
}
