# Copyright (c) 2024, 2026, Oracle and/or its affiliates.
# All rights reserved. The Universal Permissive License (UPL), Version 1.0 as shown at http://oss.oracle.com/licenses/upl
# spell-checker: disable

variable "byo_vcn_ocid" {
  description = "Bring Your Own Virtual Cloud Network - VCN OCID"
  type        = string
  default     = ""
}

variable "byo_public_subnet_ocid" {
  description = "Bring Your Own Virtual Cloud Network - Pubic Subnet OCID"
  type        = string
  default     = ""
}

variable "byo_private_subnet_ocid" {
  description = "Bring Your Own Virtual Cloud Network - Private Subnet OCID"
  type        = string
  default     = ""
}

module "network" {
  for_each       = var.byo_vcn_ocid == "" ? { managed = true } : {}
  source         = "./modules/network"
  compartment_id = local.compartment_ocid
  label_prefix   = local.label_prefix
  oci_services   = data.oci_core_services.core_services.services.0

}

variable "fsdr_standby_vcn_cidr" {
  description = "CIDR for the managed standby VCN."
  type        = list(string)
  default     = ["10.43.0.0/16"]
}

variable "fsdr_standby_network" {
  description = "Existing standby-region VCN and subnets; null creates managed networking."
  type = object({
    vcn_id            = string
    public_subnet_id  = string
    private_subnet_id = string
  })
  default = null
}

variable "fsdr_dns_zone_ocid" {
  description = "Optional OCI public DNS zone for the initial application record; supply with fsdr_dns_name."
  type        = string
  default     = ""
}

variable "fsdr_dns_name" {
  description = "Optional application hostname initially pointing to the primary; supply with fsdr_dns_zone_ocid."
  type        = string
  default     = ""
}

locals {
  fsdr_dns_enabled               = var.fsdr_enabled && trimspace(var.fsdr_dns_zone_ocid) != "" && trimspace(var.fsdr_dns_name) != ""
  fsdr_standby_label             = substr(format("%sdr", local.label_prefix), 0, 15)
  fsdr_standby_vcn_id            = var.fsdr_standby_network != null ? var.fsdr_standby_network.vcn_id : try(module.fsdr_network["standby"].vcn_ocid, null)
  fsdr_standby_public_subnet_id  = var.fsdr_standby_network != null ? var.fsdr_standby_network.public_subnet_id : try(module.fsdr_network["standby"].public_subnet_ocid, null)
  fsdr_standby_private_subnet_id = var.fsdr_standby_network != null ? var.fsdr_standby_network.private_subnet_id : try(module.fsdr_network["standby"].private_subnet_ocid, null)
}

data "oci_core_services" "fsdr_standby" {
  count    = var.fsdr_enabled ? 1 : 0
  provider = oci.fsdr_region_1
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}

data "oci_core_subnet" "fsdr_standby_private" {
  count     = var.fsdr_enabled ? 1 : 0
  subnet_id = local.fsdr_standby_private_subnet_id
  provider  = oci.fsdr_region_1
}

module "fsdr_network" {
  for_each       = var.fsdr_enabled && var.fsdr_standby_network == null ? { standby = true } : {}
  source         = "./modules/network"
  compartment_id = local.compartment_ocid
  label_prefix   = local.fsdr_standby_label
  vcn_cidr       = var.fsdr_standby_vcn_cidr
  oci_services   = data.oci_core_services.fsdr_standby[0].services[0]
  providers = {
    oci = oci.fsdr_region_1
  }
}

resource "oci_core_network_security_group" "fsdr_standby" {
  for_each       = var.fsdr_enabled ? toset(["lb", "adb"]) : toset([])
  compartment_id = local.compartment_ocid
  vcn_id         = local.fsdr_standby_vcn_id
  display_name   = format("%s-%s", local.fsdr_standby_label, each.key)
  provider       = oci.fsdr_region_1
}

locals {
  fsdr_standby_rules = var.fsdr_enabled ? merge(
    { for cidr in split(",", replace(var.client_allowed_cidrs, "/\\s+/", "")) : format("http-%s", cidr) => { nsg = "lb", source = cidr, min = 80, max = 80 } },
    { for cidr in split(",", replace(var.server_allowed_cidrs, "/\\s+/", "")) : format("https-%s", cidr) => { nsg = "lb", source = cidr, min = 443, max = 443 } },
    { database = { nsg = "adb", source = data.oci_core_subnet.fsdr_standby_private[0].cidr_block, min = 1521, max = 1522 } }
  ) : {}
}

resource "oci_core_network_security_group_security_rule" "fsdr_standby_ingress" {
  for_each                  = local.fsdr_standby_rules
  network_security_group_id = oci_core_network_security_group.fsdr_standby[each.value.nsg].id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = each.value.source
  source_type               = "CIDR_BLOCK"
  provider                  = oci.fsdr_region_1
  tcp_options {
    destination_port_range {
      min = each.value.min
      max = each.value.max
    }
  }
}

resource "oci_core_network_security_group_security_rule" "fsdr_standby_lb_egress" {
  count                     = var.fsdr_enabled ? 1 : 0
  network_security_group_id = oci_core_network_security_group.fsdr_standby["lb"].id
  direction                 = "EGRESS"
  protocol                  = "6"
  destination               = data.oci_core_subnet.fsdr_standby_private[0].cidr_block
  destination_type          = "CIDR_BLOCK"
  provider                  = oci.fsdr_region_1
}

resource "oci_load_balancer_load_balancer" "fsdr_standby" {
  count                      = var.fsdr_enabled ? 1 : 0
  compartment_id             = local.compartment_ocid
  display_name               = format("%s-lb", local.fsdr_standby_label)
  shape                      = "flexible"
  is_private                 = false
  subnet_ids                 = [local.fsdr_standby_public_subnet_id]
  network_security_group_ids = [oci_core_network_security_group.fsdr_standby["lb"].id]
  provider                   = oci.fsdr_region_1
  shape_details {
    minimum_bandwidth_in_mbps = var.lb_min_shape
    maximum_bandwidth_in_mbps = var.lb_max_shape
  }
}

resource "oci_dns_rrset" "fsdr_application" {
  count           = local.fsdr_dns_enabled ? 1 : 0
  zone_name_or_id = var.fsdr_dns_zone_ocid
  domain          = var.fsdr_dns_name
  rtype           = "A"
  items {
    domain = var.fsdr_dns_name
    rtype  = "A"
    rdata  = oci_load_balancer_load_balancer.lb.ip_address_details[0].ip_address
    ttl    = 60
  }
  lifecycle {
    ignore_changes = [items]
  }
}

output "fsdr_application_url" {
  description = "Application URL when a DNS hostname is configured."
  value       = local.fsdr_dns_enabled ? format("http://%s", var.fsdr_dns_name) : null
}

output "fsdr_regional_application_urls" {
  description = "Regional load balancer URLs; use the active region after recovery."
  value       = { for region, cluster in local.fsdr_clusters : region => format("http://%s", cluster.lb_ip) }
}
