$ErrorActionPreference = "Stop"
Write-Host "Update task started: install-node-tool"

Import-Module 'C:\Windows\Temp\clagnos-session-environment.psm1' -Force -DisableNameChecking

function Refresh-SessionPath {
    Refresh-ClagnosSessionPath | Out-Null
}

function Resolve-NodeCommand {
    $command = Get-Command node -ErrorAction SilentlyContinue
    if ($command -and -not [string]::IsNullOrWhiteSpace([string]$command.Source)) {
        return [string]$command.Source
    }

    foreach ($candidate in @(
        "C:\Program Files\nodejs\node.exe",
        "C:\Program Files (x86)\nodejs\node.exe"
    )) {
        if (Test-Path -LiteralPath $candidate) {
            return [string]$candidate
        }
    }

    return ""
}

function Wait-NodeCommand {
    param(
        [int]$TimeoutSeconds = 30,
        [int]$PollSeconds = 2
    )

    if ($TimeoutSeconds -lt 1) {
        $TimeoutSeconds = 1
    }
    if ($PollSeconds -lt 1) {
        $PollSeconds = 1
    }

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        Refresh-SessionPath
        $resolvedNode = Resolve-NodeCommand
        if (-not [string]::IsNullOrWhiteSpace([string]$resolvedNode)) {
            return [string]$resolvedNode
        }

        Start-Sleep -Seconds $PollSeconds
    }

    Refresh-SessionPath
    return [string](Resolve-NodeCommand)
}

$chocoExe = "$env:ProgramData\chocolatey\bin\choco.exe"
if (-not (Test-Path -LiteralPath $chocoExe)) {
    throw "choco was not found."
}

Refresh-SessionPath

$existingNode = Resolve-NodeCommand
if ([string]::IsNullOrWhiteSpace([string]$existingNode)) {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $entries = @()
    if (-not [string]::IsNullOrWhiteSpace($machinePath)) {
        $entries = $machinePath -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    }
    foreach ($candidate in @("C:\Program Files\nodejs")) {
        if ((Test-Path -LiteralPath $candidate) -and ($entries -notcontains $candidate)) {
            $entries += $candidate
        }
    }
    [Environment]::SetEnvironmentVariable("Path", ($entries -join ';'), "Machine")
    Refresh-SessionPath
}

$existingNode = Resolve-NodeCommand
if (-not [string]::IsNullOrWhiteSpace([string]$existingNode)) {
    Write-Host "Existing Node.js installation is already healthy. Skipping choco install."
    & $existingNode --version
    Write-Host "Update task completed: install-node-tool"
    return
}

& $chocoExe install nodejs-lts -y --no-progress --ignore-detected-reboot
if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 2) {
    throw "choco install nodejs-lts failed with exit code $LASTEXITCODE."
}

Write-Host "Waiting for node command to become available after Chocolatey install..."
$installedNode = Wait-NodeCommand -TimeoutSeconds 30 -PollSeconds 2
if ([string]::IsNullOrWhiteSpace([string]$installedNode)) {
    throw "node command was not found after installation."
}

& $installedNode --version
Write-Host "Update task completed: install-node-tool"

