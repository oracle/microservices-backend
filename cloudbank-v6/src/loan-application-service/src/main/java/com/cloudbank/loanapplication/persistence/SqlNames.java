// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.loanapplication.persistence;

import java.util.Locale;
import java.util.Set;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

@Component
public class SqlNames {

    private static final Set<String> TABLES = Set.of(
            "CB_APPLICANT",
            "CB_ADDRESS",
            "CB_APP_PRINCIPAL",
            "CB_APP_ROLE_GRANT",
            "CB_AUDIT_EVENT",
            "CB_DATA_GRANT",
            "CB_DOCUMENT",
            "CB_DOCUMENT_CONTENT",
            "CB_DOCUMENT_REGISTRATION_REQUEST",
            "CB_LOAN_APPLICATION",
            "CB_TELEMETRY_CORRELATION",
            "CB_WORKFLOW_INSTANCE",
            "CB_WORKFLOW_START_REQUEST");

    private static final Set<String> PACKAGES = Set.of("CB_APPLICATION_SECURITY_PKG");

    private final String schema;

    public SqlNames(@Value("${LOAN_SCHEMA:CLOUDBANK}") String schema) {
        if (schema == null || !schema.matches("[A-Za-z][A-Za-z0-9_$#]{0,127}")) {
            throw new IllegalArgumentException("LOAN_SCHEMA contains invalid characters");
        }
        this.schema = schema.toUpperCase(Locale.ROOT);
    }

    public String table(String table) {
        return schema + "." + requireAllowed(table, TABLES, "table");
    }

    public String packageName(String packageName) {
        return schema + "." + requireAllowed(packageName, PACKAGES, "package");
    }

    private static String requireAllowed(String name, Set<String> allowed, String objectType) {
        if (name == null || !allowed.contains(name)) {
            throw new IllegalArgumentException("Unsupported Oracle " + objectType + " identifier");
        }
        return name;
    }
}
