/*
 * Copyright (c) 2026, Oracle and/or its affiliates.
 * Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/
 */

package com.cloudbank.policyretrieval.oci;

import com.cloudbank.policyretrieval.oci.api.OracleGenAiEmbeddingTruncate;
import com.cloudbank.policyretrieval.oci.api.OracleGenAiServingMode;

/**
 * OCI Generative AI embedding options.
 */
public class OracleGenAiEmbeddingOptions implements OracleGenAiServingOptions {

    private String model;

    private Integer dimensions;

    private String compartmentId;

    private OracleGenAiServingMode servingMode = OracleGenAiServingMode.ON_DEMAND;

    private String endpointId;

    private OracleGenAiEmbeddingTruncate truncate = OracleGenAiEmbeddingTruncate.NONE;

    public static Builder builder() {
        return new Builder();
    }

    @Override
    public String getModel() {
        return model;
    }

    public void setModel(String model) {
        this.model = model;
    }

    public Integer getDimensions() {
        return dimensions;
    }

    public void setDimensions(Integer dimensions) {
        this.dimensions = dimensions;
    }

    @Override
    public String getCompartmentId() {
        return compartmentId;
    }

    @Override
    public void setCompartmentId(String compartmentId) {
        this.compartmentId = compartmentId;
    }

    @Override
    public OracleGenAiServingMode getServingMode() {
        return servingMode;
    }

    @Override
    public void setServingMode(OracleGenAiServingMode servingMode) {
        this.servingMode = servingMode;
    }

    @Override
    public String getEndpointId() {
        return endpointId;
    }

    @Override
    public void setEndpointId(String endpointId) {
        this.endpointId = endpointId;
    }

    public OracleGenAiEmbeddingTruncate getTruncate() {
        return truncate;
    }

    public void setTruncate(OracleGenAiEmbeddingTruncate truncate) {
        this.truncate = truncate;
    }

    public static final class Builder {
        private final OracleGenAiEmbeddingOptions options = new OracleGenAiEmbeddingOptions();

        public Builder model(String model) {
            options.setModel(model);
            return this;
        }

        public Builder dimensions(Integer dimensions) {
            options.setDimensions(dimensions);
            return this;
        }

        public Builder compartmentId(String compartmentId) {
            options.setCompartmentId(compartmentId);
            return this;
        }

        public Builder servingMode(OracleGenAiServingMode servingMode) {
            options.setServingMode(servingMode);
            return this;
        }

        public Builder endpointId(String endpointId) {
            options.setEndpointId(endpointId);
            return this;
        }

        public Builder truncate(OracleGenAiEmbeddingTruncate truncate) {
            options.setTruncate(truncate);
            return this;
        }

        public OracleGenAiEmbeddingOptions build() {
            return options;
        }
    }
}
