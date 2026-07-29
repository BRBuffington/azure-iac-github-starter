locals {
  private_endpoint_targets = merge(
    var.provider_storage_account_id == null ? {} : {
      storage_dfs = {
        provider_resource_id = var.provider_storage_account_id
        subresource_name     = "dfs"
        dns_family           = "dfs"
        request_message      = "Cross-tenant DFS private endpoint request"
      }
      storage_blob = {
        provider_resource_id = var.provider_storage_account_id
        subresource_name     = "blob"
        dns_family           = "blob"
        request_message      = "Cross-tenant Blob private endpoint request"
      }
    },
    var.provider_sql_server_id == null ? {} : {
      sql_server = {
        provider_resource_id = var.provider_sql_server_id
        subresource_name     = "sqlServer"
        dns_family           = "sql"
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

  provider_storage_account_name = var.provider_storage_account_id == null ? null : basename(var.provider_storage_account_id)
  provider_sql_server_name      = var.provider_sql_server_id == null ? null : basename(var.provider_sql_server_id)

  prefixed_private_dns_zone_keys = {
    dfs  = "${replace(var.prefixed_dns_label, "-", "_")}_dfs"
    blob = "${replace(var.prefixed_dns_label, "-", "_")}_blob"
    sql  = "${replace(var.prefixed_dns_label, "-", "_")}_sql"
  }

  prefixed_private_dns_zones = merge(
    var.provider_storage_account_id == null ? {} : {
      (local.prefixed_private_dns_zone_keys.dfs) = {
        domain_name                 = "${var.prefixed_dns_label}.privatelink.dfs.core.windows.net"
        private_endpoint_target_key = "storage_dfs"
        records = {
          (local.provider_storage_account_name) = {
            private_endpoint_target_key = "storage_dfs"
            ttl                         = var.private_dns_record_ttl
          }
        }
      }
      (local.prefixed_private_dns_zone_keys.blob) = {
        domain_name                 = "${var.prefixed_dns_label}.privatelink.blob.core.windows.net"
        private_endpoint_target_key = "storage_blob"
        records = {
          (local.provider_storage_account_name) = {
            private_endpoint_target_key = "storage_blob"
            ttl                         = var.private_dns_record_ttl
          }
        }
      }
    },
    var.provider_sql_server_id == null ? {} : {
      (local.prefixed_private_dns_zone_keys.sql) = {
        domain_name                 = "${var.prefixed_dns_label}.privatelink.database.windows.net"
        private_endpoint_target_key = "sql_server"
        records = {
          (local.provider_sql_server_name) = {
            private_endpoint_target_key = "sql_server"
            ttl                         = var.private_dns_record_ttl
          }
        }
      }
    }
  )

  approved_private_endpoint_target_keys_valid = length(setsubtract(
    var.approved_private_endpoint_target_keys,
    toset(keys(local.private_endpoint_targets))
  )) == 0

  dns_publication_configuration_valid = length(var.approved_private_endpoint_target_keys) == 0 || var.prefixed_dns_zone_resource_group_id != null

  private_endpoint_targets_to_create = local.provider_resource_ids_valid ? local.private_endpoint_targets : {}
  prefixed_private_dns_zones_to_publish = local.provider_resource_ids_valid && local.dns_publication_configuration_valid ? {
    for key, zone in local.prefixed_private_dns_zones : key => zone
    if contains(var.approved_private_endpoint_target_keys, zone.private_endpoint_target_key)
  } : {}

  avm_tags = merge(var.tags, {
    LastAppliedStamp = "Disabled"
  })

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
