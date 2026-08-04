# Terraform MCP catalog source:
# Azure/avm-res-network-dnsresolver/azurerm, version 0.8.0.
#
# One shared inbound endpoint. Enterprise DNS forwards the canonical Private Link
# suffixes here and nowhere else, which is what removes the per-tenant forwarder
# split. Outbound endpoints and forwarding rulesets are deliberately absent:
# cross-tenant ruleset linking is not supported, so a ruleset here would not reach
# spoke tenants and would reintroduce the split this root exists to remove.
module "dns_resolver" {
  # checkov:skip=CKV_TF_1:Official AVM Registry module pinned to the exact 0.8.0 release returned by Terraform MCP.
  count = var.deploy_dns_resolver ? 1 : 0

  source  = "Azure/avm-res-network-dnsresolver/azurerm"
  version = "0.8.0"

  name                        = coalesce(var.dns_resolver_name, "dnsr-${var.name_prefix}")
  location                    = var.location
  resource_group_name         = var.dns_resolver_resource_group_name
  virtual_network_resource_id = var.hub_virtual_network_id
  tags                        = local.avm_tags

  inbound_endpoints = {
    default = {
      name                         = "in-${var.name_prefix}"
      subnet_name                  = var.dns_resolver_inbound_subnet_name
      private_ip_allocation_method = "Dynamic"
    }
  }

  depends_on = [terraform_data.configuration_guard]
}
