#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory)][guid] $SubscriptionId,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $ResourceGroupName,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $VirtualNetworkName,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $SubnetName,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $NetworkSecurityGroupName,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $NetworkSettingsName,
    [Parameter(Mandatory)][ValidatePattern('^[0-9]+$')][string] $GitHubDatabaseId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-AzureCli {
    param([Parameter(ValueFromRemainingArguments)][string[]] $Arguments)

    $result = & az @Arguments --only-show-errors
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI failed with exit code ${LASTEXITCODE}: az $($Arguments -join ' ')"
    }
    return $result
}

Write-Host '1. Select the subscription using your existing Azure CLI sign-in.'
Invoke-AzureCli account set --subscription $SubscriptionId

Write-Host '2. Resolve the existing VNet, dedicated empty subnet, and reviewed NSG.'
$location = Invoke-AzureCli network vnet show --resource-group $ResourceGroupName `
    --name $VirtualNetworkName --query location --output tsv
$subnetId = Invoke-AzureCli network vnet subnet show --resource-group $ResourceGroupName `
    --vnet-name $VirtualNetworkName --name $SubnetName --query id --output tsv
$nsgId = Invoke-AzureCli network nsg show --resource-group $ResourceGroupName `
    --name $NetworkSecurityGroupName --query id --output tsv

if ([string]::IsNullOrWhiteSpace($location) -or [string]::IsNullOrWhiteSpace($subnetId) -or
    [string]::IsNullOrWhiteSpace($nsgId)) {
    throw 'The existing VNet location, subnet ID, and NSG ID must all resolve before setup.'
}

Write-Host '3. Register GitHub.Network and wait for registration.'
Invoke-AzureCli provider register --namespace GitHub.Network --wait --output none

Write-Host '4. Delegate the subnet and attach the existing NSG without changing its rules.'
Invoke-AzureCli network vnet subnet update --resource-group $ResourceGroupName `
    --vnet-name $VirtualNetworkName --name $SubnetName `
    --delegations GitHub.Network/networkSettings --network-security-group $nsgId --output none

Write-Host '5. Create NetworkSettings in the same resource group, subscription, and region.'
$propertiesPath = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
try {
    @{
        location = $location
        properties = @{
            subnetId = $subnetId
            businessId = $GitHubDatabaseId
        }
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $propertiesPath -Encoding utf8

    $settings = Invoke-AzureCli resource create --resource-group $ResourceGroupName `
        --name $NetworkSettingsName --resource-type GitHub.Network/networkSettings `
        --api-version 2024-04-02 --is-full-object --properties "@$propertiesPath" --output json |
        ConvertFrom-Json
}
finally {
    if (Test-Path -LiteralPath $propertiesPath) {
        Remove-Item -LiteralPath $propertiesPath
    }
}

if ([string]::IsNullOrWhiteSpace($settings.tags.GitHubId)) {
    throw 'NetworkSettings did not return tags.GitHubId. Check the Azure resource before continuing in GitHub.'
}

Write-Host '6. Use GitHubId below in GitHub Hosted compute networking, then configure the group and larger runner.'
[pscustomobject]@{
    GitHubId = $settings.tags.GitHubId
    NetworkSettingsName = $NetworkSettingsName
    SubnetId = $subnetId
    Location = $location
}