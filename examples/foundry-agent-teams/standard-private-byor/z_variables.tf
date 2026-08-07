variable "subscription_id" {
  type        = string
  description = "Azure subscription that owns the Foundry and Bot Service resources."

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.subscription_id))
    error_message = "subscription_id must be a GUID."
  }
}

variable "tenant_id" {
  type        = string
  description = "Microsoft Entra tenant ID used by the SingleTenant Bot Service."

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.tenant_id))
    error_message = "tenant_id must be a GUID."
  }
}

variable "location" {
  type        = string
  description = "Azure region shared by the Microsoft Foundry account and existing virtual network."
}

variable "resource_group_name" {
  type        = string
  description = "Resource group created for the Foundry account, project, Bot Service, and private endpoints."
}

variable "base_name" {
  type        = string
  description = "Short deterministic prefix used by the Foundry AVM composition."

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,19}$", var.base_name))
    error_message = "base_name must contain 2-20 lowercase letters, numbers, or hyphens."
  }
}

variable "foundry_account_name" {
  type        = string
  description = "Globally unique Microsoft Foundry account name."

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,62}$", var.foundry_account_name))
    error_message = "foundry_account_name must contain 2-63 lowercase letters, numbers, or hyphens."
  }
}

variable "project_name" {
  type        = string
  description = "Microsoft Foundry project name."

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{1,62}$", var.project_name))
    error_message = "project_name must contain 2-63 letters, numbers, underscores, or hyphens."
  }
}

variable "project_display_name" {
  type        = string
  description = "Display name for the Microsoft Foundry project."
}

variable "model_deployment_name" {
  type        = string
  description = "Name exposed to Prompt Agent definitions for the deployed model."
}

variable "model_name" {
  type        = string
  description = "Microsoft Foundry model catalog name."
}

variable "model_version" {
  type        = string
  description = "Pinned model version available in the selected region."
}

variable "model_sku" {
  type        = string
  description = "Model deployment SKU, such as GlobalStandard."
  default     = "GlobalStandard"
}

variable "model_capacity" {
  type        = number
  description = "Model deployment capacity in provider-defined units."
  default     = 1

  validation {
    condition     = var.model_capacity > 0
    error_message = "model_capacity must be greater than zero."
  }
}

variable "agent_subnet_resource_id" {
  type        = string
  description = "Dedicated /27-or-larger subnet delegated to Microsoft.App/environments for Foundry agent compute."
}

variable "private_endpoint_subnet_resource_id" {
  type        = string
  description = "Subnet that hosts private endpoints for Foundry and BYOR dependencies."
}

variable "mcp_subnet_resource_id" {
  type        = string
  description = "Separate subnet delegated to Microsoft.App/environments that hosts the internal MCP service."
}

variable "storage_account_resource_id" {
  type        = string
  description = "Existing customer-owned Storage account resource ID for agent files and state."
}

variable "cosmos_db_resource_id" {
  type        = string
  description = "Existing customer-owned Cosmos DB account resource ID for agent conversations."
}

variable "ai_search_resource_id" {
  type        = string
  description = "Existing customer-owned Azure AI Search resource ID for vector stores."
}

variable "key_vault_resource_id" {
  type        = string
  description = "Existing customer-owned Key Vault resource ID used by the Foundry composition."
}

variable "foundry_private_dns_zone_resource_ids" {
  type        = list(string)
  description = "Existing private DNS zone IDs for cognitiveservices, openai, and services.ai."

  validation {
    condition     = length(var.foundry_private_dns_zone_resource_ids) == 3
    error_message = "Provide exactly three Foundry private DNS zone resource IDs."
  }
}

variable "storage_blob_private_dns_zone_resource_id" {
  type        = string
  description = "Existing privatelink.blob.core.windows.net zone resource ID."
}

variable "cosmos_db_private_dns_zone_resource_id" {
  type        = string
  description = "Existing privatelink.documents.azure.com zone resource ID."
}

variable "ai_search_private_dns_zone_resource_id" {
  type        = string
  description = "Existing privatelink.search.windows.net zone resource ID."
}

variable "key_vault_private_dns_zone_resource_id" {
  type        = string
  description = "Existing privatelink.vaultcore.azure.net zone resource ID."
}

variable "agent_publications" {
  type = map(object({
    principal_id = string
    bot_name     = string
    display_name = optional(string)
  }))
  description = <<-EOT
    Prompt Agent names mapped to the instance identity principal ID returned by
    Foundry after data-plane agent creation. Keep this map empty for the first
    infrastructure apply, then populate it for the reviewed Bot Service plan.
  EOT
  default     = {}

  validation {
    condition = alltrue([
      for agent_name, publication in var.agent_publications :
      can(regex("^[A-Za-z0-9][A-Za-z0-9-]{0,63}$", agent_name)) &&
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", publication.principal_id)) &&
      can(regex("^[A-Za-z0-9][A-Za-z0-9._-]{1,41}$", publication.bot_name))
    ])
    error_message = "Each publication needs a safe agent name, GUID principal_id, and 2-42 character Bot Service name."
  }
}

variable "tags" {
  type        = map(string)
  description = "Additional tags merged with the starter's provenance tags."
  default     = {}
}