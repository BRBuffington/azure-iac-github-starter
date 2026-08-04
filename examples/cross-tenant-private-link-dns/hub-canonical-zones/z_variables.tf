variable "subscription_id" {
  type        = string
  description = "Hub Azure subscription GUID that owns the canonical Private DNS zones and the shared DNS Resolver."

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.subscription_id))
    error_message = "subscription_id must be an Azure subscription GUID."
  }
}

variable "location" {
  type        = string
  description = "Azure region for the shared DNS Resolver."
}

variable "name_prefix" {
  type        = string
  description = "Short, client-neutral prefix used in resource names."

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,30}$", var.name_prefix))
    error_message = "name_prefix must be 2-31 lowercase letters, numbers, or hyphens."
  }
}

variable "private_dns_zone_resource_group_id" {
  type        = string
  description = "Existing hub resource group ID that holds the canonical Private DNS zones."

  validation {
    condition = can(regex(
      "(?i)^/subscriptions/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/resourceGroups/[^/]+$",
      var.private_dns_zone_resource_group_id
    ))
    error_message = "private_dns_zone_resource_group_id must be a resource group resource ID."
  }
}

variable "hub_virtual_network_id" {
  type        = string
  description = "Hub virtual network resource ID. Hosts the DNS Resolver inbound endpoint and receives a resolution-only zone link."

  validation {
    condition = can(regex(
      "(?i)^/subscriptions/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+$",
      var.hub_virtual_network_id
    ))
    error_message = "hub_virtual_network_id must be a virtual network resource ID."
  }
}

# Genuine caller-owned collection: arbitrary cardinality, one entry per spoke
# network that must resolve the canonical zones. Cross-tenant entries are the
# reason this root exists; same-tenant spokes are equally valid.
variable "spoke_virtual_networks" {
  type = map(object({
    virtual_network_id = string
  }))
  description = <<-EOT
    Spoke virtual networks that receive a resolution-only link to the canonical zones,
    keyed by a short caller-chosen label. A virtual network in another Microsoft Entra
    tenant is supported: the deploying identity must hold write permission on both the
    private DNS zone and that virtual network, in both tenants.
  EOT
  default     = {}

  validation {
    condition = alltrue([
      for spoke in values(var.spoke_virtual_networks) : can(regex(
        "(?i)^/subscriptions/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+$",
        spoke.virtual_network_id
      ))
    ])
    error_message = "Every spoke_virtual_networks entry must supply a virtual network resource ID."
  }

  validation {
    condition     = alltrue([for key in keys(var.spoke_virtual_networks) : can(regex("^[a-z0-9][a-z0-9-]{0,30}$", key))])
    error_message = "spoke_virtual_networks keys must be 1-31 lowercase letters, numbers, or hyphens."
  }
}

# A resolution-only link lets a spoke QUERY the zone. It does not register that
# spoke's Private Endpoint records. Records for endpoints owned outside the hub
# must be published here explicitly, or the zone answers NXDOMAIN for them.
variable "published_endpoint_records" {
  type = map(object({
    zone_key           = string
    record_name        = string
    private_ip_address = string
  }))
  description = <<-EOT
    Canonical A records to publish into the hub zones for Private Endpoints owned by
    another tenant or subscription. zone_key is one of dfs, blob, or sql. record_name is
    the resource label only, without the zone suffix, for example the storage account name.
  EOT
  default     = {}

  validation {
    condition     = alltrue([for record in values(var.published_endpoint_records) : contains(["dfs", "blob", "sql"], record.zone_key)])
    error_message = "published_endpoint_records zone_key must be dfs, blob, or sql."
  }

  validation {
    condition = alltrue([
      for record in values(var.published_endpoint_records) :
      can(regex("^[a-z0-9][a-z0-9-]{0,62}$", record.record_name))
    ])
    error_message = "published_endpoint_records record_name must be a bare label with no zone suffix."
  }

  validation {
    condition = alltrue([
      for record in values(var.published_endpoint_records) :
      can(cidrhost("${record.private_ip_address}/32", 0))
    ])
    error_message = "published_endpoint_records private_ip_address must be a valid IPv4 address."
  }
}

variable "canonical_zone_keys" {
  type        = set(string)
  description = "Canonical Private Link zones to host in the hub. Any of dfs, blob, or sql."
  default     = ["dfs", "blob"]

  validation {
    condition     = length(var.canonical_zone_keys) > 0
    error_message = "Select at least one canonical zone."
  }

  validation {
    condition     = alltrue([for key in var.canonical_zone_keys : contains(["dfs", "blob", "sql"], key)])
    error_message = "canonical_zone_keys entries must be dfs, blob, or sql."
  }
}

variable "cross_tenant_tenant_id" {
  type        = string
  description = <<-EOT
    Optional Microsoft Entra tenant GUID to authenticate the cross_tenant provider
    alias, which creates the spoke zone links. Leave null when one identity already
    holds write permission on the private DNS zone and on every spoke virtual
    network across both tenants; the alias then behaves exactly like the default
    provider. Set it to pin link creation to a multi-tenant service principal or a
    B2B guest that spans the tenants.
  EOT
  default     = null
  nullable    = true

  validation {
    condition = var.cross_tenant_tenant_id == null || can(regex(
      "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$",
      var.cross_tenant_tenant_id
    ))
    error_message = "cross_tenant_tenant_id must be a Microsoft Entra tenant GUID when supplied."
  }
}

variable "deploy_dns_resolver" {
  type        = bool
  description = "Deploy the shared Azure DNS Private Resolver in the hub virtual network."
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
  description = "Existing hub resource group name for the DNS Resolver."
  default     = null
  nullable    = true

  validation {
    condition     = !var.deploy_dns_resolver || var.dns_resolver_resource_group_name != null
    error_message = "dns_resolver_resource_group_name is required when deploy_dns_resolver is true."
  }
}

variable "dns_resolver_inbound_subnet_name" {
  type        = string
  description = "Existing empty subnet delegated to Microsoft.Network/dnsResolvers for the inbound endpoint."
  default     = null
  nullable    = true

  validation {
    condition     = !var.deploy_dns_resolver || var.dns_resolver_inbound_subnet_name != null
    error_message = "dns_resolver_inbound_subnet_name is required when deploy_dns_resolver is true."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to resources created by this root."
  default     = {}
}
