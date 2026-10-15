[CmdletBinding()]
param([string]$RepoRoot = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = 'Stop'
$resolvedRepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$catalogRoot = Join-Path $resolvedRepoRoot 'packages/builtin/windows'
$packages = @(Get-ChildItem -LiteralPath $catalogRoot -Directory | Sort-Object Name)

function Assert-PackageLifecycle {
    param([bool]$Condition,[string]$Message)
    if (-not $Condition) { throw $Message }
}

Assert-PackageLifecycle -Condition ($packages.Count -eq 36) -Message ("Expected 36 Windows builtin packages; found {0}." -f $packages.Count)
foreach ($directory in @($packages)) {
    $manifestPath = Join-Path $directory.FullName 'package.json'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    Assert-PackageLifecycle -Condition ([string]$manifest.id -ceq [string]$directory.Name) -Message ("Package id mismatch: {0}" -f $directory.Name)
    Assert-PackageLifecycle -Condition (([string]$manifest.installScript) -ceq 'install.ps1') -Message ("Package '{0}' does not use its Windows installer." -f $directory.Name)
    Assert-PackageLifecycle -Condition ((Test-Path -LiteralPath (Join-Path $directory.FullName 'install.ps1') -PathType Leaf)) -Message ("Package '{0}' has no install.ps1." -f $directory.Name)
    Assert-PackageLifecycle -Condition (([string]$manifest.statusScript) -ceq 'status.ps1') -Message ("Package '{0}' must declare status.ps1." -f $directory.Name)
    Assert-PackageLifecycle -Condition (([string]$manifest.updateScript) -ceq 'update.ps1') -Message ("Package '{0}' must declare update.ps1." -f $directory.Name)
    Assert-PackageLifecycle -Condition (([string]$manifest.uninstallScript) -ceq 'uninstall.ps1') -Message ("Package '{0}' must declare uninstall.ps1." -f $directory.Name)
    Assert-PackageLifecycle -Condition ([string]$manifest.updateStrategy -in @('winget','choco','npm','choco-self','installer')) -Message ("Package '{0}' has an invalid update strategy." -f $directory.Name)
    foreach ($operation in @('status','update','uninstall','repair')) {
        $scriptPath = Join-Path $directory.FullName ("{0}.ps1" -f $operation)
        Assert-PackageLifecycle -Condition (Test-Path -LiteralPath $scriptPath -PathType Leaf) -Message ("Package '{0}' has no {1}.ps1." -f $directory.Name,$operation)
        $scriptText = [string](Get-Content -LiteralPath $scriptPath -Raw)
        Assert-PackageLifecycle -Condition ($scriptText.Contains('CLAGNOS_PACKAGE_SPEC_B64')) -Message ("Package '{0}' {1}.ps1 is missing its package specification input." -f $directory.Name,$operation)
        Assert-PackageLifecycle -Condition ($scriptText -match ("-Action {0}\b" -f $operation)) -Message ("Package '{0}' {1}.ps1 dispatches the wrong lifecycle action." -f $directory.Name,$operation)
        Assert-PackageLifecycle -Condition ($scriptText.Contains('clagnos-package-operations.psm1')) -Message ("Package '{0}' {1}.ps1 must use the shared verified operation helper." -f $directory.Name,$operation)
    }
}

$runtimeText = [string](Get-Content -LiteralPath (Join-Path $resolvedRepoRoot 'modules/commands/package/runtime.ps1') -Raw)
$winrmText = [string](Get-Content -LiteralPath (Join-Path $resolvedRepoRoot 'modules/core/tasks/clagnos-winrm-task-runner.ps1') -Raw)
$appStatePluginText = [string](Get-Content -LiteralPath (Join-Path $resolvedRepoRoot 'modules/core/tasks/clagnos-app-state-plugin.ps1') -Raw)
$operationModuleText = [string](Get-Content -LiteralPath (Join-Path $resolvedRepoRoot 'modules/commands/package/clagnos-package-operations.psm1') -Raw)
$uiText = [string](Get-Content -LiteralPath (Join-Path $resolvedRepoRoot 'scripts/clagnos-cli.ps1') -Raw)
$contractText = [string](Get-Content -LiteralPath (Join-Path $resolvedRepoRoot 'modules/commands/package/contract.ps1') -Raw)
$envText = [string](Get-Content -LiteralPath (Join-Path $resolvedRepoRoot '.env.example') -Raw)
$benchmarkText = [string](Get-Content -LiteralPath (Join-Path $resolvedRepoRoot 'tools/benchmark-package-transports.ps1') -Raw)

$null = . (Join-Path $resolvedRepoRoot 'clagnos.ps1')
$allWindowsPackages = @(
    @(Get-ClagnosPackageCatalog -Platform windows -Catalog builtin) +
    @(Get-ClagnosPackageCatalog -Platform windows -Catalog custom)
)
$orderedPackageIds = @((Get-ClagnosPackageDependencyOrder -Packages $allWindowsPackages) | ForEach-Object { [string]$_.Id })
foreach ($dependencyPair in @(
    @('windows-subsystem-linux','docker-desktop'),
    @('nodejs','github-copilot-cli'),
    @('nodejs','google-gemini-cli'),
    @('nodejs','openai-codex-cli')
)) {
    $dependencyIndex = [array]::IndexOf([object[]]$orderedPackageIds,[string]$dependencyPair[0])
    $dependentIndex = [array]::IndexOf([object[]]$orderedPackageIds,[string]$dependencyPair[1])
    Assert-PackageLifecycle -Condition ($dependencyIndex -ge 0 -and $dependentIndex -gt $dependencyIndex) -Message ("Package setup must order '{0}' before '{1}'." -f [string]$dependencyPair[0],[string]$dependencyPair[1])
}
$jawsPackage = @($allWindowsPackages | Where-Object { [string]$_.Id -eq 'jaws' })[0]
$generatedRepairScript = New-ClagnosPackageLifecycleScript -Action repair -Package $jawsPackage
$repairTokens = $null
$repairParseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseInput([string]$generatedRepairScript,[ref]$repairTokens,[ref]$repairParseErrors)
Assert-PackageLifecycle -Condition (@($repairParseErrors).Count -eq 0) -Message 'Generated app-state-backed package repair wrappers must parse before they can run.'

Assert-PackageLifecycle -Condition ($runtimeText.Contains("'install','repair','update','uninstall'")) -Message 'Package runtime must route install, repair, update, and uninstall as separate actions.'
Assert-PackageLifecycle -Condition ($runtimeText.Contains('already installed') -and $runtimeText.Contains('update was not run')) -Message 'Package install/update must not collapse into one operation.'
Assert-PackageLifecycle -Condition ($runtimeText.Contains('New-ClagnosPackageRepairWithAppStateBackupScript') -and $runtimeText.Contains('package-repair-backups') -and $runtimeText.Contains('VerifyMismatchCount')) -Message 'Same-version package repair must snapshot app-state, restore and verify it, and retain an emergency backup only after a failed restore.'
Assert-PackageLifecycle -Condition ($operationModuleText.Contains('--version ([string]$record.Version)') -and $operationModuleText.Contains('same-version repair')) -Message 'Package repair must pin the detected version and refuse a vendor upgrade.'
Assert-PackageLifecycle -Condition ($winrmText.Contains('Add-ClagnosPackageTrustedHost') -and $winrmText.Contains('Invoke-Command') -and $winrmText.Contains('Copy-Item')) -Message 'The WinRM task runner must copy assets and execute guest scripts.'
Assert-PackageLifecycle -Condition ($appStatePluginText.Contains('$Transport -eq ''ssh'' -and (') -and $appStatePluginText.Contains('$Transport -eq ''winrm''')) -Message 'Windows app-state replay must not require SSH credentials when a WinRM session is supplied.'
Assert-PackageLifecycle -Condition ($winrmText.Contains("Get-ClagnosPackageTransport") -or $runtimeText.Contains("Get-ClagnosPackageTransport")) -Message 'Package transport selection must be implemented.'
Assert-PackageLifecycle -Condition ($operationModuleText.Contains('CLAGNOS_PACKAGE_RESULT:') -and $operationModuleText.Contains('Uninstall did not verify')) -Message 'Package scripts must emit structured results and verify uninstall.'
Assert-PackageLifecycle -Condition ($operationModuleText.Contains('jfw.exe') -and $operationModuleText.Contains('JAWS update file copied and verified')) -Message 'JAWS update must close the application, apply update-files, and verify the copied payload.'
Assert-PackageLifecycle -Condition ($operationModuleText.Contains('list --upgrade-available') -and $operationModuleText.Contains('already matches the app-state payload')) -Message 'JAWS update must avoid unnecessary vendor upgrades and file writes when the package is already current.'
$chocolateyInstallerText = [string](Get-Content -LiteralPath (Join-Path $catalogRoot 'chocolatey/install.ps1') -Raw)
Assert-PackageLifecycle -Condition ($chocolateyInstallerText.Contains('preserve existing Chocolatey package files') -and $chocolateyInstallerText.Contains('Merge-ClagnosPreservedChocolateyFiles')) -Message 'Chocolatey bootstrap must preserve unrelated package files when reinstalling its CLI.'
Assert-PackageLifecycle -Condition ($uiText.Contains("'v' { 'update' }") -and $uiText.Contains('v: update')) -Message 'The TUI must expose a separate package update action.'
Assert-PackageLifecycle -Condition ($uiText.Contains('p: setup all program packages') -and $uiText.Contains('m: manage program packages') -and $runtimeText.Contains('Invoke-ClagnosPackageSetupPlan')) -Message 'The VC UI must expose the reviewed setup-all and separate package management paths.'
Assert-PackageLifecycle -Condition ($contractText.Contains("'update'")) -Message 'The package CLI contract must accept update.'
Assert-PackageLifecycle -Condition ($envText -match '(?m)^PACKAGE_TRANSPORT=ssh\s*$') -Message '.env.example must document the default Windows package transport.'
Assert-PackageLifecycle -Condition ($benchmarkText.Contains("@('ssh','winrm')") -and $benchmarkText.Contains("'PACKAGE_TRANSPORT=' + $Value") -and $benchmarkText.Contains('BENCHMARK {0}')) -Message 'The live read-only package transport benchmark must compare SSH and WinRM and report both results.'

$jawsManifest = Get-Content -LiteralPath (Join-Path $catalogRoot 'jaws/package.json') -Raw | ConvertFrom-Json
Assert-PackageLifecycle -Condition ([string]$jawsManifest.appStateKey -eq '133-install-jaws-application') -Message 'The existing JAWS app-state identity must remain compatible.'
Assert-PackageLifecycle -Condition ([string]$jawsManifest.startupPolicy.logonScreen -eq 'installer-managed' -and @($jawsManifest.startupPolicy.afterLogonRoles).Count -eq 2) -Message 'JAWS startup behavior must distinguish installer-managed logon-screen support and both managed post-logon roles.'
$ollamaManifest = Get-Content -LiteralPath (Join-Path $catalogRoot 'ollama/package.json') -Raw | ConvertFrom-Json
$dockerManifest = Get-Content -LiteralPath (Join-Path $catalogRoot 'docker-desktop/package.json') -Raw | ConvertFrom-Json
Assert-PackageLifecycle -Condition (@($ollamaManifest.startupPolicy.roles).Count -eq 2 -and [string]$ollamaManifest.startupPolicy.launchTarget -eq 'ollama app.exe') -Message 'Ollama must define portable manager/assistant startup shortcuts.'
Assert-PackageLifecycle -Condition (@($dockerManifest.startupPolicy.roles).Count -eq 2 -and [string]$dockerManifest.startupPolicy.launchArgument -eq '--minimized') -Message 'Docker Desktop must define its machine-wide minimized startup policy.'
$ollamaInstaller = [string](Get-Content -LiteralPath (Join-Path $catalogRoot 'ollama/install.ps1') -Raw)
$dockerInstaller = [string](Get-Content -LiteralPath (Join-Path $catalogRoot 'docker-desktop/install.ps1') -Raw)
Assert-PackageLifecycle -Condition ($ollamaInstaller.Contains('Ensure-OllamaStartupShortcuts') -and $ollamaInstaller.Contains('__ASSISTANT_USER__')) -Message 'Ollama installation must create and verify manager/assistant startup shortcuts.'
Assert-PackageLifecycle -Condition ($dockerInstaller.Contains("Join-Path `$env:ProgramData 'Microsoft\Windows\Start Menu\Programs\StartUp\Docker Desktop.lnk'")) -Message 'Docker startup must use the target machine ProgramData root.'
$jawsAppState = Join-Path $catalogRoot 'jaws/app-state/app-state.zip'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$jawsArchive = [IO.Compression.ZipFile]::OpenRead($jawsAppState)
try {
    $updateFiles = @($jawsArchive.Entries | Where-Object { ([string]$_.FullName).StartsWith('payload/update-files/',[StringComparison]::OrdinalIgnoreCase) -and -not ([string]$_.FullName).EndsWith('/') })
    Assert-PackageLifecycle -Condition ($updateFiles.Count -eq 3) -Message ("JAWS app-state update-files payload must remain complete; found {0} files." -f $updateFiles.Count)
}
finally { $jawsArchive.Dispose() }

Write-Host ("Package lifecycle contract passed for {0} Windows builtin packages." -f $packages.Count) -ForegroundColor Green
