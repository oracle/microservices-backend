# Copyright (c) 2024, 2026, Oracle and/or its affiliates.
# All rights reserved. The Universal Permissive License (UPL), Version 1.0 as shown at http://oss.oracle.com/licenses/upl
# spell-checker: disable

mock_provider "oci" {}

variables {
  compartment_id = "test-compartment"
  display_name   = "test-group"
  log_location   = { bucket = "logs", namespace = "test" }
  automatic_dr = {
    display_name                  = "automatic"
    default_switchover_dr_plan_id = "switchover-plan"
    default_failover_dr_plan_id   = "failover-plan"
    members                       = [{ member_id = "standby-adb", member_type = "AUTONOMOUS_DATABASE", is_auto_switchover_enabled = true, is_auto_failover_enabled = true }]
  }
}

run "both_events" {
  command = plan
  assert {
    condition     = one(oci_disaster_recovery_automatic_dr_configuration.automatic_dr_configuration[0].members).is_auto_switchover_enabled && one(oci_disaster_recovery_automatic_dr_configuration.automatic_dr_configuration[0].members).is_auto_failover_enabled && oci_disaster_recovery_automatic_dr_configuration.automatic_dr_configuration[0].default_failover_dr_plan_id == "failover-plan"
    error_message = "Automatic DR must connect the standby member, events, and plans."
  }
}

run "failover_only" {
  command = plan
  variables {
    automatic_dr = {
      display_name                = "automatic"
      default_failover_dr_plan_id = "failover-plan"
      members                     = [{ member_id = "standby-adb", member_type = "AUTONOMOUS_DATABASE", is_auto_failover_enabled = true }]
    }
  }
  assert {
    condition     = !one(oci_disaster_recovery_automatic_dr_configuration.automatic_dr_configuration[0].members).is_auto_switchover_enabled && local.default_switchover_dr_plan_id == null
    error_message = "Automatic DR events must be independently selectable."
  }
}

run "missing_default_plan" {
  command = plan
  variables {
    automatic_dr = {
      display_name                  = "automatic"
      default_switchover_dr_plan_id = "switchover-plan"
      members                       = [{ member_id = "standby-adb", member_type = "AUTONOMOUS_DATABASE", is_auto_switchover_enabled = true, is_auto_failover_enabled = true }]
    }
  }
  expect_failures = [oci_disaster_recovery_automatic_dr_configuration.automatic_dr_configuration]
}

run "no_event" {
  command = plan
  variables {
    automatic_dr = {
      display_name = "automatic"
      members      = [{ member_id = "standby-adb", member_type = "AUTONOMOUS_DATABASE" }]
    }
  }
  expect_failures = [var.automatic_dr]
}

run "duplicate_member" {
  command = plan
  variables {
    automatic_dr = {
      display_name                = "automatic"
      default_failover_dr_plan_id = "failover-plan"
      members = [
        { member_id = "standby-adb", member_type = "AUTONOMOUS_DATABASE", is_auto_failover_enabled = true },
        { member_id = "standby-adb", member_type = "AUTONOMOUS_DATABASE", is_auto_switchover_enabled = true }
      ]
    }
  }
  expect_failures = [var.automatic_dr]
}
