# Copyright (c) 2024, 2026, Oracle and/or its affiliates.
# All rights reserved. The Universal Permissive License (UPL), Version 1.0 as shown at http://oss.oracle.com/licenses/upl
# spell-checker: disable

# Complete association and member enrollment before creating standby plans.
resource "terraform_data" "plan_association" {
  count = length(var.plans) > 0 || length(var.executions) > 0 || var.automatic_dr != null ? 1 : 0
  input = { association = var.plan_association_id, members = var.members_ready_id }
}

# Standard plan operations share BRIE backup setup on the same OKE cluster.
resource "oci_disaster_recovery_dr_plan" "dr_plan" {
  for_each               = { for key, plan in var.plans : key => plan if !contains(["switchover", "start_drill", "stop_drill"], key) }
  display_name           = each.value["display_name"]
  dr_protection_group_id = each.value.dr_protection_group_id != null ? each.value.dr_protection_group_id : oci_disaster_recovery_dr_protection_group.dr_protection_group.id
  type                   = each.value["type"]
  defined_tags           = each.value["defined_tags"]
  freeform_tags          = each.value["freeform_tags"]
  source_plan_id         = each.value["source_plan_id"]
  refresh_trigger        = each.value["refresh_trigger"]
  verify_trigger         = each.value["verify_trigger"]
  depends_on             = [terraform_data.plan_association]
  timeouts {
    create = each.value.timeouts_create
    update = each.value.timeouts_update
    delete = each.value.timeouts_delete
  }
}

resource "oci_disaster_recovery_dr_plan" "switchover" {
  for_each               = { for key, plan in var.plans : key => plan if key == "switchover" }
  display_name           = each.value["display_name"]
  dr_protection_group_id = each.value.dr_protection_group_id != null ? each.value.dr_protection_group_id : oci_disaster_recovery_dr_protection_group.dr_protection_group.id
  type                   = each.value["type"]
  defined_tags           = each.value["defined_tags"]
  freeform_tags          = each.value["freeform_tags"]
  source_plan_id         = each.value["source_plan_id"]
  refresh_trigger        = each.value["refresh_trigger"]
  verify_trigger         = each.value["verify_trigger"]
  depends_on             = [oci_disaster_recovery_dr_plan.dr_plan]
  timeouts {
    create = each.value.timeouts_create
    update = each.value.timeouts_update
    delete = each.value.timeouts_delete
  }
}

resource "oci_disaster_recovery_dr_plan" "start_drill" {
  for_each               = { for key, plan in var.plans : key => plan if key == "start_drill" }
  display_name           = each.value["display_name"]
  dr_protection_group_id = each.value.dr_protection_group_id != null ? each.value.dr_protection_group_id : oci_disaster_recovery_dr_protection_group.dr_protection_group.id
  type                   = each.value["type"]
  defined_tags           = each.value["defined_tags"]
  freeform_tags          = each.value["freeform_tags"]
  source_plan_id         = each.value["source_plan_id"]
  refresh_trigger        = each.value["refresh_trigger"]
  verify_trigger         = each.value["verify_trigger"]
  depends_on             = [oci_disaster_recovery_dr_plan.switchover]
  timeouts {
    create = each.value.timeouts_create
    update = each.value.timeouts_update
    delete = each.value.timeouts_delete
  }
}

resource "oci_disaster_recovery_dr_plan" "stop_drill" {
  for_each               = { for key, plan in var.plans : key => plan if key == "stop_drill" }
  display_name           = each.value["display_name"]
  dr_protection_group_id = each.value.dr_protection_group_id != null ? each.value.dr_protection_group_id : oci_disaster_recovery_dr_protection_group.dr_protection_group.id
  type                   = each.value["type"]
  defined_tags           = each.value["defined_tags"]
  freeform_tags          = each.value["freeform_tags"]
  source_plan_id         = each.value["source_plan_id"]
  refresh_trigger        = each.value["refresh_trigger"]
  verify_trigger         = each.value["verify_trigger"]
  depends_on             = [oci_disaster_recovery_dr_plan.start_drill]
  timeouts {
    create = each.value.timeouts_create
    update = each.value.timeouts_update
    delete = each.value.timeouts_delete
  }
}

locals {
  dr_plans = merge(
    oci_disaster_recovery_dr_plan.dr_plan,
    oci_disaster_recovery_dr_plan.switchover,
    oci_disaster_recovery_dr_plan.start_drill,
    oci_disaster_recovery_dr_plan.stop_drill,
  )
}

moved {
  from = oci_disaster_recovery_dr_plan.dr_plan["switchover"]
  to   = oci_disaster_recovery_dr_plan.switchover["switchover"]
}

moved {
  from = oci_disaster_recovery_dr_plan.dr_plan["start_drill"]
  to   = oci_disaster_recovery_dr_plan.start_drill["start_drill"]
}

moved {
  from = oci_disaster_recovery_dr_plan.dr_plan["stop_drill"]
  to   = oci_disaster_recovery_dr_plan.stop_drill["stop_drill"]
}

resource "terraform_data" "operations_ready" {
  count = length(var.executions) > 0 || var.automatic_dr != null ? 1 : 0
  input = var.operations_ready_id
}

resource "oci_disaster_recovery_dr_plan_execution" "dr_plan_execution" {
  for_each   = var.executions
  depends_on = [terraform_data.plan_association, terraform_data.operations_ready]
  execution_options {
    plan_execution_type   = each.value["plan_execution_type"]
    are_prechecks_enabled = each.value["are_prechecks_enabled"]
    are_warnings_ignored  = each.value["are_warnings_ignored"]
  }
  plan_id       = each.value.plan_id != null ? each.value.plan_id : try(local.dr_plans[each.key].id, null)
  defined_tags  = each.value["defined_tags"]
  display_name  = each.value["display_name"]
  freeform_tags = each.value["freeform_tags"]
  timeouts {
    create = each.value["timeouts_create"]
    update = each.value["timeouts_update"]
    delete = each.value["timeouts_delete"]
  }
  lifecycle {
    precondition {
      condition     = each.value.plan_id != null || contains(keys(var.plans), each.key)
      error_message = "Supply an existing plan_id or a plan with the same execution key."
    }
    precondition {
      condition     = each.value.plan_id != null || replace(each.value.plan_execution_type, "_PRECHECK", "") == try(var.plans[each.key].type, null)
      error_message = "The execution type must match the created DR plan type."
    }
  }
}
