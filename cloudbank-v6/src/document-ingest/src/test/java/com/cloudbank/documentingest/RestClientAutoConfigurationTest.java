// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.documentingest;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.springframework.boot.autoconfigure.AutoConfigurations;
import org.springframework.boot.restclient.autoconfigure.RestClientAutoConfiguration;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.web.client.RestClient;

class RestClientAutoConfigurationTest {

    private final ApplicationContextRunner contextRunner = new ApplicationContextRunner()
            .withConfiguration(AutoConfigurations.of(RestClientAutoConfiguration.class));

    @Test
    void providesManagedRestClientBuilder() {
        contextRunner.run(context -> assertThat(context.getBeansOfType(RestClient.Builder.class)).hasSize(1));
    }
}
