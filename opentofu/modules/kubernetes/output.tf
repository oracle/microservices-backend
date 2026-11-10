# Copyright (c) 2024, 2026, Oracle and/or its affiliates.
# All rights reserved. The Universal Permissive License (UPL), Version 1.0 as shown at http://oss.oracle.com/licenses/upl
# spell-checker: disable

output "cluster_id" {
  value = oci_containerengine_cluster.default_cluster.id
}

output "orm_private_endpoint_ip" {
  value = local.orm_pe
}

output "workers_dynamic_group_name" {
  value = oci_identity_dynamic_group.workers_dynamic_group.name
}

output "node_pool_ids" {
  value = merge(
    { cpu = oci_containerengine_node_pool.cpu_node_pool_details.id },
    var.node_pool_gpu_deploy ? { gpu = oci_containerengine_node_pool.gpu_node_pool_details[0].id } : {}
  )
}

output "configuration_files" {
  value = {
    kubeconfig = local_sensitive_file.kubeconfig.filename
    manifest   = local_sensitive_file.k8s_manifest.filename
    prereqs    = local_sensitive_file.obaas_prereqs_values.filename
    app        = local_sensitive_file.obaas_values.filename
  }
}

output "configuration_ready_id" {
  value = var.run_cfgmgt ? null_resource.apply[0].id : oci_containerengine_cluster.default_cluster.id
}

output "repository_host" {
  value = local.repository_host
}

output "kubeconfig_cmd" {
  description = "Command to generate kubeconfig file"
  value = format(
    "oci ce cluster create-kubeconfig --cluster-id %s --region %s --token-version 2.0.0 --kube-endpoint %s --file $HOME/.kube/config --with-auth-context --profile DEFAULT",
    oci_containerengine_cluster.default_cluster.id,
    var.region,
    oci_containerengine_cluster.default_cluster.endpoint_config[0].is_public_ip_enabled ? "PUBLIC_ENDPOINT" : "PRIVATE_ENDPOINT"
  )
}

output "helm_manual_instructions" {
  description = "Instructions for manual Helm deployment (when cfgmgt was skipped)"
  value       = local.should_show_manual_steps ? local.manual_helm_instructions : null
}
