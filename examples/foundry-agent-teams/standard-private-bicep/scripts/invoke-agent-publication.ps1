#requires -Version 7.1

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Configure', 'Publish')]
    [string]$Operation,

    [Parameter(Mandatory)]
    [string]$ProjectEndpoint,

    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9-]{0,63}$')]
    [string]$AgentName,

    [Parameter(Mandatory)]
    [string]$ModelDeploymentName,

    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{1,41}$')]
    [string]$BotName,

    [Parameter(Mandatory)]
    [string]$AgentDisplayName,

    [string]$BotServiceArmId = '',

    [ValidateSet('Shared', 'Tenant')]
    [string]$PublishScope = 'Shared',

    [ValidatePattern('^[1-9][0-9]*\.[0-9]+\.[0-9]+$')]
    [string]$AppVersion = '1.0.0',

    [string]$DeveloperName = '',

    [string]$DeveloperWebsiteUrl = '',

    [string]$PrivacyUrl = '',

    [string]$TermsOfUseUrl = '',

    [string]$ShortDescription = 'A private Microsoft Foundry agent available in Teams and Microsoft 365.',

    [string]$FullDescription = 'A private Microsoft Foundry Prompt Agent published through a governed client deployment.',

    [string]$AgentDefinitionPath = (Join-Path $PSScriptRoot '..\resources\agent.json'),

    [string]$PublishDefinitionPath = (Join-Path $PSScriptRoot '..\resources\publish.json'),

    [string]$HandoffPath = (Join-Path (Get-Location) 'agent-handoff.parameters.json'),

    [ValidateRange(1, 300)]
    [int]$TimeoutSeconds = 60,

    [switch]$Execute
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$azureCliLibrary = Join-Path (Join-Path $PSScriptRoot 'lib') 'azure-cli.ps1'
. $azureCliLibrary

function Read-JsonDefinition {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Definition file not found: $Path"
    }

    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
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

    $request = @{
        Method = $Method
        Uri = $Uri
        Headers = @{
            Authorization = "Bearer $AccessToken"
            'Foundry-Features' = 'AgentEndpoints=V1Preview'
        }
        TimeoutSec = $TimeoutSeconds
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
        $detail = $_.ErrorDetails.Message
        if ([string]::IsNullOrWhiteSpace($detail)) {
            $detail = $_.Exception.Message
        }
        throw "$Method $Uri failed.`n$detail"
    }
}

function Get-AgentPrincipalId {
    param(
        [Parameter(Mandatory)]
        [object]$Agent
    )

    $identityProperty = $Agent.PSObject.Properties['instance_identity']
    $identity = if ($null -ne $identityProperty) { $identityProperty.Value } else { $null }
    $versionsProperty = $Agent.PSObject.Properties['versions']
    if ($null -eq $identity -and $null -ne $versionsProperty) {
        $identity = $versionsProperty.Value.latest.instance_identity
    }

    $principalId = [string]$identity.principal_id
    if ($principalId -notmatch '^[0-9a-fA-F-]{36}$') {
        throw 'The agent response did not contain a valid instance_identity.principal_id.'
    }

    return $principalId
}

function Enable-AgentPublicationProtocol {
    param(
        [Parameter(Mandatory)]
        [string]$AgentUri,

        [Parameter(Mandatory)]
        [string]$AccessToken,

        [Parameter(Mandatory)]
        [ValidateSet('BotServiceRbac', 'BotServiceTenant')]
        [string]$AuthorizationType
    )

    $body = @{
        agent_endpoint = @{
            protocol_configuration = @{
                activity = @{}
                responses = @{}
            }
            authorization_schemes = @(
                @{ type = 'Entra' }
                @{ type = $AuthorizationType }
            )
        }
    }

    $patched = Invoke-FoundryRequest -Method PATCH -Uri $AgentUri -AccessToken $AccessToken -Body $body -ContentType 'application/merge-patch+json'
    $protocols = @($patched.agent_endpoint.protocols)
    $authorization = @($patched.agent_endpoint.authorization_schemes | ForEach-Object { $_.type })
    if ('activity' -notin $protocols -or 'responses' -notin $protocols -or $AuthorizationType -notin $authorization) {
        throw "The agent update did not return the required activity, responses, and $AuthorizationType configuration."
    }
}

$ProjectEndpoint = $ProjectEndpoint.TrimEnd('/')
$projectUri = [uri]$ProjectEndpoint
if ($projectUri.Scheme -ne 'https' -or -not $projectUri.DnsSafeHost.EndsWith('.services.ai.azure.com', [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'ProjectEndpoint must use HTTPS on a *.services.ai.azure.com host.'
}
if ($projectUri.AbsolutePath -notmatch '^/api/projects/[^/]+$') {
    throw 'ProjectEndpoint must end with /api/projects/<project-name>.'
}

$account = Invoke-BoundedAzJson -Description 'Reading the delegated Azure CLI identity' -TimeoutSeconds $TimeoutSeconds -Arguments @(
    'account', 'show', '--query', '{name:name,id:id,tenantId:tenantId,user:user}', '-o', 'json'
)
if ([string]$account.user.type -ne 'user') {
    throw 'This proof path requires a delegated user from az login; service-principal and managed-identity sessions are rejected.'
}

$encodedAgentName = [uri]::EscapeDataString($AgentName)
$agentUri = "$ProjectEndpoint/agents/$encodedAgentName`?api-version=v1"
$activityEndpoint = "$ProjectEndpoint/agents/$encodedAgentName/endpoint/protocols/activityProtocol?api-version=2025-05-15-preview"
$authorizationType = if ($PublishScope -eq 'Tenant') { 'BotServiceTenant' } else { 'BotServiceRbac' }
$mode = if ($Execute) { 'EXECUTE' } else { 'PREVIEW (read-only)' }

Write-Host "Operation    : $Operation"
Write-Host "Mode         : $mode"
Write-Host "Subscription : $($account.name) ($($account.id))"
Write-Host "Tenant       : $($account.tenantId)"
Write-Host "Signed in as : $($account.user.name)"
Write-Host "Project      : $ProjectEndpoint"
Write-Host "Agent        : $AgentName"

if ($Operation -eq 'Configure') {
    $agentBody = Read-JsonDefinition -Path $AgentDefinitionPath
    $agentBody['name'] = $AgentName
    $agentBody['definition']['model'] = $ModelDeploymentName

    if (-not $Execute) {
        Write-Host 'Would create a new Prompt Agent version, enable activity and BotServiceRbac, and emit a non-secret Bicep handoff file.'
        Write-Host ($agentBody | ConvertTo-Json -Depth 20)
        return
    }

    $token = Invoke-BoundedAzText -Description 'Acquiring the delegated Foundry token' -TimeoutSeconds $TimeoutSeconds -Arguments @(
        'account', 'get-access-token', '--resource', 'https://ai.azure.com', '--query', 'accessToken', '-o', 'tsv'
    )
    if ([string]::IsNullOrWhiteSpace($token)) {
        throw 'Unable to acquire a delegated token for https://ai.azure.com.'
    }

    $created = Invoke-FoundryRequest -Method POST -Uri "$ProjectEndpoint/agents?api-version=v1" -AccessToken $token -Body $agentBody
    $agent = Invoke-FoundryRequest -Method GET -Uri $agentUri -AccessToken $token
    $principalId = Get-AgentPrincipalId -Agent $agent
    Enable-AgentPublicationProtocol -AgentUri $agentUri -AccessToken $token -AuthorizationType $authorizationType

    $handoff = [ordered]@{
        '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
        contentVersion = '1.0.0.0'
        parameters = [ordered]@{
            agentName = @{ value = $AgentName }
            agentPrincipalId = @{ value = $principalId }
            botName = @{ value = $BotName }
            botDisplayName = @{ value = $AgentDisplayName }
        }
    }
    [System.IO.File]::WriteAllText($HandoffPath, ($handoff | ConvertTo-Json -Depth 10), [System.Text.UTF8Encoding]::new($false))

    Write-Host "Agent version: $($created.version)"
    Write-Host "Principal ID : $principalId"
    Write-Host "Handoff      : $HandoffPath"
    $token = $null
    return
}

if ([string]::IsNullOrWhiteSpace($BotServiceArmId)) {
    throw 'BotServiceArmId is required for Publish.'
}
foreach ($requiredValue in @($DeveloperName, $DeveloperWebsiteUrl, $PrivacyUrl, $TermsOfUseUrl)) {
    if ([string]::IsNullOrWhiteSpace($requiredValue)) {
        throw 'DeveloperName and all three HTTPS metadata URLs are required for Publish.'
    }
}
foreach ($url in @($DeveloperWebsiteUrl, $PrivacyUrl, $TermsOfUseUrl)) {
    if (-not $url.StartsWith('https://', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Publication metadata URL must use HTTPS: $url"
    }
}

$publishBody = Read-JsonDefinition -Path $PublishDefinitionPath
$publishBody['agentDisplayName'] = $AgentDisplayName
$publishBody['botServiceArmId'] = $BotServiceArmId
$publishBody['publishScope'] = $PublishScope
$publishBody['appVersion'] = $AppVersion
$publishBody['shortDescription'] = $ShortDescription
$publishBody['fullDescription'] = $FullDescription
$publishBody['developerName'] = $DeveloperName
$publishBody['developerWebsiteUrl'] = $DeveloperWebsiteUrl
$publishBody['privacyUrl'] = $PrivacyUrl
$publishBody['termsOfUseUrl'] = $TermsOfUseUrl

if (-not $Execute) {
    Write-Host 'Would validate the Bicep-owned Bot Service, enable the publication protocol, and publish this payload:'
    Write-Host ($publishBody | ConvertTo-Json -Depth 20)
    return
}

$token = Invoke-BoundedAzText -Description 'Acquiring the delegated Foundry token' -TimeoutSeconds $TimeoutSeconds -Arguments @(
    'account', 'get-access-token', '--resource', 'https://ai.azure.com', '--query', 'accessToken', '-o', 'tsv'
)
if ([string]::IsNullOrWhiteSpace($token)) {
    throw 'Unable to acquire a delegated token for https://ai.azure.com.'
}

$agent = Invoke-FoundryRequest -Method GET -Uri $agentUri -AccessToken $token
$principalId = Get-AgentPrincipalId -Agent $agent
$bot = Invoke-BoundedAzJson -Description 'Reading the Bicep-owned Bot Service' -TimeoutSeconds $TimeoutSeconds -Arguments @(
    'resource', 'show', '--ids', $BotServiceArmId, '--api-version', '2022-09-15', '-o', 'json'
)
if ([string]$bot.properties.msaAppId -ne $principalId) {
    throw "Bot Service msaAppId $($bot.properties.msaAppId) does not match agent principal ID $principalId."
}
if ([string]$bot.properties.endpoint -ne $activityEndpoint) {
    throw 'Bot Service endpoint does not match the agent activity protocol endpoint.'
}
if ([string]$bot.properties.publicNetworkAccess -ne 'Disabled') {
    throw 'Bot Service publicNetworkAccess must remain Disabled.'
}
if ([string]$bot.properties.msaAppTenantId -ne [string]$account.tenantId) {
    throw "Bot Service tenant $($bot.properties.msaAppTenantId) does not match delegated publisher tenant $($account.tenantId)."
}

$null = Invoke-BoundedAzJson -Description 'Reading the Bicep-owned Microsoft Teams channel' -TimeoutSeconds $TimeoutSeconds -Arguments @(
    'resource', 'show', '--ids', "$BotServiceArmId/channels/MsTeamsChannel", '--api-version', '2021-03-01', '-o', 'json'
)

Enable-AgentPublicationProtocol -AgentUri $agentUri -AccessToken $token -AuthorizationType $authorizationType
$published = Invoke-FoundryRequest -Method POST -Uri "$ProjectEndpoint/agents/$encodedAgentName/microsoft365/publish?api-version=v1" -AccessToken $token -Body $publishBody
if ([string]::IsNullOrWhiteSpace([string]$published.titleId)) {
    throw 'Publication returned without a titleId.'
}

Write-Host 'Publication succeeded.'
Write-Host "Title ID     : $($published.titleId)"
Write-Host "Teams App ID : $($published.teamsAppId)"
Write-Host 'Required acceptance: find the agent in Teams and verify a real reply.'
$token = $null