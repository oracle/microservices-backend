// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.policyretrieval.model;

import java.sql.Date;
import java.time.OffsetDateTime;
import java.util.Objects;

/**
 * Entity mapping for the {@code cb_policy_document} table.
 * <p>
 * All column constraints mirror the DDL from the repository. The Java enums below
 * provide a type‑safe representation of the limited value sets used by Oracle's
 * CHECK constraints.
 */
public record PolicyDocument(
        Long id,                                 // primary key / identifier
        String documentId,                       // unique document reference
        String policyCode,                       // e.g. "CB‑001"
        String title,                            // human‑readable title
        String version,                          // default “2026.0”
        String sourcePath,                       // filesystem or object store path
        Date effectiveDate,                      // when the policy becomes active
        ReviewStatus reviewStatus,               // REVIEW_STATUS enum – default APPROVED
        PolicyRole ownerRole,                    // lowest role that owns it – default UNDERWRITER
        DataClassification classification,      // default RESTRICTED_POLICY
        byte[] metadataJson,                     // optional JSON blob (e.g., tags)
        OffsetDateTime createdAt                 // timestamp of creation
) {
    public static PolicyDocument of(
            Long id,
            String documentId,
            String policyCode,
            String title,
            String version,
            String sourcePath,
            Date effectiveDate,
            ReviewStatus reviewStatus,
            PolicyRole ownerRole,
            DataClassification classification,
            byte[] metadataJson,
            OffsetDateTime createdAt) {

        return new PolicyDocument(
                id,
                documentId,
                policyCode,
                title,
                version != null ? version : "2026.0",
                sourcePath,
                effectiveDate,
                reviewStatus != null ? reviewStatus : ReviewStatus.APPROVED,
                ownerRole != null ? ownerRole : PolicyRole.UNDERWRITER,
                classification != null
                        ? classification
                        : DataClassification.RESTRICTED_POLICY,
                metadataJson,
                createdAt);
    }

    @Override
    public boolean equals(Object o) {
        if (o == null || getClass() != o.getClass()) return false;
        PolicyDocument that = (PolicyDocument) o;
        return Objects.equals(id(), that.id());
    }

    @Override
    public int hashCode() {
        return Objects.hashCode(id());
    }
}
