# Copyright (c) 2024, 2026, Oracle and/or its affiliates.
# All rights reserved. The Universal Permissive License (UPL), Version 1.0 as shown at http://oss.oracle.com/licenses/upl
# spell-checker: disable

variable "k8s_run_cfgmgt" {
  description = "Run Configuration Management Scripts?"
  type        = bool
  default     = true
}

variable "k8s_use_cluster_addons" {
  description = "Install Cluster Add-Ons?"
  type        = bool
  default     = true
}

variable "k8s_use_local_charts" {
  description = "Use local Helm charts from ../helm/infra-charts instead of the remote Helm repository."
  type        = bool
  default     = false
}

//Deploy basic Kafka Cluster
variable "k8s_deploy_kafka" {
  description = "Deploy a cluster using the Strimzi Operator."
  type        = bool
  default     = false
}

variable "k8s_deploy_coherence" {
  description = "Deploy a cluster using the Coherence Operator."
  type        = bool
  default     = false
}

variable "k8s_api_is_public" {
  description = "Make K8s API endpoint accessible from external networks via NSG rules. If false, only ORM deployments can apply Helm automatically."
  type        = bool
  default     = true
}

variable "k8s_api_endpoint_allowed_cidrs" {
  description = "Comma separated string of CIDR blocks from which the API Endpoint can be accessed."
  type        = string
  default     = "0.0.0.0/0"
  validation {
    condition     = can(regex("$|((25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9]).(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9]).(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9]).(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])/(3[0-2]|[1-2]?[0-9])(,?)( ?)){1,}$", var.k8s_api_endpoint_allowed_cidrs))
    error_message = "Must be a comma separated string of valid CIDRs."
  }
}

variable "k8s_cpu_node_pool_size" {
  description = "Number of Workers in the CPU Node Pool."
  type        = number
  default     = 3
}

variable "k8s_node_pool_gpu_deploy" {
  description = "Deploy a GPU Node Pool?"
  type        = bool
  default     = false
}

variable "k8s_gpu_node_pool_size" {
  description = "Number of Workers in the GPU Node Pool."
  type        = number
  default     = 1
}

variable "k8s_byo_ocir_url" {
  description = "BYO Oracle Cluster Image Repository URL"
  type        = string
  default     = ""
}

# Validation: Configuration management requires either public API endpoint or ORM installation
resource "terraform_data" "k8s_cfgmgt_validation" {
  count = 1
  lifecycle {
    precondition {
      condition     = var.fsdr_init_destroy || !var.k8s_run_cfgmgt || var.k8s_api_is_public || var.current_user_ocid != ""
      error_message = "Cannot run configuration management with a private K8s API endpoint from local Terraform. Set k8s_api_is_public=true, k8s_run_cfgmgt=false, or use ORM."
    }
  }
}

module "kubernetes_storage" {
  source                      = "./modules/kubernetes/storage"
  compartment_id              = local.compartment_ocid
  label_prefix                = local.fsdr_label_prefix
  namespace                   = local.label_prefix
  source_availability_domains = local.availability_domains
  deploy_kafka                = var.k8s_deploy_kafka
}

module "kubernetes" {
  for_each           = { managed = true }
  source             = "./modules/kubernetes"
  label_prefix       = local.label_prefix
  tenancy_id         = var.tenancy_ocid
  compartment_id     = local.compartment_ocid
  adb_compartment_id = local.adb_compartment_ocid
  vcn_id             = local.vcn_ocid
  oci_services       = data.oci_core_services.core_services.services.0
  region             = var.region
  lb = {
    id                 = oci_load_balancer_load_balancer.lb.id
    compartment_id     = oci_load_balancer_load_balancer.lb.compartment_id
    ip_address_details = oci_load_balancer_load_balancer.lb.ip_address_details
    shape_details      = oci_load_balancer_load_balancer.lb.shape_details
  }
  db_ocid                     = local.db_ocid
  db_name                     = local.db_name
  db_conn                     = local.db_conn
  api_is_public               = var.k8s_api_is_public
  node_pool_gpu_deploy        = var.k8s_node_pool_gpu_deploy
  gpu_node_pool_size          = var.k8s_gpu_node_pool_size
  kubernetes_version          = local.k8s_version
  cpu_node_pool_size          = var.k8s_cpu_node_pool_size
  api_endpoint_allowed_cidrs  = var.k8s_api_endpoint_allowed_cidrs
  use_cluster_addons          = var.k8s_use_cluster_addons
  use_local_charts            = var.k8s_use_local_charts
  run_cfgmgt                  = var.k8s_run_cfgmgt && !var.fsdr_init_destroy
  apply_cfgmgt                = !var.fsdr_enabled || coalesce(local.db_role, "PRIMARY") == "PRIMARY"
  persistent_storage          = module.kubernetes_storage.persistent_storage
  manage_persistent_volumes   = !try(module.fsdr["managed"].storage_recovered, false)
  recovery_external_databases = local.fsdr_external_databases
  compute_os_ver              = local.compute_os_ver
  compute_cpu_ocpu            = var.compute_cpu_ocpu
  compute_gpu_shape           = var.compute_gpu_shape
  compute_cpu_shape           = var.compute_cpu_shape
  availability_domains        = local.availability_domains
  public_subnet_id            = local.public_subnet_ocid
  private_subnet_id           = local.private_subnet_ocid
  lb_nsg_id                   = oci_core_network_security_group.lb.id
  orm_install                 = var.current_user_ocid != ""
  byo_ocir_url                = var.k8s_byo_ocir_url
  optimizer_version           = "Stable"
  deploy_optimizer            = var.deploy_optimizer
  deploy_kafka                = var.k8s_deploy_kafka
  deploy_coherence            = var.k8s_deploy_coherence
  providers = {
    oci.home_region = oci.home_region
  }
}

output "kubeconfig_cmd" {
  description = "Command to generate kubeconfig file"
  value       = module.kubernetes["managed"].kubeconfig_cmd
}

variable "fsdr_standby_cpu_node_pool_size" {
  description = "Standby CPU workers used for cluster prerequisites before recovery."
  type        = number
  default     = 1
  validation {
    condition     = var.fsdr_standby_cpu_node_pool_size >= 1
    error_message = "Keep at least one standby worker for cluster prerequisites."
  }
}

module "fsdr_kubernetes" {
  for_each           = var.fsdr_enabled ? { standby = true } : {}
  source             = "./modules/kubernetes"
  label_prefix       = local.fsdr_standby_label
  app_namespace      = local.label_prefix
  stage_directory    = format("%s/cfgmgt/stage/fsdr/standby", path.root)
  tenancy_id         = var.tenancy_ocid
  compartment_id     = local.compartment_ocid
  adb_compartment_id = local.adb_compartment_ocid
  vcn_id             = local.fsdr_standby_vcn_id
  oci_services       = data.oci_core_services.fsdr_standby[0].services[0]
  region             = var.fsdr_region_1
  lb = {
    id                 = oci_load_balancer_load_balancer.fsdr_standby[0].id
    compartment_id     = oci_load_balancer_load_balancer.fsdr_standby[0].compartment_id
    ip_address_details = oci_load_balancer_load_balancer.fsdr_standby[0].ip_address_details
    shape_details      = oci_load_balancer_load_balancer.fsdr_standby[0].shape_details
  }
  db_ocid                     = try(oci_database_autonomous_database.dr_adb_standby["fsdr_region_1"].id, "")
  db_name                     = local.db_name
  db_conn                     = local.db_conn
  api_is_public               = var.k8s_api_is_public
  node_pool_gpu_deploy        = var.k8s_node_pool_gpu_deploy
  gpu_node_pool_size          = 0
  kubernetes_version          = local.k8s_version
  cpu_node_pool_size          = var.fsdr_standby_cpu_node_pool_size
  api_endpoint_allowed_cidrs  = var.k8s_api_endpoint_allowed_cidrs
  use_cluster_addons          = true
  use_local_charts            = true
  run_cfgmgt                  = false
  recovery_external_databases = local.fsdr_external_databases
  compute_os_ver              = local.compute_os_ver
  compute_cpu_ocpu            = var.compute_cpu_ocpu
  compute_gpu_shape           = var.compute_gpu_shape
  compute_cpu_shape           = var.compute_cpu_shape
  availability_domains        = [for ad in data.oci_identity_availability_domains.fsdr_region_1[0].availability_domains : ad.name]
  public_subnet_id            = local.fsdr_standby_public_subnet_id
  private_subnet_id           = local.fsdr_standby_private_subnet_id
  lb_nsg_id                   = oci_core_network_security_group.fsdr_standby["lb"].id
  orm_install                 = var.current_user_ocid != ""
  byo_ocir_url                = var.k8s_byo_ocir_url
  deploy_optimizer            = var.deploy_optimizer
  optimizer_version           = "Stable"
  deploy_kafka                = var.k8s_deploy_kafka
  deploy_coherence            = var.k8s_deploy_coherence
  providers = {
    oci             = oci.fsdr_region_1
    oci.home_region = oci.home_region
  }
}

output "fsdr_standby_kubeconfig_cmd" {
  value = try(module.fsdr_kubernetes["standby"].kubeconfig_cmd, null)
}
