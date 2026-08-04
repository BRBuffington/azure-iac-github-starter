mock_provider "azapi" {}
mock_provider "azurerm" {}

# The cross_tenant alias creates the spoke links, so it needs its own mock.
mock_provider "azurerm" {
  alias = "cross_tenant"
}

variables {
  subscription_id                    = "00000000-0000-0000-0000-000000000000"
  location                           = "eastus"
  name_prefix                        = "hub-prd"
  private_dns_zone_resource_group_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dns-hub-eus-prd"
  hub_virtual_network_id             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-hub-eus-prd/providers/Microsoft.Network/virtualNetworks/vnet-hub-eus-prd"
}

run "single_authority_for_each_canonical_suffix" {
  command = plan

  assert {
    condition     = length(local.private_dns_zones_to_create) == 2
    error_message = "The default ADLS pairing must create exactly one zone per canonical suffix."
  }

  assert {
    condition = alltrue([
      for domain_name in values(local.private_dns_zones_to_create) : startswith(domain_name, "privatelink.")
    ])
    error_message = "Only canonical privatelink zones belong in this root; a prefixed variant is never queried by a standard client."
  }
}

run "cross_tenant_spoke_is_linked_for_resolution_only" {
  command = plan

  variables {
    spoke_virtual_networks = {
      partner-tenant = {
        virtual_network_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-network-partner/providers/Microsoft.Network/virtualNetworks/vnet-partner"
      }
    }
  }

  # One link per zone per spoke, plus one hub link per zone.
  assert {
    condition     = length(local.spoke_zone_links) == 2
    error_message = "Each canonical zone must receive its own link to each spoke network."
  }

  assert {
    condition     = length(azurerm_private_dns_zone_virtual_network_link.hub) == 2
    error_message = "The hub must be linked to every canonical zone it hosts."
  }

  assert {
    condition = alltrue([
      for link in values(azurerm_private_dns_zone_virtual_network_link.spoke) : link.registration_enabled == false
    ])
    error_message = "Private Link zones must never absorb spoke registrations; every link is resolution-only."
  }

  assert {
    condition = alltrue([
      for link in values(azurerm_private_dns_zone_virtual_network_link.hub) : link.registration_enabled == false
    ])
    error_message = "The hub link is resolution-only as well."
  }

  assert {
    condition     = local.private_dns_zone_resource_group_name == "rg-dns-hub-eus-prd"
    error_message = "Explicit links address the zone by resource group name parsed from the supplied ID."
  }
}

run "records_are_published_because_links_do_not_register" {
  command = plan

  variables {
    published_endpoint_records = {
      partner-dfs = {
        zone_key           = "dfs"
        record_name        = "stpartnerexample"
        private_ip_address = "10.216.80.9"
      }
      partner-blob = {
        zone_key           = "blob"
        record_name        = "stpartnerexample"
        private_ip_address = "10.216.80.8"
      }
    }
  }

  assert {
    condition     = length(local.published_records_by_zone["dfs"]) == 1 && length(local.published_records_by_zone["blob"]) == 1
    error_message = "Each published record must land in exactly its own canonical zone."
  }

  assert {
    condition     = local.published_records_by_zone["dfs"]["partner-dfs"].records[0] == "10.216.80.9"
    error_message = "A published record must carry the owning tenant's private endpoint IP."
  }
}

run "reject_record_for_unhosted_zone" {
  command = plan

  variables {
    canonical_zone_keys = ["dfs", "blob"]
    published_endpoint_records = {
      orphan-sql = {
        zone_key           = "sql"
        record_name        = "sqlpartnerexample"
        private_ip_address = "10.216.80.20"
      }
    }
  }

  expect_failures = [terraform_data.configuration_guard]
}

run "reject_half_of_the_adls_pair" {
  command = plan

  variables {
    canonical_zone_keys = ["dfs"]
  }

  expect_failures = [terraform_data.configuration_guard]
}

run "reject_duplicate_spoke_link" {
  command = plan

  variables {
    spoke_virtual_networks = {
      first = {
        virtual_network_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-network-partner/providers/Microsoft.Network/virtualNetworks/vnet-partner"
      }
      second = {
        virtual_network_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-network-partner/providers/Microsoft.Network/virtualNetworks/VNET-PARTNER"
      }
    }
  }

  expect_failures = [terraform_data.configuration_guard]
}

run "reject_resolver_without_subnet" {
  command = plan

  variables {
    deploy_dns_resolver              = true
    dns_resolver_resource_group_name = "rg-network-hub-eus-prd"
  }

  expect_failures = [var.dns_resolver_inbound_subnet_name]
}
