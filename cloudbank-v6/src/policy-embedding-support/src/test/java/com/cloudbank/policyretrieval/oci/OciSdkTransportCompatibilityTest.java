// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.policyretrieval.oci;

import com.oracle.bmc.auth.SimpleAuthenticationDetailsProvider;
import com.oracle.bmc.generativeaiinference.GenerativeAiInferenceClient;
import org.junit.jupiter.api.Test;

import java.io.ByteArrayInputStream;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.security.KeyPairGenerator;
import java.util.Base64;

import static org.assertj.core.api.Assertions.assertThat;

class OciSdkTransportCompatibilityTest {

    @Test
    void createsAndClosesTheOciHttpTransportOnTheManagedClasspath() throws Exception {
        KeyPairGenerator generator = KeyPairGenerator.getInstance("RSA");
        generator.initialize(2048);
        byte[] encoded = generator.generateKeyPair().getPrivate().getEncoded();
        String pem = "-----BEGIN PRIVATE KEY-----\n"
                + Base64.getMimeEncoder(64, new byte[]{'\n'}).encodeToString(encoded)
                + "\n-----END PRIVATE KEY-----\n";
        byte[] key = pem.getBytes(StandardCharsets.US_ASCII);
        var authentication = SimpleAuthenticationDetailsProvider.builder()
                .tenantId("ocid1.tenancy.oc1..synthetic-transport-test")
                .userId("ocid1.user.oc1..synthetic-transport-test")
                .fingerprint("00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00")
                .privateKeySupplier(() -> new ByteArrayInputStream(key))
                .build();

        // Construct the real SDK/Jersey transport without sending any request to OCI.
        try (var client = GenerativeAiInferenceClient.builder()
                .endpoint("http://127.0.0.1:9")
                .build(authentication)) {
            assertThat(URI.create(client.getEndpoint()).getPort()).isEqualTo(9);
        }
    }
}
