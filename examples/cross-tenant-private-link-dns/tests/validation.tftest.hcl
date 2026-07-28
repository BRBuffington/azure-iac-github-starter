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

  assert {
    condition     = length(azurerm_private_endpoint.cross_tenant["sql_server"].private_dns_zone_group) == 1
    error_message = "The default standard_contexts architecture must attach exactly one Azure-managed zone group."
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

run "valid_prefixed_backing_configuration" {
  command = plan

  variables {
    dns_architecture             = "prefixed_backing"
    publish_prefixed_dns_records = true
    private_endpoint_targets = {
      storage_dfs = {
        provider_resource_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-provider-data/providers/Microsoft.Storage/storageAccounts/stproviderexample"
        subresource_name     = "dfs"
        private_dns_zone_key = "dfs"
      }
      storage_blob = {
        provider_resource_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-provider-data/providers/Microsoft.Storage/storageAccounts/stproviderexample"
        subresource_name     = "blob"
        private_dns_zone_key = "blob"
      }
    }
    approved_private_endpoint_target_keys = ["storage_dfs", "storage_blob"]
    prefixed_private_dns_zones = {
      tenant_a_dfs = {
        domain_name = "tenant-a.privatelink.dfs.core.windows.net"
        records = {
          stproviderexample = {
            private_endpoint_target_key = "storage_dfs"
            ttl                         = 60
          }
        }
      }
      tenant_a_blob = {
        domain_name = "tenant-a.privatelink.blob.core.windows.net"
        records = {
          stproviderexample = {
            private_endpoint_target_key = "storage_blob"
            ttl                         = 60
          }
        }
      }
    }
  }

  assert {
    condition     = length(module.private_dns_zone) == 0 && length(local.private_dns_zone_ids) == 0
    error_message = "The prefixed architecture must not create or expose standard Private DNS zones."
  }

  assert {
    condition     = length(module.prefixed_private_dns_zone) == 2
    error_message = "The prefixed architecture must create each configured custom backing zone."
  }

  assert {
    condition     = length(azurerm_private_endpoint.cross_tenant["storage_dfs"].private_dns_zone_group) == 0
    error_message = "The prefixed architecture must not attach Azure-managed standard zone groups."
  }

  assert {
    condition     = output.prefixed_private_dns_records["tenant_a_dfs"].records["stproviderexample"].fqdn == "stproviderexample.tenant-a.privatelink.dfs.core.windows.net"
    error_message = "The prefixed architecture must expose deterministic backing-record metadata for the enterprise DNS bridge."
  }
}

run "valid_prefixed_request_phase_without_dns_publication" {
  command = plan

  variables {
    dns_architecture                   = "prefixed_backing"
    private_dns_zone_resource_group_id = null
  }

  assert {
    condition     = length(azurerm_private_endpoint.cross_tenant) == 1
    error_message = "The prefixed request phase must create Private Endpoint requests before DNS publication."
  }

  assert {
    condition     = length(module.private_dns_zone) == 0 && length(module.prefixed_private_dns_zone) == 0
    error_message = "The prefixed request phase must not create standard or custom DNS zones."
  }

  assert {
    condition     = length(azurerm_private_endpoint.cross_tenant["sql_server"].private_dns_zone_group) == 0
    error_message = "The prefixed request phase must not attach a standard zone group."
  }
}

run "reject_prefixed_zones_in_standard_architecture" {
  command = plan

  variables {
    prefixed_private_dns_zones = {
      tenant_a_sql = {
        domain_name = "tenant-a.privatelink.database.windows.net"
        records = {
          sqlproviderexample = {
            private_endpoint_target_key = "sql_server"
          }
        }
      }
    }
  }

  expect_failures = [var.prefixed_private_dns_zones]
}

run "reject_prefixed_architecture_without_zones" {
  command = plan

  variables {
    dns_architecture                      = "prefixed_backing"
    publish_prefixed_dns_records          = true
    approved_private_endpoint_target_keys = ["sql_server"]
  }

  expect_failures = [var.prefixed_private_dns_zones]
}

run "reject_unapproved_prefixed_record" {
  command = plan

  variables {
    dns_architecture             = "prefixed_backing"
    publish_prefixed_dns_records = true
    prefixed_private_dns_zones = {
      tenant_a_sql = {
        domain_name = "tenant-a.privatelink.database.windows.net"
        records = {
          sqlproviderexample = {
            private_endpoint_target_key = "sql_server"
          }
        }
      }
    }
  }

  expect_failures = [var.approved_private_endpoint_target_keys]
}

run "reject_prefixed_zone_service_mismatch" {
  command = plan

  variables {
    dns_architecture                      = "prefixed_backing"
    publish_prefixed_dns_records          = true
    approved_private_endpoint_target_keys = ["sql_server"]
    prefixed_private_dns_zones = {
      tenant_a_blob = {
        domain_name = "tenant-a.privatelink.blob.core.windows.net"
        records = {
          sqlproviderexample = {
            private_endpoint_target_key = "sql_server"
          }
        }
      }
    }
  }

  expect_failures = [var.prefixed_private_dns_zones]
}

run "reject_duplicate_prefixed_zone_names" {
  command = plan

  variables {
    dns_architecture                      = "prefixed_backing"
    publish_prefixed_dns_records          = true
    approved_private_endpoint_target_keys = ["sql_server"]
    prefixed_private_dns_zones = {
      tenant_a_sql = {
        domain_name = "tenant-a.privatelink.database.windows.net"
        records = {
          sqlproviderexample = {
            private_endpoint_target_key = "sql_server"
          }
        }
      }
      duplicate_tenant_a_sql = {
        domain_name = "TENANT-A.PRIVATELINK.DATABASE.WINDOWS.NET"
        records = {
          sqlproviderexample = {
            private_endpoint_target_key = "sql_server"
          }
        }
      }
    }
  }

  expect_failures = [var.prefixed_private_dns_zones]
}

run "reject_existing_standard_zones_in_prefixed_architecture" {
  command = plan

  variables {
    dns_architecture                      = "prefixed_backing"
    publish_prefixed_dns_records          = true
    approved_private_endpoint_target_keys = ["sql_server"]
    existing_private_dns_zone_ids = {
      sql = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dns-consumer-eus-prd/providers/Microsoft.Network/privateDnsZones/privatelink.database.windows.net"
    }
    prefixed_private_dns_zones = {
      tenant_a_sql = {
        domain_name = "tenant-a.privatelink.database.windows.net"
        records = {
          sqlproviderexample = {
            private_endpoint_target_key = "sql_server"
          }
        }
      }
    }
  }

  expect_failures = [var.existing_private_dns_zone_ids]
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
