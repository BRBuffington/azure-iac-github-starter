targetScope = 'resourceGroup'

@description('Name of the existing shared virtual network.')
param vnetName string

@description('Name of the subnet dedicated to the Foundry agent runtime.')
param agentSubnetName string = 'snet-foundry-agent'

@description('Address prefix allocated to the Foundry agent runtime subnet.')
param agentSubnetPrefix string

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: vnetName
}

resource agentSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: vnet
  name: agentSubnetName
  properties: {
    addressPrefix: agentSubnetPrefix
    delegations: [
      {
        name: 'foundryAgentDelegation'
        properties: {
          serviceName: 'Microsoft.App/environments'
        }
      }
    ]
  }
}

output agentSubnetId string = agentSubnet.id