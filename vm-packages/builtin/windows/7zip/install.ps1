$ErrorActionPreference = "Stop"
Write-Host "Update task started: install-7zip-tool"

Import-Module 'C:\Windows\Temp\clagnos-session-environment.psm1' -Force -DisableNameChecking

function Refresh-SessionPath {
    Refresh-ClagnosSessionPath | Out-Null
}

Refresh-SessionPath

function Resolve-WingetExe {
    $portableCandidate = 'C:\ProgramData\clagnos\tools\winget-x64\winget.exe'
    if (Test-Path -LiteralPath $portableCandidate -PathType Leaf) { return $portableCandidate }
    $command = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $command) { $command = Get-Command winget -ErrorAction SilentlyContinue }
    if ($command -and -not [string]::IsNullOrWhiteSpace([string]$command.Source)) { return [string]$command.Source }
    return ''
}

function Resolve-SevenZipExe {
    foreach ($candidate in @(
        'C:\Program Files\7-Zip\7z.exe',
        'C:\Program Files (x86)\7-Zip\7z.exe'
    )) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    return ''
}

$existingExe = Resolve-SevenZipExe
if (-not [string]::IsNullOrWhiteSpace([string]$existingExe)) {
    Write-Host ("Existing 7-Zip installation is already healthy at {0}. Skipping install." -f $existingExe)
    & $existingExe
    Write-Host "Update task completed: install-7zip-tool"
    return
}

$wingetExe = Resolve-WingetExe
if ([string]::IsNullOrWhiteSpace([string]$wingetExe)) { throw 'winget command is not available.' }
Write-Host ("Resolved winget executable: {0}" -f $wingetExe)
Write-Host 'Running: winget install --id 7zip.7zip --exact --silent --accept-source-agreements --accept-package-agreements --disable-interactivity'
& $wingetExe install --id 7zip.7zip --exact --silent --accept-source-agreements --accept-package-agreements --disable-interactivity
$installExit = [int]$LASTEXITCODE
if ($installExit -ne 0 -and $installExit -ne -1978335189) { throw ("winget install 7zip.7zip failed with exit code {0}." -f $installExit) }
Refresh-SessionPath
$installedExe = Resolve-SevenZipExe
if ([string]::IsNullOrWhiteSpace([string]$installedExe)) { throw '7z.exe was not found after install.' }
& $installedExe
Write-Host "Update task completed: install-7zip-tool"

