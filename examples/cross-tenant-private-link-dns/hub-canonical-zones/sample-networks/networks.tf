locals {
  # /26 is the smallest subnet Azure DNS Private Resolver accepts for an inbound
  # endpoint, and the subnet must be empty and delegated to the resolver.
  hub_inbound_subnet_cidr  = cidrsubnet(var.hub_address_space, 4, 0)
  hub_workload_subnet_cidr = cidrsubnet(var.hub_address_space, 4, 1)
  spoke_workload_cidr      = cidrsubnet(var.spoke_address_space, 4, 0)
}

resource "azurerm_resource_group" "hub" {
  name     = "rg-${var.name_prefix}-hub"
  location = var.location
  tags     = var.tags
}

resource "azurerm_resource_group" "spoke" {
  name     = "rg-${var.name_prefix}-spoke"
  location = var.location
  tags     = var.tags
}

# The hub resource group that will hold the canonical private DNS zones. Kept
# separate from the network group so zone ownership and network ownership can be
# delegated to different teams.
resource "azurerm_resource_group" "dns" {
  name     = "rg-${var.name_prefix}-dns"
  location = var.location
  tags     = var.tags
}

# Terraform MCP catalog source:
# Azure/avm-res-network-virtualnetwork/azurerm, version 0.11.0.
module "hub_virtual_network" {
  # checkov:skip=CKV_TF_1:Official AVM Registry module pinned to an exact release.
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "0.11.0"

  name          = "vnet-${var.name_prefix}-hub"
  location      = var.location
  parent_id     = azurerm_resource_group.hub.id
  address_space = [var.hub_address_space]
  tags          = var.tags

  subnets = {
    dnsr_inbound = {
      name             = "snet-dnsr-inbound"
      address_prefixes = [local.hub_inbound_subnet_cidr]

      # Required for the resolver inbound endpoint. Without this delegation the
      # resolver cannot bind and the enterprise forwarder has no target.
      delegation = [{
        name = "Microsoft.Network.dnsResolvers"
        service_delegation = {
          name = "Microsoft.Network/dnsResolvers"
        }
      }]
    }

    workload = {
      name             = "snet-workload"
      address_prefixes = [local.hub_workload_subnet_cidr]
    }
  }
}

module "spoke_virtual_network" {
  # checkov:skip=CKV_TF_1:Official AVM Registry module pinned to an exact release.
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "0.11.0"

  name          = "vnet-${var.name_prefix}-spoke"
  location      = var.location
  parent_id     = azurerm_resource_group.spoke.id
  address_space = [var.spoke_address_space]
  tags          = var.tags

  subnets = {
    workload = {
      name             = "snet-workload"
      address_prefixes = [local.spoke_workload_cidr]
    }
  }
}
