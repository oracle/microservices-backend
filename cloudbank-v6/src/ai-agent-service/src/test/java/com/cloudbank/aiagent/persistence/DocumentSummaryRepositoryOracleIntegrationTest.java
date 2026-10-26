// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.

package com.cloudbank.aiagent.persistence;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.cloudbank.aiagent.api.AiAgentApiModels.DocumentEvidenceSummaryResponse;
import com.cloudbank.aiagent.api.AiAgentApiModels.MaterialDocumentIssue;
import com.cloudbank.aiagent.api.AiAgentApiModels.SourceReference;
import com.cloudbank.aiagent.service.ReviewAssistanceException;
import java.nio.file.Path;
import java.sql.Connection;
import java.util.List;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.springframework.core.io.FileSystemResource;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.jdbc.datasource.init.ScriptUtils;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.oracle.OracleContainer;
import org.testcontainers.utility.DockerImageName;
import tools.jackson.databind.ObjectMapper;

@Testcontainers(disabledWithoutDocker = true)
class DocumentSummaryRepositoryOracleIntegrationTest {
    private static final String SCHEMA_OWNER = "CLOUDBANK";

    @Container
    private static final OracleContainer ORACLE = new OracleContainer(
            DockerImageName.parse("gvenzl/oracle-free:23.26.2-slim-faststart")).withPassword("OracleTestPassword1");
    private static DriverManagerDataSource admin;
    private static DriverManagerDataSource owner;
    private static DocumentSummaryRepository repository;

    @BeforeAll
    static void migrateAndProvisionRuntimeAccount() throws Exception {
        admin = new DriverManagerDataSource(ORACLE.getJdbcUrl(), "system", ORACLE.getPassword());
        // Native JSON columns require ASSM storage; SYSTEM's default tablespace does not qualify.
        try (Connection connection = admin.getConnection(); var statement = connection.createStatement()) {
            statement.execute("CREATE USER " + SCHEMA_OWNER + " IDENTIFIED BY " + ORACLE.getPassword()
                    + " DEFAULT TABLESPACE USERS QUOTA UNLIMITED ON USERS");
            statement.execute("GRANT CREATE SESSION, CREATE TABLE TO " + SCHEMA_OWNER);
        }
        owner = new DriverManagerDataSource(ORACLE.getJdbcUrl(), SCHEMA_OWNER, ORACLE.getPassword());
        Path schema = Path.of("../schema");
        if (!schema.toFile().exists()) {
            schema = Path.of("src/schema");
        }
        try (Connection connection = owner.getConnection()) {
            ScriptUtils.executeSqlScript(connection, new FileSystemResource(schema.resolve("changes/029-ai-document-summary.sql")));
        }
        // Role and runtime-account provisioning stays on the privileged connection.
        try (Connection connection = admin.getConnection()) {
            try (var statement = connection.createStatement()) {
                statement.execute("ALTER SESSION SET CURRENT_SCHEMA = " + SCHEMA_OWNER);
            }
            ScriptUtils.executeSqlScript(connection, new org.springframework.core.io.support.EncodedResource(
                    new FileSystemResource(schema.resolve("changes/030-ai-agent-runtime-role.sql"))), false, false,
                    "--", "/", "/*", "*/");
            try (var statement = connection.createStatement()) {
                statement.execute("CREATE USER CB_AI_AGENT_APP IDENTIFIED BY OracleTestPassword2");
                statement.execute("GRANT CB_AI_AGENT_RUNTIME TO CB_AI_AGENT_APP");
            }
        }
        var runtime = new DriverManagerDataSource(ORACLE.getJdbcUrl(), "CB_AI_AGENT_APP", "OracleTestPassword2");
        repository = new DocumentSummaryRepository(JdbcClient.create(runtime), new ObjectMapper(), SCHEMA_OWNER);
    }

    @Test
    void persistsValidatedJsonAndReplaysTheDurableWinner() {
        String key = "1".repeat(64);
        String request = "2".repeat(64);
        var first = response("Validated evidence needs human verification.");
        assertThat(repository.save(key, request, first)).isEqualTo(first);
        assertThat(repository.find(key).orElseThrow().replay(request)).isEqualTo(first);
        assertThat(repository.save(key, request, response("A concurrent alternative summary."))).isEqualTo(first);
        assertThatThrownBy(() -> repository.save(key, "3".repeat(64), first))
                .isInstanceOf(ReviewAssistanceException.class)
                .extracting(error -> ((ReviewAssistanceException) error).code()).isEqualTo("IDEMPOTENCY_CONFLICT");
    }

    @Test
    void grantsOnlyImmutableResultAccessAndKeepsAnnotationsQueryable() {
        var jdbc = JdbcClient.create(admin);
        assertThat(jdbc.sql("SELECT COUNT(*) FROM ROLE_TAB_PRIVS WHERE ROLE = 'CB_AI_AGENT_RUNTIME' "
                        + "AND OWNER = '" + SCHEMA_OWNER + "' AND TABLE_NAME = 'CB_AI_DOCUMENT_SUMMARY' "
                        + "AND PRIVILEGE IN ('SELECT','INSERT')")
                .query(Integer.class).single()).isEqualTo(2);
        assertThat(jdbc.sql("SELECT COUNT(*) FROM ROLE_TAB_PRIVS WHERE ROLE = 'CB_AI_AGENT_RUNTIME' "
                        + "AND (TABLE_NAME <> 'CB_AI_DOCUMENT_SUMMARY' OR PRIVILEGE NOT IN ('SELECT','INSERT'))")
                .query(Integer.class).single()).isZero();
        var ownerJdbc = JdbcClient.create(owner);
        assertThat(ownerJdbc.sql("SELECT tablespace_name FROM USER_TABLES WHERE TABLE_NAME = 'CB_AI_DOCUMENT_SUMMARY'")
                .query(String.class).single()).isEqualTo("USERS");
        assertThat(ownerJdbc.sql("SELECT COUNT(*) FROM USER_ANNOTATIONS_USAGE WHERE OBJECT_NAME = 'CB_AI_DOCUMENT_SUMMARY'")
                .query(Integer.class).single()).isGreaterThan(0);
    }

    private static DocumentEvidenceSummaryResponse response(String summary) {
        return new DocumentEvidenceSummaryResponse("AISUM-" + "0".repeat(32), "COMPLETED", "oci-genai", "test-model",
                "APP-ONE", "WF-ONE", "ai_document_evidence_summary", "0123456789abcdef0123456789abcdef",
                "DREV-" + "0".repeat(32), "UNDERWRITER", summary,
                List.of(new MaterialDocumentIssue("EMPLOYER_INCONSISTENCY", "REVIEW", "MANUAL_REVIEW", List.of("DOC-ONE"))),
                List.of(), List.of(new SourceReference("DOCUMENT", "DOC-ONE")), "PASSED", List.of());
    }
}
