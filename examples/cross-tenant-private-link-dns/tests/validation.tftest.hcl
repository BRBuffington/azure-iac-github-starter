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
  private_endpoint_targets = {
    sql_server = {
      provider_resource_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-provider-data/providers/Microsoft.Sql/servers/sql-provider-example"
      subresource_name     = "sqlServer"
      private_dns_zone_key = "sql"
    }
  }
}

run "valid_sql_configuration" {
  command = plan

  assert {
    condition     = length(local.private_dns_zones_to_create) == 1 && contains(keys(local.private_dns_zones_to_create), "sql")
    error_message = "A SQL-only configuration must create only the requested SQL private DNS zone."
  }

  assert {
    condition     = local.avm_tags.LastAppliedStamp == "Disabled"
    error_message = "AVM-managed resources must remain excluded from the external LastApplied stamp."
  }
}

run "valid_resolver_with_forwarding" {
  command = plan

  variables {
    deploy_dns_resolver               = true
    dns_resolver_inbound_subnet_name  = "snet-dns-inbound"
    dns_resolver_inbound_ip           = "10.10.0.4"
    dns_resolver_outbound_subnet_name = "snet-dns-outbound"
    enterprise_forwarding_rules = {
      corporate_internal = {
        domain_name = "corp.example."
        destination_ip_addresses = {
          "10.20.0.10" = "53"
          "10.20.0.11" = "53"
        }
      }
    }
  }

  assert {
    condition     = length(module.dns_resolver) == 1
    error_message = "Enabling the resolver with valid inbound and outbound inputs must plan one Resolver module."
  }
}

run "reject_mismatched_zone" {
  command = plan

  variables {
    private_endpoint_targets = {
      sql_server = {
        provider_resource_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-provider-data/providers/Microsoft.Sql/servers/sql-provider-example"
        subresource_name     = "sqlServer"
        private_dns_zone_key = "blob"
      }
    }
  }

  expect_failures = [var.private_endpoint_targets]
}

run "reject_dfs_without_blob" {
  command = plan

  variables {
    private_endpoint_targets = {
      storage_dfs = {
        provider_resource_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-provider-data/providers/Microsoft.Storage/storageAccounts/stproviderexample"
        subresource_name     = "dfs"
        private_dns_zone_key = "dfs"
      }
    }
  }

  expect_failures = [var.private_endpoint_targets]
}

run "reject_missing_zone_resource_group" {
  command = plan

  variables {
    private_dns_zone_resource_group_id = null
  }

  expect_failures = [var.private_dns_zone_resource_group_id]
}

run "reject_forwarding_without_outbound_resolver" {
  command = plan

  variables {
    enterprise_forwarding_rules = {
      corporate_internal = {
        domain_name = "corp.example."
        destination_ip_addresses = {
          "10.20.0.10" = "53"
        }
      }
    }
  }

  expect_failures = [var.dns_resolver_outbound_subnet_name]
}

run "reject_azure_service_forwarding" {
  command = plan

  variables {
    deploy_dns_resolver               = true
    dns_resolver_inbound_subnet_name  = "snet-dns-inbound"
    dns_resolver_outbound_subnet_name = "snet-dns-outbound"
    enterprise_forwarding_rules = {
      unsafe_service_zone = {
        domain_name = "account.blob.core.windows.net."
        destination_ip_addresses = {
          "10.20.0.10" = "53"
        }
      }
    }
  }

  expect_failures = [var.enterprise_forwarding_rules]
}