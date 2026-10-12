$ErrorActionPreference = "Stop"
Write-Host "Update task started: install-powershell-tool"

Import-Module 'C:\Windows\Temp\clagnos-session-environment.psm1' -Force -DisableNameChecking

function Refresh-SessionPath {
    Refresh-ClagnosSessionPath | Out-Null
}

function Resolve-PwshExePath {
    $command = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($command -and -not [string]::IsNullOrWhiteSpace([string]$command.Source) -and (Test-Path -LiteralPath ([string]$command.Source))) {
        return [string]$command.Source
    }

    foreach ($candidate in @(
        'C:\Program Files\PowerShell\7\pwsh.exe',
        'C:\Program Files\PowerShell\7-preview\pwsh.exe',
        'C:\Program Files (x86)\PowerShell\7\pwsh.exe'
    )) {
        if (Test-Path -LiteralPath $candidate) {
            return [string]$candidate
        }
    }

    return ''
}

function Ensure-MachinePathContains {
    param([string]$DirectoryPath)

    if ([string]::IsNullOrWhiteSpace([string]$DirectoryPath) -or -not (Test-Path -LiteralPath $DirectoryPath)) {
        return
    }

    $machinePath = [string][Environment]::GetEnvironmentVariable('Path', 'Machine')
    $entries = @()
    if (-not [string]::IsNullOrWhiteSpace([string]$machinePath)) {
        $entries = @($machinePath -split ';' | ForEach-Object { [string]$_.Trim() } | Where-Object { $_ })
    }

    if ($entries -contains $DirectoryPath) {
        return
    }

    $entries += [string]$DirectoryPath
    [Environment]::SetEnvironmentVariable('Path', ($entries -join ';'), 'Machine')
}

$chocoExe = "$env:ProgramData\chocolatey\bin\choco.exe"
if (-not (Test-Path -LiteralPath $chocoExe)) { throw "choco was not found." }
Refresh-SessionPath

$pwshExePath = Resolve-PwshExePath
if (-not [string]::IsNullOrWhiteSpace([string]$pwshExePath)) {
    Write-Host "Existing PowerShell 7 installation is already healthy. Skipping choco install."
    & $pwshExePath --version
    Write-Host "Update task completed: install-powershell-tool"
    return
}

& $chocoExe install powershell-core -y --no-progress --ignore-detected-reboot
$installExitCode = [int]$LASTEXITCODE
$pwshExePath = Resolve-PwshExePath
if (-not [string]::IsNullOrWhiteSpace([string]$pwshExePath)) {
    Ensure-MachinePathContains -DirectoryPath (Split-Path -Path $pwshExePath -Parent)
}
Refresh-SessionPath
$pwshExePath = Resolve-PwshExePath
if (-not [string]::IsNullOrWhiteSpace([string]$pwshExePath)) {
    & $pwshExePath --version
    Write-Host "Update task completed: install-powershell-tool"
    return
}

if ($installExitCode -ne 0 -and $installExitCode -ne 2 -and $installExitCode -ne 3010) { throw "choco install powershell-core failed with exit code $installExitCode." }
throw "pwsh command was not found after install."
Write-Host "Update task completed: install-powershell-tool"

