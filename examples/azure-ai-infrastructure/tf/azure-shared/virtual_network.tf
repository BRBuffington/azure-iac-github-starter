module "spoke" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "0.22.2"

  name             = "vnet-${local.prefix}"
  parent_id        = var.resource_group_id
  location         = var.location
  address_space    = [var.vnet_address_space]
  dns_servers      = { dns_servers = var.dns_server_ips }
  subnets          = local.subnets
  peerings         = local.peerings
  tags             = local.common_tags
  enable_telemetry = false

  depends_on = [terraform_data.addresses]
}

resource "terraform_data" "addresses" {
  input = local.subnet_cidrs

  lifecycle {
    precondition {
      condition = alltrue([
        for subnet in local.subnet_cidrs :
        tonumber(split("/", subnet)[1]) >= tonumber(split("/", var.vnet_address_space)[1]) &&
        cidrhost("${cidrhost(subnet, 0)}/${split("/", var.vnet_address_space)[1]}", 0) == cidrhost(var.vnet_address_space, 0)
      ])
      error_message = "Both subnets must fit within the supplied VNet address space."
    }
    precondition {
      condition = (
        cidrhost("${cidrhost(var.agent_subnet_cidr, 0)}/${local.common_prefix_length}", 0) !=
        cidrhost("${cidrhost(var.private_endpoint_subnet_cidr, 0)}/${local.common_prefix_length}", 0)
      )
      error_message = "Agent and private-endpoint subnets must not overlap."
    }
  }
}