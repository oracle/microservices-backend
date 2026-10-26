// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.policyretrieval.model;

public enum AiUse {
    NONE("none"), RETRIEVAL("retrieval"), STRUCTURED_FACTS_ONLY("structured facts only"), EXPLANATION_GROUNDING("explanation grounding");

    private final String value;
    AiUse(String value) { this.value = value; }
    public static AiUse fromValue(String value) {
        for (AiUse aiUse : values()) {
            if (aiUse.value.equals(value)) return aiUse;
        }
        throw new IllegalArgumentException("Unknown AI use: " + value);
    }
    @Override public String toString() { return value; }
}
