// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.policyretrieval.rest;

import com.cloudbank.policyretrieval.model.AiUse;
import org.springframework.core.convert.converter.Converter;
import org.springframework.stereotype.Component;

/** Converts the stable lowercase API values into the corresponding domain enum. */
@Component
public class AiUseConverter implements Converter<String, AiUse> {

    @Override
    public AiUse convert(String source) {
        return AiUse.fromValue(source);
    }
}
