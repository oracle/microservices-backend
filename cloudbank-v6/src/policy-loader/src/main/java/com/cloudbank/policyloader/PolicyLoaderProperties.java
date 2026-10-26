// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.policyloader;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.validation.annotation.Validated;

import java.nio.file.Path;

@Validated
@ConfigurationProperties(prefix = "cloudbank.policy-loader")
public class PolicyLoaderProperties {
    @NotNull
    private Path corpusPath;

    @Pattern(regexp = "[A-Za-z][A-Za-z0-9_$#]{0,127}")
    private String schema = "CLOUDBANK";

    public Path getCorpusPath() {
        return corpusPath;
    }

    public void setCorpusPath(Path corpusPath) {
        this.corpusPath = corpusPath;
    }

    public String getSchema() {
        return schema;
    }

    public void setSchema(String schema) {
        this.schema = schema;
    }
}
