// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.loanapplication.workflow;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.boot.autoconfigure.AutoConfigurations;
import org.springframework.boot.restclient.autoconfigure.RestClientAutoConfiguration;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;

class MicroTxWorkflowStarterBeanTest {

    private final ApplicationContextRunner contextRunner = new ApplicationContextRunner()
            .withConfiguration(AutoConfigurations.of(RestClientAutoConfiguration.class))
            .withBean(ObjectMapper.class, ObjectMapper::new)
            .withUserConfiguration(MicroTxWorkflowStarter.class)
            .withPropertyValues(
                    "cloudbank.workflow.mode=microtx",
                    "cloudbank.workflow.base-url=http://microtx.example",
                    "cloudbank.workflow.token-uri=http://azn.example/oauth2/token",
                    "cloudbank.workflow.client-id=cloudbank-service-client",
                    "cloudbank.workflow.client-secret=ServiceClientSecret123!");

    @Test
    void createsMicroTxStarterBeanWhenMicroTxModeIsEnabled() {
        contextRunner.run(context -> assertThat(context).hasSingleBean(MicroTxWorkflowStarter.class));
    }
}
