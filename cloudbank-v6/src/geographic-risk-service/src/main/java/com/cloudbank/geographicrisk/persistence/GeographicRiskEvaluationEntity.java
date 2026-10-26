// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.geographicrisk.persistence;

import com.cloudbank.geographicrisk.domain.Disposition;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

@Entity
@Table(schema = "CLOUDBANK", name = "cb_geographic_risk_evaluation")
public class GeographicRiskEvaluationEntity {

    private static final String SERVICE_NAME = "geographic-risk-service";

    @Id
    @Column(name = "evaluation_id", length = 80, nullable = false)
    private String evaluationId;

    @Column(name = "application_sk", nullable = false)
    private long applicationSk;

    @Column(name = "workflow_id", length = 100, nullable = false)
    private String workflowId;

    @Column(name = "task_reference", length = 120, nullable = false)
    private String taskReference;

    @Column(name = "trace_id", length = 32, nullable = false)
    private String traceId;

    @Column(name = "idempotency_key", length = 200, nullable = false)
    private String idempotencyKey;

    @Column(name = "request_hash", length = 64, nullable = false)
    private String requestHash;

    @Enumerated(EnumType.STRING)
    @Column(name = "disposition", length = 40, nullable = false)
    private Disposition disposition;

    @Column(name = "service_name", length = 80, nullable = false)
    private String serviceName;

    public GeographicRiskEvaluationEntity() {
    }

    public GeographicRiskEvaluationEntity(String evaluationId, long applicationSk, String workflowId,
            String taskReference, String traceId, String idempotencyKey, String requestHash,
            Disposition disposition) {
        this.evaluationId = evaluationId;
        this.applicationSk = applicationSk;
        this.workflowId = workflowId;
        this.taskReference = taskReference;
        this.traceId = traceId;
        this.idempotencyKey = idempotencyKey;
        this.requestHash = requestHash;
        this.disposition = disposition;
        this.serviceName = SERVICE_NAME;
    }

    public String evaluationId() {
        return evaluationId;
    }

    public long applicationSk() {
        return applicationSk;
    }

    public String workflowId() {
        return workflowId;
    }

    public String taskReference() {
        return taskReference;
    }

    public String traceId() {
        return traceId;
    }

    public String idempotencyKey() {
        return idempotencyKey;
    }

    public String requestHash() {
        return requestHash;
    }

    public Disposition disposition() {
        return disposition;
    }

}
