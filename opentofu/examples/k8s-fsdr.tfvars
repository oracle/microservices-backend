# Copyright (c) 2024, 2026, Oracle and/or its affiliates.
# All rights reserved. The Universal Permissive License (UPL), Version 1.0 as shown at http://oss.oracle.com/licenses/upl
# spell-checker: disable

region          = "uk-london-1"
label_prefix    = "obaasdr"
fsdr_enabled    = true
# The standby region must differ from region and have a READY tenancy subscription.
fsdr_region_1   = "eu-frankfurt-1"
fsdr_plan_types = ["SWITCHOVER", "FAILOVER", "START_DRILL", "STOP_DRILL"]
fsdr_timeouts = {
  create = "40m"
  update = "40m"
  delete = "40m"
}

# Increment after protection group changes.
fsdr_plan_refresh_trigger = 0
fsdr_plan_verify_trigger  = 0

# Optional application DNS record initially pointing to the primary.
# fsdr_dns_zone_ocid = "<oci-public-dns-zone-ocid>"
# fsdr_dns_name      = "obaas.example.com"

# Enable after validating recovery with a drill.
# fsdr_automatic_dr = {
#   is_auto_switchover_enabled = true
#   is_auto_failover_enabled   = true
# }

# Applying this entry submits a precheck.
# fsdr_plan_executions = {
#   switchover = { plan_execution_type = "SWITCHOVER_PRECHECK" }
# }
