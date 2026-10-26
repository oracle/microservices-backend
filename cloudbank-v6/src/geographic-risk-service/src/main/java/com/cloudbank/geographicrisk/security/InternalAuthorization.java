// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.geographicrisk.security;

import jakarta.json.JsonArray;
import jakarta.json.JsonString;
import org.eclipse.microprofile.jwt.JsonWebToken;

import java.util.Arrays;
import java.util.Set;
import java.util.stream.Collectors;

final class InternalAuthorization {

    private final Set<String> clientIds;

    InternalAuthorization(String configuredClientIds) {
        clientIds = Arrays.stream(configuredClientIds.split(","))
                .map(String::trim)
                .filter(value -> !value.isEmpty())
                .collect(Collectors.toUnmodifiableSet());
    }

    boolean isInternal(JsonWebToken token) {
        return "service".equals(asString(token.getClaim("token_kind")))
                && clientIds.contains(asString(token.getClaim("client_id")))
                && hasInternalScope(token.getClaim("scope"));
    }

    private static String asString(Object value) {
        if (value instanceof String string) {
            return string;
        }
        if (value instanceof JsonString string) {
            return string.getString();
        }
        return null;
    }

    private static boolean hasInternalScope(Object scope) {
        if (scope instanceof String scopes) {
            return Arrays.stream(scopes.split("\\s+"))
                    .anyMatch("cloudbank.internal"::equals);
        }
        if (scope instanceof JsonArray scopes) {
            return scopes.stream()
                    .filter(JsonString.class::isInstance)
                    .map(JsonString.class::cast)
                    .map(JsonString::getString)
                    .anyMatch("cloudbank.internal"::equals);
        }
        if (scope instanceof Iterable<?> scopes) {
            for (Object value : scopes) {
                if ("cloudbank.internal".equals(value)) {
                    return true;
                }
            }
        }
        return false;
    }
}
