output "private_endpoint_ids" {
  description = "Consumer-side private endpoint resource IDs, keyed by target."
  value       = { for key, endpoint in azurerm_private_endpoint.cross_tenant : key => endpoint.id }
}

output "private_endpoint_private_ip_addresses" {
  description = "Consumer-local private endpoint IP addresses for post-approval validation."
  value = {
    for key, endpoint in azurerm_private_endpoint.cross_tenant :
    key => endpoint.private_service_connection[0].private_ip_address
  }
}

output "private_dns_zone_ids" {
  description = "Requested or supplied consumer-owned private DNS zone IDs keyed by dfs, blob, or sql."
  value       = local.private_dns_zone_ids
}

output "dns_resolver_inbound_endpoints" {
  description = "Optional DNS Resolver inbound endpoint outputs for enterprise DNS forwarding."
  value       = var.deploy_dns_resolver ? module.dns_resolver[0].inbound_endpoints : {}
}