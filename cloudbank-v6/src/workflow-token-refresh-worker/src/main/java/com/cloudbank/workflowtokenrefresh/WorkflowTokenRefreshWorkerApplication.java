// Copyright (c) 2026, Oracle and/or its affiliates.
//
// Licensed under the Universal Permissive License v 1.0 as shown at
// https://oss.oracle.com/licenses/upl/.

package com.cloudbank.workflowtokenrefresh;

import com.cloudbank.workflowtokenrefresh.config.TokenRefreshWorkerProperties;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.scheduling.annotation.EnableScheduling;

@SpringBootApplication
@EnableScheduling
@EnableConfigurationProperties(TokenRefreshWorkerProperties.class)
public class WorkflowTokenRefreshWorkerApplication {

    public static void main(String[] args) {
        SpringApplication.run(WorkflowTokenRefreshWorkerApplication.class, args);
    }
}
