$ErrorActionPreference = "Stop"
Write-Host "Update task started: install-azure-cli-tool"

Import-Module 'C:\Windows\Temp\prodicloud-session-environment.psm1' -Force -DisableNameChecking

function Refresh-SessionPath {
    Refresh-ProdicloudSessionPath | Out-Null
}

function Add-MachinePathEntry {
    param(
        [string]$Entry
    )

    if ([string]::IsNullOrWhiteSpace([string]$Entry)) {
        return
    }

    $trimmedEntry = $Entry.Trim().TrimEnd('\')
    if ([string]::IsNullOrWhiteSpace($trimmedEntry)) {
        return
    }

    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $entries = @()
    if (-not [string]::IsNullOrWhiteSpace($machinePath)) {
        $entries = @($machinePath -split ';' | ForEach-Object { [string]$_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    $exists = $false
    foreach ($existing in @($entries)) {
        if ([string]::Equals($existing.TrimEnd('\'), $trimmedEntry, [System.StringComparison]::OrdinalIgnoreCase)) {
            $exists = $true
            break
        }
    }

    if (-not $exists) {
        $entries += $trimmedEntry
        [Environment]::SetEnvironmentVariable("Path", ($entries -join ';'), "Machine")
        Write-Host ("Path entry added: {0}" -f $trimmedEntry)
    }
}

function Resolve-AzCommandPath {
    $azCmd = Get-Command az -ErrorAction SilentlyContinue
    if ($azCmd -and -not [string]::IsNullOrWhiteSpace([string]$azCmd.Source)) {
        return [string]$azCmd.Source
    }

    foreach ($candidate in @(
        "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd",
        "C:\Program Files (x86)\Microsoft SDKs\Azure\CLI2\wbin\az.cmd",
        "C:\ProgramData\chocolatey\bin\az.cmd"
    )) {
        if (Test-Path -LiteralPath $candidate) {
            return [string]$candidate
        }
    }

    return ""
}

function Ensure-AzCommandPathAvailable {
    param(
        [string]$AzCommandPath
    )

    if ([string]::IsNullOrWhiteSpace([string]$AzCommandPath)) {
        return
    }

    $resolvedDirectory = Split-Path -Path ([string]$AzCommandPath) -Parent
    if (-not [string]::IsNullOrWhiteSpace([string]$resolvedDirectory) -and (Test-Path -LiteralPath $resolvedDirectory)) {
        Add-MachinePathEntry -Entry ([string]$resolvedDirectory)
        Refresh-SessionPath
    }
}

function Resolve-WingetExe {
    $portableCandidate = 'C:\ProgramData\prodicloud\tools\winget-x64\winget.exe'
    if (Test-Path -LiteralPath $portableCandidate) {
        return [string]$portableCandidate
    }

    $cmd = Get-Command winget -ErrorAction SilentlyContinue
    if ($cmd -and -not [string]::IsNullOrWhiteSpace([string]$cmd.Source)) {
        return [string]$cmd.Source
    }

    return ''
}

function Test-ChocoAzureCliPackageListed {
    $listOutput = & $chocoExe list --local-only azure-cli --exact --limit-output
    $listExit = [int]$LASTEXITCODE
    $listText = [string]($listOutput | Out-String)
    return ($listExit -eq 0 -and -not [string]::IsNullOrWhiteSpace([string]$listText) -and $listText.ToLowerInvariant().Contains('azure-cli'))
}

$chocoExe = "$env:ProgramData\chocolatey\bin\choco.exe"
if (-not (Test-Path -LiteralPath $chocoExe)) { throw "choco was not found." }
Refresh-SessionPath

$azPath = Resolve-AzCommandPath
$existingAzWasUnhealthy = $false
if (-not [string]::IsNullOrWhiteSpace($azPath)) {
    Write-Host ("Existing Azure CLI installation is already healthy: {0}" -f $azPath)
    & $azPath version
    if ($LASTEXITCODE -eq 0) {
        Ensure-AzCommandPathAvailable -AzCommandPath $azPath
        Write-Host "Update task completed: install-azure-cli-tool"
        return
    }

    Write-Host ("azure-cli-reinstall => existing-install-unhealthy; exit={0}" -f $LASTEXITCODE) -ForegroundColor Yellow
    $existingAzWasUnhealthy = $true
}

if ($existingAzWasUnhealthy) {
    Write-Host 'azure-cli-reinstall => uninstall existing package'
    & $chocoExe uninstall azure-cli -y
    $uninstallExit = [int]$LASTEXITCODE
    Refresh-SessionPath
    if ($uninstallExit -notin @(0, 2, 1605, 1614, 1641, 3010) -and (Test-ChocoAzureCliPackageListed)) {
        throw "choco uninstall azure-cli failed with exit code $uninstallExit."
    }
}

& $chocoExe install azure-cli -y --no-progress --ignore-detected-reboot
if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 2) { throw "choco install azure-cli failed with exit code $LASTEXITCODE." }
Refresh-SessionPath

$azPath = Resolve-AzCommandPath
if ([string]::IsNullOrWhiteSpace($azPath)) {
    foreach ($candidatePath in @(
        "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin",
        "C:\Program Files (x86)\Microsoft SDKs\Azure\CLI2\wbin",
        "C:\ProgramData\chocolatey\bin"
    )) {
        if (Test-Path -LiteralPath $candidatePath) {
            Add-MachinePathEntry -Entry $candidatePath
        }
    }
    Refresh-SessionPath
    $azPath = Resolve-AzCommandPath
}

if ([string]::IsNullOrWhiteSpace($azPath)) {
    $wingetExe = Resolve-WingetExe
    if (-not [string]::IsNullOrWhiteSpace([string]$wingetExe)) {
        Write-Host 'azure-cli-install-fallback => winget' -ForegroundColor Yellow
        & $wingetExe install --id Microsoft.AzureCLI --exact --accept-source-agreements --accept-package-agreements --silent --disable-interactivity
        $wingetExitCode = [int]$LASTEXITCODE
        if ($wingetExitCode -ne 0 -and $wingetExitCode -ne -1978335189) {
            throw "winget install Microsoft.AzureCLI failed with exit code $wingetExitCode."
        }
        Refresh-SessionPath
        $azPath = Resolve-AzCommandPath
    }
}

if ([string]::IsNullOrWhiteSpace($azPath)) {
    throw "az command was not found after install."
}

Ensure-AzCommandPathAvailable -AzCommandPath $azPath
Write-Host ("Resolved az executable: {0}" -f $azPath)
& $azPath version
if ($LASTEXITCODE -ne 0) {
    throw "az version command failed with exit code $LASTEXITCODE."
}
Write-Host "Update task completed: install-azure-cli-tool"

