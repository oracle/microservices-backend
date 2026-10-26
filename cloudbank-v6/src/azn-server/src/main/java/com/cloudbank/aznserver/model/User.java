// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.aznserver.model;

import java.util.Objects;
import java.util.UUID;

import com.fasterxml.jackson.annotation.JsonProperty;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

@Entity
@Table(name = "users", schema = "user_repo")
public class User {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "USER_ID")
    private Long userId;
    @Column(name = "USERNAME", nullable = false)
    private String username;
    @Column(name = "PRINCIPAL_ID", nullable = false, unique = true, length = 80)
    private String principalId;
    /**
     * Stores the PBKDF2 hash that is persisted in USER_REPO.USERS.PASSWORD.
     * Cleartext passwords may be accepted at API boundaries, but they must be
     * encoded before this entity is saved.
     */
    @JsonProperty(access = JsonProperty.Access.WRITE_ONLY)
    @Column(name = "PASSWORD", nullable = false, length = 255)
    private String password;
    @Column(name = "ROLES", nullable = false)
    private String roles;
    @Column(name = "EMAIL")
    private String email;
    @JsonProperty(access = JsonProperty.Access.WRITE_ONLY)
    @Column(name = "OTP")
    private String otp;

    public User() {
    }

    public User(Long userId, String username, String password, String roles, String email, String otp) {
        this.userId = userId;
        this.username = username;
        this.principalId = newPrincipalId();
        this.password = password;
        this.roles = roles;
        this.email = email;
        this.otp = otp;
    }

    /**
     * Create a user object.
     * 
     * @param username The username.
     * @param password The encoded password hash for persistence.
     * @param roles    The roles assigned the user, as a comma separated list, e.g.
     *                 "ROLE_USER,ROLE_ADMIN".
     */
    public User(String username, String password, String roles) {
        this.username = username;
        this.principalId = newPrincipalId();
        this.password = password;
        this.roles = roles;
    }

    // This constructor should only be used during testing with a mock repository,
    // when we need to set the id manually
    public User(long userId, String username, String password, String roles) {
        this(username, password, roles);
        this.userId = userId;
    }

    /**
     * Create a user object.
     * 
     * @param username The username.
     * @param password The encoded password hash for persistence.
     * @param roles    The roles assigned the user, as a comma separated list, e.g.
     *                 "ROLE_USER,ROLE_ADMIN".
     * @param email    The email associated with user account.
     */
    public User(String username, String password, String roles, String email) {
        this(username, password, roles);
        this.email = email;
    }

    public Long getUserId() {
        return userId;
    }

    public void setUserId(Long userId) {
        this.userId = userId;
    }

    public String getUsername() {
        return username;
    }

    public void setUsername(String username) {
        this.username = username;
    }

    public String getPrincipalId() {
        return principalId;
    }

    public void setPrincipalId(String principalId) {
        this.principalId = principalId;
    }

    public String getPassword() {
        return password;
    }

    public void setPassword(String password) {
        this.password = password;
    }

    public String getRoles() {
        return roles;
    }

    public void setRoles(String roles) {
        this.roles = roles;
    }

    public String getEmail() {
        return email;
    }

    public void setEmail(String email) {
        this.email = email;
    }

    public String getOtp() {
        return otp;
    }

    public void setOtp(String otp) {
        this.otp = otp;
    }

    @Override
    public boolean equals(Object o) {
        if (o == null || getClass() != o.getClass()) return false;
        User user = (User) o;
        return Objects.equals(getUserId(), user.getUserId());
    }

    @Override
    public int hashCode() {
        return Objects.hashCode(getUserId());
    }

    @Override
    public String toString() {
        return "User(userId=" + userId
                + ", username=" + username
                + ", principalId=" + principalId
                + ", roles=" + roles
                + ", email=" + email
                + ")";
    }

    private static String newPrincipalId() {
        return "usr-" + UUID.randomUUID();
    }

}
