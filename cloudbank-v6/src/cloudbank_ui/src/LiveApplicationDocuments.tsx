// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.

import { useRef, useState } from 'react';
import { BffError, startProcessing, uploadDocument, type BffCreatedApplication, type BffSession, type BffUploadedDocument } from './bff';
import { Link } from './navigation';
import { Badge, Card, Fact, FilePicker, PageHeading } from './ui';

function message(error: unknown): string {
  return error instanceof BffError ? `${error.message}${error.correlationId ? ` Reference: ${error.correlationId}` : ''}`
    : 'The request could not be completed. Retry the same operation.';
}

const label = (value: string) => value.replaceAll('_', ' ').toLowerCase();
type UploadState = { busy?: boolean; error?: string; receipt?: BffUploadedDocument };

export function LiveApplicationDocuments({ application: initial, initialFiles, session, onStarted }: {
  application: BffCreatedApplication; initialFiles: Record<string, File>; session: BffSession;
  onStarted: (application: BffCreatedApplication) => void;
}) {
  const [application, setApplication] = useState(initial);
  const [files, setFiles] = useState<Record<string, File>>(initialFiles);
  const [uploads, setUploads] = useState<Record<string, UploadState>>({});
  const [starting, setStarting] = useState(false);
  const [accepted, setAccepted] = useState(false);
  const [startError, setStartError] = useState('');
  const operations = useRef<Record<string, { file: File | null; key: string }>>({});
  const activeUploads = useRef(new Set<string>());
  const startLock = useRef(false);
  const startAccepted = useRef(false);

  const upload = async (documentId: string) => {
    if (activeUploads.current.has(documentId) || startLock.current || startAccepted.current) return;
    activeUploads.current.add(documentId);
    setUploads(previous => ({ ...previous, [documentId]: { busy: true } }));
    const file = files[documentId] ?? null;
    if (!operations.current[documentId] || operations.current[documentId].file !== file) {
      operations.current[documentId] = { file, key: crypto.randomUUID() };
    }
    try {
      const receipt = await uploadDocument(application.applicationId, documentId, file, operations.current[documentId].key, session);
      setUploads(previous => ({ ...previous, [documentId]: { receipt } }));
      setApplication(previous => ({ ...previous, documents: previous.documents.map(doc =>
        doc.documentId === documentId ? { ...doc, status: receipt.status } : doc) }));
      setFiles(previous => { const next = { ...previous }; delete next[documentId]; return next; });
    } catch (error) {
      setUploads(previous => ({ ...previous, [documentId]: { error: message(error) } }));
    } finally {
      activeUploads.current.delete(documentId);
    }
  };

  const start = async () => {
    if (startLock.current || startAccepted.current || activeUploads.current.size > 0) return;
    startLock.current = true;
    setStarting(true);
    setStartError('');
    try {
      const result = await startProcessing(application.applicationId, session);
      setApplication(result);
      setUploads(previous => Object.fromEntries(result.documents.map(doc => [doc.documentId,
        doc.status === 'EXPECTED' ? previous[doc.documentId] ?? {} : { receipt: previous[doc.documentId]?.receipt }])));
      startAccepted.current = true;
      setAccepted(true);
      onStarted(result);
    } catch (error) {
      setStartError(message(error));
    } finally {
      startLock.current = false;
      setStarting(false);
    }
  };

  const uploading = Object.values(uploads).some(state => state.busy);
  return <><PageHeading eyebrow="APPLICATIONS / DOCUMENTS · LIVE BFF" title={application.scenarioName}
    description={`Application created · ${application.applicationId}. Upload the PDFs, then start processing.`}
    action={<Link href="/applications" className="button button--ghost">← Application list</Link>} />
    <Card title="Application saved" subtitle="Complete document upload and start on this page">
      <div className="fact-grid"><Fact label="Application ID" value={application.applicationId} />
        <Fact label="Application status" value={label(application.status)} />
        <Fact label="Workflow dispatch" value={label(application.workflow.dispatchStatus)} />
        <Fact label="Workflow ID" value={application.workflow.workflowId || 'Not assigned yet'} /></div>
    </Card>
    <Card title="Upload documents" subtitle="Each successful upload is stored by the loan service. PDF contents are immutable after receipt.">
      <div className="table-wrap"><table className="documents-table"><thead><tr><th>Document</th><th>File</th><th>Required for processing</th><th>Upload state</th><th>Action</th></tr></thead>
        <tbody>{application.documents.map(doc => {
          const state = uploads[doc.documentId];
          const received = doc.status !== 'EXPECTED';
          return <tr key={doc.documentId}><td><strong>{doc.documentLabel || doc.documentType.replaceAll('_', ' ')}</strong><small className="mono">{doc.documentId}</small></td>
            <td>{received ? <span>{doc.fileName}</span> : <FilePicker label={`Select file for ${doc.documentId}`}
              fileName={files[doc.documentId]?.name} disabled={Boolean(state?.busy) || starting || accepted}
              onChange={file => {
                setFiles(previous => { const next = { ...previous }; if (file) next[doc.documentId] = file; else delete next[doc.documentId]; return next; });
                setUploads(previous => ({ ...previous, [doc.documentId]: {} }));
              }} />}
              <small>Registered name: {doc.fileName}</small></td>
            <td>{doc.required ? 'Yes' : 'No'}</td>
            <td><Badge tone={received ? 'teal' : state?.error ? 'rose' : 'neutral'}>{state?.busy ? 'Uploading…' : received ? label(doc.status) : 'Not uploaded'}</Badge>
              {state?.receipt && <small>{state.receipt.contentLengthBytes.toLocaleString('en-US')} bytes stored</small>}
              {state?.error && <p className="live-error" role="alert">{state.error}</p>}</td>
            <td>{!received && <button className="button button--small button--secondary" disabled={Boolean(state?.busy) || starting || accepted}
              onClick={() => void upload(doc.documentId)}>{state?.busy ? 'Uploading…' : state?.error ? 'Retry upload' : 'Upload'}</button>}</td>
          </tr>;
        })}</tbody></table></div>
      <p className="helper">PDFs from 1 byte to 25 MiB. Backend checks apply. If a selected file could not be matched uniquely to a document, choose it again for the displayed document ID. Finish uploads before starting processing.</p>
    </Card>
    <Card title="Start processing" subtitle="Release this application's deferred workflow">
      {startError && <div className="live-error" role="alert">{startError}</div>}
      {accepted ? <div className="callout" role="status"><span className="callout-icon">✓</span><p>
        <strong>Start request accepted.</strong> Workflow dispatch: {label(application.workflow.dispatchStatus)}.
        {' '}Execution and the lending outcome are asynchronous. Refresh the application list to see the assigned workflow ID.
      </p></div> : <p>Upload the documents, then select Start processing. The backend handles release and dispatch; request acceptance does not mean workflow completion or loan approval.</p>}
      <div className="page-actions"><button className="button button--primary" disabled={starting || uploading || accepted} onClick={() => void start()}>
        {starting ? 'Requesting start…' : accepted ? 'Start accepted' : 'Start processing →'}</button>
        <Link href="/applications" className="button button--ghost">Return to application list</Link></div>
    </Card></>;
}
