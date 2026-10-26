// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.policyretrieval.model;

import java.util.Locale;

public enum DataClassification {
    PUBLIC_DEMO, INTERNAL, RESTRICTED_CUSTOMER, RESTRICTED_POLICY;

    public static DataClassification fromValue(String value) {
        if (value == null) {
            throw new IllegalArgumentException("Data classification must not be null");
        }
        return valueOf(value.toUpperCase(Locale.ROOT));
    }
}
