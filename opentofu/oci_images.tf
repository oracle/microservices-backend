# Copyright © 2023, 2025, Oracle and/or its affiliates.
# All rights reserved. The Universal Permissive License (UPL), Version 1.0 as shown at http://oss.oracle.com/licenses/upl

/********************
Marketplace UI Parameters
https://docs.oracle.com/en-us/iaas/Content/partner-portal/partner-portal_build-subscribe_terraform_configurations_to_marketplace_images.htm
********************/
# Controls if we need to subscribe to marketplace PIC image and accept terms & conditions
# false -> for internal testing.
# true  -> for publishing
# This will be over-rode during build.py for the ORM stack
variable "mktpl_use_image" {
  default = "false"
}

variable "mktpl_listing_resource_version" {
  description = "Package Version Reference"
  default     = "1.0.0" # Metered
}

variable "mktpl_listing_id" {
  description = "Listing OCID"
  default     = "ocid1.appcataloglisting.oc1..aaaaaaaa3tfuluibh4gneqv7fd4bxpczepgt5qmyglrjaoxrihyncifkubkq" # Metered
}

variable "mktpl_listing_resource_id" {
  description = "Image OCID (from Marketplace)"
  default     = "ocid1.image.oc1..aaaaaaaapxqd742nhqijxtquidej4zji2fxlk4pcldtkeakknbqtsv4zusnq" # Metered
}

/********************
Marketplace Data
********************/
# Gets the partner image subscription
data "oci_core_app_catalog_subscriptions" "oci_core_app_catalog_subscriptions" {
  for_each       = var.mktpl_use_image ? { marketplace = true } : {}
  compartment_id = local.compartment_ocid
  listing_id     = var.mktpl_listing_id
  filter {
    name   = "listing_resource_version"
    values = [var.mktpl_listing_resource_version]
  }
}

// Look for where the Micro Instance can be placed (in case using non-Flex)
data "oci_limits_limit_values" "limits_limit_values" {
  for_each = var.mktpl_use_image ? { marketplace = true } : {}

  compartment_id = var.tenancy_ocid
  service_name   = "compute"
  scope_type     = "AD"
  name           = "vm-standard-e2-1-micro-count"
  filter {
    name   = "value"
    values = ["2"]
  }
}

// If we have a value from limits, use that, otherwise use AD-1
locals {
  is_flexible_shape = length(regexall("Flex", var.compute_cpu_shape)) > 0 ? true : false
  mktpl_ad = var.mktpl_use_image && try(length(data.oci_limits_limit_values.limits_limit_values["marketplace"].limit_values), 0) > 0 ? (
    data.oci_limits_limit_values.limits_limit_values["marketplace"].limit_values[0].availability_domain
    ) : (
    data.oci_identity_availability_domains.all.availability_domains[0]["name"]
  )
}

/********************
Marketplace Resources
********************/
# Get Image Agreement
resource "oci_core_app_catalog_listing_resource_version_agreement" "mktpl_image_agreement" {
  for_each                 = var.mktpl_use_image ? { marketplace = true } : {}
  listing_id               = var.mktpl_listing_id
  listing_resource_version = var.mktpl_listing_resource_version
}

# Accept Terms and Subscribe to the image, placing the image in a particular compartment
resource "oci_core_app_catalog_subscription" "mktpl_image_subscription" {
  for_each                 = var.mktpl_use_image ? { marketplace = true } : {}
  compartment_id           = local.compartment_ocid
  eula_link                = oci_core_app_catalog_listing_resource_version_agreement.mktpl_image_agreement["marketplace"].eula_link
  listing_id               = oci_core_app_catalog_listing_resource_version_agreement.mktpl_image_agreement["marketplace"].listing_id
  listing_resource_version = oci_core_app_catalog_listing_resource_version_agreement.mktpl_image_agreement["marketplace"].listing_resource_version
  oracle_terms_of_use_link = oci_core_app_catalog_listing_resource_version_agreement.mktpl_image_agreement["marketplace"].oracle_terms_of_use_link
  signature                = oci_core_app_catalog_listing_resource_version_agreement.mktpl_image_agreement["marketplace"].signature
  time_retrieved           = oci_core_app_catalog_listing_resource_version_agreement.mktpl_image_agreement["marketplace"].time_retrieved
  timeouts {
    create = "20m"
  }
}



resource "oci_core_instance" "mktpl_instance" {
  for_each            = var.mktpl_use_image ? { marketplace = true } : {}
  compartment_id      = local.compartment_ocid
  availability_domain = local.mktpl_ad
  display_name        = format("%s-mktpl-instance", local.label_prefix)
  agent_config {
    are_all_plugins_disabled = "true"
  }
  availability_config {
    recovery_action = "RESTORE_INSTANCE"
  }
  create_vnic_details {
    assign_private_dns_record = "false"
    assign_public_ip          = "false"
    subnet_id                 = local.private_subnet_ocid
  }
  shape = local.is_flexible_shape ? var.compute_cpu_shape : "VM.Standard.E2.1.Micro"
  dynamic "shape_config" {
    for_each = local.is_flexible_shape ? [1] : []
    content {
      memory_in_gbs = "1"
      ocpus         = "1"
    }
  }
  launch_options {
    boot_volume_type                    = "PARAVIRTUALIZED"
    firmware                            = "UEFI_64"
    is_consistent_volume_naming_enabled = "true"
    network_type                        = "PARAVIRTUALIZED"
    remote_data_volume_type             = "PARAVIRTUALIZED"
  }
  source_details {
    boot_volume_size_in_gbs = "50"
    boot_volume_vpus_per_gb = "10"
    source_id               = var.mktpl_listing_resource_id
    source_type             = "image"
  }
  state = "STOPPED"
}
