# Copyright (c) 2024, 2026, Oracle and/or its affiliates.
# All rights reserved. The Universal Permissive License (UPL), Version 1.0 as shown at http://oss.oracle.com/licenses/upl
# spell-checker: disable

locals {
  default_switchover_dr_plan_id = var.automatic_dr == null ? null : (
    var.automatic_dr.default_switchover_dr_plan_id != null ? var.automatic_dr.default_switchover_dr_plan_id : (
      anytrue([for member in var.automatic_dr.members : member.is_auto_switchover_enabled]) ? try(local.dr_plans["switchover"].id, null) : null
    )
  )
  default_failover_dr_plan_id = var.automatic_dr == null ? null : (
    var.automatic_dr.default_failover_dr_plan_id != null ? var.automatic_dr.default_failover_dr_plan_id : (
      anytrue([for member in var.automatic_dr.members : member.is_auto_failover_enabled]) ? try(local.dr_plans["failover"].id, null) : null
    )
  )
}

resource "oci_disaster_recovery_automatic_dr_configuration" "automatic_dr_configuration" {
  count                         = var.automatic_dr == null ? 0 : 1
  display_name                  = var.automatic_dr.display_name
  dr_protection_group_id        = var.automatic_dr.dr_protection_group_id != null ? var.automatic_dr.dr_protection_group_id : oci_disaster_recovery_dr_protection_group.dr_protection_group.id
  default_switchover_dr_plan_id = local.default_switchover_dr_plan_id
  default_failover_dr_plan_id   = local.default_failover_dr_plan_id
  defined_tags                  = var.automatic_dr.defined_tags
  freeform_tags                 = var.automatic_dr.freeform_tags
  dynamic "members" {
    for_each = var.automatic_dr.members
    content {
      member_id                  = members.value.member_id
      member_type                = members.value.member_type
      is_auto_switchover_enabled = members.value.is_auto_switchover_enabled
      is_auto_failover_enabled   = members.value.is_auto_failover_enabled
    }
  }
  depends_on = [terraform_data.plan_association, terraform_data.operations_ready]
  timeouts {
    create = var.timeouts.create
    update = var.timeouts.update
    delete = var.timeouts.delete
  }
  lifecycle {
    precondition {
      condition     = !anytrue([for member in var.automatic_dr.members : member.is_auto_switchover_enabled]) || local.default_switchover_dr_plan_id != null
      error_message = "Automatic switchover requires a default switchover DR plan."
    }
    precondition {
      condition     = !anytrue([for member in var.automatic_dr.members : member.is_auto_failover_enabled]) || local.default_failover_dr_plan_id != null
      error_message = "Automatic failover requires a default failover DR plan."
    }
  }
}
