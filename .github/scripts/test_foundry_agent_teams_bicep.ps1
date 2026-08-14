#requires -Version 7.1

$ErrorActionPreference = 'Stop'
$collectorPath = Join-Path $PSScriptRoot '../../examples/foundry-agent-teams/standard-private-bicep/scripts/collect-network-diagnostics.ps1'
$collectorPath = (Resolve-Path $collectorPath).Path
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    $collectorPath,
    [ref]$tokens,
    [ref]$errors
)
if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_.Message }
    exit 1
}

$functionNames = @(
    'ConvertTo-IPv4Number',
    'Get-CidrRange',
    'Test-CidrOverlap',
    'Test-Rfc1918Cidr'
)
$definitions = $ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -in $functionNames
}, $true)
if ($definitions.Count -ne $functionNames.Count) {
    throw 'The collector CIDR functions could not be loaded for testing.'
}
$definitions | ForEach-Object { Invoke-Expression $_.Extent.Text }

if (-not (Test-Rfc1918Cidr -Cidr '10.153.78.0/23')) {
    throw 'A valid RFC1918 delegated subnet was rejected.'
}
if (Test-CidrOverlap -Left '10.153.78.0/23' -Right '100.64.0.0/11') {
    throw 'An RFC1918 delegated subnet falsely overlapped the reserved CGNAT range.'
}
if (-not (Test-CidrOverlap -Left '100.64.1.0/24' -Right '100.64.0.0/11')) {
    throw 'A reserved CGNAT overlap was missed.'
}
if (Test-Rfc1918Cidr -Cidr '100.64.1.0/24') {
    throw 'CGNAT was falsely classified as RFC1918.'
}
if (-not (Test-CidrOverlap -Left '172.30.20.0/24' -Right '172.30.0.0/16')) {
    throw 'A Microsoft-reserved VNet overlap was missed.'
}

Write-Host 'Foundry Bicep CIDR diagnostic behavior passed'