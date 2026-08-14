targetScope = 'resourceGroup'

@description('Azure Bot Service resource name.')
param botName string

@description('Display name shown in Azure and Microsoft 365.')
param displayName string = 'Private Foundry agent'

@description('Prompt Agent instance_identity.principal_id from Step 1.')
param agentPrincipalId string

@description('Microsoft Entra tenant ID returned by Step 1.')
param tenantId string

@description('Prompt Agent activity protocol endpoint returned by Step 1.')
param activityEndpoint string

@description('Bot Service SKU.')
@allowed([
  'F0'
  'S1'
])
param botServiceSku string = 'F0'

resource botService 'Microsoft.BotService/botServices@2022-09-15' = {
  name: botName
  kind: 'azurebot'
  location: 'global'
  sku: {
    name: botServiceSku
  }
  properties: {
    displayName: displayName
    endpoint: activityEndpoint
    msaAppId: agentPrincipalId
    msaAppTenantId: tenantId
    msaAppType: 'SingleTenant'
    publicNetworkAccess: 'Disabled'
  }
}

resource teamsChannel 'Microsoft.BotService/botServices/channels@2021-03-01' = {
  parent: botService
  name: 'MsTeamsChannel'
  location: 'global'
  properties: {
    channelName: 'MsTeamsChannel'
  }
}

output botServiceArmId string = botService.id