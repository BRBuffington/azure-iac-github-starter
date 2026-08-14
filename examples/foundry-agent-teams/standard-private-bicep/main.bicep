targetScope = 'resourceGroup'

@description('Azure region for the Foundry account, project, and agent subnet.')
param location string = resourceGroup().location

@description('Globally unique Microsoft Foundry AIServices account name.')
@minLength(2)
@maxLength(64)
param foundryAccountName string

@description('Foundry project name.')
@minLength(2)
@maxLength(64)
param projectName string

@description('Foundry project display name.')
param projectDisplayName string

@description('Model deployment name used by the Prompt Agent definition.')
param modelDeploymentName string

@description('Model catalog name available in the selected region.')
param modelName string

@description('Pinned model version available in the selected region.')
param modelVersion string

@description('Model deployment SKU.')
param modelSkuName string = 'GlobalStandard'

@description('Model deployment capacity in provider-defined units.')
@minValue(1)
param modelCapacity int = 1

@description('Full resource ID of a dedicated RFC1918 subnet delegated to Microsoft.App/environments.')
@minLength(1)
param agentSubnetResourceId string

@description('Full resource ID of the subnet that hosts private endpoints.')
@minLength(1)
param privateEndpointSubnetResourceId string

@description('Existing Storage account resource ID used for agent files.')
@minLength(1)
param storageAccountResourceId string

@description('Existing Cosmos DB account resource ID used for agent thread storage.')
@minLength(1)
param cosmosDbAccountResourceId string

@description('Existing Azure AI Search resource ID used for agent vector stores.')
@minLength(1)
param aiSearchResourceId string

@description('Create a workload-owned Storage blob private endpoint. Set false when the platform already provides one reachable from the agent subnet.')
param createStoragePrivateEndpoint bool = true

@description('Create a workload-owned Cosmos DB private endpoint. Set false when the platform already provides one reachable from the agent subnet.')
param createCosmosDbPrivateEndpoint bool = true

@description('Create a workload-owned Azure AI Search private endpoint. Set false when the platform already provides one reachable from the agent subnet.')
param createAiSearchPrivateEndpoint bool = true

@description('Project capability host name.')
@minLength(2)
@maxLength(64)
param projectCapabilityHostName string = 'caphostproj'

@description('Prompt Agent name. Required when agentPrincipalId is set.')
param agentName string = ''

@description('Prompt Agent instance_identity.principal_id. Leave empty on the foundation deployment.')
param agentPrincipalId string = ''

@description('Azure Bot Service name. Required when agentPrincipalId is set.')
param botName string = ''

@description('Azure Bot Service display name. Required when agentPrincipalId is set.')
param botDisplayName string = ''

@description('Existing privatelink.services.ai.azure.com private DNS zone resource ID.')
@minLength(1)
param foundryServicesPrivateDnsZoneResourceId string

@description('Existing privatelink.openai.azure.com private DNS zone resource ID.')
@minLength(1)
param openAiPrivateDnsZoneResourceId string

@description('Existing privatelink.cognitiveservices.azure.com private DNS zone resource ID.')
@minLength(1)
param cognitiveServicesPrivateDnsZoneResourceId string

@description('Existing privatelink.blob.core.windows.net private DNS zone resource ID.')
@minLength(1)
param storageBlobPrivateDnsZoneResourceId string

@description('Existing privatelink.documents.azure.com private DNS zone resource ID.')
@minLength(1)
param cosmosDbPrivateDnsZoneResourceId string

@description('Existing privatelink.search.windows.net private DNS zone resource ID.')
@minLength(1)
param aiSearchPrivateDnsZoneResourceId string

@description('Short lowercase prefix for private endpoint names.')
@minLength(2)
@maxLength(32)
param namePrefix string

@description('Repository that owns this deployment, for example Contoso/foundry-agent.')
@minLength(1)
param deployedByRepo string

@description('Configuration name that owns this deployment.')
@minLength(1)
param deployedConfig string

@description('Client environment label.')
@minLength(1)
param environment string

@description('Additional client tags merged with required provenance tags.')
param tags object = {}

var commonTags = union(tags, {
  DeployedByRepo: deployedByRepo
  DeployedConfig: deployedConfig
  Environment: environment
  Architecture: 'foundry-agent-teams-standard-private-bicep'
})
var storageAccountParts = split(storageAccountResourceId, '/')
var cosmosDbAccountParts = split(cosmosDbAccountResourceId, '/')
var aiSearchParts = split(aiSearchResourceId, '/')
var storageConnectionName = '${projectName}-storage'
var cosmosDbConnectionName = '${projectName}-cosmos'
var aiSearchConnectionName = '${projectName}-search'
var createBotService = !empty(agentPrincipalId)
var projectEndpoint = 'https://${foundryAccountName}.services.ai.azure.com/api/projects/${projectName}'

resource foundryAccount 'Microsoft.CognitiveServices/accounts@2025-06-01' = {
  name: foundryAccountName
  location: location
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    allowProjectManagement: true
    customSubDomainName: foundryAccountName
    disableLocalAuth: true
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
      ipRules: []
      virtualNetworkRules: []
    }
    networkInjections: [
      {
        scenario: 'agent'
        subnetArmId: agentSubnetResourceId
        useMicrosoftManagedNetwork: false
      }
    ]
  }
  tags: commonTags
}

resource modelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = {
  parent: foundryAccount
  name: modelDeploymentName
  sku: {
    name: modelSkuName
    capacity: modelCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: modelName
      version: modelVersion
    }
    versionUpgradeOption: 'NoAutoUpgrade'
  }
}

resource foundryProject 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' = {
  parent: foundryAccount
  name: projectName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: projectDisplayName
    description: 'Standard network-secured Microsoft Foundry Agent Service project.'
  }
  tags: commonTags
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: last(storageAccountParts)
  scope: resourceGroup(storageAccountParts[2], storageAccountParts[4])
}

resource cosmosDbAccount 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' existing = {
  name: last(cosmosDbAccountParts)
  scope: resourceGroup(cosmosDbAccountParts[2], cosmosDbAccountParts[4])
}

resource aiSearch 'Microsoft.Search/searchServices@2024-06-01-preview' existing = {
  name: last(aiSearchParts)
  scope: resourceGroup(aiSearchParts[2], aiSearchParts[4])
}

resource storageConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01' = {
  parent: foundryProject
  name: storageConnectionName
  properties: {
    category: 'AzureStorageAccount'
    target: storageAccount.properties.primaryEndpoints.blob
    authType: 'AAD'
    metadata: {
      ApiType: 'Azure'
      ResourceId: storageAccount.id
      location: storageAccount.location
    }
  }
}

resource cosmosDbConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01' = {
  parent: foundryProject
  name: cosmosDbConnectionName
  properties: {
    category: 'CosmosDB'
    target: cosmosDbAccount.properties.documentEndpoint
    authType: 'AAD'
    metadata: {
      ApiType: 'Azure'
      ResourceId: cosmosDbAccount.id
      location: cosmosDbAccount.location
    }
  }
}

resource aiSearchConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01' = {
  parent: foundryProject
  name: aiSearchConnectionName
  properties: {
    category: 'CognitiveSearch'
    target: 'https://${aiSearch.name}.search.windows.net'
    authType: 'AAD'
    metadata: {
      ApiType: 'Azure'
      ApiVersion: '2024-05-01-preview'
      ResourceId: aiSearch.id
      location: aiSearch.location
    }
  }
}

module foundryProjectRbac 'modules/foundry-project-rbac.bicep' = {
  name: '${namePrefix}-foundry-project-rbac'
  params: {
    foundryAccountName: foundryAccount.name
    projectName: foundryProject.name
    projectPrincipalId: foundryProject.identity.principalId
  }
}

module storageControlPlaneRbac 'modules/storage-control-plane-rbac.bicep' = {
  name: '${namePrefix}-storage-control-rbac'
  scope: resourceGroup(storageAccountParts[2], storageAccountParts[4])
  params: {
    storageAccountName: storageAccount.name
    projectPrincipalId: foundryProject.identity.principalId
  }
}

module cosmosDbControlPlaneRbac 'modules/cosmos-control-plane-rbac.bicep' = {
  name: '${namePrefix}-cosmos-control-rbac'
  scope: resourceGroup(cosmosDbAccountParts[2], cosmosDbAccountParts[4])
  params: {
    cosmosDbAccountName: cosmosDbAccount.name
    projectPrincipalId: foundryProject.identity.principalId
  }
}

module aiSearchProjectRbac 'modules/search-project-rbac.bicep' = {
  name: '${namePrefix}-search-project-rbac'
  scope: resourceGroup(aiSearchParts[2], aiSearchParts[4])
  params: {
    aiSearchName: aiSearch.name
    projectPrincipalId: foundryProject.identity.principalId
  }
}

resource projectCapabilityHost 'Microsoft.CognitiveServices/accounts/projects/capabilityHosts@2025-06-01' = {
  parent: foundryProject
  name: projectCapabilityHostName
  properties: {
    #disable-next-line BCP037
    capabilityHostKind: 'Agents'
    storageConnections: [
      storageConnection.name
    ]
    threadStorageConnections: [
      cosmosDbConnection.name
    ]
    vectorStoreConnections: [
      aiSearchConnection.name
    ]
  }
  dependsOn: [
    foundryProjectRbac
    storageControlPlaneRbac
    cosmosDbControlPlaneRbac
    aiSearchProjectRbac
  ]
}

// The 2025-06-01 Bicep schema omits the read-only project internalId.
#disable-next-line BCP053
var projectInternalId = foundryProject.properties.internalId
var projectWorkspaceId = '${substring(projectInternalId, 0, 8)}-${substring(projectInternalId, 8, 4)}-${substring(projectInternalId, 12, 4)}-${substring(projectInternalId, 16, 4)}-${substring(projectInternalId, 20, 12)}'

module storageDataPlaneRbac 'modules/storage-data-plane-rbac.bicep' = {
  name: '${namePrefix}-storage-data-rbac'
  scope: resourceGroup(storageAccountParts[2], storageAccountParts[4])
  params: {
    storageAccountName: storageAccount.name
    projectPrincipalId: foundryProject.identity.principalId
    projectWorkspaceId: projectWorkspaceId
  }
  dependsOn: [
    projectCapabilityHost
  ]
}

module cosmosDbDataPlaneRbac 'modules/cosmos-data-plane-rbac.bicep' = {
  name: '${namePrefix}-cosmos-data-rbac'
  scope: resourceGroup(cosmosDbAccountParts[2], cosmosDbAccountParts[4])
  params: {
    cosmosDbAccountName: cosmosDbAccount.name
    projectPrincipalId: foundryProject.identity.principalId
    projectWorkspaceId: projectWorkspaceId
  }
  dependsOn: [
    projectCapabilityHost
  ]
}

module privateEndpoints 'modules/private-endpoints.bicep' = {
  name: '${namePrefix}-private-endpoints'
  params: {
    location: location
    namePrefix: namePrefix
    privateEndpointSubnetResourceId: privateEndpointSubnetResourceId
    foundryAccountResourceId: foundryAccount.id
    storageAccountResourceId: storageAccountResourceId
    cosmosDbAccountResourceId: cosmosDbAccountResourceId
    aiSearchResourceId: aiSearchResourceId
    foundryPrivateDnsZoneResourceIds: [
      foundryServicesPrivateDnsZoneResourceId
      openAiPrivateDnsZoneResourceId
      cognitiveServicesPrivateDnsZoneResourceId
    ]
    storageBlobPrivateDnsZoneResourceId: storageBlobPrivateDnsZoneResourceId
    cosmosDbPrivateDnsZoneResourceId: cosmosDbPrivateDnsZoneResourceId
    aiSearchPrivateDnsZoneResourceId: aiSearchPrivateDnsZoneResourceId
    createStoragePrivateEndpoint: createStoragePrivateEndpoint
    createCosmosDbPrivateEndpoint: createCosmosDbPrivateEndpoint
    createAiSearchPrivateEndpoint: createAiSearchPrivateEndpoint
    tags: commonTags
  }
}

module botService 'modules/bot-service.bicep' = if (createBotService) {
  name: '${namePrefix}-bot-service'
  params: {
    botName: botName
    displayName: botDisplayName
    agentPrincipalId: agentPrincipalId
    tenantId: tenant().tenantId
    activityEndpoint: '${projectEndpoint}/agents/${agentName}/endpoint/protocols/activityProtocol?api-version=2025-05-15-preview'
    tags: commonTags
  }
}

output foundryAccountResourceId string = foundryAccount.id
output projectResourceId string = foundryProject.id
output projectPrincipalId string = foundryProject.identity.principalId
output projectCapabilityHostResourceId string = projectCapabilityHost.id
output projectEndpoint string = projectEndpoint
output modelNameForAgent string = modelDeployment.name
output privateEndpointResourceIds object = privateEndpoints.outputs.privateEndpointResourceIds
output botServiceResourceId string = botService.?outputs.botServiceResourceId ?? ''
output connectionNames object = {
  storage: storageConnection.name
  cosmosDb: cosmosDbConnection.name
  aiSearch: aiSearchConnection.name
}