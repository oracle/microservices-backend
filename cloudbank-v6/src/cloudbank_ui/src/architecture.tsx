// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at
// https://oss.oracle.com/licenses/upl/.

import { useState } from 'react';
import {
  architectureAiTasks, architectureComponents as components, architectureFeatures,
  architectureJourney, architectureLanes, type ArchitectureStatus,
} from './architectureModel';
import { Link, go } from './navigation';
import { Badge, Card, PageHeading } from './ui';
import './Architecture.css';

interface ArchitectureApplication {
  id: string;
  name: string;
  status: string;
}

function scenarioHighlights(application: ArchitectureApplication | undefined): string[] {
  const common = ['obaas', 'ui', 'bff', 'auth', 'loan', 'ingest', 'review', 'ai', 'policy',
    'geo', 'decision', 'workflow', 'database', 'audit', 'observability'];
  return application?.status === 'MANUAL_REVIEW' ? [...common, 'manual-review', 'refresh'] : common;
}

function statusTone(status: ArchitectureStatus) {
  return status === 'Implemented' ? 'teal' : status === 'Planned' ? 'neutral' : status === 'Database object' ? 'blue' : 'amber';
}

export function ArchitecturePage({ path, mode, applications = [] }: {
  path: string; mode: 'api' | 'mock'; applications?: ArchitectureApplication[];
}) {
  const params = new URLSearchParams(path.split('?')[1] ?? '');
  const requestedApplication = params.get('application');
  const selectedApp = mode === 'mock'
    ? applications.find(app => app.id === requestedApplication) ?? applications[0] : undefined;
  const linkedApplicationId = mode === 'mock' ? selectedApp?.id
    : requestedApplication && /^APP-[A-Za-z0-9][A-Za-z0-9-]{0,35}$/.test(requestedApplication)
      ? requestedApplication : undefined;
  const [selectedId, setSelectedId] = useState('obaas');
  const component = components.find(item => item.id === selectedId) ?? components[0];
  const highlighted = new Set(mode === 'mock' ? scenarioHighlights(selectedApp)
    : components.filter(item => item.status !== 'Planned').map(item => item.id));
  const applicationHref = linkedApplicationId ? `/applications/${encodeURIComponent(linkedApplicationId)}` : null;

  return <div className="architecture-explorer">
    <PageHeading eyebrow="ARCHITECTURE EXPLORER · STATIC REFERENCE" title="One platform, many services."
      description="Explore the implemented CloudBank services, their responsibilities and the OBaaS capabilities that connect them."
      action={<><Badge tone="blue">Static architecture</Badge>{mode === 'mock' && applications.length > 0 &&
        <select className="heading-select" aria-label="Select mock scenario" value={selectedApp?.id}
          onChange={event => go(`/architecture?application=${encodeURIComponent(event.target.value)}`)}>
          {applications.map(app => <option key={app.id} value={app.id}>{app.name} · {app.id}</option>)}
        </select>}</>} />
    <div className="architecture-hero"><div className="architecture-hero-icon" aria-hidden="true">OB</div>
      <div><span className="eyebrow eyebrow--light">TOP-LEVEL PLATFORM</span><h2>Oracle Backend for Microservices and AI</h2>
        <p>Gateway, discovery, configuration, deployment, MicroTx Workflows, Oracle Database and observability support the CloudBank journey.</p>
      </div><Badge tone="amber">External platform</Badge></div>
    <p className="architecture-reference-note">This map describes repository implementation. Application results and read availability are shown in the application workspace.
      {mode === 'mock' && ' Scenario highlighting below is a mock illustration.'}</p>
    <div className="architecture-legend" aria-label="Component implementation status">
      {(['Implemented', 'External platform', 'Database object', 'Planned'] as const).map(status =>
        <Badge key={status} tone={statusTone(status)}>{status}</Badge>)}
    </div>
    <Card title="Loan journey" subtitle="Implemented workflow version 1 · human review runs when required">
      <div className="flow-steps architecture-journey">{architectureJourney.map((step, index) =>
        <div key={step.title}><span className="flow-dot">{index + 1}</span><strong>{step.title}</strong><small>{step.detail}</small></div>)}
      </div>
    </Card>
    <div className="architecture-layout">
      <section className="architecture-map" aria-labelledby="architecture-map-title">
        <div className="architecture-map-heading"><div><h2 id="architecture-map-title">System map</h2>
          <p>{selectedApp ? <>Mock scenario: <strong>{selectedApp.name}</strong></> : 'Select a component to inspect its implementation and integration.'}</p>
        </div>{selectedApp ? <span className="mono">{selectedApp.id}</span> : <Badge>Repository reference</Badge>}</div>
        {architectureLanes.map(lane => <div className="architecture-lane" key={lane}>
          <div className="lane-name">{lane}</div><div className="lane-components">
            {components.filter(item => item.lane === lane).map(item => <button type="button" key={item.id}
              aria-pressed={selectedId === item.id} aria-controls="architecture-inspector"
              className={`component-node ${selectedId === item.id ? 'component-node--selected' : ''} ${highlighted.has(item.id) ? 'component-node--involved' : ''}`}
              onClick={() => setSelectedId(item.id)}>
              <span className="node-dot" aria-hidden="true" /><span><strong>{item.name}</strong><small>{item.style}</small>
                <span className="architecture-node-status"><Badge tone={statusTone(item.status)}>{item.status}</Badge></span>
              </span><span className="node-chevron" aria-hidden="true">›</span>
            </button>)}
          </div></div>)}
      </section>
      <aside className="inspector" id="architecture-inspector" aria-label="Selected architecture component">
        <div className="inspector-top"><span className="eyebrow">TECHNOLOGY INSPECTOR</span><Badge tone={statusTone(component.status)}>{component.status}</Badge></div>
        <h2 aria-live="polite">{component.name}</h2><p>{component.description}</p>
        <div className="inspector-facts">
          <div><span>STYLE</span><strong>{component.style}</strong></div>
          <div><span>REPOSITORY EVIDENCE</span><strong className="mono">{component.evidence}</strong></div>
          <div><span>INTEGRATION</span><strong>{component.integration}</strong></div>
          {mode === 'mock' && <div><span>MOCK SCENARIO</span><strong>{highlighted.has(component.id) ? 'Highlighted in the illustration' : 'Not highlighted'}</strong></div>}
          <div><span>SECURITY</span><strong>{component.security}</strong></div>
          <div><span>DEPLOYMENT DEPENDENCIES</span><strong>{component.runtime}</strong></div>
          <div><span>DATA SOURCE</span><strong>Static repository catalog · deployment health is not queried here</strong></div>
        </div>
      </aside>
    </div>
    <div className="two-up architecture-feature-cards">
      <Card title="Oracle Feature Map" subtitle="Storage and capabilities used by the implementation">
        <div className="feature-map">{architectureFeatures.map(feature => <div key={feature.name}>
          <span className="feature-symbol" aria-hidden="true">◇</span><strong>{feature.name}</strong><small>{feature.description}</small>
          <span className="architecture-feature-status"><Badge tone={statusTone(feature.status)}>{feature.status}</Badge></span>
        </div>)}</div>
      </Card>
      <Card title="AI Workflow Task Map" subtitle="Three supported tasks in ai-agent-service">
        <div className="ai-map">{architectureAiTasks.map(task => <div className="architecture-ai-task" key={task.name}>
          <div><strong>{task.name}</strong><small>{task.mode}</small><p>{task.description}</p></div>
          <Badge tone={task.deterministic ? 'blue' : 'teal'}>Implemented</Badge>
        </div>)}</div>
        <p className="helper">AI supplies evidence and reviewer assistance. The deterministic decision service and authorized human review govern lending outcomes.</p>
      </Card>
    </div>
    <div className="architecture-footer"><div><strong>Continue the journey</strong>
      <p>{linkedApplicationId ? <>Application ID: <span className="mono">{linkedApplicationId}</span></> : 'Open an application to inspect its recorded evidence, audit and trace.'}</p>
    </div><div>
      <Link href={applicationHref ? `${applicationHref}?tab=overview` : '/applications'} className="button button--secondary">
        {applicationHref ? 'Open application →' : 'Application list →'}</Link>
      {applicationHref && linkedApplicationId && <Link href={mode === 'mock'
        ? `/observability?application=${encodeURIComponent(linkedApplicationId)}` : `${applicationHref}?tab=trace`}
        className="button button--ghost">{mode === 'mock' ? 'Observability ↗' : 'Application Trace ↗'}</Link>}
    </div></div>
  </div>;
}
