$ErrorActionPreference = 'Stop'
Write-Output 'Doing: install FFmpeg through its Chocolatey package'

Import-Module 'C:\Windows\Temp\clagnos-session-environment.psm1' -Force -DisableNameChecking

Refresh-ClagnosSessionPath | Out-Null

$chocolateyRoot = [string][Environment]::GetEnvironmentVariable('ChocolateyInstall','Machine')
if ([string]::IsNullOrWhiteSpace($chocolateyRoot)) { $chocolateyRoot = [string]$env:ChocolateyInstall }
if ([string]::IsNullOrWhiteSpace($chocolateyRoot)) { $chocolateyRoot = Join-Path $env:ProgramData 'chocolatey' }
$chocoExe = Join-Path ([IO.Path]::GetFullPath($chocolateyRoot)) 'bin\choco.exe'
if (-not (Test-Path -LiteralPath $chocoExe -PathType Leaf)) { throw ("Chocolatey executable was not found at '{0}'." -f $chocoExe) }

Write-Output 'Doing: run unattended Chocolatey install for FFmpeg'
& $chocoExe install ffmpeg -y --no-progress --ignore-detected-reboot
if ($LASTEXITCODE -notin @(0,2)) { throw ("Chocolatey install ffmpeg failed with exit code {0}." -f [int]$LASTEXITCODE) }
Refresh-ClagnosSessionPath | Out-Null
$ffmpegRecord = Get-ClagnosChocolateyPackageExecutableRecord -PackageId 'ffmpeg' -ExecutableName 'ffmpeg.exe'
if ([string]$ffmpegRecord.Status -ne 'installed') {
    throw ("FFmpeg installation did not produce a runnable ffmpeg.exe. {0}" -f [string]$ffmpegRecord.Detail)
}
Write-Output ('FFmpeg executable verified: {0}' -f [string]$ffmpegRecord.Path)
Write-Output ([string]$ffmpegRecord.VersionText)
Write-Output 'FFmpeg install script completed.'

