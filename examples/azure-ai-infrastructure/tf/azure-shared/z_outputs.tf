output "vnet_resource_id" {
  description = "New spoke ID for the platform owner's reverse-peering configuration."
  value       = module.spoke.resource_id
}

output "agent_subnet_resource_id" {
  description = "Dedicated subnet ID for the AI workload root."
  value       = module.spoke.subnets["agents"].resource_id
}

output "private_endpoint_subnet_resource_id" {
  description = "Private-endpoint subnet ID for the AI workload root."
  value       = module.spoke.subnets["private_endpoints"].resource_id
}

output "network_control_ids" {
  description = "Effective created or reused NSG and agent route-table IDs."
  value = {
    agent_nsg            = local.agent_nsg_id
    private_endpoint_nsg = local.private_endpoint_nsg_id
    agent_route_table    = local.agent_route_table_id
  }
}