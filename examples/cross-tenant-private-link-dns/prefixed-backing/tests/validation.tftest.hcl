mock_provider "azapi" {}
mock_provider "azurerm" {}

variables {
  subscription_id                      = "00000000-0000-0000-0000-000000000000"
  location                             = "eastus"
  name_prefix                          = "consumer-prd"
  private_endpoint_resource_group_name = "rg-network-consumer-eus-prd"
  private_endpoint_subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-consumer-eus-prd/providers/Microsoft.Network/virtualNetworks/vnet-consumer-eus-prd/subnets/snet-private-endpoints"
  consumer_virtual_network_id          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-consumer-eus-prd/providers/Microsoft.Network/virtualNetworks/vnet-consumer-eus-prd"
  prefixed_dns_zone_resource_group_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dns-consumer-eus-prd"
  provider_sql_server_id               = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-provider-data/providers/Microsoft.Sql/servers/sql-provider-example"
  prefixed_dns_label                   = "tenant-a"
}

run "valid_request_phase_without_dns_publication" {
  command = plan

  variables {
    prefixed_dns_zone_resource_group_id = null
  }

  assert {
    condition     = length(azurerm_private_endpoint.cross_tenant) == 1
    error_message = "The request phase must create the pending Private Endpoint."
  }

  assert {
    condition     = length(azurerm_private_endpoint.cross_tenant["sql_server"].private_dns_zone_group) == 0
    error_message = "The prefixed-backing option must never attach a standard zone group."
  }

  assert {
    condition     = length(module.prefixed_private_dns_zone) == 0
    error_message = "The request phase must not publish backing zones or records."
  }
}

run "valid_approved_record_publication" {
  command = plan

  variables {
    provider_storage_account_id           = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-provider-data/providers/Microsoft.Storage/storageAccounts/stproviderexample"
    provider_sql_server_id                = null
    approved_private_endpoint_target_keys = ["storage_dfs", "storage_blob"]
  }

  assert {
    condition     = length(module.prefixed_private_dns_zone) == 2
    error_message = "Approved publication must create every configured backing zone."
  }

  assert {
    condition     = output.prefixed_private_dns_records["tenant_a_dfs"].records["stproviderexample"].fqdn == "stproviderexample.tenant-a.privatelink.dfs.core.windows.net"
    error_message = "Publication must expose deterministic bridge metadata."
  }
}

run "valid_resolver_with_forwarding" {
  command = plan

  variables {
    deploy_dns_resolver                = true
    dns_resolver_inbound_subnet_name   = "snet-dns-inbound"
    dns_resolver_inbound_ip            = "10.10.0.4"
    dns_resolver_outbound_subnet_name  = "snet-dns-outbound"
    enterprise_forwarding_domain_name  = "corp.example."
    enterprise_dns_server_ip_addresses = ["10.20.0.10"]
  }

  assert {
    condition     = length(module.dns_resolver) == 1
    error_message = "Valid resolver inputs must plan one Resolver module."
  }
}

run "reject_missing_provider_resource" {
  command = plan

  variables {
    provider_storage_account_id = null
    provider_sql_server_id      = null
  }

  expect_failures = [terraform_data.configuration_guard]
}

run "reject_invalid_provider_resource_id" {
  command = plan

  variables {
    provider_sql_server_id = "/subscriptions/not-a-guid/resourceGroups/rg-provider-data/providers/Microsoft.Sql/servers/sql-provider-example"
  }

  expect_failures = [terraform_data.configuration_guard]
}

run "reject_unknown_approval_key" {
  command = plan

  variables {
    approved_private_endpoint_target_keys = ["storage_blob"]
  }

  expect_failures = [terraform_data.configuration_guard]
}

run "reject_unapproved_record" {
  command = plan

  assert {
    condition     = length(module.prefixed_private_dns_zone) == 0
    error_message = "Unapproved endpoint targets must not publish backing zones or records."
  }
}

run "valid_local_zone_family_mapping" {
  command = plan

  assert {
    condition     = local.prefixed_private_dns_zones["tenant_a_sql"].domain_name == "tenant-a.privatelink.database.windows.net"
    error_message = "The local SQL target must map to the prefixed SQL Private Link suffix."
  }
}

run "reject_invalid_prefixed_dns_label" {
  command = plan

  variables {
    prefixed_dns_label = "Tenant A"
  }

  expect_failures = [var.prefixed_dns_label]
}

run "valid_storage_composition" {
  command = plan

  variables {
    provider_storage_account_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-provider-data/providers/Microsoft.Storage/storageAccounts/stproviderexample"
    provider_sql_server_id      = null
  }

  assert {
    condition     = length(local.private_endpoint_targets) == 2 && length(local.prefixed_private_dns_zones) == 2
    error_message = "A Storage account ID must compose DFS and Blob endpoints plus matching backing zones."
  }
}

run "valid_incremental_publication" {
  command = plan

  variables {
    provider_storage_account_id           = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-provider-data/providers/Microsoft.Storage/storageAccounts/stproviderexample"
    approved_private_endpoint_target_keys = ["sql_server"]
  }

  assert {
    condition     = length(azurerm_private_endpoint.cross_tenant) == 3
    error_message = "Adding Storage must create pending DFS and Blob endpoints alongside the existing SQL endpoint."
  }

  assert {
    condition     = length(module.prefixed_private_dns_zone) == 1 && contains(keys(module.prefixed_private_dns_zone), "tenant_a_sql")
    error_message = "Incremental expansion must retain the approved SQL zone while unapproved Storage zones remain unpublished."
  }

  assert {
    condition     = toset(keys(output.prefixed_private_dns_records)) == toset(["tenant_a_sql"])
    error_message = "The enterprise-DNS bridge output must expose only published, approved targets."
  }
}

run "reject_missing_zone_resource_group_on_publication" {
  command = plan

  variables {
    prefixed_dns_zone_resource_group_id   = null
    approved_private_endpoint_target_keys = ["sql_server"]
  }

  expect_failures = [terraform_data.configuration_guard]
}

run "reject_azure_service_forwarding" {
  command = plan

  variables {
    deploy_dns_resolver                = true
    dns_resolver_inbound_subnet_name   = "snet-dns-inbound"
    dns_resolver_outbound_subnet_name  = "snet-dns-outbound"
    enterprise_forwarding_domain_name  = "account.blob.core.windows.net."
    enterprise_dns_server_ip_addresses = ["10.20.0.10"]
  }

  expect_failures = [var.enterprise_forwarding_domain_name]
}
