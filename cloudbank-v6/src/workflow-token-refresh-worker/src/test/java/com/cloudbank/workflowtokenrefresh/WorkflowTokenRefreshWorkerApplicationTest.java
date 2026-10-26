// Copyright (c) 2026, Oracle and/or its affiliates.
//
// Licensed under the Universal Permissive License v 1.0 as shown at
// https://oss.oracle.com/licenses/upl/.

package com.cloudbank.workflowtokenrefresh;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.NONE,
        properties = "WORKFLOW_MODE=fake")
class WorkflowTokenRefreshWorkerApplicationTest {

    @Test
    void contextLoadsWhileTheWorkerIsIdleOutsideMicroTxMode() {
    }
}
