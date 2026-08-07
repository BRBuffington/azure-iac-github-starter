module "bot_service" {
  # checkov:skip=CKV_TF_1:Official AVM Registry module pinned to the exact 0.4.0 release returned by Terraform MCP.
  source  = "Azure/avm-res-botservice-botservice/azurerm"
  version = "0.4.0"

  for_each = local.agent_publications

  location                     = "global"
  name                         = each.value.bot_name
  resource_group_name          = module.resource_group.name
  display_name                 = each.value.display_name
  endpoint                     = each.value.activity_endpoint
  microsoft_app_id             = each.value.principal_id
  microsoft_app_tenant_id      = var.tenant_id
  microsoft_app_type           = "SingleTenant"
  local_authentication_enabled = false
  public_network_access        = "Disabled"
  schema_validation_enabled    = false
  sku                          = "F0"
  tags                         = local.common_tags
  enable_telemetry             = false

  channels = {
    teams = {
      name         = "MsTeamsChannel"
      channel_name = "MsTeamsChannel"
      location     = "global"
    }
  }
}