// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at
// https://oss.oracle.com/licenses/upl/.

import { useCallback, useEffect, useState } from 'react';
import { BffError, getApplications, getSession, logout, type BffApplication, type BffApplicationPage, type BffCreatedApplication, type BffSession } from './bff';
import { LiveNewApplication } from './LiveNewApplication';
import { LiveManualReview } from './LiveManualReview';
import { go, Link, usePath } from './navigation';
import { Badge, Card, Empty, Fact, PageHeading } from './ui';

const copyrightNotice = 'Copyright (c) 2026, Oracle and/or its affiliates.';
const statuses = [
  'SUBMITTED', 'DOCUMENTS_RECEIVED', 'PROCESSING', 'MANUAL_REVIEW', 'APPROVED',
  'REJECTED', 'FAILED_RETRYABLE', 'RECOVERED', 'WITHDRAWN', 'EXPIRED',
];

type AuthState =
  | { kind: 'loading' }
  | { kind: 'signedOut' }
  | { kind: 'authenticated'; session: BffSession }
  | { kind: 'unavailable'; message: string }
  | { kind: 'forbidden'; message: string };

function errorMessage(error: unknown): string {
  return error instanceof BffError ? error.message : 'The BFF request could not be completed.';
}

function label(status: string): string {
  return status.toLowerCase().replaceAll('_', ' ').replace(/^./, letter => letter.toUpperCase());
}

function statusBadge(status: string) {
  const tone: 'teal' | 'rose' | 'amber' | 'blue' = status === 'APPROVED' ? 'teal' : status === 'REJECTED' ? 'rose' :
    status === 'MANUAL_REVIEW' || status === 'FAILED_RETRYABLE' ? 'amber' : 'blue';
  return <Badge tone={tone}>{label(status)}</Badge>;
}

function amount(value: number | null): string {
  return value == null ? '—' : `USD ${Number(value).toLocaleString('en-US', { maximumFractionDigits: 2 })}`;
}

function dateTime(value: string | null): string {
  if (!value) return '—';
  const timestamp = new Date(value);
  return Number.isNaN(timestamp.getTime()) ? '—' : timestamp.toLocaleString('en-US', { dateStyle: 'medium', timeStyle: 'short' });
}

function LoginScreen({ state, retry }: { state: AuthState; retry: () => void }) {
  const unavailable = state.kind === 'unavailable' || state.kind === 'forbidden';
  return <div className="login-layout"><main className="login-screen"><div className="login-card">
    <div className="logo-mark logo-mark--large">CB</div><div className="eyebrow">CLOUDBANK AI · OBaaS</div>
    <h1>Your applications,<br /><em>connected.</em></h1>
    <p>Sign in through CloudBank to view the applications available to obaas-admin.</p>
    <div className="login-divider" />
    <div className="login-profile"><span className="avatar">OA</span><span><strong>obaas-admin</strong><small>CloudBank account · BFF session</small></span><span className="dot dot--teal" /></div>
    {state.kind === 'loading' ? <p role="status">Checking the BFF connection…</p> :
      unavailable ? <><div className="live-error" role="alert">{state.message}</div>
        <button className="button button--primary button--wide" onClick={retry}>Retry connection <span>↻</span></button></> :
        <button className="button button--primary button--wide" onClick={() => window.location.assign('/bff/auth/login')}>
          Sign in with CloudBank <span>→</span>
        </button>}
    <p className="login-footnote">The browser uses a BFF session cookie. Credentials and access tokens stay outside the GUI.</p>
  </div><div className="login-aside"><span className="aside-kicker">ORACLE BACKEND FOR MICROSERVICES AND AI</span><div className="orbit orbit--one" /><div className="orbit orbit--two" /><div className="orbit-center">OBaaS</div><div className="orbit-label orbit-label--one">MicroTx</div><div className="orbit-label orbit-label--two">Spring AI</div><div className="orbit-label orbit-label--three">Oracle DB</div><h2>One platform.<br />Every step connected.</h2><p>Applications come from the running loan service through the CloudBank BFF.</p></div></main><footer className="footer footer--login"><span>{copyrightNotice}</span></footer></div>;
}

function LiveApplications({ onSessionExpired }: { onSessionExpired: () => void }) {
  const [status, setStatus] = useState('');
  const [page, setPage] = useState(0);
  const [refresh, setRefresh] = useState(0);
  const [result, setResult] = useState<BffApplicationPage | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    const controller = new AbortController();
    const load = async () => {
      setLoading(true);
      setError('');
      try {
        const data = await getApplications(page, status, controller.signal);
        if (!controller.signal.aborted) setResult(data);
      } catch (reason) {
        if (controller.signal.aborted) return;
        if (reason instanceof BffError && reason.status === 401) {
          try {
            await getSession(controller.signal);
            if (!controller.signal.aborted) {
              setResult(null);
              setError('The loan service rejected this request while your BFF session is active. Check service authorization.');
            }
          } catch (sessionError) {
            if (controller.signal.aborted) return;
            if (sessionError instanceof BffError && sessionError.status === 401) {
              onSessionExpired();
            } else {
              setResult(null);
              setError(errorMessage(sessionError));
            }
          }
          return;
        }
        setResult(null);
        setError(errorMessage(reason));
      } finally {
        if (!controller.signal.aborted) setLoading(false);
      }
    };
    void load();
    return () => controller.abort();
  }, [page, status, refresh, onSessionExpired]);

  const metadata = result?.page;
  const totalPages = Math.max(1, metadata?.totalPages ?? 1);
  const rows: BffApplication[] = result?.content ?? [];
  return <><PageHeading eyebrow="APPLICATIONS · LIVE BFF" title="Loan applications"
    description="Applications authorized for your CloudBank account, read through the BFF and loan service."
    action={<><Link href="/applications/new" className="button button--primary">＋ New application</Link><button className="button button--secondary" onClick={() => setRefresh(value => value + 1)} disabled={loading}>↻ Refresh</button></>} />
    <Card className="table-card" title="Application list"
      subtitle={loading ? 'Loading from the BFF…' : metadata ? `${metadata.totalElements} authorized applications` : 'BFF data unavailable'}
      action={<label className="filter-label">Status <select value={status} onChange={event => { setStatus(event.target.value); setPage(0); }}>
        <option value="">All statuses</option>{statuses.map(value => <option value={value} key={value}>{label(value)}</option>)}
      </select></label>}>
      {error && <div className="live-error" role="alert">{error}</div>}
      {loading ? <p className="live-loading" role="status">Loading applications…</p> : !error && <>
        <div className="table-wrap"><table><thead><tr><th>Application</th><th>Status</th><th>Amount</th><th>Term</th><th>Workflow</th><th>Updated</th></tr></thead><tbody>{rows.map(item =>
          <tr key={item.applicationId}><td><strong>{item.scenarioName || 'Loan application'}</strong><small className="mono">{item.applicationId}{item.scenarioId ? ` · ${item.scenarioId}` : ''}</small></td><td>{statusBadge(item.status)}</td><td>{amount(item.requestedAmount)}</td><td>{item.requestedTermMonths == null ? '—' : `${item.requestedTermMonths} months`}</td><td className="mono small-text">{item.workflowId || 'Not assigned yet'}</td><td>{dateTime(item.updatedAt ?? item.createdAt)}</td></tr>
        )}</tbody></table></div>
        {rows.length === 0 && <Empty title="No applications">No applications are available for this account and status.</Empty>}
        <div className="pagination"><span>Page {Math.min(page + 1, totalPages)} of {totalPages}</span><div>
          <button className="button button--small button--ghost" disabled={page <= 0} onClick={() => setPage(value => value - 1)}>← Previous</button>
          <button className="button button--small button--ghost" disabled={page + 1 >= totalPages} onClick={() => setPage(value => value + 1)}>Next →</button>
        </div></div>
      </>}
    </Card>
    <div className="callout"><span className="callout-icon">i</span><p>Select New application to create a record, upload its PDFs, and start processing. Open Manual review for pending human tasks. Workspace details remain planned.</p></div>
  </>;
}

function LiveSecurity({ session }: { session: BffSession }) {
  return <><PageHeading eyebrow="SECURITY · LIVE BFF" title="Your CloudBank session"
    description="Authentication and service access are handled by the BFF." />
    <div className="security-grid"><Card title="Signed-in profile" subtitle="Current BFF session">
      <div className="profile-row"><span className="avatar avatar--large">OA</span><div><strong>{session.user.displayName}</strong><p>{session.user.username}</p></div></div>
      <div className="fact-list"><Fact label="UI profile" value={session.profile} /><Fact label="Data mode" value="Live API" /><Fact label="Session expires" value={dateTime(session.expiresAt)} /></div>
    </Card><Card title="Security boundary" subtitle="Browser to CloudBank services">
      <div className="boundary"><span>Browser SPA</span><b>→</b><span>Session-backed BFF</span><b>→</b><span>OBaaS services</span></div>
      <p>The GUI uses an HttpOnly BFF session cookie. OAuth tokens and service credentials remain on the server.</p>
      <Badge tone="teal">BFF connected</Badge>
    </Card></div></>;
}

export function LiveApp() {
  const path = usePath();
  const pathname = path.split('?')[0];
  const [auth, setAuth] = useState<AuthState>({ kind: 'loading' });
  const [retry, setRetry] = useState(0);
  const [logoutError, setLogoutError] = useState('');
  const [loggingOut, setLoggingOut] = useState(false);
  const [created, setCreated] = useState<BffCreatedApplication | null>(null);
  const onSessionExpired = useCallback(() => setAuth({ kind: 'signedOut' }), []);

  useEffect(() => {
    const controller = new AbortController();
    getSession(controller.signal).then(session => {
      if (!controller.signal.aborted) setAuth({ kind: 'authenticated', session });
    }).catch(reason => {
      if (controller.signal.aborted) return;
      if (reason instanceof BffError && reason.status === 401) setAuth({ kind: 'signedOut' });
      else if (reason instanceof BffError && reason.status === 403) setAuth({ kind: 'forbidden', message: reason.message });
      else setAuth({ kind: 'unavailable', message: errorMessage(reason) });
    });
    return () => controller.abort();
  }, [retry]);

  useEffect(() => {
    if (auth.kind === 'authenticated' && pathname !== '/applications' && pathname !== '/applications/new' && pathname !== '/admin/security' && pathname !== '/manual-review') go('/applications');
    if (auth.kind === 'signedOut' && pathname !== '/login') go('/login');
  }, [auth.kind, pathname]);

  const retryConnection = () => { setAuth({ kind: 'loading' }); setRetry(value => value + 1); };
  const endSession = async () => {
    if (auth.kind !== 'authenticated') return;
    setLoggingOut(true);
    setLogoutError('');
    try {
      await logout(auth.session);
      setCreated(null);
      setAuth({ kind: 'signedOut' });
    } catch (reason) {
      if (reason instanceof BffError && reason.status === 401) setAuth({ kind: 'signedOut' });
      else setLogoutError(errorMessage(reason));
    } finally {
      setLoggingOut(false);
    }
  };

  if (auth.kind !== 'authenticated') return <LoginScreen state={auth} retry={retryConnection} />;
  const security = pathname === '/admin/security';
  const creating = pathname === '/applications/new';
  const reviewing = pathname === '/manual-review';
  return <div className="app-shell"><header className="topbar"><Link href="/applications" className="brand"><span className="logo-mark">CB</span><span><strong>CloudBank <b>AI</b></strong><small>OBaaS DEMO</small></span></Link>
    <nav aria-label="Main navigation"><Link href="/applications" className={`nav-link ${!security && !reviewing ? 'nav-link--active' : ''}`}>Applications</Link><Link href="/manual-review" className={`nav-link ${reviewing ? 'nav-link--active' : ''}`}>Manual review</Link><Link href="/admin/security" className={`nav-link ${security ? 'nav-link--active' : ''}`}>Security</Link></nav>
    <div className="topbar-right"><span className="mode-pill"><span className="dot dot--teal" /> LIVE BFF</span><span className="topbar-avatar" title={auth.session.user.username}>OA</span><button className="button button--small button--ghost" onClick={endSession} disabled={loggingOut}>{loggingOut ? 'Signing out…' : 'Sign out'}</button></div>
  </header><main className="main-content">{logoutError && <div className="live-error" role="alert">{logoutError}</div>}
    {!security && !creating && !reviewing && created && <div className="callout" role="status"><span className="callout-icon">✓</span><p>
      <strong>Application created: {created.scenarioName} · {created.applicationId}.</strong> Status: {label(created.status)}.
      {' '}Workflow dispatch at the last request: {label(created.workflow.dispatchStatus)}.
    </p></div>}
    {security ? <LiveSecurity session={auth.session} /> : reviewing
      ? <LiveManualReview session={auth.session} onSessionExpired={onSessionExpired} /> : creating
      ? <LiveNewApplication session={auth.session} onCreated={setCreated} />
      : <LiveApplications onSessionExpired={onSessionExpired} />}
  </main><footer className="footer"><span>{copyrightNotice}</span><span>Live applications via CloudBank BFF</span></footer></div>;
}
