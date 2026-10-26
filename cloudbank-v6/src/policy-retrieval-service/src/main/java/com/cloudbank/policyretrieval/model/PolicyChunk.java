// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.policyretrieval.model;

import java.time.OffsetDateTime;
import java.util.Map;
import java.util.Objects;

/**
 * Entity mapping for the {@code cb_policy_chunk} table.
 */
public record PolicyChunk(
        Long id,                                 // primary key / identifier
        Long policyDocumentSk,                   // reference to the owning document
        String policyDocumentId,                 // policy document id
        String chunkId,                          // unique within a document
        String sectionRef,                       // e.g. "SEC‑01"
        String heading,                          // chunk title
        Integer ordinal,                         // position within the section
        String chunkText,                        // plain text of the chunk
        Map<String, Object> metadataJson,        // optional JSON blob (e.g., extra attributes)
        PolicyRole minRole,                      // lowest role that can view – default LOAN_OFFICER
        String accessLabel,                      // e.g. "policy" – default “policy”
        AiUse aiUse,                             // AI use case – default RETRIEVAL
        float[] embedding,                       // optional vector embedding
        OffsetDateTime createdAt                 // creation timestamp
) {
    public static PolicyChunk of(
            Long id,
            Long policyDocumentSk,
            String policyDocumentId,
            String chunkId,
            String sectionRef,
            String heading,
            Integer ordinal,
            String chunkText,
            Map<String, Object> metadataJson,
            PolicyRole minRole,
            String accessLabel,
            AiUse aiUse,
            float[] embedding,
            OffsetDateTime createdAt) {

        return new PolicyChunk(
                id,
                policyDocumentSk,
                policyDocumentId,
                chunkId,
                sectionRef,
                heading,
                ordinal,
                chunkText,
                metadataJson,
                // apply defaults
                minRole != null ? minRole : PolicyRole.LOAN_OFFICER,
                accessLabel != null ? accessLabel : "policy",
                aiUse != null ? aiUse : AiUse.RETRIEVAL,
                embedding,
                createdAt);
    }

    @Override
    public boolean equals(Object o) {
        if (o == null || getClass() != o.getClass()) return false;
        PolicyChunk that = (PolicyChunk) o;
        return Objects.equals(id(), that.id());
    }

    @Override
    public int hashCode() {
        return Objects.hashCode(id());
    }
}
