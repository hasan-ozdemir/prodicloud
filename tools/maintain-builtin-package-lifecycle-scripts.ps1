[CmdletBinding()]
param([switch]$Apply)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$catalogRoot = Join-Path $repoRoot 'vm-packages/builtin/windows'
$statusTemplate = @'
$ErrorActionPreference = 'Stop'
Import-Module 'C:\Windows\Temp\clagnos-package-operations.psm1' -Force -DisableNameChecking
Invoke-ClagnosPackageLifecycle -Action status -PackageSpecBase64 '__CLAGNOS_PACKAGE_SPEC_B64__'
'@
$uninstallTemplate = @'
$ErrorActionPreference = 'Stop'
Import-Module 'C:\Windows\Temp\clagnos-package-operations.psm1' -Force -DisableNameChecking
Invoke-ClagnosPackageLifecycle -Action uninstall -PackageSpecBase64 '__CLAGNOS_PACKAGE_SPEC_B64__'
'@
$updateTemplate = @'
$ErrorActionPreference = 'Stop'
Import-Module 'C:\Windows\Temp\clagnos-package-operations.psm1' -Force -DisableNameChecking
Invoke-ClagnosPackageLifecycle -Action update -PackageSpecBase64 '__CLAGNOS_PACKAGE_SPEC_B64__' -InstallScriptBase64 '__CLAGNOS_INSTALL_SCRIPT_B64__'
'@
$repairTemplate = @'
$ErrorActionPreference = 'Stop'
Import-Module 'C:\Windows\Temp\clagnos-package-operations.psm1' -Force -DisableNameChecking
Invoke-ClagnosPackageLifecycle -Action repair -PackageSpecBase64 '__CLAGNOS_PACKAGE_SPEC_B64__' -InstallScriptBase64 '__CLAGNOS_INSTALL_SCRIPT_B64__'
'@

function Get-UpdateStrategy {
    param([string]$StatusKind)
    switch ($StatusKind) {
        'winget' { return 'winget' }
        'choco' { return 'choco' }
        'npm' { return 'npm' }
        'choco-self' { return 'choco-self' }
        default { return 'installer' }
    }
}

$planned = @()
foreach ($directory in @(Get-ChildItem -LiteralPath $catalogRoot -Directory | Sort-Object Name)) {
    $manifestPath = Join-Path $directory.FullName 'package.json'
    $manifestRaw = [string](Get-Content -LiteralPath $manifestPath -Raw)
    $manifest = ConvertFrom-Json -InputObject $manifestRaw
    if ([string]$manifest.id -ne [string]$directory.Name) { throw ("Package folder/manifest mismatch: {0}" -f $directory.Name) }
    $scriptMap = [ordered]@{
        statusScript = 'status.ps1'
        updateScript = 'update.ps1'
        uninstallScript = 'uninstall.ps1'
        repairScript = 'repair.ps1'
    }
    foreach ($key in $scriptMap.Keys) {
        $expected = [string]$scriptMap[$key]
        $prop = $manifest.PSObject.Properties[[string]$key]
        if ($null -ne $prop -and -not [string]::Equals([string]$prop.Value,$expected,[StringComparison]::Ordinal)) { throw ("Unexpected {0} for {1}; review it manually before regenerating." -f $key,[string]$manifest.id) }
    }
    $manifestInsertion = '  "statusScript": "status.ps1",' + "`n" + '  "updateScript": "update.ps1",' + "`n" + '  "uninstallScript": "uninstall.ps1",' + "`n" + '  "repairScript": "repair.ps1",' + "`n" + '  "updateStrategy": "' + (Get-UpdateStrategy -StatusKind ([string]$manifest.statusCheck.kind)) + '",'
    if ($manifestRaw -notmatch '"statusScript"\s*:') {
        if ($manifestRaw -notmatch '(?m)^\s*"installScript"\s*:\s*"[^"]+"\s*,\s*$') { throw ("Could not find installScript insertion point in {0}" -f $manifestPath) }
        $manifestRaw = [regex]::Replace($manifestRaw,'(?m)^(\s*"installScript"\s*:\s*"[^"]+"\s*,\s*)$',('$1' + "`n" + $manifestInsertion),1)
    }
    elseif ($manifestRaw -notmatch '"repairScript"\s*:') {
        if ($manifestRaw -notmatch '(?m)^\s*"uninstallScript"\s*:\s*"[^"]+"\s*,\s*$') { throw ("Could not find uninstallScript insertion point in {0}" -f $manifestPath) }
        $manifestRaw = [regex]::Replace($manifestRaw,'(?m)^(\s*"uninstallScript"\s*:\s*"[^"]+"\s*,\s*)$',('$1' + "`n" + '  "repairScript": "repair.ps1",'),1)
    }
    elseif ($manifestRaw -notmatch '"updateStrategy"\s*:') {
        $insertionKey = if ($manifestRaw -match '"repairScript"\s*:') { 'repairScript' } else { 'uninstallScript' }
        $manifestRaw = [regex]::Replace($manifestRaw,('(?m)^(\s*"' + $insertionKey + '"\s*:\s*"[^"]+"\s*,\s*)$'),('$1' + "`n" + '  "updateStrategy": "' + (Get-UpdateStrategy -StatusKind ([string]$manifest.statusCheck.kind)) + '",'),1)
    }

    foreach ($spec in @(
        @{ Name = 'status.ps1'; Text = $statusTemplate },
        @{ Name = 'update.ps1'; Text = $updateTemplate },
        @{ Name = 'uninstall.ps1'; Text = $uninstallTemplate },
        @{ Name = 'repair.ps1'; Text = $repairTemplate }
    )) {
        $path = Join-Path $directory.FullName ([string]$spec.Name)
        $oldText = if (Test-Path -LiteralPath $path -PathType Leaf) { [string](Get-Content -LiteralPath $path -Raw) } else { '' }
        if ($oldText -cne [string]$spec.Text) { $planned += [pscustomobject]@{ Path = $path; Text = [string]$spec.Text } }
    }
    if ($manifestRaw -cne [string]$((Get-Content -LiteralPath $manifestPath -Raw))) { $planned += [pscustomobject]@{ Path = $manifestPath; Text = [string]$manifestRaw.TrimEnd() + [Environment]::NewLine } }
}

if (-not $Apply) {
    Write-Host ("Planned Windows builtin package lifecycle updates: {0} files. Re-run with -Apply to write them." -f $planned.Count)
    foreach ($change in @($planned)) { Write-Host ("- {0}" -f ([string]$change.Path).Substring($repoRoot.Length).TrimStart([char[]]@('\','/'))) }
    return
}

foreach ($change in @($planned)) {
    [System.IO.File]::WriteAllText([string]$change.Path,[string]$change.Text,[System.Text.UTF8Encoding]::new($false))
}
Write-Host ("Updated {0} Windows builtin package lifecycle files." -f $planned.Count) -ForegroundColor Green
