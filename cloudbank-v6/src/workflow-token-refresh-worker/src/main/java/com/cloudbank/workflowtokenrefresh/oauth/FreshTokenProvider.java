// Copyright (c) 2026, Oracle and/or its affiliates.
//
// Licensed under the Universal Permissive License v 1.0 as shown at
// https://oss.oracle.com/licenses/upl/.

package com.cloudbank.workflowtokenrefresh.oauth;

import java.time.Instant;

public interface FreshTokenProvider {

    AccessToken accessToken();

    void invalidate();

    record AccessToken(String value, Instant expiresAt) {
    }
}
