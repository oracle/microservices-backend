// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at
// https://oss.oracle.com/licenses/upl/.

export type ArchitectureStatus = 'Implemented' | 'Planned' | 'External platform' | 'Database object';

export const architectureLanes = [
  'Platform', 'Experience', 'Boundary', 'CloudBank services',
  'Orchestration', 'Data', 'Operations', 'Future capabilities',
] as const;

interface ArchitectureComponent {
  id: string;
  name: string;
  lane: typeof architectureLanes[number];
  status: ArchitectureStatus;
  style: string;
  description: string;
  evidence: string;
  integration: string;
  security: string;
  runtime: string;
}

export const architectureComponents: ArchitectureComponent[] = [
  {
    id: 'obaas', name: 'Oracle Backend for Microservices and AI', lane: 'Platform',
    status: 'External platform', style: 'OBaaS platform',
    description: 'Hosts CloudBank with gateway routing, discovery, configuration, workflow orchestration, Oracle integration and observability.',
    evidence: 'deploy/obaas/',
    integration: 'OKE deployment helpers use the existing OBaaS platform and capability-aligned service releases.',
    security: 'Application credentials use Kubernetes Secrets and service identities.',
    runtime: 'Platform readiness and public routing depend on the target deployment.',
  },
  {
    id: 'ui', name: 'CloudBank Web GUI', lane: 'Experience',
    status: 'Implemented', style: 'React / TypeScript / Vite',
    description: 'Application list, deferred intake, PDF upload/preview, nine-tab workspace, HUMAN review and this architecture explorer.',
    evidence: 'src/cloudbank_ui/',
    integration: 'Application operations use the BFF; the architecture catalog is a static repository reference.',
    security: 'The browser uses the BFF session cookie; OAuth tokens and service credentials stay on the server.',
    runtime: 'Repository implementation does not establish availability of deployed backend services.',
  },
  {
    id: 'bff', name: 'Gateway BFF', lane: 'Boundary',
    status: 'Implemented', style: 'Spring Boot service',
    description: 'Owns login/session, authorized application operations, composed workspace reads, PDF streaming and HUMAN task completion.',
    evidence: 'src/gateway-bff-service/',
    integration: 'Checks application access through the loan owner before composing bounded service evidence.',
    security: 'Server-held OAuth tokens, HttpOnly cookies, CSRF protection and read/write scope checks.',
    runtime: 'Deploy the matching owner services; each workspace section reports its own availability.',
  },
  {
    id: 'manual-review', name: 'Manual review', lane: 'Boundary',
    status: 'Implemented', style: 'BFF / MicroTx HUMAN adapter',
    description: 'Pending task queue, authorized review details and underwriter submission through the BFF.',
    evidence: 'src/cloudbank_ui/src/LiveManualReview.tsx',
    integration: 'Completes the HUMAN task; the workflow then refreshes authorization and runs the final deterministic decision.',
    security: 'Explicit UNDERWRITER role, write scope, CSRF and idempotent submission.',
    runtime: 'A pending HUMAN task and configured MicroTx access are required.',
  },
  {
    id: 'auth', name: 'Authorization server', lane: 'CloudBank services',
    status: 'Implemented', style: 'Spring Boot / OAuth2 / OIDC',
    description: 'azn-server owns CloudBank authentication, demo users, roles, OAuth clients and signed JWTs.',
    evidence: 'src/azn-server/',
    integration: 'Registers the browser login client and the dedicated BFF workspace-read service identity.',
    security: 'Persistent signing keys, hashed credentials and endpoint-specific authorization.',
    runtime: 'Issuer, registered callback and deployed client configuration must agree.',
  },
  {
    id: 'loan', name: 'Loan application', lane: 'CloudBank services',
    status: 'Implemented', style: 'Spring Boot / Oracle Database',
    description: 'Owns durable intake, canonical application state, document inventory, immutable PDF BLOBs, audit reads and the workflow-start outbox.',
    evidence: 'src/loan-application-service/',
    integration: 'Create metadata, upload PDFs, explicitly release processing; owner APIs supply Overview, Documents and Audit.',
    security: 'User/application ownership checks and bounded, redacted reads.',
    runtime: 'Audit requires the loan image with the /audit endpoint as well as the updated BFF.',
  },
  {
    id: 'ingest', name: 'Document ingest', lane: 'CloudBank services',
    status: 'Implemented', style: 'Spring Boot service',
    description: 'Extracts authorized stored PDFs and persists structured document evidence.',
    evidence: 'src/document-ingest/',
    integration: 'MicroTx invokes extraction; ingest obtains its own service token and fetches PDF content from the loan owner.',
    security: 'PDF bytes remain outside workflow payloads and AI evidence requests.',
    runtime: 'Extraction, persistence and callback connectivity require target verification.',
  },
  {
    id: 'review', name: 'Document review', lane: 'CloudBank services',
    status: 'Implemented', style: 'Spring Boot / deterministic checks',
    description: 'Reviews bounded inventory and extraction facts for completeness, consistency and quality.',
    evidence: 'src/document-review-service/',
    integration: 'Publishes CLEAR, MANUAL_REVIEW, RETRY_EXTRACTION or BLOCKED evidence for workflow routing.',
    security: 'Receives identifiers and fetches authorized bounded projections; no PDF or direct ingest-table access.',
    runtime: 'Review dispositions are processing evidence; decision-service owns lending outcomes.',
  },
  {
    id: 'ai', name: 'AI agent', lane: 'CloudBank services',
    status: 'Implemented', style: 'Spring AI / OCI GenAI',
    description: 'Governed document summaries and manual-review assistance, plus deterministic policy evidence support.',
    evidence: 'src/ai-agent-service/',
    integration: 'Three supported workflow tasks publish validated, bounded results for BFF reads.',
    security: 'Authorized evidence only, output validation and OKE Workload Identity for OCI GenAI.',
    runtime: 'Document summaries are durable; policy support and review assistance use bounded process-local caches.',
  },
  {
    id: 'policy', name: 'Policy retrieval', lane: 'CloudBank services',
    status: 'Implemented', style: 'Spring Boot / Oracle Vector Search',
    description: 'Retrieves authorized, bounded policy chunks that support underwriting evidence.',
    evidence: 'src/policy-retrieval-service/',
    integration: 'The workflow links retrieved chunks to its execution; Policy Evidence displays those existing references through the BFF.',
    security: 'Read-only runtime identity and policy access labels bound the returned evidence.',
    runtime: 'Requires loaded policy embeddings and configured OCI embedding access.',
  },
  {
    id: 'geo', name: 'Geographic risk', lane: 'CloudBank services',
    status: 'Implemented', style: 'Helidon / Oracle Spatial',
    description: 'Produces a deterministic geographic signal and disposition for the application location.',
    evidence: 'src/geographic-risk-service/',
    integration: 'Risk Signals reads geographic evidence through the BFF; lending outcomes remain with decision-service.',
    security: 'Service authorization and bounded geographic evidence projection.',
    runtime: 'Requires Spatial schema objects and target geocoding configuration.',
  },
  {
    id: 'decision', name: 'Decision service', lane: 'CloudBank services',
    status: 'Implemented', style: 'Spring Boot / deterministic rules',
    description: 'Owns initial and manual-final lending decisions, payment facts and durable decision evidence.',
    evidence: 'src/decision-service/',
    integration: 'The BFF reads stored decisions; workflow callbacks reconcile canonical application state.',
    security: 'Deterministic policy rules and explicit human-review outcomes govern decisions.',
    runtime: 'Stored decisions and target workflow execution must be verified separately from this map.',
  },
  {
    id: 'workflow', name: 'MicroTx Workflows', lane: 'Orchestration',
    status: 'External platform', style: 'OBaaS workflow capability',
    description: 'Coordinates extraction/review retries, AI, policy/geographic evidence, decisions and the HUMAN review gate.',
    evidence: 'src/workflows/cloudbank-loan-origination/',
    integration: 'Workflow version 1 is implemented in versioned definitions and operator assets; the BFF reads a filtered task timeline.',
    security: 'Masked task authorization; raw inputs, outputs and history stay outside browser projections.',
    runtime: 'Deploy the versioned definition and verify service routing, retries and resume in the target environment.',
  },
  {
    id: 'refresh', name: 'Token refresh worker', lane: 'Orchestration',
    status: 'Implemented', style: 'Spring Boot / MicroTx SIMPLE worker',
    description: 'Refreshes workflow service authorization after a long-running HUMAN task.',
    evidence: 'src/workflow-token-refresh-worker/',
    integration: 'Resumes the authorized workflow path before the manual-final deterministic decision.',
    security: 'Refreshed credentials remain within the documented masked workflow authorization boundary.',
    runtime: 'Worker polling, refreshed authorization and workflow resume require deployment verification.',
  },
  {
    id: 'database', name: 'Oracle Database', lane: 'Data',
    status: 'Database object', style: 'Oracle relational / JSON / Vector / Spatial',
    description: 'Stores applications, immutable PDFs, structured extraction, decisions, validated summaries and redacted audit events.',
    evidence: 'src/schema/',
    integration: 'Ordered Liquibase changes and per-service runtime accounts; optional features depend on the schema profile.',
    security: 'Least-privilege accounts, data grants and redacted owner projections.',
    runtime: 'Provisioned objects, grants and feature availability depend on the selected target profile.',
  },
  {
    id: 'policy-loader', name: 'Policy loader', lane: 'Data',
    status: 'Implemented', style: 'One-shot deployment job',
    description: 'Loads the versioned synthetic policy corpus and its OCI-generated embeddings.',
    evidence: 'src/policy-loader/',
    integration: 'Runs during backend deployment; policy-retrieval-service uses its stored corpus.',
    security: 'Dedicated write identity, separate from policy retrieval runtime reads.',
    runtime: 'Corpus version, completed loading and embedding access require target verification.',
  },
  {
    id: 'audit', name: 'Application Audit', lane: 'Operations',
    status: 'Implemented', style: 'Loan owner / BFF / Oracle',
    description: 'Displays the newest 100 redacted stored application/document events with a truncation indicator.',
    evidence: 'src/loan-application-service/',
    integration: 'The BFF reads /audit with the server-held user token; complete cross-service audit coverage remains planned.',
    security: 'Application access checks; no event payloads, raw actor identities or idempotency keys.',
    runtime: 'Availability depends on the deployed loan audit endpoint and existing redacted Oracle events.',
  },
  {
    id: 'observability', name: 'OpenTelemetry / SigNoz', lane: 'Operations',
    status: 'External platform', style: 'OBaaS observability capability',
    description: 'Collects telemetry; the Trace tab shows owner-correlated spans with service, timing, status and approved attributes.',
    evidence: 'src/gateway-bff-service/src/main/java/com/cloudbank/gatewaybff/TraceReadService.java',
    integration: 'The BFF reads one authorized trace waterfall, capped at 100 spans, using a server-only Viewer API key.',
    security: 'API key from a Kubernetes Secret; no generic browser telemetry proxy or raw span payloads.',
    runtime: 'Collection, correlation, retention and API-key configuration determine span availability.',
  },
  {
    id: 'risk', name: 'Relationship / identity risk', lane: 'Future capabilities',
    status: 'Planned', style: 'Future capability',
    description: 'Broader identity, relationship and graph risk evaluation beyond the implemented geographic signal.',
    evidence: 'docs/architecture/service-boundaries.md',
    integration: 'Graph/schema assets exist; a corresponding risk evaluation service and browser contract remain planned.',
    security: 'Future contracts must preserve authorized, bounded evidence access.',
    runtime: 'No implemented relationship/identity risk evaluator is represented by this map.',
  },
  {
    id: 'ords', name: 'ORDS inspection', lane: 'Future capabilities',
    status: 'Planned', style: 'Optional read-only inspection surfaces',
    description: 'Optional database inspection APIs defined under a separate schema label.',
    evidence: 'src/schema/',
    integration: 'Separate from the implemented browser BFF and not installed by local Compose.',
    security: 'Any exposed inspection projection requires its own authorization and redaction controls.',
    runtime: 'An ORDS browser integration is not part of the current application flow.',
  },
];

export const architectureFeatures: { name: string; description: string; status: ArchitectureStatus }[] = [
  { name: 'Relational', description: 'Application, decision, outbox and redacted audit records.', status: 'Database object' },
  { name: 'SecureFiles PDFs', description: 'Immutable content owned and authorized by the loan service.', status: 'Database object' },
  { name: 'Native JSON', description: 'Structured extraction and bounded evidence persistence.', status: 'Database object' },
  { name: 'Vector Search', description: 'Policy retrieval with stored chunks and OCI embeddings.', status: 'Database object' },
  { name: 'Spatial', description: 'Deterministic geographic signals through the Helidon service.', status: 'Database object' },
  { name: 'Text / Property Graph', description: 'Schema assets; broader relationship-risk evaluation remains planned.', status: 'Database object' },
  { name: 'Access controls', description: 'OAuth scopes, data grants, redaction and service runtime accounts.', status: 'Implemented' },
  { name: 'ORDS', description: 'Optional inspection surfaces under a separate deployment label.', status: 'Planned' },
];

export const architectureAiTasks = [
  { name: 'Document Evidence Summary', mode: 'Spring AI / OCI GenAI', description: 'Validated, redacted summaries persisted in Oracle.', deterministic: false },
  { name: 'Policy Evidence Support', mode: 'Deterministic adapter', description: 'Bounded support from this execution’s authorized policy chunks.', deterministic: true },
  { name: 'Manual Review Assistant', mode: 'Spring AI / OCI GenAI', description: 'Governed reviewer checklists and clarification questions; process-local result cache.', deterministic: false },
];

export const architectureJourney = [
  { title: 'Intake & PDFs', detail: 'Loan owner / explicit workflow start' },
  { title: 'Review & evidence', detail: 'Ingest / review / AI / policy / geography' },
  { title: 'Initial decision', detail: 'Deterministic decision service' },
  { title: 'Human review', detail: 'MicroTx HUMAN when required' },
  { title: 'Resume & finalize', detail: 'Authorization refresh / final decision' },
];
