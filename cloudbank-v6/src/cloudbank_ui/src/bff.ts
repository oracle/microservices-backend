// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at
// https://oss.oracle.com/licenses/upl/.

export interface BffSession {
  authenticated: true;
  user: { displayName: string; username: string };
  profile: string;
  expiresAt: string;
  dataMode: 'api';
  csrfHeaderName: string;
  csrfToken: string;
}

export interface BffApplication {
  applicationId: string;
  scenarioId: string | null;
  scenarioName: string | null;
  status: string;
  requestedAmount: number | null;
  requestedTermMonths: number | null;
  createdAt: string | null;
  updatedAt: string | null;
  workflowId: string | null;
  traceId: string | null;
}

export interface BffApplicationPage {
  content: BffApplication[];
  page: { number: number; size: number; totalElements: number; totalPages: number };
}

export interface BffCreationInput {
  scenarioId: string;
  scenarioName: string;
  applicant: {
    displayName: string; phoneToken: string; emailToken: string; ageBand: string;
    address: { addressLine: string; locality: string; jurisdictionCode: string; addressToken: string; countryCode: string; postalCode: string };
  };
  loan: { requestedAmount: string; requestedTermMonths: string; purposeCode: string; policyVersion: string };
  documents: { documentType: string; fileName: string; required: boolean }[];
}

export interface BffCreatedApplication {
  applicationId: string;
  scenarioName: string;
  status: string;
  documents: BffDocument[];
  workflow: { dispatchStatus: string; workflowId: string | null };
  correlationId: string;
}

export interface BffDocument {
  documentId: string;
  documentType: string;
  documentLabel: string | null;
  fileName: string;
  required: boolean;
  status: string;
}

export interface BffUploadedDocument {
  documentId: string;
  status: string;
  mediaType: string;
  contentLengthBytes: number;
  contentSha256: string;
  correlationId: string;
}

export class BffError extends Error {
  constructor(readonly status: number, message: string, readonly correlationId: string | null = null) {
    super(message);
  }
}

async function readResponseError(response: Response): Promise<BffError> {
  const fallback = responseError(response.status);
  try {
    const body = await response.json();
    if (typeof body.code === 'string' && typeof body.message === 'string' && body.message.length <= 500) {
      return new BffError(response.status, body.message,
        typeof body.correlationId === 'string' ? body.correlationId : null);
    }
  } catch { /* A proxy or unavailable service may return a non-JSON error. */ }
  return fallback;
}

function responseError(status: number): BffError {
  if (status === 401) return new BffError(status, 'Your session has expired. Sign in again.');
  if (status === 403) return new BffError(status, 'Access denied by the BFF or loan service.');
  if (status === 503 || status === 502) return new BffError(status, 'The BFF could not complete the loan service request. Check the port-forward, service health, and authorization.');
  return new BffError(status, `The BFF request failed (HTTP ${status}).`);
}

async function request(path: string, init: RequestInit = {}): Promise<Response> {
  try {
    const headers = new Headers(init.headers);
    if (!headers.has('Accept')) headers.set('Accept', 'application/json');
    const response = await fetch(path, {
      credentials: 'same-origin',
      cache: 'no-store',
      ...init,
      headers,
    });
    if (!response.ok) throw await readResponseError(response);
    return response;
  } catch (error) {
    if (error instanceof BffError || (error instanceof DOMException && error.name === 'AbortError')) throw error;
    if (error instanceof DOMException && error.name === 'TimeoutError') {
      throw new BffError(0, 'The BFF application request timed out. Check the loan service connection and try again.');
    }
    throw new BffError(0, 'Cannot reach the BFF. Check the BFF port-forward on 127.0.0.1:8089.');
  }
}

export async function createApplication(input: BffCreationInput, key: string, session: BffSession): Promise<BffCreatedApplication> {
  const response = await request('/bff/api/v1/applications', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Idempotency-Key': key, [session.csrfHeaderName]: session.csrfToken },
    body: JSON.stringify(input),
    signal: AbortSignal.timeout(15000),
  });
  return applicationResponse(response);
}

async function applicationResponse(response: Response, expectedId?: string): Promise<BffCreatedApplication> {
  const result = await response.json() as BffCreatedApplication;
  if (response.status !== 202 || typeof result.applicationId !== 'string'
      || !/^APP-[A-Za-z0-9][A-Za-z0-9-]{0,35}$/.test(result.applicationId)
      || (expectedId !== undefined && result.applicationId !== expectedId)
      || typeof result.scenarioName !== 'string' || typeof result.status !== 'string'
      || typeof result.workflow?.dispatchStatus !== 'string' || !Array.isArray(result.documents)
      || result.documents.some(doc => !doc || typeof doc.documentId !== 'string'
        || !/^DOC-[A-Za-z0-9][A-Za-z0-9-]{0,55}$/.test(doc.documentId)
        || typeof doc.documentType !== 'string' || typeof doc.fileName !== 'string'
        || typeof doc.required !== 'boolean' || typeof doc.status !== 'string')
      || new Set(result.documents.map(doc => doc.documentId)).size !== result.documents.length) {
    throw new BffError(0, 'The application response is incomplete. Check the application list before retrying.');
  }
  return result;
}

export async function uploadDocument(applicationId: string, documentId: string, file: Blob | null,
  key: string, session: BffSession): Promise<BffUploadedDocument> {
  const content = file ?? new Blob([], { type: 'application/pdf' });
  const response = await request(`/bff/api/v1/applications/${encodeURIComponent(applicationId)}/documents/${encodeURIComponent(documentId)}/content`, {
    method: 'PUT',
    headers: { 'Content-Type': content.type || 'application/octet-stream', 'Idempotency-Key': key,
      [session.csrfHeaderName]: session.csrfToken },
    body: content,
    signal: AbortSignal.timeout(120000),
  });
  const result = await response.json() as BffUploadedDocument;
  if (response.status !== 200 || result.documentId !== documentId || typeof result.status !== 'string'
      || result.mediaType !== 'application/pdf' || typeof result.contentLengthBytes !== 'number'
      || typeof result.contentSha256 !== 'string' || !/^[0-9a-fA-F]{64}$/.test(result.contentSha256)) {
    throw new BffError(0, 'The upload response is incomplete. Retry with the same file.');
  }
  return result;
}

export async function startProcessing(applicationId: string, session: BffSession): Promise<BffCreatedApplication> {
  const response = await request(`/bff/api/v1/applications/${encodeURIComponent(applicationId)}/workflow-start`, {
    method: 'POST', headers: { [session.csrfHeaderName]: session.csrfToken },
    signal: AbortSignal.timeout(15000),
  });
  return applicationResponse(response, applicationId);
}

async function json<T>(path: string, signal?: AbortSignal): Promise<T> {
  const response = await request(path, { signal });
  if (!response.headers.get('content-type')?.includes('application/json')) {
    throw new BffError(0, 'The BFF returned an unexpected response. Check the Vite proxy and port-forward.');
  }
  return response.json() as Promise<T>;
}

export async function getSession(signal?: AbortSignal): Promise<BffSession> {
  const session = await json<BffSession>('/bff/api/v1/session', signal);
  if (session.authenticated !== true || session.dataMode !== 'api' || !session.user?.username) {
    throw new BffError(0, 'The BFF session response is incomplete.');
  }
  return session;
}

export async function getApplications(page: number, status: string, signal?: AbortSignal): Promise<BffApplicationPage> {
  const query = new URLSearchParams({ page: String(page), size: '8' });
  if (status) query.set('status', status);
  const timeout = AbortSignal.timeout(15000);
  const requestSignal = signal ? AbortSignal.any([signal, timeout]) : timeout;
  const result = await json<BffApplicationPage>(`/bff/api/v1/applications?${query}`, requestSignal);
  if (!Array.isArray(result.content) || !result.page || typeof result.page.totalElements !== 'number') {
    throw new BffError(0, 'The BFF application list response is incomplete.');
  }
  return result;
}

export async function logout(session: BffSession): Promise<void> {
  await request('/bff/auth/logout', {
    method: 'POST',
    headers: { [session.csrfHeaderName]: session.csrfToken },
  });
}

export interface BffSection<T> {
  availability: 'AVAILABLE' | 'PENDING' | 'UNAVAILABLE' | 'ERROR';
  data: T | null;
  code: string | null;
  message: string | null;
}

export interface BffOverview {
  applicant: {
    displayName: string; phoneToken: string | null; emailToken: string | null; ageBand: string | null;
    address: { addressLine: string | null; locality: string | null; jurisdictionCode: string | null;
      addressToken: string | null; countryCode: string | null; postalCode: string | null } | null;
  };
  loan: { requestedAmount: number | null; requestedTermMonths: number | null; purposeCode: string | null; policyVersion: string | null };
  status: string; createdAt: string | null; updatedAt: string | null;
}

export interface BffWorkspaceDocument extends BffDocument {
  contentAvailable: boolean;
  mediaType: string | null;
  contentLengthBytes: number | null;
  contentSha256: string | null;
}

export interface BffAiResult {
  applicationId: string; workflowId: string; taskReference: string; resultId: string;
  provider: string; model: string; guardrailStatus: string; summary: string | null;
  notes: string[]; checklist: string[]; clarificationQuestions: string[];
  sourceReferences: { sourceType: string; sourceId: string }[];
}
export interface BffAiTask {
  taskReference: string; name: string; implementationMode: string; status: string;
  result: BffSection<BffAiResult>;
}
export interface BffDecision {
  result: { decisionId: string; applicationId: string; workflowId: string; taskReference: string;
    decisionType: string; outcome: string; riskBand: string; policyVersion: string; ruleProfileVersion: string;
    decisionSource: string; reasonCodes: string[];
    policyCitations: { chunkId: string; policyCode: string; sectionRef: string }[]; traceId: string | null };
  paymentFacts: { currency: 'USD'; evaluatedAmount: number | null; termMonths: number | null;
    monthlyPayment: number | null; calculationStatus: string | null } | null;
}
export interface BffDecisions { applicationId: string; workflowId: string; items: BffDecision[]; truncated: boolean }
export interface BffPolicyEvidence {
  workflowId: string; retrievalReference: string | null;
  items: { policyDocumentId: string; policyCode: string; policyVersion: string; chunkId: string;
    sectionRef: string; heading: string; excerpt: string; truncated: boolean }[]; truncated: boolean;
}
export interface BffGeographic {
  applicationId: string; workflowId: string; taskReference: string; evaluationId: string; disposition: string;
  signals: { signalCode: string; label: string; signalResult: string; routingEffect: string;
    zoneId: string | null; zoneName: string | null; distanceToBoundaryMeters: number | null }[];
}
export interface BffRisks {
  geographic: BffSection<BffGeographic>; identity: BffSection<unknown>;
  relationship: BffSection<unknown>; graph: BffSection<unknown>;
}
export interface BffWorkflow {
  dispatchStatus: string | null; workflowId: string | null; workflowName: string; workflowVersion: number;
  executionStatus: string; items: { taskId: string; taskReference: string; name: string; status: string;
    scheduledAt: string | null; startedAt: string | null; endedAt: string | null; retryCount: number }[];
  truncated: boolean; humanTaskId: string | null; humanTaskStatus: string | null;
}

export interface BffAudit {
  applicationId: string;
  items: { eventId: string; occurredAt: string; action: string; actionLabel: string;
    actorLabel: string; outcome: 'SUCCESS' | 'DENIED' | 'ERROR';
    objectType: 'LOAN_APPLICATION' | 'DOCUMENT' | 'OTHER'; objectId: string | null; traceId: string | null }[];
  truncated: boolean;
}

export interface BffTraceSpans {
  items: { spanId: string; parentSpanId: string | null; service: string; name: string;
    startedAt: string; durationMs: number; status: 'OK' | 'ERROR' | 'UNSET'; attributes: Record<string, string> }[];
  truncated: boolean; totalSpans: number | null; hasMissingSpans: boolean;
}
export interface BffTrace {
  applicationId: string; workflowId: string | null; traceId: string | null; signozUrl: string | null;
  spans: BffSection<BffTraceSpans>;
}

export interface BffWorkspace {
  applicationId: string; scenarioId: string | null; scenarioName: string | null; status: string;
  workflowId: string | null; traceId: string | null; dispatchStatus: string | null;
  correlationId: string; source: 'LIVE'; snapshotAt: string;
  overview: BffSection<BffOverview>;
  documents: BffSection<{ items: BffWorkspaceDocument[]; truncated: boolean }>;
  aiWorkflowTasks: BffSection<{ items: BffAiTask[]; truncated: boolean }>; decision: BffSection<BffDecisions>;
  policyEvidence: BffSection<BffPolicyEvidence>; riskSignals: BffSection<BffRisks>; workflow: BffSection<BffWorkflow>;
  audit: BffSection<BffAudit>; trace: BffSection<BffTrace>;
}

export async function getApplicationWorkspace(applicationId: string, signal?: AbortSignal): Promise<BffWorkspace> {
  const result = await json<BffWorkspace>(`/bff/api/v1/applications/${encodeURIComponent(applicationId)}`, timedSignal(signal));
  const sections = ['overview', 'documents', 'aiWorkflowTasks', 'decision', 'policyEvidence', 'riskSignals', 'workflow', 'audit', 'trace'] as const;
  const invalid = () => new BffError(0, 'The BFF workspace response is incomplete. Retry loading this application.');
  if (!result || typeof result !== 'object' || result.applicationId !== applicationId || result.source !== 'LIVE' || typeof result.status !== 'string'
      || sections.some(key => !result[key] || !['AVAILABLE', 'PENDING', 'UNAVAILABLE', 'ERROR'].includes(result[key].availability)
        || (result[key].availability === 'AVAILABLE' && result[key].data == null))) throw invalid();
  if (result.overview.availability === 'AVAILABLE'
      && (!result.overview.data?.applicant || !result.overview.data.loan
        || typeof result.overview.data.applicant.displayName !== 'string')) throw invalid();
  if (result.documents.availability === 'AVAILABLE') {
    const inventory = result.documents.data;
    if (!inventory || !Array.isArray(inventory.items) || inventory.items.length > 100 || typeof inventory.truncated !== 'boolean'
        || inventory.items.some(doc => !doc || typeof doc.documentId !== 'string'
          || !/^DOC-[A-Za-z0-9][A-Za-z0-9-]{0,55}$/.test(doc.documentId)
          || typeof doc.documentType !== 'string' || typeof doc.fileName !== 'string' || typeof doc.status !== 'string'
          || typeof doc.required !== 'boolean' || typeof doc.contentAvailable !== 'boolean'
          || (doc.contentAvailable && (doc.mediaType !== 'application/pdf' || !Number.isInteger(doc.contentLengthBytes)
            || doc.contentLengthBytes! < 1 || doc.contentLengthBytes! > 25 * 1024 * 1024)))
        || new Set(inventory.items.map(doc => doc.documentId)).size !== inventory.items.length) throw invalid();
  }
  validateWorkspaceSections(result, invalid);
  return result;
}

function validateWorkspaceSections(value: BffWorkspace, invalid: () => BffError) {
  const check = (condition: unknown) => { if (!condition) throw invalid(); };
  const section = (item: BffSection<unknown>) => check(item && ['AVAILABLE', 'PENDING', 'UNAVAILABLE', 'ERROR'].includes(item.availability)
    && (item.availability === 'AVAILABLE' ? item.data != null : item.data == null));
  const text = (item: unknown, max = 200): item is string => typeof item === 'string' && item.length <= max;
  const strings = (items: unknown, count: number, max = 1000): items is string[] => Array.isArray(items)
    && items.length <= count && items.every(item => text(item, max));
  const numberOrNull = (item: unknown) => item === null || (typeof item === 'number' && Number.isFinite(item));
  const linked = (item: { applicationId: string; workflowId: string | null }) => item.applicationId === value.applicationId && item.workflowId === value.workflowId;
  if (value.aiWorkflowTasks.availability === 'AVAILABLE') {
    const data = value.aiWorkflowTasks.data!;
    check(Array.isArray(data.items) && data.items.length === 3 && typeof data.truncated === 'boolean');
    const refs = ['ai_document_evidence_summary', 'ai_policy_evidence_support', 'ai_manual_review_assistant'];
    data.items.forEach((task, index) => {
      check(task && task.taskReference === refs[index] && text(task.name) && text(task.implementationMode) && text(task.status));
      section(task.result);
      if (task.result.availability === 'AVAILABLE') {
        const ai = task.result.data!;
        check(linked(ai) && ai.taskReference === task.taskReference && /^(AISUM|AIPOL|AIREV)-[0-9a-fA-F]{32}$/.test(ai.resultId)
          && ai.guardrailStatus === 'PASSED' && text(ai.provider) && text(ai.model)
          && (ai.summary === null || text(ai.summary, 1500)) && strings(ai.notes, 8)
          && strings(ai.checklist, 12) && strings(ai.clarificationQuestions, 8)
          && Array.isArray(ai.sourceReferences) && ai.sourceReferences.length <= 100
          && ai.sourceReferences.every(ref => text(ref.sourceType) && text(ref.sourceId)));
      }
    });
  }
  if (value.decision.availability === 'AVAILABLE') {
    const data = value.decision.data!;
    check(linked(data) && Array.isArray(data.items) && data.items.length <= 2 && typeof data.truncated === 'boolean');
    data.items.forEach(entry => check(entry && entry.result && linked(entry.result)
      && /^DEC-[0-9a-f]{32}$/.test(entry.result.decisionId)
      && ['INITIAL', 'MANUAL_FINAL'].includes(entry.result.decisionType)
      && ['APPROVED', 'REJECTED', 'MANUAL_REVIEW'].includes(entry.result.outcome)
      && text(entry.result.riskBand) && text(entry.result.policyVersion) && text(entry.result.ruleProfileVersion)
      && strings(entry.result.reasonCodes, 100, 120) && Array.isArray(entry.result.policyCitations)
      && entry.result.policyCitations.length <= 10 && entry.result.policyCitations.every(ref => text(ref.chunkId) && text(ref.policyCode) && text(ref.sectionRef))
      && (entry.paymentFacts === null || (entry.paymentFacts.currency === 'USD'
        && numberOrNull(entry.paymentFacts.evaluatedAmount) && numberOrNull(entry.paymentFacts.monthlyPayment)
        && numberOrNull(entry.paymentFacts.termMonths) && (entry.paymentFacts.calculationStatus === null || text(entry.paymentFacts.calculationStatus))))));
  }
  if (value.policyEvidence.availability === 'AVAILABLE') {
    const data = value.policyEvidence.data!;
    check(data.workflowId === value.workflowId && Array.isArray(data.items) && data.items.length <= 3 && typeof data.truncated === 'boolean');
    data.items.forEach(chunk => check(chunk && text(chunk.chunkId) && text(chunk.policyDocumentId)
      && text(chunk.policyCode) && text(chunk.policyVersion) && text(chunk.sectionRef) && text(chunk.heading)
      && text(chunk.excerpt, 1000) && typeof chunk.truncated === 'boolean'));
  }
  if (value.riskSignals.availability === 'AVAILABLE') {
    const data = value.riskSignals.data!;
    [data.geographic, data.identity, data.relationship, data.graph].forEach(section);
    if (data.geographic.availability === 'AVAILABLE') {
      const geo = data.geographic.data!;
      check(linked(geo) && text(geo.evaluationId) && ['CLEAR', 'MANUAL_REVIEW', 'BLOCKED', 'NOT_EVALUATED'].includes(geo.disposition)
        && Array.isArray(geo.signals) && geo.signals.length <= 100
        && geo.signals.every(signal => text(signal.signalCode) && text(signal.label, 300) && text(signal.signalResult) && text(signal.routingEffect)));
    }
  }
  if (value.workflow.availability === 'AVAILABLE') {
    const data = value.workflow.data!;
    check(data.workflowId === value.workflowId && data.workflowName === 'cloudbank-loan-origination' && data.workflowVersion === 1
      && text(data.executionStatus) && Array.isArray(data.items) && data.items.length <= 100 && typeof data.truncated === 'boolean'
      && data.items.every(task => text(task.taskId) && text(task.taskReference) && text(task.name) && text(task.status)
        && Number.isInteger(task.retryCount) && task.retryCount >= 0));
  }
  if (value.audit.availability === 'AVAILABLE') {
    const data = value.audit.data!;
    const actions = ['INTAKE_CREATED', 'DOCUMENT_METADATA_REGISTERED', 'DOCUMENT_CONTENT_UPLOADED',
      'DOCUMENT_STATUS_CHANGED', 'APPLICATION_STATUS_CHANGED', 'DECISION_RECORDED', 'OTHER_EVENT'];
    const actionLabels = ['Application created', 'Document registered', 'Document uploaded',
      'Document status changed', 'Application status changed', 'Decision recorded', 'Recorded event'];
    check(data.applicationId === value.applicationId && Array.isArray(data.items) && data.items.length <= 100
      && typeof data.truncated === 'boolean' && data.items.every(event => event
        && typeof event.eventId === 'string' && /^AUDIT-[1-9][0-9]{0,17}$/.test(event.eventId)
        && text(event.occurredAt, 40) && Number.isFinite(Date.parse(event.occurredAt))
        && actions.includes(event.action) && actionLabels.includes(event.actionLabel)
        && ['Current user', 'Recorded actor', 'Not recorded'].includes(event.actorLabel)
        && ['SUCCESS', 'DENIED', 'ERROR'].includes(event.outcome)
        && ['LOAN_APPLICATION', 'DOCUMENT', 'OTHER'].includes(event.objectType)
        && (event.objectId === null || (event.objectType === 'LOAN_APPLICATION' && event.objectId === value.applicationId)
          || (event.objectType === 'DOCUMENT' && typeof event.objectId === 'string' && /^DOC-[A-Za-z0-9][A-Za-z0-9-]{0,55}$/.test(event.objectId)))
        && (event.traceId === null || (typeof event.traceId === 'string' && /^[0-9a-fA-F]{32}$/.test(event.traceId)))));
    check(new Set(data.items.map(event => event.eventId)).size === data.items.length);
  }
  if (value.trace.availability === 'AVAILABLE') {
    const data = value.trace.data!;
    const ownerTraceId = typeof value.traceId === 'string' && /^(?!0{32}$)[0-9a-fA-F]{32}$/.test(value.traceId)
      ? value.traceId.toLowerCase() : null;
    check(linked(data) && (data.traceId === null || (typeof data.traceId === 'string'
      && /^(?!0{32}$)[0-9a-f]{32}$/.test(data.traceId))) && data.traceId === ownerTraceId);
    if (data.signozUrl !== null) {
      try {
        const url = new URL(data.signozUrl);
        check(['http:', 'https:'].includes(url.protocol) && !url.username && !url.password && !url.search && !url.hash);
      } catch { throw invalid(); }
    }
    section(data.spans);
    if (data.spans.availability === 'AVAILABLE') {
      const spans = data.spans.data!;
      const services = ['loan-application-service', 'document-ingest', 'document-review-service', 'ai-agent-service',
        'decision-service', 'geographic-risk-service', 'policy-retrieval-service', 'workflow-token-refresh-worker',
        'gateway-bff-service', 'azn-server', 'workflow-server', 'microtx-workflow-server', 'Other instrumented service'];
      const attributes: Record<string, (item: string) => boolean> = {
        'http.request.method': item => ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS'].includes(item),
        'http.response.status_code': item => /^[1-5][0-9]{2}$/.test(item),
        'db.operation': item => ['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'COMMIT', 'ROLLBACK', 'CALL', 'EXECUTE'].includes(item),
        'db.system': item => ['oracle', 'postgresql', 'mysql', 'mariadb', 'sqlite', 'redis', 'clickhouse'].includes(item),
        'gen_ai.operation.name': item => ['chat', 'embeddings', 'embedding', 'text_completion'].includes(item),
        'gen_ai.system': item => ['oci-genai', 'oracle', 'openai', 'cohere'].includes(item),
        'application.id': item => item === value.applicationId,
        'workflow.id': item => item === value.workflowId,
      };
      const names = ['Instrumented operation', 'GET request', 'POST request', 'PUT request', 'PATCH request',
        'DELETE request', 'HEAD request', 'OPTIONS request', 'Database SELECT', 'Database INSERT', 'Database UPDATE',
        'Database DELETE', 'Database COMMIT', 'Database ROLLBACK', 'Database CALL', 'Database EXECUTE',
        'AI chat', 'AI embeddings', 'AI embedding', 'AI text_completion'];
      check(data.traceId !== null && Array.isArray(spans.items) && spans.items.length <= 100
        && typeof spans.truncated === 'boolean' && typeof spans.hasMissingSpans === 'boolean'
        && (spans.totalSpans === null || (Number.isSafeInteger(spans.totalSpans) && spans.totalSpans >= 0))
        && spans.items.every(span => span && typeof span.spanId === 'string' && /^(?!0{16}$)[0-9a-f]{16}$/.test(span.spanId)
          && (span.parentSpanId === null || (/^(?!0{16}$)[0-9a-f]{16}$/.test(span.parentSpanId) && span.parentSpanId !== span.spanId))
          && services.includes(span.service) && names.includes(span.name)
          && text(span.startedAt, 40) && Number.isFinite(Date.parse(span.startedAt))
          && Number.isFinite(span.durationMs) && span.durationMs >= 0 && ['OK', 'ERROR', 'UNSET'].includes(span.status)
          && span.attributes && typeof span.attributes === 'object' && !Array.isArray(span.attributes)
          && Object.entries(span.attributes).length <= 8 && Object.entries(span.attributes)
            .every(([key, item]) => typeof item === 'string' && Object.hasOwn(attributes, key) && attributes[key](item))));
      check(new Set(spans.items.map(span => span.spanId)).size === spans.items.length);
    }
  }
}

export function documentContentUrl(applicationId: string, documentId: string): string {
  return `/bff/api/v1/applications/${encodeURIComponent(applicationId)}/documents/${encodeURIComponent(documentId)}/content`;
}

export async function getDocumentPdf(applicationId: string, documentId: string, signal?: AbortSignal): Promise<Blob> {
  const timeout = AbortSignal.timeout(120000);
  const response = await request(documentContentUrl(applicationId, documentId), {
    headers: { Accept: 'application/pdf' }, signal: signal ? AbortSignal.any([signal, timeout]) : timeout,
  });
  const limit = 25 * 1024 * 1024;
  const declared = response.headers.get('content-length');
  const invalid = () => new BffError(502, 'The PDF response is unavailable or invalid. Retry opening the document.');
  if (response.status !== 200 || response.headers.get('content-type')?.split(';')[0].trim().toLowerCase() !== 'application/pdf'
      || (declared !== null && (!/^\d+$/.test(declared) || Number(declared) < 1 || Number(declared) > limit))) {
    await response.body?.cancel();
    throw invalid();
  }
  const reader = response.body?.getReader();
  if (!reader) throw invalid();
  const parts: BlobPart[] = [];
  let size = 0;
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > limit) { await reader.cancel(); throw invalid(); }
      parts.push(new Uint8Array(value));
    }
  } finally { reader.releaseLock(); }
  if (size === 0 || (declared !== null && size !== Number(declared))) throw invalid();
  return new Blob(parts, { type: 'application/pdf' });
}

export interface BffHumanTask {
  taskId: string; applicationId: string; scenarioId: string | null; scenarioName: string | null;
  workflowId: string; taskReference: string; status: string; priority: string;
  reasonCode: string; reasonLabel: string; scheduledAt: string | null; updatedAt: string | null;
  reviewId: string | null; documentSummaryId: string | null;
  manualReviewAssistanceId: string | null; initialDecisionId: string | null;
}

export interface BffHumanTaskPage {
  content: BffHumanTask[];
  page: BffApplicationPage['page'];
}

export interface BffHumanTaskDetail {
  task: BffHumanTask; allowedDecisionOutcomes: string[]; defaultReasonCode: string;
  defaultPolicySection: string; reviewerRole: string; reviewer: string; correlationId: string;
}

export interface BffHumanResolution {
  decisionOutcome: string; reasonCode: string; policySection: string;
}

export interface BffHumanReceipt {
  taskId: string; applicationId: string; workflowId: string; completionStatus: 'ACCEPTED';
  decisionOutcome: string; correlationId: string;
}

function isHumanTask(value: BffHumanTask): boolean {
  return Boolean(value && typeof value.taskId === 'string' && typeof value.applicationId === 'string'
    && typeof value.workflowId === 'string' && value.taskReference === 'human_task_manual_review'
    && typeof value.status === 'string' && typeof value.reasonLabel === 'string');
}

function timedSignal(signal?: AbortSignal): AbortSignal {
  const timeout = AbortSignal.timeout(30000);
  return signal ? AbortSignal.any([signal, timeout]) : timeout;
}

export async function getHumanTasks(page: number, signal?: AbortSignal): Promise<BffHumanTaskPage> {
  const query = new URLSearchParams({ page: String(page), size: '8' });
  const result = await json<BffHumanTaskPage>(`/bff/api/v1/manual-review/tasks?${query}`, timedSignal(signal));
  if (!Array.isArray(result.content) || result.content.some(task => !isHumanTask(task))
      || !result.page || typeof result.page.totalElements !== 'number') {
    throw new BffError(0, 'The BFF human-task queue response is incomplete.');
  }
  return result;
}

export async function getHumanTask(taskId: string, signal?: AbortSignal): Promise<BffHumanTaskDetail> {
  const result = await json<BffHumanTaskDetail>(`/bff/api/v1/manual-review/tasks/${encodeURIComponent(taskId)}`, timedSignal(signal));
  if (!isHumanTask(result.task) || result.task.taskId !== taskId
      || !Array.isArray(result.allowedDecisionOutcomes) || result.allowedDecisionOutcomes.length !== 2
      || !result.allowedDecisionOutcomes.includes('APPROVED') || !result.allowedDecisionOutcomes.includes('REJECTED')
      || result.reviewerRole !== 'UNDERWRITER' || typeof result.reviewer !== 'string'
      || typeof result.defaultReasonCode !== 'string' || typeof result.defaultPolicySection !== 'string') {
    throw new BffError(0, 'The BFF human-task detail response is incomplete. Refresh the queue.');
  }
  return result;
}

export async function resolveHumanTask(task: BffHumanTask, input: BffHumanResolution,
  key: string, session: BffSession): Promise<BffHumanReceipt> {
  const response = await request(`/bff/api/v1/manual-review/tasks/${encodeURIComponent(task.taskId)}/resolution`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', 'Idempotency-Key': key,
      [session.csrfHeaderName]: session.csrfToken },
    body: JSON.stringify({ decisionOutcome: input.decisionOutcome, reasonCode: input.reasonCode, policySection: input.policySection }),
    signal: timedSignal(),
  });
  const result = await response.json() as BffHumanReceipt;
  if (response.status !== 202 || result.taskId !== task.taskId || result.applicationId !== task.applicationId
      || result.workflowId !== task.workflowId || result.completionStatus !== 'ACCEPTED'
      || result.decisionOutcome !== input.decisionOutcome) {
    throw new BffError(0, 'The completion response is incomplete. Retry the same resolution to check its acceptance.');
  }
  return result;
}
