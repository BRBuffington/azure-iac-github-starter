targetScope = 'resourceGroup'

@description('Cosmos DB account name in the module deployment resource group.')
param cosmosDbAccountName string

@description('System-assigned principal ID of the Foundry project.')
param projectPrincipalId string

resource cosmosDbAccount 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' existing = {
  name: cosmosDbAccountName
}

resource cosmosDbOperatorRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: subscription()
  name: '230815da-be43-4aae-9cb4-875f7bd000aa'
}

resource cosmosDbOperatorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: cosmosDbAccount
  name: guid(cosmosDbAccount.id, projectPrincipalId, cosmosDbOperatorRoleDefinition.id)
  properties: {
    principalId: projectPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: cosmosDbOperatorRoleDefinition.id
  }
}

output roleAssignmentResourceId string = cosmosDbOperatorRoleAssignment.id