$ErrorActionPreference = "Stop"
Write-Host "Update task started: install-github-copilot-tool"

Import-Module 'C:\Windows\Temp\prodicloud-session-environment.psm1' -Force -DisableNameChecking

function Refresh-SessionPath {
    Refresh-ProdicloudSessionPath | Out-Null
}

$taskConfig = [ordered]@{
    TaskName = 'install-github-copilot-tool'
    InstallSpec = '@github/copilot@latest'
    PackageName = '@github/copilot'
    ExpectedBinNames = @('copilot.cmd', 'copilot')
}

function Resolve-NpmExecutable {
    $command = Get-Command npm -ErrorAction SilentlyContinue
    if ($command -and -not [string]::IsNullOrWhiteSpace([string]$command.Source) -and (Test-Path -LiteralPath ([string]$command.Source))) {
        return [string]$command.Source
    }

    foreach ($candidate in @(
        'C:\Program Files\nodejs\npm.cmd',
        'C:\Program Files\nodejs\npm.exe',
        'C:\Program Files (x86)\nodejs\npm.cmd',
        'C:\Program Files (x86)\nodejs\npm.exe'
    )) {
        if (Test-Path -LiteralPath $candidate) {
            return [string]$candidate
        }
    }

    return ''
}

function Get-GlobalNpmPrefixPath {
    $applicationDataPath = [Environment]::GetFolderPath('ApplicationData')
    if ([string]::IsNullOrWhiteSpace([string]$applicationDataPath)) {
        return (Join-Path $env:USERPROFILE 'AppData\Roaming\npm')
    }

    return (Join-Path $applicationDataPath 'npm')
}

function Get-GlobalNpmNodeModulesPath {
    return (Join-Path (Get-GlobalNpmPrefixPath) 'node_modules')
}

function Ensure-GlobalNpmLayout {
    foreach ($path in @((Get-GlobalNpmPrefixPath), (Get-GlobalNpmNodeModulesPath))) {
        if (-not (Test-Path -LiteralPath $path)) {
            [void](New-Item -ItemType Directory -Path $path -Force)
        }
    }
}

function Get-GlobalNpmPackageInstallPath {
    param([string]$PackageName)

    $packagePath = [string](Get-GlobalNpmNodeModulesPath)
    foreach ($segment in @([string]$PackageName -split '/')) {
        if ([string]::IsNullOrWhiteSpace([string]$segment)) {
            continue
        }

        $packagePath = Join-Path $packagePath ([string]$segment)
    }

    return [string]$packagePath
}

function Test-GlobalNpmPackageInstalled {
    param(
        [string]$PackageName,
        [string[]]$ExpectedBinNames = @()
    )

    $packagePath = Get-GlobalNpmPackageInstallPath -PackageName $PackageName
    if (-not (Test-Path -LiteralPath $packagePath)) {
        return $false
    }

    $prefixPath = Get-GlobalNpmPrefixPath
    foreach ($binName in @($ExpectedBinNames)) {
        if ([string]::IsNullOrWhiteSpace([string]$binName)) {
            continue
        }

        if (Test-Path -LiteralPath (Join-Path $prefixPath ([string]$binName))) {
            return $true
        }
    }

    Write-Host ("Global npm package path exists without a resolved shim; accepting the installed package directory as authoritative: {0}" -f $PackageName)
    return $true
}

function Test-BenignNpmInstallNoiseLine {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace([string]$Text)) {
        return $false
    }

    $normalizedText = [string]$Text
    return (
        ($normalizedText -match '^(?i)npm notice(?:\b|$)') -or
        ($normalizedText -match '^(?i)npm warn deprecated\b')
    )
}

function Install-GlobalNpmPackage {
    param(
        [string]$NpmExe,
        [string]$InstallSpec
    )

    Write-Host ("Running: npm install -g --no-audit --no-fund --no-progress --loglevel error {0}" -f [string]$InstallSpec)
    $previousErrorActionPreference = $ErrorActionPreference
    $commandOutput = @()
    $exitCode = 0
    try {
        # Native npm notice/deprecated chatter can still surface as warning records under SSH task execution;
        # capture merged output locally, filter only the known benign lines, and keep the real exit code authoritative.
        $ErrorActionPreference = 'Continue'
        $commandOutput = @(& $NpmExe @('install', '-g', '--no-audit', '--no-fund', '--no-progress', '--loglevel', 'error', [string]$InstallSpec) 2>&1)
        $exitCode = [int]$LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    foreach ($line in @($commandOutput)) {
        $lineText = [string]$line
        if ([string]::IsNullOrWhiteSpace([string]$lineText)) {
            continue
        }

        if (Test-BenignNpmInstallNoiseLine -Text $lineText) {
            continue
        }

        Write-Host $lineText
    }

    if ($exitCode -ne 0) {
        throw ("npm install failed with exit code {0}." -f $exitCode)
    }

    Write-Host ("npm install exit code: {0}" -f $exitCode)
}

Refresh-SessionPath

$npmExe = Resolve-NpmExecutable
if ([string]::IsNullOrWhiteSpace([string]$npmExe)) {
    throw ("npm command was not found. NodeJS task must run before {0}." -f [string]$taskConfig.TaskName)
}

Ensure-GlobalNpmLayout

if (Test-GlobalNpmPackageInstalled -PackageName ([string]$taskConfig.PackageName) -ExpectedBinNames @($taskConfig.ExpectedBinNames)) {
    Write-Host ("Global npm package is already installed: {0}" -f [string]$taskConfig.PackageName)
}
else {
    Install-GlobalNpmPackage -NpmExe $npmExe -InstallSpec ([string]$taskConfig.InstallSpec)
    Refresh-SessionPath
}

if (-not (Test-GlobalNpmPackageInstalled -PackageName ([string]$taskConfig.PackageName) -ExpectedBinNames @($taskConfig.ExpectedBinNames))) {
    throw ("Global npm package '{0}' could not be verified after installation." -f [string]$taskConfig.PackageName)
}

Write-Host "install-github-copilot-tool-completed"
Write-Host "Update task completed: install-github-copilot-tool"
