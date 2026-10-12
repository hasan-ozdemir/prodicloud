$ErrorActionPreference = "Stop"
Write-Host "Update task started: configure-unlocker-settings"

$unlockerPackagePath = Join-Path $env:ProgramData 'chocolatey\lib\io-unlocker'
if (-not (Test-Path -LiteralPath $unlockerPackagePath -PathType Container)) {
    Write-Host 'unlocker-settings-skip => IObit Unlocker is not installed; no per-VM settings are available to apply.'
    Write-Host "Update task completed: configure-unlocker-settings"
    return
}

Write-Host "Existing IObit Unlocker installation is present; its task-local settings step is complete."
Write-Host "Update task completed: configure-unlocker-settings"

