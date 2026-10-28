$ErrorActionPreference = 'Stop'
Write-Output 'Doing: install GitHub CLI through its Chocolatey package'

Import-Module 'C:\Windows\Temp\prodicloud-session-environment.psm1' -Force -DisableNameChecking

function Refresh-SessionPath {
    Refresh-ProdicloudSessionPath | Out-Null
}

$chocoExe = "$env:ProgramData\chocolatey\bin\choco.exe"
if (-not (Test-Path -LiteralPath $chocoExe)) { throw "choco was not found." }
Refresh-SessionPath

Write-Output 'Doing: run unattended Chocolatey install for GitHub CLI'
& $chocoExe install gh -y --no-progress --ignore-detected-reboot
if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 2) { throw "choco install gh failed with exit code $LASTEXITCODE." }
Refresh-SessionPath
$ghExecutablePaths = @()
foreach ($root in @(
    [Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles),
    [Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFilesX86),
    [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
)) {
    if ([string]::IsNullOrWhiteSpace([string]$root)) { continue }
    $relativePath = if ([string]::Equals([string]$root,[Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData),[System.StringComparison]::OrdinalIgnoreCase)) { 'Programs\GitHub CLI\gh.exe' } else { 'GitHub CLI\gh.exe' }
    $ghExecutablePaths += Join-Path ([string]$root) $relativePath
}
$ghRecord = Get-ProdicloudChocolateyPackageExecutableRecord -PackageId 'gh' -ExecutableName 'gh.exe' -VersionArgument '--version' -AdditionalPaths $ghExecutablePaths
if ([string]$ghRecord.Status -ne 'installed') {
    throw ("GitHub CLI installation did not produce a runnable gh.exe. {0}" -f [string]$ghRecord.Detail)
}
Write-Output ('GitHub CLI executable verified: {0}' -f [string]$ghRecord.Path)
Write-Output ([string]$ghRecord.VersionText)
Write-Output 'GitHub CLI install script completed.'

