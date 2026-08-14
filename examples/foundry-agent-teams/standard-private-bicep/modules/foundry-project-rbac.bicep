targetScope = 'resourceGroup'

@description('Foundry account name in the deployment resource group.')
param foundryAccountName string

@description('Foundry project name under the account.')
param projectName string

@description('System-assigned principal ID of the Foundry project.')
param projectPrincipalId string

resource foundryAccount 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = {
  name: foundryAccountName
}

resource foundryProject 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' existing = {
  parent: foundryAccount
  name: projectName
}

resource foundryUserRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: subscription()
  name: '53ca6127-db72-4b80-b1b0-d745d6d5456d'
}

resource projectFoundryUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: foundryProject
  name: guid(foundryProject.id, projectPrincipalId, foundryUserRoleDefinition.id)
  properties: {
    principalId: projectPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: foundryUserRoleDefinition.id
  }
}

output roleAssignmentResourceId string = projectFoundryUserRoleAssignment.id