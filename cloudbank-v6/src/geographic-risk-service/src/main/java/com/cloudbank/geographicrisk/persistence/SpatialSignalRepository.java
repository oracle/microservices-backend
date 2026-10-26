// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.geographicrisk.persistence;

import io.helidon.data.Data;

import java.util.List;

@Data.Repository
public interface SpatialSignalRepository extends Data.CrudRepository<SpatialSignalEntity, String> {

    @Data.Query("SELECT s FROM SpatialSignalEntity s WHERE s.geographicEvaluationId = :evaluationId "
            + "ORDER BY s.spatialSignalSk")
    List<SpatialSignalEntity> listByEvaluation(String evaluationId);
}
