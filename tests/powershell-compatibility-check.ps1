param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$testScript = Join-Path $PSScriptRoot "clagnos-smoke-tests.ps1"
if (-not (Test-Path -LiteralPath $testScript)) {
    throw "Compatibility smoke script was not found: $testScript"
}
$tuiTestScript = Join-Path $PSScriptRoot "tui\run-tui-tests.ps1"
if (-not (Test-Path -LiteralPath $tuiTestScript)) {
    throw "TUI test script was not found: $tuiTestScript"
}

$targets = @(
    @{
        Label = "Windows PowerShell 5.1"
        Exe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    },
    @{
        Label = "PowerShell 7+"
        Exe = "pwsh.exe"
    }
)

$failedTargets = @()
foreach ($target in $targets) {
    $label = [string]$target.Label
    $exe = [string]$target.Exe

    Write-Host ""
    Write-Host ("=== Running compatibility matrix target: {0} ===" -f $label) -ForegroundColor Cyan

    $cmd = Get-Command $exe -ErrorAction SilentlyContinue
    if (-not $cmd) {
        Write-Host ("Target shell is not installed or not reachable: {0}" -f $exe) -ForegroundColor Yellow
        $failedTargets += $label
        continue
    }

    foreach ($scriptPath in @($testScript,$tuiTestScript)) {
        $scriptLabel = Split-Path -Leaf $scriptPath
        Write-Host ("--- {0} / {1} ---" -f $label,$scriptLabel) -ForegroundColor DarkCyan
        $output = & $cmd.Source -NoProfile -ExecutionPolicy Bypass -File $scriptPath -RepoRoot $RepoRoot 2>&1
        foreach ($line in @($output)) {
            Write-Host ([string]$line)
        }

        if ($LASTEXITCODE -ne 0) {
            $failureLabel = '{0} / {1}' -f $label,$scriptLabel
            Write-Host ("Target failed: {0} (exit={1})" -f $failureLabel, $LASTEXITCODE) -ForegroundColor Red
            $failedTargets += $failureLabel
        }
        else {
            Write-Host ("Target passed: {0} / {1}" -f $label,$scriptLabel) -ForegroundColor Green
        }
    }
}

if ($failedTargets.Count -gt 0) {
    Write-Host ""
    Write-Host ("Compatibility matrix failed for: {0}" -f ($failedTargets -join ", ")) -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Compatibility matrix passed on all targets." -ForegroundColor Green
