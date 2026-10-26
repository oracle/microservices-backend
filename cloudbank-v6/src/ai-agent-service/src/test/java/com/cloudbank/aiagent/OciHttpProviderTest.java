// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.aiagent;

import static org.assertj.core.api.Assertions.assertThat;

import com.oracle.bmc.http.client.HttpProvider;
import org.junit.jupiter.api.Test;

class OciHttpProviderTest {

    @Test
    void loadsConcreteOciHttpProvider() {
        assertThat(HttpProvider.getDefault()).isNotNull();
    }
}
