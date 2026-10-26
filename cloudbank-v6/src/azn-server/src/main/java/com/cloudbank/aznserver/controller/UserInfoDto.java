// Copyright (c) 2022, 2026, Oracle and/or its affiliates.

package com.cloudbank.aznserver.controller;

import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.annotation.JsonProperty;

@JsonInclude(JsonInclude.Include.NON_NULL)
public record UserInfoDto(
    String username,
    @JsonProperty(access = JsonProperty.Access.WRITE_ONLY)
    String password,
    String email
) {}
