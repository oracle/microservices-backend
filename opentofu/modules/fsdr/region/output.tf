# Copyright (c) 2024, 2026, Oracle and/or its affiliates.
# All rights reserved. The Universal Permissive License (UPL), Version 1.0 as shown at http://oss.oracle.com/licenses/upl
# spell-checker: disable

output "dr_protection_group" {
  sensitive = true
  value     = oci_disaster_recovery_dr_protection_group.dr_protection_group
}

output "dr_protection_group_id" {
  description = "DR protection group OCID."
  value       = oci_disaster_recovery_dr_protection_group.dr_protection_group.id
}

output "dr_plans" {
  value = local.dr_plans
}

output "dr_plan_executions" {
  value = oci_disaster_recovery_dr_plan_execution.dr_plan_execution
}

output "dr_plan_ids" {
  description = "DR plan OCIDs by plan key."
  value       = { for key, plan in local.dr_plans : key => plan.id }
}

output "dr_plan_execution_ids" {
  description = "Explicit DR plan execution OCIDs by execution key."
  value       = { for key, execution in oci_disaster_recovery_dr_plan_execution.dr_plan_execution : key => execution.id }
}

output "automatic_dr_configuration_id" {
  description = "Automatic DR configuration OCID."
  value       = try(oci_disaster_recovery_automatic_dr_configuration.automatic_dr_configuration[0].id, null)
}

output "automatic_dr_configuration" {
  value = try(oci_disaster_recovery_automatic_dr_configuration.automatic_dr_configuration[0], null)
}
