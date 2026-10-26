// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/.

import application from '../../../synthetic_data/customer_packets/demo_geocoded_loan/application.json';
import type { Draft } from './model';
import type { SelectedDocument } from './intake';

// Same standard intake as start-geocoded-loan-oke.sh and its smoke-test adapter.
// New forms receive independent synthetic correlation values, never fixture IDs.
export function createNewApplicationDraft(): Draft {
  const runId = crypto.randomUUID();
  return {
    scenarioId: `${application.scenarioId}-${runId}`,
    name: application.scenarioName,
    applicant: application.applicant.displayName,
    ageBand: application.applicant.ageBand,
    phoneToken: `${application.applicant.phoneToken}-${runId}`,
    emailToken: `${application.applicant.emailToken}-${runId}`,
    addressLine: application.applicant.address.addressLine,
    locality: application.applicant.address.locality,
    jurisdiction: application.applicant.address.jurisdictionCode,
    country: application.applicant.address.countryCode,
    postalCode: application.applicant.address.postalCode,
    addressToken: `${application.applicant.address.addressToken}-${runId}`,
    amount: application.loan.requestedAmount.toFixed(2),
    term: String(application.loan.requestedTermMonths),
    purpose: application.loan.purposeCode,
    policyVersion: application.loan.policyVersion,
  };
}

export function createNewApplicationDocuments(): SelectedDocument[] {
  return application.documents.map(document => ({ ...document, rowId: crypto.randomUUID(), file: null }));
}
