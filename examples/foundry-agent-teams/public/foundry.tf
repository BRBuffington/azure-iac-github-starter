module "resource_group" {
  # checkov:skip=CKV_TF_1:Official AVM Registry module pinned to the exact 0.4.0 release returned by Terraform MCP.
  source  = "Azure/avm-res-resources-resourcegroup/azurerm"
  version = "0.4.0"

  location         = var.location
  name             = var.resource_group_name
  tags             = local.common_tags
  enable_telemetry = false
}

module "ai_foundry" {
  # checkov:skip=CKV_TF_1:Official AVM Registry module pinned to the exact 0.11.2 release returned by Terraform MCP.
  source  = "Azure/avm-ptn-aiml-ai-foundry/azurerm"
  version = "0.11.2"

  base_name                  = var.base_name
  location                   = var.location
  resource_group_resource_id = module.resource_group.resource_id

  ai_foundry = {
    name                    = var.foundry_account_name
    create_ai_agent_service = false
  }
  ai_model_deployments = {
    primary = {
      name = var.model_deployment_name
      model = {
        format  = "OpenAI"
        name    = var.model_name
        version = var.model_version
      }
      scale = {
        type     = var.model_sku
        capacity = var.model_capacity
      }
    }
  }
  ai_projects = {
    primary = {
      name                       = var.project_name
      display_name               = var.project_display_name
      description                = "Prompt Agent published to Microsoft Teams and Microsoft 365 Copilot."
      create_project_connections = false
    }
  }
  create_byor              = false
  create_private_endpoints = false
  enable_telemetry         = false
  tags                     = local.common_tags
}