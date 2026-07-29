# Terraform MCP catalog source:
# Azure/avm-res-network-privatednszone/azurerm, version 0.5.0.
module "prefixed_private_dns_zone" {
  # checkov:skip=CKV_TF_1:Official AVM Registry module pinned to the exact 0.5.0 release returned by Terraform MCP.
  for_each = local.prefixed_private_dns_zones_to_publish

  source  = "Azure/avm-res-network-privatednszone/azurerm"
  version = "0.5.0"

  domain_name = each.value.domain_name
  parent_id   = var.prefixed_dns_zone_resource_group_id
  tags        = local.avm_tags

  a_records = {
    for record_name, record in each.value.records : record_name => {
      name = record_name
      ttl  = record.ttl
      ip_addresses = toset([
        azurerm_private_endpoint.cross_tenant[record.private_endpoint_target_key].private_service_connection[0].private_ip_address
      ])
    }
  }

  virtual_network_links = {
    consumer = {
      name                                   = "link-${var.name_prefix}-${each.key}"
      virtual_network_id                     = var.consumer_virtual_network_id
      registration_enabled                   = false
      private_dns_zone_supports_private_link = false
    }
  }

  depends_on = [terraform_data.configuration_guard]
}
