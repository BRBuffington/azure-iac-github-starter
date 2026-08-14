targetScope = 'resourceGroup'

@description('Azure AI Search service name in the module deployment resource group.')
param aiSearchName string

@description('System-assigned principal ID of the Foundry project.')
param projectPrincipalId string

resource aiSearch 'Microsoft.Search/searchServices@2024-06-01-preview' existing = {
  name: aiSearchName
}

resource searchIndexDataContributorRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: subscription()
  name: '8ebe5a00-799e-43f5-93ac-243d3dce84a7'
}

resource searchServiceContributorRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: subscription()
  name: '7ca78c08-252a-4471-8644-bb5ff32d4ba0'
}

resource searchIndexDataContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: aiSearch
  name: guid(aiSearch.id, projectPrincipalId, searchIndexDataContributorRoleDefinition.id)
  properties: {
    principalId: projectPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: searchIndexDataContributorRoleDefinition.id
  }
}

resource searchServiceContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: aiSearch
  name: guid(aiSearch.id, projectPrincipalId, searchServiceContributorRoleDefinition.id)
  properties: {
    principalId: projectPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: searchServiceContributorRoleDefinition.id
  }
}

output roleAssignmentResourceIds array = [
  searchIndexDataContributorRoleAssignment.id
  searchServiceContributorRoleAssignment.id
]