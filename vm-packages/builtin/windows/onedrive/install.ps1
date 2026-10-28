$ErrorActionPreference = "Stop"
Write-Host "Update task started: install-onedrive-application"

$managerUser = "__VM_ADMIN_USER__"
$assistantUser = "__ASSISTANT_USER__"
$taskConfig = [ordered]@{
    PortableWingetPath = 'C:\ProgramData\prodicloud\tools\winget-x64\winget.exe'
    OneDrivePackageId = 'Microsoft.OneDrive'
    OneDriveExecutableCandidates = @(
        'C:\Program Files\Microsoft OneDrive\OneDrive.exe',
        ("C:\Users\{0}\AppData\Local\Microsoft\OneDrive\OneDrive.exe" -f $managerUser),
        ("C:\Users\{0}\AppData\Local\Microsoft\OneDrive\OneDrive.exe" -f $assistantUser)
    )
}

Import-Module 'C:\Windows\Temp\prodicloud-session-environment.psm1' -Force -DisableNameChecking

function Refresh-SessionPath {
    Refresh-ProdicloudSessionPath | Out-Null
}

function Resolve-WingetExe {
    $portableCandidate = [string]$taskConfig.PortableWingetPath
    if (Test-Path -LiteralPath $portableCandidate) {
        return [string]$portableCandidate
    }

    $cmd = Get-Command winget -ErrorAction SilentlyContinue
    if ($cmd -and -not [string]::IsNullOrWhiteSpace([string]$cmd.Source)) {
        return [string]$cmd.Source
    }

    return ""
}

function Resolve-OneDriveExe {
    foreach ($candidate in @($taskConfig.OneDriveExecutableCandidates)) {
        if (Test-Path -LiteralPath $candidate) {
            return [string]$candidate
        }
    }

    return ""
}

Refresh-SessionPath
$existingExe = Resolve-OneDriveExe
if (-not [string]::IsNullOrWhiteSpace([string]$existingExe)) {
    Write-Host ("OneDrive executable already exists: {0}" -f $existingExe)
    Write-Host "install-onedrive-application-completed"
    Write-Host "Update task completed: install-onedrive-application"
    return
}

$wingetExe = Resolve-WingetExe
if ([string]::IsNullOrWhiteSpace([string]$wingetExe)) {
    throw "winget command is not available."
}

Write-Host "Resolved winget executable: $wingetExe"
Write-Host ("Running: winget install --id {0} --accept-source-agreements --accept-package-agreements --silent --disable-interactivity" -f [string]$taskConfig.OneDrivePackageId)
& $wingetExe install --id ([string]$taskConfig.OneDrivePackageId) --accept-source-agreements --accept-package-agreements --silent --disable-interactivity
$installExit = [int]$LASTEXITCODE
if ($installExit -ne 0 -and $installExit -ne -1978335189) {
    throw ("winget install {0} failed with exit code {1}." -f [string]$taskConfig.OneDrivePackageId, $installExit)
}

Refresh-SessionPath
$installedExe = Resolve-OneDriveExe
if ([string]::IsNullOrWhiteSpace([string]$installedExe)) {
    Write-Host ("Running: winget list --id {0}" -f [string]$taskConfig.OneDrivePackageId)
    $listOutput = & $wingetExe list --id ([string]$taskConfig.OneDrivePackageId)
    $listText = [string]($listOutput | Out-String)
    if ([string]::IsNullOrWhiteSpace($listText) -or -not $listText.ToLowerInvariant().Contains("onedrive")) {
        throw "OneDrive install could not be verified."
    }
}

Write-Host "install-onedrive-application-completed"
Write-Host "Update task completed: install-onedrive-application"

