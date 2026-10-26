// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.policyretrieval;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Collections;
import java.util.Map;

@RestController
@RequestMapping("/policy")
public class PolicyController {
    @GetMapping("/{id}/chunk")
    public Map<String, String> getPolicyChunk(@PathVariable String id) {
        // Stub: return a static policy chunk for demo purposes
        return Collections.singletonMap("content", "This is a stubbed policy chunk for policy id=" + id);
    }
}
