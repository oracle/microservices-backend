# Copyright (c) 2024, 2026, Oracle and/or its affiliates.
# All rights reserved. The Universal Permissive License (UPL), Version 1.0 as shown at http://oss.oracle.com/licenses/upl
# spell-checker: disable

locals {
  obaas_prereqs_values = templatefile("${path.module}/templates/obaas-prereqs-values.yaml", {
    label        = var.label_prefix
    byo_ocir_url = var.byo_ocir_url
  })

  obaas_values = templatefile("${path.module}/templates/obaas-values.yaml", {
    label                = var.label_prefix
    oci_region           = var.region
    db_type              = var.db_conn.db_type
    db_ocid              = var.db_ocid
    db_dsn               = var.db_conn.service
    db_name              = local.db_name
    lb_ip                = var.lb.ip_address_details[0].ip_address
    deploy_optimizer     = var.deploy_optimizer
    repository_host      = local.repository_host
    repository_base      = local.repository_base
    node_pool_gpu_deploy = var.node_pool_gpu_deploy
    byo_ocir_url         = var.byo_ocir_url
    deploy_kafka         = var.deploy_kafka
  })
}

resource "local_sensitive_file" "obaas_prereqs_values" {
  content         = local.obaas_prereqs_values
  filename        = "${path.root}/cfgmgt/stage/obaas-prereqs-values.yaml"
  file_permission = 0600
}

resource "local_sensitive_file" "obaas_values" {
  content         = local.obaas_values
  filename        = "${path.root}/cfgmgt/stage/obaas-values.yaml"
  file_permission = 0600
}