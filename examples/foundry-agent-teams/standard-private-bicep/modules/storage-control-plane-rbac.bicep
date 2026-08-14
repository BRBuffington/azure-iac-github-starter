targetScope = 'resourceGroup'

@description('Storage account name in the module deployment resource group.')
param storageAccountName string

@description('System-assigned principal ID of the Foundry project.')
param projectPrincipalId string

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

resource storageBlobDataContributorRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: subscription()
  name: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
}

resource storageBlobDataContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(storageAccount.id, projectPrincipalId, storageBlobDataContributorRoleDefinition.id)
  properties: {
    principalId: projectPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: storageBlobDataContributorRoleDefinition.id
  }
}

output roleAssignmentResourceId string = storageBlobDataContributorRoleAssignment.id