// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/

package com.oracle.demo.lab.config;

import org.junit.jupiter.api.Test;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.WebApplicationType;
import org.springframework.context.annotation.Configuration;
import org.springframework.mock.env.MockEnvironment;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.api.Assertions.assertThatNoException;
import static org.mockito.Mockito.mock;

class DatabaseCredentialsEnvironmentPostProcessorTest {

    private final DatabaseCredentialsEnvironmentPostProcessor processor =
            new DatabaseCredentialsEnvironmentPostProcessor();
    private final SpringApplication application = mock(SpringApplication.class);

    @Test
    void failsWhenUsernameAndPasswordAreMissing() {
        MockEnvironment env = new MockEnvironment();
        assertThatThrownBy(() -> processor.postProcessEnvironment(env, application))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("APP_DB_USERNAME")
                .hasMessageContaining("APP_DB_PASSWORD");
    }

    @Test
    void failsWhenPasswordIsMissing() {
        MockEnvironment env = new MockEnvironment();
        env.setProperty("APP_DB_USERNAME", "lab_user");
        assertThatThrownBy(() -> processor.postProcessEnvironment(env, application))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("APP_DB_PASSWORD")
                .hasMessageNotContaining("APP_DB_USERNAME");
    }

    @Test
    void acceptsExplicitCredentials() {
        MockEnvironment env = new MockEnvironment();
        env.setProperty("APP_DB_USERNAME", "lab_user");
        env.setProperty("APP_DB_PASSWORD", "s3cr3t");
        assertThatNoException().isThrownBy(() -> processor.postProcessEnvironment(env, application));
    }

    @Test
    void registeredProcessorRejectsStartupWithoutCredentials() {
        SpringApplication application = new SpringApplication(EmptyConfiguration.class);
        application.setWebApplicationType(WebApplicationType.NONE);
        application.setEnvironment(new MockEnvironment());

        assertThatThrownBy(application::run)
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("APP_DB_USERNAME")
                .hasMessageContaining("APP_DB_PASSWORD");
    }

    @Configuration(proxyBeanMethods = false)
    static class EmptyConfiguration {
    }
}
