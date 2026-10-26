// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.loanapplication.persistence;

import static com.cloudbank.loanapplication.persistence.LoanRecords.ApplicationRow;
import static com.cloudbank.loanapplication.api.ApplicationApiModels.AddressRequest;
import static com.cloudbank.loanapplication.api.ApplicationApiModels.ApplicantRequest;
import static com.cloudbank.loanapplication.api.ApplicationApiModels.CreateApplicationRequest;
import static com.cloudbank.loanapplication.api.ApplicationApiModels.LoanRequest;
import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Answers.RETURNS_SELF;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.cloudbank.loanapplication.api.ApplicationApiModels.DocumentRequest;
import com.cloudbank.loanapplication.domain.DocumentStatus;
import com.cloudbank.loanapplication.domain.WorkflowStartMode;
import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.jdbc.core.simple.JdbcClient;

class LoanApplicationRepositoryTest {

    @Test
    @SuppressWarnings("unchecked")
    void bindsApplicationIdInsteadOfAddingItToTheSqlText() {
        JdbcClient jdbc = mock(JdbcClient.class);
        JdbcClient.StatementSpec statement = mock(JdbcClient.StatementSpec.class, RETURNS_SELF);
        JdbcClient.MappedQuerySpec<ApplicationRow> query = mock(JdbcClient.MappedQuerySpec.class);
        when(jdbc.sql(anyString())).thenReturn(statement);
        when(statement.query(any(org.springframework.jdbc.core.RowMapper.class))).thenReturn(query);
        when(query.optional()).thenReturn(Optional.empty());
        LoanApplicationRepository repository = new LoanApplicationRepository(jdbc, new SqlNames("CLOUDBANK"));
        String suppliedApplicationId = "APP-' OR 1=1--";

        repository.findByApplicationId(suppliedApplicationId);

        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);
        verify(jdbc).sql(sql.capture());
        assertThat(sql.getValue())
                .contains("FROM CLOUDBANK.CB_LOAN_APPLICATION")
                .contains("application_id = :applicationId")
                .doesNotContain(suppliedApplicationId);
        verify(statement).param("applicationId", suppliedApplicationId);
    }

    @Test
    void writesDocumentsWithoutMerge() {
        JdbcClient jdbc = mock(JdbcClient.class);
        JdbcClient.StatementSpec update = mock(JdbcClient.StatementSpec.class, RETURNS_SELF);
        JdbcClient.StatementSpec insert = mock(JdbcClient.StatementSpec.class, RETURNS_SELF);
        when(jdbc.sql(anyString())).thenReturn(update, insert);
        when(update.update()).thenReturn(0);
        when(insert.update()).thenReturn(1);
        LoanApplicationRepository repository = new LoanApplicationRepository(jdbc, new SqlNames("CLOUDBANK"));
        DocumentRequest document = new DocumentRequest("INCOME_VALIDATION", "income.pdf",
                DocumentStatus.EXPECTED, true, null, null, "application/pdf", null);

        repository.insertDocument(42L, "DOC-test", document);

        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);
        verify(jdbc, times(2)).sql(sql.capture());
        List<String> statements = sql.getAllValues();
        assertThat(statements.get(0).stripLeading()).startsWith("UPDATE CLOUDBANK.CB_DOCUMENT");
        assertThat(statements.get(1).stripLeading()).startsWith("INSERT INTO CLOUDBANK.CB_DOCUMENT");
        assertThat(statements).allSatisfy(statement -> assertThat(statement).doesNotContainIgnoringCase("MERGE"));
    }

    @Test
    void writesCoreAddressWithPendingJurisdictionReview() {
        JdbcClient jdbc = mock(JdbcClient.class);
        JdbcClient.StatementSpec insert = mock(JdbcClient.StatementSpec.class, RETURNS_SELF);
        when(jdbc.sql(anyString())).thenReturn(insert);
        when(insert.update()).thenReturn(1);
        LoanApplicationRepository repository = new LoanApplicationRepository(jdbc, new SqlNames("CLOUDBANK"));
        CreateApplicationRequest request = new CreateApplicationRequest("scenario", "Scenario",
                new ApplicantRequest("Synthetic Applicant", "phone-token", "email-token", "35-44",
                        new AddressRequest("Via del Corso 1", "Roma", "IT-ROMA", "address-token", "IT", "00186")),
                new LoanRequest(new BigDecimal("5000.00"), 24, "PERSONAL", "2026.0"),
                List.of(new DocumentRequest("LOAN_APPLICATION", "application.pdf", DocumentStatus.EXPECTED,
                        true, null, null, "application/pdf", null)), WorkflowStartMode.AUTO);

        repository.insertAddress(42L, "ADDR-0123456789abcdef0123456789abcdef", request);

        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);
        verify(jdbc).sql(sql.capture());
        assertThat(sql.getValue()).contains("INSERT INTO CLOUDBANK.CB_ADDRESS").contains("'REVIEW'");
        verify(insert).param("applicantSk", 42L);
        verify(insert).param("addressLine", "Via del Corso 1");
        verify(insert).param("locality", "Roma");
        verify(insert).param("jurisdictionCode", "IT-ROMA");
        verify(insert).param("addressToken", "address-token");
        verify(insert).param("countryCode", "IT");
        verify(insert).param("postalCode", "00186");
    }
}
