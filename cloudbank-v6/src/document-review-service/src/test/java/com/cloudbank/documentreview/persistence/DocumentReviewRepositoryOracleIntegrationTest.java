// Copyright (c) 2026, Oracle and/or its affiliates.
//
// Licensed under the Universal Permissive License v 1.0 as shown at
// https://oss.oracle.com/licenses/upl/.
//

package com.cloudbank.documentreview.persistence;

import static org.assertj.core.api.Assertions.assertThat;

import com.cloudbank.documentreview.domain.ReviewModels.DocumentCounts;
import com.cloudbank.documentreview.domain.ReviewModels.ExtractedFacts;
import com.cloudbank.documentreview.domain.ReviewModels.ExtractionDocument;
import com.cloudbank.documentreview.domain.ReviewModels.ExtractionReviewInput;
import com.cloudbank.documentreview.domain.ReviewModels.ReviewDisposition;
import com.cloudbank.documentreview.domain.ReviewModels.ReviewIssue;
import com.cloudbank.documentreview.domain.ReviewModels.ReviewResult;
import com.cloudbank.documentreview.domain.ReviewModels.ReviewStatus;
import com.cloudbank.documentreview.domain.ReviewModels.RoutingEffect;
import java.math.BigDecimal;
import java.sql.Connection;
import java.sql.Statement;
import java.util.List;
import javax.sql.DataSource;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.oracle.OracleContainer;
import org.testcontainers.utility.DockerImageName;
import tools.jackson.databind.ObjectMapper;

@Testcontainers(disabledWithoutDocker = true)
class DocumentReviewRepositoryOracleIntegrationTest {
    @Container
    private static final OracleContainer ORACLE = new OracleContainer(
            DockerImageName.parse("gvenzl/oracle-free:23.26.2-slim-faststart")).withPassword("OracleTestPassword1");

    private static JdbcClient jdbc;
    private static DataSource dataSource;
    private static DocumentReviewRepository repository;

    @BeforeAll
    static void createSchema() throws Exception {
        dataSource = new DriverManagerDataSource(ORACLE.getJdbcUrl(), "system", ORACLE.getPassword());
        jdbc = JdbcClient.create(dataSource);
        repository = new DocumentReviewRepository(jdbc, new SqlNames("SYSTEM"), new ObjectMapper());
        try (Connection connection = dataSource.getConnection();
                Statement statement = connection.createStatement()) {
            statement.execute(
                    "CREATE TABLE cb_loan_application (application_sk NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY, application_id VARCHAR2(40) UNIQUE NOT NULL)");
            statement.execute(
                    "CREATE TABLE cb_document (document_sk NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY, application_sk NUMBER NOT NULL, document_id VARCHAR2(60) NOT NULL, CONSTRAINT cb_doc_app_fk FOREIGN KEY (application_sk) REFERENCES cb_loan_application(application_sk))");
            statement.execute(
                    "CREATE TABLE cb_document_review (application_sk NUMBER NOT NULL, review_id VARCHAR2(40) PRIMARY KEY, workflow_id VARCHAR2(100) NOT NULL, task_reference VARCHAR2(120) NOT NULL, idempotency_key_hash VARCHAR2(64) UNIQUE NOT NULL, request_hash VARCHAR2(64) NOT NULL, input_fingerprint VARCHAR2(64) NOT NULL, profile_version VARCHAR2(80) NOT NULL, review_status VARCHAR2(20) NOT NULL, disposition VARCHAR2(30) NOT NULL, result_payload CLOB NOT NULL, trace_id VARCHAR2(32) NOT NULL, created_at TIMESTAMP DEFAULT SYSTIMESTAMP, updated_at TIMESTAMP DEFAULT SYSTIMESTAMP, completed_at TIMESTAMP)");
            statement.execute(
                    "CREATE TABLE cb_document_issue (application_sk NUMBER NOT NULL, document_sk NUMBER, issue_code VARCHAR2(120) NOT NULL, issue_severity VARCHAR2(40) NOT NULL, routing_effect VARCHAR2(60) NOT NULL CHECK (routing_effect IN ('BLOCKED','MANUAL_REVIEW','RETRY')), policy_hint VARCHAR2(80), issue_detail VARCHAR2(1000), detected_at TIMESTAMP DEFAULT SYSTIMESTAMP, CONSTRAINT cb_issue_uk UNIQUE (application_sk, issue_code))");
            statement.execute(
                    "CREATE TABLE cb_document_fact (application_sk NUMBER NOT NULL, document_sk NUMBER, fact_name VARCHAR2(120) NOT NULL, fact_value_text VARCHAR2(4000), fact_value_number NUMBER, fact_value_date DATE, source_field_path VARCHAR2(200), CONSTRAINT cb_fact_uk UNIQUE (application_sk, fact_name))");
            statement.execute(
                    "CREATE TABLE cb_income_evidence (application_sk NUMBER PRIMARY KEY, document_sk NUMBER, stated_gross_monthly_income NUMBER(12,2) NOT NULL, pay_document_monthly_income NUMBER(12,2), verified_gross_monthly_income NUMBER(12,2) NOT NULL, income_consistency_result VARCHAR2(80) NOT NULL CHECK (income_consistency_result IN ('CONSISTENT_WITHIN_10_PERCENT','INCONSISTENT_OVER_10_PERCENT')), extraction_confidence VARCHAR2(40) NOT NULL, document_validation_status VARCHAR2(40) NOT NULL, evidence_timestamp TIMESTAMP)");
        }
    }

    @BeforeEach
    void resetRows() {
        jdbc.sql("DELETE FROM SYSTEM.CB_INCOME_EVIDENCE").update();
        jdbc.sql("DELETE FROM SYSTEM.CB_DOCUMENT_FACT").update();
        jdbc.sql("DELETE FROM SYSTEM.CB_DOCUMENT_ISSUE").update();
        jdbc.sql("DELETE FROM SYSTEM.CB_DOCUMENT_REVIEW").update();
        jdbc.sql("DELETE FROM SYSTEM.CB_DOCUMENT").update();
        jdbc.sql("DELETE FROM SYSTEM.CB_LOAN_APPLICATION").update();
        jdbc.sql("INSERT INTO SYSTEM.CB_LOAN_APPLICATION (application_id) VALUES ('APP-ONE')").update();
        jdbc.sql(
                "INSERT INTO SYSTEM.CB_DOCUMENT (application_sk, document_id) SELECT application_sk, 'DOC-ONE' FROM SYSTEM.CB_LOAN_APPLICATION WHERE application_id = 'APP-ONE'")
                .update();
    }

    @Test
    void persistsBlockedAsADocumentProcessingOutcomeAndUsesTheTenPercentIncomeLabel() {
        ReviewResult result = result();
        ExtractionReviewInput input = new ExtractionReviewInput("APP-ONE",
                List.of(new ExtractionDocument("DOC-ONE", "LOAN_APPLICATION", "EXT-ONE", "SUCCEEDED", "DOCUMENT_INGEST",
                        "local_pdf_text", new BigDecimal("0.99"), new ExtractedFacts("APP-ONE", "Employer",
                                new BigDecimal("100"), new BigDecimal("100"), new BigDecimal("89"), "MATCH",
                                null, null, null),
                        List.of(), List.of())));

        repository.persist(result, "a".repeat(64), "b".repeat(64), "c".repeat(64));
        repository.persistProjections(result, input);

        assertThat(jdbc
                .sql("SELECT routing_effect FROM SYSTEM.CB_DOCUMENT_ISSUE WHERE issue_code = 'APPLICATION_ID_MISMATCH'")
                .query(String.class).single()).isEqualTo("BLOCKED");
        assertThat(jdbc.sql("SELECT income_consistency_result FROM SYSTEM.CB_INCOME_EVIDENCE").query(String.class)
                .single()).isEqualTo("INCONSISTENT_OVER_10_PERCENT");
        assertThat(repository.findByReviewId(result.reviewId())).contains(result);
        assertThat(jdbc.sql("SELECT DISTINCT source_field_path FROM SYSTEM.CB_DOCUMENT_FACT")
                .query(String.class).list()).containsExactly(result.profileVersion());
    }

    @Test
    void performsRepositoryWorkWithoutDatabaseSessionIdentity() {
        String value = jdbc.sql("SELECT 'ready' FROM dual").query(String.class).single();
        assertThat(value).isEqualTo("ready");
    }

    private static ReviewResult result() {
        return new ReviewResult("DREV-00000000000000000000000000000000", "APP-ONE", "WF-ONE", "review_documents",
                ReviewStatus.ACK_PENDING, ReviewDisposition.BLOCKED, "document-review-v1",
                new DocumentCounts(1, 0, 0, 0, 1),
                List.of(new ReviewIssue("APPLICATION_ID_MISMATCH",
                        com.cloudbank.documentreview.domain.ReviewModels.IssueSeverity.BLOCKING, RoutingEffect.BLOCKED,
                        List.of("DOC-ONE"), "Document application ID differs."),
                        new ReviewIssue("INCOME_DIFFERENCE_OVER_10_PERCENT",
                                com.cloudbank.documentreview.domain.ReviewModels.IssueSeverity.REVIEW,
                                RoutingEffect.MANUAL_REVIEW, List.of("DOC-ONE"), "Income evidence differs.")),
                "0123456789abcdef0123456789abcdef", List.of());
    }
}
