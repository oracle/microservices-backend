// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { runInNewContext } from 'node:vm';

function* walk(tasks) {
  for (const task of tasks) {
    yield task;
    for (const branch of Object.values(task.decisionCases ?? {})) yield* walk(branch);
    yield* walk(task.defaultCase ?? []);
  }
}

for (const filename of ['workflow-v1.json', 'workflow-v1-obaas.json']) {
  const workflow = JSON.parse(readFileSync(new URL(`../${filename}`, import.meta.url), 'utf8'));
  const tasks = [...walk(workflow.tasks)];
  const find = ref => tasks.find(task => task.taskReferenceName === ref);
  const normalize = response => JSON.parse(JSON.stringify(runInNewContext(
    find('normalize_document_summary').inputParameters.expression, { $: { summaryResponse: response } })));

  test(`${filename}: failed, absent, and rejected summaries remain unavailable`, () => {
    for (const response of [undefined, {}, { statusCode: 503 }, { statusCode: 200, body: {} },
      { statusCode: 200, body: { summaryId: `AISUM-${'0'.repeat(32)}`, status: 'COMPLETED', guardrailStatus: 'FAILED' } }]) {
      assert.deepEqual(normalize(response), {
        summaryId: '', summaryStatus: 'UNAVAILABLE', summaryUnavailableReason: 'AI_DOCUMENT_SUMMARY_UNAVAILABLE'
      });
    }
    assert.equal(find('ai_document_evidence_summary').optional, true);
    assert.equal(find('ai_document_evidence_summary').retryCount, 3);
  });

  test(`${filename}: only a validated successful response supplies a summary reference`, () => {
    const id = `AISUM-${'0'.repeat(32)}`;
    const body = { summaryId: id, status: 'COMPLETED', guardrailStatus: 'PASSED' };
    assert.deepEqual(normalize({ statusCode: 200, body }), {
      summaryId: id, summaryStatus: 'AVAILABLE', summaryUnavailableReason: ''
    });
    assert.equal(normalize({ statusCode: 503, body }).summaryStatus, 'UNAVAILABLE');
    for (const task of tasks) {
      assert.ok(!JSON.stringify(task.inputParameters ?? {}).includes('${ai_document_evidence_summary.output.response.body.summaryId}'));
    }
  });

  test(`${filename}: unavailable summaries do not add a human gate or change final initial decisions`, () => {
    const decisionRoute = find('route_initial_decision');
    assert.equal(decisionRoute.inputParameters.case, '${deterministic_initial_decision.output.response.body.outcome}');
    const decisionPath = find('route_post_evidence_disposition').defaultCase;
    const initialIndex = decisionPath.findIndex(task => task.taskReferenceName === 'deterministic_initial_decision');
    assert.ok(initialIndex >= 0);
    assert.equal(decisionPath[initialIndex + 1].taskReferenceName, 'route_initial_decision');
    for (const ref of ['route_document_summary_fallback', 'route_summary_fallback_decision',
      'human_task_document_summary_unavailable', 'use_existing_manual_review', 'document_summary_available']) {
      assert.equal(find(ref), undefined);
    }
    const initial = find('deterministic_initial_decision');
    assert.equal(initial.inputParameters.body.evidence.documentDisposition, '${select_final_review.output.result.disposition}');
    const finalExpression = find('select_final_decision').inputParameters.expression;
    for (const outcome of ['APPROVED', 'REJECTED']) {
      assert.ok([...walk(decisionRoute.decisionCases[outcome])].every(task => task.type !== 'HUMAN'));
      const result = runInNewContext(finalExpression, {
        $: { initialResponse: { body: { decisionId: 'DEC-TEST', outcome } } }
      });
      assert.equal(result.outcome, outcome);
    }
    assert.equal(workflow.outputParameters.documentSummaryStatus,
      '${normalize_document_summary.output.result.summaryStatus}');
    assert.equal(workflow.outputParameters.documentSummaryUnavailableReason,
      '${normalize_document_summary.output.result.summaryUnavailableReason}');
    assert.equal(new Set(tasks.map(task => task.taskReferenceName)).size, tasks.length);
  });

  test(`${filename}: the existing manual-review gate retains summary availability and final decisioning`, () => {
    const manualReview = find('human_task_manual_review');
    assert.deepEqual(tasks.filter(task => task.type === 'HUMAN').map(task => task.taskReferenceName),
      ['human_task_manual_review']);
    assert.ok([...walk(find('route_initial_decision').decisionCases.MANUAL_REVIEW)].includes(manualReview));
    assert.equal(manualReview.inputParameters.documentSummaryStatus,
      '${normalize_document_summary.output.result.summaryStatus}');
    assert.equal(manualReview.inputParameters.documentSummaryUnavailableReason,
      '${normalize_document_summary.output.result.summaryUnavailableReason}');
    assert.equal(find('validate_manual_review_completion').inputParameters.completion,
      '${human_task_manual_review.output}');
    assert.equal(find('deterministic_manual_final_decision').inputParameters.body.manualReview.outcome,
      '${human_task_manual_review.output.decisionOutcome}');
  });
}
