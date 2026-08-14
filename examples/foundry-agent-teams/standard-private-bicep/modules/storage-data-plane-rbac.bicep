targetScope = 'resourceGroup'

@description('Storage account name in the module deployment resource group.')
param storageAccountName string

@description('System-assigned principal ID of the Foundry project.')
param projectPrincipalId string

@description('Foundry project internal ID formatted as a GUID.')
param projectWorkspaceId string

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

resource storageBlobDataOwnerRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: subscription()
  name: 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
}

var storageBlobOwnerCondition = '((!(ActionMatches{\'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/tags/read\'}) AND !(ActionMatches{\'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/filter/action\'}) AND !(ActionMatches{\'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/tags/write\'})) OR (@Resource[Microsoft.Storage/storageAccounts/blobServices/containers:name] StringStartsWithIgnoreCase \'${projectWorkspaceId}\' AND @Resource[Microsoft.Storage/storageAccounts/blobServices/containers:name] StringLikeIgnoreCase \'*-azureml-agent\'))'

resource storageBlobDataOwnerRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(storageAccount.id, projectPrincipalId, storageBlobDataOwnerRoleDefinition.id, projectWorkspaceId)
  properties: {
    principalId: projectPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: storageBlobDataOwnerRoleDefinition.id
    conditionVersion: '2.0'
    condition: storageBlobOwnerCondition
  }
}

output roleAssignmentResourceId string = storageBlobDataOwnerRoleAssignment.id