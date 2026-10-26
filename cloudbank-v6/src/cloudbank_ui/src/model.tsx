import { createContext, useContext, useState, type ReactNode } from 'react';

export type Status = 'APPROVED' | 'MANUAL_REVIEW' | 'REJECTED' | 'RECOVERED' | 'DEFERRED';
export type DocumentStatus = 'EXPECTED' | 'RECEIVED' | 'VALIDATED' | 'NEEDS_REVIEW';

export interface DocumentRow {
  id: string;
  type: string;
  required: boolean;
  fileName: string;
  status: DocumentStatus;
}

export interface AuditEvent {
  at: string;
  action: string;
  detail: string;
}

export interface MockApplication {
  id: string;
  scenarioId: string;
  name: string;
  description: string;
  status: Status;
  expected: string;
  canonical: boolean;
  amount: string;
  term: string;
  purpose: string;
  policyVersion: string;
  applicant: string;
  ageBand: string;
  phoneToken: string;
  emailToken: string;
  addressLine: string;
  locality: string;
  jurisdiction: string;
  country: string;
  postalCode: string;
  addressToken: string;
  workflowId: string;
  traceId: string;
  documents: DocumentRow[];
  decision: { outcome: string; riskBand: string; explanation: string; citations: string[] } | null;
  reviewReason: string;
  reviewPriority: string;
  audit: AuditEvent[];
}

export type Draft = Pick<MockApplication,
  'scenarioId' | 'name' | 'applicant' | 'ageBand' | 'phoneToken' | 'emailToken' |
  'addressLine' | 'locality' | 'jurisdiction' | 'country' | 'postalCode' |
  'addressToken' | 'amount' | 'term' | 'purpose' | 'policyVersion'>;

const seed = (
  id: string, scenarioId: string, name: string, description: string, status: Status,
  amount: string, term: string, purpose: string, documentTypes: [string, DocumentStatus, string][],
  riskBand: string, explanation: string, citations: string[], reviewReason = '', reviewPriority = 'Normal',
): MockApplication => ({
  id, scenarioId, name, description, status, expected: status === 'RECOVERED' ? 'FAILED_RETRYABLE_RECOVERED' : status,
  canonical: true, amount, term, purpose, policyVersion: '2026.0', applicant: 'Synthetic applicant',
  ageBand: '35-44', phoneToken: 'PHONE-SYNTH', emailToken: 'EMAIL-SYNTH', addressLine: '10 Demo Avenue',
  locality: 'Demo City', jurisdiction: 'US-CA', country: 'US', postalCode: '00000', addressToken: 'ADDR-SYNTH',
  workflowId: `WF-${id}`, traceId: `trace-${id.toLowerCase().slice(4)}`,
  documents: documentTypes.map(([type, docStatus, fileName], index) => ({
    id: seedDocumentIds[id][index],
    type, status: docStatus, fileName, required: true,
  })),
  decision: { outcome: status === 'RECOVERED' ? 'Final outcome pending' : status, riskBand, explanation, citations },
  reviewReason, reviewPriority,
  audit: [
    { at: '09:12', action: 'APPLICATION_CREATED', detail: 'Synthetic application received' },
    { at: '09:14', action: 'WORKFLOW_STARTED', detail: 'Simulated processing started' },
    { at: '09:18', action: status === 'MANUAL_REVIEW' ? 'HUMAN_REVIEW_OPENED' : 'STATE_UPDATED', detail: `Status ${status} (mock)` },
  ],
});

const seedDocumentIds: Record<string, string[]> = {
  'APP-APR-001': ['DOC-APR-001', 'DOC-APR-002', 'DOC-APR-003', 'DOC-APR-006', 'DOC-APR-007'],
  'APP-MR-002': ['DOC-MR-001', 'DOC-MR-006', 'DOC-MR-007'],
  'APP-REJ-003': ['DOC-REJ-001', 'DOC-REJ-006', 'DOC-REJ-008'],
  'APP-OPFAIL-004': ['DOC-OPF-001', 'DOC-OPF-006', 'DOC-OPF-010'],
  'APP-RISK-005': ['DOC-RSK-001', 'DOC-RSK-006', 'DOC-RSK-010'],
};

export const canonicalApplications: MockApplication[] = [
  seed('APP-APR-001', 'SCN-FAST-APPROVAL-001', 'Fast Approval: Stable Income And Low Debt',
    'Stable verified income, complete documents, and a low debt-to-income ratio.', 'APPROVED', '16000', '36', 'DEBT_CONSOLIDATION',
    [['LOAN_APPLICATION', 'VALIDATED', 'loan_application.pdf'], ['DISCLOSURE_CONSENT', 'VALIDATED', 'applicant_disclosures_and_consent.pdf'], ['IDENTITY_SUMMARY', 'VALIDATED', 'identity_verification_summary.pdf'], ['PAY_STATEMENT', 'VALIDATED', 'pay_statement_novereign_systems.pdf'], ['DEPOSIT_SUMMARY', 'VALIDATED', 'deposit_summary_cloudbank.pdf']],
    'CB-A', 'Complete eligibility evidence, stable income, and policy checks passed.', ['CBPL-100-S3-C01', 'CBPL-120-S5-C01', 'CBPL-130-S5-C01', 'CBPL-140-S3-C01']),
  seed('APP-MR-002', 'SCN-MANUAL-REVIEW-002', 'Manual Review: Income Inconsistency',
    'Pay and deposit evidence do not fully agree.', 'MANUAL_REVIEW', '18000', '48', 'DEBT_CONSOLIDATION',
    [['LOAN_APPLICATION', 'VALIDATED', 'loan_application.pdf'], ['PAY_STATEMENT', 'NEEDS_REVIEW', 'earnings_statement_lumenfield.pdf'], ['ACCOUNT_ACTIVITY', 'NEEDS_REVIEW', 'account_activity_summary.pdf']],
    'CB-B', 'Human review is required because income evidence is inconsistent and extraction confidence is below threshold.', ['CBPL-120-S4-C01', 'CBPL-130-S3-C01', 'CBPL-150-S2-C01', 'CBPL-160-S3-C01'], 'Pay statement and account activity differ', 'High'),
  seed('APP-REJ-003', 'SCN-REJECTION-003', 'Rejection: Insufficient Verified Capacity',
    'Verified income cannot support the requested payment and existing obligations.', 'REJECTED', '30000', '48', 'OTHER_CONSUMER_PURPOSE',
    [['LOAN_APPLICATION', 'VALIDATED', 'loan_application.pdf'], ['CONTRACTOR_INCOME', 'NEEDS_REVIEW', 'contractor_income_statement.pdf'], ['LIABILITY_SCHEDULE', 'VALIDATED', 'liability_schedule.pdf']],
    'CB-X', 'Verified repayment capacity is insufficient for the payment and stated obligations.', ['CBPL-130-S4-C01', 'CBPL-160-S4-C01']),
  seed('APP-OPFAIL-004', 'SCN-OPERATIONAL-FAILURE-004', 'Recovered Processing Failure',
    'A temporary ingest failure is recovered after a retry.', 'RECOVERED', '22000', '48', 'HOME_IMPROVEMENT',
    [['LOAN_APPLICATION', 'VALIDATED', 'loan_application.pdf'], ['PAY_STATEMENT', 'VALIDATED', 'pay_statement_sablecrest.pdf'], ['DOCUMENT_RECEIPT', 'VALIDATED', 'document_receipt.pdf']],
    'CB-A', 'Document processing recovered; the final lending outcome remains separate.', ['CBPL-150-S6-C01', 'CBPL-170-S5-C01']),
  seed('APP-RISK-005', 'SCN-RISK-SIGNAL-005', 'Manual Review: Relationship And Location Risk',
    'Identity, relationship, and location signals require human review.', 'MANUAL_REVIEW', '12000', '36', 'MAJOR_PURCHASE',
    [['LOAN_APPLICATION', 'VALIDATED', 'loan_application.pdf'], ['PAY_STATEMENT', 'VALIDATED', 'pay_statement_copperline.pdf'], ['RELATIONSHIP_SIGNAL', 'NEEDS_REVIEW', 'relationship_signal_summary.pdf']],
    'CB-B', 'Identity and relationship signals require review before the final decision.', ['CBPL-110-S4-C01', 'CBPL-150-S3-C01', 'CBPL-170-S4-C01'], 'Relationship and location signals', 'High'),
];

export interface NewDocument { type: string; required: boolean; file: File | null }

interface Store {
  applications: MockApplication[];
  pendingFiles: Record<string, File>;
  create: (draft: Draft, documents: NewDocument[]) => string;
  upload: (applicationId: string, documentId: string, file: File) => void;
  addDocument: (applicationId: string, type: string, required: boolean, file: File | null) => void;
  start: (applicationId: string) => void;
  review: (applicationId: string, outcome: string, reason: string, section: string) => void;
  reset: () => void;
}

const StoreContext = createContext<Store | null>(null);
const now = () => new Date().toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' });

export function MockStoreProvider({ children }: { children: ReactNode }) {
  const [applications, setApplications] = useState<MockApplication[]>(canonicalApplications);
  const [pendingFiles, setPendingFiles] = useState<Record<string, File>>({});
  const [counter, setCounter] = useState(1);

  const change = (id: string, fn: (app: MockApplication) => MockApplication) => {
    setApplications(previous => previous.map(app => app.id === id ? fn(app) : app));
  };

  const create = (draft: Draft, docs: NewDocument[]) => {
    const id = `APP-NEW-${String(counter).padStart(3, '0')}`;
    const rows = docs.map((doc, index) => ({
      id: `DOC-NEW-${String(counter).padStart(3, '0')}-${index + 1}`,
      type: doc.type, required: doc.required, fileName: doc.file?.name ?? '', status: 'EXPECTED' as DocumentStatus,
    }));
    const files: Record<string, File> = {};
    docs.forEach((doc, index) => { if (doc.file) files[rows[index].id] = doc.file; });
    setPendingFiles(previous => ({ ...previous, ...files }));
    setApplications(previous => [{
      ...draft, id, name: draft.name || 'New synthetic application', description: 'Application created locally with deferred processing.',
      status: 'DEFERRED', expected: 'Simulated manual review', canonical: false,
      workflowId: 'Not started', traceId: 'Unavailable', documents: rows, decision: null,
      reviewReason: '', reviewPriority: 'Normal',
      audit: [{ at: now(), action: 'APPLICATION_CREATED', detail: 'Metadata created in DEFERRED mode (mock)' }],
    }, ...previous]);
    setCounter(previous => previous + 1);
    return id;
  };

  const upload = (applicationId: string, documentId: string, file: File) => {
    change(applicationId, app => ({ ...app,
      documents: app.documents.map(doc => doc.id === documentId ? { ...doc, status: 'RECEIVED', fileName: file.name } : doc),
      audit: [...app.audit, { at: now(), action: 'DOCUMENT_RECEIVED', detail: `${documentId}: simulated upload, file ${file.name}` }],
    }));
    setPendingFiles(previous => { const next = { ...previous }; delete next[documentId]; return next; });
  };

  const addDocument = (applicationId: string, type: string, required: boolean, file: File | null) => {
    const id = `DOC-${applicationId}-${Date.now()}`;
    change(applicationId, app => ({ ...app, documents: [...app.documents, { id, type, required, fileName: file?.name ?? '', status: 'EXPECTED' }] }));
    if (file) setPendingFiles(previous => ({ ...previous, [id]: file }));
  };

  const start = (applicationId: string) => {
    change(applicationId, app => ({ ...app,
      status: 'MANUAL_REVIEW', workflowId: `WF-${applicationId}`, traceId: `trace-${applicationId.toLowerCase()}`,
      reviewReason: 'Demo review after simulated processing',
      decision: { outcome: 'MANUAL_REVIEW', riskBand: 'Not calculated', explanation: 'Fixed mock path: human review required.', citations: [] },
      audit: [...app.audit,
        { at: now(), action: 'WORKFLOW_STARTED', detail: 'Deferred start released (mock)' },
        { at: now(), action: 'HUMAN_REVIEW_OPENED', detail: 'Simulated review task' }],
    }));
  };

  const review = (applicationId: string, outcome: string, reason: string, section: string) => {
    change(applicationId, app => ({ ...app, status: outcome as Status, reviewReason: '',
      decision: { outcome, riskBand: app.decision?.riskBand ?? 'Not calculated',
        explanation: 'Simulated final outcome after human review completion.',
        citations: section ? [section] : app.decision?.citations ?? [] },
      audit: [...app.audit,
        { at: now(), action: 'HUMAN_REVIEW_COMPLETED', detail: `Requested outcome ${outcome}; reason ${reason || 'not provided'}; section ${section || 'not provided'} (mock)` },
        { at: now(), action: 'FINAL_DECISION_SIMULATED', detail: `Outcome ${outcome} simulated after workflow resume` }],
    }));
  };

  const reset = () => { setApplications(canonicalApplications); setPendingFiles({}); setCounter(1); };
  return <StoreContext.Provider value={{ applications, pendingFiles, create, upload, addDocument, start, review, reset }}>{children}</StoreContext.Provider>;
}

export function useMockStore() {
  const store = useContext(StoreContext);
  if (!store) throw new Error('MockStoreProvider is missing');
  return store;
}
