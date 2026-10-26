/*
 * Copyright (c) 2026, Oracle and/or its affiliates.
 * Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/
 */

package com.cloudbank.policyretrieval.oci;

import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.auth.ConfigFileAuthenticationDetailsProvider;
import com.oracle.bmc.auth.InstancePrincipalsAuthenticationDetailsProvider;
import com.oracle.bmc.auth.ResourcePrincipalAuthenticationDetailsProvider;
import com.oracle.bmc.auth.SessionTokenAuthenticationDetailsProvider;
import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;
import com.oracle.bmc.auth.SimplePrivateKeySupplier;
import com.oracle.bmc.auth.okeworkloadidentity.OkeWorkloadIdentityAuthenticationDetailsProvider;
import org.springframework.util.StringUtils;

import java.io.IOException;

final class AuthenticationProviderFactory {

    private static final String DEFAULT_PROFILE = "DEFAULT";

    private AuthenticationProviderFactory() {
    }

    static BasicAuthenticationDetailsProvider create(AuthenticationProperties properties) throws IOException {
        return switch (properties.getAuthenticationType()) {
            case WORKLOAD_IDENTITY -> OkeWorkloadIdentityAuthenticationDetailsProvider.builder()
                    .federationEndpoint(properties.getFederationEndpoint())
                    .build();
            case RESOURCE_PRINCIPAL -> ResourcePrincipalAuthenticationDetailsProvider.builder()
                    .federationEndpoint(properties.getFederationEndpoint())
                    .build();
            case INSTANCE_PRINCIPAL -> InstancePrincipalsAuthenticationDetailsProvider.builder()
                    .federationEndpoint(properties.getFederationEndpoint())
                    .build();
            case SIMPLE -> createSimpleAuthenticationDetailsProvider(properties);
            case SESSION_TOKEN -> createSessionTokenAuthenticationDetailsProvider(properties);
            case FILE -> createConfigFileAuthenticationDetailsProvider(properties);
        };
    }

    private static BasicAuthenticationDetailsProvider createSimpleAuthenticationDetailsProvider(
            AuthenticationProperties properties) {
        SimpleAuthenticationDetailsProvider.SimpleAuthenticationDetailsProviderBuilder builder =
                SimpleAuthenticationDetailsProvider.builder()
                        .userId(properties.getUserId())
                        .tenantId(properties.getTenantId())
                        .fingerprint(properties.getFingerprint())
                        .privateKeySupplier(new SimplePrivateKeySupplier(properties.getPrivateKey()))
                        .passPhrase(properties.getPassPhrase());
        if (StringUtils.hasText(properties.getRegion())) {
            builder.region(Region.valueOf(properties.getRegion()));
        }
        return builder.build();
    }

    private static BasicAuthenticationDetailsProvider createSessionTokenAuthenticationDetailsProvider(
            AuthenticationProperties properties) throws IOException {
        String profile = profile(properties);
        if (StringUtils.hasText(properties.getConfigFile())) {
            return new SessionTokenAuthenticationDetailsProvider(properties.getConfigFile(), profile);
        }
        return new SessionTokenAuthenticationDetailsProvider(profile);
    }

    private static BasicAuthenticationDetailsProvider createConfigFileAuthenticationDetailsProvider(
            AuthenticationProperties properties) throws IOException {
        String profile = profile(properties);
        if (StringUtils.hasText(properties.getConfigFile())) {
            return new ConfigFileAuthenticationDetailsProvider(properties.getConfigFile(), profile);
        }
        return new ConfigFileAuthenticationDetailsProvider(profile);
    }

    private static String profile(AuthenticationProperties properties) {
        return StringUtils.hasText(properties.getProfile()) ? properties.getProfile() : DEFAULT_PROFILE;
    }
}
