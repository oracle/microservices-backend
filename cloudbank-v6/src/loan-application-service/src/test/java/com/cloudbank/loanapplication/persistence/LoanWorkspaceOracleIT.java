// Copyright (c) 2026, Oracle and/or its affiliates.
package com.cloudbank.loanapplication.persistence;

import static org.assertj.core.api.Assertions.assertThat;

import java.nio.charset.StandardCharsets;
import java.sql.DriverManager;
import java.util.Locale;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.oracle.OracleContainer;

/** Verifies Oracle joins, typed nullable metadata and bounded BLOB retrieval in an isolated schema. */
@Testcontainers(disabledWithoutDocker = true)
class LoanWorkspaceOracleIT {
    @Container
    static final OracleContainer ORACLE = new OracleContainer("gvenzl/oracle-free:latest");
    static final byte[] PDF = "%PDF-1.7\nSynthetic preview integration fixture".getBytes(StandardCharsets.UTF_8);

    @BeforeAll
    static void schema() throws Exception {
        try (var connection = DriverManager.getConnection(ORACLE.getJdbcUrl(), ORACLE.getUsername(), ORACLE.getPassword());
                var statement = connection.createStatement()) {
            statement.execute("CREATE TABLE CB_APPLICANT (applicant_sk NUMBER PRIMARY KEY, display_name VARCHAR2(200), phone_token VARCHAR2(80), email_token VARCHAR2(160), age_band VARCHAR2(20))");
            statement.execute("CREATE TABLE CB_LOAN_APPLICATION (application_sk NUMBER PRIMARY KEY, applicant_sk NUMBER, requested_amount NUMBER(12,2), requested_term_months NUMBER, purpose_code VARCHAR2(40), policy_version VARCHAR2(20))");
            statement.execute("CREATE TABLE CB_ADDRESS (address_sk NUMBER PRIMARY KEY, applicant_sk NUMBER, address_line VARCHAR2(300), locality VARCHAR2(120), jurisdiction_code VARCHAR2(20), address_token VARCHAR2(80), country_code VARCHAR2(2), postal_code VARCHAR2(20))");
            statement.execute("CREATE TABLE CB_DOCUMENT (document_sk NUMBER PRIMARY KEY, application_sk NUMBER, document_id VARCHAR2(60), document_type VARCHAR2(60), file_name VARCHAR2(260), document_status VARCHAR2(40), required_flag VARCHAR2(5), received_at TIMESTAMP)");
            statement.execute("CREATE TABLE CB_DOCUMENT_CONTENT (document_sk NUMBER PRIMARY KEY, content_sha256 VARCHAR2(64), content_length_bytes NUMBER, media_type VARCHAR2(120), upload_idempotency_key VARCHAR2(200), file_content BLOB)");
            statement.execute("INSERT INTO CB_APPLICANT VALUES (1, 'Synthetic Applicant', 'PHONE-SYNTH', 'EMAIL-SYNTH', '25-34')");
            statement.execute("INSERT INTO CB_LOAN_APPLICATION VALUES (10, 1, 5000, 24, 'OTHER_CONSUMER_PURPOSE', '2026.0')");
            statement.execute("INSERT INTO CB_ADDRESS VALUES (1, 1, '10 Synthetic Avenue', 'Demo City', 'US-CA', 'ADDR-SYNTH', 'US', '00000')");
            statement.execute("INSERT INTO CB_DOCUMENT VALUES (100, 10, 'DOC-stored', 'LOAN_APPLICATION', 'loan.pdf', 'VALIDATED', 'true', SYSTIMESTAMP)");
            statement.execute("INSERT INTO CB_DOCUMENT VALUES (101, 10, 'DOC-missing', 'PAY_STATEMENT', 'pay.pdf', 'EXPECTED', 'true', SYSTIMESTAMP)");
            try (var insert = connection.prepareStatement("INSERT INTO CB_DOCUMENT_CONTENT VALUES (100, ?, ?, 'application/pdf', 'synthetic-key', ?)")) {
                insert.setString(1, "a".repeat(64)); insert.setLong(2, PDF.length); insert.setBytes(3, PDF); insert.executeUpdate();
            }
        }
    }

    @Test
    void readsOverviewAndTrueContentAvailabilityWithoutInferringItFromStatus() {
        var repository = repository();
        var overview = repository.findOverview(10).orElseThrow();
        assertThat(overview.applicant().displayName()).isEqualTo("Synthetic Applicant");
        assertThat(overview.applicant().address().countryCode()).isEqualTo("US");
        assertThat(overview.loan().policyVersion()).isEqualTo("2026.0");
        var documents = repository.findWorkspaceDocuments(10);
        assertThat(documents).hasSize(2);
        assertThat(documents.stream().filter(d -> d.documentId().equals("DOC-stored")).findFirst().orElseThrow().contentAvailable()).isTrue();
        var missing = documents.stream().filter(d -> d.documentId().equals("DOC-missing")).findFirst().orElseThrow();
        assertThat(missing.contentAvailable()).isFalse();
        assertThat(missing.contentLengthBytes()).isNull();
        assertThat(repository.findDocumentPreviewContent(100).orElseThrow().content()).isEqualTo(PDF);
        assertThat(repository.findDocumentPreviewContent(101)).isEmpty();
    }

    private LoanApplicationRepository repository() {
        return new LoanApplicationRepository(JdbcClient.create(new DriverManagerDataSource(ORACLE.getJdbcUrl(),
                ORACLE.getUsername(), ORACLE.getPassword())), new SqlNames(ORACLE.getUsername().toUpperCase(Locale.ROOT)));
    }
}
