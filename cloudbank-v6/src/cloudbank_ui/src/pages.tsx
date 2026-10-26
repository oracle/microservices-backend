import { useState } from 'react';
import { type Draft, type NewDocument, useMockStore } from './model';
import { Link, go } from './navigation';
import { AppLink, Badge, Card, Empty, Fact, FilePicker, PageHeading, StatusBadge } from './ui';
import { createNewApplicationDocuments, createNewApplicationDraft } from './newApplicationDefaults';

const purposeChoices: [string, string][] = [
  ['DEBT_CONSOLIDATION', 'Debt consolidation'], ['HOME_IMPROVEMENT', 'Home improvement'],
  ['MAJOR_PURCHASE', 'Major purchase'], ['MEDICAL_EXPENSE', 'Medical expenses'],
  ['HOUSEHOLD_EXPENSE', 'Household expenses'], ['MOVING_EXPENSE', 'Moving expenses'],
  ['OTHER_CONSUMER_PURPOSE', 'Other consumer purpose'],
];

export const documentTypes = [
  'LOAN_APPLICATION', 'DISCLOSURE_CONSENT', 'IDENTITY_SUMMARY', 'ADDRESS_VERIFICATION',
  'INCOME_VALIDATION', 'PAY_STATEMENT', 'DEPOSIT_SUMMARY', 'ACCOUNT_ACTIVITY',
  'CONTRACTOR_INCOME', 'LIABILITY_SCHEDULE', 'PAYMENT_CALCULATION', 'CLARIFICATION_REQUEST',
  'DOCUMENT_RECEIPT', 'RELATIONSHIP_SIGNAL',
];

export function DemoPage() {
  const { applications, reset } = useMockStore();
  const canonical = applications.filter(app => app.canonical);
  return <><div className="hero"><div className="hero-copy"><div className="eyebrow eyebrow--light">DEMO WORKSPACE · MOCK DATA</div><h1>From application to decision.<br /><em>Every step is visible.</em></h1><p>Explore five synthetic scenarios, workflow evidence, and the OBaaS services behind them.</p><div className="hero-actions"><Link href="/applications/new" className="button button--white">＋ New application</Link><Link href="/architecture" className="button button--outline-light">Explore architecture ↗</Link></div></div><div className="hero-diagram" aria-hidden="true"><div className="diagram-step">01 <span>Intake</span></div><i /><div className="diagram-step">02 <span>Workflow</span></div><i /><div className="diagram-step diagram-step--active">03 <span>Decision</span></div><div className="diagram-caption">OBaaS · MICROTX · ORACLE DATABASE</div></div></div>
    <div className="stats-grid"><div className="stat"><strong>05</strong><span>Canonical scenarios</span></div><div className="stat"><strong>{applications.length}</strong><span>Applications in session</span></div><div className="stat"><strong>{applications.filter(a => a.status === 'MANUAL_REVIEW').length}</strong><span>Open reviews</span></div><div className="stat"><strong>09</strong><span>Views per application</span></div></div>
    <div className="section-title"><div><div className="eyebrow">GUIDED JOURNEYS</div><h2>Demo scenarios</h2><p>Select a scenario to inspect documents, AI tasks, decisions, and correlated traces.</p></div><button className="button button--ghost" onClick={reset}>↺ Reset demo</button></div>
    <div className="scenario-grid">{canonical.map((app, index) => <article className="scenario-card" key={app.id}><div className="scenario-top"><span className="scenario-number">{String(index + 1).padStart(2, '0')}</span><StatusBadge status={app.status} /></div><h3>{app.name}</h3><p>{app.description}</p><div className="scenario-meta"><span className="mono">{app.id}</span><span>USD {Number(app.amount).toLocaleString('en-US')}</span></div><div className="scenario-links"><AppLink id={app.id} name="Open application →" /><Link href={`/architecture?application=${app.id}`}>Architecture ↗</Link><Link href={`/observability?application=${app.id}`}>Traces ↗</Link></div></article>)}</div>
    <div className="callout"><span className="callout-icon">i</span><p><strong>Demo environment.</strong> Statuses, decisions, and traces are simulated. Repository implementation status is separate from live service availability.</p></div></>;
}

export function ApplicationsPage() {
  const { applications } = useMockStore();
  const [filter, setFilter] = useState('ALL');
  const [page, setPage] = useState(1);
  const filtered = filter === 'ALL' ? applications : applications.filter(app => app.status === filter);
  const pages = Math.max(1, Math.ceil(filtered.length / 8));
  const visible = filtered.slice((Math.min(page, pages) - 1) * 8, Math.min(page, pages) * 8);
  return <><PageHeading eyebrow="APPLICATIONS · MOCK DATA" title="Loan applications" description="Five canonical scenarios and applications created during this session." action={<Link className="button button--primary" href="/applications/new">＋ New application</Link>} />
    <Card className="table-card" title="Application list" subtitle={`${filtered.length} results in current session`} action={<label className="filter-label">Status <select value={filter} onChange={e => { setFilter(e.target.value); setPage(1); }}><option value="ALL">All</option><option value="APPROVED">Approved</option><option value="MANUAL_REVIEW">Manual review</option><option value="REJECTED">Rejected</option><option value="RECOVERED">Processing recovered</option><option value="DEFERRED">Awaiting start</option></select></label>}>
      <div className="table-wrap"><table><thead><tr><th>Scenario / application</th><th>Status</th><th>Amount</th><th>Workflow</th><th>Source</th><th></th></tr></thead><tbody>{visible.map(app => <tr key={app.id}><td><strong>{app.name}</strong><small className="mono">{app.id}</small></td><td><StatusBadge status={app.status} /></td><td>USD {Number(app.amount || 0).toLocaleString('en-US')}</td><td className="mono small-text">{app.workflowId}</td><td><Badge>{app.canonical ? 'Fixture' : 'Created now'}</Badge></td><td><AppLink id={app.id} name="Open →" /></td></tr>)}</tbody></table></div>
      {visible.length === 0 && <Empty title="No applications">Change the filter to see other statuses.</Empty>}
      <div className="pagination"><span>Page {Math.min(page, pages)} of {pages}</span><div><button className="button button--small button--ghost" disabled={page <= 1} onClick={() => setPage(page - 1)}>← Previous</button><button className="button button--small button--ghost" disabled={page >= pages} onClick={() => setPage(page + 1)}>Next →</button></div></div>
    </Card></>;
}

export const fields: { key: keyof Draft; label: string; hint: string; choices?: [string, string][] }[] = [
  { key: 'scenarioId', label: 'Scenario identifier', hint: 'SCN-NEW-DEMO' },
  { key: 'name', label: 'Scenario / application name', hint: 'New Application: Synthetic Applicant' },
  { key: 'applicant', label: 'Applicant name', hint: 'Synthetic Applicant' },
  { key: 'ageBand', label: 'Age band', hint: 'Select', choices: ['18-24', '25-34', '35-44', '45-54', '55-64', '65_PLUS'].map(v => [v, v]) },
  { key: 'phoneToken', label: 'Synthetic phone token', hint: 'PHONE-SYNTH-001' },
  { key: 'emailToken', label: 'Synthetic email token', hint: 'EMAIL-SYNTH-001' },
  { key: 'addressLine', label: 'Address line', hint: '10 Demo Avenue' },
  { key: 'locality', label: 'City / locality', hint: 'Demo City' },
  { key: 'jurisdiction', label: 'Jurisdiction', hint: 'US-CA' },
  { key: 'country', label: 'Country code', hint: 'US' },
  { key: 'postalCode', label: 'Postal code', hint: '00000' },
  { key: 'addressToken', label: 'Synthetic address token', hint: 'ADDR-SYNTH-001' },
  { key: 'amount', label: 'Requested amount · USD', hint: '12000.00' },
  { key: 'term', label: 'Term · months', hint: 'Select', choices: ['24', '36', '48', '60'].map(v => [v, v]) },
  { key: 'purpose', label: 'Loan purpose', hint: 'Select', choices: purposeChoices },
  { key: 'policyVersion', label: 'Policy version', hint: '2026.0' },
];

export function NewApplicationPage() {
  const { create } = useMockStore();
  const [draft, setDraft] = useState<Draft>(createNewApplicationDraft);
  const [documents, setDocuments] = useState<NewDocument[]>(() => createNewApplicationDocuments().map(doc => ({ type: doc.documentType, required: doc.required, file: null })));
  const changeDocument = (index: number, patch: Partial<NewDocument>) => setDocuments(previous => previous.map((row, i) => i === index ? { ...row, ...patch } : row));
  return <><PageHeading eyebrow="APPLICATIONS / NEW" title="Create application" description="Enter synthetic metadata. The application starts in deferred mode; upload files and start processing from the workspace." action={<Link href="/applications" className="button button--ghost">← Back to list</Link>} />
    <form noValidate onSubmit={event => { event.preventDefault(); const id = create(draft, documents); go(`/applications/${id}?tab=documents`); }}>
      <Card title="Application details" subtitle="Input matrix · 2 columns × 8 rows"><div className="field-grid">{fields.map(field => <label className="field" key={field.key}><span>{field.label}</span>{field.choices ? <select value={draft[field.key]} onChange={e => setDraft({ ...draft, [field.key]: e.target.value })}><option value="">{field.hint}</option>{field.choices.map(([value, label]) => <option value={value} key={value}>{label}</option>)}</select> : <input value={draft[field.key]} placeholder={field.hint} inputMode={field.key === 'amount' ? 'decimal' : 'text'} onChange={e => setDraft({ ...draft, [field.key]: e.target.value })} />}</label>)}</div></Card>
      <Card title="Documents" subtitle="One row per document · individual upload after creation" action={<button type="button" className="button button--ghost" onClick={() => setDocuments([...documents, { type: '', required: true, file: null }])}>＋ Add row</button>}><div className="table-wrap"><table className="documents-table"><thead><tr><th>Document type</th><th>Required</th><th>File</th><th>Upload status</th><th></th></tr></thead><tbody>{documents.map((row, index) => <tr key={index}><td><select aria-label={`Document type ${index + 1}`} value={row.type} onChange={e => changeDocument(index, { type: e.target.value })}><option value="">Select type</option>{documentTypes.map(type => <option value={type} key={type}>{type.replaceAll('_', ' ')}</option>)}</select></td><td><label className="checkbox-label"><input type="checkbox" checked={row.required} onChange={e => changeDocument(index, { required: e.target.checked })} /><span>Yes</span></label></td><td><FilePicker label={`Document file ${index + 1}`} fileName={row.file?.name} onChange={file => changeDocument(index, { file })} /></td><td><Badge>Not uploaded</Badge></td><td><button type="button" className="icon-button" aria-label={`Remove row ${index + 1}`} onClick={() => setDocuments(documents.filter((_, i) => i !== index))}>×</button></td></tr>)}</tbody></table></div><p className="helper">The backend accepts PDFs up to 25 MiB. The mock does not validate files: upload is simulated and bytes are not retained.</p></Card>
      <div className="form-footer"><span><strong>Deferred start</strong><small>Processing starts only when you select the workspace action.</small></span><button className="button button--primary" type="submit">Create application →</button></div>
    </form></>;
}

export function ReviewPage() {
  const { applications, review } = useMockStore();
  const queue = applications.filter(app => app.status === 'MANUAL_REVIEW');
  const [selected, setSelected] = useState<string>('');
  const [outcome, setOutcome] = useState('APPROVED');
  const [reason, setReason] = useState('');
  const [section, setSection] = useState('');
  const [completed, setCompleted] = useState('');
  const app = queue.find(item => item.id === selected);
  return <><PageHeading eyebrow="HUMAN TASKS · MOCK" title="Manual review" description="Simulated HUMAN tasks. Complete a review as obaas-admin; the mock journey applies the final outcome." action={<Badge tone="amber">{queue.length} open</Badge>} />
    <div className="review-layout"><Card title="Review queue" subtitle="No assignment or role hierarchy"><div className="review-list">{queue.map(item => <button key={item.id} className={`review-item ${selected === item.id ? 'review-item--active' : ''}`} onClick={() => { setSelected(item.id); setCompleted(''); }}><span><Badge tone={item.reviewPriority === 'High' ? 'rose' : 'blue'}>{item.reviewPriority}</Badge><small className="mono">{item.id}</small></span><strong>{item.name}</strong><small>{item.reviewReason}</small><span className="review-item-foot">Open task <b>→</b></span></button>)}</div>{queue.length === 0 && <Empty title="No open tasks">Completed reviews remain available in the workspace.</Empty>}</Card>
    <Card title={app ? 'Complete review' : 'Task details'} subtitle={app ? `${app.name} · ${app.id}` : 'Select an application from the queue'}>{app ? <><div className="detail-banner"><span className="detail-banner-icon">◎</span><div><strong>{app.reviewReason}</strong><p>Simulated HUMAN task · reviewer obaas-admin</p></div></div><form noValidate onSubmit={event => { event.preventDefault(); review(app.id, outcome, reason, section); setCompleted(app.name); setSelected(''); }}><div className="field-grid"><label className="field"><span>Requested outcome</span><select value={outcome} onChange={e => setOutcome(e.target.value)}><option value="APPROVED">APPROVED · Approve</option><option value="REJECTED">REJECTED · Reject</option></select></label><label className="field"><span>Reason code</span><input value={reason} placeholder="DOCUMENT_EXCEPTION_RESOLVED" onChange={e => setReason(e.target.value)} /></label><label className="field"><span>Policy section</span><input value={section} placeholder="CBPL-150-S4" onChange={e => setSection(e.target.value)} /></label><label className="field"><span>Reviewer</span><input value="obaas-admin" readOnly /></label></div><div className="form-actions"><Link href={`/applications/${app.id}?tab=documents`} className="button button--ghost">View evidence ↗</Link><button type="submit" className="button button--primary">Complete review →</button></div></form></> : completed ? <div className="success-state"><strong>Review completed (mock)</strong><p>{completed}. Check the decision and audit in the workspace.</p></div> : <Empty title="Choose an application">Synthetic evidence remains available before completion.</Empty>}</Card></div></>;
}

export function ObservabilityPage({ path }: { path: string }) {
  const { applications } = useMockStore();
  const params = new URLSearchParams(path.split('?')[1] ?? '');
  const id = params.get('application') || applications[0]?.id;
  const app = applications.find(item => item.id === id) ?? applications[0];
  if (!app) return null;
  const spans = ['Gateway / application request', 'Loan application / status', 'MicroTx / workflow', 'Document review / evidence', 'Decision service / outcome'];
  return <><PageHeading eyebrow="OBSERVABILITY · SIMULATION" title="End-to-end correlation" description="A safe view of synthetic traces with sensitive attributes omitted." action={<select aria-label="Select application" className="heading-select" value={app.id} onChange={e => go(`/observability?application=${e.target.value}`)}>{applications.map(item => <option key={item.id} value={item.id}>{item.name} · {item.id}</option>)}</select>} />
    <div className="metric-row"><div className="metric"><span>APPLICATION ID</span><strong className="mono">{app.id}</strong></div><div className="metric"><span>WORKFLOW ID</span><strong className="mono">{app.workflowId}</strong></div><div className="metric"><span>TRACE ID</span><strong className="mono">{app.traceId}</strong></div></div>
    <div className="two-up"><Card title="Span timeline" subtitle="Mock projection, not live telemetry"><div className="timeline">{spans.map((span, i) => <div className="timeline-row" key={span}><span className="timeline-node">{i + 1}</span><div><strong>{span}</strong><small>Simulated · {app.id} · {i === 4 && app.status === 'DEFERRED' ? 'not executed' : 'completed'}</small></div><span className="timeline-time">+{i * 180}ms</span></div>)}</div></Card><Card title="SigNoz search" subtitle="Guidance for future integration"><div className="search-guide"><div className="guide-icon">⌕</div><h3>Follow one application across services</h3><p>In an OBaaS deployment, confirm SigNoz is available, then search by application ID, workflow ID, or trace ID.</p><div className="code-line">application.id = {app.id}</div><div className="code-line">trace.id = {app.traceId}</div><p className="helper">This page does not query SigNoz or OpenTelemetry.</p></div></Card></div>
    <div className="page-actions"><Link href={`/applications/${app.id}?tab=trace`} className="button button--secondary">Open Trace in workspace →</Link><Link href={`/architecture?application=${app.id}`} className="button button--ghost">View participating components ↗</Link></div></>;
}

export function SecurityPage() {
  const { applications } = useMockStore();
  const [id, setId] = useState(applications[0]?.id ?? '');
  const app = applications.find(item => item.id === id) ?? applications[0];
  return <><PageHeading eyebrow="ADMINISTRATION / SECURITY" title="Session and protected data" description="The UI has one profile; backend technical permissions remain separate and must be verified by the BFF." action={<Badge tone="teal">obaas-admin profile</Badge>} />
    <div className="security-grid"><Card title="Local session" subtitle="Mock authentication"><div className="profile-row"><span className="avatar avatar--large">OA</span><div><strong>obaas-admin</strong><p>Flat UI profile · all demo views</p></div></div><div className="fact-list"><Fact label="Data mode" value="In-memory mock" /><Fact label="Browser session" value="Local, without tokens" /><Fact label="Backend roles" value="To verify in API mode" /></div></Card><Card title="Security boundary" subtitle="Contract planned for integration"><div className="boundary"><span>Browser SPA</span><b>→</b><span>Session-backed BFF</span><b>→</b><span>OBaaS services</span></div><p>The browser does not receive access tokens, client secrets, service credentials, or persisted PDFs. In API mode, the BFF verifies the principal and UNDERWRITER grant before HUMAN review.</p><Badge tone="blue">BFF planned</Badge></Card></div>
    <div className="two-up"><Card title="Safe projection" subtitle="Examples of data shown by this UI"><div className="safe-list"><span>✓ Application, workflow, and trace IDs</span><span>✓ Statuses, reason codes, and bounded citations</span><span>✓ Document metadata and redacted signals</span></div><div className="unsafe-list"><span>— No tokens or secrets</span><span>— No raw PDF text or prompts</span><span>— No credentials in browser storage</span></div></Card><Card title="Selected audit" subtitle="Synthetic application events"><select className="full-select" value={app.id} onChange={e => setId(e.target.value)}>{applications.map(item => <option value={item.id} key={item.id}>{item.name} · {item.id}</option>)}</select><div className="audit-mini">{app.audit.slice(-4).reverse().map((event, i) => <div key={`${event.action}-${i}`}><span className="mono">{event.at}</span><strong>{event.action}</strong><small>{event.detail}</small></div>)}</div></Card></div></>;
}
