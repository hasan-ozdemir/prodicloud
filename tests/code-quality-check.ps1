param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$env:PYTHONDONTWRITEBYTECODE = "1"

$results = @()

function Add-AuditResult {
    param(
        [string]$Name,
        [bool]$Passed,
        [string]$Detail
    )

    $script:results += [pscustomobject]@{
        Name = $Name
        Passed = $Passed
        Detail = $Detail
    }
}

function Invoke-AuditStep {
    param(
        [string]$Name,
        [scriptblock]$Action
    )

    try {
        . $Action
        Add-AuditResult -Name $Name -Passed $true -Detail "ok"
        Write-Host ("[PASS] {0}" -f $Name) -ForegroundColor Green
    }
    catch {
        Add-AuditResult -Name $Name -Passed $false -Detail $_.Exception.Message
        Write-Host ("[FAIL] {0}: {1}" -f $Name, $_.Exception.Message) -ForegroundColor Red
    }
}

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

function Resolve-PowerShellHost {
    $windowsPowerShell = Get-Command powershell.exe -ErrorAction SilentlyContinue
    if ($windowsPowerShell) {
        return $windowsPowerShell.Source
    }

    $powerShellCore = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($powerShellCore) {
        return $powerShellCore.Source
    }

    throw "Neither powershell.exe nor pwsh was found."
}

Invoke-AuditStep -Name "PowerShell parse (*.ps1)" -Action {
    $parseErrors = @()
    Get-ChildItem -Path $RepoRoot -Recurse -File -Filter *.ps1 | ForEach-Object {
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors)
        if ($errors -and $errors.Count -gt 0) {
            $first = $errors[0]
            $parseErrors += ("{0}:{1}: {2}" -f $_.FullName, $first.Extent.StartLineNumber, $first.Message)
        }
    }
    if ($parseErrors.Count -gt 0) {
        throw ($parseErrors -join "; ")
    }
}

Invoke-AuditStep -Name "Sensitive-content audit" -Action {
    $auditPath = Join-Path $RepoRoot "tests\sensitive-content-check.ps1"
    if (-not (Test-Path -LiteralPath $auditPath)) {
        throw "sensitive-content-check.ps1 was not found."
    }

    $powerShellHost = Resolve-PowerShellHost
    & $powerShellHost -NoLogo -NoProfile -ExecutionPolicy Bypass -File $auditPath -RepoRoot $RepoRoot -SkipHistoryAudit
    if ($LASTEXITCODE -ne 0) {
        throw "sensitive-content-check.ps1 failed."
    }
}

Invoke-AuditStep -Name "Documentation contract" -Action {
    $docContractPath = Join-Path $RepoRoot "tests\documentation-contract-check.ps1"
    if (-not (Test-Path -LiteralPath $docContractPath)) {
        throw "documentation-contract-check.ps1 was not found."
    }

    $powerShellHost = Resolve-PowerShellHost
    & $powerShellHost -NoLogo -NoProfile -ExecutionPolicy Bypass -File $docContractPath -RepoRoot $RepoRoot
    if ($LASTEXITCODE -ne 0) {
        throw "documentation-contract-check.ps1 failed."
    }
}

Invoke-AuditStep -Name "Package app-state contract" -Action {
    $contractPath = Join-Path $RepoRoot "tests\package-app-state-contract-check.ps1"
    if (-not (Test-Path -LiteralPath $contractPath)) {
        throw "package-app-state-contract-check.ps1 was not found."
    }

    $powerShellHost = Resolve-PowerShellHost
    & $powerShellHost -NoLogo -NoProfile -ExecutionPolicy Bypass -File $contractPath -RepoRoot $RepoRoot
    if ($LASTEXITCODE -ne 0) {
        throw "package-app-state-contract-check.ps1 failed."
    }
}

Invoke-AuditStep -Name "Package lifecycle contract" -Action {
    $lifecycleContractPath = Join-Path $RepoRoot "tests\package-lifecycle-contract-check.ps1"
    if (-not (Test-Path -LiteralPath $lifecycleContractPath)) {
        throw "package-lifecycle-contract-check.ps1 was not found."
    }

    $powerShellHost = Resolve-PowerShellHost
    & $powerShellHost -NoLogo -NoProfile -ExecutionPolicy Bypass -File $lifecycleContractPath -RepoRoot $RepoRoot
    if ($LASTEXITCODE -ne 0) {
        throw "package-lifecycle-contract-check.ps1 failed."
    }
}

Invoke-AuditStep -Name "Versioned release package" -Action {
    $releasePackageCheckPath = Join-Path $RepoRoot "tests\release-package-check.ps1"
    if (-not (Test-Path -LiteralPath $releasePackageCheckPath)) {
        throw "release-package-check.ps1 was not found."
    }

    $powerShellHost = Resolve-PowerShellHost
    & $powerShellHost -NoLogo -NoProfile -ExecutionPolicy Bypass -File $releasePackageCheckPath -RepoRoot $RepoRoot
    if ($LASTEXITCODE -ne 0) {
        throw "release-package-check.ps1 failed."
    }
}

Invoke-AuditStep -Name "Python syntax (Linux app-state portability)" -Action {
    $python = Get-Command python -ErrorAction SilentlyContinue
    if (-not $python) { throw "python command was not found." }
    $helperPath = Join-Path $RepoRoot "modules\core\tasks\clagnos-app-state-portability.py"
    if (-not (Test-Path -LiteralPath $helperPath -PathType Leaf)) { throw "Linux app-state portability helper was not found." }
    $syntaxProbe = @'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
source = path.read_text(encoding="utf-8")
compile(source, str(path), "exec")
'@
    $syntaxProbe | & $python.Source -B - $helperPath
    if ($LASTEXITCODE -ne 0) { throw "Linux app-state portability helper syntax check failed." }
}

Invoke-AuditStep -Name "Linux app-state placeholder round trip" -Action {
    $python = Get-Command python -ErrorAction SilentlyContinue
    if (-not $python) { throw "python command was not found." }
    $helperPath = Join-Path $RepoRoot "modules\core\tasks\clagnos-app-state-portability.py"
    $contractPath = Join-Path $RepoRoot "tests\linux-app-state-portability-check.py"
    if (-not (Test-Path -LiteralPath $contractPath -PathType Leaf)) { throw "Linux app-state portability contract test was not found." }
    & $python.Source -B $contractPath $helperPath
    if ($LASTEXITCODE -ne 0) { throw "Linux app-state placeholder round trip failed." }
}

Invoke-AuditStep -Name "Python syntax (tools/pyssh/ssh_client.py)" -Action {
    $python = Get-Command python -ErrorAction SilentlyContinue
    if (-not $python) {
        throw "python command was not found."
    }

    $clientPath = Join-Path $RepoRoot "tools\pyssh\ssh_client.py"
    if (-not (Test-Path -LiteralPath $clientPath)) {
        Write-Host "ssh_client.py was not found. Python syntax check skipped." -ForegroundColor Yellow
        return
    }

    $pyCachePath = Join-Path (Split-Path -Path $clientPath -Parent) "__pycache__"
    if (Test-Path -LiteralPath $pyCachePath) {
        Remove-Item -LiteralPath $pyCachePath -Recurse -Force -ErrorAction SilentlyContinue
    }

    $syntaxProbe = @'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
source = path.read_text(encoding="utf-8")
compile(source, str(path), "exec")
'@

    $previousDontWriteBytecode = [System.Environment]::GetEnvironmentVariable("PYTHONDONTWRITEBYTECODE", "Process")
    try {
        [System.Environment]::SetEnvironmentVariable("PYTHONDONTWRITEBYTECODE", "1", "Process")
        $syntaxProbe | & $python.Source -B - $clientPath
    }
    finally {
        [System.Environment]::SetEnvironmentVariable("PYTHONDONTWRITEBYTECODE", $previousDontWriteBytecode, "Process")
    }

    if ($LASTEXITCODE -ne 0) {
        throw "in-memory python syntax check failed."
    }
    if (Test-Path -LiteralPath $pyCachePath) {
        throw "__pycache__ must not be created by python syntax validation."
    }
}

Invoke-AuditStep -Name "Python cache artifact hygiene (tools/pyssh)" -Action {
    $pyRoot = Join-Path $RepoRoot "tools\pyssh"
    if (-not (Test-Path -LiteralPath $pyRoot)) {
        return
    }

    Remove-PythonCacheArtifacts -RootPath $pyRoot

    $cacheDirs = @(Get-ChildItem -LiteralPath $pyRoot -Recurse -Force -Directory -Filter "__pycache__" -ErrorAction SilentlyContinue)
    $cacheFiles = @(Get-ChildItem -LiteralPath $pyRoot -Recurse -Force -File -ErrorAction SilentlyContinue | Where-Object { @('.pyc', '.pyo') -contains ([string]$_.Extension).ToLowerInvariant() })
    if ($cacheDirs.Count -gt 0 -or $cacheFiles.Count -gt 0) {
        throw "Python cache artifacts must not remain under tools/pyssh."
    }
}

Invoke-AuditStep -Name "CLI help smoke" -Action {
    $scriptPath = Join-Path $RepoRoot "clagnos.ps1"
    $ps = Get-Command powershell.exe -ErrorAction SilentlyContinue
    if (-not $ps) {
        $ps = Get-Command pwsh -ErrorAction SilentlyContinue
    }
    if (-not $ps) {
        throw "Neither powershell.exe nor pwsh was found."
    }

    $cases = @(
        @("-h"),
        @("--help"),
        @("help"),
        @("help","-h"),
        @("help","create"),
        @("help","configure"),
        @("help","list"),
        @("help","do"),
        @("create","-h"),
        @("create","--help"),
        @("configure","-h"),
        @("configure","--help"),
        @("list","-h"),
        @("list","--help"),
        @("do","-h"),
        @("do","--help"),
        @("resize","-h"),
        @("resize","--help"),
        @("delete","-h"),
        @("delete","--help")
    )

    foreach ($case in $cases) {
        $out = & $ps.Source -NoLogo -NoProfile -ExecutionPolicy Bypass -File $scriptPath @case 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw ("help smoke failed for args: {0}" -f ($case -join " "))
        }
        $joined = (@($out) | ForEach-Object { [string]$_ }) -join "`n"
        if ([string]::IsNullOrWhiteSpace($joined)) {
            throw ("help smoke returned empty output for args: {0}" -f ($case -join " "))
        }
    }
}

Write-Host ""
Write-Host "Quality audit summary:" -ForegroundColor Cyan
$results | ForEach-Object {
    $status = if ($_.Passed) { "PASS" } else { "FAIL" }
    Write-Host ("- [{0}] {1}: {2}" -f $status, $_.Name, $_.Detail)
}

$failedCount = @($results | Where-Object { -not $_.Passed }).Count
if ($failedCount -gt 0) {
    exit 1
}
