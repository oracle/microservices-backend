// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.

package com.cloudbank.aznserver;

import com.cloudbank.aznserver.model.User;
import com.cloudbank.aznserver.repository.UserRepository;
import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.security.crypto.password.PasswordEncoder;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.*;

class BootstrapUsersTest {
    private static final String DEMO_ROLES = "ROLE_ADMIN,ROLE_CONFIG_EDITOR,ROLE_USER,ROLE_UNDERWRITER";
    private final UserRepository users = mock(UserRepository.class);
    private final PasswordEncoder encoder = mock(PasswordEncoder.class);

    @Test
    void cleanInstallationCreatesTheDemoAdminReadyForHumanReview() {
        when(encoder.encode("synthetic-admin-password")).thenReturn("encoded-admin-password");
        when(encoder.encode("synthetic-user-password")).thenReturn("encoded-user-password");

        AznServerApplication.initUserStore(users, encoder, "synthetic-admin-password", "synthetic-user-password");

        var saved = ArgumentCaptor.forClass(User.class);
        verify(users, times(3)).saveAndFlush(saved.capture());
        assertThat(saved.getAllValues()).filteredOn(user -> "obaas-admin".equals(user.getUsername()))
                .singleElement().satisfies(admin -> {
                    assertThat(admin.getRoles()).isEqualTo(DEMO_ROLES);
                    assertThat(admin.getPassword()).isEqualTo("encoded-admin-password");
                    assertThat(admin.getPrincipalId()).isNotBlank();
                });
        assertThat(saved.getAllValues()).filteredOn(user -> !"obaas-admin".equals(user.getUsername()))
                .allSatisfy(user -> assertThat(user.getRoles()).doesNotContain("ROLE_UNDERWRITER"));
    }

    @Test
    void upgradesAnExistingDemoAdminWithoutChangingIdentityCredentialsOrAdditionalRoles() {
        User admin = existingAdmin("ROLE_ADMIN,ROLE_CONFIG_EDITOR,ROLE_USER,ROLE_AUDITOR");
        admin.setPrincipalId("synthetic-stable-principal");
        admin.setOtp("synthetic-otp-hash");
        admin.setEmail("synthetic@example.invalid");

        AznServerApplication.initUserStore(users, encoder, "", "");

        verify(users).saveAndFlush(same(admin));
        assertThat(admin.getRoles()).isEqualTo("ROLE_ADMIN,ROLE_CONFIG_EDITOR,ROLE_USER,ROLE_AUDITOR,ROLE_UNDERWRITER");
        assertThat(admin.getPrincipalId()).isEqualTo("synthetic-stable-principal");
        assertThat(admin.getPassword()).isEqualTo("existing-password-hash");
        assertThat(admin.getOtp()).isEqualTo("synthetic-otp-hash");
        assertThat(admin.getEmail()).isEqualTo("synthetic@example.invalid");
        verifyNoInteractions(encoder);
    }

    @Test
    void repeatedBootstrapAddsMissingGrantsOnlyOnce() {
        User admin = existingAdmin("ROLE_ADMIN,ROLE_CONFIG_EDITOR,ROLE_USER");

        AznServerApplication.initUserStore(users, encoder, "", "");
        AznServerApplication.initUserStore(users, encoder, "", "");

        verify(users, times(1)).saveAndFlush(same(admin));
        assertThat(admin.getRoles()).isEqualTo(DEMO_ROLES);
        verifyNoInteractions(encoder);
    }

    @Test
    void alreadyConfiguredDemoUsersNeedNoWritesOrBootstrapPasswords() {
        existingAdmin(DEMO_ROLES + ",ROLE_OPERATOR");

        AznServerApplication.initUserStore(users, encoder, "", "");

        verify(users, never()).saveAndFlush(any());
        verifyNoInteractions(encoder);
    }

    @Test
    void restoresTheRequiredDemoRoleSetWhilePreservingOtherExplicitGrants() {
        User admin = existingAdmin("ROLE_ADMIN,ROLE_AUDITOR");

        AznServerApplication.initUserStore(users, encoder, "", "");

        assertThat(admin.getRoles().split(",")).containsExactly(
                "ROLE_ADMIN", "ROLE_AUDITOR", "ROLE_CONFIG_EDITOR", "ROLE_USER", "ROLE_UNDERWRITER");
        verify(users).saveAndFlush(same(admin));
    }

    @Test
    void newUsersStillRequireExternalBootstrapPasswords() {
        assertThatThrownBy(() -> AznServerApplication.initUserStore(users, encoder, "", ""))
                .isInstanceOf(IllegalStateException.class).hasMessageContaining("must be set");
        verify(users, never()).saveAndFlush(any());
    }

    private User existingAdmin(String roles) {
        User admin = new User("obaas-admin", "existing-password-hash", roles);
        when(users.findByUsername("obaas-admin")).thenReturn(Optional.of(admin));
        when(users.findByUsername("obaas-user"))
                .thenReturn(Optional.of(new User("obaas-user", "user-password-hash", "ROLE_APPLICANT,ROLE_USER")));
        when(users.findByUsernameIgnoreCase("obaas-config"))
                .thenReturn(Optional.of(new User("obaas-config", "config-password-hash", "ROLE_CONFIG_EDITOR,ROLE_USER")));
        return admin;
    }
}
