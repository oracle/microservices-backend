// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.policyretrieval.model;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatIllegalArgumentException;

import org.junit.jupiter.api.Test;

class DataClassificationTest {

    @Test
    void convertsOracleLowercaseValue() {
        assertThat(DataClassification.fromValue("restricted_policy"))
                .isEqualTo(DataClassification.RESTRICTED_POLICY);
    }

    @Test
    void rejectsNullValue() {
        assertThatIllegalArgumentException()
                .isThrownBy(() -> DataClassification.fromValue(null))
                .withMessage("Data classification must not be null");
    }
}
