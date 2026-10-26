// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.policyretrieval.rest;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatIllegalArgumentException;

import com.cloudbank.policyretrieval.model.AiUse;
import org.junit.jupiter.api.Test;

class AiUseConverterTest {

    private final AiUseConverter converter = new AiUseConverter();

    @Test
    void convertsDocumentedLowercaseApiValue() {
        assertThat(converter.convert("retrieval")).isEqualTo(AiUse.RETRIEVAL);
    }

    @Test
    void rejectsUnknownApiValue() {
        assertThatIllegalArgumentException()
                .isThrownBy(() -> converter.convert("unknown"))
                .withMessage("Unknown AI use: unknown");
    }
}
