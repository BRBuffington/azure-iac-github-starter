output "runner_vnet_resource_id" {
  description = "Resource ID of the environment-specific runner VNet."
  value       = module.runner_vnet.resource_id
}

output "runner_subnet_resource_id" {
  description = "Resource ID of the subnet delegated to GitHub.Network/networkSettings."
  value       = module.runner_vnet.subnets["runners"].resource_id
}

output "dependency_subnet_resource_id" {
  description = "Resource ID of the fail-closed subnet reserved for approved private endpoints."
  value       = module.runner_vnet.subnets["dependencies"].resource_id
}

output "github_network_settings_id" {
  description = "GitHubId returned by the Azure NetworkSettings resource."
  value       = azapi_resource.github_network_settings.output.github_network_settings_id
}

output "github_runner_group_id" {
  description = "Organization runner group ID."
  value       = github_actions_runner_group.this.id
}

output "github_hosted_runner_id" {
  description = "GitHub-hosted larger runner pool ID."
  value       = github_actions_hosted_runner.this.id
}
