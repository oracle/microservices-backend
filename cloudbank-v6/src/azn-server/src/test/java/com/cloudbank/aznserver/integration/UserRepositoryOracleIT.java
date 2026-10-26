// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.aznserver.integration;

import com.cloudbank.aznserver.model.User;
import com.cloudbank.aznserver.AznServerApplication;
import com.cloudbank.aznserver.repository.UserRepository;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.context.TestPropertySource;
import org.springframework.transaction.annotation.Transactional;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest
@TestPropertySource(properties = "azn.authorization-server.default-client.enabled=true")
class UserRepositoryOracleIT extends OracleIntegrationTestSupport {

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @Autowired
    private PasswordEncoder passwordEncoder;

    @Autowired
    private UserRepository userRepository;

    @DynamicPropertySource
    static void oracleProperties(DynamicPropertyRegistry registry) {
        configureOracleProperties(registry);
    }

    @Test
    void liquibaseCreatesUsersTableAndStartupUsers() {
        String currentUser = jdbcTemplate.queryForObject(
                "select sys_context('USERENV', 'CURRENT_USER') from dual", String.class);
        String proxyUser = jdbcTemplate.queryForObject(
                "select sys_context('USERENV', 'PROXY_USER') from dual", String.class);
        Integer userCount = jdbcTemplate.queryForObject("select count(*) from USER_REPO.USERS", Integer.class);

        assertThat(currentUser).isEqualTo("USER_REPO_APP");
        assertThat(proxyUser).isNull();
        assertThat(userCount).isNotNull();
        assertStoredPbkdf2Password("obaas-user", BOOTSTRAP_PASSWORD);
        assertStoredPbkdf2Password("obaas-config", BOOTSTRAP_PASSWORD);
        assertThat(userRepository.findByUsername("obaas-admin"))
                .hasValueSatisfying(user -> {
                    assertThat(user.getRoles()).isEqualTo("ROLE_ADMIN,ROLE_CONFIG_EDITOR,ROLE_USER,ROLE_UNDERWRITER");
                    assertThat(user.getPassword()).isNotEqualTo(BOOTSTRAP_PASSWORD).matches("[0-9a-f]{96}");
                    assertThat(passwordEncoder.matches(BOOTSTRAP_PASSWORD, user.getPassword())).isTrue();
                    assertThat(passwordEncoder.matches("WrongPass123!", user.getPassword())).isFalse();
                });
    }

    @Test
    @Transactional
    void bootstrapPersistsMissingDemoGrantsAndPreservesExistingIdentityAndPassword() {
        User admin = userRepository.findByUsername("obaas-admin").orElseThrow();
        String principalId = admin.getPrincipalId();
        String passwordHash = admin.getPassword();
        admin.setRoles("ROLE_ADMIN,ROLE_CONFIG_EDITOR,ROLE_USER,ROLE_AUDITOR");
        userRepository.saveAndFlush(admin);

        AznServerApplication.initUserStore(userRepository, passwordEncoder, "", "");
        AznServerApplication.initUserStore(userRepository, passwordEncoder, "", "");

        assertThat(jdbcTemplate.queryForObject(
                "SELECT roles FROM USER_REPO.USERS WHERE username = ?", String.class, "obaas-admin"))
                .isEqualTo("ROLE_ADMIN,ROLE_CONFIG_EDITOR,ROLE_USER,ROLE_AUDITOR,ROLE_UNDERWRITER");
        assertThat(userRepository.findByUsername("obaas-admin")).hasValueSatisfying(updated -> {
            assertThat(updated.getPrincipalId()).isEqualTo(principalId);
            assertThat(updated.getPassword()).isEqualTo(passwordHash);
        });
    }

    @Test
    void repositoryPersistsAndFindsUsersCaseInsensitively() {
        User saved = userRepository.saveAndFlush(new User(
                "CaseUser",
                passwordEncoder.encode("StrongPass123!"),
                "ROLE_USER",
                "caseuser@example.com"));

        assertThat(saved.getUserId()).isNotNull();
        assertThat(userRepository.findByUsernameIgnoreCase("caseuser"))
                .hasValueSatisfying(user -> assertThat(user.getEmail()).isEqualTo("caseuser@example.com"));
        assertThat(userRepository.findUsersByUsernameStartsWithIgnoreCase("case")).hasSize(1);
        assertThat(userRepository.findByEmailIgnoreCase("CASEUSER@example.com")).isPresent();
    }

    private void assertStoredPbkdf2Password(String username, String cleartextPassword) {
        assertThat(userRepository.findByUsername(username))
                .hasValueSatisfying(user -> {
                    assertThat(user.getPassword()).isNotEqualTo(cleartextPassword).matches("[0-9a-f]{96}");
                    assertThat(passwordEncoder.matches(cleartextPassword, user.getPassword())).isTrue();
                    assertThat(passwordEncoder.matches("WrongPass123!", user.getPassword())).isFalse();
                });
    }
}
