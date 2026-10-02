# Copyright (c) 2024, 2026, Oracle and/or its affiliates.
# All rights reserved. The Universal Permissive License (UPL), Version 1.0 as shown at http://oss.oracle.com/licenses/upl
# spell-checker: disable

locals {
  k8s_manifest = templatefile("${path.module}/templates/k8s-manifest.yaml", {
    label              = var.label_prefix
    repository_host    = local.repository_host
    repository_base    = local.repository_base
    compartment_ocid   = var.lb.compartment_id
    lb_ocid            = var.lb.id
    lb_subnet_ocid     = var.public_subnet_id
    lb_ip_ocid         = var.lb.ip_address_details[0].ip_address
    lb_nsgs            = var.lb_nsg_id
    lb_min_shape       = var.lb.shape_details[0].minimum_bandwidth_in_mbps
    lb_max_shape       = var.lb.shape_details[0].maximum_bandwidth_in_mbps
    db_name            = local.db_name
    db_username        = var.db_conn.username
    db_password        = var.db_conn.password
    db_service         = var.db_conn.service
    signoz_secret      = random_password.signoz_secret.result
    clickhouse_secret  = random_password.clickhouse_secret.result
    deploy_buildkit    = var.byo_ocir_url == ""
    use_cluster_addons = var.use_cluster_addons
    deploy_buildkit    = var.byo_ocir_url == ""
    deploy_optimizer   = var.deploy_optimizer
    optimizer_version  = var.optimizer_version
    optimizer_api_key  = random_string.optimizer_api_key.result
    ca_crt             = base64encode(tls_self_signed_cert.acme_ca.cert_pem)
    tls_crt            = base64encode(tls_locally_signed_cert.example_com.cert_pem)
    tls_key            = base64encode(tls_private_key.example_com.private_key_pem)
  })
}

resource "local_sensitive_file" "kubeconfig" {
  content         = data.oci_containerengine_cluster_kube_config.default_cluster_kube_config.content
  filename        = "${path.root}/cfgmgt/stage/kubeconfig"
  file_permission = 0600
}

resource "local_sensitive_file" "k8s_manifest" {
  content         = local.k8s_manifest
  filename        = "${path.root}/cfgmgt/stage/k8s-manifest.yaml"
  file_permission = 0600
}

resource "null_resource" "apply" {
  count = var.run_cfgmgt ? 1 : 0
  triggers = {
    always_run = "${timestamp()}"
  }

  lifecycle {
    precondition {
      condition     = local.can_apply_cfgmgt
      error_message = local.cfgmgt_error_message
    }
  }

  provisioner "local-exec" {
    command = <<EOT
      python3 ${path.root}/cfgmgt/apply.py ${var.label_prefix}${local.orm_pe != "" ? " --private_endpoint ${local.orm_pe}" : ""} --optimizer_version ${var.optimizer_version}${var.use_local_charts ? " --local-charts" : ""}
    EOT
  }
  depends_on = [
    local_sensitive_file.kubeconfig,
    local_sensitive_file.k8s_manifest,
    oci_containerengine_node_pool.cpu_node_pool_details,
    oci_containerengine_node_pool.gpu_node_pool_details,
    oci_containerengine_addon.oraoper_addon,
    oci_containerengine_addon.certmgr_addon,
    oci_containerengine_addon.ingress_addon
  ]
}
