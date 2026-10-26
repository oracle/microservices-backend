// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.

import { useRef, useState } from 'react';
import { BffError, createApplication, type BffCreatedApplication, type BffCreationInput, type BffSession } from './bff';
import { Link } from './navigation';
import { documentTypes, fields } from './pages';
import { Badge, Card, FilePicker, PageHeading } from './ui';
import { bindDocumentFiles, type SelectedDocument } from './intake';
import { LiveApplicationDocuments } from './LiveApplicationDocuments';
import { createNewApplicationDocuments, createNewApplicationDraft } from './newApplicationDefaults';

export function LiveNewApplication({ session, onCreated }: {
  session: BffSession; onCreated: (application: BffCreatedApplication) => void;
}) {
  const [draft, setDraft] = useState(createNewApplicationDraft);
  const [documents, setDocuments] = useState<SelectedDocument[]>(createNewApplicationDocuments);
  const [created, setCreated] = useState<BffCreatedApplication | null>(null);
  const [selectedFiles, setSelectedFiles] = useState<Record<string, File>>({});
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState('');
  const operation = useRef<{ payload: string; key: string } | null>(null);
  const inFlight = useRef(false);

  const changeDocument = (index: number, patch: Partial<SelectedDocument>) =>
    setDocuments(previous => previous.map((row, i) => i === index ? { ...row, ...patch } : row));

  const submit = async () => {
    if (inFlight.current) return;
    inFlight.current = true;
    setSubmitting(true);
    setError('');
    try {
      const input: BffCreationInput = {
        scenarioId: draft.scenarioId, scenarioName: draft.name,
        applicant: {
          displayName: draft.applicant, phoneToken: draft.phoneToken, emailToken: draft.emailToken, ageBand: draft.ageBand,
          address: { addressLine: draft.addressLine, locality: draft.locality, jurisdictionCode: draft.jurisdiction,
            addressToken: draft.addressToken, countryCode: draft.country, postalCode: draft.postalCode },
        },
        loan: { requestedAmount: draft.amount, requestedTermMonths: draft.term, purposeCode: draft.purpose, policyVersion: draft.policyVersion },
        documents: documents.map(({ documentType, fileName, required }) => ({ documentType, fileName, required })),
      };
      const payload = JSON.stringify(input);
      if (operation.current?.payload !== payload) operation.current = { payload, key: crypto.randomUUID() };
      const result = await createApplication(input, operation.current.key, session);
      setSelectedFiles(bindDocumentFiles(documents, result.documents));
      setCreated(result);
      onCreated(result);
    } catch (reason) {
      setError(reason instanceof BffError
        ? `${reason.message}${reason.correlationId ? ` Reference: ${reason.correlationId}` : ''}`
        : 'The application could not be created. Check the application list before retrying.');
    } finally {
      inFlight.current = false;
      setSubmitting(false);
    }
  };

  if (created) return <LiveApplicationDocuments application={created} initialFiles={selectedFiles}
    session={session} onStarted={onCreated} />;

  return <><PageHeading eyebrow="APPLICATIONS / NEW · LIVE BFF" title="Create application"
    description="Create the application, upload its PDFs, then start processing explicitly."
    action={<Link href="/applications" className="button button--ghost">← Back to list</Link>} />
    <form noValidate onSubmit={event => { event.preventDefault(); void submit(); }}>
      {error && <div className="live-error" role="alert">{error}</div>}
      <fieldset disabled={submitting} className="application-form-fields">
        <Card title="Application details" subtitle="Prefilled from the geocoded smoke test. All values remain editable.">
          <div className="field-grid">{fields.map(field => <label className="field" key={field.key}><span>{field.label}</span>
            {field.choices ? <select value={draft[field.key]} onChange={event => setDraft(previous => ({ ...previous, [field.key]: event.target.value }))}>
              <option value="">{field.hint}</option>{field.choices.map(([value, label]) => <option value={value} key={value}>{label}</option>)}
            </select> : <input value={draft[field.key]} placeholder={field.hint} inputMode={field.key === 'amount' ? 'decimal' : 'text'}
              onChange={event => setDraft(previous => ({ ...previous, [field.key]: event.target.value }))} />}
          </label>)}</div>
        </Card>
        <Card title="Documents" subtitle="Select files now. Upload each PDF after the application is created."
          action={<button type="button" className="button button--ghost" onClick={() => setDocuments(previous => [...previous, { rowId: crypto.randomUUID(), documentType: '', fileName: '', required: true, file: null }])}>＋ Add row</button>}>
          <div className="table-wrap"><table className="documents-table"><thead><tr><th>Document type</th><th>Required for processing</th><th>File name</th><th>Upload state</th><th></th></tr></thead>
            <tbody>{documents.map((row, index) => <tr key={row.rowId}><td>
              <select aria-label={`Document type ${index + 1}`} value={row.documentType} onChange={event => changeDocument(index, { documentType: event.target.value })}>
                <option value="">Select type</option>{documentTypes.map(type => <option value={type} key={type}>{type.replaceAll('_', ' ')}</option>)}
              </select></td><td><label className="checkbox-label"><input type="checkbox" checked={row.required} onChange={event => changeDocument(index, { required: event.target.checked })} /><span>Yes</span></label></td>
              <td><FilePicker label={`Document file ${index + 1}`} fileName={row.file?.name} onChange={file => changeDocument(index, { file, fileName: file?.name ?? row.fileName })} /><small>Metadata file name: {row.fileName || 'Not specified'}</small></td>
              <td><Badge>Not uploaded</Badge></td><td><button type="button" className="icon-button" aria-label={`Remove row ${index + 1}`} onClick={() => setDocuments(previous => previous.filter((_, i) => i !== index))}>×</button></td>
            </tr>)}</tbody></table></div>
          <p className="helper">Ready-to-upload loan_application.pdf and pay_statement_novereign_systems.pdf are in synthetic_data/customer_packets/demo_geocoded_loan/. Choose them now or after creation, then upload each PDF on the next page. Application IDs are assigned by the backend; no PDF generation is required. The backend accepts 1 byte to 25 MiB.</p>
        </Card>
        <div className="form-footer"><span><strong>Deferred processing</strong><small>Next: upload documents and start processing.</small></span>
          <button className="button button--primary" type="submit">{submitting ? 'Creating application…' : 'Create application →'}</button>
        </div>
      </fieldset>
    </form></>;
}
