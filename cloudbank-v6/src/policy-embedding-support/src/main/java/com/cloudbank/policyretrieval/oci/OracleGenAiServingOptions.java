/*
 * Copyright (c) 2026, Oracle and/or its affiliates.
 * Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/
 */

package com.cloudbank.policyretrieval.oci;

import com.cloudbank.policyretrieval.oci.api.OracleGenAiServingMode;
import com.oracle.bmc.generativeaiinference.model.DedicatedServingMode;
import com.oracle.bmc.generativeaiinference.model.OnDemandServingMode;
import com.oracle.bmc.generativeaiinference.model.ServingMode;
import org.springframework.util.Assert;
import org.springframework.util.StringUtils;

interface OracleGenAiServingOptions {

    String getCompartmentId();

    void setCompartmentId(String compartmentId);

    String getModel();

    String getEndpointId();

    void setEndpointId(String endpointId);

    OracleGenAiServingMode getServingMode();

    void setServingMode(OracleGenAiServingMode servingMode);

    default void validate() {
        Assert.hasText(getCompartmentId(), "OCI Generative AI compartmentId must be configured.");
        if (getServingMode() == null) {
            throw new IllegalArgumentException("OCI Generative AI servingMode must be configured.");
        }
        if (getServingMode() != OracleGenAiServingMode.DEDICATED && !StringUtils.hasText(getModel())) {
            throw new IllegalArgumentException("OCI Generative AI on-demand serving mode requires options.model.");
        }
        if (getServingMode() == OracleGenAiServingMode.DEDICATED && !StringUtils.hasText(getEndpointId())) {
            throw new IllegalArgumentException("OCI Generative AI dedicated serving mode requires options.endpointId.");
        }
    }

    default ServingMode toServingMode() {
        if (getServingMode() == OracleGenAiServingMode.DEDICATED) {
            return DedicatedServingMode.builder().endpointId(getEndpointId()).build();
        }
        return OnDemandServingMode.builder().modelId(getModel()).build();
    }
}
