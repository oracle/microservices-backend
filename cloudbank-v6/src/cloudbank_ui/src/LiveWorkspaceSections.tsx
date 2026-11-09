import { useState, type ReactNode } from 'react';
import { BffError, startProcessing, type BffAiTask, type BffAudit, type BffDecisions, type BffPolicyEvidence,
  type BffRisks, type BffSection, type BffSession, type BffTrace, type BffTraceSpans, type BffWorkflow } from './bff';
import { Link } from './navigation';
import { Badge, Card, Empty, Fact } from './ui';
import './TraceTimeline.css';

const label = (value: string | null | undefined) => value?.replaceAll('_', ' ') || 'Not available';
const date = (value: string | null) => value ? new Date(value).toLocaleString('en-US') : '—';
const money = (value: number | null | undefined) => value == null ? 'Not available'
  : `USD ${Number(value).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

export function SectionContent<T>({ section, title, refresh, children }: {
  section: BffSection<T>; title: string; refresh: () => void; children: (data: T) => ReactNode;
}) {
  if (section.availability === 'AVAILABLE' && section.data) return children(section.data);
  return <><Empty title={`${title} · ${label(section.availability).toLowerCase()}`}>
    {section.message || 'No result is available for this execution.'}</Empty>
    {section.availability === 'ERROR' && <><button className="button button--secondary" onClick={refresh}>Reload data</button>
      <p className="helper">Reload data reads the result again. It does not execute the task or change the application.</p></>}</>;
}

export function LiveAiTasks({ items, refresh }: { items: BffAiTask[]; refresh: () => void }) {
  return <><div className="task-grid">{items.map(task => <Card key={task.taskReference} title={task.name}
    subtitle={task.implementationMode} action={<Badge tone={task.result.availability === 'AVAILABLE' ? 'teal' : 'neutral'}>{label(task.status)}</Badge>}>
    <SectionContent section={task.result} title={task.name} refresh={refresh}>{result => <>
      <div className="fact-grid"><Fact label="Result ID" value={result.resultId} /><Fact label="Guardrails" value={result.guardrailStatus} />
        <Fact label="Provider" value={result.provider} /><Fact label="Model / adapter" value={result.model} /></div>
      {result.summary && <p className="workspace-excerpt">{result.summary}</p>}
      {result.notes.length > 0 && <ul>{result.notes.map((note, i) => <li key={i}>{note}</li>)}</ul>}
      {result.checklist.length > 0 && <><h3>Reviewer checklist</h3><ul>{result.checklist.map((item, i) => <li key={i}>{item}</li>)}</ul></>}
      {result.clarificationQuestions.length > 0 && <><h3>Clarification questions</h3><ul>{result.clarificationQuestions.map((item, i) => <li key={i}>{item}</li>)}</ul></>}
      <h3>Source references</h3>{result.sourceReferences.length ? <div className="chip-row">{result.sourceReferences.map((ref, i) =>
        <Badge key={i} tone="blue">{label(ref.sourceType)} · {ref.sourceId}</Badge>)}</div> : <p className="helper">No source references were returned.</p>}
    </>}</SectionContent></Card>)}</div>
    <p className="helper">These are accepted workflow results. AI provides reviewer assistance; lending outcomes are owned by the deterministic decision service.</p></>;
}

export function LiveDecisions({ data, applicationId }: { data: BffDecisions; applicationId: string }) {
  return <>{data.items.map(entry => {
    const result = entry.result;
    const payment = entry.paymentFacts;
    return <Card key={result.decisionId} title={result.decisionType === 'MANUAL_FINAL' ? 'Final decision after human review' : 'Initial deterministic decision'}
      subtitle={result.decisionId} action={<Badge tone={result.outcome === 'APPROVED' ? 'teal' : result.outcome === 'REJECTED' ? 'rose' : 'amber'}>{label(result.outcome)}</Badge>}>
      <div className="fact-grid"><Fact label="Risk band" value={result.riskBand} /><Fact label="Decision source" value={result.decisionSource} />
        <Fact label="Policy version" value={result.policyVersion} /><Fact label="Rule profile" value={result.ruleProfileVersion} /></div>
      <h3>Reasons</h3><ul>{result.reasonCodes.map((reason, i) => <li key={i}>{label(reason)} <small className="mono">({reason})</small></li>)}</ul>
      <h3>Payment facts used by the decision</h3><div className="fact-grid"><Fact label="Evaluated amount" value={money(payment?.evaluatedAmount)} />
        <Fact label="Term" value={payment?.termMonths == null ? 'Not available' : `${payment.termMonths} months`} />
        <Fact label="Monthly payment" value={money(payment?.monthlyPayment)} /><Fact label="Calculation status" value={label(payment?.calculationStatus)} /></div>
      <h3>Policy citations</h3>{result.policyCitations.length ? <div className="policy-list">{result.policyCitations.map((citation, i) =>
        <div key={i}><div><strong>{citation.policyCode} · {citation.sectionRef}</strong><small className="mono">{citation.chunkId}</small></div>
          <Link className="button button--small button--secondary" href={`/applications/${applicationId}?tab=policy-evidence`}>Policy evidence →</Link></div>)}</div>
        : <p className="helper">No policy citations were recorded.</p>}
    </Card>;
  })}{data.truncated && <p className="helper">Only the first two decision records are shown.</p>}</>;
}

export function LivePolicyEvidence({ data }: { data: BffPolicyEvidence }) {
  return <Card title="Policy evidence used by this execution" subtitle={data.retrievalReference ? `Retrieval task · ${data.retrievalReference}` : 'Authorized workflow evidence'}>
    {data.items.length ? data.items.map((chunk, i) => <article className="workspace-policy-chunk" key={`${chunk.chunkId}/${i}`}>
      <h3>{chunk.heading}</h3><div className="chip-row"><Badge tone="blue">{chunk.policyCode}</Badge><Badge>{chunk.sectionRef}</Badge><Badge>Version {chunk.policyVersion}</Badge></div>
      <p className="workspace-excerpt">{chunk.excerpt}</p><small className="mono">{chunk.chunkId} · {chunk.policyDocumentId}</small>
      {chunk.truncated && <p className="helper">Excerpt limited to 1000 characters.</p>}</article>)
      : <Empty title="No policy evidence returned">The workflow retrieval produced no authorized policy chunks.</Empty>}
    {data.truncated && <p className="helper">The evidence collection is truncated.</p>}
  </Card>;
}

export function LiveRiskSignals({ data, refresh }: { data: BffRisks; refresh: () => void }) {
  return <><Card title="Geographic risk" subtitle="Deterministic location evidence">
    <SectionContent section={data.geographic} title="Geographic risk" refresh={refresh}>{geo => <>
      <div className="fact-grid"><Fact label="Evaluation ID" value={geo.evaluationId} /><Fact label="Disposition" value={label(geo.disposition)} /></div>
      {geo.signals.length ? <div className="table-wrap"><table><thead><tr><th>Signal</th><th>Result</th><th>Routing effect</th><th>Zone / boundary</th></tr></thead>
        <tbody>{geo.signals.map((signal, i) => <tr key={i}><td><strong>{signal.label}</strong><small className="mono">{signal.signalCode}</small></td>
          <td>{label(signal.signalResult)}</td><td>{label(signal.routingEffect)}</td><td>{signal.zoneName || signal.zoneId || 'Not available'}
            {signal.distanceToBoundaryMeters != null && <small>{Number(signal.distanceToBoundaryMeters).toLocaleString('en-US')} metres from boundary</small>}</td></tr>)}</tbody></table></div>
        : <Empty title="No geographic signals">The stored evaluation contains no signals.</Empty>}
      <p className="helper">BLOCKED is an evidence-processing disposition. The lending outcome is shown in Decision.</p>
    </>}</SectionContent></Card>
    <div className="task-grid">{(['identity', 'relationship', 'graph'] as const).map(key => <Card key={key} title={`${key[0].toUpperCase()}${key.slice(1)} risk`}>
      <Badge>{label(data[key].availability)}</Badge></Card>)}</div></>;
}

export function LiveAudit({ data }: { data: BffAudit }) {
  const objectLabels = { LOAN_APPLICATION: 'Application', DOCUMENT: 'Document', OTHER: 'Recorded object' };
  return <Card title="Application events" subtitle="Recorded application and document events · newest first">
    {data.items.length ? <div className="table-wrap"><table>
      <thead><tr><th>Date / time</th><th>Event</th><th>Actor</th><th>Outcome</th><th>Object</th><th>Trace ID</th></tr></thead>
      <tbody>{data.items.map(event => <tr key={event.eventId}>
        <td><time dateTime={event.occurredAt}>{date(event.occurredAt)}</time></td>
        <td><strong>{event.actionLabel}</strong><small className="mono">{event.action} · {event.eventId}</small></td>
        <td>{event.actorLabel}</td>
        <td><Badge tone={event.outcome === 'SUCCESS' ? 'teal' : event.outcome === 'DENIED' ? 'amber' : 'rose'}>{event.outcome}</Badge></td>
        <td>{objectLabels[event.objectType]}<small className="mono">{event.objectId || 'Reference not available'}</small></td>
        <td><span className="mono">{event.traceId || 'Not recorded'}</span></td>
      </tr>)}</tbody></table></div>
      : <Empty title="No recorded events">No audit events are available for this application.</Empty>}
    {data.truncated && <p className="helper">Showing the 100 most recent events. Earlier events are retained in the audit store.</p>}
  </Card>;
}

export function LiveTrace({ data, refresh }: { data: BffTrace; refresh: () => void }) {
  return <><Card title="Correlation" subtitle="Identifiers recorded for this application">
    <div className="fact-grid"><Fact label="Application ID" value={<span className="mono">{data.applicationId}</span>} />
      <Fact label="Workflow ID" value={<span className="mono">{data.workflowId || 'Not assigned yet'}</span>} />
      <Fact label="Trace ID" value={<span className="mono">{data.traceId || 'Not recorded'}</span>} /></div>
    {data.traceId && <p className="helper">Search SigNoz using this trace ID to inspect the recorded trace. Availability depends on telemetry collection and retention.</p>}
    {data.signozUrl && <a href={data.signozUrl} target="_blank" rel="noopener noreferrer" className="button button--secondary">Open SigNoz ↗</a>}
  </Card><Card title="Span timeline" subtitle="Recorded spans · start times and durations"
    action={<Badge tone={data.spans.availability === 'AVAILABLE' ? 'teal' : 'neutral'}>{label(data.spans.availability)}</Badge>}>
    <SectionContent section={data.spans} title="Span timeline" refresh={refresh}>
      {spans => <LiveTraceTimeline data={spans} />}</SectionContent>
  </Card></>;
}

function LiveTraceTimeline({ data }: { data: BffTraceSpans }) {
  const beginning = data.items.length ? Math.min(...data.items.map(span => Date.parse(span.startedAt))) : 0;
  const ending = data.items.length ? Math.max(...data.items.map(span => Date.parse(span.startedAt) + span.durationMs)) : 0;
  const windowMs = Math.max(ending - beginning, 1);
  const milliseconds = (value: number) => `${value.toLocaleString('en-US', { maximumFractionDigits: 3 })} ms`;
  return <>
    {data.items.length ? <><p className="helper">{data.items.length} spans displayed{data.totalSpans !== null ? ` · ${data.totalSpans} reported by telemetry` : ''}. Bars are relative to the displayed spans.</p>
      <div className="trace-span-list">{data.items.map(span => {
        const offset = Date.parse(span.startedAt) - beginning;
        return <article className="trace-span" key={span.spanId}>
          <div className="trace-span-heading"><div><strong>{span.service}</strong><span>{span.name}</span></div>
            <Badge tone={span.status === 'ERROR' ? 'rose' : span.status === 'OK' ? 'teal' : 'neutral'}>{span.status}</Badge></div>
          <div className="trace-span-track" role="img" aria-label={`Starts ${milliseconds(offset)} after the first displayed span; duration ${milliseconds(span.durationMs)}`}>
            <span className={`trace-span-bar${span.status === 'ERROR' ? ' trace-span-bar--error' : ''}`}
              style={{ marginLeft: `${offset / windowMs * 100}%`, width: `${Math.min(100 - offset / windowMs * 100, Math.max(span.durationMs / windowMs * 100, 0.3))}%` }} /></div>
          <div className="trace-span-meta"><time dateTime={span.startedAt}>{date(span.startedAt)}</time><span>{milliseconds(span.durationMs)}</span>
            <span className="mono">Span {span.spanId}</span>{span.parentSpanId && <span className="mono">Parent {span.parentSpanId}</span>}</div>
          {Object.keys(span.attributes).length > 0 && <details className="trace-span-attributes"><summary>Attributes</summary><dl>
            {Object.entries(span.attributes).map(([key, item]) => <div key={key}><dt className="mono">{key}</dt><dd>{item}</dd></div>)}</dl></details>}
        </article>;
      })}</div></> : <Empty title="No recorded spans">No spans were returned for this trace. They may not have been exported yet or may be outside telemetry retention.</Empty>}
    {data.truncated && <p className="helper">The displayed span collection is limited. Use SigNoz to inspect additional spans.</p>}
    {data.hasMissingSpans && <p className="helper">Telemetry reports missing spans. The displayed timeline is incomplete.</p>}
  </>;
}

export function LiveWorkflow({ data, applicationId, session, refresh, onSessionExpired }: {
  data: BffWorkflow; applicationId: string; session: BffSession; refresh: () => void; onSessionExpired: () => void;
}) {
  const [starting, setStarting] = useState(false);
  const [error, setError] = useState('');
  const start = async () => {
    setStarting(true); setError('');
    try { await startProcessing(applicationId, session); refresh(); }
    catch (reason) {
      if (reason instanceof BffError && reason.status === 401) onSessionExpired();
      else { setError(reason instanceof BffError ? reason.message : 'Processing could not be started.'); refresh(); }
    } finally { setStarting(false); }
  };
  const pendingHuman = data.humanTaskId && ['SCHEDULED', 'IN_PROGRESS'].includes(data.humanTaskStatus || '');
  return <Card title="CloudBank Loan Origination" subtitle={`Workflow version ${data.workflowVersion}`}>
    <div className="fact-grid"><Fact label="Dispatch" value={label(data.dispatchStatus)} /><Fact label="Execution" value={label(data.executionStatus)} />
      <Fact label="Workflow ID" value={data.workflowId || 'Not assigned yet'} /><Fact label="Human checkpoint" value={label(data.humanTaskStatus)} /></div>
    {data.humanTaskId && <div className="fact-grid"><Fact label="Human task ID" value={data.humanTaskId} /></div>}
    {data.dispatchStatus === 'DEFERRED' && !data.workflowId && <div className="start-callout"><div><strong>Awaiting explicit start</strong>
      <p>Start processing submits the stored application and documents to the existing backend checks.</p></div>
      <button className="button button--primary" disabled={starting} onClick={start}>{starting ? 'Starting…' : '▶ Start processing'}</button></div>}
    {error && <p className="live-error" role="alert">{error}</p>}
    {pendingHuman && <Link className="button button--secondary" href="/manual-review">Open manual review →</Link>}
    {data.items.length ? <div className="timeline">{data.items.map((task, i) => <div className="timeline-row" key={`${task.taskId}/${i}`}>
      <span className="timeline-node">{i + 1}</span><div><strong className="workspace-task-name">{task.name}</strong><small className="mono">{task.taskReference}</small>
        <small>Scheduled: {date(task.scheduledAt)} · Started: {date(task.startedAt)} · Ended: {date(task.endedAt)}</small>
        <small>Retries: {task.retryCount}</small></div><Badge tone={task.status === 'COMPLETED' ? 'teal' : 'neutral'}>{label(task.status)}</Badge></div>)}</div>
      : <Empty title="No tasks executed yet">The timeline appears after workflow dispatch.</Empty>}
    {data.truncated && <p className="helper">Only the first 100 tasks are shown.</p>}
  </Card>;
}
