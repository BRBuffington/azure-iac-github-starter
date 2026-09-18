variable "subscription_id" {
  type        = string
  description = "Existing approved workload-network subscription ID."
}

variable "tenant_id" {
  type        = string
  description = "Existing Microsoft Entra tenant ID."
}

variable "resource_group_id" {
  type        = string
  description = "Existing resource group owned by this network layer."
}

variable "scope" {
  type        = string
  description = "Workload abbreviation used with region_alias and environment."
}

variable "region_alias" {
  type        = string
  description = "Approved CAF region alias."
}

variable "environment" {
  type        = string
  description = "Actual environment boundary, for example dev or prd."
}

variable "location" {
  type        = string
  description = "Approved region for both this VNet and the consuming Foundry account."
}

variable "vnet_address_space" {
  type        = string
  description = "Approved non-overlapping RFC1918 VNet CIDR."

  validation {
    condition     = can(cidrnetmask(var.vnet_address_space))
    error_message = "Supply a valid IPv4 VNet CIDR."
  }
}

variable "agent_subnet_cidr" {
  type        = string
  description = "Dedicated agent subnet CIDR; /24 recommended, /27 minimum for the selected Standard setup."

  validation {
    condition     = try(tonumber(split("/", var.agent_subnet_cidr)[1]) <= 27 && can(cidrnetmask(var.agent_subnet_cidr)), false)
    error_message = "The agent subnet must be valid IPv4 and /27 or larger."
  }
}

variable "private_endpoint_subnet_cidr" {
  type        = string
  description = "Separate CIDR for workload private endpoints."

  validation {
    condition     = can(cidrnetmask(var.private_endpoint_subnet_cidr))
    error_message = "Supply a valid IPv4 private-endpoint subnet CIDR."
  }
}

variable "hub_vnet_resource_id" {
  type        = string
  description = "Existing hub VNet; its owner manages the reverse peering in platform state."
}

variable "dns_server_ips" {
  type        = list(string)
  description = "Existing reachable central DNS resolver addresses with private-zone forwarding."

  validation {
    condition     = length(var.dns_server_ips) > 0
    error_message = "Supply the approved central DNS resolver addresses."
  }
}

variable "agent_nsg_resource_id" {
  type        = string
  default     = null
  description = "Existing agent NSG to reuse unchanged. Null creates the reference rules."
}

variable "private_endpoint_nsg_resource_id" {
  type        = string
  default     = null
  description = "Existing endpoint NSG to reuse unchanged. Null creates the reference rules."
}

variable "agent_route_table_resource_id" {
  type        = string
  default     = null
  description = "Existing agent route table to reuse unchanged. Null creates a default route to firewall_private_ip."
}

variable "firewall_private_ip" {
  type        = string
  default     = null
  description = "Existing hub firewall/appliance next-hop IPv4 address. Required when creating the route table."

  validation {
    condition     = var.agent_route_table_resource_id != null || can(cidrnetmask("${var.firewall_private_ip}/32"))
    error_message = "Supply firewall_private_ip when no existing route table ID is supplied."
  }
}

variable "approved_client_cidrs" {
  type        = set(string)
  default     = []
  description = "Runner and administrator IPv4 CIDRs allowed TCP 443 to workload private endpoints; empty grants no extra clients."

  validation {
    condition     = alltrue([for prefix in var.approved_client_cidrs : can(cidrnetmask(prefix)) && prefix != "0.0.0.0/0"])
    error_message = "Use explicit client IPv4 CIDRs, not a default route."
  }
}

variable "cosmos_direct_endpoint_ips" {
  type        = set(string)
  default     = []
  description = "All Cosmos private-endpoint IPv4 addresses if Direct mode is used. Enables TCP 0-65535 from the agent subnet only; empty leaves HTTPS-only access."

  validation {
    condition     = alltrue([for address in var.cosmos_direct_endpoint_ips : can(cidrnetmask("${address}/32"))])
    error_message = "Supply individual Cosmos private-endpoint IPv4 addresses, not subnets or service tags."
  }
}

variable "use_remote_gateways" {
  type        = bool
  default     = false
  description = "Enable only when the hub owner has approved and enabled gateway transit."
}

variable "tags" {
  type        = map(string)
  description = "Approved resource ownership and classification tags."
}

variable "deployed_by_repo" {
  type        = string
  description = "Adopting repository's non-secret owner/name."
}