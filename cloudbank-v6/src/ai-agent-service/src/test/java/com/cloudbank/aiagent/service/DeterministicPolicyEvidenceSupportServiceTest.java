// Copyright (c) 2026, Oracle and/or its affiliates.
//
// Licensed under the Universal Permissive License v 1.0 as shown at
// https://oss.oracle.com/licenses/upl/.

package com.cloudbank.aiagent.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.cloudbank.aiagent.api.AiAgentApiModels.PolicyEvidenceInput;
import com.cloudbank.aiagent.api.AiAgentApiModels.PolicyEvidenceSupportRequest;
import java.util.List;
import org.junit.jupiter.api.Test;

class DeterministicPolicyEvidenceSupportServiceTest {
    private final DeterministicPolicyEvidenceSupportService service =
            new DeterministicPolicyEvidenceSupportService();

    @Test
    void returnsStableGroundedSupportWithCitationsFromSuppliedEvidence() {
        PolicyEvidenceSupportRequest request = request(List.of(evidence()));

        var first = service.summarize(request, "ai-policy:APP-ONE:WF-ONE");
        var replay = service.summarize(request, "ai-policy:APP-ONE:WF-ONE");

        assertThat(replay).isEqualTo(first);
        assertThat(first.policySupportId()).matches("AIPOL-[0-9a-f]{32}");
        assertThat(first.status()).isEqualTo("COMPLETED");
        assertThat(first.evidenceStatus()).isEqualTo("GROUNDED");
        assertThat(first.citations()).singleElement().satisfies(citation -> {
            assertThat(citation.policyCode()).isEqualTo("CB-PL-001");
            assertThat(citation.sectionRef()).isEqualTo("SEC-INCOME");
            assertThat(citation.chunkId()).isEqualTo("CHUNK-INCOME-1");
        });
        assertThat(first.sourceReferences()).singleElement().satisfies(source -> {
            assertThat(source.sourceType()).isEqualTo("POLICY_CHUNK");
            assertThat(source.sourceId()).isEqualTo("CHUNK-INCOME-1");
        });
        assertThat(first.guardrailStatus()).isEqualTo("PASSED");
    }

    @Test
    void reportsInsufficientEvidenceWithoutInventingPolicyCitations() {
        var response = service.summarize(request(List.of()), "ai-policy:APP-ONE:WF-ONE");

        assertThat(response.status()).isEqualTo("COMPLETED");
        assertThat(response.evidenceStatus()).isEqualTo("INSUFFICIENT_EVIDENCE");
        assertThat(response.citations()).isEmpty();
        assertThat(response.sourceReferences()).isEmpty();
        assertThat(response.summary()).contains("no authorized policy evidence");
    }

    private static PolicyEvidenceSupportRequest request(List<PolicyEvidenceInput> evidence) {
        return new PolicyEvidenceSupportRequest("APP-ONE", "WF-ONE", "ai_policy_evidence_support",
                "0123456789abcdef0123456789abcdef", "DREV-00000000000000000000000000000000",
                "AISUM-00000000000000000000000000000000", "UNDERWRITER", evidence);
    }

    private static PolicyEvidenceInput evidence() {
        return new PolicyEvidenceInput("POLICY-DOC-001", "CB-PL-001", "2026.0", "CHUNK-INCOME-1",
                "SEC-INCOME", "Verified income", "Use verified income evidence for affordability checks.", 0.93);
    }
}
