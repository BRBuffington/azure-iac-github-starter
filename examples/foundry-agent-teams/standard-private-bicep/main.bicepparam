using './main.bicep'

param location = 'eastus'
param foundryAccountName = 'aif-client-agent-eus-prd'
param projectName = 'agent-teams'
param projectDisplayName = 'Client Private Agent'
param modelDeploymentName = 'gpt-5-mini'
param modelName = 'gpt-5-mini'
param modelVersion = 'replace-with-region-supported-version'
param modelSkuName = 'GlobalStandard'
param modelCapacity = 1

param agentSubnetResourceId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-client-network-eus-prd/providers/Microsoft.Network/virtualNetworks/vnet-client-eus-prd/subnets/snet-foundry-agent'
param privateEndpointSubnetResourceId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-client-network-eus-prd/providers/Microsoft.Network/virtualNetworks/vnet-client-eus-prd/subnets/snet-private-endpoints'

param storageAccountResourceId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-client-data-eus-prd/providers/Microsoft.Storage/storageAccounts/stclientagentprd'
param cosmosDbAccountResourceId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-client-data-eus-prd/providers/Microsoft.DocumentDB/databaseAccounts/cosmos-client-agent-prd'
param aiSearchResourceId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-client-data-eus-prd/providers/Microsoft.Search/searchServices/srch-client-agent-prd'
param createStoragePrivateEndpoint = true
param createCosmosDbPrivateEndpoint = true
param createAiSearchPrivateEndpoint = true

param foundryServicesPrivateDnsZoneResourceId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-client-dns/providers/Microsoft.Network/privateDnsZones/privatelink.services.ai.azure.com'
param openAiPrivateDnsZoneResourceId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-client-dns/providers/Microsoft.Network/privateDnsZones/privatelink.openai.azure.com'
param cognitiveServicesPrivateDnsZoneResourceId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-client-dns/providers/Microsoft.Network/privateDnsZones/privatelink.cognitiveservices.azure.com'
param storageBlobPrivateDnsZoneResourceId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-client-dns/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net'
param cosmosDbPrivateDnsZoneResourceId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-client-dns/providers/Microsoft.Network/privateDnsZones/privatelink.documents.azure.com'
param aiSearchPrivateDnsZoneResourceId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-client-dns/providers/Microsoft.Network/privateDnsZones/privatelink.search.windows.net'

param namePrefix = 'client-agent'
param projectCapabilityHostName = 'caphostproj'

// Stage 1 leaves agentPrincipalId empty. The delegated configure operation emits
// an ARM parameter file that supplies these four values for Stage 2.
param agentName = 'client-agent'
param agentPrincipalId = ''
param botName = 'bot-client-agent'
param botDisplayName = 'Client Private Agent'

param deployedByRepo = 'Contoso/foundry-agent'
param deployedConfig = 'foundry-eus-prd'
param environment = 'prd'
param tags = {
  Workload: 'foundry-agent-teams'
}