Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$env:APN_IMPORT_ONLY = "true"
. "$PSScriptRoot/../scripts/sync-github-network.ps1"

function Assert-Equal {
    param(
        [Parameter(Mandatory)][object] $Actual,
        [Parameter(Mandatory)][object] $Expected,
        [Parameter(Mandatory)][string] $Message
    )

    if (($Actual | ConvertTo-Json -Depth 10 -Compress) -cne ($Expected | ConvertTo-Json -Depth 10 -Compress)) {
        throw "$Message. Expected '$Expected', got '$Actual'."
    }
}

function Set-TestEnvironment {
    param([Parameter(Mandatory)][ValidateSet("Ensure", "Remove")][string] $Mode)

    $env:APN_MODE = $Mode
    $env:APN_ORGANIZATION = "example-org"
    $env:APN_RUNNER_GROUP_ID = "42"
    $env:APN_NETWORK_CONFIGURATION_NAME = "ghnet-example-eus-prd"
    $env:APN_NETWORK_SETTINGS_ID = "azure-settings-123"
}

Set-TestEnvironment -Mode Ensure
$createCalls = [System.Collections.Generic.List[object]]::new()
$createApi = {
    param($Method, $Path, $Body, $AllowNotFound)
    $createCalls.Add([pscustomobject]@{ Method = $Method; Path = $Path; Body = $Body; AllowNotFound = $AllowNotFound })

    switch ("$Method $Path") {
        "GET /orgs/example-org/settings/network-configurations?per_page=100&page=1" {
            return [pscustomobject]@{ network_configurations = @() }
        }
        "POST /orgs/example-org/settings/network-configurations" {
            return [pscustomobject]@{
                id   = "network-config-123"
                name = $Body.name
            }
        }
        "GET /orgs/example-org/actions/runner-groups/42" {
            return [pscustomobject]@{ id = 42; name = "ghrg-example-eus-prd" }
        }
        "PATCH /orgs/example-org/actions/runner-groups/42" {
            return [pscustomobject]@{ id = 42; name = $Body.name; network_configuration_id = $Body.network_configuration_id }
        }
        default { throw "Unexpected mock call: $Method $Path" }
    }
}

Invoke-ApnMain -ApiInvoker $createApi
Assert-Equal -Actual $createCalls.Count -Expected 4 -Message "Create path call count"
Assert-Equal -Actual $createCalls[1].Body.compute_service -Expected "actions" -Message "Create path compute service"
Assert-Equal -Actual @($createCalls[1].Body.network_settings_ids) -Expected @("azure-settings-123") -Message "Create path settings ID"
Assert-Equal -Actual $createCalls[3].Body.name -Expected "ghrg-example-eus-prd" -Message "Runner-group PATCH required name"
Assert-Equal -Actual $createCalls[3].Body.network_configuration_id -Expected "network-config-123" -Message "Runner-group binding"

Set-TestEnvironment -Mode Ensure
$noopCalls = [System.Collections.Generic.List[object]]::new()
$noopApi = {
    param($Method, $Path, $Body, $AllowNotFound)
    $noopCalls.Add([pscustomobject]@{ Method = $Method; Path = $Path; Body = $Body; AllowNotFound = $AllowNotFound })

    if ($Path -like "*/settings/network-configurations?*") {
        return [pscustomobject]@{ network_configurations = @([pscustomobject]@{
            id                   = "network-config-123"
            name                 = "ghnet-example-eus-prd"
            compute_service      = "actions"
            network_settings_ids = @("azure-settings-123")
        }) }
    }
    if ($Path -like "*/actions/runner-groups/42") {
        return [pscustomobject]@{ id = 42; name = "ghrg-example-eus-prd"; network_configuration_id = "network-config-123" }
    }

    throw "Unexpected mock call: $Method $Path"
}

Invoke-ApnMain -ApiInvoker $noopApi
Assert-Equal -Actual $noopCalls.Count -Expected 2 -Message "No-op path call count"

foreach ($foreignConfiguration in @(
    [pscustomobject]@{
        id                   = "network-config-foreign-settings"
        name                 = "ghnet-example-eus-prd"
        compute_service      = "actions"
        network_settings_ids = @("azure-settings-foreign")
    },
    [pscustomobject]@{
        id                   = "network-config-foreign-service"
        name                 = "ghnet-example-eus-prd"
        compute_service      = "codespaces"
        network_settings_ids = @("azure-settings-123")
    }
)) {
    Set-TestEnvironment -Mode Ensure
    $driftCalls = [System.Collections.Generic.List[object]]::new()
    $driftApi = {
        param($Method, $Path, $Body, $AllowNotFound)
        $driftCalls.Add([pscustomobject]@{ Method = $Method; Path = $Path; Body = $Body; AllowNotFound = $AllowNotFound })
        return [pscustomobject]@{ network_configurations = @($foreignConfiguration) }
    }

    $driftRejected = $false
    try {
        Invoke-ApnMain -ApiInvoker $driftApi
    }
    catch {
        $driftRejected = $_.Exception.Message -like "Refusing to adopt*"
    }

    if (-not $driftRejected) {
        throw "Ensure mode must reject a same-named network configuration with ownership drift."
    }
    Assert-Equal -Actual $driftCalls.Count -Expected 1 -Message "Ownership-drift path call count"
}

Set-TestEnvironment -Mode Remove
$removeCalls = [System.Collections.Generic.List[object]]::new()
$removeApi = {
    param($Method, $Path, $Body, $AllowNotFound)
    $removeCalls.Add([pscustomobject]@{ Method = $Method; Path = $Path; Body = $Body; AllowNotFound = $AllowNotFound })

    if ($Path -like "*/settings/network-configurations?*") {
        return [pscustomobject]@{ network_configurations = @([pscustomobject]@{
            id                   = "network-config-123"
            name                 = "ghnet-example-eus-prd"
            compute_service      = "actions"
            network_settings_ids = @("azure-settings-123")
        }) }
    }
    if ($Method -eq "GET" -and $Path -like "*/actions/runner-groups/42") {
        return [pscustomobject]@{ id = 42; name = "ghrg-example-eus-prd"; network_configuration_id = "network-config-123" }
    }
    if ($Method -in @("PATCH", "DELETE")) {
        return $null
    }

    throw "Unexpected mock call: $Method $Path"
}

Invoke-ApnMain -ApiInvoker $removeApi
Assert-Equal -Actual $removeCalls.Count -Expected 4 -Message "Remove path call count"
Assert-Equal -Actual $removeCalls[2].Body.name -Expected "ghrg-example-eus-prd" -Message "Detach PATCH required name"
if ($null -ne $removeCalls[2].Body.network_configuration_id) {
    throw "Detach PATCH must set network_configuration_id to null."
}
Assert-Equal -Actual $removeCalls[3].Method -Expected "DELETE" -Message "Remove path deletes network configuration"

Write-Output "sync-github-network contract tests passed."
