# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at https://oss.oracle.com/licenses/upl

mock_provider "oci" {
  mock_data "oci_disaster_recovery_dr_protection_groups" {
    defaults = { dr_protection_group_collection = [{ items = [] }] }
  }
  mock_resource "oci_objectstorage_bucket" {
    defaults = { defined_tags = { "Oracle-Tags.CreatedBy" = "test-user" } }
  }
  mock_resource "oci_load_balancer_load_balancer" {
    defaults = { ip_address_details = [{ ip_address = "192.0.2.10", is_public = true, reserved_ip = [] }] }
  }
  mock_data "oci_identity_region_subscriptions" {
    defaults = { region_subscriptions = [
      { region_name = "uk-cardiff-1", region_key = "CWL", is_home_region = false, state = "READY", tenancy_id = "test-tenancy" },
      { region_name = "uk-london-1", region_key = "LHR", is_home_region = true, state = "READY", tenancy_id = "test-tenancy" }
    ] }
  }
  mock_data "oci_identity_availability_domains" {
    defaults = { availability_domains = [{ name = "TEST:UK-LONDON-1-AD-1", id = "test-ad", compartment_id = "test-tenancy" }] }
  }
  mock_data "oci_core_services" {
    defaults = { services = [{ id = "services", cidr_block = "all-lhr-services-in-oracle-services-network", name = "All LHR Services In Oracle Services Network", description = "test-services" }] }
  }
  mock_data "oci_objectstorage_namespace" {
    defaults = { namespace = "test-namespace" }
  }
}
mock_provider "oci" {
  alias = "fsdr_region_1"
  mock_data "oci_disaster_recovery_dr_protection_groups" {
    defaults = { dr_protection_group_collection = [{ items = [] }] }
  }
  mock_resource "oci_load_balancer_load_balancer" {
    defaults = { ip_address_details = [{ ip_address = "192.0.2.20", is_public = true, reserved_ip = [] }] }
  }
  mock_data "oci_core_services" {
    defaults = { services = [{ id = "standby-services", cidr_block = "all-cwl-services-in-oracle-services-network", name = "All CWL Services In Oracle Services Network", description = "standby-services" }] }
  }
  mock_data "oci_identity_availability_domains" {
    defaults = { availability_domains = [{ name = "TEST:UK-CARDIFF-1-AD-1", id = "standby-ad", compartment_id = "test-tenancy" }] }
  }
}
mock_provider "oci" { alias = "home_region" }
# The real provider keeps random_pet.id unknown until apply.
provider "random" {}
mock_provider "tls" {}
mock_provider "local" {}
mock_provider "null" {}
mock_provider "cloudinit" {}

override_module {
  target  = module.network
  outputs = { vcn_ocid = "test-vcn", public_subnet_ocid = "public-subnet", private_subnet_ocid = "private-subnet", private_subnet_cidr_block = "10.42.1.0/24" }
}
override_module {
  target = module.kubernetes
  outputs = {
    kubeconfig_cmd             = "test-kubeconfig"
    configuration_ready_id     = "primary-ready"
    cluster_id                 = "primary-cluster"
    workers_dynamic_group_name = "primary-workers"
    orm_private_endpoint_ip    = ""
    repository_host            = "lhr.ocir.io"
    node_pool_ids              = { cpu = "primary-cpu-pool" }
    configuration_files        = { kubeconfig = "primary-kubeconfig", manifest = "primary-manifest", prereqs = "primary-prereqs", app = "primary-app" }
  }
}
override_module {
  target  = module.fsdr_network
  outputs = { vcn_ocid = "standby-vcn", public_subnet_ocid = "standby-public-subnet", private_subnet_ocid = "standby-private-subnet", private_subnet_cidr_block = "10.43.1.0/24" }
}
override_module {
  target = module.fsdr_kubernetes
  outputs = {
    kubeconfig_cmd             = "standby-kubeconfig"
    configuration_ready_id     = "standby-ready"
    cluster_id                 = "standby-cluster"
    workers_dynamic_group_name = "standby-workers"
    orm_private_endpoint_ip    = ""
    repository_host            = "cwl.ocir.io"
    node_pool_ids              = { cpu = "standby-cpu-pool" }
    configuration_files        = { kubeconfig = "standby-kubeconfig", manifest = "standby-manifest", prereqs = "standby-prereqs", app = "standby-app" }
  }
}

variables {
  tenancy_ocid         = "test-tenancy"
  compartment_ocid     = "test-compartment"
  region               = "uk-london-1"
  label_prefix         = ""
  fsdr_enabled         = true
  fsdr_region_1        = "uk-cardiff-1"
  k8s_use_local_charts = true
  k8s_run_cfgmgt       = false
}

run "explicit_label" {
  command = plan
  assert {
    condition     = local.home_region == "uk-london-1"
    error_message = "Home-region discovery must select the home subscription regardless of list order."
  }
  variables {
    label_prefix = "MixedCaseLongLabel"
  }
  assert {
    condition     = module.fsdr["managed"].regions.region_0.dr_protection_group.display_name == "mixedcaselon-fsdr-pg-uk-london-1"
    error_message = "Explicit labels must retain the established protection-group naming convention."
  }
}

run "bootstrap_generated_label" {
  command = plan
  assert {
    condition     = toset(keys(output.fsdr_plan_ids)) == toset(["switchover", "failover"]) && length(module.fsdr["managed"].regions.region_0.dr_plans) == 0
    error_message = "Generated labels must permit empty-state planning with plans on the initial standby."
  }
}

run "persist_generated_label" {
  command = apply
  plan_options {
    target = [random_pet.label]
  }
}

run "reuse_generated_label" {
  command = plan
  assert {
    condition     = length(random_pet.label.id) > 0 && toset(keys(output.fsdr_plan_ids)) == toset(["switchover", "failover"])
    error_message = "Later plans must retain the generated label and standby plan keys."
  }
}
