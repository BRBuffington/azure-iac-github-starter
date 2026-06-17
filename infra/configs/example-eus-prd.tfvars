# Production config. Note: same physical stack as dev would be a SEPARATE
# deployment (different subscription/resources) — hence its own state file
# (configs/example-eus-prd.tfvars -> <prefix>/example-eus-prd.tfstate). Do NOT
# model dev vs prd as a posture toggle inside one config.

subscription_id = "<prod-subscription-guid>"
scope           = "example"
region_alias    = "eus"
environment     = "prd"
location        = "eastus"

tags = {
  workload    = "landing-zone"
  environment = "prd"
  managed_by  = "terraform"
}
