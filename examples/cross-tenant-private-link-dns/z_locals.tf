locals {
  standard_private_dns_zones = {
    dfs  = "privatelink.dfs.core.windows.net"
    blob = "privatelink.blob.core.windows.net"
    sql  = "privatelink.database.windows.net"
  }

  avm_tags = merge(var.tags, {
    LastAppliedStamp = "Disabled"
  })

  requested_private_dns_zone_keys = toset([
    for target in values(var.private_endpoint_targets) : target.private_dns_zone_key
  ])

  private_dns_zones_to_create = var.dns_architecture == "standard_contexts" ? {
    for key, domain_name in local.standard_private_dns_zones : key => domain_name
    if contains(local.requested_private_dns_zone_keys, key) && !contains(keys(var.existing_private_dns_zone_ids), key)
  } : {}

  private_dns_zone_ids = var.dns_architecture == "standard_contexts" ? merge(
    var.existing_private_dns_zone_ids,
    { for key, zone in module.private_dns_zone : key => zone.resource_id }
  ) : {}

  resolver_outbound_endpoints = var.deploy_dns_resolver && var.dns_resolver_outbound_subnet_name != null ? {
    default = {
      name        = "out-${var.name_prefix}"
      subnet_name = var.dns_resolver_outbound_subnet_name
      forwarding_ruleset = length(var.enterprise_forwarding_rules) > 0 ? {
        enterprise = {
          name = "rules-${var.name_prefix}"
          rules = {
            for key, rule in var.enterprise_forwarding_rules : key => {
              name                     = "rule-${replace(key, "_", "-")}"
              domain_name              = rule.domain_name
              destination_ip_addresses = rule.destination_ip_addresses
            }
          }
        }
      } : {}
    }
  } : {}
}
