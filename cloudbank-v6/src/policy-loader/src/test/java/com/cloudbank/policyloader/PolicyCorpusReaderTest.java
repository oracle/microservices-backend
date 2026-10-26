// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.policyloader;

import org.junit.jupiter.api.Test;
import tools.jackson.databind.ObjectMapper;

import java.nio.file.Path;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class PolicyCorpusReaderTest {

    @Test
    void readsTheVersionedSyntheticCorpusWithStableChunksAndRoles() {
        Path corpusPath = corpusPath();

        var corpus = new PolicyCorpusReader(new ObjectMapper()).read(corpusPath);

        assertThat(corpus.corpusId()).isEqualTo("POLICY-CORPUS-2026.0");
        assertThat(corpus.version()).isEqualTo("2026.0");
        assertThat(corpus.digest()).matches("[0-9a-f]{64}");
        assertThat(corpus.documents()).hasSize(9);
        assertThat(corpus.chunkCount()).isEqualTo(73);
        assertThat(corpus.documents()).flatExtracting(PolicyCorpusModels.PolicyDocument::chunks)
                .extracting(PolicyCorpusModels.PolicyChunk::chunkId).doesNotHaveDuplicates();

        var identityPolicy = corpus.documents().stream()
                .filter(document -> document.policyCode().equals("CBPL-110"))
                .findFirst().orElseThrow();
        assertThat(identityPolicy.chunks()).filteredOn(chunk -> chunk.sectionRef().equals("S3"))
                .extracting(PolicyCorpusModels.PolicyChunk::minRole).containsExactly("LOAN_OFFICER");
        assertThat(identityPolicy.chunks()).filteredOn(chunk -> chunk.sectionRef().equals("S4"))
                .extracting(PolicyCorpusModels.PolicyChunk::minRole).containsExactly("UNDERWRITER");
    }

    @Test
    void rejectsMissingCorpusDirectory() {
        assertThatThrownBy(() -> new PolicyCorpusReader(new ObjectMapper()).read(Path.of("missing-policy-corpus")))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("could not be read");
    }

    private static Path corpusPath() {
        Path repositoryRelative = Path.of("synthetic_data/policy").toAbsolutePath().normalize();
        if (repositoryRelative.toFile().isDirectory()) {
            return repositoryRelative;
        }
        return Path.of("../../synthetic_data/policy").toAbsolutePath().normalize();
    }
}
