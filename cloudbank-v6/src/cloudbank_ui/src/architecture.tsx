import { useState } from 'react';
import { useMockStore } from './model';
import { Link, go } from './navigation';
import { Badge, Card, PageHeading } from './ui';

type ComponentStatus = 'Implemented' | 'Planned' | 'External platform' | 'Database object' | 'Mocked in UI';
interface Component {
  id: string;
  name: string;
  lane: string;
  status: ComponentStatus;
  style: string;
  description: string;
  evidence: string;
  integration: string;
}

const components: Component[] = [
  { id: 'obaas', name: 'Oracle Backend for Microservices and AI', lane: 'Platform', status: 'External platform', style: 'OBaaS platform', description: 'Deployment, gateway, discovery, configuration, operations, and database integration.', evidence: 'deploy/obaas/', integration: 'Verify readiness and routing in the target deployment.' },
  { id: 'ui', name: 'CloudBank UI', lane: 'Experience', status: 'Implemented', style: 'React / Vite SPA', description: 'Browser demo with synthetic scenarios and correlated views.', evidence: 'src/cloudbank_ui/', integration: 'Connect the browser-safe BFF when available.' },
  { id: 'bff', name: 'Gateway BFF', lane: 'Boundary', status: 'Planned', style: 'Spring Boot service', description: 'Browser session, composed read projections, and authorized operations.', evidence: 'docs/ui/minimum-bff-api.md', integration: 'Implement the minimum contract, session, and safe projections.' },
  { id: 'auth', name: 'azn-server', lane: 'CloudBank services', status: 'Implemented', style: 'Spring Boot service', description: 'Users, technical roles, OAuth2/OIDC, and token signing.', evidence: 'src/azn-server/', integration: 'The UI will access services only through the BFF session.' },
  { id: 'loan', name: 'Loan application', lane: 'CloudBank services', status: 'Implemented', style: 'Spring Boot service', description: 'Intake, application state, immutable PDFs, and the workflow-start outbox.', evidence: 'src/loan-application-service/', integration: 'BFF for creation, inventory, upload, and deferred release.' },
  { id: 'ingest', name: 'Document ingest', lane: 'CloudBank services', status: 'Implemented', style: 'Spring Boot service', description: 'Authorized PDF extraction and structured persistence.', evidence: 'src/document-ingest/', integration: 'Internal workflow invocation.' },
  { id: 'review', name: 'Document review', lane: 'CloudBank services', status: 'Implemented', style: 'Spring Boot service', description: 'Deterministic checks on bounded evidence and inventory.', evidence: 'src/document-review-service/', integration: 'Expose through safe BFF projections.' },
  { id: 'ai', name: 'AI agent', lane: 'CloudBank services', status: 'Implemented', style: 'Spring AI service', description: 'Governed document summaries and manual-review assistance; deterministic policy support.', evidence: 'src/ai-agent-service/', integration: 'Validated, redacted output through the workflow and BFF.' },
  { id: 'policy', name: 'Policy retrieval', lane: 'CloudBank services', status: 'Implemented', style: 'Spring Boot service', description: 'Authorized vector retrieval of bounded policy evidence.', evidence: 'src/policy-retrieval-service/', integration: 'Requires OCI embedding configuration to run.' },
  { id: 'geo', name: 'Geographic risk', lane: 'CloudBank services', status: 'Implemented', style: 'Helidon service', description: 'Deterministic Oracle Spatial signal and disposition, not a lending decision.', evidence: 'src/geographic-risk-service/', integration: 'Verify Spatial availability in the target environment.' },
  { id: 'decision', name: 'Decision service', lane: 'CloudBank services', status: 'Implemented', style: 'Spring Boot service', description: 'Deterministic initial and final decisions with durable evidence.', evidence: 'src/decision-service/', integration: 'Safe browser reads through the BFF.' },
  { id: 'workflow', name: 'MicroTx Workflows', lane: 'Orchestration', status: 'External platform', style: 'OBaaS capability', description: 'Coordinates tasks, retries, HUMAN review, audit, and loan-journey resume.', evidence: 'src/workflows/cloudbank-loan-origination/', integration: 'Version 1 is defined; end-to-end validation in the target environment remains necessary.' },
  { id: 'refresh', name: 'Token refresh worker', lane: 'Orchestration', status: 'Implemented', style: 'Spring Boot service', description: 'Refreshes service authorization after long-running HUMAN tasks.', evidence: 'src/workflow-token-refresh-worker/', integration: 'Verify resume and masking in the target environment.' },
  { id: 'database', name: 'Oracle Database', lane: 'Data', status: 'Database object', style: 'Oracle Database object', description: 'Relational, JSON, Vector, Spatial, Text, and Graph assets for the loan journey.', evidence: 'src/schema/', integration: 'Available features depend on the schema profile.' },
  { id: 'risk', name: 'Relationship / identity risk', lane: 'Future capabilities', status: 'Planned', style: 'Spring Boot / Helidon service', description: 'Broader relationship and identity analysis beyond geographic risk.', evidence: 'docs/architecture/', integration: 'Define the service, contract, and security controls.' },
  { id: 'observability', name: 'OpenTelemetry / SigNoz', lane: 'Operations', status: 'External platform', style: 'External platform', description: 'Correlated traces and search where deployed.', evidence: 'deploy/obaas/', integration: 'Confirm collector, exporter, and queries in the target environment.' },
  { id: 'audit', name: 'Audit read API', lane: 'Future capabilities', status: 'Planned', style: 'Spring Boot / ORDS', description: 'Safe browser projection of complete audit events.', evidence: 'docs/ui/minimum-bff-api.md', integration: 'Implement BFF composition and redaction.' },
];

const lanes = ['Platform', 'Experience', 'Boundary', 'CloudBank services', 'Orchestration', 'Data', 'Operations', 'Future capabilities'];
const features = [
  ['Relational', 'Applications, decisions, workflow, and audit'], ['JSON', 'Extraction payloads and synthetic packets'],
  ['Vector', 'Policy evidence search'], ['Spatial', 'Geographic risk signals'],
  ['Graph', 'Assets for planned relationship risk'], ['ORDS', 'Future inspection surfaces'],
];

function involved(id: string) {
  const common = ['obaas', 'ui', 'auth', 'loan', 'ingest', 'review', 'ai', 'policy', 'decision', 'workflow', 'database', 'observability'];
  if (id === 'APP-RISK-005') return [...common, 'geo', 'risk'];
  if (id === 'APP-MR-002') return [...common, 'refresh', 'audit'];
  if (id === 'APP-OPFAIL-004') return [...common, 'refresh'];
  return common;
}

function statusTone(status: ComponentStatus) {
  return status === 'Implemented' ? 'teal' : status === 'Planned' ? 'neutral' : status === 'Database object' ? 'blue' : 'amber';
}

export function ArchitecturePage({ path }: { path: string }) {
  const { applications } = useMockStore();
  const params = new URLSearchParams(path.split('?')[1] ?? '');
  const selectedApp = applications.find(app => app.id === params.get('application')) ?? applications[0];
  const [selectedId, setSelectedId] = useState('obaas');
  const component = components.find(item => item.id === selectedId) ?? components[0];
  const highlighted = new Set(involved(selectedApp?.id ?? ''));
  return <><PageHeading eyebrow="ARCHITECTURE EXPLORER" title="One platform, many services." description="OBaaS is the starting point. Select a component to see its responsibilities, repository status, and planned integrations." action={<select className="heading-select" aria-label="Select scenario" value={selectedApp?.id} onChange={e => go(`/architecture?application=${e.target.value}`)}>{applications.map(app => <option key={app.id} value={app.id}>{app.name} · {app.id}</option>)}</select>} />
    <div className="architecture-hero"><div className="architecture-hero-icon">OB</div><div><span className="eyebrow eyebrow--light">TOP-LEVEL PLATFORM</span><h2>Oracle Backend for Microservices and AI</h2><p>Gateway, discovery, configuration, deployment, workflow, database, and observability support the CloudBank journey.</p></div><Badge tone="amber">External platform</Badge></div>
    <div className="architecture-layout"><div className="architecture-map"><div className="architecture-map-heading"><div><h2>System map</h2><p>Components highlighted for: <strong>{selectedApp?.name}</strong></p></div><span className="mono">{selectedApp?.id}</span></div>{lanes.map(lane => <div className="architecture-lane" key={lane}><div className="lane-name">{lane}</div><div className="lane-components">{components.filter(item => item.lane === lane).map(item => <button key={item.id} className={`component-node ${selectedId === item.id ? 'component-node--selected' : ''} ${highlighted.has(item.id) ? 'component-node--involved' : ''}`} onClick={() => setSelectedId(item.id)}><span className="node-dot" /><span><strong>{item.name}</strong><small>{item.style}</small></span><span className="node-chevron">›</span></button>)}</div></div>)}</div><aside className="inspector"><div className="inspector-top"><span className="eyebrow">TECHNOLOGY INSPECTOR</span><Badge tone={statusTone(component.status)}>{component.status}</Badge></div><h2>{component.name}</h2><p>{component.description}</p><div className="inspector-facts"><div><span>STYLE</span><strong>{component.style}</strong></div><div><span>REPOSITORY EVIDENCE</span><strong className="mono">{component.evidence}</strong></div><div><span>INTEGRATION</span><strong>{component.integration}</strong></div><div><span>SELECTED SCENARIO</span><strong>{highlighted.has(component.id) ? 'Participating component' : 'Not highlighted'}</strong></div><div><span>SECURITY</span><strong>Limited access and redacted projections</strong></div><div><span>OBSERVABILITY</span><strong>Correlation by application / workflow / trace ID</strong></div><div><span>RUNTIME VERIFICATION</span><strong>Not verified by this mock UI</strong></div></div></aside></div>
    <div className="two-up"><Card title="Oracle Feature Map" subtitle="Capabilities linked to the loan journey"><div className="feature-map">{features.map(([name, description]) => <div key={name}><span className="feature-symbol">◇</span><strong>{name}</strong><small>{description}</small></div>)}</div></Card><Card title="AI Workflow Task Map" subtitle="Distinct implementation modes"><div className="ai-map"><div><strong>Document Evidence Summary</strong><Badge tone="teal">Spring AI · Implemented</Badge></div><div><strong>Policy Evidence Support</strong><Badge tone="blue">Deterministic · Implemented</Badge></div><div><strong>Manual Review Assistant</strong><Badge tone="teal">Spring AI · Implemented</Badge></div><div><strong>Decision Explanation Draft</strong><Badge>Planned</Badge></div></div><p className="helper">AI outputs in this UI are simulated; AI does not decide the loan outcome.</p></Card></div>
    <div className="architecture-footer"><div><strong>Continue the journey</strong><p>Open the application or follow its observability correlation.</p></div><div><Link href={`/applications/${selectedApp.id}?tab=overview`} className="button button--secondary">Open application →</Link><Link href={`/observability?application=${selectedApp.id}`} className="button button--ghost">Observability ↗</Link></div></div></>;
}
