Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Get-RequiredEnvironmentValue {
    param([Parameter(Mandatory)][string] $Name)

    $value = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Required environment variable '$Name' is not set."
    }

    return $value.Trim()
}

function Get-ObjectPropertyValue {
    param(
        [AllowNull()][object] $InputObject,
        [Parameter(Mandatory)][string] $Name
    )

    if ($null -eq $InputObject) {
        return $null
    }

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Invoke-GitHubApi {
    param(
        [Parameter(Mandatory)][ValidateSet("GET", "POST", "PATCH", "DELETE")][string] $Method,
        [Parameter(Mandatory)][string] $Path,
        [AllowNull()][object] $Body,
        [bool] $AllowNotFound = $false
    )

    $token = if (-not [string]::IsNullOrWhiteSpace($env:GH_TOKEN)) {
        $env:GH_TOKEN
    }
    elseif (-not [string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) {
        $env:GITHUB_TOKEN
    }
    else {
        throw "GH_TOKEN or GITHUB_TOKEN must be set."
    }

    $request = @{
        Headers = @{
            Accept                 = "application/vnd.github+json"
            Authorization          = "Bearer $token"
            "X-GitHub-Api-Version" = "2026-03-10"
            "User-Agent"           = "azure-iac-github-starter-apn"
        }
        Method     = $Method
        TimeoutSec = 30
        Uri        = "https://api.github.com$Path"
    }

    if ($null -ne $Body) {
        $request.Body = $Body | ConvertTo-Json -Depth 10 -Compress
        $request.ContentType = "application/json"
    }

    try {
        return Invoke-RestMethod @request
    }
    catch {
        $statusCode = if ($null -ne $_.Exception.Response) {
            [int]$_.Exception.Response.StatusCode
        }
        else {
            0
        }

        if ($AllowNotFound -and $statusCode -eq 404) {
            return $null
        }

        throw
    }
}

function Get-NetworkConfigurations {
    param(
        [Parameter(Mandatory)][scriptblock] $ApiInvoker,
        [Parameter(Mandatory)][string] $OrganizationPath
    )

    $configurations = @()
    $page = 1

    do {
        $path = "/orgs/$OrganizationPath/settings/network-configurations?per_page=100&page=$page"
        $response = & $ApiInvoker "GET" $path $null $false
        $pageItems = @(Get-ObjectPropertyValue -InputObject $response -Name "network_configurations")
        $configurations += $pageItems
        $page++
    } while ($pageItems.Count -eq 100)

    return $configurations
}

function Invoke-ApnMain {
    param([scriptblock] $ApiInvoker)

    $mode = Get-RequiredEnvironmentValue -Name "APN_MODE"
    if ($mode -notin @("Ensure", "Remove")) {
        throw "APN_MODE must be Ensure or Remove."
    }

    $organization = Get-RequiredEnvironmentValue -Name "APN_ORGANIZATION"
    $runnerGroupId = Get-RequiredEnvironmentValue -Name "APN_RUNNER_GROUP_ID"
    $configurationName = Get-RequiredEnvironmentValue -Name "APN_NETWORK_CONFIGURATION_NAME"
    $networkSettingsId = Get-RequiredEnvironmentValue -Name "APN_NETWORK_SETTINGS_ID"

    if ($organization -notmatch "^[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?$") {
        throw "APN_ORGANIZATION is not a valid GitHub organization login."
    }
    if ($runnerGroupId -notmatch "^[0-9]+$") {
        throw "APN_RUNNER_GROUP_ID must contain only digits."
    }
    if ($configurationName.Length -gt 100 -or $configurationName -notmatch "^[A-Za-z0-9._-]+$") {
        throw "APN_NETWORK_CONFIGURATION_NAME must be 1-100 letters, numbers, periods, underscores, or hyphens."
    }

    if ($null -eq $ApiInvoker) {
        $ApiInvoker = {
            param($Method, $Path, $Body, $AllowNotFound)
            Invoke-GitHubApi -Method $Method -Path $Path -Body $Body -AllowNotFound $AllowNotFound
        }
    }

    $organizationPath = [Uri]::EscapeDataString($organization)
    $configurations = @(Get-NetworkConfigurations -ApiInvoker $ApiInvoker -OrganizationPath $organizationPath)
    $matchingConfigurations = @($configurations | Where-Object {
        (Get-ObjectPropertyValue -InputObject $_ -Name "name") -ceq $configurationName
    })

    if ($matchingConfigurations.Count -gt 1) {
        throw "More than one network configuration is named '$configurationName'."
    }

    $configuration = if ($matchingConfigurations.Count -eq 1) { $matchingConfigurations[0] } else { $null }
    $runnerGroupPath = "/orgs/$organizationPath/actions/runner-groups/$runnerGroupId"

    if ($mode -eq "Ensure") {
        $configurationBody = @{
            name                 = $configurationName
            compute_service      = "actions"
            network_settings_ids = @($networkSettingsId)
        }

        if ($null -eq $configuration) {
            $configuration = & $ApiInvoker "POST" "/orgs/$organizationPath/settings/network-configurations" $configurationBody $false
        }
        else {
            $settingsIds = @(Get-ObjectPropertyValue -InputObject $configuration -Name "network_settings_ids")
            $computeService = Get-ObjectPropertyValue -InputObject $configuration -Name "compute_service"
            $matchesDesiredState = $computeService -eq "actions" -and
                $settingsIds.Count -eq 1 -and $settingsIds[0] -eq $networkSettingsId

            if (-not $matchesDesiredState) {
                $configurationIdPath = [Uri]::EscapeDataString([string]$configuration.id)
                $configuration = & $ApiInvoker "PATCH" "/orgs/$organizationPath/settings/network-configurations/$configurationIdPath" $configurationBody $false
            }
        }

        $runnerGroup = & $ApiInvoker "GET" $runnerGroupPath $null $false
        $runnerGroupNetworkConfigurationId = Get-ObjectPropertyValue -InputObject $runnerGroup -Name "network_configuration_id"
        $configurationId = Get-ObjectPropertyValue -InputObject $configuration -Name "id"
        if ($runnerGroupNetworkConfigurationId -ne $configurationId) {
            $runnerGroupBody = @{
                name                     = Get-ObjectPropertyValue -InputObject $runnerGroup -Name "name"
                network_configuration_id = $configurationId
            }
            $null = & $ApiInvoker "PATCH" $runnerGroupPath $runnerGroupBody $false
        }

        Write-Output "Ensured network configuration '$configurationName' on runner group $runnerGroupId."
        return
    }

    if ($null -eq $configuration) {
        Write-Output "Network configuration '$configurationName' is already absent."
        return
    }
    if ((Get-ObjectPropertyValue -InputObject $configuration -Name "compute_service") -ne "actions") {
        throw "Refusing to remove '$configurationName' because its compute service is not actions."
    }
    $configurationSettingsIds = @(Get-ObjectPropertyValue -InputObject $configuration -Name "network_settings_ids")
    if ($configurationSettingsIds.Count -ne 1 -or $configurationSettingsIds[0] -ne $networkSettingsId) {
        throw "Refusing to remove '$configurationName' because it no longer references this state's NetworkSettings ID."
    }

    $runnerGroup = & $ApiInvoker "GET" $runnerGroupPath $null $true
    $configurationId = Get-ObjectPropertyValue -InputObject $configuration -Name "id"
    $runnerGroupNetworkConfigurationId = Get-ObjectPropertyValue -InputObject $runnerGroup -Name "network_configuration_id"
    if ($null -ne $runnerGroup -and $runnerGroupNetworkConfigurationId -eq $configurationId) {
        $runnerGroupBody = @{
            name                     = Get-ObjectPropertyValue -InputObject $runnerGroup -Name "name"
            network_configuration_id = $null
        }
        $null = & $ApiInvoker "PATCH" $runnerGroupPath $runnerGroupBody $false
    }

    $configurationIdPath = [Uri]::EscapeDataString([string]$configurationId)
    $null = & $ApiInvoker "DELETE" "/orgs/$organizationPath/settings/network-configurations/$configurationIdPath" $null $false
    Write-Output "Removed network configuration '$configurationName'."
}

if ($env:APN_IMPORT_ONLY -ne "true") {
    Invoke-ApnMain
}
