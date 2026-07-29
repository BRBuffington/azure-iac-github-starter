variable "subscription_id" {
  type        = string
  description = "Consumer Azure subscription GUID where private endpoints and optional DNS resources are deployed."

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.subscription_id))
    error_message = "subscription_id must be an Azure subscription GUID."
  }
}

variable "location" {
  type        = string
  description = "Azure region for consumer-side private endpoints and the optional DNS Resolver."
}

variable "name_prefix" {
  type        = string
  description = "Short, client-neutral prefix used in resource names."

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,30}$", var.name_prefix))
    error_message = "name_prefix must be 2-31 lowercase letters, numbers, or hyphens."
  }
}

variable "private_endpoint_resource_group_name" {
  type        = string
  description = "Existing consumer resource group for private endpoints."
}

variable "private_endpoint_subnet_id" {
  type        = string
  description = "Consumer subnet resource ID from which private endpoint addresses are allocated."
}

variable "consumer_virtual_network_id" {
  type        = string
  description = "Consumer virtual network resource ID linked to newly created private DNS zones."
}

variable "private_dns_zone_resource_group_id" {
  type        = string
  description = "Existing resource group ID for standard Private DNS zones."
  default     = null
  nullable    = true
}

variable "existing_dfs_private_dns_zone_id" {
  type        = string
  description = "Optional existing privatelink.dfs.core.windows.net zone ID."
  default     = null
  nullable    = true

  validation {
    condition = var.existing_dfs_private_dns_zone_id == null || can(regex(
      "(?i)^/subscriptions/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/resourceGroups/[^/]+/providers/Microsoft\\.Network/privateDnsZones/privatelink\\.dfs\\.core\\.windows\\.net$",
      var.existing_dfs_private_dns_zone_id
    ))
    error_message = "existing_dfs_private_dns_zone_id must identify privatelink.dfs.core.windows.net."
  }
}

variable "existing_blob_private_dns_zone_id" {
  type        = string
  description = "Optional existing privatelink.blob.core.windows.net zone ID."
  default     = null
  nullable    = true

  validation {
    condition = var.existing_blob_private_dns_zone_id == null || can(regex(
      "(?i)^/subscriptions/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/resourceGroups/[^/]+/providers/Microsoft\\.Network/privateDnsZones/privatelink\\.blob\\.core\\.windows\\.net$",
      var.existing_blob_private_dns_zone_id
    ))
    error_message = "existing_blob_private_dns_zone_id must identify privatelink.blob.core.windows.net."
  }
}

variable "existing_sql_private_dns_zone_id" {
  type        = string
  description = "Optional existing privatelink.database.windows.net zone ID."
  default     = null
  nullable    = true

  validation {
    condition = var.existing_sql_private_dns_zone_id == null || can(regex(
      "(?i)^/subscriptions/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/resourceGroups/[^/]+/providers/Microsoft\\.Network/privateDnsZones/privatelink\\.database\\.windows\\.net$",
      var.existing_sql_private_dns_zone_id
    ))
    error_message = "existing_sql_private_dns_zone_id must identify privatelink.database.windows.net."
  }
}

variable "provider_storage_account_id" {
  type        = string
  description = "Optional full resource ID of the provider Storage account. Creates both DFS and Blob Private Endpoints."
  default     = null
  nullable    = true
}

variable "provider_sql_server_id" {
  type        = string
  description = "Optional full resource ID of the provider Azure SQL logical server."
  default     = null
  nullable    = true
}

variable "deploy_dns_resolver" {
  type        = bool
  description = "Deploy an Azure DNS Private Resolver in an existing consumer VNet."
  default     = false
}

variable "dns_resolver_name" {
  type        = string
  description = "Optional DNS Resolver name."
  default     = null
  nullable    = true
}

variable "dns_resolver_resource_group_name" {
  type        = string
  description = "Optional existing resource group for the DNS Resolver. Defaults to the private endpoint resource group."
  default     = null
  nullable    = true
}

variable "dns_resolver_virtual_network_id" {
  type        = string
  description = "Optional VNet resource ID for the DNS Resolver. Defaults to consumer_virtual_network_id."
  default     = null
  nullable    = true
}

variable "dns_resolver_inbound_subnet_name" {
  type        = string
  description = "Existing empty, delegated subnet name for the resolver inbound endpoint."
  default     = null
  nullable    = true

  validation {
    condition     = !var.deploy_dns_resolver || var.dns_resolver_inbound_subnet_name != null
    error_message = "dns_resolver_inbound_subnet_name is required when deploy_dns_resolver is true."
  }
}

variable "dns_resolver_inbound_ip" {
  type        = string
  description = "Optional static inbound endpoint IP. A static address is recommended for enterprise DNS forwarding."
  default     = null
  nullable    = true

  validation {
    condition     = var.dns_resolver_inbound_ip == null || can(cidrnetmask("${var.dns_resolver_inbound_ip}/32"))
    error_message = "dns_resolver_inbound_ip must be a valid IPv4 address when supplied."
  }
}

variable "dns_resolver_outbound_subnet_name" {
  type        = string
  description = "Optional existing empty, delegated subnet name for the resolver outbound endpoint."
  default     = null
  nullable    = true

  validation {
    condition = (
      length(var.enterprise_dns_server_ip_addresses) == 0 ||
      (var.deploy_dns_resolver && var.dns_resolver_outbound_subnet_name != null)
    )
    error_message = "deploy_dns_resolver and dns_resolver_outbound_subnet_name are required when enterprise DNS server IPs are supplied."
  }
}

variable "enterprise_forwarding_domain_name" {
  type        = string
  description = "Optional enterprise-owned DNS suffix forwarded from Azure, including the trailing period."
  default     = null
  nullable    = true

  validation {
    condition = var.enterprise_forwarding_domain_name == null || !anytrue([
      for azure_zone in [
        "privatelink.dfs.core.windows.net.",
        "privatelink.blob.core.windows.net.",
        "privatelink.database.windows.net.",
        "dfs.core.windows.net.",
        "blob.core.windows.net.",
        "database.windows.net."
      ] : endswith(lower(var.enterprise_forwarding_domain_name), azure_zone)
    ])
    error_message = "Resolver outbound rules are only for enterprise-owned namespaces. Azure service and privatelink zones remain consumer-local."
  }

  validation {
    condition     = var.enterprise_forwarding_domain_name == null || endswith(var.enterprise_forwarding_domain_name, ".")
    error_message = "enterprise_forwarding_domain_name must be a fully qualified domain ending with a period."
  }
}

variable "enterprise_dns_server_ip_addresses" {
  type        = set(string)
  description = "Optional central DNS server IPv4 addresses for the enterprise forwarding domain. DNS port 53 is applied locally."
  default     = []

  validation {
    condition     = alltrue([for ip_address in var.enterprise_dns_server_ip_addresses : can(cidrnetmask("${ip_address}/32"))])
    error_message = "Every enterprise DNS server address must be a valid IPv4 address."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to supported resources."
  default     = {}
}
