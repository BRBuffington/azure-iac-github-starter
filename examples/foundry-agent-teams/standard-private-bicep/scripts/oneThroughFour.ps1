#requires -Version 7.1

<#
.SYNOPSIS
Walks through publishing a Microsoft Foundry agent to Microsoft 365 and Teams.

.DESCRIPTION
Implements Steps 1 through 4 of the REST API publication flow:

1. Read the agent identity and current tenant.
2. Verify the Bicep-deployed Azure Bot resource and Microsoft Teams channel.
3. Enable the activity protocol and BotServiceRbac authorization.
4. Publish the agent to Microsoft 365 with Shared scope.

The script is read-only unless -Execute is supplied. Access tokens are never
printed or written to a transcript. Run this from a machine that can resolve
and reach the Foundry project endpoint, including its private endpoint when
public network access is disabled.

.EXAMPLE
.\scripts\oneThroughFour.ps1 `
  -ProjectEndpoint 'https://contoso-foundry.services.ai.azure.com/api/projects/my-project' `
  -AgentName 'my-agent' `
  -BotName 'my-agent-bot' `
  -BotResourceGroup 'rg-foundry' `
  -DeveloperName 'Contoso' `
  -DeveloperWebsiteUrl 'https://www.contoso.com' `
  -PrivacyUrl 'https://www.contoso.com/privacy' `
  -TermsOfUseUrl 'https://www.contoso.com/terms'

Runs preflight checks and shows the planned writes without changing Azure.

.EXAMPLE
.\scripts\oneThroughFour.ps1 `
  -ProjectEndpoint 'https://contoso-foundry.services.ai.azure.com/api/projects/my-project' `
  -AgentName 'my-agent' `
  -BotName 'my-agent-bot' `
  -BotResourceGroup 'rg-foundry' `
  -DeveloperName 'Contoso' `
  -DeveloperWebsiteUrl 'https://www.contoso.com' `
  -PrivacyUrl 'https://www.contoso.com/privacy' `
  -TermsOfUseUrl 'https://www.contoso.com/terms' `
  -Execute

Executes the data-plane writes in Steps 3 and 4 after Step 2 has been deployed
with bot-service.bicep. Review preview output before adding -Execute.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^https://.+/api/projects/[^/]+/?$')]
    [string]$ProjectEndpoint,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$AgentName,

    [Parameter(Mandatory)]
    [ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9_.-]{1,63}$')]
    [string]$BotName,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$BotResourceGroup,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$DeveloperName,

    [Parameter(Mandatory)]
    [ValidatePattern('^https://')]
    [string]$DeveloperWebsiteUrl,

    [Parameter(Mandatory)]
    [ValidatePattern('^https://')]
    [string]$PrivacyUrl,

    [Parameter(Mandatory)]
    [ValidatePattern('^https://')]
    [string]$TermsOfUseUrl,

    [ValidateNotNullOrEmpty()]
    [string]$AgentDisplayName,

    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$AppVersion = '1.0.0',

    [ValidateLength(1, 80)]
    [string]$ShortDescription = 'Microsoft Foundry agent',

    [ValidateLength(1, 4000)]
    [string]$FullDescription = 'A Microsoft Foundry agent published to Microsoft 365.',

    [switch]$Execute
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step {
    param(
        [Parameter(Mandatory)]
        [int]$Number,

        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [string]$Mode
    )

    Write-Host ''
    Write-Host ('#' * 78)
    Write-Host ("# STEP {0} - {1}" -f $Number, $Title)
    Write-Host ("# Mode: {0}" -f $Mode)
    Write-Host ('#' * 78)
}

function Invoke-AzJson {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,

        [Parameter(Mandatory)]
        [string]$Description
    )

    $output = & az @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "$Description failed.`n$($output | Out-String)"
    }

    $text = ($output | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }

    return $text | ConvertFrom-Json -AsHashtable
}

function Invoke-FoundryRequest {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('GET', 'PATCH', 'POST')]
        [string]$Method,

        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter(Mandatory)]
        [string]$AccessToken,

        [hashtable]$Body,

        [string]$ContentType = 'application/json'
    )

    $headers = @{
        Authorization = "Bearer $AccessToken"
        'Foundry-Features' = 'AgentEndpoints=V1Preview'
    }

    $request = @{
        Method = $Method
        Uri = $Uri
        Headers = $headers
        ErrorAction = 'Stop'
    }

    if ($null -ne $Body) {
        $request.ContentType = $ContentType
        $request.Body = $Body | ConvertTo-Json -Depth 20 -Compress
    }

    try {
        return Invoke-RestMethod @request
    }
    catch {
        $details = $_.ErrorDetails.Message
        if ([string]::IsNullOrWhiteSpace($details)) {
            $details = $_.Exception.Message
        }

        throw "$Method $Uri failed.`n$details"
    }
}

function Test-PrivateIpAddress {
    param(
        [Parameter(Mandatory)]
        [System.Net.IPAddress]$Address
    )

    if ($Address.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
        return $false
    }

    $bytes = $Address.GetAddressBytes()
    return (
        $bytes[0] -eq 10 -or
        ($bytes[0] -eq 172 -and $bytes[1] -ge 16 -and $bytes[1] -le 31) -or
        ($bytes[0] -eq 192 -and $bytes[1] -eq 168)
    )
}

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI was not found. Install Azure CLI and open a new PowerShell session.'
}

$ProjectEndpoint = $ProjectEndpoint.TrimEnd('/')
if ([string]::IsNullOrWhiteSpace($AgentDisplayName)) {
    $AgentDisplayName = $AgentName
}

$account = Invoke-AzJson -Description 'Reading the Azure CLI account' -Arguments @(
    'account', 'show', '--query', '{name:name,id:id,tenantId:tenantId,user:user.name}', '-o', 'json'
)
$subscriptionId = [string]$account.id
$tenantId = [string]$account.tenantId
$foundryHost = ([uri]$ProjectEndpoint).DnsSafeHost
$encodedAgentName = [uri]::EscapeDataString($AgentName)
$agentUri = "$ProjectEndpoint/agents/$encodedAgentName`?api-version=v1"
$activityEndpoint = "$ProjectEndpoint/agents/$encodedAgentName/endpoint/protocols/activityProtocol?api-version=2025-05-15-preview"
$botArmId = "/subscriptions/$subscriptionId/resourceGroups/$BotResourceGroup/providers/Microsoft.BotService/botServices/$BotName"
$teamsChannelUri = "https://management.azure.com$botArmId/channels/MsTeamsChannel?api-version=2021-03-01"

Write-Host 'Foundry to Microsoft 365: Steps 1-4'
Write-Host ("Mode         : {0}" -f $(if ($Execute) { 'EXECUTE' } else { 'PREVIEW (read-only)' }))
Write-Host ("Subscription : {0} ({1})" -f $account.name, $subscriptionId)
Write-Host ("Tenant       : {0}" -f $tenantId)
Write-Host ("Signed in as : {0}" -f $account.user)
Write-Host ("Project      : {0}" -f $ProjectEndpoint)
Write-Host ("Agent        : {0}" -f $AgentName)
Write-Host ("Bot / RG     : {0} / {1}" -f $BotName, $BotResourceGroup)

Write-Host ''
Write-Host "Resolving $foundryHost ..."
$resolvedAddresses = [System.Net.Dns]::GetHostAddresses($foundryHost)
$ipv4Addresses = @($resolvedAddresses | Where-Object AddressFamily -EQ InterNetwork)
if ($ipv4Addresses.Count -eq 0) {
    Write-Warning 'The Foundry hostname did not return an IPv4 address.'
}
else {
    foreach ($address in $ipv4Addresses) {
        $classification = if (Test-PrivateIpAddress -Address $address) { 'private' } else { 'not RFC1918 private' }
        Write-Host ("DNS          : {0} ({1})" -f $address.IPAddressToString, $classification)
    }

    if (-not ($ipv4Addresses | Where-Object { Test-PrivateIpAddress -Address $_ })) {
        Write-Warning 'Foundry did not resolve to an RFC1918 address. A network-secured project will reject the next request; run this script from its VNet or connected network.'
    }
}

$providerState = & az provider show --namespace Microsoft.BotService --query registrationState -o tsv 2>$null
if ($LASTEXITCODE -ne 0 -or $providerState.Trim() -ne 'Registered') {
    throw "Microsoft.BotService is not registered in subscription $subscriptionId. Register it before continuing."
}

$foundryToken = & az account get-access-token --resource 'https://ai.azure.com' --query accessToken -o tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($foundryToken)) {
    throw 'Unable to acquire a Foundry token for https://ai.azure.com.'
}
$foundryToken = $foundryToken.Trim()

Write-Step -Number 1 -Title 'Get the agent identity and tenant ID' -Mode 'READ-ONLY'
$agent = Invoke-FoundryRequest -Method GET -Uri $agentUri -AccessToken $foundryToken
$agentIdentity = $agent.instance_identity
if ($null -eq $agentIdentity) {
    $agentIdentity = $agent.versions.latest.instance_identity
}

$agentPrincipalId = [string]$agentIdentity.principal_id
$agentClientId = [string]$agentIdentity.client_id
if ([string]::IsNullOrWhiteSpace($agentPrincipalId) -or [string]::IsNullOrWhiteSpace($agentClientId)) {
    throw 'The agent response did not contain instance_identity principal_id and client_id.'
}

Write-Host ("Agent ID     : {0}" -f $agent.id)
Write-Host ("Principal ID : {0}" -f $agentPrincipalId)
Write-Host ("Client ID    : {0}" -f $agentClientId)
Write-Host ("Tenant ID    : {0}" -f $tenantId)
Write-Host ("Protocols    : {0}" -f (($agent.agent_endpoint.protocols | ForEach-Object { [string]$_ }) -join ', '))
Write-Host ("Authorization: {0}" -f (($agent.agent_endpoint.authorization_schemes | ForEach-Object { [string]$_.type }) -join ', '))

Write-Step -Number 2 -Title 'Verify Bicep-owned Azure Bot Service and Teams channel' -Mode 'READ-ONLY'
$resourceGroupExists = $false
& az group show --name $BotResourceGroup --subscription $subscriptionId --only-show-errors -o none 2>$null
if ($LASTEXITCODE -eq 0) {
    $resourceGroupExists = $true
}

if (-not $resourceGroupExists) {
    throw "Resource group $BotResourceGroup does not exist. Deploy bot-service.bicep before running Steps 3 and 4."
}
Write-Host ("Resource group {0} exists." -f $BotResourceGroup)

$existingBotOutput = & az bot show --name $BotName --resource-group $BotResourceGroup --subscription $subscriptionId -o json 2>$null
if ($LASTEXITCODE -ne 0) {
    throw "Bot Service $BotName does not exist in $BotResourceGroup. Deploy bot-service.bicep with the Step 1 values first."
}
$existingBot = ($existingBotOutput | Out-String) | ConvertFrom-Json -AsHashtable

if ([string]$existingBot.properties.msaAppId -ne $agentPrincipalId) {
    throw "Bot Service $BotName uses msaAppId $($existingBot.properties.msaAppId), not agent principal ID $agentPrincipalId."
}
if ([string]$existingBot.properties.msaAppTenantId -ne $tenantId) {
    throw "Bot Service $BotName belongs to tenant $($existingBot.properties.msaAppTenantId), not signed-in tenant $tenantId."
}
if ([string]$existingBot.properties.endpoint -ne $activityEndpoint) {
    throw "Bot Service $BotName endpoint does not match the agent activity endpoint."
}
if ([string]$existingBot.properties.publicNetworkAccess -ne 'Disabled') {
    throw "Bot Service $BotName publicNetworkAccess must be Disabled."
}

$channel = Invoke-AzJson -Description 'Reading the Bicep-owned Microsoft Teams channel' -Arguments @(
    'rest', '--method', 'get', '--url', $teamsChannelUri, '-o', 'json'
)
Write-Host ("Bot state    : {0}" -f $existingBot.properties.provisioningState)
Write-Host ("Bot endpoint : {0}" -f $existingBot.properties.endpoint)
Write-Host ("Bot PNA      : {0}" -f $existingBot.properties.publicNetworkAccess)
Write-Host ("Teams state  : {0}" -f $channel.properties.provisioningState)

Write-Step -Number 3 -Title 'Enable activity protocol and Bot Service authorization' -Mode $(if ($Execute) { 'EXECUTE' } else { 'PREVIEW' })
$agentPatch = @{
    agent_endpoint = @{
        protocol_configuration = @{
            activity = @{}
            responses = @{}
        }
        authorization_schemes = @(
            @{ type = 'Entra' }
            @{ type = 'BotServiceRbac' }
        )
    }
}

if (-not $Execute) {
    Write-Host 'Would PATCH the agent to enable activity, responses, Entra, and BotServiceRbac.'
}
else {
    $patchedAgent = Invoke-FoundryRequest -Method PATCH -Uri $agentUri -AccessToken $foundryToken -Body $agentPatch -ContentType 'application/merge-patch+json'
    $protocols = @($patchedAgent.agent_endpoint.protocols | ForEach-Object { [string]$_ })
    $authorizationSchemes = @($patchedAgent.agent_endpoint.authorization_schemes | ForEach-Object { [string]$_.type })
    if ('activity' -notin $protocols -or 'responses' -notin $protocols) {
        throw "Agent PATCH completed, but the expected protocols were not returned: $($protocols -join ', ')."
    }
    if ('BotServiceRbac' -notin $authorizationSchemes) {
        throw "Agent PATCH completed, but BotServiceRbac was not returned: $($authorizationSchemes -join ', ')."
    }

    Write-Host ("Protocols    : {0}" -f ($protocols -join ', '))
    Write-Host ("Authorization: {0}" -f ($authorizationSchemes -join ', '))
}

Write-Step -Number 4 -Title 'Publish the agent to Microsoft 365' -Mode $(if ($Execute) { 'EXECUTE' } else { 'PREVIEW' })
$publishUri = "$ProjectEndpoint/agents/$encodedAgentName/microsoft365/publish?api-version=v1"
$publishBody = @{
    agentDisplayName = $AgentDisplayName
    botServiceArmId = $botArmId
    publishScope = 'Shared'
    publishAsAutopilot = $false
    appVersion = $AppVersion
    shortDescription = $ShortDescription
    fullDescription = $FullDescription
    developerName = $DeveloperName
    developerWebsiteUrl = $DeveloperWebsiteUrl
    privacyUrl = $PrivacyUrl
    termsOfUseUrl = $TermsOfUseUrl
}

if (-not $Execute) {
    Write-Host 'Would publish the agent with the following non-secret payload:'
    Write-Host ($publishBody | ConvertTo-Json -Depth 10)
    Write-Host ''
    Write-Host 'Preview complete. Review the subscription, tenant, identity, bot, and URLs above.'
    Write-Host 'Run the same command with -Execute to perform Steps 3 and 4.'
}
else {
    $publishResult = Invoke-FoundryRequest -Method POST -Uri $publishUri -AccessToken $foundryToken -Body $publishBody
    Write-Host 'Publication succeeded.'
    Write-Host ("Title ID     : {0}" -f $publishResult.titleId)
    Write-Host ("Teams App ID : {0}" -f $publishResult.teamsAppId)
    Write-Host ''
    Write-Host 'The published agent should appear under Your agents in Microsoft 365 and Teams.'
}

$foundryToken = $null