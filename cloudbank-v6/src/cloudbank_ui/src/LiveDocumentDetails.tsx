import { useEffect, useRef, useState } from 'react';
import { BffError, documentContentUrl, getDocumentPdf, type BffWorkspaceDocument } from './bff';
import { Badge, Fact } from './ui';

export function LiveDocumentDetails({ applicationId, document: doc, onClose, onSessionExpired }: {
  applicationId: string; document: BffWorkspaceDocument; onClose: () => void; onSessionExpired: () => void;
}) {
  const dialog = useRef<HTMLDialogElement>(null);
  const [url, setUrl] = useState('');
  const [error, setError] = useState('');
  const [attempt, setAttempt] = useState(0);
  const [loading, setLoading] = useState(false);
  useEffect(() => {
    const opener = window.document.activeElement;
    const element = dialog.current;
    element?.showModal();
    return () => {
      if (element?.open) element.close();
      if (opener instanceof HTMLElement && opener.isConnected) opener.focus();
    };
  }, []);
  useEffect(() => {
    const controller = new AbortController();
    let objectUrl = '';
    setUrl(''); setError(''); setLoading(doc.contentAvailable);
    if (doc.contentAvailable) {
      getDocumentPdf(applicationId, doc.documentId, controller.signal).then(blob => {
        if (controller.signal.aborted) return;
        objectUrl = URL.createObjectURL(blob);
        setUrl(objectUrl);
      }).catch(reason => {
        if (controller.signal.aborted) return;
        if (reason instanceof BffError && reason.status === 401) onSessionExpired();
        else setError(reason instanceof BffError ? reason.message : 'The PDF could not be loaded. Retry opening it.');
      }).finally(() => { if (!controller.signal.aborted) setLoading(false); });
    }
    return () => { controller.abort(); if (objectUrl) URL.revokeObjectURL(objectUrl); };
  }, [applicationId, doc.documentId, doc.contentAvailable, attempt, onSessionExpired]);

  return <dialog ref={dialog} className="document-preview-dialog document-details-dialog" aria-labelledby="document-preview-title"
    onCancel={event => { event.preventDefault(); onClose(); }}>
    <div className="document-preview-header"><div><div className="eyebrow">DOCUMENT DETAILS · LIVE API</div>
      <h2 id="document-preview-title">{doc.fileName}</h2><small className="mono">{applicationId} / {doc.documentId}</small></div>
      <button className="button button--small button--secondary" onClick={onClose}>Close</button></div>
    <div className="document-details-body"><div className="document-details-facts">
      <Fact label="Document type" value={doc.documentLabel || doc.documentType.replaceAll('_', ' ')} />
      <Fact label="Status" value={doc.status.replaceAll('_', ' ')} /><Fact label="Required for processing" value={doc.required ? 'Yes' : 'No'} />
      <Fact label="Media type" value={doc.mediaType} /><Fact label="Stored size" value={doc.contentLengthBytes == null ? 'Not uploaded' : `${doc.contentLengthBytes.toLocaleString('en-US')} bytes`} />
      <Fact label="Content" value={doc.contentAvailable ? 'Stored immutable PDF' : 'Not available'} />
    </div><div className="document-details-preview" aria-busy={loading}>
      {loading && <p role="status" className="live-loading">Loading PDF preview…</p>}
      {!doc.contentAvailable && <p className="live-loading">No stored PDF is available for this document.</p>}
      {error && <div className="document-preview-error" role="alert"><p>{error}</p>
        <button className="button button--secondary" onClick={() => setAttempt(value => value + 1)}>Retry preview</button></div>}
      {url && <iframe className="document-preview-frame" src={url} title={`PDF preview: ${doc.fileName}`} />}
    </div></div>
    <div className="document-preview-footer"><span><Badge tone="teal">API</Badge> Read-only preview · If inline viewing is unsupported, open the PDF in a new tab.</span>
      {doc.contentAvailable && <a href={documentContentUrl(applicationId, doc.documentId)} target="_blank" rel="noreferrer">Open PDF in new tab ↗</a>}</div>
  </dialog>;
}
