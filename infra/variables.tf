variable "subscription_id" {
  type        = string
  description = "Target Azure subscription GUID."
}

variable "scope" {
  type        = string
  description = "Workload / sub-stack name (e.g. hub, platform, avd)."
}

variable "region_alias" {
  type        = string
  description = "CAF region alias: eus=eastus, eus2=eastus2, wus=westus, cus=centralus, etc."
}

variable "environment" {
  type        = string
  description = "Lifecycle suffix: dev, tst, qa, uat, prd, dr."
}

variable "location" {
  type        = string
  description = "Azure region (e.g. eastus). Must correspond to region_alias."
}

variable "tags" {
  type        = map(string)
  description = "Resource tags."
  default     = {}
}

variable "deployed_by_repo" {
  type        = string
  description = "Owning repository (owner/name), recorded as the DeployedByRepo provenance tag. CI sets this from github.repository; the default covers off-pipeline (local read-only) runs."
  default     = "local"
}
