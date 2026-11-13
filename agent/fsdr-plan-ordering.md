# Sequence the stack's FSDR plans

## Objective

Create, refresh, and verify the standard FSDR plans sequentially in ORM and local Terraform/OpenTofu, while retaining stack-wide parallelism and existing OCI plan identities.

## Evidence and design

The 2026-10-14 haddock apply created failover, switchover, and start-drill plans concurrently. Switchover failed during BRIE backup setup; the diagnostic log shows a backup pod disappearing and being replaced. Concurrent setup is the suspected service race.

The root module generates the fixed keys `failover`, `switchover`, `start_drill`, and `stop_drill`. Keep `failover` and custom regional-module keys in the existing `dr_plan` resource. Move the other three standard keys to separate resource blocks chained after it. Merge all four resource maps for outputs, executions, and Automatic DR. Custom keys retain their existing addresses and run in the initial stage; callers requiring serialization should use the standard keys.

Use static `moved` declarations for the three relocated keys. These work with Terraform 1.5 and preserve state during upgrade, including destroy preparation. The dependency graph supplies the ordering in both runtimes.

`agent/PLANS.md` is absent from this checkout; this file records the implementation plan.

## Work and validation

- [x] Implement ordered resources, moves, and merged references.
- [x] Cover all standard plans, subsets with missing intermediate stages, custom keys, and plan controls with mocked tests.
- [x] Check actual Terraform dependency paths and upgrade state moves in isolated local fixtures; never apply against OCI.
- [x] Run regional and parent FSDR suites and configuration validation.
- [x] Review with the simplify skill and update developer documentation.

## Results

The parent and regional FSDR suites passed all 29 mocked plans. All 10 Python tests passed, including actual provider graph checks for create/refresh, omitted intermediate plans, unrelated resource independence, and synthetic state migrations. Terraform 1.5.7 also confirmed three address moves with all five synthetic existing plans unchanged. Root configuration validation and formatting passed. The simplify review retained explicit resource blocks so dependencies and state migrations remain visible.

## Remaining verification

A fresh ORM deployment at normal parallelism must confirm whether sequencing resolves the observed BRIE failure.
