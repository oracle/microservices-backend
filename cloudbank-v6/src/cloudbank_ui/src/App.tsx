import { useEffect, useState } from 'react';
import { Link, go, usePath } from './navigation';
import { DemoPage, ApplicationsPage, NewApplicationPage, ReviewPage, ObservabilityPage, SecurityPage } from './pages';
import { WorkspacePage } from './workspace';
import { ArchitecturePage } from './architecture';
import { LiveApp } from './LiveApp';

const nav = [
  ['Demo', '/demo'], ['Applications', '/applications'], ['Manual review', '/manual-review'],
  ['Architecture', '/architecture'], ['Observability', '/observability'], ['Security', '/admin/security'],
];
const copyrightNotice = 'Copyright (c) 2026, Oracle and/or its affiliates.';

function MockApp() {
  const path = usePath();
  const [entered, setEntered] = useState(false);
  const pathname = path.split('?')[0];
  useEffect(() => { if (!entered && pathname !== '/login') go('/login'); }, [entered, pathname]);

  if (!entered || pathname === '/login') {
    return <div className="login-layout"><main className="login-screen"><div className="login-card"><div className="logo-mark logo-mark--large">CB</div><div className="eyebrow">CLOUDBANK AI · OBaaS DEMO</div><h1>The loan journey,<br /><em>ready to explore.</em></h1><p>Enter the local demo with five synthetic scenarios, observable workflows, and architecture.</p><div className="login-divider" /><div className="login-profile"><span className="avatar">OA</span><span><strong>obaas-admin</strong><small>Single UI profile · mock authentication</small></span><span className="dot dot--teal" /></div><button className="button button--primary button--wide" onClick={() => { setEntered(true); go('/demo'); }}>Enter demo <span>→</span></button><p className="login-footnote">Simulated data in memory. No service calls.</p></div><div className="login-aside"><span className="aside-kicker">ORACLE BACKEND FOR MICROSERVICES AND AI</span><div className="orbit orbit--one" /><div className="orbit orbit--two" /><div className="orbit-center">OBaaS</div><div className="orbit-label orbit-label--one">MicroTx</div><div className="orbit-label orbit-label--two">Spring AI</div><div className="orbit-label orbit-label--three">Oracle DB</div><h2>One platform.<br />Every step connected.</h2><p>A demo interface for exploring applications, evidence, decisions, and services.</p></div></main><footer className="footer footer--login"><span>{copyrightNotice}</span></footer></div>;
  }

  const active = pathname.startsWith('/applications') ? '/applications' : pathname;
  return <div className="app-shell"><header className="topbar"><Link href="/demo" className="brand"><span className="logo-mark">CB</span><span><strong>CloudBank <b>AI</b></strong><small>OBaaS DEMO</small></span></Link><nav aria-label="Main navigation">{nav.map(([label, href]) => <Link key={href} href={href} className={`nav-link ${active === href ? 'nav-link--active' : ''}`}>{label}</Link>)}</nav><div className="topbar-right"><span className="mode-pill"><span className="dot dot--teal" /> MOCK</span><span className="topbar-avatar" title="obaas-admin">OA</span></div></header><main className="main-content">
    {pathname === '/demo' || pathname === '/' ? <DemoPage /> :
      pathname === '/applications' ? <ApplicationsPage /> :
      pathname === '/applications/new' ? <NewApplicationPage /> :
      pathname.startsWith('/applications/') ? <WorkspacePage id={decodeURIComponent(pathname.slice('/applications/'.length))} path={path} /> :
      pathname === '/manual-review' ? <ReviewPage /> :
      pathname === '/architecture' ? <ArchitecturePage path={path} /> :
      pathname === '/observability' ? <ObservabilityPage path={path} /> :
      pathname === '/admin/security' ? <SecurityPage /> : <div className="card"><h1>Page not found</h1><Link href="/demo">Back to demo →</Link></div>}
  </main><footer className="footer"><span>{copyrightNotice}</span><span>Synthetic, simulated data · No live services connected</span></footer></div>;
}

export function App() {
  return import.meta.env.VITE_DATA_MODE === 'mock' ? <MockApp /> : <LiveApp />;
}
