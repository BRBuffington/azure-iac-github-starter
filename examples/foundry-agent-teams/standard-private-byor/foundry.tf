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
    name                          = var.foundry_account_name
    create_ai_agent_service       = true
    network_injections            = local.foundry_network_injections
    private_dns_zone_resource_ids = var.foundry_private_dns_zone_resource_ids
    public_network_access_enabled = false
    network_acls = {
      default_action = "Deny"
      bypass         = "AzureServices"
    }
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
      description                = "Private Prompt Agent published to Microsoft Teams and Microsoft 365 Copilot."
      create_project_connections = true
      storage_account_connection = {
        new_resource_map_key = "primary"
        existing_resource_id = var.storage_account_resource_id
      }
      cosmos_db_connection = {
        new_resource_map_key = "primary"
        existing_resource_id = var.cosmos_db_resource_id
      }
      ai_search_connection = {
        new_resource_map_key = "primary"
        existing_resource_id = var.ai_search_resource_id
      }
      key_vault_connection = {
        new_resource_map_key = "primary"
        existing_resource_id = var.key_vault_resource_id
      }
    }
  }
  storage_account_definition = {
    primary = {
      existing_resource_id = var.storage_account_resource_id
      endpoints = {
        blob = {
          type                         = "blob"
          private_dns_zone_resource_id = var.storage_blob_private_dns_zone_resource_id
        }
      }
    }
  }
  cosmosdb_definition = {
    primary = {
      existing_resource_id         = var.cosmos_db_resource_id
      private_dns_zone_resource_id = var.cosmos_db_private_dns_zone_resource_id
    }
  }
  ai_search_definition = {
    primary = {
      existing_resource_id         = var.ai_search_resource_id
      private_dns_zone_resource_id = var.ai_search_private_dns_zone_resource_id
    }
  }
  key_vault_definition = {
    primary = {
      existing_resource_id         = var.key_vault_resource_id
      private_dns_zone_resource_id = var.key_vault_private_dns_zone_resource_id
    }
  }

  create_byor                              = true
  create_private_endpoints                 = true
  private_endpoint_subnet_resource_id      = var.private_endpoint_subnet_resource_id
  private_endpoint_resource_group_name     = var.resource_group_name
  private_endpoint_resource_group_location = var.location
  enable_telemetry                         = false
  tags                                     = local.common_tags

  depends_on = [terraform_data.configuration_guard]
}