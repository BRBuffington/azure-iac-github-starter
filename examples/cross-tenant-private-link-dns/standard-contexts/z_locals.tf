locals {
  standard_private_dns_zones = {
    dfs  = "privatelink.dfs.core.windows.net"
    blob = "privatelink.blob.core.windows.net"
    sql  = "privatelink.database.windows.net"
  }

  existing_private_dns_zone_ids = {
    for key, zone_id in {
      dfs  = var.existing_dfs_private_dns_zone_id
      blob = var.existing_blob_private_dns_zone_id
      sql  = var.existing_sql_private_dns_zone_id
    } : key => zone_id if zone_id != null
  }

  private_endpoint_targets = merge(
    var.provider_storage_account_id == null ? {} : {
      storage_dfs = {
        provider_resource_id = var.provider_storage_account_id
        subresource_name     = "dfs"
        private_dns_zone_key = "dfs"
        request_message      = "Cross-tenant DFS private endpoint request"
      }
      storage_blob = {
        provider_resource_id = var.provider_storage_account_id
        subresource_name     = "blob"
        private_dns_zone_key = "blob"
        request_message      = "Cross-tenant Blob private endpoint request"
      }
    },
    var.provider_sql_server_id == null ? {} : {
      sql_server = {
        provider_resource_id = var.provider_sql_server_id
        subresource_name     = "sqlServer"
        private_dns_zone_key = "sql"
        request_message      = "Cross-tenant SQL private endpoint request"
      }
    }
  )

  provider_resource_ids_valid = (
    (var.provider_storage_account_id == null || can(regex(
      "(?i)^/subscriptions/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/resourceGroups/[^/]+/providers/Microsoft\\.Storage/storageAccounts/[^/]+$",
      var.provider_storage_account_id
    ))) &&
    (var.provider_sql_server_id == null || can(regex(
      "(?i)^/subscriptions/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/resourceGroups/[^/]+/providers/Microsoft\\.Sql/servers/[^/]+$",
      var.provider_sql_server_id
    )))
  )

  avm_tags = merge(var.tags, {
    LastAppliedStamp = "Disabled"
  })

  requested_private_dns_zone_keys = toset([
    for target in values(local.private_endpoint_targets) : target.private_dns_zone_key
  ])

  private_dns_zones_required = {
    for key, domain_name in local.standard_private_dns_zones : key => domain_name
    if contains(local.requested_private_dns_zone_keys, key) && !contains(keys(local.existing_private_dns_zone_ids), key)
  }

  standard_dns_configuration_valid = var.private_dns_zone_resource_group_id != null || length(local.private_dns_zones_required) == 0
  private_dns_zones_to_create      = local.standard_dns_configuration_valid ? local.private_dns_zones_required : {}
  private_endpoint_targets_to_create = (
    local.provider_resource_ids_valid && local.standard_dns_configuration_valid
  ) ? local.private_endpoint_targets : {}

  private_dns_zone_ids = merge(
    local.existing_private_dns_zone_ids,
    { for key, zone in module.private_dns_zone : key => zone.resource_id }
  )

  enterprise_forwarding_rules = var.enterprise_forwarding_domain_name == null ? {} : {
    enterprise = {
      domain_name = var.enterprise_forwarding_domain_name
      destination_ip_addresses = {
        for ip_address in var.enterprise_dns_server_ip_addresses : ip_address => "53"
      }
    }
  }

  enterprise_forwarding_valid = (
    (var.enterprise_forwarding_domain_name == null && length(var.enterprise_dns_server_ip_addresses) == 0) ||
    (var.enterprise_forwarding_domain_name != null && length(var.enterprise_dns_server_ip_addresses) > 0)
  )

  resolver_outbound_endpoints = local.enterprise_forwarding_valid && var.deploy_dns_resolver && var.dns_resolver_outbound_subnet_name != null ? {
    default = {
      name        = "out-${var.name_prefix}"
      subnet_name = var.dns_resolver_outbound_subnet_name
      forwarding_ruleset = length(local.enterprise_forwarding_rules) > 0 ? {
        enterprise = {
          name = "rules-${var.name_prefix}"
          rules = {
            for key, rule in local.enterprise_forwarding_rules : key => {
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
