output "private_dns_zone_ids" {
  description = "Canonical hub private DNS zone IDs keyed by dfs, blob, or sql."
  value       = local.private_dns_zone_ids
}

output "linked_virtual_network_ids" {
  description = "Virtual networks holding a resolution-only link to every canonical zone, keyed by link label."
  value       = { for key, link in local.virtual_network_links : key => link.virtual_network_id }
}

output "published_record_fqdns" {
  description = "Canonical FQDNs published for Private Endpoints owned outside the hub, with their private IPs."
  value = {
    for key, record in var.published_endpoint_records :
    key => {
      fqdn               = "${record.record_name}.${local.canonical_private_dns_zones[record.zone_key]}"
      private_ip_address = record.private_ip_address
    }
  }
}

output "dns_resolver_inbound_endpoints" {
  description = "Shared inbound endpoint for enterprise DNS forwarding. Forward the canonical suffixes only to these addresses."
  value       = var.deploy_dns_resolver ? module.dns_resolver[0].inbound_endpoints : {}
}

output "enterprise_forwarding_domains" {
  description = "Exact suffixes enterprise DNS should conditionally forward to this resolver."
  value       = values(local.private_dns_zones_required)
}
