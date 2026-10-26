// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.policyloader;

import oracle.sql.VECTOR;
import tools.jackson.core.JacksonException;
import tools.jackson.databind.ObjectMapper;
import org.springframework.stereotype.Repository;

import javax.sql.DataSource;
import java.sql.Connection;
import java.sql.Date;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Optional;

import static com.cloudbank.policyloader.PolicyCorpusModels.EmbeddedCorpus;
import static com.cloudbank.policyloader.PolicyCorpusModels.EmbeddedDocument;
import static com.cloudbank.policyloader.PolicyCorpusModels.ExistingLoad;
import static com.cloudbank.policyloader.PolicyCorpusModels.PolicyChunk;
import static com.cloudbank.policyloader.PolicyCorpusModels.PolicyDocument;

@Repository
class PolicyLoaderRepository {
    private final DataSource dataSource;
    private final ObjectMapper json;
    private final String loadTable;
    private final String documentTable;
    private final String chunkTable;

    PolicyLoaderRepository(DataSource dataSource, ObjectMapper json, PolicyLoaderProperties properties) {
        this.dataSource = dataSource;
        this.json = json;
        String schema = properties.getSchema().toUpperCase(java.util.Locale.ROOT);
        if (!schema.matches("[A-Z][A-Z0-9_$#]{0,127}")) {
            throw new IllegalArgumentException("policy loader schema is invalid");
        }
        loadTable = schema + ".CB_POLICY_CORPUS_LOAD";
        documentTable = schema + ".CB_POLICY_DOCUMENT";
        chunkTable = schema + ".CB_POLICY_CHUNK";
    }

    Optional<ExistingLoad> findLoad(String corpusId) {
        String sql = """
                SELECT corpus_id, corpus_version, corpus_sha256, embedding_model,
                       embedding_dimensions, document_count, chunk_count
                FROM %s WHERE corpus_id = ?
                """.formatted(loadTable);
        try (Connection connection = dataSource.getConnection();
             PreparedStatement statement = connection.prepareStatement(sql)) {
            statement.setString(1, corpusId);
            try (ResultSet result = statement.executeQuery()) {
                if (!result.next()) {
                    return Optional.empty();
                }
                return Optional.of(new ExistingLoad(result.getString("corpus_id"),
                        result.getString("corpus_version"), result.getString("corpus_sha256"),
                        result.getString("embedding_model"), result.getInt("embedding_dimensions"),
                        result.getInt("document_count"), result.getInt("chunk_count")));
            }
        }
        catch (SQLException exception) {
            throw new IllegalStateException("could not inspect the policy corpus load state", exception);
        }
    }

    void verifyExisting(ExistingLoad load) {
        Counts counts = counts();
        if (counts.documents() != load.documentCount() || counts.chunks() != load.chunkCount()
                || counts.missingEmbeddings() != 0) {
            throw new IllegalStateException("stored policy corpus counts do not match the recorded load");
        }
    }

    void requireEmptyCorpusTables() {
        Counts counts = counts();
        if (counts.documents() != 0 || counts.chunks() != 0) {
            throw new IllegalStateException("policy tables contain data without a matching corpus load record");
        }
    }

    void insert(EmbeddedCorpus embedded) {
        try (Connection connection = dataSource.getConnection()) {
            connection.setAutoCommit(false);
            try {
                requireEmptyCorpusTables(connection);
                requireMissingLoad(connection, embedded.corpus().corpusId());
                for (EmbeddedDocument document : embedded.documents()) {
                    insertDocument(connection, embedded, document);
                }
                insertLoad(connection, embedded);
                Counts counts = counts(connection);
                if (counts.documents() != embedded.corpus().documents().size()
                        || counts.chunks() != embedded.corpus().chunkCount()
                        || counts.missingEmbeddings() != 0) {
                    throw new SQLException("inserted policy corpus failed its count verification");
                }
                connection.commit();
            }
            catch (SQLException | RuntimeException exception) {
                connection.rollback();
                throw exception;
            }
        }
        catch (SQLException exception) {
            throw new IllegalStateException("policy corpus could not be persisted", exception);
        }
    }

    private void insertDocument(Connection connection, EmbeddedCorpus corpus, EmbeddedDocument embedded)
            throws SQLException {
        PolicyDocument document = embedded.document();
        String sql = """
                INSERT INTO %s
                    (policy_document_id, policy_code, policy_title, policy_version,
                     source_path, effective_date, review_status, owner_role,
                     data_classification, metadata_json)
                VALUES (?, ?, ?, ?, ?, ?, 'APPROVED', 'UNDERWRITER', 'restricted_policy', ?)
                """.formatted(documentTable);
        long documentSk;
        try (PreparedStatement statement = connection.prepareStatement(sql)) {
            statement.setString(1, document.documentId());
            statement.setString(2, document.policyCode());
            statement.setString(3, document.title());
            statement.setString(4, document.version());
            statement.setString(5, document.sourcePath());
            statement.setDate(6, Date.valueOf(document.effectiveDate()));
            statement.setString(7, documentMetadata(corpus, document));
            statement.executeUpdate();
        }
        documentSk = findDocumentKey(connection, document.documentId());

        String chunkSql = """
                INSERT INTO %s
                    (policy_document_sk, chunk_id, section_ref, heading, chunk_ordinal,
                     chunk_text, chunk_metadata, min_role, access_label, ai_use, embedding)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'policy', 'retrieval', ?)
                """.formatted(chunkTable);
        try (PreparedStatement statement = connection.prepareStatement(chunkSql)) {
            for (int index = 0; index < document.chunks().size(); index++) {
                PolicyChunk chunk = document.chunks().get(index);
                statement.setLong(1, documentSk);
                statement.setString(2, chunk.chunkId());
                statement.setString(3, chunk.sectionRef());
                statement.setString(4, chunk.heading());
                statement.setInt(5, chunk.ordinal());
                statement.setString(6, chunk.text());
                statement.setString(7, chunkMetadata(corpus, document, chunk));
                statement.setString(8, chunk.minRole());
                statement.setObject(9, VECTOR.ofFloat32Values(embedded.embeddings().get(index)));
                statement.addBatch();
            }
            statement.executeBatch();
        }
    }

    private long findDocumentKey(Connection connection, String documentId) throws SQLException {
        String sql = "SELECT policy_document_sk FROM " + documentTable + " WHERE policy_document_id = ?";
        try (PreparedStatement statement = connection.prepareStatement(sql)) {
            statement.setString(1, documentId);
            try (ResultSet result = statement.executeQuery()) {
                if (!result.next()) {
                    throw new SQLException("inserted policy document could not be read back");
                }
                return result.getLong(1);
            }
        }
    }

    private void insertLoad(Connection connection, EmbeddedCorpus corpus) throws SQLException {
        String sql = """
                INSERT INTO %s
                    (corpus_id, corpus_version, corpus_sha256, embedding_provider,
                     embedding_model, embedding_region, embedding_dimensions,
                     document_count, chunk_count)
                VALUES (?, ?, ?, 'OCI_GENAI', ?, ?, ?, ?, ?)
                """.formatted(loadTable);
        try (PreparedStatement statement = connection.prepareStatement(sql)) {
            statement.setString(1, corpus.corpus().corpusId());
            statement.setString(2, corpus.corpus().version());
            statement.setString(3, corpus.corpus().digest());
            statement.setString(4, corpus.model());
            statement.setString(5, corpus.region());
            statement.setInt(6, corpus.dimensions());
            statement.setInt(7, corpus.corpus().documents().size());
            statement.setInt(8, corpus.corpus().chunkCount());
            statement.executeUpdate();
        }
    }

    private String documentMetadata(EmbeddedCorpus corpus, PolicyDocument document) {
        Map<String, Object> values = new LinkedHashMap<>();
        values.put("corpus_id", corpus.corpus().corpusId());
        values.put("corpus_sha256", corpus.corpus().digest());
        values.put("policy_domain", document.domain());
        values.put("embedding_provider", "OCI_GENAI");
        values.put("embedding_model", corpus.model());
        values.put("embedding_dimensions", corpus.dimensions());
        return json(values);
    }

    private String chunkMetadata(EmbeddedCorpus corpus, PolicyDocument document, PolicyChunk chunk) {
        Map<String, Object> values = new LinkedHashMap<>();
        values.put("corpus_id", corpus.corpus().corpusId());
        values.put("policy_id", document.policyCode());
        values.put("policy_version", document.version());
        values.put("policy_domain", document.domain());
        values.put("section_id", chunk.sectionRef());
        values.put("role_filter_required", true);
        values.put("embedding_model", corpus.model());
        values.put("embedding_dimensions", corpus.dimensions());
        return json(values);
    }

    private String json(Map<String, Object> values) {
        try {
            return json.writeValueAsString(values);
        }
        catch (JacksonException exception) {
            throw new IllegalStateException("policy metadata could not be serialized", exception);
        }
    }

    private Counts counts() {
        try (Connection connection = dataSource.getConnection()) {
            return counts(connection);
        }
        catch (SQLException exception) {
            throw new IllegalStateException("could not inspect policy corpus tables", exception);
        }
    }

    private Counts counts(Connection connection) throws SQLException {
        return new Counts(count(connection, "SELECT COUNT(*) FROM " + documentTable),
                count(connection, "SELECT COUNT(*) FROM " + chunkTable),
                count(connection, "SELECT COUNT(*) FROM " + chunkTable + " WHERE embedding IS NULL"));
    }

    private static int count(Connection connection, String sql) throws SQLException {
        try (PreparedStatement statement = connection.prepareStatement(sql);
             ResultSet result = statement.executeQuery()) {
            result.next();
            return result.getInt(1);
        }
    }

    private void requireEmptyCorpusTables(Connection connection) throws SQLException {
        Counts counts = counts(connection);
        if (counts.documents() != 0 || counts.chunks() != 0) {
            throw new SQLException("policy tables are not empty");
        }
    }

    private void requireMissingLoad(Connection connection, String corpusId) throws SQLException {
        try (PreparedStatement statement = connection.prepareStatement(
                "SELECT COUNT(*) FROM " + loadTable + " WHERE corpus_id = ?")) {
            statement.setString(1, corpusId);
            try (ResultSet result = statement.executeQuery()) {
                result.next();
                if (result.getInt(1) != 0) {
                    throw new SQLException("policy corpus load record already exists");
                }
            }
        }
    }

    private record Counts(int documents, int chunks, int missingEmbeddings) {
    }
}
