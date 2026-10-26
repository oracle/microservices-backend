// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.policyloader;

import com.cloudbank.policyretrieval.oci.AuthenticationProperties;
import com.cloudbank.policyretrieval.oci.EmbeddingProperties;
import com.cloudbank.policyretrieval.vector.EmbeddingModel;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;

import java.util.ArrayList;
import java.util.List;

import static com.cloudbank.policyloader.PolicyCorpusModels.Corpus;
import static com.cloudbank.policyloader.PolicyCorpusModels.EmbeddedCorpus;
import static com.cloudbank.policyloader.PolicyCorpusModels.EmbeddedDocument;
import static com.cloudbank.policyloader.PolicyCorpusModels.ExistingLoad;
import static com.cloudbank.policyloader.PolicyCorpusModels.PolicyDocument;

@Service
class PolicyLoaderService implements ApplicationRunner {
    private static final Logger LOGGER = LoggerFactory.getLogger(PolicyLoaderService.class);

    private final PolicyLoaderProperties loaderProperties;
    private final PolicyCorpusReader corpusReader;
    private final PolicyLoaderRepository repository;
    private final EmbeddingModel embeddingModel;
    private final EmbeddingProperties embeddingProperties;
    private final AuthenticationProperties authenticationProperties;

    PolicyLoaderService(PolicyLoaderProperties loaderProperties, PolicyCorpusReader corpusReader,
                        PolicyLoaderRepository repository, EmbeddingModel embeddingModel,
                        EmbeddingProperties embeddingProperties, AuthenticationProperties authenticationProperties) {
        this.loaderProperties = loaderProperties;
        this.corpusReader = corpusReader;
        this.repository = repository;
        this.embeddingModel = embeddingModel;
        this.embeddingProperties = embeddingProperties;
        this.authenticationProperties = authenticationProperties;
    }

    @Override
    public void run(ApplicationArguments args) {
        Corpus corpus = corpusReader.read(loaderProperties.getCorpusPath());
        String model = embeddingProperties.getModel();
        if (!StringUtils.hasText(model)) {
            throw new IllegalStateException("OCI GenAI embedding model must be configured");
        }

        var existing = repository.findLoad(corpus.corpusId());
        if (existing.isPresent()) {
            verifySameLoad(existing.get(), corpus, model);
            repository.verifyExisting(existing.get());
            LOGGER.info("Policy corpus already loaded corpusId={} version={} documents={} chunks={} model={}",
                    corpus.corpusId(), corpus.version(), existing.get().documentCount(),
                    existing.get().chunkCount(), model);
            return;
        }

        repository.requireEmptyCorpusTables();
        List<EmbeddedDocument> embeddedDocuments = new ArrayList<>();
        int dimensions = -1;
        for (PolicyDocument document : corpus.documents()) {
            List<String> inputs = document.chunks().stream()
                    .map(chunk -> chunk.heading() + "\n" + chunk.text()).toList();
            List<float[]> embeddings = embeddingModel.embed(inputs);
            if (embeddings.size() != document.chunks().size()) {
                throw new IllegalStateException("OCI GenAI returned an unexpected embedding count");
            }
            for (float[] embedding : embeddings) {
                if (embedding == null || embedding.length == 0) {
                    throw new IllegalStateException("OCI GenAI returned an empty embedding");
                }
                if (dimensions < 0) {
                    dimensions = embedding.length;
                }
                else if (dimensions != embedding.length) {
                    throw new IllegalStateException("OCI GenAI returned inconsistent embedding dimensions");
                }
            }
            embeddedDocuments.add(new EmbeddedDocument(document, List.copyOf(embeddings)));
        }
        if (embeddingProperties.getDimensions() != null
                && embeddingProperties.getDimensions() != dimensions) {
            throw new IllegalStateException("OCI GenAI returned a dimension different from the configured value");
        }

        EmbeddedCorpus embedded = new EmbeddedCorpus(corpus, model, authenticationProperties.getRegion(), dimensions,
                List.copyOf(embeddedDocuments));
        repository.insert(embedded);
        LOGGER.info("Policy corpus loaded corpusId={} version={} documents={} chunks={} dimensions={} model={}",
                corpus.corpusId(), corpus.version(), corpus.documents().size(), corpus.chunkCount(), dimensions, model);
    }

    private void verifySameLoad(ExistingLoad load, Corpus corpus, String model) {
        if (!load.version().equals(corpus.version()) || !load.digest().equals(corpus.digest())
                || !load.model().equals(model) || load.documentCount() != corpus.documents().size()
                || load.chunkCount() != corpus.chunkCount()) {
            throw new IllegalStateException("existing policy corpus load does not match the packaged corpus and model");
        }
        if (embeddingProperties.getDimensions() != null
                && !embeddingProperties.getDimensions().equals(load.dimensions())) {
            throw new IllegalStateException("existing policy embeddings do not match the configured dimensions");
        }
    }
}
