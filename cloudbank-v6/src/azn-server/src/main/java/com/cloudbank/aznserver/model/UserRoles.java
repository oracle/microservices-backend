// Copyright (c) 2023, Oracle and/or its affiliates.

package com.cloudbank.aznserver.model;

public enum UserRoles {

    ROLE_ADMIN("ROLE_ADMIN"),
    ROLE_APPLICANT("ROLE_APPLICANT"),
    ROLE_AUDITOR("ROLE_AUDITOR"),
    ROLE_CONFIG_EDITOR("ROLE_CONFIG_EDITOR"),
    ROLE_LOAN_OFFICER("ROLE_LOAN_OFFICER"),
    ROLE_OPERATOR("ROLE_OPERATOR"),
    ROLE_UNDERWRITER("ROLE_UNDERWRITER"),
    ROLE_USER("ROLE_USER");

    UserRoles(String roleUser) {
    }

}
