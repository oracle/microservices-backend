import { useEffect, useState, type KeyboardEvent } from 'react';
import { BffError, getApplicationWorkspace, type BffOverview, type BffSession, type BffWorkspace } from './bff';
import { LiveAiTasks, LiveAudit, LiveDecisions, LivePolicyEvidence, LiveRiskSignals, LiveTrace, LiveWorkflow, SectionContent } from './LiveWorkspaceSections';
import { LiveDocumentDetails } from './LiveDocumentDetails';
import { go, Link } from './navigation';
import { Badge, Card, Empty, Fact, PageHeading } from './ui';
import { workspaceTabs as tabs } from './workspaceTabs';

const unavailableKeys: Record<string, 'aiWorkflowTasks' | 'decision' | 'policyEvidence' | 'riskSignals' | 'workflow' | 'audit' | 'trace'> = {
  'ai-tasks': 'aiWorkflowTasks', decision: 'decision', 'policy-evidence': 'policyEvidence',
  'risk-signals': 'riskSignals', workflow: 'workflow', audit: 'audit', trace: 'trace',
};

export function LiveWorkspace({ applicationId, path, session, onSessionExpired }: {
  applicationId: string; path: string; session: BffSession; onSessionExpired: () => void;
}) {
  const [workspace, setWorkspace] = useState<BffWorkspace | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [revision, setRevision] = useState(0);
  const query = new URLSearchParams(path.split('?')[1] ?? '');
  const requested = query.get('tab') || 'overview';
  const active = tabs.some(([key]) => key === requested) ? requested : 'overview';
  const selectedId = active === 'documents' ? query.get('document') : null;

  useEffect(() => {
    const controller = new AbortController();
    setLoading(true); setError('');
    getApplicationWorkspace(applicationId, controller.signal).then(result => {
      if (!controller.signal.aborted) setWorkspace(result);
    }).catch(reason => {
      if (controller.signal.aborted) return;
      setWorkspace(null);
      if (reason instanceof BffError && reason.status === 401) onSessionExpired();
      else setError(reason instanceof BffError ? reason.message : 'The application could not be loaded.');
    }).finally(() => { if (!controller.signal.aborted) setLoading(false); });
    return () => controller.abort();
  }, [applicationId, revision, onSessionExpired]);

  const execution = workspace?.workflow.data?.executionStatus;
  const polling = workspace && (['RUNNING', 'PAUSED'].includes(execution || '')
    || (!execution && ['PROCESSING', 'MANUAL_REVIEW'].includes(workspace.status))
    || ['PENDING', 'IN_PROGRESS'].includes(workspace.dispatchStatus || '')
    || (workspace.status === 'SUBMITTED' && workspace.dispatchStatus === 'STARTED'));
  useEffect(() => {
    if (!polling || loading) return;
    const timer = window.setTimeout(() => setRevision(value => value + 1), 5000);
    return () => window.clearTimeout(timer);
  }, [polling, loading]);
  const refresh = () => setRevision(value => value + 1);

  const select = (tab: string) => go(`/applications/${applicationId}?tab=${tab}`);
  const onTabKeyDown = (event: KeyboardEvent<HTMLButtonElement>, index: number) => {
    if (!['ArrowDown', 'ArrowUp', 'Home', 'End'].includes(event.key)) return;
    event.preventDefault();
    const next = event.key === 'Home' ? 0 : event.key === 'End' ? tabs.length - 1
      : (index + (event.key === 'ArrowDown' ? 1 : -1) + tabs.length) % tabs.length;
    select(tabs[next][0]);
    requestAnimationFrame(() => document.getElementById(`tab-${tabs[next][0]}`)?.focus());
  };

  if (!workspace) return <><PageHeading eyebrow="APPLICATION WORKSPACE · API" title="Application details"
    action={<Link href="/applications" className="button button--ghost">← Application list</Link>} />
    {loading ? <p role="status" className="live-loading">Loading application…</p> : <Card title="Application unavailable">
      <p role="alert" className="live-error">{error}</p><button className="button button--secondary" onClick={() => setRevision(value => value + 1)}>Retry</button>
    </Card>}</>;

  const title = workspace.scenarioName || 'Loan application';
  const tabTitle = tabs.find(([key]) => key === active)![1];
  const inventory = workspace.documents.availability === 'AVAILABLE' ? workspace.documents.data : null;
  const selected = inventory?.items.find(doc => doc.documentId === selectedId);
  const unavailable = unavailableKeys[active] ? workspace[unavailableKeys[active]] : null;

  return <><div className="workspace-breadcrumb"><Link href="/applications">Applications</Link><span>/</span><span>{title}</span></div>
    <div className="workspace-header"><div><div className="eyebrow">APPLICATION WORKSPACE · API</div><h1>{title}</h1>
      <p>Application, evidence, decision and workflow results read through the authorized CloudBank BFF.</p>
      <div className="workspace-meta"><span className="mono">{workspace.applicationId}</span>
        <Badge tone="blue">{workspace.status.replaceAll('_', ' ')}</Badge><Badge>obaas-admin profile</Badge></div></div>
      <div className="workspace-actions"><Link href="/applications" className="button button--ghost">← Application list</Link>
        <Link href={`/architecture?application=${encodeURIComponent(workspace.applicationId)}`} className="button button--ghost">Architecture ↗</Link>
        <button className="button button--secondary" disabled={loading} onClick={() => setRevision(value => value + 1)}>{loading ? 'Refreshing…' : '↻ Refresh'}</button></div></div>
    <div className="correlation-strip"><span><small>APPLICATION ID</small><strong className="mono">{workspace.applicationId}</strong></span>
      <span><small>WORKFLOW ID</small><strong className="mono">{workspace.workflowId || 'Not assigned yet'}</strong></span>
      <span><small>TRACE ID</small><strong className="mono">{workspace.traceId || 'Not available'}</strong></span>
      <span><small>DATA SOURCE</small><strong>API · live services</strong></span></div>
    <div className="workspace-layout"><aside className="workspace-tabs" aria-label="Application sections"><div className="tabs-label">EXPLORE APPLICATION</div>
      <div role="tablist" aria-orientation="vertical" aria-label="Application workspace">{tabs.map(([key, name, icon], index) =>
        <button key={key} role="tab" id={`tab-${key}`} aria-selected={active === key} aria-controls="workspace-panel"
          tabIndex={active === key ? 0 : -1} className={`workspace-tab ${active === key ? 'workspace-tab--active' : ''}`}
          onClick={() => select(key)} onKeyDown={event => onTabKeyDown(event, index)}>
          <span className="workspace-tab-icon" aria-hidden="true">{icon}</span><span>{name}</span><span className="workspace-tab-arrow">›</span></button>)}</div>
      <div className="tabs-foot"><span className="dot dot--teal" /> Live BFF data</div></aside>
      <section className="workspace-panel" id="workspace-panel" role="tabpanel" aria-labelledby={`tab-${active}`}>
        <div className="panel-heading"><div><div className="eyebrow">{tabTitle.toUpperCase()}</div><h2>{tabTitle}</h2></div>
          <Badge tone={unavailable ? 'neutral' : 'teal'}>{unavailable?.availability || 'Live API'}</Badge></div>
        {active === 'overview' && (workspace.overview.availability === 'AVAILABLE' && workspace.overview.data
          ? <LiveOverview overview={workspace.overview.data} dispatchStatus={workspace.dispatchStatus} />
          : <Empty title="Overview unavailable">{workspace.overview.message || 'Applicant details are not available.'}</Empty>)}
        {active === 'documents' && (inventory ? <Card title="Document inventory" subtitle="Documents registered for this application">
          {inventory.items.length ? <div className="table-wrap"><table><thead><tr><th>Document</th><th>File</th><th>Required</th><th>Status</th><th>Content</th><th>Action</th></tr></thead>
            <tbody>{inventory.items.map(doc => <tr key={doc.documentId}>
              <td><strong>{doc.documentLabel || doc.documentType.replaceAll('_', ' ')}</strong><small className="mono">{doc.documentId}</small></td>
              <td>{doc.fileName}</td><td>{doc.required ? 'Yes' : 'No'}</td><td><Badge tone="blue">{doc.status.replaceAll('_', ' ')}</Badge></td>
              <td>{doc.contentAvailable ? `${doc.contentLengthBytes?.toLocaleString('en-US')} bytes` : 'Not uploaded'}</td>
              <td><Link className="button button--small button--secondary" href={`/applications/${applicationId}?tab=documents&document=${encodeURIComponent(doc.documentId)}`}
                aria-label={`${doc.contentAvailable ? 'Preview' : 'Details for'} ${doc.fileName}`}>{doc.contentAvailable ? 'Preview' : 'Details'}</Link></td></tr>)}</tbody></table></div>
            : <Empty title="No documents">No documents are registered for this application.</Empty>}
          {inventory.truncated && <p className="helper">Only the first 100 document rows are shown.</p>}
          <p className="helper">Open a document to see its metadata and read-only PDF preview. A PDF is available only after its content has been stored.</p>
        </Card> : <Empty title="Documents unavailable">{workspace.documents.message || 'Document inventory is not available.'}</Empty>)}
        {active === 'ai-tasks' && <SectionContent section={workspace.aiWorkflowTasks} title="AI Workflow Tasks" refresh={refresh}>
          {data => <LiveAiTasks items={data.items} refresh={refresh} />}</SectionContent>}
        {active === 'decision' && <SectionContent section={workspace.decision} title="Decision" refresh={refresh}>
          {data => <LiveDecisions data={data} applicationId={applicationId} />}</SectionContent>}
        {active === 'policy-evidence' && <SectionContent section={workspace.policyEvidence} title="Policy Evidence" refresh={refresh}>
          {data => <LivePolicyEvidence data={data} />}</SectionContent>}
        {active === 'risk-signals' && <SectionContent section={workspace.riskSignals} title="Risk Signals" refresh={refresh}>
          {data => <LiveRiskSignals data={data} refresh={refresh} />}</SectionContent>}
        {active === 'workflow' && <SectionContent section={workspace.workflow} title="Workflow" refresh={refresh}>
          {data => <LiveWorkflow data={data} applicationId={applicationId} session={session} refresh={refresh} onSessionExpired={onSessionExpired} />}</SectionContent>}
        {active === 'audit' && <SectionContent section={workspace.audit} title="Audit" refresh={refresh}>
          {data => <LiveAudit data={data} />}</SectionContent>}
        {active === 'trace' && <SectionContent section={workspace.trace} title="Trace" refresh={refresh}>
          {data => <LiveTrace data={data} refresh={refresh} />}</SectionContent>}
        {selectedId && !selected && <Empty title="Document unavailable">The selected document is not present in this application's current inventory.</Empty>}
      </section></div>
    {selected && <LiveDocumentDetails key={`${applicationId}/${selected.documentId}`} applicationId={applicationId} document={selected}
      onClose={() => select('documents')} onSessionExpired={onSessionExpired} />}
  </>;
}

function LiveOverview({ overview, dispatchStatus }: { overview: BffOverview; dispatchStatus: string | null }) {
  const { applicant, loan } = overview;
  const address = applicant.address;
  const date = (value: string | null) => value ? new Date(value).toLocaleString('en-US') : 'Not available';
  return <><Card title="Applicant and request" subtitle="Stored application details · read-only">
    <div className="fact-grid"><Fact label="Applicant name" value={applicant.displayName} /><Fact label="Age band" value={applicant.ageBand} />
      <Fact label="Synthetic phone token" value={applicant.phoneToken} /><Fact label="Synthetic email token" value={applicant.emailToken} />
      <Fact label="Address line" value={address?.addressLine} /><Fact label="City / locality" value={address?.locality} />
      <Fact label="Jurisdiction" value={address?.jurisdictionCode} /><Fact label="Country" value={address?.countryCode} />
      <Fact label="Postal code" value={address?.postalCode} /><Fact label="Address token" value={address?.addressToken} />
      <Fact label="Requested amount" value={loan.requestedAmount == null ? null : `USD ${Number(loan.requestedAmount).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`} />
      <Fact label="Term" value={loan.requestedTermMonths == null ? null : `${loan.requestedTermMonths} months`} />
      <Fact label="Loan purpose" value={loan.purposeCode?.replaceAll('_', ' ')} /><Fact label="Policy version" value={loan.policyVersion} /></div>
  </Card><Card title="Application status" subtitle="Application state and workflow dispatch are distinct from the lending outcome">
    <div className="fact-grid"><Fact label="Application status" value={overview.status.replaceAll('_', ' ')} />
      <Fact label="Workflow dispatch" value={dispatchStatus?.replaceAll('_', ' ')} /><Fact label="Created" value={date(overview.createdAt)} />
      <Fact label="Last updated" value={date(overview.updatedAt)} /></div></Card></>;
}
