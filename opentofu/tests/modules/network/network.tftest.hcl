# Copyright (c) 2024, 2026, Oracle and/or its affiliates.
# All rights reserved. The Universal Permissive License (UPL), Version 1.0 as shown at http://oss.oracle.com/licenses/upl
# spell-checker: disable

mock_provider "oci" {}
variables {
  compartment_id = "test-compartment"
  label_prefix   = "networktest"
  oci_services   = { id = "services", cidr_block = "all-lhr-services-in-oracle-services-network", name = "All LHR Services In Oracle Services Network" }
}

run "separate_public_and_private_subnets" {
  command = plan
  assert {
    condition     = output.private_subnet_cidr_block == "10.42.0.0/17" && output.public_subnet_cidr_block == "10.42.128.0/17"
    error_message = "Managed subnets must split the VCN CIDR into distinct private and public halves."
  }
  assert {
    condition     = oci_core_subnet.private.prohibit_public_ip_on_vnic && !oci_core_subnet.public.prohibit_public_ip_on_vnic
    error_message = "Only the public subnet may assign public addresses."
  }
}

run "private_egress_routes" {
  command = plan
  assert {
    condition = zipmap(oci_core_route_table.private_route_table.route_rules[*].destination, oci_core_route_table.private_route_table.route_rules[*].destination_type) == tomap({
      "0.0.0.0/0"                                   = "CIDR_BLOCK"
      "all-lhr-services-in-oracle-services-network" = "SERVICE_CIDR_BLOCK"
    })
    error_message = "Private routing must cover internet and OCI services destinations."
  }
  assert {
    condition     = one(oci_core_default_route_table.public_route_table.route_rules[*].destination) == "0.0.0.0/0" && length(oci_core_default_security_list.lockdown.ingress_security_rules) == 0
    error_message = "Public routing must allow internet destinations while the default security list denies ingress."
  }
}

run "custom_vcn_cidr" {
  command = plan
  variables {
    vcn_cidr = ["10.80.0.0/20"]
  }
  assert {
    condition     = output.private_subnet_cidr_block == "10.80.0.0/21" && output.public_subnet_cidr_block == "10.80.8.0/21"
    error_message = "Subnet calculation must respect the operator VCN CIDR."
  }
}
