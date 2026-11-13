# Copyright (c) 2024, 2026, Oracle and/or its affiliates.
# All rights reserved. The Universal Permissive License (UPL), Version 1.0 as shown at http://oss.oracle.com/licenses/upl
# spell-checker: disable

mock_provider "oci" {
  mock_resource "oci_objectstorage_bucket" {
    defaults = { defined_tags = { "Oracle-Tags.CreatedBy" = "test-user" } }
  }
  mock_resource "oci_database_autonomous_database" {
    defaults = { role = "PRIMARY" }
  }
  mock_data "oci_disaster_recovery_dr_protection_groups" {
    defaults = { dr_protection_group_collection = [{ items = [] }] }
  }
  mock_resource "oci_load_balancer_load_balancer" {
    defaults = { ip_address_details = [{ ip_address = "192.0.2.10", is_public = true, reserved_ip = [] }] }
  }
  mock_data "oci_identity_region_subscriptions" {
    defaults = { region_subscriptions = [
      { region_name = "uk-london-1", region_key = "LHR", is_home_region = true, state = "READY", tenancy_id = "test-tenancy" },
      { region_name = "uk-cardiff-1", region_key = "CWL", is_home_region = false, state = "READY", tenancy_id = "test-tenancy" }
    ] }
  }
  mock_data "oci_identity_availability_domains" {
    defaults = { availability_domains = [{ name = "TEST:UK-LONDON-1-AD-1", id = "test-ad", compartment_id = "test-tenancy" }] }
  }
  mock_data "oci_core_services" {
    defaults = { services = [{ id = "services", cidr_block = "all-lhr-services-in-oracle-services-network", name = "All LHR Services In Oracle Services Network", description = "test-services" }] }
  }
  mock_data "oci_database_autonomous_database" {
    defaults = { id = "byo-adb", db_name = "BYODB", compartment_id = "database-compartment", role = "PRIMARY" }
  }
  mock_data "oci_core_subnet" {
    defaults = { cidr_block = "10.80.0.0/24" }
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
    defaults = { availability_domains = [{ name = "TEST:uk-london-1-AD-1", id = "standby-ad", compartment_id = "test-tenancy" }] }
  }
  mock_data "oci_core_subnet" { defaults = { cidr_block = "10.43.1.0/24" } }
}
mock_provider "oci" { alias = "home_region" }
mock_provider "random" {}
mock_provider "tls" {}
mock_provider "local" {}
mock_provider "null" {}
mock_provider "cloudinit" {}

override_module {
  target = module.network
  outputs = {
    vcn_ocid                  = "test-vcn"
    public_subnet_ocid        = "public-subnet"
    private_subnet_ocid       = "private-subnet"
    private_subnet_cidr_block = "10.42.1.0/24"
  }
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
  target = module.fsdr_network
  outputs = {
    vcn_ocid                  = "standby-vcn"
    public_subnet_ocid        = "standby-public-subnet"
    private_subnet_ocid       = "standby-private-subnet"
    private_subnet_cidr_block = "10.43.1.0/24"
  }
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
  label_prefix         = "iactest"
  k8s_use_local_charts = true
  k8s_run_cfgmgt       = false
}

run "adb_compartment_default" {
  command = plan
  variables {
    fsdr_enabled  = true
    fsdr_region_1 = "uk-cardiff-1"
  }
  assert {
    condition     = oci_database_autonomous_database.default_adb["managed"].compartment_id == "test-compartment" && oci_database_autonomous_database.dr_adb_standby["fsdr_region_1"].compartment_id == "test-compartment"
    error_message = "Both managed databases must default to the deployment compartment."
  }
}

run "adb_compartment_override" {
  command = plan
  variables {
    adb_compartment_ocid = "database-compartment"
    fsdr_enabled         = true
    fsdr_region_1        = "uk-cardiff-1"
  }
  assert {
    condition     = oci_database_autonomous_database.default_adb["managed"].compartment_id == "database-compartment" && oci_database_autonomous_database.dr_adb_standby["fsdr_region_1"].compartment_id == "database-compartment" && oci_load_balancer_load_balancer.lb.compartment_id == "test-compartment"
    error_message = "The ADB compartment must apply to both databases while other infrastructure stays in the deployment compartment."
  }
  assert {
    condition     = contains(module.fsdr["managed"].iam_policy_statements.groups, "Allow dynamic-group iactest-fsdr-groups to manage autonomous-database-family in compartment id database-compartment") && contains(module.fsdr["managed"].iam_policy_statements.groups, "Allow dynamic-group iactest-fsdr-groups to manage cluster-family in compartment id test-compartment")
    error_message = "FSDR database permissions must follow the ADB compartment while cluster permissions retain their scope."
  }
}

run "adb_compartment_without_fsdr" {
  command = plan
  variables {
    adb_compartment_ocid = "database-compartment"
  }
  assert {
    condition     = oci_database_autonomous_database.default_adb["managed"].compartment_id == "database-compartment" && length(oci_database_autonomous_database.dr_adb_standby) == 0
    error_message = "The ADB compartment must also work without FSDR."
  }
}

run "adb_compartment_tenancy_fallback" {
  command = plan
  variables {
    compartment_ocid     = ""
    adb_compartment_ocid = " "
  }
  assert {
    condition     = oci_database_autonomous_database.default_adb["managed"].compartment_id == "test-tenancy"
    error_message = "An empty ADB compartment must follow the deployment's tenancy fallback."
  }
}

run "adb_compartment_with_existing_primary" {
  command = plan
  variables {
    adb_compartment_ocid = "standby-database-compartment"
    fsdr_enabled         = true
    fsdr_region_1        = "uk-cardiff-1"
    byo_db_type          = "ADB-S"
    byo_adb_ocid         = "byo-adb"
    byo_db_password      = "test-password"
  }
  assert {
    condition     = length(oci_database_autonomous_database.default_adb) == 0 && local.fsdr_external_databases == tomap({ "byo-adb" = "database-compartment" }) && oci_database_autonomous_database.dr_adb_standby["fsdr_region_1"].compartment_id == "standby-database-compartment"
    error_message = "An existing primary keeps its actual compartment while the managed standby uses the selected compartment."
  }
}

run "disabled_by_default" {
  command = plan
  assert {
    condition     = length(output.fsdr_plan_ids) == 0 && length(output.fsdr_protection_group_ids) == 0 && length(output.fsdr_plan_execution_ids) == 0 && output.fsdr_automatic_dr_configuration_id == null
    error_message = "FSDR, execution, and Automatic DR must remain opt-in."
  }
}

run "existing_plan_keys" {
  command = plan
  variables {
    fsdr_enabled  = true
    fsdr_region_1 = "uk-cardiff-1"
  }
  assert {
    condition     = length(oci_dns_rrset.fsdr_application) == 0 && output.fsdr_application_url == null && output.fsdr_regional_application_urls == { "uk-london-1" = "http://192.0.2.10", "uk-cardiff-1" = "http://192.0.2.20" }
    error_message = "Selecting a standby region must enable FSDR with regional access URLs and optional DNS."
  }
  assert {
    condition     = toset(keys(output.fsdr_plan_ids)) == toset(["switchover", "failover"]) && module.fsdr["managed"].regions.region_1.automatic_dr_configuration == null && length(output.fsdr_plan_execution_ids) == 0
    error_message = "Default FSDR must preserve its existing plan keys without submitting executions."
  }
  assert {
    condition     = length(module.fsdr["managed"].regions.region_0.dr_plans) == 0 && length(module.fsdr["managed"].regions.region_0.dr_plan_executions) == 0 && module.fsdr["managed"].regions.region_0.automatic_dr_configuration == null && one(module.fsdr["managed"].regions.region_0.dr_protection_group.association).role == "PRIMARY"
    error_message = "The primary instance must own the association while standby operations stay in region 1."
  }
}

run "drill_plans" {
  command = plan
  variables {
    fsdr_enabled              = true
    fsdr_region_1             = "uk-cardiff-1"
    fsdr_plan_types           = ["SWITCHOVER", "FAILOVER", "START_DRILL", "STOP_DRILL"]
    fsdr_plan_refresh_trigger = 2
    fsdr_plan_verify_trigger  = 3
  }
  assert {
    condition     = contains(keys(output.fsdr_plan_ids), "start_drill") && !contains(keys(output.fsdr_plan_ids), "stop_drill") && module.fsdr["managed"].regions.region_1.dr_plans["start_drill"].refresh_trigger == 2 && module.fsdr["managed"].regions.region_1.dr_plans["start_drill"].verify_trigger == 3
    error_message = "The start-drill plan and root refresh/verify controls must reach the child module before a drill starts."
  }
}

run "automatic_failover" {
  command = plan
  variables {
    fsdr_enabled      = true
    fsdr_region_1     = "uk-cardiff-1"
    fsdr_automatic_dr = { is_auto_failover_enabled = true }
  }
  assert {
    condition     = module.fsdr["managed"].regions.region_1.automatic_dr_configuration != null && length(output.fsdr_plan_execution_ids) == 0
    error_message = "Automatic DR must configure the standby group without submitting an explicit execution."
  }
}

run "explicit_precheck" {
  command = plan
  variables {
    fsdr_enabled         = true
    fsdr_region_1        = "uk-cardiff-1"
    fsdr_plan_executions = { switchover = { plan_execution_type = "SWITCHOVER_PRECHECK" } }
  }
  assert {
    condition     = one(module.fsdr["managed"].regions.region_1.dr_plan_executions["switchover"].execution_options).are_prechecks_enabled
    error_message = "Explicit root execution inputs must reach the plan module."
  }
}

run "same_region" {
  command = plan
  variables {
    fsdr_enabled  = true
    fsdr_region_1 = "uk-london-1"
  }
  expect_failures = [terraform_data.fsdr_validation]
}

run "automatic_requires_adb" {
  command = plan
  variables {
    fsdr_enabled      = true
    fsdr_region_1     = "uk-cardiff-1"
    byo_db_type       = "OTHER"
    byo_db_password   = "test-password"
    fsdr_automatic_dr = { is_auto_failover_enabled = true }
  }
  expect_failures = [terraform_data.fsdr_validation]
}

run "unknown_execution_key" {
  command = plan
  variables {
    fsdr_enabled         = true
    fsdr_region_1        = "uk-cardiff-1"
    fsdr_plan_executions = { start_drill = { plan_execution_type = "START_DRILL" } }
  }
  expect_failures = [terraform_data.fsdr_validation]
}

run "managed_infrastructure" {
  command = plan
  assert {
    condition     = length(module.network) == 1 && length(oci_database_autonomous_database.default_adb) == 1 && length(oci_core_instance.mktpl_instance) == 0
    error_message = "Defaults must create managed networking and ADB with Marketplace opt-in."
  }
  assert {
    condition     = oci_database_autonomous_database.default_adb["managed"].compute_model == "ECPU" && oci_database_autonomous_database.default_adb["managed"].compute_count == 2 && oci_database_autonomous_database.default_adb["managed"].is_mtls_connection_required
    error_message = "Default ADB sizing and mTLS must be retained."
  }
  assert {
    condition     = oci_load_balancer_load_balancer.lb.shape == "flexible" && !oci_load_balancer_load_balancer.lb.is_private && one(oci_load_balancer_load_balancer.lb.subnet_ids) == "public-subnet"
    error_message = "Application access must use a public flexible load balancer on the public subnet."
  }
}

run "private_adb" {
  command = plan
  variables {
    adb_networking = "PRIVATE_ENDPOINT_ACCESS"
  }
  assert {
    condition     = oci_database_autonomous_database.default_adb["managed"].subnet_id == "private-subnet" && oci_database_autonomous_database.default_adb["managed"].whitelisted_ips == null && length(oci_core_network_security_group.adb) == 1
    error_message = "Private ADB must use the private subnet and its database security group."
  }
  assert {
    condition     = one(one(oci_core_network_security_group_security_rule.adb_ingress[0].tcp_options).destination_port_range).min == 1521 && one(one(oci_core_network_security_group_security_rule.adb_ingress[0].tcp_options).destination_port_range).max == 1522
    error_message = "ADB access must allow only the required listener port range."
  }
}

run "secure_adb_and_license" {
  command = plan
  variables {
    adb_whitelist_cidrs = "192.0.2.0/24, 198.51.100.0/24"
    adb_license_model   = "BRING_YOUR_OWN_LICENSE"
    adb_edition         = "STANDARD_EDITION"
  }
  assert {
    condition     = toset(oci_database_autonomous_database.default_adb["managed"].whitelisted_ips) == toset(["192.0.2.0/24", "198.51.100.0/24", "test-vcn"]) && length(oci_core_network_security_group.adb) == 0
    error_message = "Secure ADB access must combine operator CIDRs with VCN access."
  }
  assert {
    condition     = oci_database_autonomous_database.default_adb["managed"].database_edition == "STANDARD_EDITION"
    error_message = "BYOL database edition must reach ADB configuration."
  }
}

run "byo_autonomous_database" {
  command = plan
  variables {
    byo_db_type     = "ADB-S"
    byo_adb_ocid    = "byo-adb"
    byo_db_password = "test-password"
  }
  assert {
    condition     = length(oci_database_autonomous_database.default_adb) == 0 && local.db_ocid == "byo-adb" && local.db_conn.service == "BYODB_TP" && local.db_conn.username == "ADMIN"
    error_message = "BYO ADB must supply discovered identity and connection details without creating a database."
  }
  assert {
    condition     = local.db_conn.password == "test-password"
    error_message = "BYO credentials must reach database connection configuration."
  }
}

run "byo_other_database" {
  command = plan
  variables {
    byo_db_type     = "OTHER"
    byo_db_password = "test-password"
    byo_odb_host    = "db.example.com"
    byo_odb_port    = 1522
    byo_odb_service = "PDB.example.com"
  }
  assert {
    condition     = length(oci_database_autonomous_database.default_adb) == 0 && length(data.oci_database_autonomous_database.byo_adb) == 0 && local.db_conn.db_type == "OTHER" && local.db_conn.username == "SYSTEM" && local.db_conn.service == "db.example.com:1522/PDB.example.com"
    error_message = "External database mode must construct the operator-provided connect string without creating ADB."
  }
}

run "byo_network" {
  command = plan
  variables {
    byo_vcn_ocid            = "byo-vcn"
    byo_public_subnet_ocid  = "byo-public"
    byo_private_subnet_ocid = "byo-private"
    adb_networking          = "PRIVATE_ENDPOINT_ACCESS"
  }
  assert {
    condition     = length(module.network) == 0 && local.vcn_ocid == "byo-vcn" && one(oci_load_balancer_load_balancer.lb.subnet_ids) == "byo-public" && oci_database_autonomous_database.default_adb["managed"].subnet_id == "byo-private"
    error_message = "BYO networking must route load balancer and private ADB to the supplied subnets."
  }
  assert {
    condition     = oci_core_network_security_group_security_rule.lb_egress.destination == "10.80.0.0/24" && length(oci_core_network_security_group.adb) == 0
    error_message = "BYO private subnet discovery must supply load-balancer egress without creating a managed ADB NSG."
  }
}

run "load_balancer_access" {
  command = plan
  variables {
    client_allowed_cidrs = "192.0.2.0/24, 198.51.100.0/24"
    server_allowed_cidrs = "203.0.113.0/24"
    lb_min_shape         = 20
    lb_max_shape         = 100
  }
  assert {
    condition     = toset(keys(oci_core_network_security_group_security_rule.lb_http_ingress)) == toset(["192.0.2.0/24", "198.51.100.0/24"]) && toset(keys(oci_core_network_security_group_security_rule.lb_https_ingress)) == toset(["203.0.113.0/24"])
    error_message = "Client and server access must retain separate normalized CIDR sets."
  }
  assert {
    condition     = one(one(oci_core_network_security_group_security_rule.lb_http_ingress["192.0.2.0/24"].tcp_options).destination_port_range).min == 80 && one(one(oci_core_network_security_group_security_rule.lb_https_ingress["203.0.113.0/24"].tcp_options).destination_port_range).min == 443
    error_message = "Load-balancer access must use the HTTP and HTTPS listener ports."
  }
  assert {
    condition     = one(oci_load_balancer_load_balancer.lb.shape_details).minimum_bandwidth_in_mbps == 20 && one(oci_load_balancer_load_balancer.lb.shape_details).maximum_bandwidth_in_mbps == 100
    error_message = "Configured load-balancer bandwidth bounds must be preserved."
  }
}

run "private_cfgmgt_requires_access" {
  command = plan
  variables {
    k8s_api_is_public = false
    k8s_run_cfgmgt    = true
  }
  expect_failures = [terraform_data.k8s_cfgmgt_validation]
}

run "orm_private_cfgmgt" {
  command = plan
  variables {
    k8s_api_is_public = false
    k8s_run_cfgmgt    = true
    current_user_ocid = "orm-user"
  }
  assert {
    condition     = local.user_ocid == "orm-user"
    error_message = "ORM must use the current user when explicit API user identity is absent."
  }
}

run "marketplace_subscription" {
  command = plan
  variables {
    mktpl_use_image   = true
    compute_cpu_shape = "VM.Standard.A1.Flex"
  }
  assert {
    condition     = length(oci_core_app_catalog_subscription.mktpl_image_subscription) == 1 && oci_core_instance.mktpl_instance["marketplace"].state == "STOPPED" && !one(oci_core_instance.mktpl_instance["marketplace"].create_vnic_details).assign_public_ip
    error_message = "Marketplace opt-in must create a stopped private instance and its subscription."
  }
  assert {
    condition     = oci_core_instance.mktpl_instance["marketplace"].shape == "VM.Standard.A1.Flex" && length(oci_core_instance.mktpl_instance["marketplace"].shape_config) == 1
    error_message = "Marketplace Flex shapes must include their shape configuration."
  }
}

run "normalized_label" {
  command = plan
  variables {
    label_prefix = "MixedCaseLongLabel"
  }
  assert {
    condition     = output.app_name == "mixedcaselon"
    error_message = "Resource labels must be lowercase and limited to twelve characters."
  }
}

run "full_stack_membership" {
  command = plan
  variables {
    fsdr_enabled       = true
    fsdr_region_1      = "uk-cardiff-1"
    fsdr_dns_zone_ocid = "test-zone"
    fsdr_dns_name      = "obaas.example.com"
  }
  assert {
    condition     = length(module.fsdr["managed"].regions.region_0.dr_protection_group.members) == 3 && length(module.fsdr["managed"].regions.region_1.dr_protection_group.members) == 2
    error_message = "Provider-managed groups must contain the database and OKE members."
  }
  assert {
    condition     = local.fsdr_clusters["uk-london-1"].cluster_id == "primary-cluster" && local.fsdr_clusters["uk-cardiff-1"].cluster_id == "standby-cluster" && one([for member in module.fsdr["managed"].regions.region_0.dr_protection_group.members : member if member.member_type == "OKE_CLUSTER"]).managed_node_pool_configs[0].maximum == 3 && length(one(one([for member in module.fsdr["managed"].regions.region_0.dr_protection_group.members : member if member.member_type == "OKE_CLUSTER"]).backup_config).namespaces) == 0 && length(one(one([for member in module.fsdr["managed"].regions.region_0.dr_protection_group.members : member if member.member_type == "OKE_CLUSTER"]).backup_config).exclude_namespaces) == 0
    error_message = "Full-stack preparation must cover both OKE peers, all namespaces, and recovery capacity."
  }
  assert {
    condition     = oci_database_autonomous_database.dr_adb_standby["fsdr_region_1"].subnet_id == "standby-private-subnet" && oci_database_autonomous_database.dr_adb_standby["fsdr_region_1"].is_mtls_connection_required
    error_message = "The standby database must use its regional private endpoint and mTLS."
  }
  assert {
    condition     = oci_dns_rrset.fsdr_application[0].domain == "obaas.example.com" && one(oci_dns_rrset.fsdr_application[0].items).rdata == "192.0.2.10" && output.fsdr_application_url == "http://obaas.example.com" && length(module.fsdr["managed"].iam_policy_statements.groups) > 10
    error_message = "DNS starts on the primary and recovery IAM covers the full stack."
  }
}

run "full_stack_byo_database_compartment" {
  command = plan
  variables {
    fsdr_enabled    = true
    fsdr_region_1   = "uk-cardiff-1"
    byo_db_type     = "ADB-S"
    byo_adb_ocid    = "byo-adb"
    byo_db_password = "test-password"
  }
  assert {
    condition     = local.fsdr_external_databases == tomap({ "byo-adb" = "database-compartment" }) && anytrue([for statement in module.fsdr["managed"].iam_policy_statements.groups : strcontains(statement, "manage autonomous-databases in compartment id database-compartment where target.database.id = 'byo-adb'")])
    error_message = "Protection groups must recover the exact BYO database in its actual compartment."
  }
}

run "existing_standby_network" {
  command = plan
  variables {
    fsdr_enabled         = true
    fsdr_region_1        = "uk-cardiff-1"
    fsdr_standby_network = { vcn_id = "existing-dr-vcn", public_subnet_id = "existing-dr-public", private_subnet_id = "existing-dr-private" }
  }
  assert {
    condition     = length(module.fsdr_network) == 0 && oci_database_autonomous_database.dr_adb_standby["fsdr_region_1"].subnet_id == "existing-dr-private" && oci_load_balancer_load_balancer.fsdr_standby[0].subnet_ids == tolist(["existing-dr-public"])
    error_message = "Existing standby networking must supply both database and ingress subnets."
  }
}

run "full_stack_requires_addons" {
  command = plan
  variables {
    fsdr_enabled           = true
    fsdr_region_1          = "uk-cardiff-1"
    k8s_use_cluster_addons = false
  }
  expect_failures = [terraform_data.fsdr_validation]
}

run "dns_zone_requires_hostname" {
  command = plan
  variables {
    fsdr_enabled       = true
    fsdr_region_1      = "uk-cardiff-1"
    fsdr_dns_zone_ocid = "test-zone"
  }
  expect_failures = [terraform_data.fsdr_validation]
}

run "dns_hostname_requires_zone" {
  command = plan
  variables {
    fsdr_enabled  = true
    fsdr_region_1 = "uk-cardiff-1"
    fsdr_dns_name = "obaas.example.com"
  }
  expect_failures = [terraform_data.fsdr_validation]
}
