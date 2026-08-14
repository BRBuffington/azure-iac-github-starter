#requires -Version 7.1

<#
.SYNOPSIS
Collects read-only network evidence for a private Microsoft Foundry agent.

.DESCRIPTION
Reports the Foundry account network posture, agent network injection, delegated
subnet, private endpoint connections, local and peered VNet address spaces,
visible Azure roles, and Azure Network Watcher VNet flow-log configuration.

The collector does not create or update resources. VNet flow logs are not
retroactive; enable them through the client's IaC before reproducing an issue.
New NSG flow logs are retired. Use Network Watcher VNet flow logs.

.EXAMPLE
./scripts/collect-network-diagnostics.ps1 `
  -ProjectEndpoint 'https://contoso-foundry.services.ai.azure.com/api/projects/my-project' `
  -BotName 'bot-contoso-agent-eus2-prd-001' `
  -BotResourceGroup 'rg-contoso-agent-eus2-prd'
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^https://.+/api/projects/[^/]+/?$')]
    [string]$ProjectEndpoint,

    [string]$BotName,

    [string]$BotResourceGroup,

    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$reservedCidrs = @(
    '169.254.0.0/16',
    '172.30.0.0/16',
    '172.31.0.0/16',
    '192.0.2.0/24',
    '0.0.0.0/8',
    '127.0.0.0/8',
    '100.100.0.0/17',
    '100.100.192.0/19',
    '100.100.224.0/19',
    '100.64.0.0/11'
)

function Invoke-AzJson {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,

        [Parameter(Mandatory)]
        [string]$Description,

        [switch]$Optional
    )

    $output = & az @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        if ($Optional) {
            Write-Warning "$Description was unavailable: $($output | Out-String)"
            return $null
        }
        throw "$Description failed.`n$($output | Out-String)"
    }

    $text = ($output | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }
    return $text | ConvertFrom-Json -AsHashtable
}

function ConvertTo-IPv4Number {
    param([Parameter(Mandatory)][string]$Address)

    $ip = [System.Net.IPAddress]::Parse($Address)
    if ($ip.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
        throw "$Address is not an IPv4 address."
    }
    $bytes = $ip.GetAddressBytes()
    return (
        ([uint64]$bytes[0] * 16777216) +
        ([uint64]$bytes[1] * 65536) +
        ([uint64]$bytes[2] * 256) +
        [uint64]$bytes[3]
    )
}

function Get-CidrRange {
    param([Parameter(Mandatory)][string]$Cidr)

    $parts = $Cidr.Split('/')
    if ($parts.Count -ne 2) {
        throw "$Cidr is not valid CIDR notation."
    }
    $prefix = [int]$parts[1]
    if ($prefix -lt 0 -or $prefix -gt 32) {
        throw "$Cidr has an invalid prefix length."
    }
    $size = [uint64][math]::Pow(2, 32 - $prefix)
    $address = ConvertTo-IPv4Number -Address $parts[0]
    $start = [uint64]([math]::Floor($address / $size) * $size)
    return [ordered]@{ Start = $start; End = $start + $size - 1 }
}

function Test-CidrOverlap {
    param(
        [Parameter(Mandatory)][string]$Left,
        [Parameter(Mandatory)][string]$Right
    )

    $leftRange = Get-CidrRange -Cidr $Left
    $rightRange = Get-CidrRange -Cidr $Right
    return $leftRange.Start -le $rightRange.End -and $rightRange.Start -le $leftRange.End
}

function Test-Rfc1918Cidr {
    param([Parameter(Mandatory)][string]$Cidr)

    return @('10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16') |
        Where-Object {
            $candidate = Get-CidrRange -Cidr $Cidr
            $private = Get-CidrRange -Cidr $_
            $candidate.Start -ge $private.Start -and $candidate.End -le $private.End
        } |
        Select-Object -First 1
}

function Get-RoleNames {
    param(
        [Parameter(Mandatory)][string]$AssigneeObjectId,
        [Parameter(Mandatory)][string]$Scope
    )

    $roles = Invoke-AzJson -Optional -Description "Reading role assignments on $Scope" -Arguments @(
        'role', 'assignment', 'list', '--assignee', $AssigneeObjectId,
        '--scope', $Scope, '--include-inherited', '--query', '[].roleDefinitionName', '-o', 'json'
    )
    return @($roles)
}

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI was not found. Install Azure CLI and open a new PowerShell session.'
}

$ProjectEndpoint = $ProjectEndpoint.TrimEnd('/')
$projectUri = [uri]$ProjectEndpoint
$foundryName = $projectUri.DnsSafeHost.Split('.')[0]
$projectName = $projectUri.Segments[-1].Trim('/')
$account = Invoke-AzJson -Description 'Reading the Azure CLI account' -Arguments @(
    'account', 'show', '--query', '{name:name,id:id,tenantId:tenantId,user:user.name}', '-o', 'json'
)
$subscriptionId = [string]$account.id

$accountLookup = Invoke-AzJson -Description "Locating Foundry account $foundryName" -Arguments @(
    'cognitiveservices', 'account', 'list', '--subscription', $subscriptionId,
    '--query', "[?name=='$foundryName'] | [0].{id:id,resourceGroup:resourceGroup}", '-o', 'json'
)
if ($null -eq $accountLookup) {
    throw "Foundry account $foundryName was not found in subscription $subscriptionId."
}

$foundry = Invoke-AzJson -Description "Reading Foundry account $foundryName with the preview ARM contract" -Arguments @(
    'rest', '--method', 'get',
    '--url', "https://management.azure.com$($accountLookup.id)?api-version=2025-04-01-preview",
    '-o', 'json'
)
$networkInjections = @($foundry.properties.networkInjections)
$agentInjection = $networkInjections | Where-Object { $_.scenario -eq 'agent' } | Select-Object -First 1
$subnetId = $(if ($null -eq $agentInjection) { '' } else { [string]$agentInjection.subnetArmId })
if ([string]::IsNullOrWhiteSpace($subnetId)) {
    throw 'The Foundry account does not expose networkInjections.scenario=agent with a subnetArmId.'
}

$subnetMatch = [regex]::Match(
    $subnetId,
    '^/subscriptions/([^/]+)/resourceGroups/([^/]+)/providers/Microsoft\.Network/virtualNetworks/([^/]+)/subnets/([^/]+)$',
    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
)
if (-not $subnetMatch.Success) {
    throw "Could not parse agent subnet resource ID: $subnetId"
}

$vnetSubscriptionId = $subnetMatch.Groups[1].Value
$vnetResourceGroup = $subnetMatch.Groups[2].Value
$vnetName = $subnetMatch.Groups[3].Value
$subnetName = $subnetMatch.Groups[4].Value
$vnetId = $subnetId.Substring(0, $subnetId.LastIndexOf('/subnets/', [System.StringComparison]::OrdinalIgnoreCase))

$subnet = Invoke-AzJson -Description "Reading agent subnet $subnetName" -Arguments @(
    'network', 'vnet', 'subnet', 'show', '--ids', $subnetId, '-o', 'json'
)
$vnet = Invoke-AzJson -Description "Reading VNet $vnetName" -Arguments @(
    'network', 'vnet', 'show', '--ids', $vnetId, '-o', 'json'
)
$peerings = @(Invoke-AzJson -Description "Reading peerings for $vnetName" -Arguments @(
    'network', 'vnet', 'peering', 'list', '--subscription', $vnetSubscriptionId,
    '--resource-group', $vnetResourceGroup, '--vnet-name', $vnetName, '-o', 'json'
))

$addressSpaces = [System.Collections.Generic.List[object]]::new()
foreach ($cidr in @($vnet.addressSpace.addressPrefixes)) {
    $addressSpaces.Add([ordered]@{ Source = "vnet:$vnetName"; Cidr = [string]$cidr })
}
foreach ($peering in $peerings) {
    $remoteId = [string]$peering.remoteVirtualNetwork.id
    if ([string]::IsNullOrWhiteSpace($remoteId)) {
        continue
    }
    $remoteVnet = Invoke-AzJson -Optional -Description "Reading peered VNet $remoteId" -Arguments @(
        'network', 'vnet', 'show', '--ids', $remoteId, '-o', 'json'
    )
    if ($null -eq $remoteVnet) {
        continue
    }
    foreach ($cidr in @($remoteVnet.addressSpace.addressPrefixes)) {
        $addressSpaces.Add([ordered]@{ Source = "peer:$($peering.name)"; Cidr = [string]$cidr })
    }
}

$cidrFindings = foreach ($entry in $addressSpaces) {
    $reservedOverlaps = @($reservedCidrs | Where-Object { Test-CidrOverlap -Left $entry.Cidr -Right $_ })
    [ordered]@{
        Source = $entry.Source
        Cidr = $entry.Cidr
        Rfc1918 = [bool](Test-Rfc1918Cidr -Cidr $entry.Cidr)
        ReservedOverlaps = $reservedOverlaps
    }
}

$privateEndpointConnections = @(Invoke-AzJson -Optional -Description 'Reading Foundry private endpoint connections' -Arguments @(
    'network', 'private-endpoint-connection', 'list', '--name', $foundryName,
    '--resource-group', [string]$accountLookup.resourceGroup,
    '--type', 'Microsoft.CognitiveServices/accounts', '--subscription', $subscriptionId,
    '--query', '[].{name:name,status:properties.privateLinkServiceConnectionState.status,state:properties.provisioningState}',
    '-o', 'json'
))

$flowLogs = @(Invoke-AzJson -Optional -Description "Reading Network Watcher VNet flow logs in $($vnet.location)" -Arguments @(
    'network', 'watcher', 'flow-log', 'list', '--location', [string]$vnet.location,
    '--subscription', $vnetSubscriptionId,
    '--query', '[].{name:name,enabled:enabled,target:targetResourceId,storage:storageId,analytics:flowAnalyticsConfiguration.networkWatcherFlowAnalyticsConfiguration.enabled,interval:flowAnalyticsConfiguration.networkWatcherFlowAnalyticsConfiguration.trafficAnalyticsInterval}',
    '-o', 'json'
))
$matchingFlowLogs = @($flowLogs | Where-Object {
    ([string]$_.target).StartsWith($vnetId, [System.StringComparison]::OrdinalIgnoreCase)
})

$signedInObjectId = (& az ad signed-in-user show --query id -o tsv 2>$null | Out-String).Trim()
$projectScope = "$($accountLookup.id)/projects/$projectName"
$foundryRoles = @()
$botRoles = @()
if (-not [string]::IsNullOrWhiteSpace($signedInObjectId)) {
    $foundryRoles = @(Get-RoleNames -AssigneeObjectId $signedInObjectId -Scope $projectScope)
    if (-not [string]::IsNullOrWhiteSpace($BotName) -and -not [string]::IsNullOrWhiteSpace($BotResourceGroup)) {
        $botScope = "/subscriptions/$subscriptionId/resourceGroups/$BotResourceGroup/providers/Microsoft.BotService/botServices/$BotName"
        $botRoles = @(Get-RoleNames -AssigneeObjectId $signedInObjectId -Scope $botScope)
    }
}

$delegations = @($subnet.delegations | ForEach-Object { [string]$_.serviceName })
$subnetPrefixes = @($subnet.addressPrefix) + @($subnet.addressPrefixes) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
$subnetPrefixLengths = @($subnetPrefixes | ForEach-Object { [int]([string]$_).Split('/')[1] })
$subnetIsRfc1918 = -not ($subnetPrefixes | Where-Object { -not (Test-Rfc1918Cidr -Cidr ([string]$_)) })
$subnetSizeSupported = -not ($subnetPrefixLengths | Where-Object { $_ -gt 27 })
$sameRegion = [string]$foundry.location -eq [string]$vnet.location
$report = [ordered]@{
    CollectedAt = [DateTimeOffset]::UtcNow.ToString('o')
    Subscription = [ordered]@{ Name = $account.name; Id = $subscriptionId; TenantId = $account.tenantId; User = $account.user }
    Foundry = [ordered]@{
        Name = $foundryName
        ResourceGroup = $accountLookup.resourceGroup
        Project = $projectName
        PublicNetworkAccess = $foundry.properties.publicNetworkAccess
        Location = $foundry.location
        NetworkInjectionScenario = $agentInjection.scenario
        AgentSubnetId = $subnetId
        PrivateEndpointConnections = $privateEndpointConnections
    }
    AgentSubnet = [ordered]@{
        Name = $subnetName
        Prefixes = $subnetPrefixes
        Delegations = $delegations
        HasRequiredDelegation = 'Microsoft.App/environments' -in $delegations
        IsRfc1918 = $subnetIsRfc1918
        SizeSupported = $subnetSizeSupported
    }
    FoundryAndVnetSameRegion = $sameRegion
    AddressSpaces = @($cidrFindings)
    Roles = [ordered]@{ FoundryProject = $foundryRoles; BotService = $botRoles }
    VnetFlowLogs = [ordered]@{
        Region = $vnet.location
        Matching = $matchingFlowLogs
        Present = $matchingFlowLogs.Count -gt 0
        Note = 'VNet flow logs are not retroactive. New NSG flow logs are retired.'
    }
}

Write-Host 'Foundry network diagnostics (read-only)'
Write-Host ("Foundry PNA       : {0}" -f $report.Foundry.PublicNetworkAccess)
Write-Host ("Network injection : {0}" -f $report.Foundry.NetworkInjectionScenario)
Write-Host ("Agent subnet       : {0}" -f $report.Foundry.AgentSubnetId)
Write-Host ("Delegation         : {0}" -f ($delegations -join ', '))
Write-Host ("Subnet RFC1918     : {0}" -f $subnetIsRfc1918)
Write-Host ("Subnet size >= /27 : {0}" -f $subnetSizeSupported)
Write-Host ("Same region        : {0} (Foundry={1}, VNet={2})" -f $sameRegion, $foundry.location, $vnet.location)
foreach ($finding in $cidrFindings) {
    $overlap = if ($finding.ReservedOverlaps.Count) { $finding.ReservedOverlaps -join ', ' } else { 'none' }
    Write-Host ("CIDR               : {0} {1} RFC1918={2} reserved-overlap={3}" -f $finding.Source, $finding.Cidr, $finding.Rfc1918, $overlap)
}
foreach ($connection in $privateEndpointConnections) {
    Write-Host ("Private endpoint   : {0} status={1} state={2}" -f $connection.name, $connection.status, $connection.state)
}
Write-Host ("Foundry roles       : {0}" -f $(if ($foundryRoles.Count) { $foundryRoles -join ', ' } else { 'none visible' }))
Write-Host ("Bot roles           : {0}" -f $(if ($botRoles.Count) { $botRoles -join ', ' } else { 'not requested or none visible' }))
Write-Host ("VNet flow logs      : {0}" -f $(if ($matchingFlowLogs.Count) { $matchingFlowLogs.Count } else { 'none' }))
if ($matchingFlowLogs.Count -eq 0) {
    Write-Warning 'No matching Network Watcher VNet flow log is configured. Configure one through client IaC before reproducing; past traffic cannot be recovered.'
}

if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    if (Test-Path -LiteralPath $OutputPath) {
        throw "OutputPath already exists; refusing to overwrite $OutputPath."
    }
    $parent = Split-Path -Parent $OutputPath
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $OutputPath -Encoding utf8NoBOM
    Write-Host ("Report             : {0}" -f $OutputPath)
}

if (
    -not $report.AgentSubnet.HasRequiredDelegation -or
    -not $report.AgentSubnet.IsRfc1918 -or
    -not $report.AgentSubnet.SizeSupported -or
    -not $report.FoundryAndVnetSameRegion -or
    ($cidrFindings | Where-Object { $_.ReservedOverlaps.Count })
) {
    exit 2
}