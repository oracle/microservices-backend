// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.geographicrisk.security;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.ws.rs.core.Application;
import org.eclipse.microprofile.auth.LoginConfig;

/** Enables MP-JWT authentication for the internal geographic-risk APIs. */
@ApplicationScoped
@LoginConfig(authMethod = "MP-JWT")
public class GeographicRiskSecurityApplication extends Application {
}
