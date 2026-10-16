[CmdletBinding()]
param([string]$RepoRoot = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = 'Stop'
$resolvedRepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$catalogRoot = Join-Path $resolvedRepoRoot 'vm-packages/builtin/windows'
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
$entryText = [string](Get-Content -LiteralPath (Join-Path $resolvedRepoRoot 'modules/commands/package/entry.ps1') -Raw)
$packageContractText = [string](Get-Content -LiteralPath (Join-Path $resolvedRepoRoot 'modules/commands/package/contract.ps1') -Raw)
$helpText = [string](Get-Content -LiteralPath (Join-Path $resolvedRepoRoot 'modules/core/cli/clagnos-help.ps1') -Raw)
$winrmText = [string](Get-Content -LiteralPath (Join-Path $resolvedRepoRoot 'modules/core/tasks/clagnos-winrm-task-runner.ps1') -Raw)
$appStatePluginText = [string](Get-Content -LiteralPath (Join-Path $resolvedRepoRoot 'modules/core/tasks/clagnos-app-state-plugin.ps1') -Raw)
$operationModuleText = [string](Get-Content -LiteralPath (Join-Path $resolvedRepoRoot 'modules/commands/package/clagnos-package-operations.psm1') -Raw)
$uiText = [string](Get-Content -LiteralPath (Join-Path $resolvedRepoRoot 'scripts/clagnos-cli.ps1') -Raw)
$contractText = [string](Get-Content -LiteralPath (Join-Path $resolvedRepoRoot 'modules/commands/package/contract.ps1') -Raw)
$envText = [string](Get-Content -LiteralPath (Join-Path $resolvedRepoRoot 'clagnos.env.example') -Raw)
$benchmarkText = [string](Get-Content -LiteralPath (Join-Path $resolvedRepoRoot 'tools/benchmark-package-transports.ps1') -Raw)
$setupVc2Text = [string](Get-Content -LiteralPath (Join-Path $resolvedRepoRoot 'setup-vc2.ps1') -Raw)
$setupVc2CmdText = [string](Get-Content -LiteralPath (Join-Path $resolvedRepoRoot 'setup-vc2.cmd') -Raw)

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
Assert-PackageLifecycle -Condition ($operationModuleText.Contains('function Resolve-ClagnosWingetExecutable') -and $operationModuleText.Contains("Get-AppxPackage -AllUsers -Name 'Microsoft.DesktopAppInstaller'") -and $operationModuleText.Contains('Initialize-ClagnosWingetCommandPath')) -Message 'Winget package detection and installers must resolve the App Installer payload even when the per-user WindowsApps alias is absent.'
Assert-PackageLifecycle -Condition ($runtimeText.Contains('`$npmModulesRoot = Join-Path') -and $operationModuleText.Contains('$npmModulesRoot = Join-Path') -and -not $runtimeText.Contains('list --global --depth=0 --json')) -Message 'Npm package status must inspect the managed global package directory without failing the WinRM task when npm has an empty global inventory.'
Assert-PackageLifecycle -Condition ($winrmText.Contains('Add-ClagnosPackageTrustedHost') -and $winrmText.Contains('Invoke-Command') -and $winrmText.Contains('Copy-Item')) -Message 'The WinRM task runner must copy assets and execute guest scripts.'
Assert-PackageLifecycle -Condition ($winrmText.Contains('Stop-Job -Job $job -ErrorAction') -and -not $winrmText.Contains('Stop-Job -Job $job -Force')) -Message 'WinRM timeout cleanup must use Stop-Job parameters supported by Windows PowerShell 5.1.'
Assert-PackageLifecycle -Condition ($appStatePluginText.Contains('$Transport -eq ''ssh'' -and (') -and $appStatePluginText.Contains('$Transport -eq ''winrm''')) -Message 'Windows app-state replay must not require SSH credentials when a WinRM session is supplied.'
Assert-PackageLifecycle -Condition ($winrmText.Contains("Get-ClagnosPackageTransport") -or $runtimeText.Contains("Get-ClagnosPackageTransport")) -Message 'Package transport selection must be implemented.'
Assert-PackageLifecycle -Condition ($operationModuleText.Contains('CLAGNOS_PACKAGE_RESULT:') -and $operationModuleText.Contains('Uninstall did not verify') -and $operationModuleText.Contains('Export-ModuleMember -Function Invoke-ClagnosPackageLifecycle,Set-ClagnosJawsPostLogonStartup,Test-ClagnosJawsPostLogonStartup,Install-ClagnosJawsAppStateUpdateFiles,Set-ClagnosPackageStartupState,Test-ClagnosPackageStartupState')) -Message 'Package scripts must emit structured results, verify uninstall, and export startup/app-state helpers used by guest lifecycle scripts.'
Assert-PackageLifecycle -Condition ($operationModuleText.Contains('jfw.exe') -and $operationModuleText.Contains('JAWS update file copied and verified')) -Message 'JAWS update must close the application, apply update-files, and verify the copied payload.'
Assert-PackageLifecycle -Condition ($operationModuleText.Contains('list --upgrade-available') -and $operationModuleText.Contains('already matches the app-state payload')) -Message 'JAWS update must avoid unnecessary vendor upgrades and file writes when the package is already current.'
$chocolateyInstallerText = [string](Get-Content -LiteralPath (Join-Path $catalogRoot 'chocolatey/install.ps1') -Raw)
Assert-PackageLifecycle -Condition ($chocolateyInstallerText.Contains('preserve existing Chocolatey package files') -and $chocolateyInstallerText.Contains('Merge-ClagnosPreservedChocolateyFiles')) -Message 'Chocolatey bootstrap must preserve unrelated package files when reinstalling its CLI.'
Assert-PackageLifecycle -Condition ($uiText.Contains("'v' { 'update' }") -and $uiText.Contains('v: update')) -Message 'The TUI must expose a separate package update action.'
Assert-PackageLifecycle -Condition ($uiText.Contains('p: setup all program packages') -and $uiText.Contains('m: manage program packages') -and $runtimeText.Contains('Invoke-ClagnosPackageSetupPlan')) -Message 'The VC UI must expose the reviewed setup-all and separate package management paths.'
Assert-PackageLifecycle -Condition ($entryText.Contains("'setup-all'") -and $entryText.Contains("'all'") -and $packageContractText.Contains("'setup-all'") -and $packageContractText.Contains("@('all')") -and $runtimeText.Contains('function Invoke-ClagnosPackageSetupAll') -and $runtimeText.Contains("'SETUP ALL'") -and $helpText.Contains('--catalog all')) -Message 'The direct setup-all package action must review both catalogs and require explicit confirmation or --yes.'
Assert-PackageLifecycle -Condition ($runtimeText.Contains('$dependencies = @(') -and $runtimeText.Contains('Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }') -and $runtimeText.Contains('$blockedDependency = @($dependencies | Where-Object') -and $runtimeText.Contains('recheck-after-dependencies') -and $runtimeText.Contains('Get-ClagnosPackageStatusSnapshot -Packages @($package)')) -Message 'Package setup-all must ignore empty dependency placeholders and recheck dependency-gated packages after dependencies become available.'
Assert-PackageLifecycle -Condition ($runtimeText.Contains('startupPolicy = $_.StartupPolicy') -and $operationModuleText.Contains('Test-ClagnosPackageDockerStartupForUser') -and $operationModuleText.Contains('userRunEntryName')) -Message 'Windows package status batches must include startup-policy metadata and validate Docker Desktop against manager/assistant Run or StartupFolder state.'
Assert-PackageLifecycle -Condition ($setupVc2Text.Contains("'germanywestcentral'") -and $setupVc2Text.Contains("'Standard_B2s_v2'") -and $setupVc2Text.Contains("'160'") -and $setupVc2Text.Contains("VM_ENABLE_NESTED_VIRTUALIZATION = 'false'") -and $setupVc2Text.Contains('function Get-SetupPackageStatus') -and $setupVc2Text.Contains('function Stage-SetupAnyDeskInstaller') -and $setupVc2Text.Contains('Get-SetupAuthenticodeInfo -Path $localInstaller') -and $setupVc2Text.Contains('Get-SetupSha256Hash -Path $localInstaller') -and $setupVc2Text.Contains('[System.Security.Cryptography.SHA256]::Create()') -and $setupVc2Text.Contains('Get-AuthenticodeSignature -LiteralPath ''$escapedPath''') -and $setupVc2Text.Contains('Add-ClagnosPackageTrustedHost -HostName $connectionHost') -and $setupVc2Text.Contains('New-ClagnosPowerShellRemotingSession -Runtime $connectionRuntime') -and -not $setupVc2Text.Contains('Initialize-ClagnosConnectionCommandContext -Options $connectionOptions') -and $setupVc2Text.Contains("'package','--action','setup-all'") -and $setupVc2Text.Contains("'connect','--powershell'") -and $setupVc2Text.Contains('Restore-SetupOriginalEnv')) -Message 'The repeatable VC2 setup runner must use the requested target, handle the unsupported nested-virtualization SKU, stage and hash-verify the signed AnyDesk installer over WinRM, check remote transports, and restore local configuration.'
Assert-PackageLifecycle -Condition ($setupVc2Text.Contains('function Invoke-SetupCgCaptured') -and $setupVc2Text.Contains('SetupPackageWarnings') -and $setupVc2Text.Contains('continuing with final update, connection, and Azure health checks')) -Message 'The setup runner must finish final health and transport checks even when a package installer reports a verified partial failure.'
Assert-PackageLifecycle -Condition ($setupVc2Text.Contains('[switch]$ResumeAtPackageStage') -and $setupVc2Text.Contains('requires an existing Clagnos-managed VM named vc2') -and $setupVc2Text.Contains('Start-Transcript -LiteralPath $script:SetupTranscriptPath') -and $setupVc2Text.Contains('if (-not (Test-Path -LiteralPath $localInstaller -PathType Leaf))') -and $setupVc2Text.Contains('continuing setup-all so independent packages can still be prepared')) -Message 'The VC2 setup runner must support observable package-stage resumption on an existing target and continue independent package setup when AnyDesk staging fails.'
Assert-PackageLifecycle -Condition ($setupVc2Text.Contains('$instance.instanceView.statuses') -and $setupVc2Text.Contains("'do','--vm-action=start'") -and $setupVc2Text.Contains("'do','--vm-action=status'") -and -not $setupVc2Text.Contains("'do','--auto','--windows'") -and $setupVc2Text.Contains('refusing to issue a lifecycle action without a verified current state')) -Message 'The VC2 runner must read power state from Azure instanceView and use supported start/status commands only after known power states.'
Assert-PackageLifecycle -Condition ($setupVc2Text.Contains("'show','--group'") -and -not $setupVc2Text.Contains("'show','--windows'")) -Message 'The VC2 runner must call show using only options accepted by its public command contract.'
Assert-PackageLifecycle -Condition ($setupVc2Text.Contains('$output = New-Object ''System.Collections.Generic.List[string]''') -and $setupVc2Text.IndexOf('Write-Host $safeLine',$setupVc2Text.IndexOf('function Invoke-SetupCgCaptured',[System.StringComparison]::Ordinal),[System.StringComparison]::Ordinal) -lt $setupVc2Text.IndexOf('$exitCode = $LASTEXITCODE',$setupVc2Text.IndexOf('function Invoke-SetupCgCaptured',[System.StringComparison]::Ordinal),[System.StringComparison]::Ordinal)) -Message 'The setup runner must stream redacted setup-all progress as it arrives instead of buffering the full package pass.'
$dockerManifest = Get-Content -LiteralPath (Join-Path $resolvedRepoRoot 'vm-packages/builtin/windows/docker-desktop/package.json') -Raw | ConvertFrom-Json
Assert-PackageLifecycle -Condition ([string]$dockerManifest.repairStrategy -eq 'startup' -and $operationModuleText.Contains("'startup' {") -and $operationModuleText.Contains('Set-ClagnosPackageStartupState -Spec $spec | Out-String')) -Message 'Docker Desktop startup drift must be repaired by reconciling its managed startup shortcut without reinstalling the 600 MB vendor package.'
$setupInitIndex = $setupVc2Text.IndexOf("'initialize','--auto'",[System.StringComparison]::Ordinal)
$setupChocolateyIndex = $setupVc2Text.IndexOf("'package','--action','install','--catalog','builtin','--package','chocolatey'",[System.StringComparison]::Ordinal)
$setupPrerequisiteIndex = $setupVc2Text.IndexOf("'package','--action','install','--catalog','builtin','--package','sysinternals'",[System.StringComparison]::Ordinal)
$setupFirstUpdateIndex = $setupVc2Text.IndexOf("'update','--step','vm-update'",[System.StringComparison]::Ordinal)
$setupAllIndex = $setupVc2Text.IndexOf("'package','--action','setup-all'",[System.StringComparison]::Ordinal)
$setupFinalUpdateIndex = $setupVc2Text.IndexOf("'update','--step','vm-update'",$setupFirstUpdateIndex + 1,[System.StringComparison]::Ordinal)
Assert-PackageLifecycle -Condition ($setupInitIndex -ge 0 -and $setupChocolateyIndex -gt $setupInitIndex -and $setupPrerequisiteIndex -gt $setupChocolateyIndex -and $setupFirstUpdateIndex -gt $setupPrerequisiteIndex -and $setupAllIndex -gt $setupFirstUpdateIndex -and $setupFinalUpdateIndex -gt $setupAllIndex) -Message 'The VC2 runner must sequence init, Chocolatey, Sysinternals, vm-update, package setup-all, and a final idempotent vm-update pass.'
Assert-PackageLifecycle -Condition ($setupVc2CmdText.Contains('setup-vc2.ps1') -and $setupVc2CmdText.Contains('%ERRORLEVEL%')) -Message 'The setup-vc2.cmd launcher must delegate to the PowerShell runner and propagate its exit code.'
$slowStoreTimeouts = @{}
foreach ($packageId in @('be-my-eyes','whatsapp','codex-app','icloud','windows-subsystem-linux')) {
    $packageManifest = Get-Content -LiteralPath (Join-Path $resolvedRepoRoot ("vm-packages/builtin/windows/{0}/package.json" -f $packageId)) -Raw | ConvertFrom-Json
    $slowStoreTimeouts[$packageId] = [int]$packageManifest.timeout
}
Assert-PackageLifecycle -Condition ($slowStoreTimeouts['be-my-eyes'] -ge 600 -and $slowStoreTimeouts['whatsapp'] -ge 600 -and $slowStoreTimeouts['codex-app'] -ge 600 -and $slowStoreTimeouts['icloud'] -ge 600 -and $slowStoreTimeouts['windows-subsystem-linux'] -ge 600) -Message 'WinRM Store-backed and WSL bootstrap package jobs must receive a bounded timeout that covers first-install work.'
Assert-PackageLifecycle -Condition ($contractText.Contains("'update'")) -Message 'The package CLI contract must accept update.'
Assert-PackageLifecycle -Condition ($envText -match '(?m)^DEFAULT_PACKAGE_TRANSPORT=ssh\s*$') -Message 'clagnos.env.example must document the default Windows package transport.'
Assert-PackageLifecycle -Condition ($benchmarkText.Contains("@('ssh','winrm')") -and $benchmarkText.Contains("'PACKAGE_TRANSPORT=' + $Value") -and $benchmarkText.Contains('BENCHMARK {0}')) -Message 'The live read-only package transport benchmark must compare SSH and WinRM and report both results.'

$jawsManifest = Get-Content -LiteralPath (Join-Path $catalogRoot 'jaws/package.json') -Raw | ConvertFrom-Json
$jawsInstallerText = [string](Get-Content -LiteralPath (Join-Path $catalogRoot 'jaws/install.ps1') -Raw)
Assert-PackageLifecycle -Condition ($jawsInstallerText.Contains('Install-JawsUpdateFilesFromAppState') -and $jawsInstallerText.Contains('Set-JawsPostLogonStartup') -and -not $jawsInstallerText.Contains("Import-Module 'C:\Windows\Temp\clagnos-package-operations.psm1' -Force")) -Message 'The JAWS installer must reuse the active package operation module instead of force-reimporting and unloading its caller while install verification is pending.'
Assert-PackageLifecycle -Condition ([string]$jawsManifest.appStateKey -eq '133-install-jaws-application') -Message 'The existing JAWS app-state identity must remain compatible.'
Assert-PackageLifecycle -Condition ([string]$jawsManifest.startupPolicy.logonScreen -eq 'installer-managed' -and @($jawsManifest.startupPolicy.afterLogonRoles).Count -eq 2) -Message 'JAWS startup behavior must distinguish installer-managed logon-screen support and both managed post-logon roles.'
$ollamaManifest = Get-Content -LiteralPath (Join-Path $catalogRoot 'ollama/package.json') -Raw | ConvertFrom-Json
$dockerManifest = Get-Content -LiteralPath (Join-Path $catalogRoot 'docker-desktop/package.json') -Raw | ConvertFrom-Json
$anydeskManifest = Get-Content -LiteralPath (Join-Path $catalogRoot 'anydesk/package.json') -Raw | ConvertFrom-Json
$anydeskInstallerText = [string](Get-Content -LiteralPath (Join-Path $catalogRoot 'anydesk/install.ps1') -Raw)
Assert-PackageLifecycle -Condition (@($ollamaManifest.startupPolicy.roles).Count -eq 2 -and [string]$ollamaManifest.startupPolicy.launchTarget -eq 'ollama app.exe') -Message 'Ollama must define portable manager/assistant startup shortcuts.'
Assert-PackageLifecycle -Condition ([string]$anydeskManifest.statusCheck.kind -eq 'command' -and [string]$anydeskManifest.uninstall.kind -eq 'anydesk' -and $anydeskInstallerText.Contains('Get-AuthenticodeSignature') -and $anydeskInstallerText.Contains('$jsonLine = @([string]$probe.StdoutText -split') -and $anydeskInstallerText.Contains('AnyDesk Software GmbH') -and $anydeskInstallerText.Contains('--install') -and $operationModuleText.Contains("'anydesk' {")) -Message 'AnyDesk may use the official installer only after valid Authenticode verification and must retain a verified uninstall action.'
Assert-PackageLifecycle -Condition ([int]$anydeskManifest.timeout -ge 600 -and $anydeskInstallerText.Contains('WingetInstallTimeoutSeconds = 300')) -Message 'AnyDesk must allow sufficient bounded time for its first winget download and installation.'
Assert-PackageLifecycle -Condition ($anydeskInstallerText.Contains('WingetSourceUpdateTimeoutSeconds = 120') -and $anydeskInstallerText.Contains('no hash bypass was attempted') -and $anydeskInstallerText.Contains("'source','update','--disable-interactivity'")) -Message 'AnyDesk may refresh WinGet source metadata once after a hash mismatch, then require valid vendor Authenticode signing without bypassing the hash check.'
Assert-PackageLifecycle -Condition (@($dockerManifest.startupPolicy.roles).Count -eq 2 -and [string]$dockerManifest.startupPolicy.userRunEntryName -eq 'Docker Desktop' -and [string]$dockerManifest.startupPolicy.launchArgument -eq '--minimized' -and $operationModuleText.Contains('function Test-ClagnosPackageDockerStartupForUser') -and $operationModuleText.Contains('Docker Desktop startup is verified for managed users:')) -Message 'Docker Desktop startup health must match the manager/assistant Run-entry or startup-folder policy maintained by vm-update.'
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
