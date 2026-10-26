// Copyright (c) 2026, Oracle and/or its affiliates.
//
// Licensed under the Universal Permissive License v 1.0 as shown at
// https://oss.oracle.com/licenses/upl/.
//

package com.cloudbank.documentingest.persistence;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

class ExtractionRepositoryTest {

    @Test
    void buildsReviewInputSqlWithLiteralPercentageRemoval() {
        String sql = ExtractionRepository.reviewInputSql(new SqlNames("cloudbank"));

        assertThat(sql)
                .contains("CLOUDBANK.CB_DOCUMENT_EXTRACTION")
                .contains("RETURNING VARCHAR2(40)), '%', '')) dti_pct")
                .doesNotContain("%%");
    }
}
