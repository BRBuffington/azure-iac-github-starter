# Terraform MCP catalog source:
# Azure/avm-res-network-privatednszone/azurerm, version 0.5.0.
module "private_dns_zone" {
  # checkov:skip=CKV_TF_1:Official AVM Registry module pinned to the exact 0.5.0 release returned by Terraform MCP.
  for_each = local.private_dns_zones_to_create

  source  = "Azure/avm-res-network-privatednszone/azurerm"
  version = "0.5.0"

  domain_name = each.value
  parent_id   = var.private_dns_zone_resource_group_id
  tags        = local.avm_tags

  virtual_network_links = {
    consumer = {
      name                                   = "link-${var.name_prefix}-${each.key}"
      virtual_network_id                     = var.consumer_virtual_network_id
      registration_enabled                   = false
      private_dns_zone_supports_private_link = true
    }
  }
}
