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

variable "dns_architecture" {
  type        = string
  description = "DNS record ownership model: standard_contexts uses Azure-managed standard zone groups; prefixed_backing uses Terraform-managed custom backing-zone records."
  default     = "standard_contexts"

  validation {
    condition     = contains(["standard_contexts", "prefixed_backing"], var.dns_architecture)
    error_message = "dns_architecture must be standard_contexts or prefixed_backing."
  }
}

variable "private_dns_zone_resource_group_id" {
  type        = string
  description = "Existing resource group ID for private DNS zones. Required when any standard zone is created by this example."
  default     = null
  nullable    = true

  validation {
    condition = var.dns_architecture == "prefixed_backing" ? (
      !var.publish_prefixed_dns_records || var.private_dns_zone_resource_group_id != null
      ) : (
      var.private_dns_zone_resource_group_id != null || alltrue([
        for key in distinct([for target in values(var.private_endpoint_targets) : target.private_dns_zone_key]) :
        contains(keys(var.existing_private_dns_zone_ids), key)
      ])
    )
    error_message = "private_dns_zone_resource_group_id is required for prefixed backing zones and for every standard zone not supplied in existing_private_dns_zone_ids."
  }
}

variable "publish_prefixed_dns_records" {
  type        = bool
  description = "Create prefixed backing zones and records after provider-side Private Endpoint approval has been verified."
  default     = false

  validation {
    condition     = var.dns_architecture == "prefixed_backing" || !var.publish_prefixed_dns_records
    error_message = "publish_prefixed_dns_records can be true only when dns_architecture is prefixed_backing."
  }
}

variable "existing_private_dns_zone_ids" {
  type        = map(string)
  description = "Existing consumer private DNS zone IDs keyed by dfs, blob, or sql. Existing zones must already be linked to the consumer VNet."
  default     = {}

  validation {
    condition = alltrue([
      for key in keys(var.existing_private_dns_zone_ids) : contains(["dfs", "blob", "sql"], key)
    ])
    error_message = "existing_private_dns_zone_ids keys must be dfs, blob, or sql."
  }

  validation {
    condition     = var.dns_architecture == "standard_contexts" || length(var.existing_private_dns_zone_ids) == 0
    error_message = "existing_private_dns_zone_ids applies only to the standard_contexts architecture."
  }
}

variable "private_endpoint_targets" {
  type = map(object({
    provider_resource_id = string
    subresource_name     = string
    private_dns_zone_key = string
    request_message      = optional(string, "Cross-tenant private endpoint request")
  }))
  description = "Provider resource IDs and subresources. Use dfs and blob for ADLS Gen2, and sqlServer for Azure SQL."

  validation {
    condition     = length(var.private_endpoint_targets) > 0
    error_message = "private_endpoint_targets must contain at least one consumer-side private endpoint."
  }

  validation {
    condition = alltrue([
      for target in values(var.private_endpoint_targets) :
      contains(["dfs", "blob", "sqlServer"], target.subresource_name)
    ])
    error_message = "subresource_name must be dfs, blob, or sqlServer for this starter."
  }

  validation {
    condition = alltrue([
      for target in values(var.private_endpoint_targets) :
      target.private_dns_zone_key == {
        dfs       = "dfs"
        blob      = "blob"
        sqlServer = "sql"
      }[target.subresource_name]
    ])
    error_message = "private_dns_zone_key must match the subresource: dfs=dfs, blob=blob, and sqlServer=sql."
  }

  validation {
    condition = alltrue([
      for target in values(var.private_endpoint_targets) :
      can(regex(
        target.subresource_name == "sqlServer" ?
        "(?i)^/subscriptions/[0-9a-f-]{36}/resourceGroups/[^/]+/providers/Microsoft\\.Sql/servers/[^/]+$" :
        "(?i)^/subscriptions/[0-9a-f-]{36}/resourceGroups/[^/]+/providers/Microsoft\\.Storage/storageAccounts/[^/]+$",
        target.provider_resource_id
      ))
    ])
    error_message = "provider_resource_id must be a full Storage account ID for dfs/blob or a full SQL logical-server ID for sqlServer."
  }

  validation {
    condition = alltrue([
      for target in values(var.private_endpoint_targets) :
      target.subresource_name != "dfs" || anytrue([
        for companion in values(var.private_endpoint_targets) :
        companion.provider_resource_id == target.provider_resource_id && companion.subresource_name == "blob"
      ])
    ])
    error_message = "Every ADLS Gen2 dfs target must include a blob target for the same Storage account."
  }

  validation {
    condition = alltrue([
      for target in values(var.private_endpoint_targets) : length(target.request_message) <= 128
    ])
    error_message = "request_message must be 128 characters or fewer so it is valid for Azure SQL and Storage."
  }
}

variable "prefixed_private_dns_zones" {
  type = map(object({
    domain_name = string
    records = map(object({
      private_endpoint_target_key = string
      ttl                         = optional(number, 60)
    }))
  }))
  description = "Custom tenant- or region-prefixed backing zones and explicit A records. Used only with dns_architecture=prefixed_backing."
  default     = {}

  validation {
    condition = (
      var.dns_architecture == "prefixed_backing" && (
        !var.publish_prefixed_dns_records || length(var.prefixed_private_dns_zones) > 0
      )
      ) || (
      var.dns_architecture == "standard_contexts" && length(var.prefixed_private_dns_zones) == 0
    )
    error_message = "prefixed_private_dns_zones applies only to prefixed_backing and must be non-empty when record publication is enabled."
  }

  validation {
    condition = alltrue([
      for zone in values(var.prefixed_private_dns_zones) : can(regex(
        "(?i)^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)*\\.privatelink\\.(?:(?:dfs|blob)\\.core\\.windows\\.net|database\\.windows\\.net)$",
        zone.domain_name
      ))
    ])
    error_message = "Each prefixed domain_name must add at least one label before a supported standard privatelink DFS, Blob, or SQL zone suffix."
  }

  validation {
    condition = alltrue(flatten([
      for zone in values(var.prefixed_private_dns_zones) : [
        for record_name, record in zone.records :
        can(regex("^[a-z0-9][a-z0-9-]{0,62}$", record_name)) && record.ttl >= 30 && record.ttl <= 86400
      ]
    ]))
    error_message = "Prefixed record names must be DNS labels and TTLs must be between 30 and 86400 seconds."
  }

  validation {
    condition = alltrue(flatten([
      for zone in values(var.prefixed_private_dns_zones) : [
        for record in values(zone.records) : try(
          endswith(lower(zone.domain_name), {
            dfs  = ".privatelink.dfs.core.windows.net"
            blob = ".privatelink.blob.core.windows.net"
            sql  = ".privatelink.database.windows.net"
          }[var.private_endpoint_targets[record.private_endpoint_target_key].private_dns_zone_key]),
          false
        )
      ]
    ]))
    error_message = "Every prefixed record must reference an existing private endpoint target whose DFS, Blob, or SQL family matches the zone suffix."
  }
}

variable "approved_private_endpoint_target_keys" {
  type        = set(string)
  description = "Endpoint target keys independently verified as Approved before custom prefixed records are published."
  default     = []

  validation {
    condition = alltrue([
      for key in var.approved_private_endpoint_target_keys : contains(keys(var.private_endpoint_targets), key)
    ])
    error_message = "Every approved_private_endpoint_target_keys value must exist in private_endpoint_targets."
  }

  validation {
    condition = !var.publish_prefixed_dns_records || alltrue(flatten([
      for zone in values(var.prefixed_private_dns_zones) : [
        for record in values(zone.records) : contains(
          var.approved_private_endpoint_target_keys,
          record.private_endpoint_target_key
        )
      ]
    ]))
    error_message = "Every prefixed record target must be listed in approved_private_endpoint_target_keys before publication."
  }
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
      length(var.enterprise_forwarding_rules) == 0 ||
      (var.deploy_dns_resolver && var.dns_resolver_outbound_subnet_name != null)
    )
    error_message = "deploy_dns_resolver and dns_resolver_outbound_subnet_name are required when enterprise_forwarding_rules are supplied."
  }
}

variable "enterprise_forwarding_rules" {
  type = map(object({
    domain_name              = string
    destination_ip_addresses = map(string)
  }))
  description = "Optional enterprise-owned namespaces forwarded from Azure to central DNS. Map each DNS server IP to port 53 as a string."
  default     = {}

  validation {
    condition = alltrue([
      for rule in values(var.enterprise_forwarding_rules) : !anytrue([
        for azure_zone in [
          "privatelink.dfs.core.windows.net.",
          "privatelink.blob.core.windows.net.",
          "privatelink.database.windows.net.",
          "dfs.core.windows.net.",
          "blob.core.windows.net.",
          "database.windows.net."
        ] : endswith(lower(rule.domain_name), azure_zone)
      ])
    ])
    error_message = "Resolver outbound rules are only for enterprise-owned namespaces. Azure service and privatelink zones remain consumer-local."
  }

  validation {
    condition = alltrue([
      for rule in values(var.enterprise_forwarding_rules) : endswith(rule.domain_name, ".")
    ])
    error_message = "Every forwarding-rule domain_name must be a fully qualified domain ending with a period."
  }

  validation {
    condition = alltrue(flatten([
      for rule in values(var.enterprise_forwarding_rules) : [
        for ip_address, port in rule.destination_ip_addresses :
        can(cidrnetmask("${ip_address}/32")) && port == "53"
      ]
    ]))
    error_message = "Every forwarding-rule destination must map a valid IPv4 address to DNS port 53."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to supported resources."
  default     = {}
}
