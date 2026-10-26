// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.policyretrieval.vector;

import oracle.jdbc.OracleType;
import oracle.sql.VECTOR;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class VectorDataAdapterTest {

    private final VectorDataAdapter adapter = new VectorDataAdapter();

    @Test
    void createsFloat32VectorForFloatEmbeddings() throws Exception {
        VECTOR vector = adapter.toVECTOR(new float[] { 0.25f, 0.5f }, false);

        assertThat(vector.getType()).isEqualTo(OracleType.VECTOR_FLOAT32);
        assertThat(vector.toFloatArray()).containsExactly(0.25f, 0.5f);
    }
}
