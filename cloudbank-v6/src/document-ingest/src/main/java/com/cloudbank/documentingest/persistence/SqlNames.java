// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.documentingest.persistence;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

@Component
public class SqlNames {

    private final String schema;

    public SqlNames(@Value("${cloudbank.schema:CLOUDBANK}") String schema) {
        if (schema == null || !schema.matches("[A-Za-z][A-Za-z0-9_$#]{0,127}")) {
            throw new IllegalArgumentException("DOCUMENT_INGEST_SCHEMA contains invalid characters");
        }
        this.schema = schema.toUpperCase();
    }

    public String table(String table) {
        return schema + "." + table;
    }
}
