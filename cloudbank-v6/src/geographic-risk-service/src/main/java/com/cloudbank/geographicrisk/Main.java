// Copyright (c) 2026, Oracle and/or its affiliates.

package com.cloudbank.geographicrisk;

import org.slf4j.bridge.SLF4JBridgeHandler;

public final class Main {

    private Main() {
    }

    public static void main(String[] args) {
        SLF4JBridgeHandler.removeHandlersForRootLogger();
        SLF4JBridgeHandler.install();
        io.helidon.microprofile.cdi.Main.main(args);
    }
}
