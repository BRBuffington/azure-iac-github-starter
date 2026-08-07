output "foundry_account_id" {
  description = "Resource ID of the Microsoft Foundry account."
  value       = module.ai_foundry.ai_foundry_id
}

output "foundry_project_id" {
  description = "Resource ID of the Microsoft Foundry project."
  value       = module.ai_foundry.ai_foundry_project_id
}

output "foundry_project_endpoint" {
  description = "Private project endpoint consumed by the in-VNet data-plane workflow."
  value       = local.foundry_project_endpoint
}

output "model_deployment_name" {
  description = "Model deployment name consumed by the Prompt Agent definition."
  value       = var.model_deployment_name
}

output "mcp_subnet_resource_id" {
  description = "Dedicated subnet where the private MCP Container Apps environment is hosted."
  value       = var.mcp_subnet_resource_id
}

output "bot_service_resource_ids" {
  description = "Bot Service ARM IDs keyed by Prompt Agent name after the identity handoff."
  value       = { for agent_name, bot in module.bot_service : agent_name => bot.resource_id }
}

output "activity_endpoints" {
  description = "Stable Foundry activity protocol endpoints keyed by Prompt Agent name."
  value       = { for agent_name, publication in local.agent_publications : agent_name => publication.activity_endpoint }
}