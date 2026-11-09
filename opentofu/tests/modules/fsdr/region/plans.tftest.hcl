# Copyright (c) 2024, 2026, Oracle and/or its affiliates.
# All rights reserved. The Universal Permissive License (UPL), Version 1.0 as shown at http://oss.oracle.com/licenses/upl
# spell-checker: disable

mock_provider "oci" {}

variables {
  compartment_id = "test-compartment"
  display_name   = "test-group"
  log_location   = { bucket = "logs", namespace = "test" }
}

run "disabled_by_default" {
  command = plan
  assert {
    condition     = length(output.dr_plan_ids) == 0 && length(output.dr_plan_execution_ids) == 0
    error_message = "Plan creation and execution must be opt-in."
  }
}

run "standard_plan_outputs" {
  command = plan
  variables {
    plans = {
      failover    = { display_name = "failover", type = "FAILOVER" }
      switchover  = { display_name = "switchover", type = "SWITCHOVER", refresh_trigger = 2 }
      start_drill = { display_name = "start", type = "START_DRILL", source_plan_id = "source-plan" }
      stop_drill  = { display_name = "stop", type = "STOP_DRILL", verify_trigger = 3, timeouts_create = "40m" }
    }
  }
  assert {
    condition     = toset(keys(output.dr_plans)) == toset(["failover", "switchover", "start_drill", "stop_drill"]) && toset(keys(output.dr_plan_ids)) == toset(keys(output.dr_plans))
    error_message = "Ordered plans must retain the public output keys."
  }
  assert {
    condition     = output.dr_plans["switchover"].refresh_trigger == 2 && output.dr_plans["start_drill"].source_plan_id == "source-plan" && output.dr_plans["stop_drill"].verify_trigger == 3 && output.dr_plans["stop_drill"].timeouts.create == "40m"
    error_message = "Ordered plans must retain refresh, clone, verification, and timeout settings."
  }
}

run "standard_plan_subset" {
  command = plan
  variables {
    plans = { stop_drill = { display_name = "stop", type = "STOP_DRILL" } }
  }
  assert {
    condition     = keys(output.dr_plans) == ["stop_drill"] && output.dr_plans["stop_drill"].type == "STOP_DRILL"
    error_message = "A plan must remain available when earlier stages are absent."
  }
}

run "ordered_plan_execution" {
  command = plan
  override_resource {
    target = oci_disaster_recovery_dr_plan.start_drill
    values = { id = "ordered-start-plan" }
  }
  variables {
    plans      = { start_drill = { display_name = "start", type = "START_DRILL" } }
    executions = { start_drill = { plan_execution_type = "START_DRILL_PRECHECK" } }
  }
  assert {
    condition     = oci_disaster_recovery_dr_plan_execution.dr_plan_execution["start_drill"].plan_id == "ordered-start-plan"
    error_message = "Executions must resolve plans from the ordered resources."
  }
}

run "drill_plan_controls" {
  command = plan
  variables {
    plans = { test = {
      display_name           = "drill"
      dr_protection_group_id = "standby-group"
      type                   = "START_DRILL"
      source_plan_id         = "source-plan"
      refresh_trigger        = 2
      verify_trigger         = 3
      timeouts_create        = "40m"
      timeouts_delete        = "30m"
    } }
  }
  assert {
    condition     = oci_disaster_recovery_dr_plan.dr_plan["test"].type == "START_DRILL" && oci_disaster_recovery_dr_plan.dr_plan["test"].refresh_trigger == 2 && oci_disaster_recovery_dr_plan.dr_plan["test"].verify_trigger == 3 && oci_disaster_recovery_dr_plan.dr_plan["test"].source_plan_id == "source-plan"
    error_message = "Drill, clone, refresh, and verify options must reach the plan."
  }
  assert {
    condition     = oci_disaster_recovery_dr_plan.dr_plan["test"].timeouts.create == "40m" && oci_disaster_recovery_dr_plan.dr_plan["test"].timeouts.delete == "30m"
    error_message = "Plan operation timeouts must be configurable."
  }
}

run "explicit_plan_selection" {
  command = plan
  variables {
    plans = { test = { display_name = "created", dr_protection_group_id = "standby", type = "SWITCHOVER" } }
    executions = { test = {
      plan_id               = "existing-plan"
      plan_execution_type   = "FAILOVER_PRECHECK"
      are_prechecks_enabled = true
      timeouts_delete       = "30m"
    } }
  }
  assert {
    condition     = oci_disaster_recovery_dr_plan_execution.dr_plan_execution["test"].plan_id == "existing-plan" && one(oci_disaster_recovery_dr_plan_execution.dr_plan_execution["test"].execution_options).plan_execution_type == "FAILOVER_PRECHECK" && oci_disaster_recovery_dr_plan_execution.dr_plan_execution["test"].timeouts.delete == "30m"
    error_message = "An explicit plan_id must take precedence over the created plan."
  }
}

run "created_plan_precheck" {
  command = plan
  variables {
    plans               = { test = { display_name = "created", dr_protection_group_id = "standby", type = "STOP_DRILL" } }
    executions          = { test = { plan_execution_type = "STOP_DRILL_PRECHECK" } }
    plan_association_id = "primary-group"
  }
  assert {
    condition     = one(oci_disaster_recovery_dr_plan_execution.dr_plan_execution["test"].execution_options).plan_execution_type == "STOP_DRILL_PRECHECK"
    error_message = "Created drill plans must support their precheck variant."
  }
  assert {
    condition     = terraform_data.plan_association[0].input.association == "primary-group"
    error_message = "Standby operations must carry the primary association dependency."
  }
}

run "invalid_plan_type" {
  command = plan
  variables {
    plans = { test = { display_name = "invalid", dr_protection_group_id = "standby", type = "UNKNOWN" } }
  }
  expect_failures = [var.plans]
}

run "mismatched_execution" {
  command = plan
  variables {
    plans      = { test = { display_name = "created", dr_protection_group_id = "standby", type = "SWITCHOVER" } }
    executions = { test = { plan_execution_type = "FAILOVER" } }
  }
  expect_failures = [oci_disaster_recovery_dr_plan_execution.dr_plan_execution]
}

run "missing_execution_plan" {
  command = plan
  variables {
    executions = { test = { plan_execution_type = "SWITCHOVER_PRECHECK" } }
  }
  expect_failures = [oci_disaster_recovery_dr_plan_execution.dr_plan_execution]
}
