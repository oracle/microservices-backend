// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.policyretrieval.persistence;

import java.util.Locale;
import java.util.Set;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

@Component
public class SqlNames {
    private static final Set<String> TABLES = Set.of("CB_POLICY_CHUNK", "CB_POLICY_DOCUMENT");

    private final String schema;

    public SqlNames(@Value("${cloudbank.schema:CLOUDBANK}") String schema) {
        if (schema == null || !schema.matches("[A-Za-z][A-Za-z0-9_$#]{0,127}")) {
            throw new IllegalArgumentException("POLICY_SCHEMA contains invalid characters");
        }
        this.schema = schema.toUpperCase(Locale.ROOT);
    }

    public String table(String table) {
        if (table == null || !TABLES.contains(table)) {
            throw new IllegalArgumentException("Unsupported Oracle table identifier");
        }
        return schema + "." + table;
    }
}
