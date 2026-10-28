$ErrorActionPreference = "Stop"
Write-Host "Update task started: install-python-tool"

Import-Module 'C:\Windows\Temp\prodicloud-store-install-state.psm1' -Force -DisableNameChecking

function Resolve-PythonCommandPath {
    foreach ($candidatePath in @(
        'C:\Python312\python.exe',
        'C:\Python312\Scripts\python.exe'
    )) {
        if (Test-Path -LiteralPath $candidatePath) {
            return [string]$candidatePath
        }
    }

    foreach ($commandName in @('python', 'py')) {
        $command = Get-Command $commandName -ErrorAction SilentlyContinue
        if ($null -eq $command -or [string]::IsNullOrWhiteSpace([string]$command.Source)) {
            continue
        }

        $resolvedPath = [string]$command.Source
        if (-not [System.IO.Path]::IsPathRooted($resolvedPath)) {
            continue
        }

        if (-not (Test-Path -LiteralPath $resolvedPath)) {
            continue
        }

        if ($resolvedPath.ToLowerInvariant().Contains('\microsoft\windowsapps\')) {
            continue
        }

        return [string]$resolvedPath
    }

    return ''
}

$chocoExe = "$env:ProgramData\chocolatey\bin\choco.exe"
if (-not (Test-Path -LiteralPath $chocoExe)) {
    throw "choco was not found."
}

$pythonCommandPath = ''
Invoke-ProdicloudRefreshSessionPath

if ([string]::IsNullOrWhiteSpace([string](Resolve-PythonCommandPath))) {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $entries = @()
    if (-not [string]::IsNullOrWhiteSpace($machinePath)) {
        $entries = $machinePath -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    }
    foreach ($candidate in @("C:\Python312", "C:\Python312\Scripts")) {
        if ((Test-Path -LiteralPath $candidate) -and ($entries -notcontains $candidate)) {
            $entries += $candidate
        }
    }
    [Environment]::SetEnvironmentVariable("Path", ($entries -join ';'), "Machine")
    Invoke-ProdicloudRefreshSessionPath
}

$pythonCommandPath = Resolve-PythonCommandPath
if (-not [string]::IsNullOrWhiteSpace([string]$pythonCommandPath)) {
    Write-Host "Existing Python installation is already healthy. Skipping choco install."
    Write-Host ("python-command-path => {0}" -f [string]$pythonCommandPath)
    & $pythonCommandPath --version
    Write-Host "Update task completed: install-python-tool"
    return
}

& $chocoExe install python312 -y --no-progress --ignore-detected-reboot
if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 2) {
    throw "choco install python312 failed with exit code $LASTEXITCODE."
}

Invoke-ProdicloudRefreshSessionPath

$pythonCommandPath = Resolve-PythonCommandPath
if ([string]::IsNullOrWhiteSpace([string]$pythonCommandPath)) {
    throw "python executable was not found after installation."
}

Write-Host ("python-command-path => {0}" -f [string]$pythonCommandPath)
& $pythonCommandPath --version
Write-Host "Update task completed: install-python-tool"

