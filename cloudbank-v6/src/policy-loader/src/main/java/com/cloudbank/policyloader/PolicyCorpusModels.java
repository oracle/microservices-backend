// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.policyloader;

import java.time.LocalDate;
import java.util.List;

final class PolicyCorpusModels {
    private PolicyCorpusModels() {
    }

    record Corpus(String corpusId, String version, String digest, List<PolicyDocument> documents) {
        int chunkCount() {
            return documents.stream().mapToInt(document -> document.chunks().size()).sum();
        }
    }

    record ManifestDocument(String file, String policyId, String title, String domain) {
    }

    record PolicyDocument(String documentId, String policyCode, String title, String version, String sourcePath,
                          LocalDate effectiveDate, String domain, List<PolicyChunk> chunks) {
    }

    record PolicyChunk(String chunkId, String sectionRef, String heading, int ordinal, String text,
                       String minRole) {
    }

    record EmbeddedCorpus(Corpus corpus, String model, String region, int dimensions,
                          List<EmbeddedDocument> documents) {
    }

    record EmbeddedDocument(PolicyDocument document, List<float[]> embeddings) {
    }

    record ExistingLoad(String corpusId, String version, String digest, String model, Integer dimensions,
                        int documentCount, int chunkCount) {
    }
}
