locals {
  prefix = "${var.scope}-${var.region_alias}-${var.environment}"
  common_tags = merge(var.tags, {
    Environment      = var.environment
    DeployedByRepo   = var.deployed_by_repo
    LastAppliedStamp = "Disabled"
  })
  subnets = {
    agents = {
      name                            = "snet-agents"
      address_prefixes                = [var.agent_subnet_cidr]
      default_outbound_access_enabled = false
      network_security_group          = { id = local.agent_nsg_id }
      route_table                     = { id = local.agent_route_table_id }
      delegations = [{
        name               = "foundry-agents"
        service_delegation = { name = "Microsoft.App/environments" }
      }]
    }
    private_endpoints = {
      name                              = "snet-private-endpoints"
      address_prefixes                  = [var.private_endpoint_subnet_cidr]
      default_outbound_access_enabled   = false
      private_endpoint_network_policies = "NetworkSecurityGroupEnabled"
      network_security_group            = { id = local.private_endpoint_nsg_id }
    }
  }
  peerings = {
    hub = {
      name                               = "spoke-to-hub"
      remote_virtual_network_resource_id = var.hub_vnet_resource_id
      allow_virtual_network_access       = true
      allow_forwarded_traffic            = true
      allow_gateway_transit              = false
      use_remote_gateways                = var.use_remote_gateways
      create_reverse_peering             = false
    }
  }
  subnet_cidrs = [var.agent_subnet_cidr, var.private_endpoint_subnet_cidr]
  common_prefix_length = min(
    tonumber(split("/", var.agent_subnet_cidr)[1]),
    tonumber(split("/", var.private_endpoint_subnet_cidr)[1])
  )

  allow_agent_tcp = {
    access                = "Allow"
    direction             = "Outbound"
    protocol              = "Tcp"
    source_address_prefix = var.agent_subnet_cidr
    source_port_range     = "*"
  }
  deny_all = {
    access                     = "Deny"
    protocol                   = "*"
    source_address_prefix      = "*"
    source_port_range          = "*"
    destination_address_prefix = "*"
    destination_port_range     = "*"
    priority                   = 4096
  }
  platform_https_destinations = {
    entra             = { priority = 200, tag = "AzureActiveDirectory" }
    registry          = { priority = 210, tag = "MicrosoftContainerRegistry" }
    registry_delivery = { priority = 220, tag = "AzureFrontDoor.FirstParty" }
    monitor           = { priority = 230, tag = "AzureMonitor" }
  }
  cosmos_direct_rules = length(var.cosmos_direct_endpoint_ips) == 0 ? {} : {
    cosmos_direct = merge(local.allow_agent_tcp, {
      name                         = "AllowCosmosDirect"
      priority                     = 130
      destination_address_prefixes = var.cosmos_direct_endpoint_ips
      destination_port_range       = "0-65535"
    })
  }
  agent_nsg_rules = merge({
    subnet_inbound = {
      name                       = "AllowAgentSubnetInbound"
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "*"
      source_address_prefix      = var.agent_subnet_cidr
      source_port_range          = "*"
      destination_address_prefix = var.agent_subnet_cidr
      destination_port_range     = "*"
    }
    load_balancer = {
      name                       = "AllowPlatformHealthProbes"
      priority                   = 110
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_address_prefix      = "AzureLoadBalancer"
      source_port_range          = "*"
      destination_address_prefix = var.agent_subnet_cidr
      destination_port_range     = "30000-32767"
    }
    dns_udp = merge(local.allow_agent_tcp, {
      name                         = "AllowDnsUdp"
      priority                     = 100
      protocol                     = "Udp"
      destination_address_prefixes = var.dns_server_ips
      destination_port_range       = "53"
    })
    dns_tcp = merge(local.allow_agent_tcp, {
      name                         = "AllowDnsTcp"
      priority                     = 110
      destination_address_prefixes = var.dns_server_ips
      destination_port_range       = "53"
    })
    private_https = merge(local.allow_agent_tcp, {
      name                       = "AllowPrivateEndpointHttps"
      priority                   = 120
      destination_address_prefix = var.private_endpoint_subnet_cidr
      destination_port_range     = "443"
    })
    subnet_outbound = merge(local.allow_agent_tcp, {
      name                       = "AllowAgentSubnetOutbound"
      priority                   = 140
      protocol                   = "*"
      destination_address_prefix = var.agent_subnet_cidr
      destination_port_range     = "*"
    })
    deny_inbound  = merge(local.deny_all, { name = "DenyOtherInbound", direction = "Inbound" })
    deny_outbound = merge(local.deny_all, { name = "DenyOtherOutbound", direction = "Outbound" })
    }, local.cosmos_direct_rules, {
    for key, destination in local.platform_https_destinations : key => merge(local.allow_agent_tcp, {
      name                       = "Allow-${key}-Https"
      priority                   = destination.priority
      destination_address_prefix = destination.tag
      destination_port_range     = "443"
    })
  })
  private_endpoint_nsg_rules = merge({
    approved_https = {
      name                       = "AllowApprovedClientsHttps"
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_address_prefixes    = setunion([var.agent_subnet_cidr], var.approved_client_cidrs)
      source_port_range          = "*"
      destination_address_prefix = var.private_endpoint_subnet_cidr
      destination_port_range     = "443"
    }
    deny_inbound  = merge(local.deny_all, { name = "DenyOtherInbound", direction = "Inbound" })
    deny_outbound = merge(local.deny_all, { name = "DenyOtherOutbound", direction = "Outbound" })
    }, {
    for key, rule in local.cosmos_direct_rules : key => merge(rule, { direction = "Inbound" })
  })
  network_security_groups = {
    for key, group in {
      agents            = { existing_id = var.agent_nsg_resource_id, rules = local.agent_nsg_rules }
      private_endpoints = { existing_id = var.private_endpoint_nsg_resource_id, rules = local.private_endpoint_nsg_rules }
    } : key => group if group.existing_id == null
  }
  agent_routes = {
    default = {
      name                   = "default-to-platform-firewall"
      address_prefix         = "0.0.0.0/0"
      next_hop_type          = "VirtualAppliance"
      next_hop_in_ip_address = var.firewall_private_ip
    }
  }
  route_tables = {
    for key in ["agents"] : key => local.agent_routes if var.agent_route_table_resource_id == null
  }
  agent_nsg_id            = var.agent_nsg_resource_id != null ? var.agent_nsg_resource_id : module.network_security_group["agents"].resource_id
  private_endpoint_nsg_id = var.private_endpoint_nsg_resource_id != null ? var.private_endpoint_nsg_resource_id : module.network_security_group["private_endpoints"].resource_id
  agent_route_table_id    = var.agent_route_table_resource_id != null ? var.agent_route_table_resource_id : module.agent_route_table["agents"].resource_id
}