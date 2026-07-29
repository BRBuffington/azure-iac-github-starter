mock_provider "azapi" {}
mock_provider "azurerm" {}

variables {
  subscription_id                      = "00000000-0000-0000-0000-000000000000"
  location                             = "eastus"
  name_prefix                          = "consumer-prd"
  private_endpoint_resource_group_name = "rg-network-consumer-eus-prd"
  private_endpoint_subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-consumer-eus-prd/providers/Microsoft.Network/virtualNetworks/vnet-consumer-eus-prd/subnets/snet-private-endpoints"
  consumer_virtual_network_id          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-consumer-eus-prd/providers/Microsoft.Network/virtualNetworks/vnet-consumer-eus-prd"
  private_dns_zone_resource_group_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dns-consumer-eus-prd"
  provider_sql_server_id               = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-provider-data/providers/Microsoft.Sql/servers/sql-provider-example"
}

run "valid_standard_sql_configuration" {
  command = plan

  assert {
    condition     = length(local.private_dns_zones_to_create) == 1 && contains(keys(local.private_dns_zones_to_create), "sql")
    error_message = "A SQL-only configuration must create only the requested SQL Private DNS zone."
  }

  assert {
    condition     = length(azurerm_private_endpoint.cross_tenant["sql_server"].private_dns_zone_group) == 1
    error_message = "The standard-contexts option must attach exactly one Azure-managed zone group."
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
    enterprise_dns_server_ip_addresses = ["10.20.0.10", "10.20.0.11"]
  }

  assert {
    condition     = length(module.dns_resolver) == 1
    error_message = "Valid resolver inputs must plan one Resolver module."
  }
}

run "valid_storage_composition" {
  command = plan

  variables {
    provider_storage_account_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-provider-data/providers/Microsoft.Storage/storageAccounts/stproviderexample"
    provider_sql_server_id      = null
  }

  assert {
    condition     = length(local.private_endpoint_targets) == 2 && contains(keys(local.private_endpoint_targets), "storage_dfs") && contains(keys(local.private_endpoint_targets), "storage_blob")
    error_message = "A Storage account ID must compose both DFS and Blob endpoint targets locally."
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

run "reject_missing_zone_resource_group" {
  command = plan

  variables {
    private_dns_zone_resource_group_id = null
  }

  expect_failures = [terraform_data.configuration_guard]
}

run "reject_mismatched_existing_zone_id" {
  command = plan

  variables {
    existing_sql_private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dns-consumer-eus-prd/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
  }

  expect_failures = [var.existing_sql_private_dns_zone_id]
}

run "reject_invalid_provider_resource_id" {
  command = plan

  variables {
    provider_sql_server_id = "/subscriptions/not-a-guid/resourceGroups/rg-provider-data/providers/Microsoft.Sql/servers/sql-provider-example"
  }

  expect_failures = [terraform_data.configuration_guard]
}

run "reject_forwarding_without_outbound_resolver" {
  command = plan

  variables {
    enterprise_forwarding_domain_name  = "corp.example."
    enterprise_dns_server_ip_addresses = ["10.20.0.10"]
  }

  expect_failures = [var.dns_resolver_outbound_subnet_name]
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
