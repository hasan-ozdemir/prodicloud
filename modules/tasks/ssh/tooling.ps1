# SSH tooling and pyssh bootstrap helpers.

# Handles Resolve-ClagnosSshRetryCount.
function Resolve-ClagnosSshRetryCount {
    param(
        [string]$RetryText,
        [int]$DefaultValue = 3
    )

    $value = $DefaultValue
    if ($RetryText -match '^\d+$') {
        $value = [int]$RetryText
    }

    if ($value -lt 1) {
        $value = 1
    }
    if ($value -gt 3) {
        $value = 3
    }

    return $value
}

# Handles Resolve-ClagnosPySshToolPath.
function Resolve-ClagnosPySshToolPath {
    param(
        [string]$ConfiguredPath,
        [string]$RepoRoot,
        [string]$ToolName
    )

    if (-not [string]::IsNullOrWhiteSpace($ConfiguredPath)) {
        $candidate = [string]$ConfiguredPath
        if (-not [System.IO.Path]::IsPathRooted($candidate)) {
            $candidate = Join-Path $RepoRoot $candidate
        }
        if (Test-Path -LiteralPath $candidate) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    $defaultPath = Join-Path (Join-Path $RepoRoot "tools\\pyssh") $ToolName
    if (Test-Path -LiteralPath $defaultPath) {
        return (Resolve-Path -LiteralPath $defaultPath).Path
    }

    return $defaultPath
}

# Handles Ensure-ClagnosPySshTools.
function Ensure-ClagnosPySshTools {
    param(
        [string]$RepoRoot,
        [string]$ConfiguredPySshClientPath = ""
    )

    $configuredClientPath = [string]$ConfiguredPySshClientPath
    $pySshClientPath = Resolve-ClagnosPySshToolPath -ConfiguredPath $configuredClientPath -RepoRoot $RepoRoot -ToolName "ssh_client.py"
    $pySshVenvRoot = Join-Path (Join-Path $RepoRoot "tools\pyssh") ".venv"
    $isWindowsPlatform = ([System.IO.Path]::DirectorySeparatorChar -eq '\')
    $pySshPythonPath = if ($isWindowsPlatform) {
        Join-Path $pySshVenvRoot "Scripts\python.exe"
    }
    else {
        Join-Path $pySshVenvRoot "bin/python"
    }

    if ((Test-Path -LiteralPath $pySshClientPath) -and (Test-Path -LiteralPath $pySshPythonPath)) {
        return [ordered]@{
            ClientPath = $pySshClientPath
            PythonPath = (Resolve-Path -LiteralPath $pySshPythonPath).Path
        }
    }

    $installerPath = Join-Path $RepoRoot "tools\\install-pyssh-tool.ps1"
    if (-not (Test-Path -LiteralPath $installerPath)) {
        throw "Python SSH tool installer script was not found: $installerPath"
    }

    Invoke-TrackedAction -Label ("powershell -File {0}" -f $installerPath) -Action {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $installerPath
        Assert-LastExitCode "install-pyssh-tool.ps1"
    } | Out-Null

    if (-not (Test-Path -LiteralPath $pySshClientPath)) {
        throw "Python SSH tools could not be initialized. Missing ssh_client.py."
    }
    if (-not (Test-Path -LiteralPath $pySshPythonPath)) {
        throw "Python SSH tools could not be initialized. Missing pyssh venv python executable."
    }

    return [ordered]@{
        ClientPath = $pySshClientPath
        PythonPath = (Resolve-Path -LiteralPath $pySshPythonPath).Path
    }
}
