variable "subscription_id" {
  type        = string
  description = "Existing approved workload subscription. This root does not create or move it."
}

variable "tenant_id" {
  type        = string
  description = "Existing Microsoft Entra tenant ID."
}

variable "scope" {
  type        = string
  description = "Workload abbreviation; 3-7 lowercase alphanumeric characters."

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{2,6}$", var.scope))
    error_message = "Use 3-7 lowercase alphanumeric characters beginning with a letter."
  }
}

variable "region_alias" {
  type        = string
  description = "Approved CAF region alias, for example eus."
}

variable "location" {
  type        = string
  description = "Approved Azure region, matching the existing agent VNet."
}

variable "environment" {
  type        = string
  description = "Actual environment boundary, for example dev or prd."
}

variable "name_suffix" {
  type        = string
  description = "Stable 4-6 character suffix for globally unique service names."

  validation {
    condition     = can(regex("^[a-z0-9]{4,6}$", var.name_suffix))
    error_message = "Use 4-6 lowercase alphanumeric characters, not a timestamp."
  }

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", "st${var.scope}${var.region_alias}${var.environment}${var.name_suffix}"))
    error_message = "The storage name composed from st, scope, region_alias, environment and name_suffix must be 3-24 lowercase letters or numbers. Shorten the inputs or remove invalid characters."
  }
}

variable "agent_subnet_resource_id" {
  type        = string
  description = "Existing dedicated Microsoft.App/environments subnet; /24 recommended."
}

variable "private_endpoint_subnet_resource_id" {
  type        = string
  description = "Existing private-endpoint subnet, distinct from the agent subnet."

  validation {
    condition     = lower(var.private_endpoint_subnet_resource_id) != lower(var.agent_subnet_resource_id)
    error_message = "The agent and private-endpoint subnets must be different."
  }
}

variable "private_dns_zone_resource_group_id" {
  type        = string
  description = "Existing platform resource group containing the six standard private DNS zones."
}

variable "log_analytics_workspace_resource_id" {
  type        = string
  description = "Existing approved central Log Analytics workspace; its owner controls retention and access."
}

variable "foundry_log_categories" {
  type        = set(string)
  default     = ["Audit"]
  description = "Foundry audit baseline; excludes RequestResponse and Trace. Review payload sensitivity and retention before adoption."
}

variable "runtime_log_categories" {
  type = object({
    cosmos = optional(set(string), ["ControlPlaneRequests"])
    search = optional(set(string), ["OperationLogs"])
    blob   = optional(set(string), ["StorageRead", "StorageWrite", "StorageDelete"])
  })
  default     = {}
  description = "Service-specific diagnostic categories. Operation logs can include identifiers, paths and query terms; approve their destination/access. Empty sets disable those logs."
}

variable "model_name" {
  type        = string
  description = "Approved model available in the chosen region."
}

variable "model_version" {
  type        = string
  description = "Explicit model version checked against current availability."
}

variable "model_capacity" {
  type        = number
  default     = 1
  description = "Starting deployment capacity in the model's quota units; verify model-specific limits."
}

variable "builder_group_ids" {
  type        = set(string)
  default     = []
  description = "Stable Entra groups receiving project Foundry User and parent Reader."
}

variable "consumer_group_ids" {
  type        = set(string)
  default     = []
  description = "Stable Entra groups receiving project Foundry Agent Consumer only."
}

variable "tags" {
  type        = map(string)
  description = "Approved ownership and classification tags; do not put sensitive data in tags."
}

variable "deployed_by_repo" {
  type        = string
  description = "Adopting repository's non-secret owner/name for resource provenance."
}