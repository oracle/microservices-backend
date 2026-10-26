// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.policyretrieval.oci;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class AuthenticationPropertiesTest {

    @Test
    void defaultsToOkeWorkloadIdentityAuthentication() {
        AuthenticationProperties properties = new AuthenticationProperties();

        assertThat(properties.getAuthenticationType())
                .isEqualTo(AuthenticationProperties.Type.WORKLOAD_IDENTITY);
    }
}
