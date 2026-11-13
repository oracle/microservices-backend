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

variable "vcn_id" {
  type = string
}

variable "oci_services" {
  description = "OCI Services Network object containing id, name, and cidr_block"
  type = object({
    cidr_block = string
    id         = string
    name       = string
  })
}

variable "public_subnet_id" {
  type = string
}

variable "private_subnet_id" {
  type = string
}

variable "orm_install" {
  type = bool
}

variable "lb" {
  type = object({
    id             = string
    compartment_id = string
    ip_address_details = list(object({
      ip_address = string
    }))
    shape_details = list(object({
      minimum_bandwidth_in_mbps = number
      maximum_bandwidth_in_mbps = number
    }))
  })
}

variable "region" {
  type = string
}

variable "availability_domains" {
  type = list(any)
}

variable "label_prefix" {
  type = string
}

variable "app_namespace" {
  description = "Application namespace shared by the primary and recovery clusters."
  type        = string
  default     = null
}

variable "stage_directory" {
  description = "Directory for this cluster's generated configuration."
  type        = string
  default     = null
}

variable "db_ocid" {
  type = string
}
variable "db_name" {
  type = string
}

variable "db_conn" {
  type = object({
    db_type  = string
    username = string
    password = string
    service  = string
  })
}

variable "kubernetes_version" {
  type = string
}

variable "api_is_public" {
  type = bool
}

variable "node_pool_gpu_deploy" {
  type = bool
}

variable "cpu_node_pool_size" {
  type = number
}

variable "gpu_node_pool_size" {
  type = number
}

variable "compute_gpu_shape" {
  type = string
}

variable "compute_os_ver" {
  type = string
}

variable "compute_cpu_shape" {
  type = string
}

variable "compute_cpu_ocpu" {
  type = number
}

variable "lb_nsg_id" {
  type = string
}

variable "api_endpoint_allowed_cidrs" {
  type    = string
  default = ""
}

variable "run_cfgmgt" {
  type = bool
}

variable "apply_cfgmgt" {
  description = "Apply the staged application configuration when configuration management runs."
  type        = bool
  default     = true
}

variable "persistent_storage" {
  description = "Preallocated OCI volumes and the chart settings for their reserved PVs."
  type = object({
    chart = map(object({ replicas = number, size_in_gbs = number, storage_class = string }))
    volumes = map(object({
      id                  = string
      claim_name          = string
      namespace           = string
      size_in_gbs         = number
      availability_domain = string
    }))
  })
  default = null
}

variable "manage_persistent_volumes" {
  description = "Render bootstrap PV definitions while the original storage is active."
  type        = bool
  default     = true
}

variable "recovery_external_databases" {
  description = "Database OCIDs and compartments accessible to the database operator during recovery."
  type        = map(string)
  default     = {}
}
variable "use_cluster_addons" {
  type    = bool
  default = true
}

variable "use_local_charts" {
  type    = bool
  default = false
}

variable "byo_ocir_url" {
  type = string
}

variable "optimizer_version" {
  type = string
}

// Deployments
variable "deploy_optimizer" {
  type    = bool
  default = false
}

// Deploy Kafka cluster
variable "deploy_kafka" {
  type    = bool
  default = false
}

variable "deploy_coherence" {
  description = "Deploy a cluster using the Coherence Operator."
  type        = bool
  default     = false
}
