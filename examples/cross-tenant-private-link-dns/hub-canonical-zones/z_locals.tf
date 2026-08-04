locals {
  # Canonical Private Link zone names. Azure's Private Endpoint CNAME chain always
  # targets these exact suffixes, so a prefixed variant is never queried by a
  # standard client and cannot be substituted here.
  canonical_private_dns_zones = {
    dfs  = "privatelink.dfs.core.windows.net"
    blob = "privatelink.blob.core.windows.net"
    sql  = "privatelink.database.windows.net"
  }

  private_dns_zones_required = {
    for key, domain_name in local.canonical_private_dns_zones : key => domain_name
    if contains(var.canonical_zone_keys, key)
  }

  # The zone's resource group name, parsed from the supplied resource group ID.
  # Explicit link resources address the zone by name, not by ID.
  private_dns_zone_resource_group_name = element(split("/", var.private_dns_zone_resource_group_id), 4)

  # One link per zone per spoke network. Flattened so each link is a discrete
  # resource instance rather than a nested module argument.
  spoke_zone_links = {
    for pair in setproduct(keys(local.private_dns_zones_to_create), keys(var.spoke_virtual_networks)) :
    "${pair[0]}-${pair[1]}" => {
      zone_key           = pair[0]
      spoke_key          = pair[1]
      domain_name        = local.private_dns_zones_to_create[pair[0]]
      virtual_network_id = var.spoke_virtual_networks[pair[1]].virtual_network_id
    }
  }

  # Every linked network, for the output and for reasoning about blast radius.
  linked_virtual_network_ids = merge(
    { hub = var.hub_virtual_network_id },
    { for key, spoke in var.spoke_virtual_networks : key => spoke.virtual_network_id },
  )

  # Records are grouped per zone so each zone module owns only its own record set.
  published_records_by_zone = {
    for zone_key in keys(local.private_dns_zones_required) : zone_key => {
      for record_key, record in var.published_endpoint_records : record_key => {
        name    = record.record_name
        ttl     = 300
        records = [record.private_ip_address]
      }
      if record.zone_key == zone_key
    }
  }

  # Fail closed: a record aimed at a zone this root is not hosting would silently
  # never be published.
  published_records_target_hosted_zones = alltrue([
    for record in values(var.published_endpoint_records) :
    contains(keys(local.private_dns_zones_required), record.zone_key)
  ])

  # ADLS Gen2 operations redirect between the blob and dfs endpoints, so hosting one
  # without the other resolves half the traffic privately and half publicly.
  adls_zone_pairing_valid = (
    contains(var.canonical_zone_keys, "dfs") == contains(var.canonical_zone_keys, "blob")
  )

  spoke_links_are_unique = length(distinct([
    for spoke in values(var.spoke_virtual_networks) : lower(spoke.virtual_network_id)
  ])) == length(var.spoke_virtual_networks)

  resolver_configuration_valid = (
    !var.deploy_dns_resolver ||
    (var.dns_resolver_resource_group_name != null && var.dns_resolver_inbound_subnet_name != null)
  )

  configuration_valid = (
    local.published_records_target_hosted_zones &&
    local.adls_zone_pairing_valid &&
    local.spoke_links_are_unique &&
    local.resolver_configuration_valid
  )

  private_dns_zones_to_create = local.configuration_valid ? local.private_dns_zones_required : {}

  avm_tags = merge(var.tags, {
    LastAppliedStamp = "Disabled"
  })

  private_dns_zone_ids = {
    for key, zone in module.private_dns_zone : key => zone.resource_id
  }
}
