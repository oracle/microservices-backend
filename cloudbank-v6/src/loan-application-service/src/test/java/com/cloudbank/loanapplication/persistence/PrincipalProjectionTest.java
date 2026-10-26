// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.loanapplication.persistence;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Answers.RETURNS_SELF;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.cloudbank.loanapplication.security.AuthenticatedPrincipal;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.jdbc.core.simple.JdbcClient;

class PrincipalProjectionTest {

    @Test
    void ensuresApplicantPrincipalThroughTheSecurityPackage() {
        JdbcClient jdbc = mock(JdbcClient.class);
        JdbcClient.StatementSpec ensure = mock(JdbcClient.StatementSpec.class, RETURNS_SELF);
        when(jdbc.sql(anyString())).thenReturn(ensure);
        PrincipalProjection projection = new PrincipalProjection(jdbc, new SqlNames("CLOUDBANK"));

        projection.ensureApplicantPrincipal(principal());

        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);
        verify(jdbc, times(1)).sql(sql.capture());
        assertThat(sql.getValue()).contains("ENSURE_APPLICANT_PRINCIPAL");
    }

    @Test
    void rejectsIncompletePrincipalClaims() {
        PrincipalProjection projection = new PrincipalProjection(mock(JdbcClient.class), new SqlNames("CLOUDBANK"));

        assertThatThrownBy(() -> projection.requireIdentity(new AuthenticatedPrincipal(
                " ", "https://issuer", "subject-1", "Applicant One", null, "user", List.of("ROLE_APPLICANT"))))
                .isInstanceOf(IllegalArgumentException.class);
    }

    private static AuthenticatedPrincipal principal() {
        return new AuthenticatedPrincipal("principal-1", "https://issuer", "subject-1", "Applicant One",
                null, "user", List.of("ROLE_APPLICANT"));
    }
}
