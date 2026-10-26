// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.policyloader;

import com.cloudbank.policyretrieval.oci.AuthenticationProperties;
import com.cloudbank.policyretrieval.oci.EmbeddingProperties;
import com.cloudbank.policyretrieval.vector.EmbeddingModel;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.nio.file.Path;
import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

import static com.cloudbank.policyloader.PolicyCorpusModels.Corpus;
import static com.cloudbank.policyloader.PolicyCorpusModels.EmbeddedCorpus;
import static com.cloudbank.policyloader.PolicyCorpusModels.ExistingLoad;
import static com.cloudbank.policyloader.PolicyCorpusModels.PolicyChunk;
import static com.cloudbank.policyloader.PolicyCorpusModels.PolicyDocument;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class PolicyLoaderServiceTest {
    @Mock
    private PolicyCorpusReader reader;
    @Mock
    private PolicyLoaderRepository repository;
    @Mock
    private EmbeddingModel embeddingModel;

    @Test
    void matchingRecordedCorpusIsANoOpWithoutEmbeddingCalls() {
        Corpus corpus = corpus();
        ExistingLoad existing = new ExistingLoad(corpus.corpusId(), corpus.version(), corpus.digest(),
                "cohere.embed-v4.0", 1024, 1, 2);
        when(reader.read(Path.of("/app/policy"))).thenReturn(corpus);
        when(repository.findLoad(corpus.corpusId())).thenReturn(Optional.of(existing));

        service("cohere.embed-v4.0", 1024).run(null);

        verify(repository).verifyExisting(existing);
        verify(embeddingModel, never()).embed(org.mockito.ArgumentMatchers.<List<String>>any());
        verify(repository, never()).insert(org.mockito.ArgumentMatchers.any());
    }

    @Test
    void embedsEveryChunkAndPersistsTheModelIdentity() {
        Corpus corpus = corpus();
        when(reader.read(Path.of("/app/policy"))).thenReturn(corpus);
        when(repository.findLoad(corpus.corpusId())).thenReturn(Optional.empty());
        when(embeddingModel.embed(List.of("S1. Purpose\nFirst", "S2. Rule\nSecond")))
                .thenReturn(List.of(new float[] { 1.0f, 0.0f }, new float[] { 0.0f, 1.0f }));

        service("cohere.embed-v4.0", 2).run(null);

        ArgumentCaptor<EmbeddedCorpus> captor = ArgumentCaptor.forClass(EmbeddedCorpus.class);
        verify(repository).requireEmptyCorpusTables();
        verify(repository).insert(captor.capture());
        assertThat(captor.getValue().model()).isEqualTo("cohere.embed-v4.0");
        assertThat(captor.getValue().region()).isEqualTo("eu-frankfurt-1");
        assertThat(captor.getValue().dimensions()).isEqualTo(2);
        assertThat(captor.getValue().documents()).hasSize(1);
    }

    @Test
    void refusesToMixAnExistingCorpusWithAnotherModel() {
        Corpus corpus = corpus();
        when(reader.read(Path.of("/app/policy"))).thenReturn(corpus);
        when(repository.findLoad(corpus.corpusId())).thenReturn(Optional.of(new ExistingLoad(
                corpus.corpusId(), corpus.version(), corpus.digest(), "old-model", 2, 1, 2)));

        assertThatThrownBy(() -> service("new-model", 2).run(null))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("does not match");
        verify(embeddingModel, never()).embed(org.mockito.ArgumentMatchers.<List<String>>any());
    }

    private PolicyLoaderService service(String model, int dimensions) {
        PolicyLoaderProperties loader = new PolicyLoaderProperties();
        loader.setCorpusPath(Path.of("/app/policy"));
        EmbeddingProperties embedding = new EmbeddingProperties();
        embedding.setModel(model);
        embedding.setDimensions(dimensions);
        AuthenticationProperties authentication = new AuthenticationProperties();
        authentication.setRegion("eu-frankfurt-1");
        return new PolicyLoaderService(loader, reader, repository, embeddingModel, embedding, authentication);
    }

    private static Corpus corpus() {
        PolicyDocument document = new PolicyDocument("CBPL-100", "CBPL-100", "Policy", "2026.0",
                "synthetic_data/policy/CBPL-100.md", LocalDate.of(2026, 1, 1), "eligibility",
                List.of(new PolicyChunk("CBPL-100-S1-C01", "S1", "S1. Purpose", 1, "First", "LOAN_OFFICER"),
                        new PolicyChunk("CBPL-100-S2-C01", "S2", "S2. Rule", 2, "Second", "UNDERWRITER")));
        return new Corpus("POLICY-CORPUS-2026.0", "2026.0", "a".repeat(64), List.of(document));
    }
}
