// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.policyretrieval.vector;

import oracle.sql.VECTOR;
import org.springframework.stereotype.Component;

import java.sql.SQLException;

@Component
public class VectorDataAdapter {
    float[] toFloatArray(double[] vector) {
        float[] result = new float[vector.length];
        for (int i = 0; i < vector.length; i++) {
            result[i] = (float) vector[i];
        }
        return result;
    }

    public VECTOR toVECTOR(float[] vector, boolean normalizeVector) throws SQLException {
        if (normalizeVector) {
            vector = normalize(vector);
        }
        return VECTOR.ofFloat32Values(vector);
    }

    float[] normalize(float[] v) {
        double squaredSum = 0d;

        for (float e : v) {
            squaredSum += e * e;
        }

        final float magnitude = (float) Math.sqrt(squaredSum);

        if (magnitude > 0) {
            final float multiplier = 1f / magnitude;
            final int length = v.length;
            for (int i = 0; i < length; i++) {
                v[i] *= multiplier;
            }
        }

        return v;
    }
}
