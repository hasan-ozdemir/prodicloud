$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Write-Output 'Doing: prepare Chocolatey bootstrap'

function Merge-ClagnosPreservedChocolateyFiles {
    param([string]$SourcePath,[string]$DestinationPath)

    if (-not (Test-Path -LiteralPath $DestinationPath)) { Move-Item -LiteralPath $SourcePath -Destination $DestinationPath -Force; return }
    if ((Get-Item -LiteralPath $SourcePath).PSIsContainer -and (Get-Item -LiteralPath $DestinationPath).PSIsContainer) {
        foreach ($child in @(Get-ChildItem -LiteralPath $SourcePath -Force)) {
            Merge-ClagnosPreservedChocolateyFiles -SourcePath $child.FullName -DestinationPath (Join-Path $DestinationPath $child.Name)
        }
    }
}

$chocolateyRoot = [string][Environment]::GetEnvironmentVariable('ChocolateyInstall','Machine')
if ([string]::IsNullOrWhiteSpace($chocolateyRoot)) { $chocolateyRoot = [string]$env:ChocolateyInstall }
if ([string]::IsNullOrWhiteSpace($chocolateyRoot)) { $chocolateyRoot = Join-Path $env:ProgramData 'chocolatey' }
$chocolateyRoot = [IO.Path]::GetFullPath($chocolateyRoot.Trim())
$env:ChocolateyInstall = $chocolateyRoot
$chocoExe = Join-Path $chocolateyRoot 'bin\choco.exe'
if (-not (Test-Path -LiteralPath $chocoExe)) {
    Write-Output ("Doing: download official Chocolatey bootstrap for '{0}'" -f $chocolateyRoot)
    Set-ExecutionPolicy Bypass -Scope Process -Force
    $preservedRoot = ''
    try {
        if (Test-Path -LiteralPath $chocolateyRoot -PathType Container) {
            $existingItems = @(Get-ChildItem -LiteralPath $chocolateyRoot -Force)
            if ($existingItems.Count -gt 0) {
                $backupRoot = Join-Path (Join-Path $env:ProgramData 'clagnos\backup') ('chocolatey-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
                $null = New-Item -ItemType Directory -Path (Split-Path -Parent $backupRoot) -Force
                Write-Output ("Doing: preserve existing Chocolatey package files at '{0}' for the bootstrap" -f $backupRoot)
                Move-Item -LiteralPath $chocolateyRoot -Destination $backupRoot -ErrorAction Stop
                $preservedRoot = $backupRoot
            }
        }
        $response = Invoke-WebRequest -Uri 'https://community.chocolatey.org/install.ps1' -UseBasicParsing -TimeoutSec 90 -ErrorAction Stop
        $installerSource = [string]$response.Content
        if ([string]::IsNullOrWhiteSpace($installerSource) -or $installerSource.Length -lt 1000) { throw 'The official bootstrap response was empty or unexpectedly short.' }
        $bootstrapOutput = & ([scriptblock]::Create($installerSource)) *>&1 | Out-String
        if (-not [string]::IsNullOrWhiteSpace($bootstrapOutput)) { Write-Output $bootstrapOutput.TrimEnd() }
        if (-not (Test-Path -LiteralPath $chocoExe -PathType Leaf)) { throw ("The official bootstrap did not create '{0}'." -f $chocoExe) }
        if (-not [string]::IsNullOrWhiteSpace($preservedRoot)) {
            foreach ($child in @(Get-ChildItem -LiteralPath $preservedRoot -Force)) {
                Merge-ClagnosPreservedChocolateyFiles -SourcePath $child.FullName -DestinationPath (Join-Path $chocolateyRoot $child.Name)
            }
            Write-Output 'Preserved existing Chocolatey package files; new Chocolatey core files took precedence only on path conflicts.'
        }
    }
    catch {
        $bootstrapDetail = [string]$_.Exception.Message
        if (-not [string]::IsNullOrWhiteSpace([string]$bootstrapOutput)) { $bootstrapDetail += "`n" + [string]$bootstrapOutput.Trim() }
        if (-not [string]::IsNullOrWhiteSpace($preservedRoot) -and (Test-Path -LiteralPath $preservedRoot -PathType Container)) {
            if (Test-Path -LiteralPath $chocolateyRoot -PathType Container) {
                $failedRoot = Join-Path (Split-Path -Parent $preservedRoot) ((Split-Path -Leaf $preservedRoot) + '-incomplete-bootstrap')
                Move-Item -LiteralPath $chocolateyRoot -Destination $failedRoot -Force -ErrorAction SilentlyContinue
            }
            Move-Item -LiteralPath $preservedRoot -Destination $chocolateyRoot -Force -ErrorAction SilentlyContinue
        }
        throw ("Official Chocolatey bootstrap failed: {0}" -f $bootstrapDetail)
    }
}

$chocoExe = Join-Path $chocolateyRoot 'bin\choco.exe'
if (-not (Test-Path -LiteralPath $chocoExe)) {
    throw ("Chocolatey bootstrap returned without creating the expected CLI executable at '{0}'. Preserve the Chocolatey folder and inspect the bootstrap output before retrying." -f $chocoExe)
}

$featureOutput = & $chocoExe feature enable -n allowGlobalConfirmation 2>&1 | Out-String
if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 2) {
    throw ("choco feature enable allowGlobalConfirmation failed with exit code {0}. {1}" -f $LASTEXITCODE,$featureOutput.Trim())
}

$versionOutput = & $chocoExe --version 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
    throw ("choco version check failed with exit code {0}. {1}" -f $LASTEXITCODE,$versionOutput.Trim())
}

Write-Output ("Chocolatey is ready at version {0}." -f $versionOutput.Trim())

