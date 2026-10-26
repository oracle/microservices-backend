// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.policyretrieval.persistence;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatIllegalArgumentException;

import org.junit.jupiter.api.Test;

class SqlNamesTest {

    @Test
    void qualifiesPolicyTablesWithTheConfiguredOwnerSchema() {
        SqlNames sqlNames = new SqlNames("cloudbank");

        assertThat(sqlNames.table("CB_POLICY_CHUNK")).isEqualTo("CLOUDBANK.CB_POLICY_CHUNK");
        assertThat(sqlNames.table("CB_POLICY_DOCUMENT")).isEqualTo("CLOUDBANK.CB_POLICY_DOCUMENT");
    }

    @Test
    void rejectsUnknownTablesAndUnsafeSchemaNames() {
        SqlNames sqlNames = new SqlNames("CLOUDBANK");

        assertThatIllegalArgumentException().isThrownBy(() -> sqlNames.table("CB_APPLICANT"));
        assertThatIllegalArgumentException().isThrownBy(() -> new SqlNames("CLOUDBANK; DROP USER X"));
    }
}
