// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.geographicrisk.domain;

public record ApplicationAddress(
        long applicationSk,
        long addressSk,
        String jurisdictionCode,
        boolean hasLocation,
        Double longitude,
        Double latitude,
        GeocodingStatus geocodingStatus) {

    public ApplicationAddress(long applicationSk, long addressSk, String jurisdictionCode,
            boolean hasLocation) {
        this(applicationSk, addressSk, jurisdictionCode, hasLocation,
                null, null,
                hasLocation ? GeocodingStatus.STORED : GeocodingStatus.NO_MATCH);
    }

    public boolean hasCoordinates() {
        return longitude != null && latitude != null;
    }

    public boolean geocodingUnavailable() {
        return geocodingStatus == GeocodingStatus.UNAVAILABLE;
    }
}
