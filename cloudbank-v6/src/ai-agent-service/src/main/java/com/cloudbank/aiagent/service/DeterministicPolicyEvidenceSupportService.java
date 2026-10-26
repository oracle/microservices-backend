// Copyright (c) 2026, Oracle and/or its affiliates.
//
// Licensed under the Universal Permissive License v 1.0 as shown at
// https://oss.oracle.com/licenses/upl/.

package com.cloudbank.aiagent.service;

import com.cloudbank.aiagent.api.AiAgentApiModels.PolicyCitation;
import com.cloudbank.aiagent.api.AiAgentApiModels.PolicyEvidenceInput;
import com.cloudbank.aiagent.api.AiAgentApiModels.PolicyEvidenceSupportRequest;
import com.cloudbank.aiagent.api.AiAgentApiModels.PolicyEvidenceSupportResponse;
import com.cloudbank.aiagent.api.AiAgentApiModels.SourceReference;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import java.util.List;
import org.springframework.stereotype.Service;

@Service
public class DeterministicPolicyEvidenceSupportService {
    private static final String GROUNDED_SUMMARY =
            "Deterministic fixture summary: authorized policy evidence is available for deterministic decisioning and underwriting review.";
    private static final String INSUFFICIENT_SUMMARY =
            "Deterministic fixture summary: no authorized policy evidence was supplied; no policy conclusion was created.";

    public PolicyEvidenceSupportResponse summarize(PolicyEvidenceSupportRequest request, String idempotencyKey) {
        String policySupportId = "AIPOL-" + digest(idempotencyKey, request).substring(0, 32);
        boolean grounded = !request.policyEvidence().isEmpty();
        List<PolicyCitation> citations = request.policyEvidence().stream().map(this::citation).toList();
        List<SourceReference> sources = request.policyEvidence().stream()
                .map(evidence -> new SourceReference("POLICY_CHUNK", evidence.chunkId())).toList();
        List<String> notes = grounded
                ? List.of("Use only the cited policy chunks as supporting evidence.",
                        "Apply deterministic policy and lending rules outside the AI service.")
                : List.of("Retrieve authorized policy evidence before relying on policy support.",
                        "Route incomplete evidence according to deterministic workflow rules.");

        return new PolicyEvidenceSupportResponse(policySupportId, "COMPLETED", "deterministic-fixture",
                "fixed-response-v1", request.applicationId(), request.workflowId(), request.taskReference(),
                request.traceId(), request.reviewId(), request.documentSummaryId(), request.audience(),
                grounded ? "GROUNDED" : "INSUFFICIENT_EVIDENCE",
                grounded ? GROUNDED_SUMMARY : INSUFFICIENT_SUMMARY, citations, notes, sources, "PASSED");
    }

    private PolicyCitation citation(PolicyEvidenceInput evidence) {
        return new PolicyCitation(evidence.policyDocumentId(), evidence.policyCode(), evidence.policyVersion(),
                evidence.chunkId(), evidence.sectionRef(), evidence.heading());
    }

    private String digest(String idempotencyKey, PolicyEvidenceSupportRequest request) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            update(digest, idempotencyKey, request.applicationId(), request.workflowId(), request.taskReference(),
                    request.traceId(), request.reviewId(), request.documentSummaryId(), request.audience());
            request.policyEvidence().forEach(evidence -> update(digest, evidence.policyDocumentId(),
                    evidence.policyCode(), evidence.policyVersion(), evidence.chunkId(), evidence.sectionRef(),
                    evidence.heading(), evidence.content(), Double.toString(evidence.vectorScore())));
            return HexFormat.of().formatHex(digest.digest());
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException("SHA-256 is not available", exception);
        }
    }

    private void update(MessageDigest digest, String... values) {
        for (String value : values) {
            digest.update(value.getBytes(StandardCharsets.UTF_8));
            digest.update((byte) 0);
        }
    }
}
