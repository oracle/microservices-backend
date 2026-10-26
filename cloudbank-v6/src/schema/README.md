# CloudBank Database Schema Plan

## Purpose

This directory contains the CloudBank AI 2026.0 database design and runnable schema assets. It is a 26ai-first Oracle Database implementation for a realistic but teachable personal-loan origination demo.

CloudBank should use relational tables as the system of record, then deliberately showcase Oracle converged database capabilities where they strengthen the same loan journey:

- relational integrity for application, document, decision, workflow, and audit state;
- native JSON for document-ingest payloads, extracted facts, and application packet snapshots;
- vector search for policy and document retrieval;
- SQL property graph for relationship and shared-attribute risk signals;
- spatial data for address, jurisdiction, and zone-boundary checks;
- Deep Data Security for database-enforced authorization before SQL, document, vector, graph, or AI retrieval results leave the database.

This is not a production lending schema. It is a compact teaching schema that should be credible enough to demonstrate realistic data modeling and Oracle capabilities without becoming a full banking platform.

## DB Skill Guidance Used

Oracle database decisions for this plan start at the globally installed `db` skill, then route to these focused skill files:

- `db/design/data-modeling.md`
- `db/design/erd-design.md`
- `db/devops/schema-migrations.md`
- `db/devops/version-control-sql.md`
- `db/appdev/json-in-oracle.md`
- `db/appdev/sql-property-graph.md`
- `db/appdev/spatial-data.md`
- `db/features/vector-search.md`
- `db/features/dbms-vector.md`
- `db/performance/index-strategy.md`
- `db/security/privilege-management.md`
- `db/security/row-level-security.md`
- `db/security/data-masking.md`
- `db/security/auditing.md`
- `db/ords/ords-rest-api-design.md`

## Baseline Decisions

- Target Oracle AI Database 26ai first.
- Use `CB_` prefixes for application-owned tables, views, indexes, and feature objects.
- Use generated numeric surrogate primary keys for joins and stable synthetic business identifiers for demo correlation.
- Use `TIMESTAMP WITH LOCAL TIME ZONE` for business and audit timestamps unless a future migration chooses a stricter time model.
- Use `JSON` columns for structured but evolving payloads such as document extraction output, application packet snapshots, policy metadata, and explanation payloads.
- Use `VECTOR(*, FLOAT32)` in the first schema iteration so embedding dimensions can vary while the demo stabilizes.
- Use Deep Data Security as the planned database-enforced authorization pattern. Until it is implemented, services perform interim access checks from ownership, active roles, and active data grants (ADR 0013); no VPD or application-context objects are installed.
- Keep ORDS to read-only inspection endpoints and operational demo queries. Primary application writes should come through Spring Boot services.
- Use Liquibase-style versioned migrations for ordinary DDL, plus SQL files for Oracle feature objects that are clearer outside XML.
- Keep optional database features out of the core loan migration path. In particular, the core `CB_ADDRESS` table does not require Oracle Spatial; `004-risk-spatial-graph-schema.sql` adds `LOCATION_GEOM` with the other Spatial and graph objects.
- Loan intake persists a validated core `CB_ADDRESS` row with jurisdiction, optional country/postal address parts, and tokenized address evidence. In the `full-demo` profile, geographic-risk evaluation uses Oracle Autonomous AI Database GCDR to resolve a missing `LOCATION_GEOM` at evaluation time when possible. A missing match reports `ADDRESS_COORDINATES_MISSING` as `NOT_EVALUATED`; an unavailable geocoder reports `SPATIAL_EVALUATION_UNAVAILABLE`. Neither outcome clears the location or makes a lending decision.
- Require Oracle schema annotations and conventional comments on schema objects wherever plausible. Comments should explain the human/business purpose; annotations should provide structured metadata that tools, documentation generators, AI assistants, and security verification scripts can query.

Implemented structure:

```text
src/schema/
  README.md
  changelog-root.xml
  admin/
    001-loan-application-accounts.sql
    002-loan-application-finalize.sql
    003-lab-admin-access.sql
  changes/
    001-core-relational-schema.sql
    002-document-json-schema.sql
    003-policy-vector-schema.sql
    004-risk-spatial-graph-schema.sql
    005-workflow-observability-audit-schema.sql
    006-security-roles-and-views.sql
    007-seed-staging.sql
    008-loan-application-intake.sql
    009-align-service-principal.sql
    010-document-json-runtime-indexes.sql
    011-document-content-and-ingest-runtime.sql
    012-document-content-runtime-index.sql
    013-document-ingest-runtime-role.sql
    014-document-content-and-ingest-grants.sql
  sql/
    001-object-comments-and-annotations.sql
    002-json-search-indexes.sql
    003-vector-indexes.sql
    004-spatial-metadata-and-indexes.sql
    004-risk-property-graph.sql
    006-deep-data-security.sql
    007-ords-inspection-endpoints.sql
    008-loan-application-security.sql
  seeds/
    seed-data.json
    load-seed-data.sql
  verify/
    000-full-demo-capabilities.sql
    001-fixture-outcomes.sql
    003-feature-index-usage.sql
    004-schema-documentation.sql
    005-loan-application-runtime.sql
    006-full-demo.sql
```

The seed corpus is deliberately stored as structured JSON in `seeds/seed-data.json` and can be loaded explicitly by `CB_SEED_LOADER` from `CB_SEED_PAYLOAD`. Neither schema profile loads it automatically. This keeps the fixture data reviewable and reusable without turning the repository into a long insert script.

### Schema profiles and Spatial migration

`changes/001-core-relational-schema.sql` creates the relational loan tables without referencing `MDSYS`. The optional `changes/004-risk-spatial-graph-schema.sql` migration adds `CB_ADDRESS.LOCATION_GEOM` and creates the remaining Spatial and relationship-risk objects. Its companion metadata and index definitions remain in `sql/004-spatial-metadata-and-indexes.sql`.

This separation keeps a service-only `runtime` path available when optional
features are unnecessary. The default Compose `full-demo` profile uses the
regular `gvenzl/oracle-free:latest` image, verifies Spatial and Text components,
and then applies the Spatial migration and indexes.

Root change sets use `loan-application-runtime`, `full-demo`, or `ords` labels.
`runtime` applies only `loan-application-runtime`. `full-demo` applies the
runtime and full-demo labels and verifies the feature contract; it does not
load `seed-data.json`. The reserved `ords` label is
separate because local Compose does not install or run ORDS yet.

From the repository root, `./run-compose.sh up` invokes that same setup as a
one-shot schema initializer and runs its contract verification before the
application services start. The follow-up `./run-compose.sh verify` command
checks the running services and executes their component smoke tests. This is
true for both the Compose-managed Oracle database and an explicitly selected
existing Oracle container; Compose does not maintain a separate schema
definition or migration path.

The same setup provisions separate runtime accounts. `CB_LOAN_APPLICATION_APP` owns intake and BLOB access, `CB_DOCUMENT_INGEST_APP` can read metadata and persist extraction JSON but cannot read the BLOB table directly, and `CB_GEOGRAPHIC_RISK_APP` is created for `full-demo` to evaluate Spatial signals through the `CB_GEOGRAPHIC_RISK_RUNTIME` role. The `full-demo` profile also creates the read-only `CB_POLICY_APPLICATION_APP` retrieval identity and the separate `CB_POLICY_LOADER_APP` one-shot write identity. The script prompts for the credentials it needs and requires the locked `CLOUDBANK` owner password to differ from runtime passwords. Runtime accounts may share a password for local development, but deployed environments should use distinct service credentials.

For a fresh OBaaS deployment on OKE, `deploy/obaas/deploy-services.sh` packages
this same setup script and schema directory in the `cloudbank-schema-init`
image. Before deploying the application services, it runs that image as a
one-shot Kubernetes Job against the target Autonomous Database, using the
OBaaS-managed privileged database Secret and ADB wallet plus dedicated
CloudBank Secrets. This creates the target schema in place; it does not read or
copy a local Compose database. Account provisioning reads
`DEFAULT_PERMANENT_TABLESPACE` from the target database and assigns the owner
and runtime accounts to that tablespace. This keeps the same SQL path portable
between Oracle Free, where the default is normally `USERS`, and Autonomous
Database, where the managed application tablespace is `DATA`. The provisioning
step is restart-safe after statement-level account creation: it tolerates only
ADB's unchanged-password reuse response and later authenticates every runtime
account with its persistent Secret before reporting success.

Document table creation and its non-constraint runtime indexes use separate change sets. Oracle commits DDL statement by statement, so the table change set uses a recovery precondition for the known case where all document tables exist after an interrupted first migration. The follow-up change set validates that the complete table set exists before adding the remaining indexes. The unique constraint on `(APPLICATION_SK, FACT_NAME)` already supplies its index; no duplicate index is created. The JSON search index is a `full-demo` feature because lightweight images may not include the required Oracle Text/Search component.

No VPD policies, application contexts, or context-driven authorization views are installed (ADR 0013). The loan service performs interim application access checks from ownership, active roles, and active data grants until the Deep Data Security replacement is designed.

After the OKE schema bootstrap, `deploy/obaas/provision-lab-admin.sh` applies
`admin/003-lab-admin-access.sql` for the verified existing `obaas-admin` identity.
It idempotently creates the missing application principal and `ADMIN` grant and
verifies visibility before committing. Inactive identities and revoked/expired
grants require explicit reconciliation. This is deployment data provisioning;
it does not expand runtime database privileges or change Liquibase checksums.
See the [lab owner runbook](../../deploy/obaas/lab-owner-runbook.md).

This change corrects the development baseline before a `CLOUDBANK` schema has been provisioned in the current local database. Moving the column changes the Liquibase checksums of change sets `001-core-relational-schema` and `004-risk-spatial-graph-schema`. An environment that already recorded either change set must use a reviewed forward migration or rebuild its disposable development schema; do not clear checksums merely to suppress validation, and do not rerun the raw SQL files manually.

Seed data is opt-in and is not loaded by `setup-local-db.sh` or Compose. A
future explicit seed command can use this SQLcl flow:

```sql
-- Load src/schema/seeds/seed-data.json into CB_SEED_PAYLOAD as JSON using SQLcl or CI tooling.
-- Then run:
EXEC cb_seed_loader.load('cloudbank-2026.0-fixtures');
```

## Schema Documentation Standard

Every table, view, materialized view, domain, important index, and important column should include both conventional comments and Oracle schema annotations wherever Oracle supports the object type.

Use comments for readable explanations:

```sql
COMMENT ON TABLE cb_loan_application IS
  'System-of-record loan application aggregate for the CloudBank personal-loan demo.';

COMMENT ON COLUMN cb_loan_application.application_id IS
  'Stable synthetic business identifier used across APIs, workflows, audit records, traces, and fixtures.';
```

Use annotations for structured metadata:

```sql
CREATE TABLE cb_loan_application (
  application_sk NUMBER(18,0)
    GENERATED ALWAYS AS IDENTITY
    ANNOTATIONS (
      SurrogateKey,
      UiLabel 'Application surrogate key',
      DataClassification 'internal'
    ),
  application_id VARCHAR2(40) NOT NULL
    ANNOTATIONS (
      BusinessKey,
      UiLabel 'Application ID',
      TraceAttribute 'cloudbank.application_id',
      DataClassification 'restricted_customer'
    ),
  application_packet_json JSON
    ANNOTATIONS (
      PayloadShape 'ApplicationPacket',
      OracleFeature 'Native JSON',
      AiUse 'structured facts only'
    ),
  CONSTRAINT cb_loan_application_pk PRIMARY KEY (application_sk),
  CONSTRAINT cb_loan_application_uk UNIQUE (application_id)
)
ANNOTATIONS (
  Domain 'Loan Origination',
  Entity 'Loan Application',
  OwnerService 'loan-service',
  OracleFeature 'Relational, JSON',
  DataClassification 'restricted_customer',
  SecurityModel 'Deep Data Security'
);
```

Recommended annotation names:

- `Domain`: high-level business area, such as `Loan Origination`, `Policy RAG`, `Workflow`, `Audit`, or `Security`.
- `Entity`: business entity name.
- `OwnerService`: owning service or module.
- `OracleFeature`: showcased feature, such as `Relational`, `Native JSON`, `Vector Search`, `SQL Property Graph`, `Spatial`, `ORDS`, or `Deep Data Security`.
- `DataClassification`: expected value such as `public_demo`, `internal`, `restricted_customer`, or `restricted_policy`.
- `RoleVisibility`: intended role visibility, such as `APPLICANT`, `LOAN_OFFICER`, `UNDERWRITER`, `AUDITOR`, or `ADMIN`.
- `AiUse`: allowed AI use, such as `none`, `retrieval`, `structured facts only`, or `explanation grounding`.
- `RetrievalScope`: retrieval category such as `policy`, `document`, `decision facts`, or `audit summary`.
- `PiiHandling`: `tokenized`, `redacted`, `masked`, `not_pii`, or `do_not_prompt`.
- `BusinessKey`: marker annotation for stable external identifiers.
- `SurrogateKey`: marker annotation for generated primary keys.
- `TraceAttribute`: OpenTelemetry attribute name when a column is safe and approved for trace correlation.
- `PolicyVersioned`: marker annotation for objects whose rows must remain tied to policy version `2026.0`.

Rules:

- Do not use annotations to store secrets, credentials, raw prompts, raw model responses, raw document text, or real PII.
- Every `JSON`, `VECTOR`, and `SDO_GEOMETRY` column should have an annotation that names the payload shape or feature purpose.
- Every column that may appear in telemetry should have a `TraceAttribute` annotation and must be approved as non-sensitive.
- Every column used by AI retrieval should have `AiUse` and `DataClassification` annotations.
- Every security-sensitive table or view should have `SecurityModel` and `RoleVisibility` annotations.
- Every table and view should have a `COMMENT ON` statement even when it also has annotations.
- Every business-critical column should have a `COMMENT ON COLUMN` statement.

Documentation verification should query annotation and comment dictionary views during schema validation:

```sql
SELECT object_name, object_type, column_name, annotation_name, annotation_value
FROM   user_annotations_usage
WHERE  object_name LIKE 'CB\_%' ESCAPE '\'
ORDER  BY object_name, column_name, annotation_name;

SELECT table_name, comments
FROM   user_tab_comments
WHERE  table_name LIKE 'CB\_%' ESCAPE '\'
AND    comments IS NULL;

SELECT table_name, column_name
FROM   user_col_comments
WHERE  table_name LIKE 'CB\_%' ESCAPE '\'
AND    comments IS NULL
ORDER  BY table_name, column_name;
```

## Data Model

The schema should be normalized enough to teach real OLTP patterns, with JSON and specialized indexes used for the parts of the demo that are naturally document-shaped, semantic, graph-shaped, or spatial.

### Core Loan Model

`CB_APPLICANT`

- Stores the synthetic applicant record and stable applicant business ID.
- Key columns: `APPLICANT_SK`, `APPLICANT_ID`, `DISPLAY_NAME`, `PHONE_TOKEN`, `EMAIL_TOKEN`, `AGE_BAND`, `DATA_CLASSIFICATION`, `CREATED_AT`.
- Notes: keep token columns separate from display fields so redaction and role-aware views can demonstrate different exposure levels.

`CB_ADDRESS`

- Stores applicant residential address evidence in the core relational schema.
- Core columns: `ADDRESS_SK`, `APPLICANT_SK`, `ADDRESS_ID`, `ADDRESS_LINE`, `LOCALITY`, `JURISDICTION_CODE`, `JURISDICTION_STATUS`, `ADDRESS_TOKEN`.
- Geocoding columns: optional `COUNTRY_CODE` (ISO 3166-1 alpha-2) and `POSTAL_CODE`.
- The optional Spatial migration adds `LOCATION_GEOM SDO_GEOMETRY` for spatial jurisdiction and risk-zone checks.

`CB_EMPLOYER`

- Stores invented employer references used by employment, documents, and graph signals.
- Key columns: `EMPLOYER_SK`, `EMPLOYER_ID`, `EMPLOYER_NAME`, `EMPLOYER_TOKEN`, `EMPLOYER_ADDRESS`, `STATUS`.

`CB_LOAN_APPLICATION`

- The primary application aggregate.
- Key columns: `APPLICATION_SK`, `APPLICATION_ID`, `APPLICANT_SK`, `SCENARIO_ID`, `POLICY_VERSION`, `REQUESTED_AMOUNT`, `REQUESTED_TERM_MONTHS`, `PURPOSE_CODE`, `APPLICATION_STATUS`, `EXPECTED_OUTCOME`, `APPLICATION_PACKET_JSON JSON`, `DATA_CLASSIFICATION`, `CREATED_AT`, `UPDATED_AT`.
- JSON use case: `APPLICATION_PACKET_JSON` stores a point-in-time normalized packet snapshot used for teaching JSON queries and JSON_TABLE examples.

`CB_EMPLOYMENT`

- Stores employment and income-source facts from application and extraction.
- Key columns: `EMPLOYMENT_SK`, `APPLICATION_SK`, `EMPLOYER_SK`, `EMPLOYMENT_STATUS`, `JOB_TITLE`, `TENURE_TEXT`, `TENURE_BAND`, `INCOME_SOURCE_TYPE`, `PAY_FREQUENCY`.

`CB_INCOME_EVIDENCE`

- Stores income verification facts and consistency result.
- Key columns: `INCOME_EVIDENCE_SK`, `APPLICATION_SK`, `DOCUMENT_SK`, `STATED_GROSS_MONTHLY_INCOME`, `PAY_DOCUMENT_MONTHLY_INCOME`, `VERIFIED_GROSS_MONTHLY_INCOME`, `INCOME_CONSISTENCY_RESULT`, `EXTRACTION_CONFIDENCE`, `DOCUMENT_VALIDATION_STATUS`, `EVIDENCE_TIMESTAMP`.

`CB_LIABILITY_SNAPSHOT`

- Stores applicant obligation facts used by deterministic capacity rules.
- Key columns: `LIABILITY_SK`, `APPLICATION_SK`, `EXISTING_MONTHLY_DEBT`, `PROPOSED_MONTHLY_PAYMENT`, `TOTAL_OBLIGATIONS`, `DEBT_TO_INCOME_PCT`, `RECENT_DELINQUENCY_INDICATOR`, `BANKRUPTCY_INDICATOR`, `CAPTURED_AT`.

`CB_PAYMENT_CALCULATION`

- Stores deterministic payment calculation facts.
- Key columns: `PAYMENT_CALC_SK`, `APPLICATION_SK`, `REQUESTED_AMOUNT`, `EVALUATED_AMOUNT`, `TERM_MONTHS`, `APR_TEXT`, `MONTHLY_PAYMENT`, `CALCULATION_STATUS`, `CALCULATION_TIMESTAMP`, `POLICY_VERSION`.

### Document Model

`CB_DOCUMENT`

- Stores document inventory and metadata; content is separated into a one-to-one BLOB table.
- Key columns: `DOCUMENT_SK`, `APPLICATION_SK`, `DOCUMENT_ID`, `DOCUMENT_TYPE`, `FILE_NAME`, `CONTENT_SHA256`, `SOURCE_PACKET_PATH`, `RECEIVED_AT`, `DATA_CLASSIFICATION`.

`CB_DOCUMENT_CONTENT`

- Stores one immutable uploaded PDF per document in an Oracle SecureFiles BLOB.
- Key columns: `DOCUMENT_SK`, `APPLICATION_SK`, `CONTENT_SHA256`, `CONTENT_LENGTH_BYTES`, `MEDIA_TYPE`, `UPLOAD_IDEMPOTENCY_KEY`, `FILE_CONTENT`, `CREATED_AT`.
- Enforces PDF media type and a 25 MiB maximum. Access follows the same interim service-side application authorization checks as document metadata.

`CB_DOCUMENT_EXTRACTION`

- Stores the full structured response from `document-ingest`.
- Key columns: `EXTRACTION_SK`, `DOCUMENT_SK`, `APPLICATION_SK`, `PROVIDER`, `EXTRACTION_STATUS`, `EXTRACTION_PAYLOAD JSON`, `RAW_TEXT_LINE_COUNT`, `CREATED_AT`.
- JSON use case: query `EXTRACTION_PAYLOAD` using dot notation, `JSON_VALUE`, and `JSON_TABLE` for extracted facts.

`CB_DOCUMENT_FACT`

- Stores extracted facts promoted from JSON into relational form for deterministic rules.
- Key columns: `DOCUMENT_FACT_SK`, `APPLICATION_SK`, `DOCUMENT_SK`, `FACT_NAME`, `FACT_VALUE_TEXT`, `FACT_VALUE_NUMBER`, `FACT_VALUE_DATE`, `CONFIDENCE_SCORE`.

`CB_DOCUMENT_ISSUE`

- Stores extraction and validation issues.
- Key columns: `DOCUMENT_ISSUE_SK`, `APPLICATION_SK`, `DOCUMENT_SK`, `ISSUE_CODE`, `ISSUE_SEVERITY`, `ROUTING_EFFECT`, `POLICY_HINT`.

`CB_DOCUMENT_REVIEW`

- Stores the durable, idempotent deterministic document-review envelope owned
  by `document-review-service`; it is not a lending decision record.
- Key columns: `DOCUMENT_REVIEW_SK`, `REVIEW_ID`, `APPLICATION_SK`,
  `WORKFLOW_ID`, `TASK_REFERENCE`, `IDEMPOTENCY_KEY_HASH`,
  `INPUT_FINGERPRINT`, `PROFILE_VERSION`, `REVIEW_STATUS`, `DISPOSITION`,
  `RESULT_PAYLOAD JSON`, `TRACE_ID`, `CREATED_AT`, `UPDATED_AT`,
  `COMPLETED_AT`.
- `DISPOSITION` is constrained to `CLEAR`, `MANUAL_REVIEW`,
  `RETRY_EXTRACTION`, or `BLOCKED`; `BLOCKED` is a document-processing
  outcome, never a loan rejection. The original idempotency key is never
  stored.
- Changesets 025–027 create the table and indexes, grant the
  `CB_DOCUMENT_REVIEW_RUNTIME` least-privilege role to
  `CB_DOCUMENT_REVIEW_APP`, and align document-issue and income-evidence
  routing constraints with the review outcomes.

`CB_DOCUMENT_CHUNK`

- Stores authorized text chunks for document Q&A and review assistance.
- Key columns: `DOCUMENT_CHUNK_SK`, `DOCUMENT_SK`, `APPLICATION_SK`, `CHUNK_ID`, `CHUNK_TEXT`, `CHUNK_METADATA JSON`, `MIN_ROLE`, `ACCESS_LABEL`, `EMBEDDING VECTOR(*, FLOAT32)`.
- Security use case: Deep Data Security must filter chunks before vector/RAG retrieval returns results to Spring AI tools.

### Policy and RAG Model

`CB_POLICY_DOCUMENT`

- Stores policy file inventory and access metadata.
- Key columns: `POLICY_DOCUMENT_SK`, `POLICY_DOCUMENT_ID`, `POLICY_CODE`, `POLICY_TITLE`, `POLICY_VERSION`, `SOURCE_PATH`, `EFFECTIVE_DATE`, `OWNER_ROLE`, `METADATA_JSON JSON`, `REVIEW_STATUS`.

`CB_POLICY_CHUNK`

- Stores chunked policy text and embeddings.
- Key columns: `POLICY_CHUNK_SK`, `POLICY_DOCUMENT_SK`, `CHUNK_ID`, `SECTION_REF`, `HEADING`, `CHUNK_ORDINAL`, `CHUNK_TEXT`, `MIN_ROLE`, `ACCESS_LABEL`, `CHUNK_METADATA JSON`, `EMBEDDING VECTOR(*, FLOAT32)`.
- Vector use case: retrieve chunks for explanation grounding with role-aware database authorization.

### Decision Model

`CB_DECISION`

- Stores the deterministic decision result.
- Key columns: `DECISION_SK`, `APPLICATION_SK`, `DECISION_ID`, `DECISION_TYPE`, `DECISION_OUTCOME`, `RISK_BAND`, `POLICY_VERSION`, `DECISION_PAYLOAD JSON`, `WORKFLOW_ID`, `TASK_REFERENCE`, `IDEMPOTENCY_KEY_HASH`, `REQUEST_HASH`, `TRACE_ID`, `DECIDED_BY`, `DECIDED_AT`.
- Constraint: `DECISION_TYPE` distinguishes initial, recovered, manual-final, and adverse decisions.
- `decision-service` stores only SHA-256 hashes of idempotency keys. Its
  restricted JSON payload snapshots the typed facts and optional underwriter
  resolution used by `decision-rules-v1`; those values are not returned by the
  bounded decision response or written to service logs.
- Changesets 032–034 add decision correlation/idempotency metadata, create the
  least-privilege `CB_DECISION_RUNTIME` role and `CB_DECISION_APP` account
  contract, and permit document review to promote vetted capacity/payment
  projections.

`CB_DECISION_POLICY_EVIDENCE`

- Links decisions to policy chunks used in explanations.
- Key columns: `DECISION_EVIDENCE_SK`, `DECISION_SK`, `POLICY_CHUNK_SK`, `EVIDENCE_ID`, `POLICY_CODE`, `SECTION_REF`, `EVIDENCE_ROLE`, `EVIDENCE_SUMMARY`.

`CB_EXPLANATION`

- Stores grounded explanation output and safe metadata.
- Key columns: `EXPLANATION_SK`, `DECISION_SK`, `EXPLANATION_ID`, `AUDIENCE`, `EXPLANATION_STATUS`, `EXPLANATION_TEXT`, `EXPLANATION_PAYLOAD JSON`, `CREATED_AT`.

`CB_MANUAL_REVIEW_TASK`

- Stores manual review queue state.
- Key columns: `REVIEW_TASK_SK`, `APPLICATION_SK`, `TASK_ID`, `TASK_TYPE`, `TASK_STATUS`, `PRIORITY`, `ASSIGNED_TO_PRINCIPAL_ID`, `REASON_CODE`, `TASK_PAYLOAD JSON`, `DUE_AT`.

### Workflow, Observability, and Audit Model

`CB_WORKFLOW_INSTANCE`

- Stores MicroTx Workflow correlation state for the loan workflow.
- Key columns: `WORKFLOW_INSTANCE_SK`, `APPLICATION_SK`, `WORKFLOW_ID`, `WORKFLOW_NAME`, `WORKFLOW_ENGINE`, `WORKFLOW_STATUS`, `TRACE_ID`, `STARTED_AT`, `COMPLETED_AT`, `WORKFLOW_PAYLOAD JSON`.

`CB_WORKFLOW_EVENT`

- Stores major workflow step events.
- Key columns: `WORKFLOW_EVENT_SK`, `WORKFLOW_INSTANCE_SK`, `EVENT_ID`, `EVENT_TYPE`, `EVENT_STATUS`, `SERVICE_NAME`, `EVENT_PAYLOAD JSON`, `TRACE_ID`, `SPAN_ID`, `EVENT_AT`.

`CB_TELEMETRY_CORRELATION`

- Stores trace/search correlation values used in SigNoz walkthroughs.
- Key columns: `TELEMETRY_CORRELATION_SK`, `APPLICATION_SK`, `CORRELATION_ID`, `TRACE_ID`, `SPAN_ID`, `SERVICE_NAME`, `TELEMETRY_KIND`, `SAFE_ATTRIBUTES_JSON JSON`, `CREATED_AT`.
- Redaction rule: no raw applicant name, address, prompt, response, or document text.

`CB_AUDIT_EVENT`

- Stores application-level audit events that complement database unified auditing.
- Key columns: `AUDIT_EVENT_SK`, `APPLICATION_SK`, `AUDIT_EVENT_ID`, `PRINCIPAL_ID`, `EVENT_ACTION`, `EVENT_OUTCOME`, `OBJECT_TYPE`, `OBJECT_ID`, `TRACE_ID`, `REDACTION_APPLIED`, `EVENT_PAYLOAD JSON`, `CREATED_AT`.

### Risk Signal Model

`CB_RELATIONSHIP_EDGE`

- Stores shared-attribute edges for SQL property graph queries.
- Key columns: `RELATIONSHIP_EDGE_SK`, `EDGE_ID`, `APPLICATION_SK`, `SOURCE_ENTITY_TYPE`, `SOURCE_ENTITY_ID`, `TARGET_ENTITY_TYPE`, `TARGET_ENTITY_ID`, `RELATIONSHIP_TYPE`, `EVIDENCE_STRENGTH`, `SIGNAL_STATUS`, `METADATA_JSON JSON`, `CREATED_AT`.
- Graph use case: shared device, shared address token, shared employer token, shared bank-account token, or duplicate document token.

`CB_JURISDICTION_ZONE`

- Stores enabled jurisdictions and synthetic boundary/review zones.
- Key columns: `JURISDICTION_ZONE_SK`, `ZONE_ID`, `JURISDICTION_CODE`, `ZONE_NAME`, `ZONE_TYPE`, `ZONE_STATUS`, `ZONE_GEOM SDO_GEOMETRY`, `METADATA_JSON JSON`.

`CB_SPATIAL_SIGNAL`

- Stores per-application spatial check results.
- Key columns: `SPATIAL_SIGNAL_SK`, `APPLICATION_SK`, `ADDRESS_SK`, `JURISDICTION_ZONE_SK`, `SIGNAL_ID`, `SIGNAL_CODE`, `SIGNAL_TYPE`, `SIGNAL_RESULT`, `DISTANCE_TO_BOUNDARY_M`, `ROUTING_EFFECT`, `CREATED_AT`.

### Security Support Model

`CB_APP_PRINCIPAL`

- Maps authenticated application users, services, and synthetic demo users.
- Key columns: `PRINCIPAL_SK`, `PRINCIPAL_ID`, `PRINCIPAL_TYPE`, `DISPLAY_NAME`, `EXTERNAL_SUBJECT`, `STATUS`.

`CB_APP_ROLE_GRANT`

- Maps principals to application roles.
- Key columns: `ROLE_GRANT_SK`, `PRINCIPAL_SK`, `ROLE_CODE`, `GRANTED_AT`, `EXPIRES_AT`.

`CB_DATA_GRANT`

- Supports database-enforced authorization for applications, policy chunks, document chunks, and audit views.
- Key columns: `DATA_GRANT_SK`, `PRINCIPAL_SK`, `APPLICATION_SK`, `GRANT_SCOPE`, `GRANT_REASON`, `GRANT_STATUS`, `GRANTED_AT`, `EXPIRES_AT`.
- Deep Data Security use case: drive role and object access before application SQL or RAG retrieval returns rows.

## Views and Public Query Shapes

`CB_V_APPLICATION_SUMMARY`

- ORDS-ready read-only view for application state.
- Shows application ID, scenario ID, status, decision result, workflow ID, trace ID, and redacted applicant label.

`CB_V_APPLICATION_DECISION_FACTS`

- Used by decision and explanation services.
- Joins application, income, liabilities, payment calculation, identity, risk, and policy version facts.

`CB_V_AUTHORIZED_POLICY_CHUNKS`

- Same query shape for loan officers and underwriters.
- Deep Data Security should determine which chunks are visible before vector retrieval.

`CB_V_AUTHORIZED_DOCUMENT_CHUNKS`

- Same query shape for applicant, loan officer, underwriter, and auditor roles.
- Document chunks must be filtered by active principal, role, and application assignment.

`CB_V_MANUAL_REVIEW_QUEUE`

- Queue view for loan officers and underwriters.
- Includes application ID, reason code, task age, status, and redacted applicant label.

`CB_V_AUDIT_REDACTED`

- Auditor-friendly audit view.
- Excludes raw prompts, raw document text, raw sensitive tokens, and unnecessary PII.

## Index Plan

Use B-tree indexes for OLTP lookup and join paths. Do not use bitmap indexes on high-write operational tables.

Unique and primary lookup indexes:

- `CB_APPLICANT(APPLICANT_ID)`
- `CB_LOAN_APPLICATION(APPLICATION_ID)`
- `CB_WORKFLOW_INSTANCE(WORKFLOW_ID)`
- `CB_DOCUMENT(DOCUMENT_ID)`
- `CB_POLICY_CHUNK(CHUNK_ID)`
- `CB_DECISION(DECISION_ID)`

Foreign key and status indexes:

- `CB_LOAN_APPLICATION(APPLICANT_SK, CREATED_AT)`
- `CB_DOCUMENT(APPLICATION_SK, DOCUMENT_TYPE)`
- `CB_DOCUMENT_EXTRACTION(APPLICATION_SK, EXTRACTION_STATUS)`
- `CB_DECISION(APPLICATION_SK, DECIDED_AT)`
- `CB_MANUAL_REVIEW_TASK(TASK_STATUS, PRIORITY, CREATED_AT)`
- `CB_WORKFLOW_EVENT(WORKFLOW_INSTANCE_SK, EVENT_AT)`
- `CB_AUDIT_EVENT(APPLICATION_SK, CREATED_AT)`
- `CB_TELEMETRY_CORRELATION(TRACE_ID)`
- `CB_TELEMETRY_CORRELATION(APPLICATION_SK, SERVICE_NAME)`

Function-based indexes:

- `LOWER(CB_APPLICANT.EMAIL_TOKEN)` if email-token lookup is part of fixture loading or user mapping.
- `LOWER(CB_APPLICANT.PHONE_TOKEN)` if phone-token matching is part of relationship checks.

JSON indexes:

- JSON value index on `CB_DOCUMENT_EXTRACTION.EXTRACTION_PAYLOAD` for common paths such as applicant name, employer, verified income, and document type.
- JSON search index on `CB_DECISION.DECISION_PAYLOAD` for decision reconstruction and explanation/debug queries.

Vector indexes:

- `CB_POLICY_CHUNK(EMBEDDING)` using HNSW with cosine distance for policy RAG.
- `CB_DOCUMENT_CHUNK(EMBEDDING)` using HNSW or IVF with cosine distance for document review retrieval.

Spatial indexes:

- `CB_ADDRESS(LOCATION_GEOM)`
- `CB_JURISDICTION_ZONE(ZONE_GEOM)`

Graph support indexes:

- `CB_RELATIONSHIP_EDGE(SOURCE_ENTITY_TYPE, SOURCE_ENTITY_ID)`
- `CB_RELATIONSHIP_EDGE(TARGET_ENTITY_TYPE, TARGET_ENTITY_ID)`
- `CB_RELATIONSHIP_EDGE(APPLICATION_SK, RELATIONSHIP_TYPE)`

## Oracle Feature Objects

### JSON

Use native `JSON` columns for:

- `CB_LOAN_APPLICATION.APPLICATION_PACKET_JSON`
- `CB_DOCUMENT_EXTRACTION.EXTRACTION_PAYLOAD`
- `CB_DOCUMENT_CHUNK.CHUNK_METADATA`
- `CB_POLICY_CHUNK.CHUNK_METADATA`
- `CB_DECISION.DECISION_PAYLOAD`
- `CB_EXPLANATION.EXPLANATION_PAYLOAD`
- `CB_WORKFLOW_EVENT.EVENT_PAYLOAD`
- `CB_AUDIT_EVENT.EVENT_PAYLOAD`
- `CB_TELEMETRY_CORRELATION.SAFE_ATTRIBUTES_JSON`

JSON should hold evidence shape and payloads, while deterministic decision inputs should also be promoted into typed relational columns.

### Vector Search

Store embeddings in:

- `CB_POLICY_CHUNK.EMBEDDING VECTOR(*, FLOAT32)`
- `CB_DOCUMENT_CHUNK.EMBEDDING VECTOR(*, FLOAT32)`

Required retrieval behavior:

```sql
SELECT chunk_id, heading, chunk_text
FROM   cb_v_authorized_policy_chunks
WHERE  policy_version = :policy_version
ORDER  BY embedding <=> :query_embedding
FETCH  FIRST 5 ROWS ONLY;
```

The authorized view and Deep Data Security policy must apply before chunks are available to the Spring AI retriever.

### SQL Property Graph

Create `CB_RISK_GRAPH` over current relational tables and a compact `CB_RISK_GRAPH_NODE` table. Oracle property graph vertex and edge definitions require tables or materialized views, so the node table is used as the unified vertex source for the demo graph.

Planned vertices:

- applicant from `CB_APPLICANT`;
- address token from `CB_ADDRESS`;
- employer from `CB_EMPLOYER`;
- application from `CB_LOAN_APPLICATION`;
- token/entity vertices from future normalized risk-entity rows if needed.

Planned edges:

- applicant submitted application;
- applicant uses address token;
- applicant works for employer;
- application has shared-attribute signal;
- relationship edges from `CB_RELATIONSHIP_EDGE`.

Example teaching query:

```sql
SELECT *
FROM GRAPH_TABLE (
  cb_risk_graph
  MATCH (a IS applicant)-[e IS shared_attribute]-(b)
  WHERE a.applicant_id = :applicant_id
  COLUMNS (
    a.applicant_id AS applicant_id,
    e.relationship_type AS relationship_type,
    e.severity AS severity
  )
);
```

### Spatial

Use `SDO_GEOMETRY` for:

- applicant/address point geometry in `CB_ADDRESS.LOCATION_GEOM`;
- zone polygons in `CB_JURISDICTION_ZONE.ZONE_GEOM`.

Required setup:

- Insert metadata into `USER_SDO_GEOM_METADATA` for both spatial columns.
- Create spatial indexes after metadata is present.
- Use `SDO_RELATE` and `SDO_WITHIN_DISTANCE` for zone and boundary checks.
- On Oracle Autonomous AI Database, grant address geocoding access to the
  geographic-risk runtime user with `EXEC
  SDO_GCDR.ELOC_GRANT_ACCESS('CB_GEOGRAPHIC_RISK_APP');`.

Example teaching query:

```sql
SELECT a.application_id, z.zone_id, z.zone_type, z.review_required_flag
FROM   cb_loan_application a
JOIN   cb_address ad ON ad.applicant_sk = a.applicant_sk
JOIN   cb_jurisdiction_zone z ON z.jurisdiction_code = ad.jurisdiction_code
WHERE  a.application_id = :application_id
AND    SDO_RELATE(ad.location_geom, z.zone_geom, 'mask=INSIDE') = 'TRUE';
```

### Deep Data Security

Deep Data Security is the preferred 26ai-first authorization model for this schema. It should protect:

- application rows by applicant ownership and staff assignment;
- sensitive applicant columns such as name, address, phone, and email tokens;
- document chunks and raw extraction payloads;
- underwriter-only policy chunks;
- vector retrieval on policy and document chunks;
- audit rows and redacted audit views.

The demo must prove that the same SQL and vector query can return different authorized results for different end-user roles.

Until Deep Data Security is implemented, no database-enforced row or column
authorization is installed (ADR 0013). Services perform interim access checks
from ownership, active roles, and active data grants, and object grants plus
least-privilege runtime roles bound what each service account can read. The
same acceptance tests must carry over when the Deep Data Security policies are
designed.

### ORDS

ORDS endpoints expose read-only inspection APIs backed by views:

- `GET /cloudbank/schema/applications/:application_id`
- `GET /cloudbank/schema/manual-review`
- `GET /cloudbank/schema/audit/:application_id`

Writes should remain in Spring Boot services for the first implementation path.

## Deterministic Fixture Coverage

The schema and seed data must support these existing scenarios:

| Application | Workflow | Scenario | Expected outcome | Required schema evidence |
|---|---|---|---|---|
| `APP-APR-001` | `WF-APP-APR-001` | `SCN-FAST-APPROVAL-001` | `APPROVED` | product scope pass, identity verified, income consistent, DTI within auto threshold, no unresolved signals |
| `APP-MR-002` | `WF-APP-MR-002` | `SCN-MANUAL-REVIEW-002` | `MANUAL_REVIEW` | income inconsistency, low extraction confidence, DTI in manual-review range |
| `APP-REJ-003` | `WF-APP-REJ-003` | `SCN-REJECTION-003` | `REJECTED` | verified income below minimum and DTI above hard reject threshold |
| `APP-OPFAIL-004` | `WF-APP-OPFAIL-004` | `SCN-OPERATIONAL-FAILURE-004` | `FAILED_RETRYABLE_RECOVERED` | retryable document processing event, recovered workflow state, final decision evidence |
| `APP-RISK-005` | `WF-APP-RISK-005` | `SCN-RISK-SIGNAL-005` | `MANUAL_REVIEW` | identity needs review, relationship/shared-attribute signal, spatial boundary review signal |

## Acceptance Queries

Application summary:

```sql
SELECT application_id, scenario_id, application_status, decision_outcome, risk_band
FROM   cb_v_application_summary
WHERE  application_id = :application_id;
```

Decision evidence reconstruction:

```sql
SELECT a.application_id,
       d.decision_outcome,
       d.risk_band,
       e.policy_code,
       e.section_ref,
       pc.chunk_id,
       e.evidence_role
FROM   cb_loan_application a
JOIN   cb_decision d ON d.application_sk = a.application_sk
JOIN   cb_decision_policy_evidence e ON e.decision_sk = d.decision_sk
JOIN   cb_policy_chunk pc ON pc.policy_chunk_sk = e.policy_chunk_sk
WHERE  a.application_id = :application_id
ORDER  BY e.evidence_id;
```

Role-filtered policy retrieval:

```sql
SELECT chunk_id, policy_code, section_ref, heading
FROM   cb_v_authorized_policy_chunks
WHERE  policy_version = '2026.0'
ORDER  BY embedding <=> :query_embedding
FETCH  FIRST 5 ROWS ONLY;
```

Role-filtered document retrieval:

```sql
SELECT chunk_id, document_id, document_type
FROM   cb_v_authorized_document_chunks
WHERE  application_id = :application_id
ORDER  BY embedding <=> :query_embedding
FETCH  FIRST 5 ROWS ONLY;
```

Graph shared-attribute signal:

```sql
SELECT source_entity_type, source_entity_id, target_entity_type, target_entity_id, relationship_type, evidence_strength, signal_status
FROM   cb_relationship_edge
WHERE  application_sk = (
  SELECT application_sk
  FROM   cb_loan_application
  WHERE  application_id = :application_id
);
```

Spatial signal:

```sql
SELECT a.application_id, s.signal_code, s.signal_type, s.signal_result, s.routing_effect, z.zone_id
FROM   cb_spatial_signal s
JOIN   cb_loan_application a ON a.application_sk = s.application_sk
LEFT JOIN cb_jurisdiction_zone z ON z.jurisdiction_zone_sk = s.jurisdiction_zone_sk
WHERE  a.application_id = :application_id;
```

Audit by application and trace:

```sql
SELECT event_action, event_outcome, object_type, object_id, created_at
FROM   cb_v_audit_redacted
WHERE  application_id = :application_id
OR     trace_id = :trace_id
ORDER  BY created_at;
```

## Security Verification

Required tests for the schema implementation:

- As applicant principal for `APP-APR-001`, `CB_V_APPLICATION_SUMMARY` returns only that applicant's application.
- As applicant principal for `APP-APR-001`, a query for `APP-MR-002` returns no rows.
- As loan officer, `CB_V_AUTHORIZED_POLICY_CHUNKS` returns loan-officer sections and excludes underwriter-only chunks.
- As underwriter, the same policy query returns loan-officer and underwriter chunks.
- As loan officer, document vector retrieval excludes underwriter-only relationship and fraud-signal chunks.
- As auditor, `CB_V_AUDIT_REDACTED` returns event metadata without raw names, addresses, full prompts, raw model responses, or raw document text.
- Runtime service account has no `DBA`, `SELECT ANY TABLE`, `DROP ANY TABLE`, `CREATE ANY TABLE`, or `EXECUTE ANY PROCEDURE` privileges.
- Schema documentation verification finds no undocumented `CB_` tables/views and no undocumented business-critical columns.
- Annotation verification finds `Domain`, `Entity`, `DataClassification`, and `OwnerService` annotations on every `CB_` table and view.
- Annotation verification finds feature annotations on every `JSON`, `VECTOR`, and `SDO_GEOMETRY` column.

## Performance Sanity Checks

The first implementation should include verification scripts that run `EXPLAIN PLAN` or equivalent checks for:

- unique index lookup by `APPLICATION_ID`;
- B-tree lookup by `WORKFLOW_ID`;
- B-tree lookup by `TRACE_ID`;
- review queue index use for open manual review tasks;
- vector index use for policy retrieval;
- vector index use for document retrieval;
- spatial index use for zone checks;
- graph query constrained by indexed relationship edge tables.

## Implementation Notes for Later DDL

- Prefer explicit Oracle data types in migrations: `NUMBER(18,0)`, `VARCHAR2`, `TIMESTAMP WITH LOCAL TIME ZONE`, `JSON`, `VECTOR`, and `MDSYS.SDO_GEOMETRY`.
- Add `COMMENT ON TABLE`, `COMMENT ON VIEW`, and `COMMENT ON COLUMN` statements as part of the same migration that creates or changes an object.
- Add Oracle schema annotations in the DDL for new objects where syntax is clean; otherwise add them in `sql/001-object-comments-and-annotations.sql` using `ALTER ... ANNOTATIONS`.
- Add check constraints for stable enumerations such as decision result, task status, purpose code, data classification, and document validation status.
- Add foreign keys for all core parent-child relationships.
- Do not put bitmap indexes on operational OLTP tables.
- Keep uploaded PDF bytes in the dedicated `CB_DOCUMENT_CONTENT` SecureFiles BLOB table owned by the loan intake boundary; do not embed them in workflow payloads, extraction JSON, audit events, or telemetry.
- Keep the `CB_DOCUMENT_INGEST_APP` runtime identity away from direct BLOB-table grants. It retrieves content through the loan service using its own OAuth service identity and persists only extraction results through its least-privilege role.
- Keep the `CB_DOCUMENT_REVIEW_APP` runtime identity away from PDF BLOBs and raw extraction payloads. It reads the bounded relational review projection and writes durable review state through `CB_DOCUMENT_REVIEW_RUNTIME`.
- Store policy and document chunk text only where authorization and redaction controls can be demonstrated.
- Ensure every row loaded from the synthetic packet corpus has `DATA_CLASSIFICATION='restricted_customer'` or an equivalent demo-safe classification.
- Do not log or store production credentials, raw prompts, raw model responses, or real customer PII.

### AI document-summary result store

Runtime migrations 029/030 add `CB_AI_DOCUMENT_SUMMARY` and
`CB_AI_AGENT_RUNTIME`. Provisioning creates `CB_AI_AGENT_APP` with its own
`AI_DATASOURCE_PASSWORD` and grants SELECT/INSERT on that result table only.
The table contains validated redacted responses, correlation metadata, and
idempotency/request hashes. It contains no prompts, raw evidence, model
reasoning, tokens, or credentials. AI evidence gathering continues through
owning service APIs; this account has no direct document, ingest, or loan table
access. The shared runtime verifier checks the account and grants.
