// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/

package com.oracle.demo.lab.config;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.EnvironmentPostProcessor;
import org.springframework.core.Ordered;
import org.springframework.core.env.ConfigurableEnvironment;
import org.springframework.util.StringUtils;

import java.util.ArrayList;
import java.util.List;

public class DatabaseCredentialsEnvironmentPostProcessor implements EnvironmentPostProcessor, Ordered {
    private static final List<String> REQUIRED_PROPERTIES = List.of("APP_DB_USERNAME", "APP_DB_PASSWORD");

    @Override
    public void postProcessEnvironment(ConfigurableEnvironment environment, SpringApplication application) {
        List<String> missingProperties = new ArrayList<>();
        for (String property : REQUIRED_PROPERTIES) {
            if (!StringUtils.hasText(environment.getProperty(property))) {
                missingProperties.add(property);
            }
        }

        if (!missingProperties.isEmpty()) {
            throw new IllegalStateException(
                    "Missing required database credential environment variable(s): "
                            + String.join(", ", missingProperties)
                            + ". Set them before starting the lab."
            );
        }
    }

    @Override
    public int getOrder() {
        return Ordered.HIGHEST_PRECEDENCE;
    }
}
