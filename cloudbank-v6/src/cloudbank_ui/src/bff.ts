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
    headers.set('Accept', 'application/json');
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
