# Copyright (c) 2024, 2026, Oracle and/or its affiliates.
# All rights reserved. The Universal Permissive License (UPL), Version 1.0 as shown at http://oss.oracle.com/licenses/upl
# spell-checker: disable

variable "fsdr_enabled" {
  description = "Create FSDR protection groups and standby-region plans."
  type        = bool
  default     = false
}

variable "fsdr_init_destroy" {
  description = "Prepare an existing FSDR deployment for destroy: disassociate groups, disable storage replication and skip configuration management."
  type        = bool
  default     = false
}

variable "fsdr_region_1" {
  description = "Subscribed OCI standby region, distinct from region."
  type        = string
  default     = ""
}

variable "fsdr_plan_types" {
  description = "Standby-region plan types. STOP_DRILL is created while a drill is in progress."
  type        = set(string)
  default     = ["SWITCHOVER", "FAILOVER"]
  validation {
    condition     = alltrue([for plan_type in var.fsdr_plan_types : contains(["SWITCHOVER", "FAILOVER", "START_DRILL", "STOP_DRILL"], plan_type)])
    error_message = "FSDR plan types must be SWITCHOVER, FAILOVER, START_DRILL, or STOP_DRILL."
  }
}

variable "fsdr_plan_refresh_trigger" {
  description = "Increment to refresh generated DR plans after member changes."
  type        = number
  default     = null
}

variable "fsdr_plan_verify_trigger" {
  description = "Increment to verify generated DR plans."
  type        = number
  default     = null
}

variable "fsdr_adb_drill_standby_type" {
  description = "OCI Autonomous Database standby mechanism for DR drills."
  type        = string
  default     = null
}

variable "fsdr_timeouts" {
  description = "Create, update, and delete timeouts for FSDR groups, plans, and Automatic DR configuration."
  type = object({
    create = optional(string, "20m")
    update = optional(string, "20m")
    delete = optional(string, "20m")
  })
  default = {}
}

variable "fsdr_plan_executions" {
  description = "Explicit plan executions keyed by lowercase plan type, such as switchover or start_drill. Apply submits each configured execution."
  type = map(object({
    plan_execution_type   = string
    are_prechecks_enabled = optional(bool, true)
    are_warnings_ignored  = optional(bool, false)
    display_name          = optional(string, null)
    timeouts_create       = optional(string, "20m")
    timeouts_update       = optional(string, "20m")
    timeouts_delete       = optional(string, "20m")
  }))
  default = {}
  validation {
    condition     = length(var.fsdr_plan_executions) <= 1
    error_message = "Submit one FSDR plan execution per apply."
  }
}

variable "fsdr_automatic_dr" {
  description = "Opt-in ADB event-driven DR on the standby protection group. Prepare Resource Principal IAM policies before enabling."
  type = object({
    is_auto_switchover_enabled = optional(bool, false)
    is_auto_failover_enabled   = optional(bool, false)
  })
  default = null
  validation {
    condition     = var.fsdr_automatic_dr == null ? true : var.fsdr_automatic_dr.is_auto_switchover_enabled || var.fsdr_automatic_dr.is_auto_failover_enabled
    error_message = "Automatic DR requires at least one enabled switchover or failover event."
  }
}

variable "fsdr_backup_schedule" {
  description = "RFC 5545 recurrence for OKE backups (one hour by default)."
  type        = string
  default     = "FREQ=HOURLY;INTERVAL=1"
}

variable "fsdr_backup_retention" {
  description = "Number of OKE backups retained."
  type        = number
  default     = 10
}

variable "fsdr_additional_namespaces" {
  description = "Application namespaces to recover alongside OBaaS."
  type        = list(string)
  default     = []
  validation {
    condition     = alltrue([for namespace in var.fsdr_additional_namespaces : !contains(["obaas-system", "kube-system", "brie"], namespace)])
    error_message = "Additional recovery namespaces must contain application workloads; cluster control namespaces are reserved."
  }
}

resource "terraform_data" "fsdr_database_role_guard" {
  input = {
    fsdr_enabled  = var.fsdr_enabled
    database_role = local.db_role
  }

  lifecycle {
    precondition {
      condition     = var.fsdr_enabled || coalesce(local.db_role, "UNKNOWN") == "PRIMARY"
      error_message = "The source Autonomous Database is STANDBY. Switch it back to PRIMARY before disabling FSDR to preserve the promoted database."
    }
  }
}

resource "terraform_data" "fsdr_validation" {
  count = var.fsdr_enabled || var.fsdr_init_destroy || var.fsdr_automatic_dr != null || length(var.fsdr_plan_executions) > 0 ? 1 : 0
  lifecycle {
    precondition {
      condition     = !var.fsdr_init_destroy || var.fsdr_enabled
      error_message = "FSDR destroy preparation requires fsdr_enabled=true."
    }
    precondition {
      condition     = local.fsdr_topology_selected
      error_message = "Enable FSDR and select a non-empty standby region distinct from region."
    }
    precondition {
      condition = anytrue([
        for subscription in data.oci_identity_region_subscriptions.tenancy.region_subscriptions :
        subscription.region_name == var.fsdr_region_1 && subscription.state == "READY"
      ])
      error_message = "Standby region ${var.fsdr_region_1} must have a READY subscription in this tenancy. Subscribe to the region and wait for activation before planning FSDR."
    }
    precondition {
      condition     = var.fsdr_standby_cpu_node_pool_size <= var.k8s_cpu_node_pool_size
      error_message = "Standby prerequisite capacity must fit within the recovery CPU worker count."
    }
    precondition {
      condition     = local.fsdr_include_adb && var.k8s_use_cluster_addons
      error_message = "Full-stack recovery requires Autonomous Database and the OKE-managed database and ingress controllers."
    }
    precondition {
      condition     = (trimspace(var.fsdr_dns_zone_ocid) == "") == (trimspace(var.fsdr_dns_name) == "")
      error_message = "Supply fsdr_dns_zone_ocid and fsdr_dns_name together for an application DNS record, or leave both empty."
    }
    precondition {
      condition     = var.fsdr_adb_drill_standby_type == null || var.fsdr_adb_drill_standby_type == "SNAPSHOT_STANDBY"
      error_message = "Full-stack drills use SNAPSHOT_STANDBY to recover against the protected database endpoint."
    }
    precondition {
      condition     = var.fsdr_automatic_dr == null || local.fsdr_include_adb
      error_message = "Automatic DR requires an Autonomous Database protected by FSDR."
    }
    precondition {
      condition = var.fsdr_automatic_dr == null ? true : (
        (!var.fsdr_automatic_dr.is_auto_switchover_enabled || contains(var.fsdr_plan_types, "SWITCHOVER")) &&
        (!var.fsdr_automatic_dr.is_auto_failover_enabled || contains(var.fsdr_plan_types, "FAILOVER"))
      )
      error_message = "Automatic DR requires the plan type for every enabled event."
    }
    precondition {
      condition     = alltrue([for key in keys(var.fsdr_plan_executions) : contains([for plan_type in var.fsdr_plan_types : lower(plan_type)], key)])
      error_message = "Each execution must reference a configured lowercase FSDR plan type."
    }
  }
}

module "fsdr" {
  for_each                        = local.fsdr_topology_selected ? { managed = true } : {}
  source                          = "./modules/fsdr"
  tenancy_id                      = var.tenancy_ocid
  compartment_id                  = local.compartment_ocid
  adb_compartment_id              = local.adb_compartment_ocid
  label_prefix                    = local.fsdr_label_prefix
  group_label_prefix              = local.fsdr_group_label_prefix
  region_0                        = var.region
  region_1                        = var.fsdr_region_1
  objectstorage_namespace         = data.oci_objectstorage_namespace.objectstorage_namespace.namespace
  clusters                        = local.fsdr_clusters
  external_databases              = local.fsdr_external_databases
  namespaces                      = concat([local.label_prefix], var.fsdr_additional_namespaces)
  volumes                         = module.kubernetes_storage.persistent_storage.volumes
  destination_availability_domain = data.oci_identity_availability_domains.fsdr_region_1[0].availability_domains[0].name
  node_counts                     = { cpu = var.k8s_cpu_node_pool_size, gpu = var.k8s_gpu_node_pool_size }
  standby_node_counts             = { cpu = var.fsdr_standby_cpu_node_pool_size, gpu = 0 }
  backup_schedule                 = var.fsdr_backup_schedule
  backup_retention                = var.fsdr_backup_retention
  adb_drill_standby_type          = coalesce(var.fsdr_adb_drill_standby_type, "SNAPSHOT_STANDBY")
  init_destroy                    = var.fsdr_init_destroy
  plan_types                      = var.fsdr_plan_types
  plan_refresh_trigger            = var.fsdr_plan_refresh_trigger
  plan_verify_trigger             = var.fsdr_plan_verify_trigger
  timeouts                        = var.fsdr_timeouts
  executions                      = var.fsdr_plan_executions
  automatic_dr                    = var.fsdr_automatic_dr
  providers = {
    oci               = oci
    oci.fsdr_region_1 = oci.fsdr_region_1
    oci.home_region   = oci.home_region
  }
}

output "fsdr_protection_group_ids" {
  description = "FSDR protection group OCIDs by region."
  value       = try(module.fsdr["managed"].protection_group_ids, {})
}

output "fsdr_plan_ids" {
  description = "Standby-region DR plan OCIDs keyed by lowercase plan type."
  value       = try(module.fsdr["managed"].plan_ids, {})
}

output "fsdr_plan_execution_ids" {
  description = "Explicit DR execution OCIDs keyed by execution key."
  value       = try(module.fsdr["managed"].plan_execution_ids, {})
}

output "fsdr_automatic_dr_configuration_id" {
  description = "Standby-region Automatic DR configuration OCID."
  value       = try(module.fsdr["managed"].automatic_dr_configuration_id, null)
}
