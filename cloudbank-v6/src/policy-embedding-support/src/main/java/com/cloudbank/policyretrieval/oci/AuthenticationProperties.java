/*
 * Copyright (c) 2026, Oracle and/or its affiliates.
 * Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/
 */

package com.cloudbank.policyretrieval.oci;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * OCI authentication properties for Spring AI Oracle model clients.
 */
@ConfigurationProperties(prefix = PropertyNames.CONFIG_PREFIX)
public class AuthenticationProperties {
    private Type authenticationType = Type.WORKLOAD_IDENTITY;

    private String federationEndpoint;

    private String configFile;

    private String profile;

    private String tenantId;

    private String userId;

    private String fingerprint;

    private String privateKey;

    private String passPhrase;

    private String region;

    private String endpoint;

    public enum Type {
        FILE,
        INSTANCE_PRINCIPAL,
        RESOURCE_PRINCIPAL,
        WORKLOAD_IDENTITY,
        SIMPLE,
        SESSION_TOKEN
    }

    public Type getAuthenticationType() {
        return authenticationType;
    }

    public void setAuthenticationType(Type authenticationType) {
        this.authenticationType = authenticationType;
    }

    public String getFederationEndpoint() {
        return federationEndpoint;
    }

    public void setFederationEndpoint(String federationEndpoint) {
        this.federationEndpoint = federationEndpoint;
    }

    public String getConfigFile() {
        return configFile;
    }

    public void setConfigFile(String configFile) {
        this.configFile = configFile;
    }

    public String getProfile() {
        return profile;
    }

    public void setProfile(String profile) {
        this.profile = profile;
    }

    public String getTenantId() {
        return tenantId;
    }

    public void setTenantId(String tenantId) {
        this.tenantId = tenantId;
    }

    public String getUserId() {
        return userId;
    }

    public void setUserId(String userId) {
        this.userId = userId;
    }

    public String getFingerprint() {
        return fingerprint;
    }

    public void setFingerprint(String fingerprint) {
        this.fingerprint = fingerprint;
    }

    public String getPrivateKey() {
        return privateKey;
    }

    public void setPrivateKey(String privateKey) {
        this.privateKey = privateKey;
    }

    public String getPassPhrase() {
        return passPhrase;
    }

    public void setPassPhrase(String passPhrase) {
        this.passPhrase = passPhrase;
    }

    public String getRegion() {
        return region;
    }

    public void setRegion(String region) {
        this.region = region;
    }

    public String getEndpoint() {
        return endpoint;
    }

    public void setEndpoint(String endpoint) {
        this.endpoint = endpoint;
    }
}
