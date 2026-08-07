resource "terraform_data" "configuration_guard" {
  lifecycle {
    precondition {
      condition = length(distinct([
        var.agent_subnet_resource_id,
        var.private_endpoint_subnet_resource_id,
        var.mcp_subnet_resource_id,
      ])) == 3
      error_message = "Agent, private endpoint, and MCP subnets must be three distinct resources."
    }

    precondition {
      condition = alltrue([
        for resource_id in concat(
          values(local.byor_resource_ids),
          [
            var.agent_subnet_resource_id,
            var.private_endpoint_subnet_resource_id,
            var.mcp_subnet_resource_id,
          ],
          var.foundry_private_dns_zone_resource_ids,
          [
            var.storage_blob_private_dns_zone_resource_id,
            var.cosmos_db_private_dns_zone_resource_id,
            var.ai_search_private_dns_zone_resource_id,
            var.key_vault_private_dns_zone_resource_id,
          ],
        ) : startswith(lower(resource_id), "/subscriptions/")
      ])
      error_message = "Every BYOR, subnet, and private DNS input must be a full Azure resource ID."
    }
  }
}