# These outputs are the exact inputs the parent hub-canonical-zones root expects.

output "hub_virtual_network_id" {
  description = "Feed to hub_virtual_network_id."
  value       = module.hub_virtual_network.resource_id
}

output "spoke_virtual_networks" {
  description = "Feed to spoke_virtual_networks."
  value = {
    sample-spoke = {
      virtual_network_id = module.spoke_virtual_network.resource_id
    }
  }
}

output "private_dns_zone_resource_group_id" {
  description = "Feed to private_dns_zone_resource_group_id."
  value       = azurerm_resource_group.dns.id
}

output "dns_resolver_resource_group_name" {
  description = "Feed to dns_resolver_resource_group_name."
  value       = azurerm_resource_group.hub.name
}

output "dns_resolver_inbound_subnet_name" {
  description = "Feed to dns_resolver_inbound_subnet_name."
  value       = "snet-dnsr-inbound"
}

output "parent_tfvars_snippet" {
  description = "Paste-ready tfvars fragment for the parent root."
  value       = <<-EOT
    hub_virtual_network_id             = "${module.hub_virtual_network.resource_id}"
    private_dns_zone_resource_group_id = "${azurerm_resource_group.dns.id}"
    dns_resolver_resource_group_name   = "${azurerm_resource_group.hub.name}"
    dns_resolver_inbound_subnet_name   = "snet-dnsr-inbound"

    spoke_virtual_networks = {
      sample-spoke = {
        virtual_network_id = "${module.spoke_virtual_network.resource_id}"
      }
    }
  EOT
}
