/*
 * Copyright (c) 2026, Oracle and/or its affiliates.
 * Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/
 */

package com.cloudbank.policyretrieval.oci;

import com.oracle.bmc.ClientRuntime;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.auth.RegionProvider;
import com.oracle.bmc.generativeaiinference.GenerativeAiInference;
import com.oracle.bmc.generativeaiinference.GenerativeAiInferenceClient;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.util.StringUtils;

import java.io.IOException;

@Configuration
@EnableConfigurationProperties(AuthenticationProperties.class)
public class GenAiConfiguration {

    static final String USER_AGENT = "Oracle-CloudbankAI";

    private static final Logger LOGGER = LoggerFactory.getLogger(GenAiConfiguration.class);

    @Bean
    public BasicAuthenticationDetailsProvider oracleGenAiAuthenticationDetailsProvider(
            AuthenticationProperties properties) throws IOException {
        ClientRuntime.setClientUserAgent(USER_AGENT);
        return AuthenticationProviderFactory.create(properties);
    }

    @Bean
    public GenerativeAiInference oracleGenAiInferenceClient(BasicAuthenticationDetailsProvider authenticationDetailsProvider,
            AuthenticationProperties properties) {
        GenerativeAiInference client = GenerativeAiInferenceClient.builder().build(authenticationDetailsProvider);
        String effectiveRegion = properties.getRegion();
        if (StringUtils.hasText(properties.getEndpoint())) {
            client.setEndpoint(properties.getEndpoint());
        }
        else if (StringUtils.hasText(properties.getRegion())) {
            client.setRegion(properties.getRegion());
        }
        else if (authenticationDetailsProvider instanceof RegionProvider regionProvider
                && regionProvider.getRegion() != null) {
            client.setRegion(regionProvider.getRegion());
            effectiveRegion = regionProvider.getRegion().getRegionId();
        }
        LOGGER.info(
                "OCI GenAI inference client configured authenticationType={} region={} customEndpointConfigured={}",
                properties.getAuthenticationType(), effectiveRegion, StringUtils.hasText(properties.getEndpoint()));
        return client;
    }
}
