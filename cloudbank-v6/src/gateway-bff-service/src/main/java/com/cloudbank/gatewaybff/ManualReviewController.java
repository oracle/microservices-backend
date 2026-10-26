// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.

package com.cloudbank.gatewaybff;

import com.cloudbank.gatewaybff.ApplicationCreationController.LoanCreationResponse;
import com.cloudbank.gatewaybff.MicroTxClient.Completion;
import com.cloudbank.gatewaybff.MicroTxClient.Task;
import com.fasterxml.jackson.annotation.JsonAnySetter;
import jakarta.servlet.http.HttpServletRequest;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.function.Supplier;
import java.util.stream.IntStream;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestClientResponseException;
import org.springframework.web.server.ResponseStatusException;

@RestController
class ManualReviewController {
    private static final String WORKFLOW = "cloudbank-loan-origination";
    private static final String TASK_REFERENCE = "human_task_manual_review";
    private static final List<String> OUTCOMES = List.of("APPROVED", "REJECTED");
    private static final Set<String> PENDING = Set.of("IN_PROGRESS", "SCHEDULED");
    private static final String ATTEMPTS = ManualReviewController.class.getName() + ".attempts";
    private final Object[] locks = IntStream.range(0, 64).mapToObj(i -> new Object()).toArray();
    private final SessionIdentity identity;
    private final MicroTxClient microtx;
    private final RestClient loan;

    ManualReviewController(SessionIdentity identity, MicroTxClient microtx,
            @Value("${cloudbank.bff.loan-base-url}") String loanBaseUrl, RestClient.Builder builder) {
        this.identity = identity;
        this.microtx = microtx;
        loan = builder.clone().baseUrl(loanBaseUrl).build();
    }

    @GetMapping("/bff/api/v1/manual-review/tasks")
    ResponseEntity<TaskPage> list(@RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size, Authentication authentication,
            HttpServletRequest request) {
        var user = identity.require(authentication, request);
        String correlation = correlate(request);
        if (page < 0 || page > 1000 || size < 1 || size > 50) throw failure(HttpStatus.BAD_REQUEST);
        return safe(() -> {
            List<TaskItem> authorized = new ArrayList<>();
            Set<String> seen = new HashSet<>();
            // Bound work and fail explicitly instead of returning misleading partial counts.
            for (int start = 0; start < 1000; start += 100) {
                var batch = microtx.pending(start, 100, correlation);
                if (batch == null || batch.results() == null || batch.totalHits() < 0
                        || batch.totalHits() > 1000 || batch.results().size() > 100) {
                    throw failure(HttpStatus.SERVICE_UNAVAILABLE);
                }
                for (var notification : batch.results()) {
                    if (notification == null || !WORKFLOW.equals(notification.workflowName())
                            || !pending(notification.status()) || !safeId(notification.taskId())
                            || !(TASK_REFERENCE.equals(notification.taskDefName())
                                || "human_task".equals(notification.taskDefName()))) continue;
                    if (!seen.add(notification.taskId())) continue;
                    try {
                        var context = context(notification.taskId(), user, correlation);
                        if (pending(context.task().status()) && "RUNNING".equals(context.workflow().status())) {
                            authorized.add(item(context));
                        }
                    } catch (ResponseStatusException unavailable) {
                        if (unavailable.getStatusCode().value() != 404) throw unavailable;
                    } catch (RestClientResponseException upstream) {
                        if (upstream.getStatusCode().value() != 404) throw upstream;
                    }
                }
                if (start + batch.results().size() >= batch.totalHits()) break;
                if (batch.results().isEmpty()) throw failure(HttpStatus.SERVICE_UNAVAILABLE);
            }
            authorized.sort(Comparator.comparing(TaskItem::scheduledAt,
                    Comparator.nullsLast(Comparator.naturalOrder())).thenComparing(TaskItem::taskId));
            int from = Math.min(page * size, authorized.size());
            int to = Math.min(from + size, authorized.size());
            return ok(new TaskPage(authorized.subList(from, to), new BffController.PageMetadata(
                    page, size, authorized.size(), (authorized.size() + size - 1L) / size)), correlation);
        });
    }

    @GetMapping("/bff/api/v1/manual-review/tasks/{taskId}")
    ResponseEntity<TaskDetail> detail(@PathVariable String taskId, Authentication authentication,
            HttpServletRequest request) {
        var user = identity.require(authentication, request);
        String correlation = correlate(request);
        requireTaskId(taskId);
        return safe(() -> {
            var context = context(taskId, user, correlation);
            if (!pending(context.task().status()) || !"RUNNING".equals(context.workflow().status())) {
                throw failure(HttpStatus.CONFLICT);
            }
            return ok(new TaskDetail(item(context), OUTCOMES, "DOCUMENT_EXCEPTION_RESOLVED", "CBPL-150-S4",
                    "UNDERWRITER", user.username(), correlation), correlation);
        });
    }

    @PostMapping("/bff/api/v1/manual-review/tasks/{taskId}/resolution")
    ResponseEntity<ResolutionReceipt> resolve(@PathVariable String taskId,
            @RequestHeader("Idempotency-Key") String key, @RequestBody Resolution resolution,
            Authentication authentication, HttpServletRequest request) {
        var reviewer = identity.requireReviewer(authentication, request);
        String correlation = correlate(request);
        requireTaskId(taskId);
        if (key == null || !key.matches("[A-Za-z0-9._:-]{8,200}") || resolution == null
                || resolution.decisionOutcome() == null || !OUTCOMES.contains(resolution.decisionOutcome())
                || resolution.reasonCode() == null || !resolution.reasonCode().matches("[A-Z0-9_:-]{3,120}")
                || resolution.policySection() == null || !resolution.policySection().matches("CBPL-[0-9]{3}-S[0-9]+")) {
            throw failure(HttpStatus.BAD_REQUEST);
        }
        Completion completion = new Completion(resolution.decisionOutcome(), "UNDERWRITER",
                reviewer.principalId(), resolution.reasonCode(), resolution.policySection());
        // The chart runs one BFF replica. Runtime task output reconciles retries after a session/process restart.
        synchronized (locks[Math.floorMod(taskId.hashCode(), locks.length)]) {
            return safe(() -> {
                var context = context(taskId, reviewer.user(), correlation);
                remember(request, key, new Attempt(taskId, completion));
                Task task = context.task();
                if ("COMPLETED".equals(task.status())) {
                    if (!completion.equals(task.outputData())) throw failure(HttpStatus.CONFLICT);
                } else {
                    if (!pending(task.status()) || !"RUNNING".equals(context.workflow().status())) {
                        throw failure(HttpStatus.CONFLICT);
                    }
                    try {
                        microtx.complete(task.workflowInstanceId(), completion, key, correlation);
                    } catch (RestClientException uncertain) {
                        // A timeout may happen after MicroTx commits. Read the durable task before suggesting retry.
                        Task latest = microtx.task(taskId, correlation);
                        if (latest == null || !taskId.equals(latest.taskId())
                                || !task.workflowInstanceId().equals(latest.workflowInstanceId())
                                || !"COMPLETED".equals(latest.status())) throw uncertain;
                        if (!completion.equals(latest.outputData())) throw failure(HttpStatus.CONFLICT);
                    }
                }
                return ResponseEntity.accepted().header("Cache-Control", "no-store")
                        .header("X-Correlation-ID", correlation).body(new ResolutionReceipt(taskId,
                                context.application().applicationId(), task.workflowInstanceId(),
                                "ACCEPTED", resolution.decisionOutcome(), correlation));
            });
        }
    }

    private Context context(String taskId, SessionIdentity.AuthorizedUser user, String correlation) {
        Task task = microtx.task(taskId, correlation);
        if (task == null || !taskId.equals(task.taskId()) || !"HUMAN".equals(task.taskType())
                || !TASK_REFERENCE.equals(task.referenceTaskName()) || !safeId(task.workflowInstanceId())
                || task.inputData() == null || task.inputData().applicationId() == null
                || !task.inputData().applicationId().matches("APP-[A-Za-z0-9][A-Za-z0-9-]{0,35}")) {
            throw failure(HttpStatus.NOT_FOUND);
        }
        LoanCreationResponse application;
        try {
            application = loan.get().uri("/api/v1/loan-applications/{id}", task.inputData().applicationId())
                    .headers(headers -> headers.setBearerAuth(user.accessToken()))
                    .header("X-Correlation-ID", correlation).retrieve().body(LoanCreationResponse.class);
        } catch (RestClientResponseException denied) {
            if (denied.getStatusCode().value() == 403 || denied.getStatusCode().value() == 404) {
                throw failure(HttpStatus.NOT_FOUND);
            }
            throw denied;
        }
        if (application == null || !task.inputData().applicationId().equals(application.applicationId())
                || application.workflow() == null
                || !task.workflowInstanceId().equals(application.workflow().workflowId())
                || !WORKFLOW.equals(application.workflow().workflowName())
                || application.workflow().workflowVersion() != 1) throw failure(HttpStatus.NOT_FOUND);
        var workflow = microtx.workflow(task.workflowInstanceId(), correlation);
        if (workflow == null || !task.workflowInstanceId().equals(workflow.workflowId())
                || !WORKFLOW.equals(workflow.workflowName()) || workflow.workflowVersion() != 1
                || workflow.input() == null || !application.applicationId().equals(workflow.input().applicationId())) {
            throw failure(HttpStatus.NOT_FOUND);
        }
        return new Context(task, workflow, application);
    }

    private static TaskItem item(Context context) {
        var input = context.task().inputData();
        String reason = switch (input.reviewRouteReason() == null ? "" : input.reviewRouteReason()) {
            case "DOCUMENT_REVIEW_REQUIRED", "GEOGRAPHIC_RISK_REVIEW_REQUIRED", "GEOGRAPHIC_RISK_NOT_EVALUATED",
                    "POLICY_EVIDENCE_INSUFFICIENT" -> input.reviewRouteReason();
            default -> "MANUAL_REVIEW_REQUIRED";
        };
        return new TaskItem(context.task().taskId(), context.application().applicationId(),
                context.application().scenarioId(), context.application().scenarioName(),
                context.task().workflowInstanceId(), TASK_REFERENCE, context.task().status(), "NORMAL",
                reason, switch (reason) {
                    case "DOCUMENT_REVIEW_REQUIRED" -> "Document evidence requires review";
                    case "GEOGRAPHIC_RISK_REVIEW_REQUIRED" -> "Geographic risk requires review";
                    case "GEOGRAPHIC_RISK_NOT_EVALUATED" -> "Geographic risk evidence is unavailable";
                    case "POLICY_EVIDENCE_INSUFFICIENT" -> "Policy evidence requires review";
                    default -> "Manual review required";
                }, instant(context.task().scheduledTime()), instant(context.task().updateTime()),
                reference(input.reviewId()), reference(input.documentSummaryId()),
                reference(input.manualReviewAssistanceId()), reference(input.initialDecisionId()));
    }

    @SuppressWarnings("unchecked")
    private static void remember(HttpServletRequest request, String key, Attempt attempt) {
        var session = request.getSession();
        synchronized (session) {
            Map<String, Attempt> attempts = (Map<String, Attempt>) session.getAttribute(ATTEMPTS);
            if (attempts == null) {
                attempts = new HashMap<>();
                session.setAttribute(ATTEMPTS, attempts);
            }
            if (attempts.containsKey(key) && !attempt.equals(attempts.get(key))) throw failure(HttpStatus.CONFLICT);
            if (!attempts.containsKey(key) && attempts.size() >= 100) throw failure(HttpStatus.SERVICE_UNAVAILABLE);
            attempts.putIfAbsent(key, attempt);
        }
    }

    private static <T> T safe(Supplier<T> action) {
        try {
            return action.get();
        } catch (RestClientResponseException upstream) {
            throw failure(switch (upstream.getStatusCode().value()) {
                case 403 -> HttpStatus.FORBIDDEN;
                case 404 -> HttpStatus.NOT_FOUND;
                case 409 -> HttpStatus.CONFLICT;
                case 429, 503 -> HttpStatus.SERVICE_UNAVAILABLE;
                default -> HttpStatus.BAD_GATEWAY;
            });
        } catch (RestClientException unavailable) {
            throw failure(HttpStatus.SERVICE_UNAVAILABLE);
        }
    }

    private static String correlate(HttpServletRequest request) {
        String id = UUID.randomUUID().toString();
        request.setAttribute("bffCorrelationId", id);
        return id;
    }

    private static boolean safeId(String value) { return value != null && value.matches("[A-Za-z0-9._:-]{1,128}"); }
    private static String reference(String value) { return safeId(value) ? value : null; }
    private static boolean pending(String value) { return value != null && PENDING.contains(value); }
    private static Instant instant(long value) { return value > 0 ? Instant.ofEpochMilli(value) : null; }
    private static void requireTaskId(String value) { if (!safeId(value)) throw failure(HttpStatus.BAD_REQUEST); }
    private static ResponseStatusException failure(HttpStatus status) { return new ResponseStatusException(status); }
    private static <T> ResponseEntity<T> ok(T body, String correlation) {
        return ResponseEntity.ok().header("Cache-Control", "no-store").header("X-Correlation-ID", correlation).body(body);
    }

    record Resolution(String decisionOutcome, String reasonCode, String policySection) {
        @JsonAnySetter
        void rejectUnknown(String name, Object value) { throw new IllegalArgumentException("Unsupported field"); }
    }
    record TaskPage(List<TaskItem> content, BffController.PageMetadata page) { }
    record TaskItem(String taskId, String applicationId, String scenarioId, String scenarioName, String workflowId,
            String taskReference, String status, String priority, String reasonCode, String reasonLabel,
            Instant scheduledAt, Instant updatedAt, String reviewId, String documentSummaryId,
            String manualReviewAssistanceId, String initialDecisionId) { }
    record TaskDetail(TaskItem task, List<String> allowedDecisionOutcomes, String defaultReasonCode,
            String defaultPolicySection, String reviewerRole, String reviewer, String correlationId) { }
    record ResolutionReceipt(String taskId, String applicationId, String workflowId, String completionStatus,
            String decisionOutcome, String correlationId) { }
    private record Context(Task task, MicroTxClient.Workflow workflow, LoanCreationResponse application) { }
    private record Attempt(String taskId, Completion completion) { }
}
