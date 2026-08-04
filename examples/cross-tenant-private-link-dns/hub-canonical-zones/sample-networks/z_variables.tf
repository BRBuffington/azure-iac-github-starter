variable "subscription_id" {
  type        = string
  description = "Azure subscription GUID for these sample networks."

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.subscription_id))
    error_message = "subscription_id must be an Azure subscription GUID."
  }
}

variable "location" {
  type        = string
  description = "Azure region for the sample networks."
  default     = "centralus"
}

variable "name_prefix" {
  type        = string
  description = "Short, client-neutral prefix used in resource names."
  default     = "dnslab"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,20}$", var.name_prefix))
    error_message = "name_prefix must be 2-21 lowercase letters, numbers, or hyphens."
  }
}

variable "hub_address_space" {
  type        = string
  description = "Hub virtual network CIDR. Must be large enough for the resolver inbound subnet."
  default     = "10.90.0.0/22"

  validation {
    condition     = can(cidrhost(var.hub_address_space, 0))
    error_message = "hub_address_space must be a valid CIDR block."
  }
}

variable "spoke_address_space" {
  type        = string
  description = "Spoke virtual network CIDR. Must not overlap the hub."
  default     = "10.91.0.0/22"

  validation {
    condition     = can(cidrhost(var.spoke_address_space, 0))
    error_message = "spoke_address_space must be a valid CIDR block."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to the sample networks."
  default     = {}
}
