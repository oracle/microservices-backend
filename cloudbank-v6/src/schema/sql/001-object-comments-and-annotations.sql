-- CloudBank AI 2026.0
-- 001-object-comments-and-annotations.sql
-- Human-readable comments plus Oracle 23ai/26ai annotations for tooling and AI-safe governance.

COMMENT ON TABLE cb_applicant IS 'Applicant party record for CloudBank personal-loan origination fixtures.';
COMMENT ON TABLE cb_address IS 'Residential address evidence with jurisdiction and spatial location data.';
COMMENT ON TABLE cb_employer IS 'Invented employer reference data used by employment, income, and risk graph examples.';
COMMENT ON TABLE cb_loan_application IS 'System-of-record loan application aggregate for CloudBank personal-loan origination.';
COMMENT ON TABLE cb_employment IS 'Employment facts associated with a submitted loan application.';
COMMENT ON TABLE cb_liability_snapshot IS 'Point-in-time obligation and debt-to-income facts used by capacity rules.';
COMMENT ON TABLE cb_payment_calculation IS 'Deterministic payment calculation facts used by pricing and capacity review.';
COMMENT ON TABLE cb_document IS 'Document inventory and metadata; raw PDF bytes remain outside the database in the demo corpus.';
COMMENT ON TABLE cb_document_extraction IS 'Native JSON document-ingest output from OCR, vision, LLM, and rule-based extraction.';
COMMENT ON TABLE cb_document_fact IS 'Extracted document facts promoted from JSON for deterministic decision rules.';
COMMENT ON TABLE cb_document_issue IS 'Validation and extraction issues that affect decision routing.';
COMMENT ON TABLE cb_document_chunk IS 'Document text chunks with role labels and vector embeddings for authorized retrieval.';
COMMENT ON TABLE cb_income_evidence IS 'Income verification facts reconciled across application, pay, and deposit documents.';
COMMENT ON TABLE cb_policy_document IS 'CloudBank personal-loan policy document metadata for the RAG corpus.';
COMMENT ON TABLE cb_policy_chunk IS 'Policy chunks with role labels and vector embeddings for grounded retrieval.';
COMMENT ON TABLE cb_relationship_edge IS 'Shared-attribute and relationship edges used by SQL property graph risk analysis.';
COMMENT ON TABLE cb_jurisdiction_zone IS 'Spatial jurisdiction and review zones used by eligibility and boundary checks.';
COMMENT ON TABLE cb_spatial_signal IS 'Spatial signal results for address eligibility, boundary, and risk-zone checks.';
COMMENT ON TABLE cb_decision IS 'Decision records created by deterministic rules, workflow recovery, or manual review.';
COMMENT ON TABLE cb_decision_policy_evidence IS 'Policy evidence links used to reconstruct and explain a decision.';
COMMENT ON TABLE cb_explanation IS 'Audience-specific decision explanations and adverse action support text.';
COMMENT ON TABLE cb_manual_review_task IS 'Manual review queue tasks for underwriting and exception handling.';
COMMENT ON TABLE cb_workflow_instance IS 'MicroTx Workflow instance state for the loan origination process.';
COMMENT ON TABLE cb_workflow_event IS 'Workflow step events correlated to service calls and OpenTelemetry traces.';
COMMENT ON TABLE cb_telemetry_correlation IS 'Safe telemetry correlation attributes for traces, metrics, logs, and audits.';
COMMENT ON TABLE cb_audit_event IS 'Security and business audit events with raw payloads protected from ordinary views.';
COMMENT ON TABLE cb_app_principal IS 'Application principal registry for users, services, auditors, and administrators.';
COMMENT ON TABLE cb_app_role_grant IS 'Role grants used by CloudBank security views and fallback policies.';
COMMENT ON TABLE cb_data_grant IS 'Per-application data grants for role-aware document and application access.';
COMMENT ON TABLE cb_v_application_summary IS 'Read-only application summary view for ORDS and demo inspection.';
COMMENT ON TABLE cb_v_application_decision_facts IS 'Read-only view that reconstructs decision facts by application.';
COMMENT ON TABLE cb_v_manual_review_queue IS 'Read-only manual review work queue projection.';

COMMENT ON COLUMN cb_applicant.applicant_sk IS 'Generated surrogate primary key used for internal joins.';
COMMENT ON COLUMN cb_applicant.applicant_id IS 'Stable business identifier for applicant fixtures and API correlation.';
COMMENT ON COLUMN cb_applicant.display_name IS 'Applicant display name used in demo screens; treat as restricted customer data.';
COMMENT ON COLUMN cb_applicant.phone_token IS 'Tokenized phone-like value; do not store raw phone numbers in this demo schema.';
COMMENT ON COLUMN cb_applicant.email_token IS 'Tokenized email-like value; do not store raw customer email in telemetry.';
COMMENT ON COLUMN cb_address.location_geom IS 'SDO_GEOMETRY point used for spatial jurisdiction and boundary checks.';
COMMENT ON COLUMN cb_employer.employer_token IS 'Stable employer token used by graph signals without relying on real employer identifiers.';
COMMENT ON COLUMN cb_loan_application.application_id IS 'Stable business key used across APIs, workflows, documents, decisions, audit, and fixtures.';
COMMENT ON COLUMN cb_loan_application.scenario_id IS 'Deterministic scenario identifier for demo and test assertions.';
COMMENT ON COLUMN cb_loan_application.application_packet_json IS 'Native JSON snapshot of the normalized application packet.';
COMMENT ON COLUMN cb_liability_snapshot.total_obligations IS 'Virtual column: existing monthly debt plus proposed monthly payment.';
COMMENT ON COLUMN cb_document.content_sha256 IS 'Content digest for idempotent document loading and integrity checks.';
COMMENT ON COLUMN cb_document_extraction.extraction_payload IS 'Full structured extraction payload from the document ingest service.';
COMMENT ON COLUMN cb_document_chunk.embedding IS 'Vector embedding for authorized document retrieval after role filtering.';
COMMENT ON COLUMN cb_income_evidence.income_consistency_result IS 'Policy-aligned result comparing stated, pay-document, and verified income.';
COMMENT ON COLUMN cb_policy_document.metadata_json IS 'Native JSON policy metadata including role visibility and source manifest hints.';
COMMENT ON COLUMN cb_policy_chunk.embedding IS 'Vector embedding for role-filtered policy RAG retrieval.';
COMMENT ON COLUMN cb_relationship_edge.metadata_json IS 'Native JSON relationship evidence details for graph risk review.';
COMMENT ON COLUMN cb_jurisdiction_zone.zone_geom IS 'SDO_GEOMETRY polygon or multipolygon for eligible and review zones.';
COMMENT ON COLUMN cb_decision.decision_payload IS 'Structured decision facts, scores, and routing signals used for reconstruction.';
COMMENT ON COLUMN cb_workflow_instance.workflow_engine IS 'Expected to identify MicroTx Workflow as the orchestration engine.';
COMMENT ON COLUMN cb_audit_event.event_payload IS 'Restricted audit payload; expose only redacted projections to most roles.';
COMMENT ON COLUMN cb_app_principal.external_subject IS 'External identity subject from the authorization server when available.';

ALTER TABLE cb_applicant ANNOTATIONS (
  ADD Domain 'Loan Origination',
  ADD Entity 'Applicant',
  ADD OwnerService 'customer-service',
  ADD DataClassification 'restricted_customer',
  ADD SecurityModel 'Deep Data Security'
);
ALTER TABLE cb_address ANNOTATIONS (
  ADD Domain 'Loan Origination',
  ADD Entity 'Address',
  ADD OwnerService 'customer-service',
  ADD OracleFeature 'Spatial',
  ADD DataClassification 'restricted_customer'
);
ALTER TABLE cb_employer ANNOTATIONS (
  ADD Domain 'Loan Origination',
  ADD Entity 'Employer',
  ADD OwnerService 'customer-service',
  ADD DataClassification 'internal'
);
ALTER TABLE cb_loan_application ANNOTATIONS (
  ADD Domain 'Loan Origination',
  ADD Entity 'Loan Application',
  ADD OwnerService 'loan-service',
  ADD OracleFeature 'Relational, Native JSON',
  ADD PolicyVersioned,
  ADD DataClassification 'restricted_customer'
);
ALTER TABLE cb_document_extraction ANNOTATIONS (
  ADD Domain 'Document Ingest',
  ADD Entity 'Document Extraction',
  ADD OwnerService 'document-ingest',
  ADD OracleFeature 'Native JSON',
  ADD AiUse 'structured facts only'
);
ALTER TABLE cb_document_chunk ANNOTATIONS (
  ADD Domain 'Document Ingest',
  ADD Entity 'Document Chunk',
  ADD OwnerService 'document-ingest',
  ADD OracleFeature 'Vector Search',
  ADD RetrievalScope 'document',
  ADD SecurityModel 'Deep Data Security'
);
ALTER TABLE cb_policy_document ANNOTATIONS (
  ADD Domain 'Policy RAG',
  ADD Entity 'Policy Document',
  ADD OwnerService 'policy-service',
  ADD PolicyVersioned,
  ADD DataClassification 'restricted_policy'
);
ALTER TABLE cb_policy_chunk ANNOTATIONS (
  ADD Domain 'Policy RAG',
  ADD Entity 'Policy Chunk',
  ADD OwnerService 'policy-service',
  ADD OracleFeature 'Vector Search',
  ADD RetrievalScope 'policy',
  ADD SecurityModel 'Deep Data Security'
);
ALTER TABLE cb_relationship_edge ANNOTATIONS (
  ADD Domain 'Risk Signals',
  ADD Entity 'Relationship Edge',
  ADD OwnerService 'risk-service',
  ADD OracleFeature 'SQL Property Graph',
  ADD DataClassification 'restricted_customer'
);
ALTER TABLE cb_jurisdiction_zone ANNOTATIONS (
  ADD Domain 'Risk Signals',
  ADD Entity 'Jurisdiction Zone',
  ADD OwnerService 'risk-service',
  ADD OracleFeature 'Spatial',
  ADD DataClassification 'internal'
);
ALTER TABLE cb_decision ANNOTATIONS (
  ADD Domain 'Decisioning',
  ADD Entity 'Decision',
  ADD OwnerService 'decision-service',
  ADD RetrievalScope 'decision facts',
  ADD PolicyVersioned
);
ALTER TABLE cb_workflow_instance ANNOTATIONS (
  ADD Domain 'Workflow',
  ADD Entity 'Workflow Instance',
  ADD OwnerService 'workflow-service',
  ADD OracleFeature 'MicroTx Workflow',
  ADD TraceAttribute 'cloudbank.workflow_id'
);
ALTER TABLE cb_audit_event ANNOTATIONS (
  ADD Domain 'Audit',
  ADD Entity 'Audit Event',
  ADD OwnerService 'audit-service',
  ADD DataClassification 'restricted_customer',
  ADD PiiHandling 'redacted'
);
ALTER TABLE cb_app_principal ANNOTATIONS (
  ADD Domain 'Security',
  ADD Entity 'Application Principal',
  ADD OwnerService 'authorization-service',
  ADD SecurityModel 'Deep Data Security'
);
ALTER TABLE cb_data_grant ANNOTATIONS (
  ADD Domain 'Security',
  ADD Entity 'Data Grant',
  ADD OwnerService 'authorization-service',
  ADD SecurityModel 'Deep Data Security'
);

ALTER VIEW cb_v_application_summary ANNOTATIONS (
  ADD Domain 'Loan Origination',
  ADD Entity 'Application Summary View',
  ADD OwnerService 'loan-service',
  ADD OracleFeature 'ORDS'
);
ALTER TABLE cb_loan_application MODIFY application_id ANNOTATIONS (
  ADD BusinessKey,
  ADD UiLabel 'Application ID',
  ADD TraceAttribute 'cloudbank.application_id',
  ADD DataClassification 'restricted_customer'
);
ALTER TABLE cb_loan_application MODIFY scenario_id ANNOTATIONS (
  ADD BusinessKey,
  ADD UiLabel 'Scenario ID',
  ADD TraceAttribute 'cloudbank.scenario_id',
  ADD DataClassification 'internal'
);
ALTER TABLE cb_loan_application MODIFY application_packet_json ANNOTATIONS (
  ADD PayloadShape 'ApplicationPacket',
  ADD OracleFeature 'Native JSON',
  ADD AiUse 'structured facts only'
);
ALTER TABLE cb_address MODIFY location_geom ANNOTATIONS (
  ADD OracleFeature 'Spatial',
  ADD PayloadShape 'ApplicantLocation',
  ADD AiUse 'none'
);
ALTER TABLE cb_document_extraction MODIFY extraction_payload ANNOTATIONS (
  ADD PayloadShape 'DocumentExtraction',
  ADD OracleFeature 'Native JSON',
  ADD AiUse 'structured facts only'
);
ALTER TABLE cb_document_chunk MODIFY embedding ANNOTATIONS (
  ADD OracleFeature 'Vector Search',
  ADD RetrievalScope 'document',
  ADD AiUse 'retrieval'
);
ALTER TABLE cb_policy_chunk MODIFY embedding ANNOTATIONS (
  ADD OracleFeature 'Vector Search',
  ADD RetrievalScope 'policy',
  ADD AiUse 'retrieval'
);
ALTER TABLE cb_jurisdiction_zone MODIFY zone_geom ANNOTATIONS (
  ADD OracleFeature 'Spatial',
  ADD PayloadShape 'JurisdictionZone',
  ADD AiUse 'none'
);
ALTER TABLE cb_audit_event MODIFY event_payload ANNOTATIONS (
  ADD PayloadShape 'AuditPayload',
  ADD PiiHandling 'do_not_prompt',
  ADD AiUse 'none'
);
