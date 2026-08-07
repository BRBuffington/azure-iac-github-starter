locals {
  common_tags = merge(var.tags, {
    LastAppliedStamp = "Disabled"
  })

  foundry_project_endpoint = "https://${var.foundry_account_name}.services.ai.azure.com/api/projects/${var.project_name}"

  foundry_network_injections = [
    {
      scenario                   = "agent"
      subnetArmId                = var.agent_subnet_resource_id
      useMicrosoftManagedNetwork = false
    }
  ]

  byor_resource_ids = {
    storage = var.storage_account_resource_id
    cosmos  = var.cosmos_db_resource_id
    search  = var.ai_search_resource_id
    vault   = var.key_vault_resource_id
  }

  agent_publications = {
    for agent_name, publication in var.agent_publications : agent_name => {
      principal_id = publication.principal_id
      bot_name     = publication.bot_name
      display_name = coalesce(publication.display_name, agent_name)
      activity_endpoint = format(
        "%s/agents/%s/endpoint/protocols/activityProtocol?api-version=2025-05-15-preview",
        local.foundry_project_endpoint,
        agent_name,
      )
    }
  }
}