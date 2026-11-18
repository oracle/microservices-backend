# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at https://oss.oracle.com/licenses/upl

mock_provider "oci" {
  mock_data "oci_identity_region_subscriptions" {
    defaults = { region_subscriptions = [
      { region_name = "uk-cardiff-1", region_key = "CWL", is_home_region = false, state = "READY", tenancy_id = "test-tenancy" },
      { region_name = "uk-london-1", region_key = "LHR", is_home_region = true, state = "READY", tenancy_id = "test-tenancy" }
    ] }
  }
}
mock_provider "oci" { alias = "home_region" }
mock_provider "oci" { alias = "fsdr_region_1" }
mock_provider "random" {}
mock_provider "tls" {}
mock_provider "local" {}
mock_provider "null" {}
mock_provider "cloudinit" {}

variables {
  tenancy_ocid     = "test-tenancy"
  compartment_ocid = "test-compartment"
  region           = "uk-london-1"
  label_prefix     = "regiontest"
  fsdr_enabled     = true
  fsdr_region_1    = "uk-cardiff-1"
  k8s_run_cfgmgt   = false
}

run "subscribed_standby" {
  command = plan
  plan_options {
    target = [terraform_data.fsdr_validation]
  }
  assert {
    condition     = data.oci_identity_region_subscriptions.tenancy.tenancy_id == "test-tenancy"
    error_message = "Standby validation must use the deployment tenancy."
  }
}

run "unsubscribed_standby" {
  command = plan
  plan_options {
    target = [terraform_data.fsdr_validation]
  }
  override_data {
    target = data.oci_identity_region_subscriptions.tenancy
    values = { region_subscriptions = [
      { region_name = "uk-london-1", region_key = "LHR", is_home_region = true, state = "READY", tenancy_id = "test-tenancy" }
    ] }
  }
  expect_failures = [terraform_data.fsdr_validation]
}

run "pending_subscription" {
  command = plan
  plan_options {
    target = [terraform_data.fsdr_validation]
  }
  override_data {
    target = data.oci_identity_region_subscriptions.tenancy
    values = { region_subscriptions = [
      { region_name = "uk-london-1", region_key = "LHR", is_home_region = true, state = "READY", tenancy_id = "test-tenancy" },
      { region_name = "uk-cardiff-1", region_key = "CWL", is_home_region = false, state = "IN_PROGRESS", tenancy_id = "test-tenancy" }
    ] }
  }
  expect_failures = [terraform_data.fsdr_validation]
}

run "fsdr_disabled" {
  command = plan
  variables {
    fsdr_enabled  = false
    fsdr_region_1 = ""
  }
  plan_options {
    target = [terraform_data.fsdr_validation]
  }
  assert {
    condition     = length(terraform_data.fsdr_validation) == 0
    error_message = "A deployment with FSDR disabled must not require a standby subscription."
  }
}
