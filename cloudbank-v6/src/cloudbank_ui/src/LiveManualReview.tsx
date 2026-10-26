// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.

import { useEffect, useRef, useState } from 'react';
import { BffError, getHumanTask, getHumanTasks, resolveHumanTask,
  type BffHumanTaskDetail, type BffHumanTaskPage, type BffHumanReceipt, type BffSession } from './bff';
import { Badge, Card, Empty, Fact, PageHeading } from './ui';
import { Link } from './navigation';

function message(error: unknown): string {
  return error instanceof BffError
    ? `${error.message}${error.correlationId ? ` Reference: ${error.correlationId}` : ''}`
    : 'The human-task request could not be completed. Retry the same operation.';
}

export function LiveManualReview({ session, onSessionExpired }: {
  session: BffSession; onSessionExpired: () => void;
}) {
  const [page, setPage] = useState(0);
  const [refresh, setRefresh] = useState(0);
  const [queue, setQueue] = useState<BffHumanTaskPage | null>(null);
  const [loading, setLoading] = useState(true);
  const [queueError, setQueueError] = useState('');
  const [selected, setSelected] = useState('');
  const [detailRefresh, setDetailRefresh] = useState(0);
  const [detail, setDetail] = useState<BffHumanTaskDetail | null>(null);
  const [detailLoading, setDetailLoading] = useState(false);
  const [detailError, setDetailError] = useState('');
  const [outcome, setOutcome] = useState('APPROVED');
  const [reason, setReason] = useState('');
  const [section, setSection] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [receipt, setReceipt] = useState<BffHumanReceipt | null>(null);
  const operation = useRef<{ payload: string; key: string } | null>(null);
  const lock = useRef(false);

  const report = (error: unknown, target: (message: string) => void) => {
    if (error instanceof BffError && error.status === 401) onSessionExpired();
    else target(message(error));
  };

  useEffect(() => {
    const controller = new AbortController();
    setLoading(true);
    setQueueError('');
    getHumanTasks(page, controller.signal).then(result => {
      if (!controller.signal.aborted) {
        if (page > 0 && result.content.length === 0) setPage(Math.max(0, result.page.totalPages - 1));
        else setQueue(result);
      }
    }).catch(error => { if (!controller.signal.aborted) report(error, setQueueError); })
      .finally(() => { if (!controller.signal.aborted) setLoading(false); });
    return () => controller.abort();
  }, [page, refresh, onSessionExpired]);

  useEffect(() => {
    setDetail(null);
    setDetailError('');
    setDetailLoading(false);
    if (!selected) return;
    const controller = new AbortController();
    setDetailLoading(true);
    getHumanTask(selected, controller.signal).then(result => {
      if (!controller.signal.aborted) {
        setDetail(result);
        setOutcome(result.allowedDecisionOutcomes[0]);
        setReason(result.defaultReasonCode);
        setSection(result.defaultPolicySection);
        operation.current = null;
      }
    }).catch(error => { if (!controller.signal.aborted) report(error, setDetailError); })
      .finally(() => { if (!controller.signal.aborted) setDetailLoading(false); });
    return () => controller.abort();
  }, [selected, detailRefresh, onSessionExpired]);

  const submit = async () => {
    if (!detail || lock.current) return;
    lock.current = true;
    setSubmitting(true);
    setDetailError('');
    const input = { decisionOutcome: outcome, reasonCode: reason, policySection: section };
    const payload = JSON.stringify({ taskId: detail.task.taskId, ...input });
    if (operation.current?.payload !== payload) operation.current = { payload, key: crypto.randomUUID() };
    try {
      const result = await resolveHumanTask(detail.task, input, operation.current.key, session);
      setReceipt(result);
      setSelected('');
      setRefresh(value => value + 1);
    } catch (error) {
      report(error, setDetailError);
    } finally {
      lock.current = false;
      setSubmitting(false);
    }
  };

  const totalPages = Math.max(1, queue?.page.totalPages ?? 1);
  return <><PageHeading eyebrow="HUMAN TASKS · LIVE BFF" title="Manual review"
    description="Review pending tasks and submit a human outcome. The workflow calculates the final lending decision."
    action={<button className="button button--secondary" disabled={loading || submitting}
      onClick={() => { setSelected(''); setRefresh(value => value + 1); }}>↻ Refresh queue</button>} />
    <div className="review-layout"><Card title="Review queue" subtitle={loading ? 'Loading human tasks…'
      : queue ? `${queue.page.totalElements} authorized open tasks` : 'Queue unavailable'}>
      {queueError && <div className="live-error" role="alert">{queueError}</div>}
      {loading ? <p role="status">Loading from the workflow server…</p> : !queueError && <>
        <div className="review-list">{queue?.content.map(task => <button key={task.taskId} disabled={submitting}
          aria-pressed={selected === task.taskId}
          className={`review-item ${selected === task.taskId ? 'review-item--active' : ''}`}
          onClick={() => { setReceipt(null); setSelected(task.taskId); setDetailRefresh(value => value + 1); }}>
          <span><Badge tone="amber">{task.status.replaceAll('_', ' ')}</Badge><small>{task.priority}</small></span>
          <strong>{task.scenarioName || 'Loan application'}</strong><small className="mono">{task.applicationId}</small>
          <small>{task.reasonLabel}</small><span className="review-item-foot">Open task <b>→</b></span>
        </button>)}</div>
        {queue?.content.length === 0 && <Empty title="No open tasks">Pending CloudBank manual reviews will appear here.</Empty>}
        <div className="pagination"><span>Page {page + 1} of {totalPages}</span><div>
          <button className="button button--small button--ghost" disabled={page === 0 || submitting}
            onClick={() => setPage(value => value - 1)}>← Previous</button>
          <button className="button button--small button--ghost" disabled={page + 1 >= totalPages || submitting}
            onClick={() => setPage(value => value + 1)}>Next →</button>
        </div></div>
      </>}
    </Card><Card title={detail ? 'Complete review' : 'Task details'}
      subtitle={detail ? `${detail.task.scenarioName || 'Loan application'} · ${detail.task.applicationId}` : 'Select a task from the queue'}>
      {detailError && <div className="live-error" role="alert">{detailError}</div>}
      {detailLoading ? <p role="status">Loading task details…</p> : detail ? <>
        <div className="detail-banner"><span className="detail-banner-icon">◎</span><div>
          <strong>{detail.task.reasonLabel}</strong><p>Human review · {detail.task.taskReference}</p>
        </div></div>
        <div className="fact-grid"><Fact label="Task ID" value={detail.task.taskId} />
          <Fact label="Workflow ID" value={detail.task.workflowId} />
          <Fact label="Document review" value={detail.task.reviewId || 'Not available'} />
          <Fact label="Review assistance" value={detail.task.manualReviewAssistanceId || 'Not available'} /></div>
        <form noValidate onSubmit={event => { event.preventDefault(); void submit(); }}>
          <fieldset disabled={submitting} className="application-form-fields"><div className="field-grid">
            <label className="field"><span>Requested outcome · decisionOutcome</span>
              <select value={outcome} onChange={event => setOutcome(event.target.value)}>
                {detail.allowedDecisionOutcomes.map(value => <option key={value} value={value}>{value} · {value === 'APPROVED' ? 'Approve' : 'Reject'}</option>)}
              </select></label>
            <label className="field"><span>Reason code · reasonCode</span><input value={reason} onChange={event => setReason(event.target.value)} /></label>
            <label className="field"><span>Policy section · policySection</span><input value={section} onChange={event => setSection(event.target.value)} /></label>
            <label className="field"><span>Reviewer role · reviewerRole</span><input value={detail.reviewerRole} readOnly /></label>
            <label className="field"><span>Reviewer</span><input value={detail.reviewer} readOnly /></label>
          </div><p className="helper">The BFF verifies UNDERWRITER authorization and fills reviewerPrincipalId from your signed identity. The requested outcome remains subject to deterministic policy rules.</p>
          <div className="form-actions"><button type="submit" className="button button--primary">
            {submitting ? 'Submitting review…' : 'Complete review →'}</button></div></fieldset>
        </form>
      </> : receipt ? <div className="success-state" role="status"><strong>Human task completion accepted</strong>
        <p>Requested outcome: {receipt.decisionOutcome}. Application: {receipt.applicationId}.</p>
        <p>The workflow resumes asynchronously. Refresh the application list to follow its progress.</p>
        <Link href="/applications" className="button button--ghost">Application list →</Link>
      </div> : !detailError && <Empty title="Choose a task">Open a pending task to review its completion fields.</Empty>}
    </Card></div></>;
}
