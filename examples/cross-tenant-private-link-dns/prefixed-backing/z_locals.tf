locals {
  avm_tags = merge(var.tags, {
    LastAppliedStamp = "Disabled"
  })

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
