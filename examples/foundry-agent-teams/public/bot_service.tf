module "bot_service" {
  # checkov:skip=CKV_TF_1:Official AVM Registry module pinned to the exact 0.4.0 release returned by Terraform MCP.
  source  = "Azure/avm-res-botservice-botservice/azurerm"
  version = "0.4.0"

  for_each = local.agent_publications

  location            = "global"
  name                = each.value.bot_name
  resource_group_name = module.resource_group.name
  display_name        = each.value.display_name
  # Foundry's publication guide requires the Bot Service endpoint to remain the
  # agent activity-protocol URL. It is not replaced by a custom bot runtime or
  # proxy URL.
  endpoint = each.value.activity_endpoint
  # Foundry's publication contract intentionally maps
  # instance_identity.principal_id to Bot Service msaAppId. This differs from
  # ordinary bot-registration client-ID guidance; do not substitute client_id.
  # https://learn.microsoft.com/azure/foundry/agents/how-to/publish-copilot-virtual-network#step-1-get-the-agent-identity-and-tenant-id
  microsoft_app_id             = each.value.principal_id
  microsoft_app_tenant_id      = var.tenant_id
  microsoft_app_type           = "SingleTenant"
  local_authentication_enabled = false
  # Microsoft's Foundry-to-M365 template sets Bot Service publicNetworkAccess
  # to Disabled while enabling MsTeamsChannel. This setting does not disable the
  # Microsoft channel adapter integration.
  public_network_access     = "Disabled"
  schema_validation_enabled = false
  sku                       = "F0"
  tags                      = local.common_tags
  enable_telemetry          = false

  channels = {
    teams = {
      name         = "MsTeamsChannel"
      channel_name = "MsTeamsChannel"
      location     = "global"
    }
  }
}