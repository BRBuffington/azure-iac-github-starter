targetScope = 'resourceGroup'

@description('Azure Bot Service resource name.')
@minLength(2)
@maxLength(42)
param botName string

@description('Bot display name shown in Azure and Microsoft 365.')
@minLength(1)
param displayName string

@description('Prompt Agent instance_identity.principal_id required by the Foundry publication contract.')
param agentPrincipalId string

@description('Microsoft Entra tenant ID for the SingleTenant bot.')
param tenantId string

@description('Foundry activity protocol endpoint for the Prompt Agent.')
param activityEndpoint string

@description('Tags applied to Azure Bot Service.')
param tags object = {}

resource botService 'Microsoft.BotService/botServices@2022-09-15' = {
  name: botName
  location: 'global'
  kind: 'azurebot'
  sku: {
    name: 'F0'
  }
  properties: {
    displayName: displayName
    // Microsoft Step 2 requires this exact Foundry activity-protocol URL.
    // Step 5 makes its hostname publicly reachable through DNS, DNAT, TLS, and
    // reverse proxy; it does not replace the Bot Service endpoint with a proxy URL.
    // https://learn.microsoft.com/azure/foundry/agents/how-to/publish-copilot-virtual-network#step-2-create-the-azure-bot-service-resource
    endpoint: activityEndpoint
    msaAppId: agentPrincipalId
    msaAppTenantId: tenantId
    msaAppType: 'SingleTenant'
    publicNetworkAccess: 'Disabled'
  }
  tags: tags
}

resource teamsChannel 'Microsoft.BotService/botServices/channels@2021-03-01' = {
  parent: botService
  name: 'MsTeamsChannel'
  location: 'global'
  properties: {
    channelName: 'MsTeamsChannel'
  }
}

output botServiceResourceId string = botService.id
output teamsChannelResourceId string = teamsChannel.id