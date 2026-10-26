// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.

import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import ts from 'typescript';

async function sourceModule(path) {
  const moduleUrl = new URL(path, import.meta.url);
  let source = await readFile(moduleUrl, 'utf8');
  for (const [statement, name, file] of [...source.matchAll(/^import (\w+) from ['"]([^'"]+\.json)['"];$/gm)]) {
    const value = JSON.parse(await readFile(new URL(file, moduleUrl), 'utf8'));
    source = source.replace(statement, `const ${name} = ${JSON.stringify(value)};`);
  }
  const { outputText } = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ES2022 } });
  return import(`data:text/javascript;base64,${Buffer.from(outputText).toString('base64')}`);
}
const { createApplication, uploadDocument, startProcessing, getHumanTasks, getHumanTask, resolveHumanTask, BffError } = await sourceModule('../src/bff.ts');
const { bindDocumentFiles } = await sourceModule('../src/intake.ts');
const { createNewApplicationDraft, createNewApplicationDocuments } = await sourceModule('../src/newApplicationDefaults.ts');
const session = { csrfHeaderName: 'X-CSRF-TOKEN', csrfToken: 'synthetic-csrf' };

test('GUI defaults share the ready CLI packet and receive fresh correlation values for each opening', async () => {
  const template = JSON.parse(await readFile(new URL('../../../synthetic_data/customer_packets/demo_geocoded_loan/application.json', import.meta.url), 'utf8'));
  const one = createNewApplicationDraft();
  const two = createNewApplicationDraft();
  assert.equal(one.name, template.scenarioName);
  assert.equal(one.applicant, template.applicant.displayName);
  assert.equal(one.amount, template.loan.requestedAmount.toFixed(2));
  assert.equal(one.addressLine, template.applicant.address.addressLine);
  assert.notEqual(one.scenarioId, two.scenarioId);
  assert.notEqual(one.phoneToken, two.phoneToken);
  assert.equal('applicationId' in one, false);
  assert.deepEqual(createNewApplicationDocuments().map(({ rowId, file, ...metadata }) => metadata), template.documents);
});
const input = {
  scenarioId: 'SCN-NEW', scenarioName: 'Synthetic Applicant',
  applicant: { displayName: 'Synthetic Applicant', phoneToken: 'PHONE-SYNTH', emailToken: 'EMAIL-SYNTH', ageBand: '35-44',
    address: { addressLine: '10 Demo Avenue', locality: 'Demo City', jurisdictionCode: 'US-CA', addressToken: 'ADDR-SYNTH', countryCode: '', postalCode: '' } },
  loan: { requestedAmount: '12000.00', requestedTermMonths: '36', purposeCode: 'HOME_IMPROVEMENT', policyVersion: '' },
  documents: [{ documentType: 'LOAN_APPLICATION', fileName: 'synthetic.pdf', required: true }],
};
const created = { applicationId: 'APP-NEW-1', scenarioName: 'Synthetic Applicant', status: 'SUBMITTED',
  documents: [{ documentId: 'DOC-NEW-1', documentType: 'LOAN_APPLICATION', documentLabel: 'Loan application',
    fileName: 'synthetic.pdf', required: true, status: 'EXPECTED' }],
  workflow: { dispatchStatus: 'DEFERRED', workflowId: null }, correlationId: 'synthetic-reference' };

test('creation uses the session CSRF header and sends JSON metadata only to the BFF', async t => {
  const calls = [];
  t.mock.method(globalThis, 'fetch', async (url, options) => {
    calls.push({ url, options });
    return Response.json(created, { status: 202 });
  });
  assert.deepEqual(await createApplication(input, 'operation-123', session), created);
  const [{ url, options }] = calls;
  assert.equal(url, '/bff/api/v1/applications');
  assert.equal(options.method, 'POST');
  assert.equal(options.credentials, 'same-origin');
  assert.equal(options.cache, 'no-store');
  assert.equal(options.headers.get('Content-Type'), 'application/json');
  assert.equal(options.headers.get('X-CSRF-TOKEN'), session.csrfToken);
  assert.equal(options.headers.get('Idempotency-Key'), 'operation-123');
  assert.equal(options.headers.has('Authorization'), false);
  assert.deepEqual(JSON.parse(options.body), input);
  assert.equal(calls.length, 1);
});

test('a retry keeps the supplied operation key after an uncertain network failure', async t => {
  const keys = [];
  t.mock.method(globalThis, 'fetch', async (_url, options) => {
    keys.push(options.headers.get('Idempotency-Key'));
    if (keys.length === 1) throw new TypeError('Network disconnected');
    return Response.json(created, { status: 202 });
  });
  await assert.rejects(createApplication(input, 'operation-123', session), BffError);
  assert.deepEqual(await createApplication(input, 'operation-123', session), created);
  assert.deepEqual(keys, ['operation-123', 'operation-123']);
});

test('backend errors retain their safe message and correlation reference', async t => {
  t.mock.method(globalThis, 'fetch', async () => Response.json({ code: 'REQUEST_REJECTED',
    message: 'Application metadata was rejected.', correlationId: 'safe-reference', retryable: false,
    authorizationStatus: 'AUTHENTICATED' }, { status: 422 }));
  await assert.rejects(createApplication(input, 'operation-123', session), error =>
    error instanceof BffError && error.status === 422 && error.message === 'Application metadata was rejected.'
    && error.correlationId === 'safe-reference');
});

test('an HTML proxy failure produces a safe error', async t => {
  t.mock.method(globalThis, 'fetch', async () => new Response('<html>internal details</html>', { status: 502 }));
  await assert.rejects(createApplication(input, 'operation-123', session), error =>
    error instanceof BffError && error.status === 502 && !error.message.includes('internal details'));
});

test('an incomplete creation response cannot become a successful GUI confirmation', async t => {
  t.mock.method(globalThis, 'fetch', async () => Response.json({ applicationId: 'APP-NEW-1', workflow: {} }, { status: 202 }));
  await assert.rejects(createApplication(input, 'operation-123', session), BffError);
});

test('upload sends the selected bytes and CSRF to the returned document ID without starting a workflow', async t => {
  const file = new Blob(['%PDF-1.7\nsynthetic content'], { type: 'application/pdf' });
  const receipt = { documentId: 'DOC-NEW-1', status: 'RECEIVED', mediaType: 'application/pdf',
    contentLengthBytes: file.size, contentSha256: 'a'.repeat(64), correlationId: 'synthetic-upload-reference' };
  const calls = [];
  t.mock.method(globalThis, 'fetch', async (url, options) => {
    calls.push(url);
    assert.equal(url, '/bff/api/v1/applications/APP-NEW-1/documents/DOC-NEW-1/content');
    assert.equal(options.method, 'PUT');
    assert.equal(options.body, file);
    assert.equal(await options.body.text(), '%PDF-1.7\nsynthetic content');
    assert.equal(options.headers.get('Content-Type'), 'application/pdf');
    assert.equal(options.headers.get('X-CSRF-TOKEN'), session.csrfToken);
    assert.equal(options.headers.get('Idempotency-Key'), 'upload-operation-1');
    assert.equal(options.headers.has('Authorization'), false);
    return Response.json(receipt);
  });
  assert.deepEqual(await uploadDocument('APP-NEW-1', 'DOC-NEW-1', file, 'upload-operation-1', session), receipt);
  assert.equal(calls.length, 1);
});

test('a failed upload retry resends the same bytes and logical operation key', async t => {
  const file = new Blob(['%PDF-1.7\nsynthetic content'], { type: 'application/pdf' });
  const keys = [];
  const bodies = [];
  t.mock.method(globalThis, 'fetch', async (_url, options) => {
    keys.push(options.headers.get('Idempotency-Key'));
    bodies.push(options.body);
    if (keys.length === 1) throw new TypeError('Network disconnected');
    return Response.json({ documentId: 'DOC-NEW-1', status: 'RECEIVED', mediaType: 'application/pdf',
      contentLengthBytes: file.size, contentSha256: 'a'.repeat(64) });
  });
  await assert.rejects(uploadDocument('APP-NEW-1', 'DOC-NEW-1', file, 'upload-operation-1', session), BffError);
  await uploadDocument('APP-NEW-1', 'DOC-NEW-1', file, 'upload-operation-1', session);
  assert.deepEqual(keys, ['upload-operation-1', 'upload-operation-1']);
  assert.equal(bodies[0], bodies[1]);
});

test('no selected file is submitted to backend checks rather than blocked by UI validation', async t => {
  let calls = 0;
  t.mock.method(globalThis, 'fetch', async (_url, options) => {
    calls++;
    assert.equal(options.body.size, 0);
    return Response.json({ code: 'DOCUMENT_SIZE_INVALID', message: 'PDF content must contain between 1 byte and 25 MiB' }, { status: 413 });
  });
  await assert.rejects(uploadDocument('APP-NEW-1', 'DOC-NEW-1', null, 'upload-operation-1', session), error =>
    error instanceof BffError && error.status === 413);
  assert.equal(calls, 1);
});

test('an upload receipt for a different document cannot confirm success', async t => {
  t.mock.method(globalThis, 'fetch', async () => Response.json({ documentId: 'DOC-OTHER', status: 'RECEIVED',
    mediaType: 'application/pdf', contentLengthBytes: 1, contentSha256: 'a'.repeat(64) }));
  await assert.rejects(uploadDocument('APP-NEW-1', 'DOC-NEW-1', new Blob(['x']), 'upload-operation-1', session), BffError);
});

test('start is an explicit empty-body CSRF-protected loan-release request', async t => {
  t.mock.method(globalThis, 'fetch', async (url, options) => {
    assert.equal(url, '/bff/api/v1/applications/APP-NEW-1/workflow-start');
    assert.equal(options.method, 'POST');
    assert.equal(options.body, undefined);
    assert.equal(options.headers.get('X-CSRF-TOKEN'), session.csrfToken);
    assert.equal(options.headers.has('Authorization'), false);
    return Response.json({ ...created, workflow: { dispatchStatus: 'PENDING', workflowId: null } }, { status: 202 });
  });
  const result = await startProcessing('APP-NEW-1', session);
  assert.equal(result.workflow.dispatchStatus, 'PENDING');
  assert.equal(result.status, 'SUBMITTED');
});

test('a start response must belong to the selected application', async t => {
  t.mock.method(globalThis, 'fetch', async () => Response.json({ ...created, applicationId: 'APP-OTHER' }, { status: 202 }));
  await assert.rejects(startProcessing('APP-NEW-1', session), BffError);
});

test('file selection follows returned metadata and IDs even when the server reorders documents', () => {
  const loan = { ...created.documents[0], rowId: 'row-loan', file: { name: 'synthetic.pdf' } };
  const pay = { documentType: 'PAY_STATEMENT', fileName: 'pay.pdf', required: true, rowId: 'row-pay', file: { name: 'pay.pdf' } };
  const bound = bindDocumentFiles([loan, pay], [{ ...pay, documentId: 'DOC-PAY', status: 'EXPECTED' }, { ...loan, documentId: 'DOC-LOAN' }]);
  assert.equal(bound['DOC-LOAN'], loan.file);
  assert.equal(bound['DOC-PAY'], pay.file);
});

test('ambiguous metadata requires a new explicit file choice instead of guessing a document ID', () => {
  const row = { ...created.documents[0], rowId: 'row-loan', file: { name: 'synthetic.pdf' } };
  assert.deepEqual(bindDocumentFiles([row, { ...row, rowId: 'duplicate' }], created.documents), {});
  assert.deepEqual(bindDocumentFiles([row], [created.documents[0], { ...created.documents[0], documentId: 'DOC-OTHER' }]), {});
});

const humanTask = { taskId: 'task-one', applicationId: 'APP-ONE', workflowId: 'wf-one',
  scenarioName: 'Synthetic manual review', taskReference: 'human_task_manual_review', status: 'IN_PROGRESS',
  reasonLabel: 'Document evidence requires review' };
const resolution = { decisionOutcome: 'REJECTED', reasonCode: 'DOCUMENT_EXCEPTION_RESOLVED', policySection: 'CBPL-150-S4' };
const humanReceipt = { taskId: 'task-one', applicationId: 'APP-ONE', workflowId: 'wf-one',
  completionStatus: 'ACCEPTED', decisionOutcome: 'REJECTED', correlationId: 'safe-reference' };

test('human queue and selected task detail are fetched through the BFF without browser bearer tokens', async t => {
  const detail = { task: humanTask, allowedDecisionOutcomes: ['APPROVED', 'REJECTED'],
    defaultReasonCode: 'DOCUMENT_EXCEPTION_RESOLVED', defaultPolicySection: 'CBPL-150-S4',
    reviewerRole: 'UNDERWRITER', reviewer: 'obaas-admin' };
  const calls = [];
  t.mock.method(globalThis, 'fetch', async (url, options) => {
    calls.push(url);
    assert.equal(options.credentials, 'same-origin');
    assert.equal(options.headers.has('Authorization'), false);
    return Response.json(url.includes('?') ? { content: [humanTask], page: { totalElements: 1 } } : detail);
  });
  assert.equal((await getHumanTasks(0)).content[0].taskId, 'task-one');
  assert.deepEqual(await getHumanTask('task-one'), detail);
  assert.deepEqual(calls, ['/bff/api/v1/manual-review/tasks?page=0&size=8', '/bff/api/v1/manual-review/tasks/task-one']);
});

test('human completion sends only the three editable fields with CSRF and a logical operation key', async t => {
  t.mock.method(globalThis, 'fetch', async (url, options) => {
    assert.equal(url, '/bff/api/v1/manual-review/tasks/task-one/resolution');
    assert.equal(options.method, 'POST');
    assert.equal(options.headers.get('X-CSRF-TOKEN'), session.csrfToken);
    assert.equal(options.headers.get('Idempotency-Key'), 'resolution-one');
    assert.equal(options.headers.has('Authorization'), false);
    assert.deepEqual(JSON.parse(options.body), resolution);
    return Response.json(humanReceipt, { status: 202 });
  });
  assert.deepEqual(await resolveHumanTask(humanTask, { ...resolution, reviewerRole: 'UNTRUSTED',
    reviewerPrincipalId: 'browser-principal' }, 'resolution-one', session), humanReceipt);
});

test('a human-completion retry retains its outcome and operation key after a network timeout', async t => {
  const keys = [];
  t.mock.method(globalThis, 'fetch', async (_url, options) => {
    keys.push(options.headers.get('Idempotency-Key'));
    if (keys.length === 1) throw new TypeError('Synthetic connection lost');
    return Response.json(humanReceipt, { status: 202 });
  });
  await assert.rejects(resolveHumanTask(humanTask, resolution, 'resolution-one', session), BffError);
  assert.deepEqual(await resolveHumanTask(humanTask, resolution, 'resolution-one', session), humanReceipt);
  assert.deepEqual(keys, ['resolution-one', 'resolution-one']);
});

test('a receipt for another task or outcome cannot confirm successful human completion', async t => {
  for (const patch of [{ taskId: 'another-task' }, { decisionOutcome: 'APPROVED' }, { applicationId: 'APP-OTHER' },
    { workflowId: 'wf-other' }, { completionStatus: 'COMPLETED' }]) {
    t.mock.method(globalThis, 'fetch', async () => Response.json({ ...humanReceipt, ...patch }, { status: 202 }));
    await assert.rejects(resolveHumanTask(humanTask, resolution, 'resolution-one', session), BffError);
  }
});

test('a stale task conflict remains visible with its safe correlation reference', async t => {
  t.mock.method(globalThis, 'fetch', async () => Response.json({ code: 'CONFLICT',
    message: 'The task state or resolution has changed.', correlationId: 'safe-reference' }, { status: 409 }));
  await assert.rejects(resolveHumanTask(humanTask, resolution, 'resolution-one', session), error =>
    error instanceof BffError && error.status === 409 && error.correlationId === 'safe-reference');
});

test('workflow v1 HUMAN fields and allowed outcomes agree with the browser completion contract', async () => {
  const workflow = JSON.parse(await readFile(new URL('../../workflows/cloudbank-loan-origination/workflow-v1-obaas.json', import.meta.url), 'utf8'));
  function findHuman(value) {
    if (!value || typeof value !== 'object') return null;
    if (value.type === 'HUMAN' && value.taskReferenceName === 'human_task_manual_review') return value;
    return Object.values(value).map(findHuman).find(Boolean);
  }
  const human = findHuman(workflow);
  assert.deepEqual(human.inputParameters.allowedDecisionOutcomes.split(','), ['APPROVED', 'REJECTED']);
  assert.equal(human.inputParameters.requiredReviewerRole, 'UNDERWRITER');
  assert.deepEqual(human.inputParameters.requiredCompletionFields.split(','),
    ['decisionOutcome', 'reviewerRole', 'reviewerPrincipalId', 'reasonCode', 'policySection']);
});
