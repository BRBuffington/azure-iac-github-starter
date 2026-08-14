targetScope = 'resourceGroup'

@description('Cosmos DB account name in the module deployment resource group.')
param cosmosDbAccountName string

@description('System-assigned principal ID of the Foundry project.')
param projectPrincipalId string

@description('Foundry project internal ID formatted as a GUID.')
param projectWorkspaceId string

resource cosmosDbAccount 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' existing = {
  name: cosmosDbAccountName
}

resource cosmosDbDataContributorRoleAssignment 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2022-05-15' = {
  parent: cosmosDbAccount
  name: guid(cosmosDbAccount.id, projectPrincipalId, projectWorkspaceId)
  properties: {
    principalId: projectPrincipalId
    roleDefinitionId: '${cosmosDbAccount.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002'
    scope: '${cosmosDbAccount.id}/dbs/enterprise_memory'
  }
}

output roleAssignmentResourceId string = cosmosDbDataContributorRoleAssignment.id