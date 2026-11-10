# Copyright (c) 2024, 2026, Oracle and/or its affiliates.
# All rights reserved. The Universal Permissive License (UPL), Version 1.0 as shown at http://oss.oracle.com/licenses/upl
# spell-checker: disable

mock_provider "oci" {
  mock_data "oci_identity_regions" {
    defaults = { regions = [{ key = "LHR", name = "uk-london-1" }] }
  }
  mock_data "oci_objectstorage_namespace" {
    defaults = { namespace = "test-namespace" }
  }
  mock_data "oci_core_vcn" {
    defaults = { cidr_blocks = ["10.42.0.0/16"] }
  }
  mock_data "oci_core_subnet" {
    defaults = { cidr_block = "10.42.0.0/17" }
  }
  override_data {
    target = data.oci_containerengine_node_pool_option.images
    values = { sources = [
      { image_id = "cpu-x86", source_name = "Oracle-Linux-8.10-20260901-OKE-1.36.1-123", source_type = "IMAGE" },
      { image_id = "cpu-arm", source_name = "Oracle-Linux-8.10-20260901-OKE-1.36.1-123-aarch64", source_type = "IMAGE" },
      { image_id = "gpu-x86", source_name = "Oracle-Linux-8.10-20260901-OKE-1.36.1-123-GPU", source_type = "IMAGE" }
    ] }
  }
  mock_data "oci_limits_limit_values" {
    defaults = { limit_values = [
      { availability_domain = "AD-1", name = "gpu-a10-count", scope_type = "AD", value = "1" },
      { availability_domain = "AD-2", name = "gpu-a10-count", scope_type = "AD", value = "0" }
    ] }
  }
  override_resource {
    target = oci_containerengine_cluster.default_cluster
    values = {
      id        = "test-cluster"
      endpoints = [{ private_endpoint = "10.42.0.10:6443", public_endpoint = "192.0.2.10:6443", kubernetes = "192.0.2.10:6443", ipv6endpoint = "", vcn_hostname_endpoint = "cluster.test" }]
    }
  }
  mock_data "oci_resourcemanager_private_endpoint_reachable_ip" {
    defaults = { ip_address = "10.42.0.12" }
  }
}
mock_provider "oci" { alias = "home_region" }
mock_provider "random" {
  mock_resource "random_password" { defaults = { result = "ExamplePassword123!" } }
  mock_resource "random_string" { defaults = { result = "ExampleApiKey" } }
}
mock_provider "tls" {
  mock_resource "tls_self_signed_cert" { defaults = { cert_pem = "test-ca" } }
  mock_resource "tls_locally_signed_cert" { defaults = { cert_pem = "test-cert" } }
  mock_resource "tls_private_key" { defaults = { private_key_pem = "test-key" } }
}
mock_provider "cloudinit" {}
mock_provider "local" {}
mock_provider "null" {}

variables {
  tenancy_id        = "test-tenancy"
  compartment_id    = "test-compartment"
  vcn_id            = "test-vcn"
  oci_services      = { id = "services", cidr_block = "all-lhr-services-in-oracle-services-network", name = "All LHR Services In Oracle Services Network" }
  public_subnet_id  = "public-subnet"
  private_subnet_id = "private-subnet"
  orm_install       = false
  lb = {
    id                 = "test-lb"
    compartment_id     = "test-compartment"
    ip_address_details = [{ ip_address = "192.0.2.20" }]
    shape_details      = [{ minimum_bandwidth_in_mbps = 10, maximum_bandwidth_in_mbps = 100 }]
  }
  region                     = "uk-london-1"
  availability_domains       = ["AD-1", "AD-2"]
  label_prefix               = "kubetest"
  db_ocid                    = "test-adb"
  db_name                    = "TEST_DB"
  db_conn                    = { db_type = "ADB", username = "ADMIN", password = "ExamplePassword123!", service = "TESTDB_TP" }
  kubernetes_version         = "1.36.1"
  api_is_public              = true
  api_endpoint_allowed_cidrs = "192.0.2.0/24, 198.51.100.0/24"
  node_pool_gpu_deploy       = false
  cpu_node_pool_size         = 3
  gpu_node_pool_size         = 1
  compute_cpu_shape          = "VM.Standard.E5.Flex"
  compute_cpu_ocpu           = 2
  compute_gpu_shape          = "VM.GPU.A10.1"
  compute_os_ver             = "8.10"
  lb_nsg_id                  = "lb-nsg"
  run_cfgmgt                 = false
  byo_ocir_url               = ""
  optimizer_version          = "Stable"
}

# Image discovery requires a cluster ID in the mock state.
run "setup_cluster" {
  command = apply
  plan_options {
    target = [oci_containerengine_cluster.default_cluster]
  }
}

run "adb_compartment_policy" {
  command = plan
  variables {
    adb_compartment_id = "database-compartment"
  }
  assert {
    condition     = contains(oci_identity_policy.workers_policies.statements, "allow any-user to manage autonomous-database-family in compartment id database-compartment where all {request.principal.type = 'workload', request.principal.namespace = 'oracle-database-operator-system', request.principal.service_account = 'default', request.principal.cluster_id = 'test-cluster'}")
    error_message = "Database operator permissions must follow the selected ADB compartment."
  }
}

run "cpu_cluster_and_addons" {
  command = plan
  assert {
    condition     = oci_containerengine_cluster.default_cluster.type == "ENHANCED_CLUSTER" && oci_containerengine_cluster.default_cluster.kubernetes_version == "v1.36.1" && one(oci_containerengine_cluster.default_cluster.cluster_pod_network_options).cni_type == "FLANNEL_OVERLAY"
    error_message = "OKE must use an enhanced cluster with the selected Kubernetes version and overlay networking."
  }
  assert {
    condition     = one(oci_containerengine_node_pool.cpu_node_pool_details.node_shape_config).ocpus == 2 && one(oci_containerengine_node_pool.cpu_node_pool_details.node_shape_config).memory_in_gbs == 32 && one(oci_containerengine_node_pool.cpu_node_pool_details.node_config_details).size == 3 && toset([for placement in one(oci_containerengine_node_pool.cpu_node_pool_details.node_config_details).placement_configs : placement.subnet_id]) == toset(["private-subnet"])
    error_message = "CPU workers must retain requested sizing and private placement."
  }
  assert {
    condition     = one(oci_containerengine_node_pool.cpu_node_pool_details.node_source_details).image_id == "cpu-x86" && length(oci_containerengine_node_pool.gpu_node_pool_details) == 0
    error_message = "CPU workers must select the matching x86 OKE image with GPU deployment opt-in."
  }
  assert {
    condition     = oci_containerengine_node_pool.cpu_node_pool_details.node_metadata.user_data == data.cloudinit_config.workers.rendered
    error_message = "CPU workers must retain the existing worker cloud-init configuration."
  }
  assert {
    condition     = length(oci_containerengine_addon.oraoper_addon) == 1 && length(oci_containerengine_addon.certmgr_addon) == 1 && length(oci_containerengine_addon.ingress_addon) == 1
    error_message = "Managed database, certificate, and native ingress add-ons must be enabled by default."
  }
}

run "arm_worker_images" {
  command = plan
  variables {
    compute_cpu_shape = "VM.Standard.A1.Flex"
    compute_cpu_ocpu  = 4
  }
  assert {
    condition     = one(oci_containerengine_node_pool.cpu_node_pool_details.node_source_details).image_id == "cpu-arm" && one(oci_containerengine_node_pool.cpu_node_pool_details.node_shape_config).memory_in_gbs == 64
    error_message = "ARM worker shapes must select an ARM image and scale memory with OCPUs."
  }
}

run "gpu_capacity_and_placement" {
  command = plan
  variables {
    node_pool_gpu_deploy = true
    gpu_node_pool_size   = 2
  }
  assert {
    condition     = one(oci_containerengine_node_pool.gpu_node_pool_details[0].node_source_details).image_id == "gpu-x86" && one(oci_containerengine_node_pool.gpu_node_pool_details[0].node_config_details).size == 2 && toset([for placement in one(oci_containerengine_node_pool.gpu_node_pool_details[0].node_config_details).placement_configs : placement.availability_domain]) == toset(["AD-1"])
    error_message = "GPU workers must select the GPU image and use only availability domains with capacity."
  }
  assert {
    condition     = oci_containerengine_node_pool.gpu_node_pool_details[0].node_metadata.user_data == data.cloudinit_config.workers.rendered
    error_message = "GPU workers must share the worker cloud-init configuration."
  }
}

run "addon_ownership" {
  command = plan
  variables {
    use_cluster_addons = false
  }
  assert {
    condition     = length(oci_containerengine_addon.oraoper_addon) == 0 && length(oci_containerengine_addon.certmgr_addon) == 0 && length(oci_containerengine_addon.ingress_addon) == 0
    error_message = "Disabling managed add-ons must leave their lifecycle to the operator."
  }
}

run "public_api_access" {
  command = plan
  assert {
    condition     = toset(keys(local.api_endpoint_custom_rules)) == toset(["Allow custom ingress to kube-apiserver from 192.0.2.0/24", "Allow custom ingress to kube-apiserver from 198.51.100.0/24"]) && one(one(oci_core_network_security_group_security_rule.k8s["Allow custom ingress to kube-apiserver from 192.0.2.0/24"].tcp_options).destination_port_range).min == 6443
    error_message = "Public API access must normalize CIDRs and target the kube-apiserver port."
  }
  assert {
    condition     = one(one(oci_core_network_security_group_security_rule.k8s["Workers from Load Balancer."].tcp_options).destination_port_range).min == 30000 && one(one(oci_core_network_security_group_security_rule.k8s["Workers from Load Balancer."].tcp_options).destination_port_range).max == 32767
    error_message = "Load-balancer ingress to workers must cover the NodePort range."
  }
}

run "private_api_access" {
  command = plan
  variables {
    api_is_public = false
  }
  assert {
    condition     = length(local.api_endpoint_custom_rules) == 0 && length(oci_core_network_security_group_security_rule.k8s) == 17 && one(oci_containerengine_cluster.default_cluster.endpoint_config).is_public_ip_enabled
    error_message = "Private API access must remove external ingress while retaining the stable endpoint and internal rules."
  }
  assert {
    condition     = length(null_resource.apply) == 0 && output.helm_manual_instructions == null
    error_message = "Infrastructure-only plans must skip configuration management."
  }
}

run "private_cfgmgt_blocked" {
  command = plan
  variables {
    api_is_public = false
    run_cfgmgt    = true
  }
  expect_failures = [null_resource.apply]
}

run "orm_private_access" {
  command = plan
  variables {
    api_is_public = false
    orm_install   = true
    run_cfgmgt    = true
  }
  assert {
    condition     = length(oci_resourcemanager_private_endpoint.orm_pe) == 1 && length(null_resource.apply) == 1 && output.helm_manual_instructions == null
    error_message = "ORM deployment must create its reachable private endpoint and allow configuration management."
  }
}

run "database_and_generated_files" {
  command = plan
  assert {
    condition     = yamldecode(local.obaas_values).database.type == "ADB-S" && yamldecode(local.obaas_values).database.oci.ocid == "test-adb" && yamldecode(local.obaas_values).database.privAuthN.secretName == "test-db-db-priv-authn"
    error_message = "Generated ADB values must use the database OCID and normalized credential secret names."
  }
  assert {
    condition     = yamldecode(local.obaas_values).apisix.ingress.className == "native-ic" && !yamldecode(local.obaas_values)["gateway-helm"].enabled && !yamldecode(local.obaas_prereqs_values)["oracle-database-operator"].enabled
    error_message = "Generated chart values must respect native ingress and managed database-operator ownership."
  }
  assert {
    condition     = local_sensitive_file.kubeconfig.file_permission == "600" && local_sensitive_file.k8s_manifest.file_permission == "600" && local_sensitive_file.obaas_values.file_permission == "600"
    error_message = "Generated credentials and configuration must use owner-only permissions."
  }
  assert {
    condition     = jsondecode(data.cloudinit_config.workers.part[0].content).resize_rootfs && contains(jsondecode(data.cloudinit_config.workers.part[0].content).growpart.devices, "/")
    error_message = "Worker cloud-init must expand the root filesystem."
  }
  assert {
    condition     = tls_self_signed_cert.acme_ca.is_ca_certificate && contains(tls_self_signed_cert.acme_ca.allowed_uses, "cert_signing") && contains(tls_locally_signed_cert.example_com.allowed_uses, "server_auth")
    error_message = "TLS configuration must distinguish the signing CA and server certificate."
  }
}

run "external_database_and_optional_components" {
  command = plan
  variables {
    db_name              = "PDB.example.com"
    db_ocid              = "N/A"
    db_conn              = { db_type = "OTHER", username = "SYSTEM", password = "ExamplePassword123!", service = "db.example.com:1522/PDB.example.com" }
    deploy_kafka         = true
    deploy_coherence     = true
    deploy_optimizer     = true
    node_pool_gpu_deploy = true
  }
  assert {
    condition     = yamldecode(local.obaas_values).database.type == "OTHER" && yamldecode(local.obaas_values).database.other.dsn == "db.example.com:1522/PDB.example.com" && yamldecode(local.obaas_values)["ai-optimizer"].server.database.type == "OTHER"
    error_message = "External database values must reach both OBaaS and AI Optimizer."
  }
  assert {
    condition     = yamldecode(local.obaas_values).kafka.enabled && yamldecode(local.obaas_values).coherence.enabled && yamldecode(local.obaas_values)["ai-optimizer"].ollama.enabled
    error_message = "Kafka, Coherence, and GPU Ollama deployment choices must reach generated Helm values."
  }
}

run "private_registry" {
  command = plan
  variables {
    byo_ocir_url     = "registry.example.com/platform"
    deploy_optimizer = true
  }
  assert {
    condition     = length(oci_artifacts_container_repository.optimizer_repositories) == 0 && yamldecode(local.obaas_values).eureka.image.repository == "registry.example.com/platform/eureka" && yamldecode(local.obaas_values)["ai-optimizer"].server.image.repository == "registry.example.com/platform/ai-optimizer-server"
    error_message = "BYO registry must supply images without creating managed repositories."
  }
  assert {
    condition     = yamldecode(local.obaas_prereqs_values)["external-secrets"].image.repository == "registry.example.com/platform/external-secrets/external-secrets" && yamldecode(local.obaas_values).signoz.signoz.env.SIGNOZ_API_KEY.valueFrom.secretKeyRef.key == "password"
    error_message = "Private-registry values must preserve prerequisite images and observability secret references."
  }
  assert {
    condition     = yamldecode(local.obaas_values).signoz.signoz.image.registry == "registry.example.com/platform" && yamldecode(local.obaas_values).otmm.image.repository == "registry.example.com/platform/database/otmm" && yamldecode(local.obaas_values).otmm.coordinator.image.repository == "registry.example.com/platform/database/microtx-coordinator"
    error_message = "Private-registry image overrides must coexist with secrets and other OTMM image settings."
  }
}

run "workload_identity" {
  command = plan
  assert {
    condition     = oci_identity_dynamic_group.workers_dynamic_group.compartment_id == "test-tenancy" && oci_identity_policy.workers_policies.compartment_id == "test-tenancy" && length(oci_identity_policy.workers_policies.statements) >= 10
    error_message = "Worker dynamic groups and workload policies must be created at tenancy scope."
  }
  assert {
    condition     = anytrue([for statement in oci_identity_policy.workers_policies.statements : strcontains(statement, "oracle-database-operator-system") && strcontains(statement, "autonomous-database-family")]) && anytrue([for statement in oci_identity_policy.workers_policies.statements : strcontains(statement, "oci-native-ingress-controller") && strcontains(statement, "load-balancers")])
    error_message = "Workload policies must include database-operator and native ingress permissions."
  }
}

run "regional_recovery_artifacts" {
  command = plan
  variables {
    label_prefix    = "kubetestdr"
    app_namespace   = "kubetest"
    stage_directory = "cfgmgt/stage/fsdr/standby"
  }
  assert {
    condition     = local_sensitive_file.kubeconfig.filename == "cfgmgt/stage/fsdr/standby/kubeconfig" && local_sensitive_file.obaas_values.filename == "cfgmgt/stage/fsdr/standby/obaas-values.yaml" && yamldecode(local.obaas_values).database.oci.ocid == "test-adb"
    error_message = "Regional configuration files must use their own directory and database."
  }
  assert {
    condition     = strcontains(local.repository_base, "/kubetest") && !strcontains(local.repository_base, "/kubetestdr")
    error_message = "Peer clusters must retain the application namespace and image repository names."
  }
}

run "recovery_external_database_permissions" {
  command = plan
  variables {
    recovery_external_databases = { "byo-adb" = "database-compartment" }
  }
  assert {
    condition     = anytrue([for statement in oci_identity_policy.workers_policies.statements : strcontains(statement, "manage autonomous-databases in compartment id database-compartment") && strcontains(statement, "target.database.id = 'byo-adb'") && strcontains(statement, "oracle-database-operator-system")])
    error_message = "Database operators must access the exact external database for recovery and failback."
  }
}

run "bootstrap_pv_manifest" {
  command = plan
  variables {
    persistent_storage = {
      chart = { etcd = { replicas = 1, size_in_gbs = 8, storage_class = "obaas-preallocated" } }
      volumes = { etcd-0 = {
        id                  = "original-volume"
        claim_name          = "data-obaas-etcd-0"
        namespace           = "kubetest"
        size_in_gbs         = 50
        availability_domain = "TEST:UK-LONDON-1-AD-3"
      } }
    }
  }
  assert {
    condition     = length(local.storage_manifests) == 2 && yamldecode(local.storage_manifests[1]).spec.csi.volumeHandle == "original-volume"
    error_message = "Bootstrap must render the reserved PV using its provisioned volume handle."
  }
  assert {
    condition     = yamldecode(local.storage_manifests[1]).spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values == ["UK-LONDON-1-AD-3"]
    error_message = "PV zone affinity must use the availability-domain name without the tenancy prefix."
  }
}

run "recovered_pv_manifest" {
  command = plan
  variables {
    manage_persistent_volumes = false
    persistent_storage = {
      chart = { etcd = { replicas = 1, size_in_gbs = 8, storage_class = "obaas-preallocated" } }
      volumes = { etcd-0 = {
        id                  = "original-volume"
        claim_name          = "data-obaas-etcd-0"
        namespace           = "kubetest"
        size_in_gbs         = 50
        availability_domain = "TEST:AD-1"
      } }
    }
  }
  assert {
    condition     = length(local.storage_manifests) == 1 && yamldecode(local.storage_manifests[0]).kind == "StorageClass" && !strcontains(local.k8s_manifest, "original-volume")
    error_message = "Recovered manifests must preserve native PV handles while retaining the StorageClass."
  }
  assert {
    condition     = yamldecode(local.obaas_values).apisix.etcd.persistence.storageClass == "obaas-preallocated"
    error_message = "Recovered releases must retain their chart storage configuration."
  }
}
