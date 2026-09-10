Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $PSScriptRoot '../github-preparation.ps1'
$parameters = @{
    SubscriptionId = '11111111-1111-1111-1111-111111111111'
    ResourceGroupName = 'rg-example-eus'
    VirtualNetworkName = 'vnet-example-eus'
    SubnetName = 'snet-example-runners'
    NetworkSecurityGroupName = 'nsg-example-runners'
    NetworkSettingsName = 'github-example-eus'
    GitHubDatabaseId = '123456'
}
$resourcePrefix = "/subscriptions/$($parameters.SubscriptionId)/resourceGroups/$($parameters.ResourceGroupName)"
$expectedSubnetId = "$resourcePrefix/providers/Microsoft.Network/virtualNetworks/$($parameters.VirtualNetworkName)/subnets/$($parameters.SubnetName)"
$expectedNsgId = "$resourcePrefix/providers/Microsoft.Network/networkSecurityGroups/$($parameters.NetworkSecurityGroupName)"
$calls = [System.Collections.Generic.List[object]]::new()
$failureCommand = ''
$returnedGitHubId = 'github-settings-example'
$capture = @{ Payload = $null; Path = '' }

function Assert-Equal {
    param($Actual, $Expected, [string] $Message)
    if ($Actual -cne $Expected) {
        throw "$Message. Expected '$Expected', got '$Actual'."
    }
}

function Get-ArgumentValue {
    param([string[]] $Arguments, [string] $Name)
    $position = [Array]::IndexOf($Arguments, $Name)
    if ($position -lt 0) {
        throw "Missing argument $Name."
    }
    return $Arguments[$position + 1]
}

function az {
    $arguments = [string[]] $args
    $calls.Add($arguments)
    $global:LASTEXITCODE = 0
    $command = $arguments -join ' '
    if ($failureCommand -and $command.StartsWith($failureCommand)) {
        $global:LASTEXITCODE = 7
        return
    }

    switch -Regex ($command) {
        '^account set ' { return }
        '^network vnet show ' { return 'eastus' }
        '^network vnet subnet show ' { return $expectedSubnetId }
        '^network nsg show ' { return $expectedNsgId }
        '^provider register ' { return }
        '^network vnet subnet update ' { return }
        '^resource create ' {
            $capture.Path = (Get-ArgumentValue $arguments '--properties').Substring(1)
            $capture.Payload = Get-Content -LiteralPath $capture.Path -Raw | ConvertFrom-Json
            return (@{ tags = @{ GitHubId = $returnedGitHubId } } | ConvertTo-Json)
        }
        default { throw "Unexpected Azure CLI command: $command" }
    }
}

$result = & $scriptPath @parameters
Assert-Equal $result.GitHubId 'github-settings-example' 'Return the GitHub handoff ID, not an Azure resource ID'
Assert-Equal $result.SubnetId $expectedSubnetId 'Reuse the existing subnet ID'
Assert-Equal $capture.Payload.location 'eastus' 'Derive the region from the existing VNet'
Assert-Equal $capture.Payload.properties.subnetId $expectedSubnetId 'Bind NetworkSettings to the supplied subnet'
Assert-Equal $capture.Payload.properties.businessId '123456' 'Use the supplied numeric GitHub database ID'
Assert-Equal ($capture.Payload.properties.businessId -is [string]) $true 'Serialize businessId as a string'
Assert-Equal (Test-Path -LiteralPath $capture.Path) $false 'Remove only the temporary JSON payload after use'

$delegation = @($calls | Where-Object { ($_ -join ' ') -match '^network vnet subnet update ' })[0]
Assert-Equal (Get-ArgumentValue $delegation '--resource-group') $parameters.ResourceGroupName 'Use the existing resource group'
Assert-Equal (Get-ArgumentValue $delegation '--vnet-name') $parameters.VirtualNetworkName 'Use the existing VNet name'
Assert-Equal (Get-ArgumentValue $delegation '--name') $parameters.SubnetName 'Use the existing subnet name'
Assert-Equal (Get-ArgumentValue $delegation '--delegations') 'GitHub.Network/networkSettings' 'Use the documented subnet delegation'
Assert-Equal (Get-ArgumentValue $delegation '--network-security-group') $expectedNsgId 'Attach the resolved existing NSG'
$creation = @($calls | Where-Object { ($_ -join ' ') -match '^resource create ' })[0]
Assert-Equal (Get-ArgumentValue $creation '--resource-type') 'GitHub.Network/networkSettings' 'Create only the APN settings resource'
Assert-Equal (Get-ArgumentValue $creation '--api-version') '2024-04-02' 'Use the current documented API version'
Assert-Equal ($creation -contains '--is-full-object') $true 'Send the location and properties in one JSON object'
$registration = @($calls | Where-Object { ($_ -join ' ') -match '^provider register ' })[0]
Assert-Equal ($registration -contains '--wait') $true 'Wait for provider registration before delegation'

foreach ($failureCommand in @(
    'account set ', 'network vnet show ', 'network vnet subnet show ', 'network nsg show ',
    'provider register ', 'network vnet subnet update ', 'resource create '
)) {
    $calls.Clear()
    $failed = $false
    try {
        & $scriptPath @parameters | Out-Null
    }
    catch {
        $failed = $_.Exception.Message -like 'Azure CLI failed with exit code 7:*'
    }
    Assert-Equal $failed $true "Stop on a failed $failureCommand command"
    Assert-Equal (($calls[$calls.Count - 1] -join ' ').StartsWith($failureCommand)) $true 'Do not continue after a CLI failure'
}

$failureCommand = ''
$returnedGitHubId = ''
$failed = $false
try {
    & $scriptPath @parameters | Out-Null
}
catch {
    $failed = $_.Exception.Message -like 'NetworkSettings did not return tags.GitHubId.*'
}
Assert-Equal $failed $true 'Do not report success without a GitHub handoff ID'
Assert-Equal (Test-Path -LiteralPath $capture.Path) $false 'Clean up the temporary payload on failure'
$global:LASTEXITCODE = 0
Write-Output 'github-preparation walkthrough tests passed; all Azure CLI calls were mocked.'