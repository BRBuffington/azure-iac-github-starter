mock_provider "azurerm" {}

override_module {
  target = module.resource_group
  outputs = {
    resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-aidemo-eus-dev-ai"
  }
}

override_module {
  target = module.ai_foundry
  outputs = {
    ai_foundry_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-aidemo-eus-dev-ai/providers/Microsoft.CognitiveServices/accounts/aif-aidemo-eus-dev-sample"
    ai_foundry_project_id = {
      runtime = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-aidemo-eus-dev-ai/providers/Microsoft.CognitiveServices/accounts/aif-aidemo-eus-dev-sample/projects/proj-aidemo-eus-dev"
    }
    storage_account_id = { runtime = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-aidemo-eus-dev-ai/providers/Microsoft.Storage/storageAccounts/staidemoeusdevsample" }
    cosmos_db_id       = { runtime = "/example/cosmos" }
    ai_search_id       = { runtime = "/example/search" }
  }
}

variables {
  subscription_id                     = "00000000-0000-0000-0000-000000000000"
  tenant_id                           = "11111111-1111-1111-1111-111111111111"
  scope                               = "aidemo"
  region_alias                        = "eus"
  location                            = "eastus"
  environment                         = "dev"
  name_suffix                         = "sample"
  agent_subnet_resource_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-agents"
  private_endpoint_subnet_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-private-endpoints"
  private_dns_zone_resource_group_id  = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-private-dns"
  log_analytics_workspace_resource_id = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-monitoring/providers/Microsoft.OperationalInsights/workspaces/log-platform"
  model_name                          = "gpt-4.1"
  model_version                       = "2025-04-14"
  tags                                = { Owner = "platform-team" }
  deployed_by_repo                    = "example-org/azure-ai-reference"
}

run "private_entra_only_runtime" {
  command = plan

  assert {
    condition = (
      !local.foundry_configuration.public_network_access_enabled &&
      local.foundry_configuration.disable_local_auth &&
      !local.storage_configuration.runtime.public_network_access_enabled &&
      !local.storage_configuration.runtime.shared_access_key_enabled &&
      !local.cosmos_configuration.runtime.public_network_access_enabled &&
      local.cosmos_configuration.runtime.local_authentication_disabled &&
      !local.search_configuration.runtime.public_network_access_enabled &&
      !local.search_configuration.runtime.local_authentication_enabled
    )
    error_message = "Foundry and every runtime store must remain private and Entra-authenticated."
  }

  assert {
    condition = (
      local.foundry_configuration.network_acls.bypass == "None" &&
      local.storage_configuration.runtime.network_rules.bypass == ["None"] &&
      !local.cosmos_configuration.runtime.network_acl_bypass_for_azure_services &&
      length(local.cosmos_configuration.runtime.ip_range_filter) == 0 &&
      local.search_configuration.runtime.network_rule_set.bypass == "None"
    )
    error_message = "The private example must not silently add trusted-service or public-IP bypasses."
  }

  assert {
    condition = (
      length(local.cosmos_configuration.runtime.secondary_regions) == 1 &&
      local.cosmos_configuration.runtime.secondary_regions[0].location == var.location &&
      !local.cosmos_configuration.runtime.automatic_failover_enabled &&
      local.storage_configuration.runtime.account_replication_type == "LRS" &&
      local.search_configuration.runtime.replica_count == 1
    )
    error_message = "The POC must not inherit multi-region or production availability settings from AVM defaults."
  }

  assert {
    condition     = length(local.zone_ids) == 6 && length(local.metrics.central.log_groups) == 0
    error_message = "Use the existing six DNS zones and do not enable unreviewed allLogs capture."
  }
}

run "service_logs_reach_their_own_diagnostic_targets" {
  command = plan

  assert {
    condition = (
      local.service_diagnostics.foundry.central.log_categories == toset(["Audit"]) &&
      local.cosmos_configuration.runtime.diagnostic_settings.central.log_categories == toset(["ControlPlaneRequests"]) &&
      local.search_configuration.runtime.diagnostic_settings.central.log_categories == toset(["OperationLogs"]) &&
      azurerm_monitor_diagnostic_setting.blob["runtime"].target_resource_id == "${output.runtime_store_ids.storage}/blobServices/default" &&
      toset([for entry in azurerm_monitor_diagnostic_setting.blob["runtime"].enabled_log : entry.category]) == toset(["StorageRead", "StorageWrite", "StorageDelete"])
    )
    error_message = "Audit categories must reach the configured services; Blob operations require the blobServices/default target."
  }

  assert {
    condition = (
      local.service_diagnostics.foundry.central.log_analytics_destination_type == "AzureDiagnostics" &&
      local.service_diagnostics.search.central.log_analytics_destination_type == "AzureDiagnostics" &&
      local.service_diagnostics.cosmos.central.log_analytics_destination_type == "Dedicated" &&
      azurerm_monitor_diagnostic_setting.blob["runtime"].log_analytics_workspace_id == var.log_analytics_workspace_resource_id
    )
    error_message = "Each service must use its supported table mode and the approved existing workspace."
  }
}

run "explicit_empty_logs_preserve_metrics" {
  command = plan

  variables {
    foundry_log_categories = []
    runtime_log_categories = {
      cosmos = []
      search = []
      blob   = []
    }
  }

  assert {
    condition = (
      length(azurerm_monitor_diagnostic_setting.blob) == 0 &&
      alltrue([for settings in local.service_diagnostics : length(settings.central.log_categories) == 0]) &&
      alltrue([for settings in local.service_diagnostics : settings.central.metric_categories == ["AllMetrics"]])
    )
    error_message = "Explicitly withheld log categories must not be re-enabled; metrics remain independently configured."
  }
}

run "project_scoped_group_access" {
  command = plan

  variables {
    builder_group_ids  = ["33333333-3333-3333-3333-333333333333"]
    consumer_group_ids = ["44444444-4444-4444-4444-444444444444"]
  }

  assert {
    condition = (
      length(azurerm_role_assignment.project) == 2 &&
      alltrue([for assignment in azurerm_role_assignment.project : assignment.scope == output.project_resource_id]) &&
      local.account_readers["33333333-3333-3333-3333-333333333333"].role_definition_id_or_name == "Reader"
    )
    error_message = "Builders and consumers get project-scoped roles; builders get only Reader on the parent account."
  }
}

run "reject_shared_subnet" {
  command = plan

  variables {
    private_endpoint_subnet_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-agents"
  }

  expect_failures = [var.private_endpoint_subnet_resource_id]
}

run "accept_storage_name_at_24_characters" {
  command = plan

  variables {
    scope        = "example"
    region_alias = "eastus"
    environment  = "prd"
    name_suffix  = "sample"
  }

  assert {
    condition     = local.storage_configuration.runtime.name == "stexampleeastusprdsample" && length(local.storage_configuration.runtime.name) == 24
    error_message = "A valid 24-character composed storage name must pass without truncation or normalization."
  }
}

run "reject_storage_name_over_24_characters" {
  command = plan

  variables {
    scope        = "example"
    region_alias = "eastusa"
    environment  = "prd"
    name_suffix  = "sample"
  }

  expect_failures = [var.name_suffix]
}

run "reject_uppercase_region_in_storage_name" {
  command = plan

  variables {
    region_alias = "EUS"
  }

  expect_failures = [var.name_suffix]
}

run "reject_punctuation_in_storage_name" {
  command = plan

  variables {
    environment = "pre-prd"
  }

  expect_failures = [var.name_suffix]
}