locals {
  prefix              = "${var.scope}-${var.region_alias}-${var.environment}"
  resource_group_name = "rg-${local.prefix}-ai"
  common_tags = merge(var.tags, {
    Environment      = var.environment
    DeployedByRepo   = var.deployed_by_repo
    LastAppliedStamp = "Disabled"
  })
  zone_names = {
    cognitive = "privatelink.cognitiveservices.azure.com"
    openai    = "privatelink.openai.azure.com"
    foundry   = "privatelink.services.ai.azure.com"
    blob      = "privatelink.blob.core.windows.net"
    cosmos    = "privatelink.documents.azure.com"
    search    = "privatelink.search.windows.net"
  }
  zone_ids = {
    for key, name in local.zone_names : key => "${var.private_dns_zone_resource_group_id}/providers/Microsoft.Network/privateDnsZones/${name}"
  }
  metrics = {
    central = {
      workspace_resource_id = var.log_analytics_workspace_resource_id
      log_groups            = []
      metric_categories     = ["AllMetrics"]
    }
  }
  service_diagnostics = {
    foundry = { central = merge(local.metrics.central, {
      log_categories                 = var.foundry_log_categories
      log_analytics_destination_type = "AzureDiagnostics"
    }) }
    cosmos = { central = merge(local.metrics.central, {
      log_categories                 = var.runtime_log_categories.cosmos
      log_analytics_destination_type = "Dedicated"
    }) }
    search = { central = merge(local.metrics.central, {
      log_categories                 = var.runtime_log_categories.search
      log_analytics_destination_type = "AzureDiagnostics"
    }) }
  }
  blob_diagnostics = length(var.runtime_log_categories.blob) == 0 ? {} : {
    runtime = var.runtime_log_categories.blob
  }
  account_readers = {
    for principal in var.builder_group_ids : principal => {
      principal_id               = principal
      principal_type             = "Group"
      role_definition_id_or_name = "Reader"
    }
  }
  project_roles = merge(
    { for principal in var.builder_group_ids : "builder-${principal}" => { principal_id = principal, role_id = "53ca6127-db72-4b80-b1b0-d745d6d5456d" } },
    { for principal in var.consumer_group_ids : "consumer-${principal}" => { principal_id = principal, role_id = "eed3b665-ab3a-47b6-8f48-c9382fb1dad6" } }
  )
  foundry_configuration = {
    name                          = "aif-${local.prefix}-${var.name_suffix}"
    create_ai_agent_service       = true
    disable_local_auth            = true
    public_network_access_enabled = false
    private_dns_zone_resource_ids = [local.zone_ids.cognitive, local.zone_ids.openai, local.zone_ids.foundry]
    network_acls                  = { default_action = "Deny", bypass = "None" }
    network_injections = [{
      scenario                   = "agent"
      subnetArmId                = var.agent_subnet_resource_id
      useMicrosoftManagedNetwork = false
    }]
    role_assignments = local.account_readers
  }
  storage_configuration = {
    runtime = {
      name                                = "st${var.scope}${var.region_alias}${var.environment}${var.name_suffix}"
      account_replication_type            = "LRS"
      shared_access_key_enabled           = false
      public_network_access_enabled       = false
      network_rules                       = { default_action = "Deny", bypass = ["None"] }
      diagnostic_settings_storage_account = local.metrics
      endpoints                           = { blob = { type = "blob", private_dns_zone_resource_id = local.zone_ids.blob } }
      tags                                = local.common_tags
    }
  }
  cosmos_configuration = {
    runtime = {
      name                                  = "cosno-${local.prefix}-${var.name_suffix}"
      public_network_access_enabled         = false
      local_authentication_disabled         = true
      ip_range_filter                       = []
      network_acl_bypass_for_azure_services = false
      automatic_failover_enabled            = false
      secondary_regions                     = [{ location = var.location, failover_priority = 0, zone_redundant = false }]
      private_dns_zone_resource_id          = local.zone_ids.cosmos
      diagnostic_settings                   = local.service_diagnostics.cosmos
      tags                                  = local.common_tags
    }
  }
  search_configuration = {
    runtime = {
      name                          = "srch-${local.prefix}-${var.name_suffix}"
      sku                           = "basic"
      replica_count                 = 1
      partition_count               = 1
      semantic_search               = "disabled"
      public_network_access_enabled = false
      local_authentication_enabled  = false
      network_rule_set              = { bypass = "None", ip_rules = [] }
      private_dns_zone_resource_id  = local.zone_ids.search
      diagnostic_settings           = local.service_diagnostics.search
      tags                          = local.common_tags
    }
  }
}