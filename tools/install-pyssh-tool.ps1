param(
    [string]$ToolsRoot = (Join-Path $PSScriptRoot "pyssh"),
    [string]$RepoRoot = "",
    [string]$PythonExe = "",
    [string]$RequirementsFile = "",
    [string]$TestHost = "",
    [int]$TestPort = 0,
    [string]$TestUser = "",
    [string]$TestPassword = "",
    [int]$TestTimeoutSeconds = 15,
    [switch]$ConnectionTest,
    [switch]$SkipConnectionTest
)

$ErrorActionPreference = "Stop"
$env:PYTHONDONTWRITEBYTECODE = "1"

# Handles Invoke-PythonNoBytecode.
function Invoke-PythonNoBytecode {
    param(
        [string]$PythonPath,
        [string[]]$Arguments
    )

    $previousDontWriteBytecode = [System.Environment]::GetEnvironmentVariable("PYTHONDONTWRITEBYTECODE", "Process")
    try {
        [System.Environment]::SetEnvironmentVariable("PYTHONDONTWRITEBYTECODE", "1", "Process")
        & $PythonPath -B @Arguments
    }
    finally {
        [System.Environment]::SetEnvironmentVariable("PYTHONDONTWRITEBYTECODE", $previousDontWriteBytecode, "Process")
    }
}

# Handles Remove-PythonCacheArtifacts.
function Remove-PythonCacheArtifacts {
    param(
        [string]$RootPath
    )

    if ([string]::IsNullOrWhiteSpace([string]$RootPath) -or -not (Test-Path -LiteralPath $RootPath)) {
        return
    }

    Get-ChildItem -LiteralPath $RootPath -Recurse -Force -Directory -Filter "__pycache__" -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

    Get-ChildItem -LiteralPath $RootPath -Recurse -Force -File -ErrorAction SilentlyContinue |
        Where-Object { @('.pyc', '.pyo') -contains ([string]$_.Extension).ToLowerInvariant() } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

# Handles Test-PythonPipModuleAvailable.
function Test-PythonPipModuleAvailable {
    param(
        [string]$PythonPath
    )

    if ([string]::IsNullOrWhiteSpace([string]$PythonPath) -or -not (Test-Path -LiteralPath $PythonPath)) {
        return $false
    }

    $pipMainPath = Join-Path (Split-Path -Parent $PythonPath) "..\Lib\site-packages\pip\__main__.py"
    if (-not (Test-Path -LiteralPath $pipMainPath)) {
        return $false
    }

    Invoke-PythonNoBytecode -PythonPath $PythonPath -Arguments @("-m", "pip", "--version") *> $null
    return ($LASTEXITCODE -eq 0)
}

function Get-DotEnvMap {
    param(
        [string]$Path
    )

    $map = @{}
    if ([string]::IsNullOrWhiteSpace([string]$Path) -or -not (Test-Path -LiteralPath $Path)) {
        return $map
    }

    foreach ($line in @(Get-Content -LiteralPath $Path)) {
        if ($null -eq $line) { continue }
        $text = [string]$line
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        if ($text.TrimStart().StartsWith('#')) { continue }

        $idx = $text.IndexOf('=')
        if ($idx -lt 1) { continue }
        $key = $text.Substring(0, $idx).Trim()
        if ([string]::IsNullOrWhiteSpace($key)) { continue }
        $value = $text.Substring($idx + 1).Trim()
        $map[$key] = $value
    }

    return $map
}

function Get-MapValue {
    param(
        [hashtable]$Map,
        [string]$Key,
        [string]$DefaultValue = ""
    )

    if ($Map -and $Map.ContainsKey($Key)) {
        return [string]$Map[$Key]
    }

    return [string]$DefaultValue
}

function Resolve-SystemPython {
    param(
        [string]$ConfiguredPath
    )

    if (-not [string]::IsNullOrWhiteSpace([string]$ConfiguredPath)) {
        if (-not (Test-Path -LiteralPath $ConfiguredPath)) {
            throw "Configured python executable was not found: $ConfiguredPath"
        }
        return (Resolve-Path -LiteralPath $ConfiguredPath).Path
    }

    $pythonCmd = Get-Command python -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $pythonCmd -or [string]::IsNullOrWhiteSpace([string]$pythonCmd.Source)) {
        throw "System python was not found in PATH. Install python first."
    }

    return [string]$pythonCmd.Source
}

if ([string]::IsNullOrWhiteSpace([string]$RepoRoot)) {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

if ([string]::IsNullOrWhiteSpace([string]$RequirementsFile)) {
    $RequirementsFile = Join-Path $ToolsRoot "requirements.txt"
}

if ($TestTimeoutSeconds -lt 5) {
    $TestTimeoutSeconds = 5
}

if (-not (Test-Path -LiteralPath $ToolsRoot)) {
    New-Item -Path $ToolsRoot -ItemType Directory -Force | Out-Null
}

$pythonExecutable = Resolve-SystemPython -ConfiguredPath $PythonExe
Write-Host ("System python resolved: {0}" -f $pythonExecutable)

$venvRoot = Join-Path $ToolsRoot ".venv"
$isWindowsPlatform = ([System.IO.Path]::DirectorySeparatorChar -eq '\')
$venvPython = if ($isWindowsPlatform) {
    Join-Path $venvRoot "Scripts\python.exe"
}
else {
    Join-Path $venvRoot "bin/python"
}

if (-not (Test-Path -LiteralPath $venvPython)) {
    Write-Host ("Creating pyssh virtual environment: {0}" -f $venvRoot)
    Invoke-PythonNoBytecode -PythonPath $pythonExecutable -Arguments @("-m", "venv", $venvRoot)
    if ($LASTEXITCODE -ne 0) {
        throw "python -m venv failed."
    }
}
else {
    Write-Host ("Using existing pyssh virtual environment: {0}" -f $venvRoot)
    if (-not (Test-PythonPipModuleAvailable -PythonPath $venvPython)) {
        Write-Host "Existing pyssh virtual environment has a broken pip bootstrap. Recreating..." -ForegroundColor Yellow
        Remove-Item -LiteralPath $venvRoot -Recurse -Force -ErrorAction Stop
        Invoke-PythonNoBytecode -PythonPath $pythonExecutable -Arguments @("-m", "venv", $venvRoot)
        if ($LASTEXITCODE -ne 0) {
            throw "python -m venv failed while rebuilding the pyssh virtual environment."
        }
    }
}

if (-not (Test-Path -LiteralPath $RequirementsFile)) {
    $requirementsText = @(
        "# pyssh runtime dependencies"
        "paramiko==4.0.0"
    ) -join "`n"
    [System.IO.File]::WriteAllText(
        $RequirementsFile,
        ($requirementsText + "`n"),
        (New-Object System.Text.UTF8Encoding($false))
    )
    Write-Host ("Created default requirements file: {0}" -f $RequirementsFile)
}

Write-Host "Installing pip requirements into pyssh virtual environment..."
Invoke-PythonNoBytecode -PythonPath $venvPython -Arguments @("-m", "ensurepip", "--upgrade", "--default-pip")
if ($LASTEXITCODE -ne 0) {
    throw "ensurepip bootstrap failed in pyssh virtual environment."
}

if (-not (Test-PythonPipModuleAvailable -PythonPath $venvPython)) {
    throw "pip bootstrap validation failed in pyssh virtual environment."
}

Invoke-PythonNoBytecode -PythonPath $venvPython -Arguments @("-m", "pip", "install", "--upgrade", "pip")
if ($LASTEXITCODE -ne 0) {
    throw "pip upgrade failed in pyssh virtual environment."
}

Invoke-PythonNoBytecode -PythonPath $venvPython -Arguments @("-m", "pip", "install", "--upgrade", "-r", $RequirementsFile)
if ($LASTEXITCODE -ne 0) {
    throw "pip requirements installation failed in pyssh virtual environment."
}

Remove-PythonCacheArtifacts -RootPath $ToolsRoot

$clientPath = Join-Path $ToolsRoot "ssh_client.py"
if (-not (Test-Path -LiteralPath $clientPath)) {
    throw "Expected SSH client script is missing: $clientPath"
}

$envMap = Get-DotEnvMap -Path (Join-Path $RepoRoot "prodicloud.env")
if ([string]::IsNullOrWhiteSpace([string]$TestUser)) {
    $TestUser = Get-MapValue -Map $envMap -Key "VM_ADMIN_USER" -DefaultValue ""
}
if ([string]::IsNullOrWhiteSpace([string]$TestPassword)) {
    $TestPassword = Get-MapValue -Map $envMap -Key "VM_ADMIN_PASS" -DefaultValue ""
}
if ($TestPort -le 0) {
    $sshPortText = Get-MapValue -Map $envMap -Key "VM_SSH_PORT" -DefaultValue "444"
    if ($sshPortText -match '^\d+$') {
        $TestPort = [int]$sshPortText
    }
}
if ($TestPort -le 0) {
    $TestPort = 444
}

if ([string]::IsNullOrWhiteSpace([string]$TestHost)) {
    $hostCandidates = @(
        (Get-MapValue -Map $envMap -Key "SSH_HOST" -DefaultValue ""),
        (Get-MapValue -Map $envMap -Key "VM_HOST" -DefaultValue ""),
        (Get-MapValue -Map $envMap -Key "VM_FQDN" -DefaultValue ""),
        (Get-MapValue -Map $envMap -Key "VM_PUBLIC_IP" -DefaultValue ""),
        (Get-MapValue -Map $envMap -Key "PUBLIC_IP" -DefaultValue "")
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }

    if ($hostCandidates.Count -gt 0) {
        $TestHost = [string]$hostCandidates[0]
    }
    else {
        $vmName = Get-MapValue -Map $envMap -Key "SELECTED_VM_NAME" -DefaultValue ""
        $azLocation = Get-MapValue -Map $envMap -Key "SELECTED_AZURE_REGION" -DefaultValue ""
        if (-not [string]::IsNullOrWhiteSpace([string]$vmName) -and -not [string]::IsNullOrWhiteSpace([string]$azLocation)) {
            $TestHost = ("{0}.{1}.cloudapp.azure.com" -f $vmName, $azLocation)
        }
    }
}

$shouldRunConnectionTest = [bool]$ConnectionTest
if ($SkipConnectionTest) {
    $shouldRunConnectionTest = $false
}

if (-not $shouldRunConnectionTest) {
    Write-Host "Isolated SSH connection test is disabled by default. Use -ConnectionTest to run it." -ForegroundColor Yellow
}
else {
    $missing = @()
    if ([string]::IsNullOrWhiteSpace([string]$TestHost)) { $missing += "TestHost" }
    if ([string]::IsNullOrWhiteSpace([string]$TestUser)) { $missing += "TestUser" }
    if ([string]::IsNullOrWhiteSpace([string]$TestPassword)) { $missing += "TestPassword" }

    if ($missing.Count -gt 0) {
        Write-Warning ("Isolated SSH connection test skipped because required inputs are missing: {0}" -f ($missing -join ", "))
    }
    else {
        Write-Host ("Running isolated SSH connection test: {0}@{1}:{2}" -f $TestUser, $TestHost, $TestPort)
        Invoke-PythonNoBytecode -PythonPath $venvPython -Arguments @(
            $clientPath,
            "exec",
            "--host", $TestHost,
            "--port", [string]$TestPort,
            "--user", $TestUser,
            "--password", $TestPassword,
            "--timeout", [string]$TestTimeoutSeconds,
            "--command", "whoami"
        )

        if ($LASTEXITCODE -ne 0) {
            throw ("Isolated SSH connection test failed with exit code {0}." -f $LASTEXITCODE)
        }

        Write-Host "Isolated SSH connection test passed."
    }
}

Write-Host ""
Write-Host "Python SSH tools are ready:"
Write-Host ("- ToolsRoot: {0}" -f $ToolsRoot)
Write-Host ("- Python (venv): {0}" -f $venvPython)
Write-Host ("- Client: {0}" -f $clientPath)
Write-Host ("- Requirements: {0}" -f $RequirementsFile)
