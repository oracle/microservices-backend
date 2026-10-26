// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.loanapplication.persistence;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.util.Arrays;
import java.util.List;
import org.junit.jupiter.api.Test;

class SqlNamesTest {

    @Test
    void qualifiesAllowlistedOracleObjectsWithNormalizedSchema() {
        SqlNames names = new SqlNames("cloudbank");

        assertThat(names.table("CB_LOAN_APPLICATION"))
                .isEqualTo("CLOUDBANK.CB_LOAN_APPLICATION");
        assertThat(names.table("CB_ADDRESS")).isEqualTo("CLOUDBANK.CB_ADDRESS");
        assertThat(names.packageName("CB_APPLICATION_SECURITY_PKG"))
                .isEqualTo("CLOUDBANK.CB_APPLICATION_SECURITY_PKG");
    }

    @Test
    void rejectsSchemaNamesThatCouldChangeSqlStructure() {
        List<String> invalidSchemas = Arrays.asList(
                null,
                "CLOUDBANK.CB_LOAN_APPLICATION",
                "CLOUDBANK --",
                "CLOUDBANK; DROP USER APP",
                "CLOUDBANK\"",
                "CLOUD BANK");

        invalidSchemas.forEach(schema -> assertThatThrownBy(() -> new SqlNames(schema))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessage("LOAN_SCHEMA contains invalid characters"));
    }

    @Test
    void rejectsOracleObjectsOutsideTheAllowlist() {
        SqlNames names = new SqlNames("CLOUDBANK");

        List<String> invalidTables = Arrays.asList(
                null,
                "CB_UNKNOWN",
                "CB_LOAN_APPLICATION --",
                "CB_LOAN_APPLICATION; DROP TABLE CB_DOCUMENT",
                "OTHER.CB_LOAN_APPLICATION",
                "CB_LOAN_APPLICATION\"");
        invalidTables.forEach(table -> assertThatThrownBy(() -> names.table(table))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessage("Unsupported Oracle table identifier"));

        assertThatThrownBy(() -> names.packageName("CB_UNKNOWN_SECURITY_PKG; END;"))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessage("Unsupported Oracle package identifier");
    }
}
