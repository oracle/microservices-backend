// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.
package com.cloudbank.gatewaybff;

import static com.cloudbank.gatewaybff.WorkspaceReadModels.*;

import com.cloudbank.gatewaybff.ApplicationWorkspaceController.Section;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.Executors;
import java.util.function.Supplier;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;

/** Explicit browser projection. Runtime JSON and owner persistence objects never leave this class. */
@Service
class WorkspaceReadService {
    private static final Set<String> TERMINAL = Set.of("COMPLETED", "FAILED", "TERMINATED", "TIMED_OUT");
    private static final Set<String> TASKS = Set.of("init_workflow_authorization", "document_extraction_review_loop",
            "extract_documents", "review_documents", "normalize_review_disposition", "select_final_review",
            "route_review_disposition", "continue_clear_review", "continue_manual_review", "terminate_retry_exhausted",
            "terminate_blocked", "terminate_unexpected_review_disposition", "ai_document_evidence_summary",
            "normalize_document_summary", "policy_evidence_retrieval", "prepare_policy_evidence_support",
            "ai_policy_evidence_support", "evaluate_geographic_risk", "derive_post_evidence_disposition",
            "route_post_evidence_disposition", "terminate_post_evidence_blocked", "prepare_decision_policy_citations",
            "deterministic_initial_decision", "route_initial_decision", "complete_approved_path", "complete_rejected_path",
            "ai_manual_review_assistant", "normalize_manual_review_assistance", "human_task_manual_review",
            "validate_manual_review_completion", "route_manual_review_completion", "terminate_invalid_manual_review_completion",
            "manual_review_completion_valid", "refresh_workflow_authorization", "use_refreshed_authorization",
            "deterministic_manual_final_decision", "terminate_unexpected_decision_outcome", "select_final_decision");
    private final MicroTxClient microtx;
    private final WorkspaceOwnerClient owners;
    private final ObjectMapper json;

    WorkspaceReadService(MicroTxClient microtx, WorkspaceOwnerClient owners, ObjectMapper json) {
        this.microtx = microtx; this.owners = owners; this.json = json;
    }

    record Sections(Section<AiTasks> ai, Section<Decisions> decision, Section<PolicyEvidence> policy,
            Section<Risks> risk, Section<Workflow> workflow) { }
    private record Snapshot(String applicationId, String workflowId, String status, List<JsonNode> tasks) { }

    Sections compose(String applicationId, String workflowId, String dispatch, String correlation) {
        if (workflowId == null || workflowId.isBlank()) {
            var tasks = List.of(pendingTask("ai_document_evidence_summary", "Document Evidence Summary", "Spring AI / OCI GenAI"),
                    pendingTask("ai_policy_evidence_support", "Policy Evidence Support", "Deterministic adapter"),
                    pendingTask("ai_manual_review_assistant", "Manual Review Assistant", "Spring AI / OCI GenAI"));
            return new Sections(Section.available(new AiTasks(tasks, false)), Section.pending("No decision has been produced yet."),
                    Section.pending("Policy retrieval has not run yet."), Section.available(risks(Section.pending("Geographic evaluation has not run yet."))),
                    Section.available(new Workflow(dispatch, null, "cloudbank-loan-origination", 1, "NOT_STARTED",
                            List.of(), false, null, null)));
        }
        if (!workflowId.matches("[A-Za-z0-9._:-]{1,100}")) {
            return new Sections(Section.error(), Section.error(), Section.error(), Section.error(), Section.error());
        }
        Snapshot execution = null;
        try { execution = snapshot(applicationId, workflowId, correlation); } catch (RuntimeException ignored) {
            // Failure is projected per section, without logging upstream bodies or exception messages.
        }
        final Snapshot current = execution;
        try (var executor = Executors.newVirtualThreadPerTaskExecutor()) {
            var summary = CompletableFuture.supplyAsync(() -> ai(current, "ai_document_evidence_summary",
                    "Document Evidence Summary", "Spring AI / OCI GenAI", "summaryId", correlation), executor);
            var policySupport = CompletableFuture.supplyAsync(() -> ai(current, "ai_policy_evidence_support",
                    "Policy Evidence Support", "Deterministic adapter", "policySupportId", correlation), executor);
            var assistant = CompletableFuture.supplyAsync(() -> ai(current, "ai_manual_review_assistant",
                    "Manual Review Assistant", "Spring AI / OCI GenAI", "assistanceId", correlation), executor);
            var decision = CompletableFuture.supplyAsync(() -> section(() -> decisions(applicationId, workflowId, current, correlation)), executor);
            var geographic = CompletableFuture.supplyAsync(() -> section(() -> geographic(current, correlation)), executor);
            Section<PolicyEvidence> policy = section(() -> policy(current));
            Section<Workflow> workflow = current == null ? Section.error() : section(() -> Section.available(timeline(current, dispatch)));
            return new Sections(Section.available(new AiTasks(List.of(summary.join(), policySupport.join(), assistant.join()), false)),
                    decision.join(), policy, Section.available(risks(geographic.join())), workflow);
        }
    }

    private Snapshot snapshot(String applicationId, String workflowId, String correlation) {
        JsonNode value = microtx.execution(workflowId, correlation, json);
        require(workflowId.equals(text(value, "workflowId", 100))
                && "cloudbank-loan-origination".equals(text(value, "workflowName", 100))
                && value.path("workflowVersion").asInt() == 1
                && applicationId.equals(text(value.path("input"), "applicationId", 40)));
        JsonNode tasks = value.path("tasks");
        require(tasks.isArray() && tasks.size() <= 1000);
        List<JsonNode> selected = new ArrayList<>();
        for (JsonNode task : tasks) {
            String reference = text(task, "referenceTaskName", 150);
            String base = reference.replaceFirst("__[0-9]+$", "");
            if (!TASKS.contains(base)) continue;
            require(workflowId.equals(text(task, "workflowInstanceId", 100)));
            state(task);
            require(text(task, "taskId", 100).matches("[A-Za-z0-9._:-]{1,100}"));
            selected.add(task);
        }
        String status = text(value, "status", 40);
        require(Set.of("RUNNING", "PAUSED", "COMPLETED", "FAILED", "TERMINATED", "TIMED_OUT").contains(status));
        return new Snapshot(applicationId, workflowId, status, List.copyOf(selected));
    }

    private AiTask ai(Snapshot execution, String reference, String name, String mode, String idField, String correlation) {
        if (execution == null) return new AiTask(reference, name, mode, "UNKNOWN", Section.error());
        JsonNode task = task(execution, reference);
        String state = task == null ? "NOT_EXECUTED" : state(task);
        Section<AiResult> result = section(() -> {
            if (task == null || !"COMPLETED".equals(state)) return absent(execution, task, "AI result");
            JsonNode body = task.path("outputData").path("response").path("body");
            String id = text(body, idField, 80);
            require(id.matches("(?:AISUM|AIPOL|AIREV)-[0-9a-fA-F]{32}"));
            AiResult value = owners.read("ai", "/ai-results/{id}", execution.applicationId(), execution.workflowId(), id,
                    correlation, AiResult.class);
            require(execution.applicationId().equals(value.applicationId()) && execution.workflowId().equals(value.workflowId())
                    && reference.equals(value.taskReference()) && id.equals(value.resultId()) && "PASSED".equals(value.guardrailStatus()));
            safe(value.provider(), 80); safe(value.model(), 200);
            if (value.summary() != null) safe(value.summary(), 1500);
            strings(value.notes(), 8, 1000); strings(value.checklist(), 12, 1000); strings(value.clarificationQuestions(), 8, 1000);
            require(value.sourceReferences() != null && value.sourceReferences().size() <= 100);
            value.sourceReferences().forEach(source -> { safe(source.sourceType(), 80); safe(source.sourceId(), 120); });
            return Section.available(value);
        });
        return new AiTask(reference, name, mode, state, result);
    }

    private Section<Decisions> decisions(String app, String workflow, Snapshot execution, String correlation) {
        Decisions value = owners.read("decision", "/decisions", app, workflow, "", correlation, Decisions.class);
        require(app.equals(value.applicationId()) && workflow.equals(value.workflowId()) && value.items() != null && value.items().size() <= 2);
        for (DecisionEntry entry : value.items()) {
            DecisionResult result = entry.result();
            require(result != null && app.equals(result.applicationId()) && workflow.equals(result.workflowId())
                    && result.decisionId().matches("DEC-[0-9a-f]{32}")
                    && Set.of("INITIAL", "MANUAL_FINAL").contains(result.decisionType())
                    && Set.of("APPROVED", "REJECTED", "MANUAL_REVIEW").contains(result.outcome()));
            safe(result.riskBand(), 40); safe(result.policyVersion(), 80); safe(result.ruleProfileVersion(), 80);
            safe(result.decisionSource(), 80); safe(result.taskReference(), 120);
            require(result.traceId() == null || result.traceId().matches("[0-9a-fA-F]{32}"));
            strings(result.reasonCodes(), 100, 120);
            require(result.policyCitations() != null && result.policyCitations().size() <= 10);
            result.policyCitations().forEach(citation -> { safe(citation.chunkId(), 100); safe(citation.policyCode(), 40); safe(citation.sectionRef(), 80); });
            if (entry.paymentFacts() != null) {
                require("USD".equals(entry.paymentFacts().currency()));
                if (entry.paymentFacts().calculationStatus() != null) safe(entry.paymentFacts().calculationStatus(), 80);
            }
        }
        if (value.items().isEmpty()) return execution == null || TERMINAL.contains(execution.status())
                ? Section.missing("No stored decision is available for this execution.") : Section.pending("Decision processing has not produced a result yet.");
        return Section.available(value);
    }

    private Section<PolicyEvidence> policy(Snapshot execution) {
        if (execution == null) return Section.error();
        JsonNode prepared = task(execution, "prepare_policy_evidence_support");
        if (prepared == null || !"COMPLETED".equals(state(prepared))) return absent(execution, prepared, "Policy evidence");
        JsonNode evidence = prepared.path("outputData").path("result").path("policyEvidence");
        require(evidence.isArray() && evidence.size() <= 3);
        List<PolicyChunk> chunks = new ArrayList<>();
        for (JsonNode item : evidence) {
            String content = text(item, "content", 4000);
            chunks.add(new PolicyChunk(text(item, "policyDocumentId", 80), text(item, "policyCode", 40),
                    text(item, "policyVersion", 40), text(item, "chunkId", 100), text(item, "sectionRef", 80),
                    text(item, "heading", 200), content.substring(0, Math.min(1000, content.length())), content.length() > 1000));
        }
        JsonNode retrieval = task(execution, "policy_evidence_retrieval");
        return Section.available(new PolicyEvidence(execution.workflowId(), retrieval == null ? null : text(retrieval, "taskId", 100), chunks, false));
    }

    private Section<Geographic> geographic(Snapshot execution, String correlation) {
        if (execution == null) return Section.error();
        JsonNode task = task(execution, "evaluate_geographic_risk");
        if (task == null || !"COMPLETED".equals(state(task))) return absent(execution, task, "Geographic evaluation");
        String id = text(task.path("outputData").path("response").path("body"), "evaluationId", 80);
        require(id.matches("GEO-EVAL-[A-Za-z0-9-]{1,70}"));
        Geographic value = owners.read("geographic", "/geographic-risk/{id}", execution.applicationId(), execution.workflowId(), id,
                correlation, Geographic.class);
        require(execution.applicationId().equals(value.applicationId()) && execution.workflowId().equals(value.workflowId())
                && id.equals(value.evaluationId()) && "evaluate_geographic_risk".equals(value.taskReference())
                && Set.of("CLEAR", "MANUAL_REVIEW", "BLOCKED", "NOT_EVALUATED").contains(value.disposition())
                && value.signals() != null && value.signals().size() <= 100);
        value.signals().forEach(signal -> { safe(signal.signalCode(), 100); safe(signal.label(), 300);
            safe(signal.signalResult(), 40); safe(signal.routingEffect(), 40);
            if (signal.zoneId() != null) safe(signal.zoneId(), 100); if (signal.zoneName() != null) safe(signal.zoneName(), 200); });
        return Section.available(value);
    }

    private Workflow timeline(Snapshot execution, String dispatch) {
        List<TimelineTask> items = new ArrayList<>();
        String humanId = null; String humanStatus = null;
        for (JsonNode task : execution.tasks()) {
            String ref = text(task, "referenceTaskName", 150);
            String id = text(task, "taskId", 100);
            if ("human_task_manual_review".equals(ref)) { humanId = id; humanStatus = state(task); }
            if (items.size() == 100) continue;
            items.add(new TimelineTask(id, ref, label(ref), state(task), instant(task, "scheduledTime"),
                    instant(task, "startTime"), instant(task, "endTime"), Math.max(0, task.path("retryCount").asInt())));
        }
        return new Workflow(dispatch, execution.workflowId(), "cloudbank-loan-origination", 1, execution.status(),
                items, execution.tasks().size() > 100, humanId, humanStatus);
    }

    private static AiTask pendingTask(String ref, String name, String mode) {
        return new AiTask(ref, name, mode, "NOT_EXECUTED", Section.pending("This task has not run yet."));
    }
    private static Risks risks(Section<Geographic> geographic) {
        return new Risks(geographic, Section.unavailable("Identity-risk evaluation is not implemented."),
                Section.unavailable("Relationship-risk evaluation is not implemented."), Section.unavailable("Graph-risk evaluation is not implemented."));
    }
    private static JsonNode task(Snapshot value, String reference) {
        JsonNode result = null;
        for (JsonNode task : value.tasks()) if (reference.equals(task.path("referenceTaskName").asText())) result = task;
        return result;
    }
    private static <T> Section<T> absent(Snapshot value, JsonNode task, String name) {
        if (task != null && Set.of("FAILED", "FAILED_WITH_TERMINAL_ERROR", "TIMED_OUT", "CANCELED", "SKIPPED", "COMPLETED_WITH_ERRORS").contains(state(task)))
            return Section.missing(name + " was not produced by this task.");
        if (TERMINAL.contains(value.status())) return Section.missing(name + " was not produced on this execution path.");
        return Section.pending(name + " has not been produced yet.");
    }
    private static <T> Section<T> section(Supplier<Section<T>> read) {
        try { return read.get(); } catch (ResponseStatusException error) {
            return error.getStatusCode().value() == 404 ? Section.missing("The stored result is not available. Process-local AI results may be unavailable after a restart, cache eviction, or a change of replica. Reloading cannot recreate a lost cached result.") : Section.error();
        } catch (RuntimeException error) { return Section.error(); }
    }
    private static String state(JsonNode task) {
        String value = text(task, "status", 40);
        require(Set.of("SCHEDULED", "IN_PROGRESS", "COMPLETED", "COMPLETED_WITH_ERRORS", "FAILED", "FAILED_WITH_TERMINAL_ERROR",
                "TIMED_OUT", "CANCELED", "SKIPPED", "READY_FOR_RERUN").contains(value));
        return value;
    }
    private static String text(JsonNode node, String key, int max) {
        JsonNode value = node.path(key); require(value.isString());
        String result = value.asText(); safe(result, max); return result;
    }
    private static void strings(List<String> values, int count, int max) {
        require(values != null && values.size() <= count); values.forEach(value -> safe(value, max));
    }
    private static void safe(String value, int max) {
        require(value != null && value.length() <= max && !value.matches("(?s).*[\\x00-\\x08\\x0b\\x0c\\x0e-\\x1f].*")
                && !value.matches("(?is).*(?:bearer\\s+[A-Za-z0-9._-]{12,}|workflowTaskAuthorization|-----BEGIN .*PRIVATE KEY).*")
                && !value.matches("(?s).*[A-Za-z0-9_-]{16,}\\.[A-Za-z0-9_-]{16,}\\.[A-Za-z0-9_-]{16,}.*"));
    }
    private static Instant instant(JsonNode node, String field) {
        long value = node.path(field).asLong(); return value > 0 ? Instant.ofEpochMilli(value) : null;
    }
    private static String label(String reference) { return reference.replaceAll("__[0-9]+$", "").replace('_', ' '); }
    private static void require(boolean condition) { if (!condition) throw new IllegalArgumentException("Invalid owner read projection"); }
}
