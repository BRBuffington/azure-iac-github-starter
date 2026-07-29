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
  private_endpoint_targets = {
    sql_server = {
      provider_resource_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-provider-data/providers/Microsoft.Sql/servers/sql-provider-example"
      subresource_name     = "sqlServer"
      dns_family           = "sql"
    }
  }
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
    publish_dns_records = true
    private_endpoint_targets = {
      storage_dfs = {
        provider_resource_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-provider-data/providers/Microsoft.Storage/storageAccounts/stproviderexample"
        subresource_name     = "dfs"
        dns_family           = "dfs"
      }
      storage_blob = {
        provider_resource_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-provider-data/providers/Microsoft.Storage/storageAccounts/stproviderexample"
        subresource_name     = "blob"
        dns_family           = "blob"
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
    deploy_dns_resolver               = true
    dns_resolver_inbound_subnet_name  = "snet-dns-inbound"
    dns_resolver_inbound_ip           = "10.10.0.4"
    dns_resolver_outbound_subnet_name = "snet-dns-outbound"
    enterprise_forwarding_rules = {
      corporate_internal = {
        domain_name = "corp.example."
        destination_ip_addresses = {
          "10.20.0.10" = "53"
        }
      }
    }
  }

  assert {
    condition     = length(module.dns_resolver) == 1
    error_message = "Valid resolver inputs must plan one Resolver module."
  }
}

run "reject_publication_without_zones" {
  command = plan

  variables {
    publish_dns_records                   = true
    approved_private_endpoint_target_keys = ["sql_server"]
  }

  expect_failures = [var.prefixed_private_dns_zones]
}

run "reject_unapproved_record" {
  command = plan

  variables {
    publish_dns_records = true
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

run "reject_zone_service_mismatch" {
  command = plan

  variables {
    publish_dns_records                   = true
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

run "reject_duplicate_zone_names" {
  command = plan

  variables {
    publish_dns_records                   = true
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

run "reject_dfs_without_blob" {
  command = plan

  variables {
    private_endpoint_targets = {
      storage_dfs = {
        provider_resource_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-provider-data/providers/Microsoft.Storage/storageAccounts/stproviderexample"
        subresource_name     = "dfs"
        dns_family           = "dfs"
      }
    }
  }

  expect_failures = [var.private_endpoint_targets]
}

run "reject_missing_zone_resource_group_on_publication" {
  command = plan

  variables {
    publish_dns_records                   = true
    prefixed_dns_zone_resource_group_id   = null
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
    }
  }

  expect_failures = [var.prefixed_dns_zone_resource_group_id]
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
