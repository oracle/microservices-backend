// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.geographicrisk.persistence;

import io.helidon.data.Data;

import java.util.List;
import java.util.Optional;

@Data.Repository
public interface GeographicRiskEvaluationRepository
        extends Data.CrudRepository<GeographicRiskEvaluationEntity, String> {

    @Data.Query("SELECT e FROM GeographicRiskEvaluationEntity e WHERE e.applicationSk = :applicationSk "
            + "AND e.idempotencyKey = :idempotencyKey")
    Optional<GeographicRiskEvaluationEntity> findByIdempotency(long applicationSk, String idempotencyKey);

    @Data.Query("SELECT e FROM GeographicRiskEvaluationEntity e WHERE e.applicationSk = :applicationSk "
            + "ORDER BY e.evaluationId DESC")
    List<GeographicRiskEvaluationEntity> listByApplication(long applicationSk);
}
