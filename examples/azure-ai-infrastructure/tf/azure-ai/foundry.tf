module "resource_group" {
  source  = "Azure/avm-res-resources-resourcegroup/azurerm"
  version = "0.4.0"

  name             = local.resource_group_name
  location         = var.location
  tags             = local.common_tags
  enable_telemetry = false
}

module "ai_foundry" {
  source  = "Azure/avm-ptn-aiml-ai-foundry/azurerm"
  version = "0.11.3"

  base_name                  = var.scope
  location                   = var.location
  resource_group_resource_id = module.resource_group.resource_id
  ai_foundry                 = local.foundry_configuration
  storage_account_definition = local.storage_configuration
  cosmosdb_definition        = local.cosmos_configuration
  ai_search_definition       = local.search_configuration

  ai_projects = {
    runtime = {
      name                       = "proj-${local.prefix}"
      display_name               = "Private infrastructure POC"
      description                = "Infrastructure foundation; application agents are managed separately."
      create_project_connections = true
      storage_account_connection = { new_resource_map_key = "runtime" }
      cosmos_db_connection       = { new_resource_map_key = "runtime" }
      ai_search_connection       = { new_resource_map_key = "runtime" }
    }
  }
  ai_model_deployments = {
    primary = {
      name                   = var.model_name
      model                  = { format = "OpenAI", name = var.model_name, version = var.model_version }
      scale                  = { type = "Standard", capacity = var.model_capacity }
      version_upgrade_option = "NoAutoUpgrade"
    }
  }
  diagnostic_settings                 = local.service_diagnostics.foundry
  create_byor                         = true
  create_private_endpoints            = true
  private_endpoint_subnet_resource_id = var.private_endpoint_subnet_resource_id
  enable_telemetry                    = false
  tags                                = local.common_tags
}

resource "azurerm_role_assignment" "project" {
  for_each = local.project_roles

  scope              = module.ai_foundry.ai_foundry_project_id["runtime"]
  principal_id       = each.value.principal_id
  principal_type     = "Group"
  role_definition_id = "/subscriptions/${var.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/${each.value.role_id}"
}