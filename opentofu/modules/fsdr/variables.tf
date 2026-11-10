# Copyright (c) 2024, 2026, Oracle and/or its affiliates.
# All rights reserved. The Universal Permissive License (UPL), Version 1.0 as shown at http://oss.oracle.com/licenses/upl
# spell-checker: disable

variable "tenancy_id" {
  type = string
}

variable "compartment_id" {
  type = string
}

variable "adb_compartment_id" {
  description = "Compartment for managed Autonomous Databases; defaults to compartment_id."
  type        = string
  default     = null
}

variable "label_prefix" {
  type = string
}

variable "group_label_prefix" {
  description = "Protection group prefix available during planning; defaults to label_prefix."
  type        = string
  default     = null
}

variable "region_0" {
  description = "Initial primary region."
  type        = string
}

variable "region_1" {
  description = "Initial standby region."
  type        = string
}

variable "objectstorage_namespace" {
  type = string
}

variable "clusters" {
  description = "Regional cluster, database and network configuration."
  type = map(object({
    cluster_id             = string
    workers_group          = string
    database_id            = string
    node_pools             = map(string)
    lb_id                  = string
    configuration_ready_id = string
  }))
}

variable "destination_availability_domain" { type = string }
variable "volumes" {
  type = map(object({ id = string, availability_domain = string }))
}

variable "adb_drill_standby_type" {
  type    = string
  default = "SNAPSHOT_STANDBY"
}

variable "external_databases" {
  description = "Existing database OCIDs mapped to their owning compartments."
  type        = map(string)
  default     = {}
}

variable "namespaces" {
  description = "Application namespaces protected by OKE backups."
  type        = list(string)
}

variable "node_counts" {
  type = object({ cpu = number, gpu = number })
}

variable "standby_node_counts" {
  type = object({ cpu = number, gpu = number })
}

variable "backup_schedule" {
  type    = string
  default = "FREQ=HOURLY;INTERVAL=1"
}

variable "backup_retention" {
  type    = number
  default = 10
  validation {
    condition     = var.backup_retention >= 1 && var.backup_retention <= 20 && var.backup_retention == floor(var.backup_retention)
    error_message = "FSDR backup retention must be a whole number from 1 to 20."
  }
}

variable "init_destroy" {
  type    = bool
  default = false
}
variable "plan_types" {
  type    = set(string)
  default = ["SWITCHOVER", "FAILOVER"]
  validation {
    condition     = alltrue([for plan_type in var.plan_types : contains(["SWITCHOVER", "FAILOVER", "START_DRILL", "STOP_DRILL"], plan_type)])
    error_message = "DR plan types must be SWITCHOVER, FAILOVER, START_DRILL, or STOP_DRILL."
  }
}

variable "plan_refresh_trigger" {
  type    = number
  default = null
}

variable "plan_verify_trigger" {
  type    = number
  default = null
}

variable "timeouts" {
  type = object({
    create = optional(string, "20m")
    update = optional(string, "20m")
    delete = optional(string, "20m")
  })
  default = {}
}

variable "executions" {
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
}

variable "automatic_dr" {
  type = object({
    is_auto_switchover_enabled = optional(bool, false)
    is_auto_failover_enabled   = optional(bool, false)
  })
  default = null
}
