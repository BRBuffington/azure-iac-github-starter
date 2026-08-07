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
  project_display_name  = "Agent for Teams"
  model_deployment_name = "gpt-5-mini"
  model_name            = "gpt-5-mini"
  model_version         = "2026-01-01"
}

run "foundry_only_before_agent_identity" {
  command = plan

  assert {
    condition     = length(module.bot_service) == 0
    error_message = "The first infrastructure plan must not create Bot Service before the Prompt Agent identity exists."
  }

  assert {
    condition     = local.foundry_project_endpoint == "https://aif-agent-eus-dev-example.services.ai.azure.com/api/projects/agent-teams"
    error_message = "The data-plane workflow must receive the deterministic Foundry project endpoint."
  }
}

run "teams_bot_after_agent_identity" {
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
    error_message = "One Prompt Agent identity must compose exactly one Bot Service."
  }

  assert {
    condition     = local.agent_publications["helpdesk-agent"].activity_endpoint == "https://aif-agent-eus-dev-example.services.ai.azure.com/api/projects/agent-teams/agents/helpdesk-agent/endpoint/protocols/activityProtocol?api-version=2025-05-15-preview"
    error_message = "Bot Service must target the documented Foundry activity protocol endpoint."
  }

}

run "reject_invalid_agent_identity" {
  command = plan

  variables {
    agent_publications = {
      helpdesk-agent = {
        principal_id = "not-a-guid"
        bot_name     = "bot-helpdesk-eus-dev"
      }
    }
  }

  expect_failures = [var.agent_publications]
}