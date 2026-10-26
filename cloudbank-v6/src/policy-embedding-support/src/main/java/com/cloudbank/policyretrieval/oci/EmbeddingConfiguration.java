/*
 * Copyright (c) 2026, Oracle and/or its affiliates.
 * Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/
 */

package com.cloudbank.policyretrieval.oci;

import com.cloudbank.policyretrieval.vector.EmbeddingModel;
import com.cloudbank.policyretrieval.vector.OracleGenAiEmbeddingModel;
import com.oracle.bmc.generativeaiinference.GenerativeAiInference;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration(proxyBeanMethods = false)
@EnableConfigurationProperties(EmbeddingProperties.class)
public class EmbeddingConfiguration {

    @Bean
    EmbeddingModel oracleGenAiEmbeddingModel(GenerativeAiInference generativeAiInference,
                                             EmbeddingProperties properties) {
        return OracleGenAiEmbeddingModel.builder()
                .client(generativeAiInference)
                .defaultOptions(properties)
                .build();
    }
}
