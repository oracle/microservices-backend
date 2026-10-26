// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.

import type { BffCreationInput, BffDocument } from './bff';

export type SelectedDocument = BffCreationInput['documents'][number] & { rowId: string; file: File | null };

// Match by metadata only when there is exactly one candidate on each side.
// Duplicate rows deliberately require an explicit file choice against the returned ID.
export function bindDocumentFiles(submitted: SelectedDocument[], returned: BffDocument[]): Record<string, File> {
  const signature = (doc: BffCreationInput['documents'][number]) => JSON.stringify([doc.documentType, doc.fileName, doc.required]);
  const files: Record<string, File> = {};
  for (const document of returned) {
    const key = signature(document);
    const candidates = submitted.filter(doc => signature(doc) === key);
    if (candidates.length === 1 && returned.filter(doc => signature(doc) === key).length === 1 && candidates[0].file) {
      files[document.documentId] = candidates[0].file;
    }
  }
  return files;
}
