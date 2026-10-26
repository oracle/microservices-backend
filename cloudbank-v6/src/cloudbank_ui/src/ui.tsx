import type { ReactNode } from 'react';
import type { Status } from './model';
import { Link } from './navigation';

export const statusLabels: Record<Status, string> = {
  APPROVED: 'Approved', MANUAL_REVIEW: 'Manual review', REJECTED: 'Rejected',
  RECOVERED: 'Processing recovered', DEFERRED: 'Awaiting start',
};

export function Badge({ children, tone = 'neutral' }: { children: ReactNode; tone?: 'neutral' | 'teal' | 'amber' | 'rose' | 'blue' }) {
  return <span className={`badge badge--${tone}`}>{children}</span>;
}

export function StatusBadge({ status }: { status: Status }) {
  const tone = status === 'APPROVED' ? 'teal' : status === 'REJECTED' ? 'rose' : status === 'MANUAL_REVIEW' ? 'amber' : 'blue';
  return <Badge tone={tone}>{statusLabels[status]}</Badge>;
}

export function PageHeading({ eyebrow, title, description, action }: { eyebrow: string; title: string; description?: string; action?: ReactNode }) {
  return <div className="page-heading"><div><div className="eyebrow">{eyebrow}</div><h1>{title}</h1>{description && <p>{description}</p>}</div>{action && <div className="heading-action">{action}</div>}</div>;
}

export function Card({ title, subtitle, children, action, className = '' }: { title?: string; subtitle?: string; children: ReactNode; action?: ReactNode; className?: string }) {
  return <section className={`card ${className}`}><div className="card-header">{title && <div><h2>{title}</h2>{subtitle && <p>{subtitle}</p>}</div>}{action}</div>{children}</section>;
}

export function Empty({ title, children }: { title: string; children: ReactNode }) {
  return <div className="empty"><div className="empty-icon">◇</div><strong>{title}</strong><p>{children}</p></div>;
}

export function Fact({ label, value }: { label: string; value: ReactNode }) {
  return <div className="fact"><span>{label}</span><strong>{value || '—'}</strong></div>;
}

export function FilePicker({ label, fileName, onChange, disabled = false }: { label: string; fileName?: string; onChange: (file: File | null) => void; disabled?: boolean }) {
  return <label className="file-picker"><input type="file" aria-label={label} disabled={disabled} onChange={event => onChange(event.target.files?.[0] ?? null)} /><span className="file-picker-button">Choose file</span><span className="file-picker-name">{fileName || 'No file selected'}</span></label>;
}

export function AppLink({ id, name, tab = 'overview' }: { id: string; name: string; tab?: string }) {
  return <Link href={`/applications/${id}?tab=${tab}`}>{name} <span className="mono muted">{id}</span></Link>;
}
