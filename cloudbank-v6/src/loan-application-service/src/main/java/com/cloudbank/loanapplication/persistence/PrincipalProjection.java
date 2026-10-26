// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.loanapplication.persistence;

import com.cloudbank.loanapplication.security.AuthenticatedPrincipal;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;

@Component
public class PrincipalProjection {

    private final JdbcClient jdbc;
    private final SqlNames names;

    public PrincipalProjection(JdbcClient jdbc, SqlNames names) {
        this.jdbc = jdbc;
        this.names = names;
    }

    public void requireIdentity(AuthenticatedPrincipal principal) {
        if (principal == null || principal.principalId() == null || principal.principalId().isBlank()
                || principal.issuer() == null || principal.subject() == null) {
            throw new IllegalArgumentException("Authenticated principal claims are incomplete");
        }
    }

    public void ensureApplicantPrincipal(AuthenticatedPrincipal principal) {
        jdbc.sql("BEGIN " + names.packageName("CB_APPLICATION_SECURITY_PKG")
                        + ".ENSURE_APPLICANT_PRINCIPAL(:principalId, :issuer, :subject, :displayName); END;")
                .param("principalId", principal.principalId())
                .param("issuer", principal.issuer())
                .param("subject", principal.subject())
                .param("displayName", principal.displayName())
                .update();
    }
}
