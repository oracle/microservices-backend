---
title: MicroTx Workflow Orchestration
sidebar_position: 4
---

MicroTx Workflow is a workflow orchestration platform, based on Orkes Conductor, which was originally developed at Netflix.  It is designed to coordinate long-running, distributed workflows across microservices by defining tasks, dependencies, and retries, while providing scalability, fault tolerance, and operational visibility through a centralized engine.

For reference: [Conductor OSS Documentation](https://docs.conductor-oss.org)

## Installing MicroTx Workflow

MicroTx Workflow Server is installed when `otmm.workflowServer.enabled` is set to `true` in the `values.yaml` file. The MicroTx transaction coordinator is controlled separately by `otmm.coordinator.enabled`.

```yaml
otmm:
  coordinator:
    enabled: true
  workflowServer:
    enabled: true
  console:
    enabled: true
```

The web user interface is requested with `otmm.console.enabled=true`, but it is deployed only when either `otmm.coordinator.enabled` or `otmm.workflowServer.enabled` is also `true`. The web user interface is optional; you may install just the workflow engine by setting `otmm.workflowServer.enabled=true` and `otmm.console.enabled=false`.
