// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/

package com.oracle.demo.lab.ai;

import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.generativeaiinference.GenerativeAiInference;
import org.junit.jupiter.api.Test;

import java.io.ByteArrayInputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.security.KeyPairGenerator;
import java.util.Base64;

import static org.assertj.core.api.Assertions.assertThat;

class GenAIConfigurationTest {

    @Test
    void createsOciClientWithoutACloudRequest() throws Exception {
        KeyPairGenerator keyGenerator = KeyPairGenerator.getInstance("RSA");
        keyGenerator.initialize(2048);
        String privateKey = "-----BEGIN PRIVATE KEY-----\n"
                + Base64.getMimeEncoder(64, new byte[]{'\n'})
                .encodeToString(keyGenerator.generateKeyPair().getPrivate().getEncoded())
                + "\n-----END PRIVATE KEY-----\n";

        BasicAuthenticationDetailsProvider authProvider = new BasicAuthenticationDetailsProvider() {
            @Override
            public String getKeyId() {
                return "test-key";
            }

            @Override
            public InputStream getPrivateKey() {
                return new ByteArrayInputStream(privateKey.getBytes(StandardCharsets.US_ASCII));
            }

            @Override
            public String getPassPhrase() {
                return null;
            }

            @Override
            public char[] getPassphraseCharacters() {
                return null;
            }
        };

        try (GenerativeAiInference client = new GenAIConfiguration().generativeAiInferenceClient(authProvider)) {
            assertThat(client).isNotNull();
        }
    }
}
