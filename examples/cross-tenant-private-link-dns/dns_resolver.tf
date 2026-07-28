# Terraform MCP catalog source:
# Azure/avm-res-network-dnsresolver/azurerm, version 0.8.0.
module "dns_resolver" {
  # checkov:skip=CKV_TF_1:Official AVM Registry module pinned to the exact 0.8.0 release returned by Terraform MCP.
  count = var.deploy_dns_resolver ? 1 : 0

  source  = "Azure/avm-res-network-dnsresolver/azurerm"
  version = "0.8.0"

  name                        = coalesce(var.dns_resolver_name, "dnsr-${var.name_prefix}")
  location                    = var.location
  resource_group_name         = coalesce(var.dns_resolver_resource_group_name, var.private_endpoint_resource_group_name)
  virtual_network_resource_id = coalesce(var.dns_resolver_virtual_network_id, var.consumer_virtual_network_id)
  tags                        = local.avm_tags

  inbound_endpoints = {
    default = {
      name                         = "in-${var.name_prefix}"
      subnet_name                  = var.dns_resolver_inbound_subnet_name
      private_ip_allocation_method = var.dns_resolver_inbound_ip == null ? "Dynamic" : "Static"
      private_ip_address           = var.dns_resolver_inbound_ip
    }
  }

  outbound_endpoints = local.resolver_outbound_endpoints
}