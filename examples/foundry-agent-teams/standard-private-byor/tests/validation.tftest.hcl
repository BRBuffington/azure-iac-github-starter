mock_provider "azurerm" {}

override_module {
  target = module.resource_group
  outputs = {
    name        = "rg-foundry-agent-eus-dev"
    resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-agent-eus-dev"
  }
}

override_module {
  target = module.ai_foundry
  outputs = {
    ai_foundry_id         = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-agent-eus-dev/providers/Microsoft.CognitiveServices/accounts/aif-agent-eus-dev-example"
    ai_foundry_project_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-agent-eus-dev/providers/Microsoft.CognitiveServices/accounts/aif-agent-eus-dev-example/projects/agent-teams"
  }
}

override_module {
  target = module.bot_service
  outputs = {
    name        = "bot-helpdesk-eus-dev"
    resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-foundry-agent-eus-dev/providers/Microsoft.BotService/botServices/bot-helpdesk-eus-dev"
  }
}

variables {
  subscription_id       = "00000000-0000-0000-0000-000000000000"
  tenant_id             = "11111111-1111-1111-1111-111111111111"
  location              = "eastus"
  resource_group_name   = "rg-foundry-agent-eus-dev"
  base_name             = "agent-eus-dev"
  foundry_account_name  = "aif-agent-eus-dev-example"
  project_name          = "agent-teams"
  project_display_name  = "Private Agent for Teams"
  model_deployment_name = "gpt-5-mini"
  model_name            = "gpt-5-mini"
  model_version         = "2026-01-01"

  agent_subnet_resource_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-agent/subnets/snet-agent"
  private_endpoint_subnet_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-agent/subnets/snet-private-endpoints"
  mcp_subnet_resource_id              = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-agent/subnets/snet-mcp"

  storage_account_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-data/providers/Microsoft.Storage/storageAccounts/stagentexample"
  cosmos_db_resource_id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-data/providers/Microsoft.DocumentDB/databaseAccounts/cosmos-agent-example"
  ai_search_resource_id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-data/providers/Microsoft.Search/searchServices/srch-agent-example"
  key_vault_resource_id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-data/providers/Microsoft.KeyVault/vaults/kv-agent-example"

  foundry_private_dns_zone_resource_ids = [
    "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dns/providers/Microsoft.Network/privateDnsZones/privatelink.cognitiveservices.azure.com",
    "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dns/providers/Microsoft.Network/privateDnsZones/privatelink.openai.azure.com",
    "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dns/providers/Microsoft.Network/privateDnsZones/privatelink.services.ai.azure.com",
  ]
  storage_blob_private_dns_zone_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dns/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
  cosmos_db_private_dns_zone_resource_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dns/providers/Microsoft.Network/privateDnsZones/privatelink.documents.azure.com"
  ai_search_private_dns_zone_resource_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dns/providers/Microsoft.Network/privateDnsZones/privatelink.search.windows.net"
  key_vault_private_dns_zone_resource_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dns/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
}

run "private_foundry_only_before_agent_identity" {
  command = plan

  assert {
    condition     = length(module.bot_service) == 0
    error_message = "The first private infrastructure plan must not create Bot Service before the Prompt Agent identity exists."
  }

  assert {
    condition     = local.foundry_network_injections == [{ scenario = "agent", subnetArmId = var.agent_subnet_resource_id, useMicrosoftManagedNetwork = false }]
    error_message = "Foundry must inject agent compute only into the dedicated agent subnet."
  }

  assert {
    condition     = length(distinct([var.agent_subnet_resource_id, var.private_endpoint_subnet_resource_id, var.mcp_subnet_resource_id])) == 3
    error_message = "The private topology must use three distinct subnets."
  }
}

run "private_teams_bot_after_agent_identity" {
  command = plan

  variables {
    agent_publications = {
      helpdesk-agent = {
        principal_id = "22222222-2222-2222-2222-222222222222"
        bot_name     = "bot-helpdesk-eus-dev"
        display_name = "Helpdesk Agent"
      }
    }
  }

  assert {
    condition     = length(module.bot_service) == 1
    error_message = "One private Prompt Agent identity must compose exactly one Bot Service."
  }

  assert {
    condition     = local.agent_publications["helpdesk-agent"].activity_endpoint == "https://aif-agent-eus-dev-example.services.ai.azure.com/api/projects/agent-teams/agents/helpdesk-agent/endpoint/protocols/activityProtocol?api-version=2025-05-15-preview"
    error_message = "Bot Service must target the documented private Foundry activity protocol endpoint."
  }
}

run "reject_reused_subnet" {
  command = plan

  variables {
    mcp_subnet_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-agent/subnets/snet-agent"
  }

  expect_failures = [terraform_data.configuration_guard]
}