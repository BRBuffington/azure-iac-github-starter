# Terraform MCP catalog source:
# Azure/avm-res-network-privatednszone/azurerm, version 0.5.0.
#
# One canonical zone per Private Link suffix, hosted in the hub. Every consuming
# network -- hub and spoke, same tenant or another tenant -- receives a
# resolution-only virtual network link to this single authority.
module "private_dns_zone" {
  # checkov:skip=CKV_TF_1:Official AVM Registry module pinned to the exact 0.5.0 release returned by Terraform MCP.
  for_each = local.private_dns_zones_to_create

  source  = "Azure/avm-res-network-privatednszone/azurerm"
  version = "0.5.0"

  domain_name = each.value
  parent_id   = var.private_dns_zone_resource_group_id
  tags        = local.avm_tags

  virtual_network_links = local.virtual_network_links

  # A virtual network link grants resolution, never registration. Private Endpoints
  # owned outside this hub do not self-register here, so their canonical A records
  # are published explicitly.
  a_records = local.published_records_by_zone[each.key]

  depends_on = [terraform_data.configuration_guard]
}
