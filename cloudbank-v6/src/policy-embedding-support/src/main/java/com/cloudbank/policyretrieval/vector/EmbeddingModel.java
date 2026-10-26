// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.policyretrieval.vector;

import java.util.List;

public interface EmbeddingModel {
    float[] embed(String chunk);
    List<float[]> embed(List<String> chunks);
}
