# Zone links are explicit resources rather than a nested module argument so the
# cross-tenant credential seam is visible and reviewable, and so each link shows
# up as its own plan entry.
#
# One link per zone per network. The hub link uses the default provider because
# it never crosses a tenant boundary. Spoke links use the cross_tenant alias,
# which is the same credential unless cross_tenant_tenant_id is set.
#
# registration_enabled is false everywhere on purpose: a Private Link zone must
# never absorb spoke virtual machine records.

resource "azurerm_private_dns_zone_virtual_network_link" "hub" {
  for_each = local.private_dns_zones_to_create

  name                  = "link-${var.name_prefix}-hub"
  resource_group_name   = local.private_dns_zone_resource_group_name
  private_dns_zone_name = each.value
  virtual_network_id    = var.hub_virtual_network_id
  registration_enabled  = false
  tags                  = local.avm_tags

  depends_on = [module.private_dns_zone]
}

resource "azurerm_private_dns_zone_virtual_network_link" "spoke" {
  provider = azurerm.cross_tenant

  for_each = local.spoke_zone_links

  name                  = "link-${var.name_prefix}-${each.value.spoke_key}"
  resource_group_name   = local.private_dns_zone_resource_group_name
  private_dns_zone_name = each.value.domain_name
  virtual_network_id    = each.value.virtual_network_id
  registration_enabled  = false
  tags                  = local.avm_tags

  depends_on = [module.private_dns_zone]
}
