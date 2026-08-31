locals {
  name_suffix = "${var.scope}-${var.region_alias}-${var.environment}"

  names = {
    dependency_nsg        = "nsg-${local.name_suffix}-runner-dependencies"
    dependency_subnet     = "snet-${local.name_suffix}-runner-dependencies"
    network_configuration = "ghnet-${local.name_suffix}"
    network_settings      = "github-network-settings-${local.name_suffix}"
    runner                = "ghr-${local.name_suffix}"
    runner_group          = "ghrg-${local.name_suffix}"
    runner_nsg            = "nsg-${local.name_suffix}-github-runners"
    runner_subnet         = "snet-${local.name_suffix}-github-runners"
    vnet                  = "vnet-${local.name_suffix}-runners"
  }

  common_tags = merge(var.tags, {
    DeployedByRepo   = var.deployed_by_repo
    Environment      = var.environment
    LastAppliedStamp = "Disabled"
  })

  runner_nsg_rules = {
    deny_all_inbound = {
      access                     = "Deny"
      description                = "GitHub requires no inbound connections to hosted runners."
      destination_address_prefix = "*"
      destination_port_range     = "*"
      direction                  = "Inbound"
      name                       = "DenyAllInbound"
      priority                   = 100
      protocol                   = "*"
      source_address_prefix      = "*"
      source_port_range          = "*"
    }
  }

  approved_dependency_nsg_rules = {
    for name, dependency in var.approved_private_dependencies : name => {
      access                       = "Allow"
      description                  = "Approved runner access to the ${name} private dependency."
      destination_address_prefixes = dependency.destination_address_prefixes
      destination_port_ranges      = dependency.destination_port_ranges
      direction                    = "Inbound"
      name                         = "Allow-${name}"
      priority                     = 100 + index(sort(keys(var.approved_private_dependencies)), name)
      protocol                     = "Tcp"
      source_address_prefix        = var.runner_subnet_cidr
      source_port_range            = "*"
    }
  }

  dependency_nsg_rules = merge(local.approved_dependency_nsg_rules, {
    deny_all_inbound = {
      access                     = "Deny"
      description                = "Dependencies remain unreachable until an approved path is added."
      destination_address_prefix = "*"
      destination_port_range     = "*"
      direction                  = "Inbound"
      name                       = "DenyAllInbound"
      priority                   = 4096
      protocol                   = "*"
      source_address_prefix      = "*"
      source_port_range          = "*"
    }
  })

  subnets = {
    runners = {
      name                            = local.names.runner_subnet
      address_prefixes                = [var.runner_subnet_cidr]
      default_outbound_access_enabled = false
      delegations = [{
        name = "github-network-settings"
        service_delegation = {
          name = "GitHub.Network/networkSettings"
        }
      }]
      network_security_group = {
        id = module.runner_nsg.resource_id
      }
      route_table = {
        id = var.route_table_resource_id
      }
    }
    dependencies = {
      name                              = local.names.dependency_subnet
      address_prefixes                  = [var.dependency_subnet_cidr]
      default_outbound_access_enabled   = false
      private_endpoint_network_policies = "Enabled"
      network_security_group = {
        id = module.dependency_nsg.resource_id
      }
      route_table = {
        id = var.route_table_resource_id
      }
    }
  }

  runner_subnet_prefix_length    = tonumber(split("/", var.runner_subnet_cidr)[1])
  runner_subnet_usable_addresses = pow(2, 32 - local.runner_subnet_prefix_length) - 5
  required_runner_addresses      = ceil(var.maximum_runners * 1.3)
}
