// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.policyloader;

import jakarta.validation.Validation;
import org.junit.jupiter.api.Test;

import java.nio.file.Path;

import static org.assertj.core.api.Assertions.assertThat;

class PolicyLoaderPropertiesTest {

    @Test
    void acceptsAQualifiedOracleSchemaNameAndRejectsSqlFragments() {
        PolicyLoaderProperties valid = new PolicyLoaderProperties();
        valid.setCorpusPath(Path.of("/app/policy"));
        valid.setSchema("CLOUDBANK");

        PolicyLoaderProperties invalid = new PolicyLoaderProperties();
        invalid.setCorpusPath(Path.of("/app/policy"));
        invalid.setSchema("CLOUDBANK.CB_POLICY_DOCUMENT");

        try (var validatorFactory = Validation.buildDefaultValidatorFactory()) {
            var validator = validatorFactory.getValidator();
            assertThat(validator.validate(valid)).isEmpty();
            assertThat(validator.validate(invalid)).isNotEmpty();
        }
    }
}
