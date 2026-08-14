using './main.bicep'

// Client environment facts. Resource names, model settings, SKUs, and project
// metadata use overridable defaults from main.bicep.
param location = 'eastus2'
param locationShortName = 'eus2'
param existingVnetResourceId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-client-network-eus2-prd/providers/Microsoft.Network/virtualNetworks/vnet-client-eus2-prd'
param reuseExistingSubnets = true

// Omit these when the deployment should create its own zones. Set per-zone
// overrides in existingDnsZones or existingMonitorDnsZones only for exceptions.
param existingDnsZonesResourceGroup = 'rg-client-dns'
param existingMonitorDnsZonesResourceGroup = 'rg-client-dns'
