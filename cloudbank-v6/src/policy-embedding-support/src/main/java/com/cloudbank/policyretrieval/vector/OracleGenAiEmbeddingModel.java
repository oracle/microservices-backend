/*
 * Copyright (c) 2026, Oracle and/or its affiliates.
 * Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/
 */

package com.cloudbank.policyretrieval.vector;

import com.cloudbank.policyretrieval.oci.OracleGenAiEmbeddingOptions;
import com.cloudbank.policyretrieval.oci.api.OracleGenAiEmbeddingTruncate;
import com.oracle.bmc.generativeaiinference.GenerativeAiInference;
import com.oracle.bmc.generativeaiinference.model.EmbedTextDetails;
import com.oracle.bmc.generativeaiinference.model.EmbedTextResult;
import com.oracle.bmc.generativeaiinference.requests.EmbedTextRequest;
import com.oracle.bmc.generativeaiinference.responses.EmbedTextResponse;
import com.oracle.bmc.model.BmcException;
import org.jspecify.annotations.Nullable;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.util.CollectionUtils;
import org.springframework.util.StringUtils;

import java.util.ArrayList;
import java.util.List;
import java.util.Objects;
import java.util.concurrent.TimeUnit;

/**
 * Spring AI embedding model backed by OCI Generative AI.
 */
public class OracleGenAiEmbeddingModel implements EmbeddingModel {

    private static final Logger LOGGER = LoggerFactory.getLogger(OracleGenAiEmbeddingModel.class);

    private final GenerativeAiInference client;

    private final OracleGenAiEmbeddingOptions options;

    public static Builder builder() {
        return new Builder();
    }

    private OracleGenAiEmbeddingModel(@Nullable GenerativeAiInference client,
            @Nullable OracleGenAiEmbeddingOptions defaultOptions) {
        this.client = Objects.requireNonNull(client, "client must not be null");
        this.options = Objects.requireNonNull(defaultOptions, "defaultOptions must not be null");
    }

    @Override
    public List<float[]> embed(List<String> chunks) {
        EmbedTextRequest ociRequest = toEmbedTextRequest(chunks);
        long startedAt = System.nanoTime();
        LOGGER.info(
                "OCI GenAI EmbedText request started inputCount={} totalCharacters={} maxInputCharacters={} "
                        + "servingMode={} model={} requestedDimensions={} truncate={}",
                chunks.size(), totalCharacters(chunks), maxInputCharacters(chunks), options.getServingMode(),
                options.getModel(), options.getDimensions(), options.getTruncate());
        try {
            EmbedTextResponse embedTextResponse = client.embedText(ociRequest);
            List<float[]> embeddings = toEmbeddingResponse(embedTextResponse);
            LOGGER.info(
                    "OCI GenAI EmbedText response received requestId={} embeddingCount={} dimensions={} durationMs={}",
                    embedTextResponse.getOpcRequestId(), embeddings.size(), embeddings.getFirst().length,
                    elapsedMilliseconds(startedAt));
            return embeddings;
        }
        catch (BmcException exception) {
            LOGGER.warn(
                    "OCI GenAI EmbedText request failed statusCode={} serviceCode={} requestId={} timeout={} "
                            + "clientSide={} durationMs={}",
                    exception.getStatusCode(), exception.getServiceCode(), exception.getOpcRequestId(),
                    exception.isTimeout(), exception.isClientSide(), elapsedMilliseconds(startedAt));
            throw exception;
        }
        catch (RuntimeException exception) {
            LOGGER.warn("OCI GenAI EmbedText request failed exceptionType={} durationMs={}",
                    exception.getClass().getSimpleName(), elapsedMilliseconds(startedAt));
            throw exception;
        }
    }

    @Override
    public float[] embed(String chunk) {
        return embed(List.of(chunk)).getFirst();
    }

    EmbedTextRequest toEmbedTextRequest(List<String> chunks) {
        options.validate();
        validateInputs(chunks);
        EmbedTextDetails details = EmbedTextDetails.builder()
                .compartmentId(options.getCompartmentId())
                .servingMode(options.toServingMode())
                .inputs(chunks)
                .outputDimensions(options.getDimensions())
                .truncate(toTruncate(options.getTruncate()))
                .build();
        return EmbedTextRequest.builder().embedTextDetails(details).build();
    }

    private List<float[]> toEmbeddingResponse(EmbedTextResponse response) {
        EmbedTextResult result = response.getEmbedTextResult();
        if (result == null) {
            throw new IllegalStateException("OCI Generative AI embedding response did not contain an embedding result.");
        }
        if (CollectionUtils.isEmpty(result.getEmbeddings())) {
            throw new IllegalStateException("OCI Generative AI embedding response did not contain embeddings.");
        }
        List<float[]> embeddings = new ArrayList<>(result.getEmbeddings().size());
        for (int index = 0; index < result.getEmbeddings().size(); index++) {
            embeddings.add(toFloatArray(result.getEmbeddings().get(index), index));
        }
        return embeddings;
    }

    private static float[] toFloatArray(List<Float> vector, int index) {
        if (vector == null) {
            throw new IllegalStateException("OCI Generative AI embedding response contained a null embedding at index "
                    + index + ".");
        }
        float[] result = new float[vector.size()];
        for (int i = 0; i < vector.size(); i++) {
            Float value = vector.get(i);
            if (value == null) {
                throw new IllegalStateException("OCI Generative AI embedding response contained a null value at embedding "
                        + index + ", vector position " + i + ".");
            }
            result[i] = value;
        }
        return result;
    }

    private static void validateInputs(List<String> inputs) {
        if (CollectionUtils.isEmpty(inputs)) {
            throw new IllegalArgumentException("Embedding inputs must not be empty.");
        }
        for (String input : inputs) {
            if (!StringUtils.hasText(input)) {
                throw new IllegalArgumentException("Embedding input text must not be empty.");
            }
        }
    }

    private static long totalCharacters(List<String> inputs) {
        return inputs.stream().mapToLong(String::length).sum();
    }

    private static int maxInputCharacters(List<String> inputs) {
        return inputs.stream().mapToInt(String::length).max().orElse(0);
    }

    private static long elapsedMilliseconds(long startedAt) {
        return TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - startedAt);
    }

    private static EmbedTextDetails.Truncate toTruncate(OracleGenAiEmbeddingTruncate truncate) {
        if (truncate == null || truncate == OracleGenAiEmbeddingTruncate.NONE) {
            return EmbedTextDetails.Truncate.None;
        }
        if (truncate == OracleGenAiEmbeddingTruncate.START) {
            return EmbedTextDetails.Truncate.Start;
        }
        return EmbedTextDetails.Truncate.End;
    }

    public static final class Builder {

        @Nullable
        private GenerativeAiInference client;

        @Nullable
        private OracleGenAiEmbeddingOptions defaultOptions;

        private Builder() {
        }

        public Builder client(GenerativeAiInference client) {
            this.client = client;
            return this;
        }

        public Builder defaultOptions(OracleGenAiEmbeddingOptions defaultOptions) {
            this.defaultOptions = defaultOptions;
            return this;
        }

        public OracleGenAiEmbeddingModel build() {
            return new OracleGenAiEmbeddingModel(client, defaultOptions);
        }
    }
}
