// Copyright (c) 2026, Oracle and/or its affiliates.
//
// Licensed under the Universal Permissive License v 1.0 as shown at
// https://oss.oracle.com/licenses/upl/.
//

package com.cloudbank.documentreview.persistence;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

@Component
public class SqlNames {
    private final String schema;

    public SqlNames(@Value("${cloudbank.schema:CLOUDBANK}") String schema) {
        if (!schema.matches("[A-Za-z][A-Za-z0-9_$#]{0,127}"))
            throw new IllegalArgumentException("Invalid schema name");
        this.schema = schema;
    }

    public String table(String name) {
        if (!name.matches("CB_[A-Z0-9_]+"))
            throw new IllegalArgumentException("Invalid table name");
        return schema + "." + name;
    }
}
