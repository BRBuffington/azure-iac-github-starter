mock_provider "azurerm" {}

override_module {
  target = module.spoke
  outputs = {
    resource_id = "/example/vnet"
    subnets = {
      agents            = { resource_id = "/example/vnet/subnets/agents" }
      private_endpoints = { resource_id = "/example/vnet/subnets/private-endpoints" }
    }
  }
}

override_module {
  target = module.network_security_group
  outputs = {
    resource_id = "/example/created-nsg"
  }
}

override_module {
  target = module.agent_route_table
  outputs = {
    resource_id = "/example/created-route-table"
  }
}

variables {
  subscription_id                  = "00000000-0000-0000-0000-000000000000"
  tenant_id                        = "11111111-1111-1111-1111-111111111111"
  resource_group_id                = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network"
  scope                            = "aidemo"
  region_alias                     = "eus"
  environment                      = "dev"
  location                         = "eastus"
  vnet_address_space               = "10.40.0.0/22"
  agent_subnet_cidr                = "10.40.0.0/24"
  private_endpoint_subnet_cidr     = "10.40.1.0/24"
  hub_vnet_resource_id             = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-hub/providers/Microsoft.Network/virtualNetworks/vnet-hub"
  dns_server_ips                   = ["10.10.0.4"]
  agent_nsg_resource_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/networkSecurityGroups/nsg-agents"
  private_endpoint_nsg_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/networkSecurityGroups/nsg-private-endpoints"
  agent_route_table_resource_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/routeTables/rt-platform-egress"
  tags                             = { Owner = "platform-team" }
  deployed_by_repo                 = "example-org/azure-network-reference"
}

run "isolated_subnets_preserve_platform_ownership" {
  command = plan

  assert {
    condition = (
      local.subnets.agents.delegations[0].service_delegation.name == "Microsoft.App/environments" &&
      !local.subnets.agents.default_outbound_access_enabled &&
      !local.subnets.private_endpoints.default_outbound_access_enabled &&
      local.subnets.private_endpoints.private_endpoint_network_policies == "NetworkSecurityGroupEnabled"
    )
    error_message = "Dedicated agent and protected endpoint subnets must not gain default public egress."
  }

  assert {
    condition = (
      length(module.network_security_group) == 0 &&
      length(module.agent_route_table) == 0 &&
      !local.peerings.hub.create_reverse_peering &&
      !local.peerings.hub.allow_gateway_transit &&
      !local.peerings.hub.use_remote_gateways &&
      local.subnets.agents.route_table.id == var.agent_route_table_resource_id
    )
    error_message = "Hub changes remain with the platform owner and workload egress uses its approved route table."
  }
}

run "create_recommended_network_controls" {
  command = plan

  variables {
    agent_nsg_resource_id            = null
    private_endpoint_nsg_resource_id = null
    agent_route_table_resource_id    = null
    firewall_private_ip              = "10.10.1.4"
    approved_client_cidrs            = ["10.20.1.0/24"]
    cosmos_direct_endpoint_ips       = ["10.40.1.5", "10.40.1.6"]
  }

  assert {
    condition = (
      length(module.network_security_group) == 2 &&
      length(module.agent_route_table) == 1 &&
      local.subnets.agents.network_security_group.id == module.network_security_group["agents"].resource_id &&
      local.subnets.private_endpoints.network_security_group.id == module.network_security_group["private_endpoints"].resource_id &&
      local.subnets.agents.route_table.id == module.agent_route_table["agents"].resource_id
    )
    error_message = "Missing network controls must be created and connected to their owning subnets."
  }

  assert {
    condition = (
      local.agent_nsg_rules.dns_udp.protocol == "Udp" &&
      local.agent_nsg_rules.dns_tcp.destination_port_range == "53" &&
      local.agent_nsg_rules.entra.destination_address_prefix == "AzureActiveDirectory" &&
      local.agent_nsg_rules.entra.destination_port_range == "443" &&
      local.agent_nsg_rules.private_https.destination_address_prefix == var.private_endpoint_subnet_cidr &&
      local.agent_nsg_rules.deny_outbound.access == "Deny" &&
      local.agent_nsg_rules.deny_outbound.priority == 4096
    )
    error_message = "Agent rules must allow DNS, Entra and private HTTPS before denying other traffic."
  }

  assert {
    condition = (
      local.private_endpoint_nsg_rules.approved_https.source_address_prefixes == toset([var.agent_subnet_cidr, "10.20.1.0/24"]) &&
      local.private_endpoint_nsg_rules.cosmos_direct.source_address_prefix == var.agent_subnet_cidr &&
      local.private_endpoint_nsg_rules.cosmos_direct.destination_address_prefixes == toset(["10.40.1.5", "10.40.1.6"]) &&
      local.private_endpoint_nsg_rules.cosmos_direct.destination_port_range == "0-65535" &&
      local.private_endpoint_nsg_rules.deny_inbound.priority == 4096
    )
    error_message = "Client HTTPS and Cosmos Direct permissions must remain source/destination scoped."
  }

  assert {
    condition = (
      local.agent_routes.default.address_prefix == "0.0.0.0/0" &&
      local.agent_routes.default.next_hop_type == "VirtualAppliance" &&
      local.agent_routes.default.next_hop_in_ip_address == "10.10.1.4"
    )
    error_message = "Agent default egress must use the supplied existing firewall address."
  }
}

run "reject_missing_firewall_next_hop" {
  command = plan
  variables {
    agent_route_table_resource_id = null
  }
  expect_failures = [var.firewall_private_ip]
}

run "reject_overlapping_subnets" {
  command = plan
  variables {
    private_endpoint_subnet_cidr = "10.40.0.128/25"
  }
  expect_failures = [terraform_data.addresses]
}

run "reject_subnet_outside_vnet" {
  command = plan
  variables {
    private_endpoint_subnet_cidr = "10.41.1.0/24"
  }
  expect_failures = [terraform_data.addresses]
}

run "reject_undersized_agent_subnet" {
  command = plan
  variables {
    agent_subnet_cidr = "10.40.0.0/28"
  }
  expect_failures = [var.agent_subnet_cidr]
}