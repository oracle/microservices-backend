/*
 * Copyright (c) 2026, Oracle and/or its affiliates.
 * Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/
 */

package com.cloudbank.policyretrieval.oci;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Configuration properties for OCI Generative AI embeddings.
 */
@ConfigurationProperties(prefix = PropertyNames.EMBEDDING_CONFIG_PREFIX)
public class EmbeddingProperties extends OracleGenAiEmbeddingOptions {
}
