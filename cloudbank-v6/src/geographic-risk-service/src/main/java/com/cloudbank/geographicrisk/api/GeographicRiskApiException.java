// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.geographicrisk.api;

/** Marks failures originating in geographic-risk resource methods only. */
public class GeographicRiskApiException extends RuntimeException {
    public GeographicRiskApiException(RuntimeException cause) {
        super("Geographic risk request failed", cause);
    }
}
