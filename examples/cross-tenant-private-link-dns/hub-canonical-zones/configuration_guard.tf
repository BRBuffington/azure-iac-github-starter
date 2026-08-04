resource "terraform_data" "configuration_guard" {
  lifecycle {
    precondition {
      condition     = local.published_records_target_hosted_zones
      error_message = "Every published_endpoint_records entry must target a zone listed in canonical_zone_keys."
    }

    precondition {
      condition     = local.adls_zone_pairing_valid
      error_message = "ADLS Gen2 requires both dfs and blob zones. Select both canonical_zone_keys or neither."
    }

    precondition {
      condition     = local.spoke_links_are_unique
      error_message = "Each virtual network can hold only one link per private DNS zone. Remove the duplicate spoke_virtual_networks entry."
    }

    precondition {
      condition     = local.resolver_configuration_valid
      error_message = "Set dns_resolver_resource_group_name and dns_resolver_inbound_subnet_name when deploy_dns_resolver is true."
    }
  }
}
