module "network_security_group" {
  for_each = local.network_security_groups
  source   = "Azure/avm-res-network-networksecuritygroup/azurerm"
  version  = "0.5.1"

  name                = "nsg-${local.prefix}-${replace(each.key, "_", "-")}"
  location            = var.location
  resource_group_name = basename(var.resource_group_id)
  security_rules      = each.value.rules
  tags                = local.common_tags
  enable_telemetry    = false
}

module "agent_route_table" {
  for_each = local.route_tables
  source   = "Azure/avm-res-network-routetable/azurerm"
  version  = "0.5.0"

  name                          = "rt-${local.prefix}-egress"
  location                      = var.location
  resource_group_name           = basename(var.resource_group_id)
  bgp_route_propagation_enabled = false
  routes                        = each.value
  tags                          = local.common_tags
  enable_telemetry              = false
}