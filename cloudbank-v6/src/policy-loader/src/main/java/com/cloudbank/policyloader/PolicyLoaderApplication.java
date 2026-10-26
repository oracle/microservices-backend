// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.policyloader;

import com.cloudbank.policyretrieval.oci.EmbeddingConfiguration;
import com.cloudbank.policyretrieval.oci.GenAiConfiguration;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Import;

@SpringBootApplication
@EnableConfigurationProperties(PolicyLoaderProperties.class)
@Import({GenAiConfiguration.class, EmbeddingConfiguration.class})
public class PolicyLoaderApplication {

    public static void main(String[] args) {
        var context = SpringApplication.run(PolicyLoaderApplication.class, args);
        System.exit(SpringApplication.exit(context));
    }
}
