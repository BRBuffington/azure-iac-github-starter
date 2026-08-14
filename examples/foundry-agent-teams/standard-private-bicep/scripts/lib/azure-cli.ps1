Set-StrictMode -Version Latest

function Invoke-BoundedExternalCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string[]]$Arguments,

        [Parameter(Mandatory)]
        [string]$Description,

        [Parameter(Mandatory)]
        [ValidateRange(1, 300)]
        [int]$TimeoutSeconds
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true

    $isCommandScript = $IsWindows -and [System.IO.Path]::GetExtension($FilePath) -in @('.cmd', '.bat')
    if ($isCommandScript) {
        $pwsh = Get-Command pwsh -ErrorAction Stop
        $payloadJson = [ordered]@{
            FilePath = $FilePath
            Arguments = $Arguments
        } | ConvertTo-Json -Compress
        $payload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payloadJson))
        $startInfo.FileName = $pwsh.Source
        $startInfo.Environment['BOUNDED_COMMAND_PAYLOAD'] = $payload
        $startInfo.ArgumentList.Add('-NoLogo')
        $startInfo.ArgumentList.Add('-NoProfile')
        $startInfo.ArgumentList.Add('-NonInteractive')
        $startInfo.ArgumentList.Add('-Command')
        $startInfo.ArgumentList.Add('$json = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($env:BOUNDED_COMMAND_PAYLOAD)); $invocation = $json | ConvertFrom-Json; & $invocation.FilePath @($invocation.Arguments); exit $LASTEXITCODE')
    }
    else {
        $startInfo.FileName = $FilePath
        foreach ($argument in $Arguments) {
            $startInfo.ArgumentList.Add($argument)
        }
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            throw "$Description did not start."
        }

        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $process.Kill($true)
            $process.WaitForExit()
            throw "$Description timed out after $TimeoutSeconds seconds."
        }

        $process.WaitForExit()
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) {
            $detail = @($stderr.Trim(), $stdout.Trim()) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            throw "$Description failed with exit code $($process.ExitCode).`n$($detail -join "`n")"
        }

        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            StandardOutput = $stdout
            StandardError = $stderr
        }
    }
    finally {
        $process.Dispose()
    }
}

function Invoke-BoundedAzText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,

        [Parameter(Mandatory)]
        [string]$Description,

        [Parameter(Mandatory)]
        [ValidateRange(1, 300)]
        [int]$TimeoutSeconds
    )

    $az = Get-Command az -ErrorAction SilentlyContinue
    if ($null -eq $az) {
        throw 'Azure CLI is required.'
    }

    $result = Invoke-BoundedExternalCommand -FilePath $az.Source -Arguments $Arguments -Description $Description -TimeoutSeconds $TimeoutSeconds
    return $result.StandardOutput.Trim()
}

function Invoke-BoundedAzJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,

        [Parameter(Mandatory)]
        [string]$Description,

        [Parameter(Mandatory)]
        [ValidateRange(1, 300)]
        [int]$TimeoutSeconds
    )

    $text = Invoke-BoundedAzText -Arguments $Arguments -Description $Description -TimeoutSeconds $TimeoutSeconds
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }

    return $text | ConvertFrom-Json
}