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

output "prefixed_private_dns_zone_ids" {
  description = "Terraform-owned custom backing-zone IDs keyed by configured zone key."
  value       = { for key, zone in module.prefixed_private_dns_zone : key => zone.resource_id }
}

output "prefixed_private_dns_records" {
  description = "Custom backing-record contract for configuring and validating the enterprise DNS standard-name bridge."
  value = {
    for zone_key, zone in var.prefixed_private_dns_zones : zone_key => {
      domain_name = zone.domain_name
      records = {
        for record_name, record in zone.records : record_name => {
          fqdn                        = "${record_name}.${zone.domain_name}"
          private_endpoint_target_key = record.private_endpoint_target_key
          private_ip_address          = azurerm_private_endpoint.cross_tenant[record.private_endpoint_target_key].private_service_connection[0].private_ip_address
          ttl                         = record.ttl
        }
      }
    }
  }
}

output "dns_resolver_inbound_endpoints" {
  description = "Optional DNS Resolver inbound endpoint outputs for enterprise DNS integration."
  value       = var.deploy_dns_resolver ? module.dns_resolver[0].inbound_endpoints : {}
}
