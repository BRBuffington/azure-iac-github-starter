locals {
  common_tags = merge(var.tags, {
    LastAppliedStamp = "Disabled"
  })

  foundry_project_endpoint = "https://${var.foundry_account_name}.services.ai.azure.com/api/projects/${var.project_name}"

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