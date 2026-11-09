// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.
package com.cloudbank.gatewaybff;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.Map;

final class WorkspaceReadModels {
    private WorkspaceReadModels() { }
    record Items<T>(List<T> items, boolean truncated) { }
    record AiTasks(List<AiTask> items, boolean truncated) { }
    record AiTask(String taskReference, String name, String implementationMode, String status,
            ApplicationWorkspaceController.Section<AiResult> result) { }
    @JsonIgnoreProperties(ignoreUnknown = true)
    record AiResult(String applicationId, String workflowId, String taskReference, String resultId,
            String provider, String model, String guardrailStatus, String summary, List<String> notes,
            List<String> checklist, List<String> clarificationQuestions, List<SourceReference> sourceReferences) { }
    @JsonIgnoreProperties(ignoreUnknown = true)
    record SourceReference(String sourceType, String sourceId) { }
    @JsonIgnoreProperties(ignoreUnknown = true)
    record Decisions(String applicationId, String workflowId, List<DecisionEntry> items, boolean truncated) { }
    @JsonIgnoreProperties(ignoreUnknown = true)
    record DecisionEntry(DecisionResult result, PaymentFacts paymentFacts) { }
    @JsonIgnoreProperties(ignoreUnknown = true)
    record DecisionResult(String decisionId, String applicationId, String workflowId, String taskReference,
            String decisionType, String outcome, String riskBand, String policyVersion, String ruleProfileVersion,
            String decisionSource, List<String> reasonCodes, List<PolicyCitation> policyCitations, String traceId) { }
    @JsonIgnoreProperties(ignoreUnknown = true)
    record PolicyCitation(String chunkId, String policyCode, String sectionRef) { }
    @JsonIgnoreProperties(ignoreUnknown = true)
    record PaymentFacts(String currency, BigDecimal evaluatedAmount, Integer termMonths,
            BigDecimal monthlyPayment, String calculationStatus) { }
    record PolicyEvidence(String workflowId, String retrievalReference, List<PolicyChunk> items, boolean truncated) { }
    record PolicyChunk(String policyDocumentId, String policyCode, String policyVersion, String chunkId,
            String sectionRef, String heading, String excerpt, boolean truncated) { }
    record Risks(ApplicationWorkspaceController.Section<Geographic> geographic,
            ApplicationWorkspaceController.Section<Void> identity,
            ApplicationWorkspaceController.Section<Void> relationship,
            ApplicationWorkspaceController.Section<Void> graph) { }
    @JsonIgnoreProperties(ignoreUnknown = true)
    record Geographic(String applicationId, String workflowId, String taskReference, String evaluationId,
            String disposition, List<GeographicSignal> signals) { }
    @JsonIgnoreProperties(ignoreUnknown = true)
    record GeographicSignal(String signalCode, String label, String signalResult, String routingEffect,
            String zoneId, String zoneName, BigDecimal distanceToBoundaryMeters) { }
    record Workflow(String dispatchStatus, String workflowId, String workflowName, Integer workflowVersion,
            String executionStatus, List<TimelineTask> items, boolean truncated, String humanTaskId,
            String humanTaskStatus) { }
    record TimelineTask(String taskId, String taskReference, String name, String status, Instant scheduledAt,
            Instant startedAt, Instant endedAt, Integer retryCount) { }
    @JsonIgnoreProperties(ignoreUnknown = true)
    record Audit(String applicationId, List<AuditEvent> items, Boolean truncated) { }
    @JsonIgnoreProperties(ignoreUnknown = true)
    record AuditEvent(String eventId, Instant occurredAt, String action, String actionLabel,
            String actorLabel, String outcome, String objectType, String objectId, String traceId) { }
    record Trace(String applicationId, String workflowId, String traceId, String signozUrl,
            ApplicationWorkspaceController.Section<TraceSpans> spans) { }
    record TraceSpans(List<TraceSpan> items, boolean truncated, Long totalSpans, boolean hasMissingSpans) { }
    record TraceSpan(String spanId, String parentSpanId, String service, String name, Instant startedAt,
            BigDecimal durationMs, String status, Map<String, String> attributes) { }
}
