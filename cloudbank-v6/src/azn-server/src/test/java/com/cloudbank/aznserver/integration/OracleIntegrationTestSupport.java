// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.aznserver.integration;

import java.security.SecureRandom;
import java.util.concurrent.atomic.AtomicInteger;

import org.springframework.test.annotation.DirtiesContext;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.oracle.OracleContainer;
import org.testcontainers.utility.DockerImageName;

@Testcontainers
@DirtiesContext(classMode = DirtiesContext.ClassMode.AFTER_CLASS)
abstract class OracleIntegrationTestSupport {

    private static final DockerImageName ORACLE_IMAGE =
            DockerImageName.parse("gvenzl/oracle-free:23.26.2-slim-faststart");
    private static final AtomicInteger POOL_SEQUENCE = new AtomicInteger();
    private static final SecureRandom PASSWORD_RANDOM = new SecureRandom();

    static final String BOOTSTRAP_PASSWORD = generatedPassword();
    static final String USER_REPO_PASSWORD = generatedPassword();

    private static final String ORACLE_PASSWORD = generatedPassword();

    @Container
    static final OracleContainer ORACLE = new OracleContainer(ORACLE_IMAGE)
            .withPassword(ORACLE_PASSWORD);

    static void configureOracleProperties(DynamicPropertyRegistry registry) {
        String poolName = "AznServerOracleIT-" + POOL_SEQUENCE.incrementAndGet();

        registry.add("spring.datasource.url", ORACLE::getJdbcUrl);
        registry.add("spring.datasource.username", () -> "USER_REPO_APP");
        registry.add("spring.datasource.password", () -> USER_REPO_PASSWORD);
        registry.add("spring.datasource.driver-class-name", ORACLE::getDriverClassName);
        registry.add("spring.datasource.type", () -> "oracle.ucp.jdbc.PoolDataSource");
        registry.add("spring.datasource.oracleucp.connection-factory-class-name",
                () -> "oracle.jdbc.pool.OracleDataSource");
        registry.add("spring.datasource.oracleucp.connection-pool-name", () -> poolName);
        registry.add("spring.datasource.oracleucp.initial-pool-size", () -> "1");
        registry.add("spring.datasource.oracleucp.min-pool-size", () -> "1");
        registry.add("spring.datasource.oracleucp.max-pool-size", () -> "4");
        registry.add("spring.liquibase.url", ORACLE::getJdbcUrl);
        registry.add("spring.liquibase.user", () -> "system");
        registry.add("spring.liquibase.password", ORACLE::getPassword);
        registry.add("spring.liquibase.parameters.userRepoOwnerPassword", () -> USER_REPO_PASSWORD);
        registry.add("spring.liquibase.parameters.userRepoRuntimePassword", () -> USER_REPO_PASSWORD);
        registry.add("spring.liquibase.enabled", () -> "true");
        registry.add("azn.bootstrap-users.enabled", () -> "true");
        registry.add("azn.bootstrap-users.admin-password", () -> BOOTSTRAP_PASSWORD);
        registry.add("azn.bootstrap-users.user-password", () -> BOOTSTRAP_PASSWORD);
        registry.add("azn.authorization-server.default-client.secret", () -> "TestLocalClientSecret123!");
        registry.add("eureka.client.enabled", () -> "false");
        registry.add("spring.cloud.discovery.enabled", () -> "false");
        registry.add("spring.cloud.service-registry.auto-registration.enabled", () -> "false");
    }

    private static String generatedPassword() {
        String upper = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
        String lower = "abcdefghijklmnopqrstuvwxyz";
        String digits = "0123456789";
        String alphabet = upper + lower + digits;
        char[] password = new char[16];

        password[0] = randomChar(upper);
        password[1] = randomChar(lower);
        password[2] = randomChar(digits);
        for (int i = 3; i < password.length; i++) {
            password[i] = randomChar(alphabet);
        }
        for (int i = password.length - 1; i > 0; i--) {
            int j = PASSWORD_RANDOM.nextInt(i + 1);
            char current = password[i];
            password[i] = password[j];
            password[j] = current;
        }
        return new String(password);
    }

    private static char randomChar(String alphabet) {
        return alphabet.charAt(PASSWORD_RANDOM.nextInt(alphabet.length()));
    }
}
