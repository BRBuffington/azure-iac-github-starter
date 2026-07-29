# Custom backing zones are not part of Azure's standard Private Endpoint DNS
# integration. Terraform owns these records, while enterprise DNS owns the
# exact standard-name bridge and any health-aware selection policy.
resource "terraform_data" "dns_publication_gate" {
  count = var.publish_dns_records ? 1 : 0

  lifecycle {
    precondition {
      condition = alltrue(flatten([
        for zone in values(var.prefixed_private_dns_zones) : [
          for record in values(zone.records) : contains(
            var.approved_private_endpoint_target_keys,
            record.private_endpoint_target_key
          )
        ]
      ]))
      error_message = "Verify every provider-side connection is Approved before publishing prefixed DNS records."
    }
  }
}

# Terraform MCP catalog source:
# Azure/avm-res-network-privatednszone/azurerm, version 0.5.0.
module "prefixed_private_dns_zone" {
  # checkov:skip=CKV_TF_1:Official AVM Registry module pinned to the exact 0.5.0 release returned by Terraform MCP.
  for_each = var.publish_dns_records ? var.prefixed_private_dns_zones : {}

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

  depends_on = [terraform_data.dns_publication_gate]
}
