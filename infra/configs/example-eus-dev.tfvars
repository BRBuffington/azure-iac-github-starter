# Config naming: configs/<scope>-<region>-<env>.tfvars
#   scope        = workload / sub-stack (hub, platform, avd, ...)
#   region alias = eus (eastus), eus2 (eastus2), wus (westus), cus (centralus), ...
#   env          = LAST so `*-dev.tfvars` / `*-prd.tfvars` glob across regions
#
# A security posture or feature flag is a VARIABLE in one config, NOT a second
# config. Two configs mean two genuinely separate deployments, each with its own
# state file.

subscription_id = "<target-subscription-guid>"
scope           = "example"
region_alias    = "eus"
environment     = "dev"
location        = "eastus"

tags = {
  workload    = "landing-zone"
  environment = "dev"
  managed_by  = "terraform"
}
