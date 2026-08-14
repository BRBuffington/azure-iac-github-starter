targetScope = 'resourceGroup'

@description('Azure region for the private endpoints.')
param location string

@description('Short lowercase prefix for private endpoint names.')
@minLength(2)
@maxLength(32)
param namePrefix string

@description('Full resource ID of the subnet that hosts private endpoints.')
param privateEndpointSubnetResourceId string

@description('Foundry account resource ID.')
param foundryAccountResourceId string

@description('Existing Storage account resource ID.')
param storageAccountResourceId string

@description('Existing Cosmos DB account resource ID.')
param cosmosDbAccountResourceId string

@description('Existing Azure AI Search resource ID.')
param aiSearchResourceId string

@description('Foundry private DNS zone resource IDs for services.ai, openai, and cognitiveservices.')
@minLength(3)
@maxLength(3)
param foundryPrivateDnsZoneResourceIds array

@description('Storage blob private DNS zone resource ID.')
param storageBlobPrivateDnsZoneResourceId string

@description('Cosmos DB private DNS zone resource ID.')
param cosmosDbPrivateDnsZoneResourceId string

@description('Azure AI Search private DNS zone resource ID.')
param aiSearchPrivateDnsZoneResourceId string

@description('Create a Storage blob private endpoint and DNS zone group.')
param createStoragePrivateEndpoint bool = true

@description('Create a Cosmos DB private endpoint and DNS zone group.')
param createCosmosDbPrivateEndpoint bool = true

@description('Create an Azure AI Search private endpoint and DNS zone group.')
param createAiSearchPrivateEndpoint bool = true

@description('Tags applied to each private endpoint.')
param tags object = {}

var foundryAccountParts = split(foundryAccountResourceId, '/')
var storageAccountParts = split(storageAccountResourceId, '/')
var cosmosDbAccountParts = split(cosmosDbAccountResourceId, '/')
var aiSearchParts = split(aiSearchResourceId, '/')

resource foundryAccount 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = {
  name: last(foundryAccountParts)
  scope: resourceGroup(foundryAccountParts[2], foundryAccountParts[4])
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

resource foundryPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${namePrefix}-foundry'
  location: location
  properties: {
    subnet: {
      id: privateEndpointSubnetResourceId
    }
    privateLinkServiceConnections: [
      {
        name: 'psc-${namePrefix}-foundry'
        properties: {
          privateLinkServiceId: foundryAccount.id
          groupIds: [
            'account'
          ]
        }
      }
    ]
  }
  tags: tags
}

resource foundryDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: foundryPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [for (zoneId, index) in foundryPrivateDnsZoneResourceIds: {
      name: 'foundry-${index}'
      properties: {
        privateDnsZoneId: zoneId
      }
    }]
  }
}

resource storagePrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = if (createStoragePrivateEndpoint) {
  name: 'pe-${namePrefix}-storage'
  location: location
  properties: {
    subnet: {
      id: privateEndpointSubnetResourceId
    }
    privateLinkServiceConnections: [
      {
        name: 'psc-${namePrefix}-storage'
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: [
            'blob'
          ]
        }
      }
    ]
  }
  tags: tags
}

resource storageDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = if (createStoragePrivateEndpoint) {
  parent: storagePrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'blob'
        properties: {
          privateDnsZoneId: storageBlobPrivateDnsZoneResourceId
        }
      }
    ]
  }
}

resource cosmosDbPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = if (createCosmosDbPrivateEndpoint) {
  name: 'pe-${namePrefix}-cosmos'
  location: location
  properties: {
    subnet: {
      id: privateEndpointSubnetResourceId
    }
    privateLinkServiceConnections: [
      {
        name: 'psc-${namePrefix}-cosmos'
        properties: {
          privateLinkServiceId: cosmosDbAccount.id
          groupIds: [
            'Sql'
          ]
        }
      }
    ]
  }
  tags: tags
}

resource cosmosDbDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = if (createCosmosDbPrivateEndpoint) {
  parent: cosmosDbPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'sql'
        properties: {
          privateDnsZoneId: cosmosDbPrivateDnsZoneResourceId
        }
      }
    ]
  }
}

resource aiSearchPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = if (createAiSearchPrivateEndpoint) {
  name: 'pe-${namePrefix}-search'
  location: location
  properties: {
    subnet: {
      id: privateEndpointSubnetResourceId
    }
    privateLinkServiceConnections: [
      {
        name: 'psc-${namePrefix}-search'
        properties: {
          privateLinkServiceId: aiSearch.id
          groupIds: [
            'searchService'
          ]
        }
      }
    ]
  }
  tags: tags
}

resource aiSearchDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = if (createAiSearchPrivateEndpoint) {
  parent: aiSearchPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'search'
        properties: {
          privateDnsZoneId: aiSearchPrivateDnsZoneResourceId
        }
      }
    ]
  }
}

output privateEndpointResourceIds object = {
  foundry: foundryPrivateEndpoint.id
  storage: storagePrivateEndpoint.?id ?? ''
  cosmosDb: cosmosDbPrivateEndpoint.?id ?? ''
  aiSearch: aiSearchPrivateEndpoint.?id ?? ''
}