// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.policyretrieval.rest;

import com.cloudbank.policyretrieval.model.AiUse;
import com.cloudbank.policyretrieval.model.PolicyDocument;
import com.cloudbank.policyretrieval.model.PolicyRole;
import com.cloudbank.policyretrieval.retrieve.PolicyRetrievalService;
import com.cloudbank.policyretrieval.retrieve.RetrievalRequest;
import com.cloudbank.policyretrieval.retrieve.RetrievalResult;
import com.cloudbank.policyretrieval.vector.EmbeddingModel;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import java.util.Comparator;
import java.util.List;

@RestController
public class PolicyRetrievalController {
    private static final int WORKFLOW_RETRIEVAL_LIMIT = 3;
    private static final PolicyRole WORKFLOW_POLICY_ROLE = PolicyRole.UNDERWRITER;

    private final PolicyRetrievalService policyRetrievalService;
    private final EmbeddingModel embeddingModel;

    public PolicyRetrievalController(PolicyRetrievalService policyRetrievalService,
                                     EmbeddingModel embeddingModel) {
        this.policyRetrievalService = policyRetrievalService;
        this.embeddingModel = embeddingModel;
    }

    @GetMapping("/policy")
    public List<RetrievalResult> getRelatedPolicyChunksAndPolicies(@RequestParam("query") String query,
                                                                   @RequestParam(value = "limit", defaultValue = "3") int limit,
                                                                   @RequestParam(value = "aiUse", defaultValue = "retrieval") AiUse aiUse,
                                                                   Authentication authentication) {
        return retrieve(query, limit, aiUse, policyRole(authentication));
    }

    @GetMapping("/internal/api/v1/policy-evidence")
    @PreAuthorize("@policyRetrievalAuthorization.isInternal(authentication)")
    public List<RetrievalResult> getWorkflowPolicyEvidence(@RequestParam("query") String query) {
        return retrieve(query, WORKFLOW_RETRIEVAL_LIMIT, AiUse.RETRIEVAL, WORKFLOW_POLICY_ROLE);
    }

    private List<RetrievalResult> retrieve(String query, int limit, AiUse aiUse, PolicyRole role) {
        RetrievalRequest request = new RetrievalRequest(
                query,
                embeddingModel.embed(query),
                aiUse,
                role
        );
        return policyRetrievalService.search(request, limit);
    }

    private static PolicyRole policyRole(Authentication authentication) {
        return authentication.getAuthorities().stream()
                .map(GrantedAuthority::getAuthority)
                .filter(authority -> authority.startsWith("ROLE_"))
                .map(authority -> authority.substring("ROLE_".length()))
                .filter(PolicyRetrievalController::isPolicyRole)
                .map(PolicyRole::valueOf)
                .max(Comparator.comparingInt(PolicyRole::ordinal))
                .orElseThrow(() -> new AccessDeniedException("A CloudBank policy role is required"));
    }

    private static boolean isPolicyRole(String role) {
        for (PolicyRole policyRole : PolicyRole.values()) {
            if (policyRole.name().equals(role)) {
                return true;
            }
        }
        return false;
    }

    @GetMapping("/policy/{id}")
    public PolicyDocument getPolicyById(@PathVariable String id) {
        return policyRetrievalService.findById(id).orElseThrow();
    }
}
