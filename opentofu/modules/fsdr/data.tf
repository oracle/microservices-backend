# Copyright (c) 2024, 2026, Oracle and/or its affiliates.
# All rights reserved. The Universal Permissive License (UPL), Version 1.0 as shown at http://oss.oracle.com/licenses/upl
# spell-checker: disable

data "oci_disaster_recovery_dr_protection_groups" "region_0" {
  compartment_id = var.compartment_id
  display_name   = format("%s-pg-%s", local.group_label_prefix, var.region_0)
}

data "oci_disaster_recovery_dr_protection_groups" "region_1" {
  compartment_id = var.compartment_id
  display_name   = format("%s-pg-%s", local.group_label_prefix, var.region_1)
  provider       = oci.fsdr_region_1
}

# The list data source omits member details, so fetch each existing group by ID.
data "oci_disaster_recovery_dr_protection_group" "region_0" {
  count                  = local.group_summaries[var.region_0] == null ? 0 : 1
  dr_protection_group_id = local.group_summaries[var.region_0].id
}

data "oci_disaster_recovery_dr_protection_group" "region_1" {
  count                  = local.group_summaries[var.region_1] == null ? 0 : 1
  dr_protection_group_id = local.group_summaries[var.region_1].id
  provider               = oci.fsdr_region_1
}

data "oci_disaster_recovery_dr_plan_executions" "region_0" {
  count                  = local.groups[var.region_0] == null ? 0 : 1
  dr_protection_group_id = local.groups[var.region_0].id
}

data "oci_disaster_recovery_dr_plan_executions" "region_1" {
  count                  = local.groups[var.region_1] == null ? 0 : 1
  dr_protection_group_id = local.groups[var.region_1].id
  provider               = oci.fsdr_region_1
}

data "oci_disaster_recovery_dr_protection_group" "prepared_region_0" {
  count                  = var.init_destroy ? 1 : 0
  dr_protection_group_id = module.fsdr_region_0.dr_protection_group_id
  depends_on             = [terraform_data.disassociation]
}

data "oci_disaster_recovery_dr_protection_group" "prepared_region_1" {
  count                  = var.init_destroy ? 1 : 0
  dr_protection_group_id = module.fsdr_region_1.dr_protection_group_id
  provider               = oci.fsdr_region_1
  depends_on             = [terraform_data.disassociation]
}
