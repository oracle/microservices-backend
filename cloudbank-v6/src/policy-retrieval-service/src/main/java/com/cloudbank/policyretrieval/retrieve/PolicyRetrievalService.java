// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.policyretrieval.retrieve;

import com.cloudbank.policyretrieval.model.AiUse;
import com.cloudbank.policyretrieval.model.DataClassification;
import com.cloudbank.policyretrieval.model.PolicyChunk;
import com.cloudbank.policyretrieval.model.PolicyDocument;
import com.cloudbank.policyretrieval.model.PolicyRole;
import com.cloudbank.policyretrieval.model.ReviewStatus;
import com.cloudbank.policyretrieval.persistence.SqlNames;
import com.cloudbank.policyretrieval.vector.EmbeddingModel;
import com.cloudbank.policyretrieval.vector.VectorDataAdapter;
import com.oracle.spring.json.jsonb.JSONB;
import jakarta.json.stream.JsonParser;
import oracle.sql.VECTOR;
import org.springframework.stereotype.Component;

import javax.sql.DataSource;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Timestamp;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Optional;

@Component
public class PolicyRetrievalService {
    private static final String VECTOR_SEARCH_SQL_TEMPLATE = """
            select pc.policy_chunk_sk, pc.policy_document_sk, pc.chunk_id,
                   pc.section_ref, pc.heading, pc.chunk_ordinal, pc.chunk_text,
                   pc.chunk_metadata, pc.min_role, pc.access_label, pc.ai_use,
                   pc.created_at as chunk_created_at,
                   pd.policy_document_id, pd.policy_code, pd.policy_title,
                   pd.policy_version, pd.source_path, pd.effective_date,
                   pd.review_status, pd.owner_role, pd.data_classification,
                   pd.metadata_json, pd.created_at as document_created_at,
                   (1 - vector_distance(pc.embedding, ?, COSINE)) as vector_score
            from %s pc
            join %s pd on pd.policy_document_sk = pc.policy_document_sk
            where case pc.min_role
                    when 'LOAN_OFFICER' then 1
                    when 'UNDERWRITER' then 2
                    when 'AUDITOR' then 3
                    when 'ADMIN' then 4
                  end <= ?
              and pc.ai_use = ?
              and pc.embedding is not null
            order by vector_score desc
            fetch first ? rows only
            """;

    private static final String FIND_BY_DOCUMENT_ID_SQL_TEMPLATE = """
            select pd.policy_document_id, pd.policy_code, pd.policy_title,
                   pd.policy_version, pd.source_path, pd.effective_date,
                   pd.review_status, pd.owner_role, pd.data_classification,
                   pd.metadata_json, pd.created_at as document_created_at
            from %s pd
            where pd.policy_document_sk = ?
            fetch first 1 rows only
            """;

    private final VectorDataAdapter vectorDataAdapter;
    private final EmbeddingModel embeddingModel;
    private final DataSource dataSource;
    private final JSONB jsonb;
    private final String vectorSearchSql;
    private final String findByDocumentIdSql;

    public PolicyRetrievalService(VectorDataAdapter vectorDataAdapter, EmbeddingModel embeddingModel, DataSource dataSource,
                                  JSONB jsonb, SqlNames sqlNames) {
        this.vectorDataAdapter = vectorDataAdapter;
        this.embeddingModel = embeddingModel;
        this.dataSource = dataSource;
        this.jsonb = jsonb;
        this.vectorSearchSql = VECTOR_SEARCH_SQL_TEMPLATE.formatted(
                sqlNames.table("CB_POLICY_CHUNK"), sqlNames.table("CB_POLICY_DOCUMENT"));
        this.findByDocumentIdSql = FIND_BY_DOCUMENT_ID_SQL_TEMPLATE.formatted(
                sqlNames.table("CB_POLICY_DOCUMENT"));
    }

    public List<RetrievalResult> search(RetrievalRequest request, int limit) {
        Objects.requireNonNull(request, "request must not be null");
        if (limit < 1) {
            throw new IllegalArgumentException("limit must be greater than zero");
        }
        float[] embedding = request.embedding();
        if (embedding == null || embedding.length == 0) {
            embedding = embeddingModel.embed(request.content());
        }
        PolicyRole role = request.policyRole() == null ? PolicyRole.LOAN_OFFICER : request.policyRole();
        AiUse aiUse = request.aiUse() == null ? AiUse.RETRIEVAL : request.aiUse();

        try (Connection connection = dataSource.getConnection();
             PreparedStatement statement = connection.prepareStatement(vectorSearchSql)) {
            VECTOR vector = vectorDataAdapter.toVECTOR(embedding, false);
            statement.setObject(1, vector);
            statement.setInt(2, role.ordinal() + 1);
            statement.setString(3, aiUse.toString());
            statement.setInt(4, limit);
            try (ResultSet results = statement.executeQuery()) {
                List<RetrievalResult> matches = new ArrayList<>();
                while (results.next()) {
                    matches.add(mapResult(results));
                }
                return matches;
            }
        } catch (SQLException e) {
            throw new RuntimeException("Policy vector search failed", e);
        }
    }

    public Optional<PolicyDocument> findById(String policyDocumentId) {
        Objects.requireNonNull(policyDocumentId, "policyDocumentId must not be null");

        try (Connection connection = dataSource.getConnection();
             PreparedStatement statement = connection.prepareStatement(findByDocumentIdSql)) {
            statement.setObject(1, policyDocumentId);
            try (ResultSet results = statement.executeQuery()) {
                if (results.next()) {
                    return Optional.of(mapDocument(results));
                }
                return Optional.empty();
            }
        } catch (SQLException e) {
            throw new RuntimeException(e);
        }
    }

    private PolicyDocument mapDocument(ResultSet rs) throws SQLException {
        return PolicyDocument.of(
                rs.getLong("policy_document_sk"), rs.getString("policy_document_id"),
                rs.getString("policy_code"), rs.getString("policy_title"), rs.getString("policy_version"),
                rs.getString("source_path"), rs.getDate("effective_date"),
                ReviewStatus.valueOf(rs.getString("review_status")),
                PolicyRole.valueOf(rs.getString("owner_role")),
                DataClassification.fromValue(rs.getString("data_classification")),
                rs.getBytes("metadata_json"),
                toOffsetDateTime(rs.getTimestamp("document_created_at"))
        );
    }

    private RetrievalResult mapResult(ResultSet rs) throws SQLException {
        PolicyDocument document = mapDocument(rs);
        PolicyChunk chunk = PolicyChunk.of(
                rs.getLong("policy_chunk_sk"), rs.getLong("policy_document_sk"),
                document.documentId(), rs.getString("chunk_id"), rs.getString("section_ref"),
                rs.getString("heading"), rs.getInt("chunk_ordinal"), rs.getString("chunk_text"),
                toMap(rs.getObject("chunk_metadata", JsonParser.class)),
                PolicyRole.valueOf(rs.getString("min_role")),
                rs.getString("access_label"), AiUse.fromValue(rs.getString("ai_use")), null,
                toOffsetDateTime(rs.getTimestamp("chunk_created_at")));
        return new RetrievalResult(rs.getDouble("vector_score"), chunk, document);
    }

    private OffsetDateTime toOffsetDateTime(Timestamp timestamp) {
        return timestamp == null ? null : timestamp.toInstant().atOffset(java.time.ZoneOffset.UTC);
    }

    private Map<String, Object> toMap(JsonParser jsonParser) {
        return jsonb.fromOSON(jsonParser, Map.class);
    }
}
