// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.loanapplication.persistence;

import static com.cloudbank.loanapplication.persistence.LoanRecords.ApplicationRow;
import static com.cloudbank.loanapplication.persistence.LoanRecords.DocumentRow;
import static com.cloudbank.loanapplication.persistence.LoanRecords.DocumentContentRow;
import static com.cloudbank.loanapplication.persistence.LoanRecords.DocumentProcessingRow;
import static com.cloudbank.loanapplication.persistence.LoanRecords.WorkflowRow;

import com.cloudbank.loanapplication.api.ApplicationApiModels.CreateApplicationRequest;
import com.cloudbank.loanapplication.api.ApplicationApiModels.DocumentRequest;
import com.cloudbank.loanapplication.domain.ApplicationStatus;
import com.cloudbank.loanapplication.domain.DocumentStatus;
import com.cloudbank.loanapplication.domain.WorkflowDispatchStatus;
import com.cloudbank.loanapplication.security.AuthenticatedPrincipal;
import java.sql.Timestamp;
import java.sql.Types;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.jdbc.core.support.SqlBinaryValue;
import org.springframework.stereotype.Repository;

@Repository
public class LoanApplicationRepository {

    private final JdbcClient jdbc;
    private final SqlNames names;

    public LoanApplicationRepository(JdbcClient jdbc, SqlNames names) {
        this.jdbc = jdbc;
        this.names = names;
    }

    public Optional<ApplicationRow> findByIdempotency(String principalId, String idempotencyKey) {
        return jdbc.sql("""
                SELECT application_sk, application_id, scenario_id, scenario_name, application_status,
                       requested_amount, requested_term_months, purpose_code, intake_request_hash,
                       created_at, updated_at
                FROM %s
                WHERE submitted_by_principal_id = :principalId
                  AND intake_idempotency_key = :idempotencyKey
                """.formatted(names.table("CB_LOAN_APPLICATION"))).param("principalId", principalId)
                .param("idempotencyKey", idempotencyKey).query(this::mapApplication).optional();
    }

    public Optional<ApplicationRow> findByApplicationId(String applicationId) {
        return jdbc.sql("""
                SELECT application_sk, application_id, scenario_id, scenario_name, application_status,
                       requested_amount, requested_term_months, purpose_code, intake_request_hash,
                       created_at, updated_at
                FROM %s WHERE application_id = :applicationId
                """.formatted(names.table("CB_LOAN_APPLICATION"))).param("applicationId", applicationId)
                .query(this::mapApplication).optional();
    }

    public boolean hasApplicationAccess(long applicationSk, String principalId) {
        String sql = """
                SELECT COUNT(*) FROM %s la
                WHERE la.application_sk = :applicationSk
                  AND %s
                """.formatted(names.table("CB_LOAN_APPLICATION"), applicationAccessPredicate());
        return jdbc.sql(sql).param("applicationSk", applicationSk).param("principalId", principalId)
                .query(Integer.class).single() > 0;
    }

    public List<ApplicationRow> findApplications(ApplicationStatus status, String scenarioId, String principalId,
            int offset, int size) {
        String sql = """
                SELECT application_sk, application_id, scenario_id, scenario_name, application_status,
                       requested_amount, requested_term_months, purpose_code, intake_request_hash,
                       created_at, updated_at
                FROM %s la
                WHERE (:status IS NULL OR application_status = :status)
                  AND (:scenarioId IS NULL OR scenario_id = :scenarioId)
                  AND %s
                ORDER BY created_at DESC
                OFFSET :offset ROWS FETCH NEXT :size ROWS ONLY
                """.formatted(names.table("CB_LOAN_APPLICATION"), applicationAccessPredicate());
        String statusValue = status == null ? null : status.name();
        return jdbc.sql(sql).param("status", statusValue).param("scenarioId", scenarioId)
                .param("principalId", principalId).param("offset", offset)
                .param("size", size).query(this::mapApplication).list();
    }

    public long countApplications(ApplicationStatus status, String scenarioId, String principalId) {
        String statusValue = status == null ? null : status.name();
        return jdbc.sql("""
                SELECT COUNT(*) FROM %s la
                WHERE (:status IS NULL OR application_status = :status)
                  AND (:scenarioId IS NULL OR scenario_id = :scenarioId)
                  AND %s
                """.formatted(names.table("CB_LOAN_APPLICATION"), applicationAccessPredicate()))
                .param("status", statusValue).param("scenarioId", scenarioId).param("principalId", principalId)
                .query(Long.class).single();
    }

    private String applicationAccessPredicate() {
        return """
                (la.submitted_by_principal_id = :principalId
                    OR EXISTS (SELECT 1 FROM %s p JOIN %s rg ON rg.principal_sk = p.principal_sk
                      WHERE p.principal_id = :principalId AND p.status = 'ACTIVE' AND rg.grant_status = 'ACTIVE'
                        AND (rg.expires_at IS NULL OR rg.expires_at > SYSTIMESTAMP)
                        AND rg.role_code IN ('ADMIN', 'SERVICE'))
                    OR EXISTS (SELECT 1 FROM %s p JOIN %s dg ON dg.principal_sk = p.principal_sk
                      WHERE p.principal_id = :principalId AND p.status = 'ACTIVE'
                        AND dg.application_sk = la.application_sk AND dg.grant_status = 'ACTIVE'
                        AND dg.grant_scope IN ('ALL', 'APPLICATION', 'DOCUMENT')
                        AND (dg.expires_at IS NULL OR dg.expires_at > SYSTIMESTAMP)))"""
                .formatted(names.table("CB_APP_PRINCIPAL"), names.table("CB_APP_ROLE_GRANT"),
                        names.table("CB_APP_PRINCIPAL"), names.table("CB_DATA_GRANT"));
    }

    public long insertApplicant(String applicantId, CreateApplicationRequest request) {
        jdbc.sql("""
                INSERT INTO %s (applicant_id, display_name, phone_token, email_token, age_band)
                VALUES (:applicantId, :displayName, :phoneToken, :emailToken, :ageBand)
                """.formatted(names.table("CB_APPLICANT"))).param("applicantId", applicantId)
                .param("displayName", request.applicant().displayName())
                .param("phoneToken", request.applicant().phoneToken())
                .param("emailToken", request.applicant().emailToken()).param("ageBand", request.applicant().ageBand())
                .update();
        return jdbc
                .sql("SELECT applicant_sk FROM " + names.table("CB_APPLICANT") + " WHERE applicant_id = :applicantId")
                .param("applicantId", applicantId).query(Long.class).single();
    }

    public void insertAddress(long applicantSk, String addressId, CreateApplicationRequest request) {
        jdbc.sql("""
                INSERT INTO %s (
                  applicant_sk, address_id, address_line, locality,
                  jurisdiction_code, jurisdiction_status, address_token, country_code, postal_code
                ) VALUES (
                  :applicantSk, :addressId, :addressLine, :locality,
                  :jurisdictionCode, 'REVIEW', :addressToken, :countryCode, :postalCode
                )
                """.formatted(names.table("CB_ADDRESS"))).param("applicantSk", applicantSk)
                .param("addressId", addressId).param("addressLine", request.applicant().address().addressLine())
                .param("locality", request.applicant().address().locality())
                .param("jurisdictionCode", request.applicant().address().jurisdictionCode())
                .param("addressToken", request.applicant().address().addressToken())
                .param("countryCode", request.applicant().address().countryCode())
                .param("postalCode", request.applicant().address().postalCode()).update();
    }

    public long insertApplication(String applicationId, long applicantSk, CreateApplicationRequest request,
            AuthenticatedPrincipal principal, String idempotencyKey, String requestHash) {
        String policyVersion = request.loan().policyVersion() == null ? "2026.0" : request.loan().policyVersion();
        jdbc.sql("""
                INSERT INTO %s (
                  application_id, applicant_sk, scenario_id, scenario_name, policy_version,
                  requested_amount, requested_term_months, purpose_code, application_status,
                  submitted_by_principal_id, submitted_by_issuer, submitted_by_subject,
                  intake_idempotency_key, intake_request_hash
                ) VALUES (
                  :applicationId, :applicantSk, :scenarioId, :scenarioName, :policyVersion,
                  :requestedAmount, :requestedTermMonths, :purposeCode, 'SUBMITTED',
                  :principalId, :issuer, :subject, :idempotencyKey, :requestHash
                )
                """.formatted(names.table("CB_LOAN_APPLICATION"))).param("applicationId", applicationId)
                .param("applicantSk", applicantSk).param("scenarioId", request.scenarioId())
                .param("scenarioName", request.scenarioName()).param("policyVersion", policyVersion)
                .param("requestedAmount", request.loan().requestedAmount())
                .param("requestedTermMonths", request.loan().requestedTermMonths())
                .param("purposeCode", request.loan().purposeCode()).param("principalId", principal.principalId())
                .param("issuer", principal.issuer()).param("subject", principal.subject())
                .param("idempotencyKey", idempotencyKey).param("requestHash", requestHash).update();
        return jdbc
                .sql("SELECT application_sk FROM " + names.table("CB_LOAN_APPLICATION")
                        + " WHERE application_id = :applicationId")
                .param("applicationId", applicationId).query(Long.class).single();
    }

    public void grantOwner(String applicationId, String principalId) {
        jdbc.sql("BEGIN " + names.packageName("CB_APPLICATION_SECURITY_PKG")
                + ".GRANT_APPLICATION_OWNER(:applicationId, :principalId); END;").param("applicationId", applicationId)
                .param("principalId", principalId).update();
    }

    public void insertDocument(long applicationSk, String documentId, DocumentRequest document) {
        int updated = jdbc.sql("""
                UPDATE %s SET
                  document_type = :documentType, content_sha256 = :contentSha256,
                  source_packet_path = :sourceReference, document_status = :documentStatus,
                  required_flag = :requiredFlag, media_type = :mediaType,
                  content_length_bytes = :contentLengthBytes
                WHERE application_sk = :applicationSk AND file_name = :fileName
                """.formatted(names.table("CB_DOCUMENT"))).param("documentType", document.documentType())
                .param("contentSha256", document.contentSha256()).param("sourceReference", document.sourceReference())
                .param("documentStatus", document.status().name())
                .param("requiredFlag", Boolean.toString(document.required())).param("mediaType", document.mediaType())
                .param("contentLengthBytes", document.contentLengthBytes()).param("applicationSk", applicationSk)
                .param("fileName", document.fileName()).update();
        if (updated == 0) {
            jdbc.sql("""
                    INSERT INTO %s (
                      application_sk, document_id, document_type, file_name, content_sha256,
                      source_packet_path, document_status, required_flag, media_type, content_length_bytes
                    ) VALUES (
                      :applicationSk, :documentId, :documentType, :fileName, :contentSha256,
                      :sourceReference, :documentStatus, :requiredFlag, :mediaType, :contentLengthBytes
                    )
                    """.formatted(names.table("CB_DOCUMENT"))).param("applicationSk", applicationSk)
                    .param("documentId", documentId).param("documentType", document.documentType())
                    .param("fileName", document.fileName()).param("contentSha256", document.contentSha256())
                    .param("sourceReference", document.sourceReference())
                    .param("documentStatus", document.status().name())
                    .param("requiredFlag", Boolean.toString(document.required()))
                    .param("mediaType", document.mediaType()).param("contentLengthBytes", document.contentLengthBytes())
                    .update();
        }
    }

    public Optional<String> findDocumentRegistrationHash(long applicationSk, String principalId,
            String idempotencyKey) {
        return jdbc.sql("""
                SELECT request_hash FROM %s
                WHERE application_sk = :applicationSk
                  AND principal_id = :principalId
                  AND idempotency_key = :idempotencyKey
                """.formatted(names.table("CB_DOCUMENT_REGISTRATION_REQUEST"))).param("applicationSk", applicationSk)
                .param("principalId", principalId).param("idempotencyKey", idempotencyKey).query(String.class)
                .optional();
    }

    public void insertDocumentRegistration(long applicationSk, String principalId, String idempotencyKey,
            String requestHash) {
        jdbc.sql("""
                INSERT INTO %s (application_sk, principal_id, idempotency_key, request_hash)
                VALUES (:applicationSk, :principalId, :idempotencyKey, :requestHash)
                """.formatted(names.table("CB_DOCUMENT_REGISTRATION_REQUEST"))).param("applicationSk", applicationSk)
                .param("principalId", principalId).param("idempotencyKey", idempotencyKey)
                .param("requestHash", requestHash).update();
    }

    public List<DocumentRow> findDocuments(long applicationSk) {
        return jdbc.sql("""
                SELECT document_id, document_type, file_name, document_status, required_flag
                FROM %s WHERE application_sk = :applicationSk ORDER BY received_at, document_id
                """.formatted(names.table("CB_DOCUMENT"))).param("applicationSk", applicationSk)
                .query((rs, rowNum) -> new DocumentRow(rs.getString("document_id"), rs.getString("document_type"),
                        rs.getString("file_name"), DocumentStatus.valueOf(rs.getString("document_status")),
                        Boolean.parseBoolean(rs.getString("required_flag"))))
                .list();
    }

    public Optional<DocumentProcessingRow> findProcessingDocument(String applicationId, String documentId) {
        return jdbc.sql("""
                SELECT d.document_sk, d.application_sk, a.application_id, d.document_id,
                       d.document_type, d.file_name, d.document_status, d.media_type,
                       d.content_length_bytes, d.content_sha256, d.required_flag
                FROM %s d
                JOIN %s a ON a.application_sk = d.application_sk
                WHERE a.application_id = :applicationId AND d.document_id = :documentId
                """.formatted(names.table("CB_DOCUMENT"), names.table("CB_LOAN_APPLICATION")))
                .param("applicationId", applicationId).param("documentId", documentId)
                .query(this::mapProcessingDocument).optional();
    }

    public List<DocumentProcessingRow> findProcessableDocuments(String applicationId) {
        return jdbc
                .sql("""
                        SELECT d.document_sk, d.application_sk, a.application_id, d.document_id,
                               d.document_type, d.file_name, d.document_status, d.media_type,
                               d.content_length_bytes, d.content_sha256, d.required_flag
                        FROM %s d
                        JOIN %s a ON a.application_sk = d.application_sk
                        JOIN %s c ON c.document_sk = d.document_sk
                        WHERE a.application_id = :applicationId
                          AND d.document_status IN ('RECEIVED','FAILED_RETRYABLE','EXTRACTED')
                        ORDER BY d.received_at, d.document_id
                        """.formatted(names.table("CB_DOCUMENT"), names.table("CB_LOAN_APPLICATION"),
                        names.table("CB_DOCUMENT_CONTENT")))
                .param("applicationId", applicationId).query(this::mapProcessingDocument).list();
    }

    /** Complete inventory for deterministic review; unlike extraction, this includes unavailable required documents. */
    public List<DocumentProcessingRow> findReviewDocuments(String applicationId) {
        return jdbc.sql("""
                SELECT d.document_sk, d.application_sk, a.application_id, d.document_id,
                       d.document_type, d.file_name, d.document_status, d.media_type,
                       d.content_length_bytes, d.content_sha256, d.required_flag
                FROM %s d JOIN %s a ON a.application_sk = d.application_sk
                WHERE a.application_id = :applicationId
                ORDER BY d.received_at, d.document_id
                """.formatted(names.table("CB_DOCUMENT"), names.table("CB_LOAN_APPLICATION")))
                .param("applicationId", applicationId).query(this::mapProcessingDocument).list();
    }

    public Optional<DocumentContentRow> findDocumentContent(long documentSk) {
        return jdbc.sql("""
                SELECT content_sha256, content_length_bytes, media_type,
                       upload_idempotency_key, file_content
                FROM %s WHERE document_sk = :documentSk
                """.formatted(names.table("CB_DOCUMENT_CONTENT"))).param("documentSk", documentSk)
                .query((rs, rowNum) -> new DocumentContentRow(rs.getString("content_sha256"),
                        rs.getLong("content_length_bytes"), rs.getString("media_type"),
                        rs.getString("upload_idempotency_key"), rs.getBytes("file_content")))
                .optional();
    }

    public void insertDocumentContent(DocumentProcessingRow document, String contentSha256, long contentLength,
            String mediaType, String idempotencyKey, byte[] content) {
        jdbc.sql("""
                INSERT INTO %s (
                  document_sk, application_sk, content_sha256, content_length_bytes,
                  media_type, upload_idempotency_key, file_content
                ) VALUES (
                  :documentSk, :applicationSk, :contentSha256, :contentLength,
                  :mediaType, :idempotencyKey, :fileContent
                )
                """.formatted(names.table("CB_DOCUMENT_CONTENT"))).param("documentSk", document.documentSk())
                .param("applicationSk", document.applicationSk()).param("contentSha256", contentSha256)
                .param("contentLength", contentLength).param("mediaType", mediaType)
                .param("idempotencyKey", idempotencyKey).param("fileContent", new SqlBinaryValue(content), Types.BLOB)
                .update();
    }

    public int markDocumentReceived(long documentSk, String documentId, String contentSha256, long contentLength,
            String mediaType) {
        return jdbc.sql("""
                UPDATE %s SET document_status = 'RECEIVED', content_sha256 = :contentSha256,
                              source_packet_path = :sourceReference,
                              content_length_bytes = :contentLength, media_type = :mediaType,
                              received_at = SYSTIMESTAMP
                WHERE document_sk = :documentSk AND document_status = 'EXPECTED'
                """.formatted(names.table("CB_DOCUMENT"))).param("contentSha256", contentSha256)
                .param("sourceReference", "oracle-blob:" + documentId).param("contentLength", contentLength)
                .param("mediaType", mediaType).param("documentSk", documentSk).update();
    }

    public int updateDocumentStatus(long documentSk, DocumentStatus expected, DocumentStatus target) {
        return jdbc.sql("""
                UPDATE %s SET document_status = :targetStatus
                WHERE document_sk = :documentSk AND document_status = :expectedStatus
                """.formatted(names.table("CB_DOCUMENT"))).param("targetStatus", target.name())
                .param("documentSk", documentSk).param("expectedStatus", expected.name()).update();
    }

    public void insertWorkflowStart(long applicationSk, String requestId, String workflowName, int workflowVersion,
            String startMode, WorkflowDispatchStatus status, String payload, String traceId) {
        jdbc.sql("""
                INSERT INTO %s (
                  application_sk, request_id, workflow_name, workflow_version, start_mode,
                  dispatch_status, request_payload, trace_id
                ) VALUES (
                  :applicationSk, :requestId, :workflowName, :workflowVersion, :startMode,
                  :dispatchStatus, :requestPayload, :traceId
                )
                """.formatted(names.table("CB_WORKFLOW_START_REQUEST"))).param("applicationSk", applicationSk)
                .param("requestId", requestId).param("workflowName", workflowName)
                .param("workflowVersion", workflowVersion).param("startMode", startMode)
                .param("dispatchStatus", status.name()).param("requestPayload", payload).param("traceId", traceId)
                .update();
    }

    public Optional<WorkflowRow> findWorkflow(long applicationSk) {
        return jdbc.sql("""
                SELECT w.workflow_start_request_sk, w.application_sk, a.application_id, w.request_id,
                       w.workflow_name, w.workflow_version, w.dispatch_status, w.request_payload,
                       w.attempt_count, w.trace_id, w.engine_workflow_id,
                       w.last_error_code, w.last_error_message
                FROM %s w JOIN %s a ON a.application_sk = w.application_sk
                WHERE w.application_sk = :applicationSk
                """.formatted(names.table("CB_WORKFLOW_START_REQUEST"), names.table("CB_LOAN_APPLICATION")))
                .param("applicationSk", applicationSk).query(this::mapWorkflow).optional();
    }

    public void insertAudit(long applicationSk, String eventId, String principalId, String action, String outcome,
            String objectType, String objectId, String traceId) {
        jdbc.sql("""
                INSERT INTO %s (
                  application_sk, audit_event_id, principal_id, event_action, event_outcome,
                  object_type, object_id, trace_id, redaction_applied
                ) VALUES (
                  :applicationSk, :eventId, :principalId, :eventAction, :eventOutcome,
                  :objectType, :objectId, :traceId, 'true'
                )
                """.formatted(names.table("CB_AUDIT_EVENT"))).param("applicationSk", applicationSk)
                .param("eventId", eventId).param("principalId", principalId).param("eventAction", action)
                .param("eventOutcome", outcome).param("objectType", objectType).param("objectId", objectId)
                .param("traceId", traceId).update();
    }

    public boolean auditEventExists(String eventId) {
        return jdbc.sql("SELECT COUNT(*) FROM " + names.table("CB_AUDIT_EVENT") + " WHERE audit_event_id = :eventId")
                .param("eventId", eventId).query(Integer.class).single() > 0;
    }

    public void insertTelemetry(long applicationSk, String correlationId, String traceId) {
        jdbc.sql("""
                INSERT INTO %s (
                  application_sk, correlation_id, trace_id, service_name, telemetry_kind
                ) VALUES (:applicationSk, :correlationId, :traceId, 'loan-application-service', 'TRACE')
                """.formatted(names.table("CB_TELEMETRY_CORRELATION"))).param("applicationSk", applicationSk)
                .param("correlationId", correlationId).param("traceId", traceId).update();
    }

    public int updateStatus(String applicationId, ApplicationStatus expected, ApplicationStatus target) {
        return jdbc.sql("""
                UPDATE %s SET application_status = :targetStatus, updated_at = SYSTIMESTAMP,
                              row_version = row_version + 1
                WHERE application_id = :applicationId AND application_status = :expectedStatus
                """.formatted(names.table("CB_LOAN_APPLICATION"))).param("targetStatus", target.name())
                .param("applicationId", applicationId).param("expectedStatus", expected.name()).update();
    }

    public int releaseDeferred(long applicationSk) {
        return jdbc.sql("""
                UPDATE %s SET dispatch_status = 'PENDING', updated_at = SYSTIMESTAMP
                WHERE application_sk = :applicationSk AND dispatch_status = 'DEFERRED'
                """.formatted(names.table("CB_WORKFLOW_START_REQUEST"))).param("applicationSk", applicationSk).update();
    }

    public int promoteWaitingWorkflow(long applicationSk) {
        return jdbc.sql("""
                UPDATE %s SET dispatch_status = 'PENDING', updated_at = SYSTIMESTAMP
                WHERE application_sk = :applicationSk AND dispatch_status = 'WAITING_FOR_DOCUMENTS'
                  AND NOT EXISTS (
                    SELECT 1 FROM %s d
                    WHERE d.application_sk = :applicationSk AND d.required_flag = 'true'
                      AND d.document_status = 'EXPECTED'
                  )
                """.formatted(names.table("CB_WORKFLOW_START_REQUEST"), names.table("CB_DOCUMENT")))
                .param("applicationSk", applicationSk).update();
    }

    public Optional<WorkflowRow> claimReadyWorkflow() {
        String claimToken = "loan-application-service:" + UUID.randomUUID();
        int claimed = jdbc.sql("""
                UPDATE %s SET dispatch_status = 'IN_PROGRESS', claimed_at = SYSTIMESTAMP,
                              claimed_by = :claimToken, attempt_count = attempt_count + 1,
                              updated_at = SYSTIMESTAMP
                WHERE workflow_start_request_sk = (
                  SELECT workflow_start_request_sk FROM (
                    SELECT workflow_start_request_sk FROM %s
                    WHERE dispatch_status IN ('PENDING','FAILED_RETRYABLE')
                      AND next_attempt_at <= SYSTIMESTAMP
                    ORDER BY next_attempt_at, workflow_start_request_sk
                  ) WHERE ROWNUM = 1
                )
                  AND dispatch_status IN ('PENDING','FAILED_RETRYABLE')
                """.formatted(names.table("CB_WORKFLOW_START_REQUEST"), names.table("CB_WORKFLOW_START_REQUEST")))
                .param("claimToken", claimToken).update();
        if (claimed == 0) {
            return Optional.empty();
        }
        return jdbc.sql("""
                SELECT w.workflow_start_request_sk, w.application_sk, a.application_id, w.request_id,
                       w.workflow_name, w.workflow_version, w.dispatch_status, w.request_payload,
                       w.attempt_count, w.trace_id, w.engine_workflow_id,
                       w.last_error_code, w.last_error_message
                FROM %s w JOIN %s a ON a.application_sk = w.application_sk
                WHERE w.dispatch_status = 'IN_PROGRESS' AND w.claimed_by = :claimToken
                """.formatted(names.table("CB_WORKFLOW_START_REQUEST"), names.table("CB_LOAN_APPLICATION")))
                .param("claimToken", claimToken).query(this::mapWorkflow).optional();
    }

    public void markWorkflowStarted(WorkflowRow row, String engineWorkflowId) {
        jdbc.sql("""
                UPDATE %s SET dispatch_status = 'STARTED', engine_workflow_id = :engineWorkflowId,
                              dispatched_at = SYSTIMESTAMP, updated_at = SYSTIMESTAMP,
                              last_error_code = NULL, last_error_message = NULL
                WHERE workflow_start_request_sk = :requestSk
                """.formatted(names.table("CB_WORKFLOW_START_REQUEST"))).param("engineWorkflowId", engineWorkflowId)
                .param("requestSk", row.requestSk()).update();
        jdbc.sql("""
                INSERT INTO %s (
                  application_sk, workflow_start_request_sk, workflow_id, workflow_name,
                  workflow_status, trace_id
                ) VALUES (:applicationSk, :requestSk, :workflowId, :workflowName, 'STARTED', :traceId)
                """.formatted(names.table("CB_WORKFLOW_INSTANCE"))).param("applicationSk", row.applicationSk())
                .param("requestSk", row.requestSk()).param("workflowId", engineWorkflowId)
                .param("workflowName", row.workflowName()).param("traceId", row.traceId()).update();
    }

    public void markWorkflowFailure(WorkflowRow row, boolean retryable, String code, String safeMessage) {
        int delaySeconds = Math.min(30, 1 << Math.min(row.attemptCount(), 5));
        jdbc.sql("""
                UPDATE %s SET dispatch_status = :dispatchStatus, last_error_code = :errorCode,
                              last_error_message = :errorMessage,
                              next_attempt_at = SYSTIMESTAMP + NUMTODSINTERVAL(:delaySeconds, 'SECOND'),
                              updated_at = SYSTIMESTAMP
                WHERE workflow_start_request_sk = :requestSk
                """.formatted(names.table("CB_WORKFLOW_START_REQUEST")))
                .param("dispatchStatus", retryable ? "FAILED_RETRYABLE" : "FAILED_FINAL").param("errorCode", code)
                .param("errorMessage", safeMessage).param("delaySeconds", delaySeconds)
                .param("requestSk", row.requestSk()).update();
    }

    private ApplicationRow mapApplication(java.sql.ResultSet rs, int rowNum) throws java.sql.SQLException {
        return new ApplicationRow(rs.getLong("application_sk"), rs.getString("application_id"),
                rs.getString("scenario_id"), rs.getString("scenario_name"),
                ApplicationStatus.valueOf(rs.getString("application_status")), rs.getBigDecimal("requested_amount"),
                rs.getInt("requested_term_months"), rs.getString("purpose_code"), rs.getString("intake_request_hash"),
                instant(rs.getTimestamp("created_at")), instant(rs.getTimestamp("updated_at")));
    }

    private WorkflowRow mapWorkflow(java.sql.ResultSet rs, int rowNum) throws java.sql.SQLException {
        return new WorkflowRow(rs.getLong("workflow_start_request_sk"), rs.getLong("application_sk"),
                rs.getString("application_id"), rs.getString("request_id"), rs.getString("workflow_name"),
                rs.getInt("workflow_version"), WorkflowDispatchStatus.valueOf(rs.getString("dispatch_status")),
                rs.getString("request_payload"), rs.getInt("attempt_count"), rs.getString("trace_id"),
                rs.getString("engine_workflow_id"), rs.getString("last_error_code"),
                rs.getString("last_error_message"));
    }

    private DocumentProcessingRow mapProcessingDocument(java.sql.ResultSet rs, int rowNum)
            throws java.sql.SQLException {
        long contentLength = rs.getLong("content_length_bytes");
        Long nullableContentLength = rs.wasNull() ? null : contentLength;
        return new DocumentProcessingRow(rs.getLong("document_sk"), rs.getLong("application_sk"),
                rs.getString("application_id"), rs.getString("document_id"), rs.getString("document_type"),
                rs.getString("file_name"), DocumentStatus.valueOf(rs.getString("document_status")),
                rs.getString("media_type"), nullableContentLength, rs.getString("content_sha256"),
                Boolean.parseBoolean(rs.getString("required_flag")));
    }

    private static Instant instant(Timestamp timestamp) {
        return timestamp == null ? null : timestamp.toInstant();
    }
}
