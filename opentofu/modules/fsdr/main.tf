# Copyright (c) 2024, 2026, Oracle and/or its affiliates.
# All rights reserved. The Universal Permissive License (UPL), Version 1.0 as shown at http://oss.oracle.com/licenses/upl
# spell-checker: disable

module "storage" {
  source         = "./storage"
  compartment_id = var.compartment_id
  label_prefix   = var.label_prefix
  volumes        = var.volumes
  destination_ad = var.destination_availability_domain
  init_destroy   = var.init_destroy
  providers      = { oci = oci }
  depends_on     = [terraform_data.idle]
}

resource "terraform_data" "application_ready" {
  input = { for region, cluster in var.clusters : region => cluster.configuration_ready_id }
}

resource "terraform_data" "init_destroy_validation" {
  count = var.init_destroy ? 1 : 0
  input = { for region, group in local.group_summaries : region => try(group.id, null) }

  lifecycle {
    precondition {
      condition     = alltrue([for region in [var.region_0, var.region_1] : local.group_summaries[region] != null])
      error_message = "FSDR destroy preparation requires an existing protection group in both regions.  Check that fsdr_init_destroy is not `true`."
    }
  }
}

resource "terraform_data" "disassociation" {
  count = var.init_destroy ? 1 : 0
  input = {
    groups  = local.protection_group_ids
    timeout = var.timeouts.update
  }
  triggers_replace = [local.protection_group_ids, local.associations, filesha256(format("%s/prepare.py", path.module))]
  depends_on       = [terraform_data.init_destroy_validation, terraform_data.idle, module.storage, module.fsdr_region_0, module.fsdr_region_1]

  provisioner "local-exec" {
    command = join(" ", [for argument in [
      "python3", "${path.module}/prepare.py",
      "--group", var.region_0, self.input.groups[var.region_0],
      "--group", var.region_1, self.input.groups[var.region_1],
      "--timeout", self.input.timeout
    ] : format("'%s'", replace(argument, "'", "'\"'\"'"))])
  }
}

module "fsdr_region_1" {
  source              = "./region"
  compartment_id      = var.compartment_id
  display_name        = format("%s-pg-%s", local.group_label_prefix, var.region_1)
  members             = [for member in local.members[var.region_1] : member if !var.init_destroy]
  association         = local.associations[var.region_1]
  timeouts            = var.timeouts
  plan_association_id = module.fsdr_region_0.dr_protection_group_id
  log_location = {
    bucket    = oci_objectstorage_bucket.fsdr_logs_region_1.name
    namespace = var.objectstorage_namespace
  }
  plans        = local.plans[var.region_1]
  executions   = !var.init_destroy && local.roles[var.region_1] == "STANDBY" ? var.executions : {}
  automatic_dr = local.automatic_dr[var.region_1]
  providers    = { oci = oci.fsdr_region_1 }
  depends_on   = [oci_identity_policy.fsdr, oci_identity_policy.fsdr_container, terraform_data.idle, terraform_data.application_ready]
}

module "fsdr_region_0" {
  source         = "./region"
  compartment_id = var.compartment_id
  display_name   = format("%s-pg-%s", local.group_label_prefix, var.region_0)
  members        = [for member in local.members[var.region_0] : member if !var.init_destroy]
  association = var.init_destroy ? null : {
    role        = coalesce(try(local.associations[var.region_0].role, null), "PRIMARY")
    peer_region = coalesce(try(local.associations[var.region_0].peer_region, null), var.region_1)
    peer_id     = coalesce(try(local.associations[var.region_0].peer_id, null), module.fsdr_region_1.dr_protection_group_id)
  }
  log_location = {
    bucket    = oci_objectstorage_bucket.fsdr_logs_region_0.name
    namespace = var.objectstorage_namespace
  }
  timeouts         = var.timeouts
  plans            = local.plans[var.region_0]
  members_ready_id = module.fsdr_region_1.dr_protection_group_id
  executions       = !var.init_destroy && local.roles[var.region_0] == "STANDBY" ? var.executions : {}
  automatic_dr     = local.automatic_dr[var.region_0]
  depends_on       = [oci_identity_policy.fsdr, oci_identity_policy.fsdr_container, terraform_data.idle, terraform_data.application_ready]
}

resource "terraform_data" "idle" {
  lifecycle {
    precondition {
      condition = alltrue(flatten([
        for discovery in concat(data.oci_disaster_recovery_dr_plan_executions.region_0, data.oci_disaster_recovery_dr_plan_executions.region_1) : [
          for execution in discovery.dr_plan_execution_collection[0].items :
          !contains(["ACCEPTED", "IN_PROGRESS", "WAITING", "CANCELING", "PAUSING", "PAUSED", "RESUMING"], execution.state)
        ]
      ]))
      error_message = "Wait for the active FSDR execution before changing recovery configuration."
    }
  }
}
