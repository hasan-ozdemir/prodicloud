# Package catalog, status, and managed guest install/uninstall operations.

function Get-ClagnosPackageCatalog {
    param(
        [ValidateSet('windows','linux')][string]$Platform,
        [ValidateSet('builtin','custom')][string]$Catalog,
        [string]$CatalogRoot = ''
    )

    $repoRoot = Get-ClagnosRepoRoot
    $root = if ([string]::IsNullOrWhiteSpace([string]$CatalogRoot)) {
        Join-Path $repoRoot (Join-Path 'vm-packages' (Join-Path $Catalog $Platform))
    }
    else {
        [System.IO.Path]::GetFullPath($CatalogRoot)
    }
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { return @() }
    $catalogPath = Join-Path $root 'tasks.toml'
    $catalogState = Read-ClagnosTaskCatalogState -Path $catalogPath
    $expectedExtension = if ($Platform -eq 'windows') { '.ps1' } else { '.sh' }
    $packageFolders = @(Get-ChildItem -LiteralPath $root -Directory -Force | Where-Object { -not $_.Name.StartsWith('.') -and $_.Name -ne 'backup-app-states' } | Sort-Object Name)
    $packageFolderNames = @($packageFolders | ForEach-Object { [string]$_.Name })
    foreach ($catalogPackageId in @($catalogState.Entries.Keys)) {
        if ($packageFolderNames -notcontains [string]$catalogPackageId) {
            throw ("Package catalog '{0}' lists '{1}', but its package folder is missing." -f $catalogPath, [string]$catalogPackageId)
        }
    }
    $packages = @()
    foreach ($folder in @($packageFolders)) {
        if (-not $catalogState.Entries.ContainsKey([string]$folder.Name)) {
            throw ("Package folder '{0}' is missing from tasks.toml: {1}" -f [string]$folder.Name, $catalogPath)
        }
        if ($folder.Name -notmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') {
            throw ("Package folder '{0}' must use a lower-case package id." -f [string]$folder.Name)
        }

        $manifestPath = Join-Path $folder.FullName 'package.json'
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
            throw ("Package manifest was not found: {0}" -f $manifestPath)
        }
        $manifestText = [string](Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop)
        if ([string]::IsNullOrWhiteSpace($manifestText)) { throw ("Package manifest is empty: {0}" -f $manifestPath) }
        try { $manifest = ConvertFrom-JsonCompat -InputObject $manifestText }
        catch { throw ("Package manifest parse failed for '{0}': {1}" -f $manifestPath, $_.Exception.Message) }
        if ($null -ne $manifest -and $null -ne $manifest.PSObject.Properties['enabled']) {
            throw ("Package availability belongs in tasks.toml; remove 'enabled' from {0}." -f $manifestPath)
        }

        $id = [string]$manifest.id
        if (-not [string]::Equals($id, [string]$folder.Name, [System.StringComparison]::Ordinal)) {
            throw ("Package id '{0}' must match its folder '{1}'." -f $id, [string]$folder.Name)
        }
        $displayName = [string]$manifest.displayName
        if ([string]::IsNullOrWhiteSpace($displayName)) { throw ("Package '{0}' requires displayName." -f $id) }
        $category = [string]$manifest.category
        if ([string]::IsNullOrWhiteSpace($category)) { throw ("Package '{0}' requires category." -f $id) }
        $category = $category.Trim().ToLowerInvariant()
        if ($category -notin @('application','tool','package','feature')) { throw ("Package '{0}' has unsupported category '{1}'." -f $id, $category) }

        $statusCheck = $manifest.statusCheck
        $uninstall = $manifest.uninstall
        if ($null -eq $statusCheck -or [string]::IsNullOrWhiteSpace([string]$statusCheck.kind) -or [string]::IsNullOrWhiteSpace([string]$statusCheck.value)) {
            throw ("Package '{0}' requires statusCheck.kind and statusCheck.value." -f $id)
        }
        if ($null -eq $uninstall -or [string]::IsNullOrWhiteSpace([string]$uninstall.kind) -or [string]::IsNullOrWhiteSpace([string]$uninstall.value)) {
            throw ("Package '{0}' requires uninstall.kind and uninstall.value." -f $id)
        }
        if ([string]$statusCheck.kind -notin @('command','winget','choco','npm','appx','store-state','choco-self','sysinternals','windscribe','wsl','dpkg','rpm')) {
            throw ("Package '{0}' has unsupported status check '{1}'." -f $id, [string]$statusCheck.kind)
        }
        if ([string]$statusCheck.kind -eq 'wsl' -and ($Platform -ne 'windows' -or $Catalog -ne 'builtin' -or [string]$id -ne 'windows-subsystem-linux' -or [string]$statusCheck.value -ne 'Windows Subsystem for Linux')) {
            throw 'The wsl status check is valid only for the builtin Windows Subsystem for Linux package.'
        }
        if ([string]$statusCheck.kind -eq 'windscribe' -and ($Platform -ne 'windows' -or $Catalog -ne 'builtin' -or [string]$id -ne 'windscribe' -or [string]$statusCheck.value -ne 'C:\Program Files\Windscribe\Windscribe.exe')) {
            throw 'The windscribe status check is valid only for the builtin Windows windscribe package and its fixed signed executable path.'
        }
        if ([string]$uninstall.kind -notin @('winget','choco','npm','appx','windows-feature','choco-self','anydesk','docker-desktop','google-drive','windscribe','teams','nvda','jaws','wsl','sysinternals','apt','dnf','snap')) {
            throw ("Package '{0}' has unsupported uninstall action '{1}'." -f $id, [string]$uninstall.kind)
        }
        if ([string]$uninstall.kind -eq 'jaws' -and ($Platform -ne 'windows' -or $Catalog -ne 'builtin' -or [string]$id -ne 'jaws' -or [string]$statusCheck.kind -ne 'winget' -or [string]$uninstall.value -ne 'FreedomScientific.JAWS.2025')) {
            throw 'The jaws uninstall action is valid only for the builtin Windows JAWS 2025 package and its exact WinGet identity.'
        }
        if ([string]$uninstall.kind -eq 'wsl' -and ($Platform -ne 'windows' -or $Catalog -ne 'builtin' -or [string]$id -ne 'windows-subsystem-linux' -or [string]$statusCheck.kind -ne 'wsl' -or [string]$uninstall.value -ne 'Windows Subsystem for Linux')) {
            throw 'The wsl uninstall action is valid only for the builtin Windows Subsystem for Linux MSI package.'
        }
        if ([string]$uninstall.kind -eq 'nvda' -and ($Platform -ne 'windows' -or $Catalog -ne 'builtin' -or [string]$id -ne 'nvda' -or [string]$statusCheck.kind -ne 'winget' -or [string]$uninstall.value -ne 'C:\Program Files\NVDA\uninstall.exe')) {
            throw 'The nvda uninstall action is valid only for the builtin Windows NVDA package and its fixed vendor uninstaller path.'
        }
        if ([string]$uninstall.kind -eq 'teams' -and ($Platform -ne 'windows' -or $Catalog -ne 'builtin' -or [string]$id -ne 'microsoft-teams' -or [string]$uninstall.value -ne 'MSTeams')) {
            throw 'The teams uninstall action is valid only for the builtin Windows microsoft-teams package with value MSTeams.'
        }
        if ([string]$uninstall.kind -eq 'windscribe' -and ($Platform -ne 'windows' -or $Catalog -ne 'builtin' -or [string]$id -ne 'windscribe' -or [string]$uninstall.value -ne 'C:\Program Files\Windscribe\uninstall.exe')) {
            throw 'The windscribe uninstall action is valid only for the builtin Windows windscribe package and its fixed signed vendor uninstaller path.'
        }
        if ($null -ne $uninstall.PSObject.Properties['allVersions']) {
            if ([string]$uninstall.kind -ne 'winget' -or $uninstall.allVersions -isnot [bool]) {
                throw ("Package '{0}' may set uninstall.allVersions only as a boolean with a WinGet uninstall action." -f $id)
            }
        }
        if ($null -ne $uninstall.PSObject.Properties['removeDependencies']) {
            if ([string]$uninstall.kind -ne 'choco' -or $uninstall.removeDependencies -isnot [bool]) {
                throw ("Package '{0}' may set uninstall.removeDependencies only as a boolean with a Chocolatey uninstall action." -f $id)
            }
        }
        $uninstallPolicy = $manifest.uninstallPolicy
        if ($null -ne $uninstallPolicy -and $null -ne $uninstallPolicy.PSObject.Properties['supported'] -and -not [bool]$uninstallPolicy.supported -and [string]::IsNullOrWhiteSpace([string]$uninstallPolicy.reason)) {
            throw ("Package '{0}' declares uninstall unsupported without a user-facing reason." -f $id)
        }
        if ([string]$uninstall.kind -eq 'anydesk' -and ([string]$id -ne 'anydesk' -or [string]$uninstall.value -ne 'C:\Program Files (x86)\AnyDesk\AnyDesk.exe')) {
            throw 'The anydesk uninstall action is valid only for the builtin AnyDesk package and its fixed machine installation path.'
        }
        if ([string]$uninstall.kind -eq 'google-drive' -and ($Platform -ne 'windows' -or $Catalog -ne 'builtin' -or [string]$id -ne 'google-drive' -or [string]$statusCheck.kind -ne 'winget' -or [string]$uninstall.value -ne '{6BBAE539-2232-434A-A4E5-9A33560C6283}')) {
            throw 'The google-drive uninstall action is valid only for the builtin Google Drive package and its fixed vendor product code.'
        }
        if ([string]$uninstall.kind -eq 'docker-desktop' -and ($Platform -ne 'windows' -or $Catalog -ne 'builtin' -or [string]$id -ne 'docker-desktop' -or [string]$statusCheck.kind -ne 'winget' -or [string]$uninstall.value -ne 'Docker.DockerDesktop')) {
            throw 'The docker-desktop uninstall action is valid only for the builtin Docker Desktop package and its exact WinGet identity.'
        }

        $installScript = [string]$manifest.installScript
        if ([string]::IsNullOrWhiteSpace($installScript)) { $installScript = ('install{0}' -f $expectedExtension) }
        if ([System.IO.Path]::GetFileName($installScript) -cne $installScript -or [System.IO.Path]::GetExtension($installScript) -cne $expectedExtension) {
            throw ("Package '{0}' installScript must be a {1} file directly inside its package folder." -f $id, $expectedExtension)
        }
        $installPath = Join-Path $folder.FullName $installScript
        if (-not (Test-Path -LiteralPath $installPath -PathType Leaf)) { throw ("Package installer was not found: {0}" -f $installPath) }

        $lifecycleScriptPaths = @{}
        $lifecycleScriptText = @{}
        $operationsModulePath = ''
        $repairStrategy = [string]$manifest.repairStrategy
        if ($Platform -eq 'windows') {
            if (-not [string]::IsNullOrWhiteSpace($repairStrategy) -and $repairStrategy -notin @('winget','winget-prefix','winget-vscode','google-drive-verify','wsl-msi','choco','npm','choco-self','appx','startup','installer-verify','sysinternals','windscribe','jaws')) {
                throw ("Package '{0}' has unsupported repairStrategy '{1}'" -f $id,$repairStrategy)
            }
            if ($repairStrategy -eq 'jaws' -and ($Catalog -ne 'builtin' -or $id -ne 'jaws' -or [string]$statusCheck.kind -ne 'winget' -or [string]$statusCheck.value -ne 'FreedomScientific.JAWS.2025')) {
                throw 'The jaws repair strategy is reserved for the builtin Windows JAWS 2025 package.'
            }
            if ($repairStrategy -eq 'winget-prefix' -and ($Catalog -ne 'builtin' -or $id -ne 'nvda' -or [string]$statusCheck.kind -ne 'winget')) {
                throw 'The winget-prefix repair strategy is reserved for the builtin Windows NVDA package.'
            }
            if ($repairStrategy -eq 'winget-vscode' -and ($Catalog -ne 'builtin' -or $id -ne 'visual-studio-code' -or [string]$statusCheck.kind -ne 'command' -or [string]$manifest.repairPackageId -ne 'Microsoft.VisualStudioCode')) {
                throw 'The winget-vscode repair strategy is reserved for the builtin Windows Visual Studio Code package.'
            }
            if ($repairStrategy -eq 'google-drive-verify' -and ($Catalog -ne 'builtin' -or $id -ne 'google-drive' -or [string]$statusCheck.kind -ne 'winget' -or [string]$manifest.repairPackageId -ne 'Google.GoogleDrive' -or [string]$manifest.repairProductCode -ne '{6BBAE539-2232-434A-A4E5-9A33560C6283}')) {
                throw 'The google-drive-verify repair strategy is reserved for the builtin Google Drive package and its exact provider identity.'
            }
            if ($repairStrategy -eq 'wsl-msi' -and ($Catalog -ne 'builtin' -or $id -ne 'windows-subsystem-linux' -or [string]$statusCheck.kind -ne 'wsl')) {
                throw 'The wsl-msi repair strategy is reserved for the builtin Windows Subsystem for Linux MSI package.'
            }
            foreach ($lifecycleAction in @('status','update','uninstall','repair')) {
                $manifestKey = '{0}Script' -f $lifecycleAction
                $scriptName = [string]$manifest.$manifestKey
                $hasExplicitScript = -not [string]::IsNullOrWhiteSpace($scriptName)
                if ([string]::IsNullOrWhiteSpace($scriptName)) { $scriptName = ('{0}.ps1' -f $lifecycleAction) }
                if ([System.IO.Path]::GetFileName($scriptName) -cne $scriptName -or [System.IO.Path]::GetExtension($scriptName) -cne '.ps1') {
                    throw ("Package '{0}' {1}Script must be a PowerShell file directly inside its package folder." -f $id,$lifecycleAction)
                }
                $scriptPath = Join-Path $folder.FullName $scriptName
                if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
                    if (($lifecycleAction -eq 'repair' -and -not $hasExplicitScript) -or ($Catalog -eq 'custom' -and -not $hasExplicitScript)) { continue }
                    throw ("Package '{0}' {1} script was not found: {2}" -f $id,$lifecycleAction,$scriptPath)
                }
                $lifecycleScriptPaths[$lifecycleAction] = [string]$scriptPath
                $lifecycleScriptText[$lifecycleAction] = [string](Get-Content -LiteralPath $scriptPath -Raw -ErrorAction Stop)
            }
            $updateStrategy = [string]$manifest.updateStrategy
            if ([string]::IsNullOrWhiteSpace($updateStrategy)) {
                $updateStrategy = switch ([string]$statusCheck.kind) {
                    'winget' { 'winget' }
                    'choco' { 'choco' }
                    'npm' { 'npm' }
                    'choco-self' { 'choco-self' }
                    'sysinternals' { 'sysinternals' }
                    default { 'installer' }
                }
            }
            if ($updateStrategy -notin @('winget','winget-vscode','choco','npm','choco-self','installer','sysinternals','teams-bootstrapper','anydesk','windscribe')) { throw ("Package '{0}' has unsupported updateStrategy '{1}'" -f $id,$updateStrategy) }
            $updatePackageId = [string]$manifest.updatePackageId
            if (-not [string]::IsNullOrWhiteSpace($updatePackageId) -and $updateStrategy -notin @('winget','winget-vscode')) {
                throw ("Package '{0}' may set updatePackageId only with a WinGet update strategy." -f $id)
            }
            if ([string]::IsNullOrWhiteSpace($updatePackageId) -and $updateStrategy -eq 'winget') { $updatePackageId = [string]$statusCheck.value }
            if ($updateStrategy -eq 'winget-vscode' -and ($Platform -ne 'windows' -or $Catalog -ne 'builtin' -or [string]$id -ne 'visual-studio-code' -or [string]$updatePackageId -ne 'Microsoft.VisualStudioCode')) {
                throw 'The winget-vscode update strategy is reserved for the builtin Windows Visual Studio Code package.'
            }
            if ($updateStrategy -eq 'teams-bootstrapper' -and ($Platform -ne 'windows' -or $Catalog -ne 'builtin' -or [string]$id -ne 'microsoft-teams')) {
                throw 'The teams-bootstrapper update strategy is valid only for the builtin Windows microsoft-teams package.'
            }
            if ($updateStrategy -eq 'anydesk' -and ($Platform -ne 'windows' -or $Catalog -ne 'builtin' -or [string]$id -ne 'anydesk')) {
                throw 'The anydesk update strategy is valid only for the builtin Windows anydesk package.'
            }
            if ($updateStrategy -eq 'windscribe' -and ($Platform -ne 'windows' -or $Catalog -ne 'builtin' -or [string]$id -ne 'windscribe')) {
                throw 'The windscribe update strategy is valid only for the builtin Windows windscribe package.'
            }
            $operationsModulePath = Join-Path $repoRoot 'modules/commands/package/clagnos-package-operations.psm1'
            if (-not (Test-Path -LiteralPath $operationsModulePath -PathType Leaf)) { throw "The package lifecycle helper module is missing." }
        }
        else { $updateStrategy = '' }

        $enabled = [bool]$catalogState.Entries[[string]$folder.Name]
        $bootstrapTimeoutSeconds = Convert-ClagnosTaskCatalogTimeout -Value $manifest.timeout -DefaultValue (Get-ClagnosTaskDefaultTimeoutSeconds)
        $operationTimeoutSeconds = @{}
        foreach ($timeoutAction in @('status','install','repair','update','uninstall','reinstall')) {
            $configuredTimeout = $null
            if ($null -ne $manifest.operationTimeoutSeconds -and $null -ne $manifest.operationTimeoutSeconds.PSObject.Properties[$timeoutAction]) {
                $configuredTimeout = $manifest.operationTimeoutSeconds.$timeoutAction
            }
            if ($timeoutAction -eq 'reinstall' -and $null -eq $configuredTimeout) { continue }
            $operationTimeoutSeconds[$timeoutAction] = Convert-ClagnosTaskCatalogTimeout -Value $configuredTimeout -DefaultValue $bootstrapTimeoutSeconds
        }
        if (-not $operationTimeoutSeconds.ContainsKey('reinstall')) { $operationTimeoutSeconds['reinstall'] = [Math]::Min(7200,([int]$operationTimeoutSeconds['uninstall'] + [int]$operationTimeoutSeconds['install'])) }
        $timeoutSeconds = [int]$operationTimeoutSeconds['install']
        $sortOrder = 0
        if ($null -ne $manifest.sortOrder -and [string]$manifest.sortOrder -match '^\d+$') { $sortOrder = [int]$manifest.sortOrder }
        $assetSpecs = @()
        if ($null -ne $manifest.assets) { $assetSpecs = @(ConvertTo-ClagnosTaskFolderAssetSpecs -Assets $manifest.assets -TaskLabel $id) }
        if (-not [string]::IsNullOrWhiteSpace($operationsModulePath)) {
            $assetSpecs += [pscustomobject]@{ LocalPath = [string]$operationsModulePath; RemotePath = 'C:/Windows/Temp/clagnos-package-operations.psm1' }
        }
        $appStateKey = [string]$manifest.appStateKey
        if ([string]::IsNullOrWhiteSpace($appStateKey)) { $appStateKey = $id }
        if ($appStateKey -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { throw ("Package '{0}' has an invalid appStateKey." -f $id) }
        $appStateSpec = $null
        if ($null -ne $manifest.appState) { $appStateSpec = ConvertTo-ClagnosTaskFolderAppStateSpec -AppState $manifest.appState -TaskName $appStateKey -TaskLabel $id }
        if ($null -ne $appStateSpec -and $Platform -eq 'windows') {
            $appStateGuestHelperPath = Get-ClagnosAppStateGuestHelperPath
            if (Test-Path -LiteralPath $appStateGuestHelperPath -PathType Leaf) {
                $assetSpecs += [pscustomobject]@{ LocalPath = [string]$appStateGuestHelperPath; RemotePath = 'C:/Windows/Temp/clagnos-app-state-guest.psm1' }
            }
        }
        $postInstallTasks = @()
        if ($null -ne $manifest.postInstallTasks) { $postInstallTasks = @($manifest.postInstallTasks | ForEach-Object { [string]$_ }) }
        $disabledReason = if ($enabled) { '' } else { 'disabled-in-tasks-toml' }

        $packageSpec = [pscustomobject]@{
            Id = $id
            DisplayName = $displayName.Trim()
            Category = $category
            StatusCheck = $statusCheck
            Uninstall = $uninstall
            UninstallPolicy = $uninstallPolicy
            UpdateStrategy = [string]$updateStrategy
            UpdatePackageId = [string]$updatePackageId
            RepairStrategy = [string]$repairStrategy
            RepairPackageId = [string]$manifest.repairPackageId
            RepairProductCode = [string]$manifest.repairProductCode
            StartupPolicy = $manifest.startupPolicy
            AppState = $manifest.appState
            OperationTimeoutSeconds = $operationTimeoutSeconds
            Catalog = $Catalog
            AppStateKey = $appStateKey
            PostInstallTasks = @($postInstallTasks)
            DependsOn = @($manifest.dependsOn | ForEach-Object { [string]$_ })
        }
        $taskBlock = [pscustomobject]@{
            Name = $id
            Script = [string](Get-Content -LiteralPath $installPath -Raw -ErrorAction Stop)
            Path = $installPath
            TaskRootPath = [string]$folder.FullName
            TaskMetadataPath = [string]$manifestPath
            CatalogPath = [string]$catalogPath
            RelativePath = ('{0}/{1}' -f $id, $installScript)
            DirectoryPath = [string]$folder.FullName
            StageRootDirectoryPath = [string]$root
            TimeoutSeconds = [int]$timeoutSeconds
            OperationTimeoutSeconds = $operationTimeoutSeconds
            Priority = [int]$sortOrder
            AssetSpecs = @($assetSpecs)
            AppStateSpec = $appStateSpec
            PackageSpec = $packageSpec
            AppStateKey = $appStateKey
            Extensions = $null
            TaskType = 'package'
            Source = [string]$Catalog
            TaskNumber = 0
            Enabled = [bool]$enabled
            DisabledReason = [string]$disabledReason
            DependsOn = @($packageSpec.DependsOn)
            LifecycleScriptPaths = $lifecycleScriptPaths
            LifecycleScriptText = $lifecycleScriptText
            UpdateStrategy = [string]$updateStrategy
            UpdatePackageId = [string]$updatePackageId
            RepairStrategy = [string]$repairStrategy
            RepairPackageId = [string]$manifest.repairPackageId
            StartupPolicy = $manifest.startupPolicy
            ObservedDurationSeconds = [double]::PositiveInfinity
        }
        $packages += [pscustomobject]@{
            Id = $id
            DisplayName = $displayName.Trim()
            Category = $category
            StatusCheck = $statusCheck
            Uninstall = $uninstall
            UninstallPolicy = $uninstallPolicy
            UpdateStrategy = [string]$updateStrategy
            UpdatePackageId = [string]$updatePackageId
            RepairStrategy = [string]$repairStrategy
            RepairPackageId = [string]$manifest.repairPackageId
            RepairProductCode = [string]$manifest.repairProductCode
            OperationTimeoutSeconds = $operationTimeoutSeconds
            StartupPolicy = $manifest.startupPolicy
            AppState = $manifest.appState
            LifecycleScriptPaths = $lifecycleScriptPaths
            StatusScriptText = [string]$lifecycleScriptText['status']
            UpdateScriptText = [string]$lifecycleScriptText['update']
            UninstallScriptText = [string]$lifecycleScriptText['uninstall']
            RepairScriptText = [string]$lifecycleScriptText['repair']
            Catalog = $Catalog
            CatalogRoot = [string]$root
            ManifestPath = [string]$manifestPath
            CatalogPath = [string]$catalogPath
            DirectoryPath = [string]$folder.FullName
            Enabled = [bool]$enabled
            DisabledReason = [string]$disabledReason
            SortOrder = [int]$sortOrder
            PackageTask = $taskBlock
            Platform = [string]$Platform
        }
    }

    return @($packages | Sort-Object @{ Expression = { [int]$_.SortOrder } }, { [string]$_.DisplayName })
}

function Get-ClagnosPackageStatusCacheKey {
    param([object[]]$Packages, [hashtable]$Options, [string]$Platform)
    $transport = 'ssh'
    try {
        $configPath = Get-ClagnosGlobalEnvPath
        $globalConfig = if (Test-Path -LiteralPath $configPath -PathType Leaf) { Read-DotEnvFile -Path $configPath -GlobalOnly } else { @{} }
        $targetVmName = [string](Get-ClagnosCliOptionText -Options $Options -Name 'vm-name')
        if ([string]::IsNullOrWhiteSpace([string]$targetVmName)) { $targetVmName = [string]$globalConfig['ACTIVE_VM_NAME'] }
        $targetConfig = Merge-ClagnosVmEnvironmentConfig -GlobalConfigMap $globalConfig -VmName $targetVmName
        $transport = Get-ClagnosPackageTransport -ConfigMap $targetConfig
    }
    catch { $transport = 'invalid' }
    $catalogIdentity = @($Packages | ForEach-Object {
        $statusCheck = ConvertTo-Json -InputObject $_.StatusCheck -Depth 20 -Compress
        '{0}:{1}:{2}:{3}' -f [string]$_.Catalog,[string]$_.Id,[string]$statusCheck,[bool]$_.Enabled
    } | Sort-Object) -join ','
    return ('{0}|{1}|{2}|{3}|{4}|{5}' -f [string](Get-ClagnosCliOptionText -Options $Options -Name 'subscription-id'), [string](Get-ClagnosCliOptionText -Options $Options -Name 'group'), [string](Get-ClagnosCliOptionText -Options $Options -Name 'vm-name'), [string]$Platform, $transport, $catalogIdentity).ToLowerInvariant()
}

function Get-ClagnosPackageTimeoutSeconds {
    param([Parameter(Mandatory = $true)][object]$Package,[Parameter(Mandatory = $true)][ValidateSet('status','install','repair','update','uninstall','reinstall')][string]$Action)

    $timeouts = $Package.OperationTimeoutSeconds
    if ($null -ne $timeouts -and $timeouts.ContainsKey($Action)) { return [int]$timeouts[$Action] }
    if ($Action -eq 'reinstall' -and $null -ne $timeouts) {
        return [Math]::Min(7200,([int]$timeouts['uninstall'] + [int]$timeouts['install']))
    }
    return [int]$Package.PackageTask.TimeoutSeconds
}

function Get-ClagnosPackageStatusDiskCachePath {
    param([string]$Key)

    $root = [string]$env:LOCALAPPDATA
    if ([string]::IsNullOrWhiteSpace($root)) { $root = [System.IO.Path]::GetTempPath() }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$Key)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $digest = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
    return (Join-Path (Join-Path $root 'Clagnos\cache\package-status') ($digest + '.json'))
}

function ConvertTo-ClagnosPackageStatusUtcDateTime {
    param([Parameter(Mandatory = $true)][object]$Value)

    if ($Value -is [DateTime]) { return ([DateTime]$Value).ToUniversalTime() }
    return [DateTime]::Parse([string]$Value,[System.Globalization.CultureInfo]::InvariantCulture,[System.Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
}

function Save-ClagnosPackageStatusCacheEntry {
    param([string]$Key, [hashtable]$Entry)

    if ([string]$env:CLAGNOS_PACKAGE_STATUS_CACHE_NO_DISK_WRITE -match '^(?i)(1|true|yes|on)$') { return }
    $path = Get-ClagnosPackageStatusDiskCachePath -Key $Key
    $directory = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    $temporaryPath = '{0}.{1}.{2}.tmp' -f $path,$PID,[Guid]::NewGuid().ToString('N')
    try {
        $json = ConvertTo-Json -InputObject ([ordered]@{ CacheKey = [string]$Key; CreatedAtUtc = ([DateTime]$Entry.CreatedAtUtc).ToString('o'); Complete = [bool]$Entry.Complete; StatusByPackage = $Entry.StatusByPackage }) -Depth 30 -Compress
        Set-Content -LiteralPath $temporaryPath -Value $json -Encoding UTF8
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            try { [System.IO.File]::Replace($temporaryPath,$path,$null) }
            catch { Move-Item -LiteralPath $temporaryPath -Destination $path -Force }
        }
        else { Move-Item -LiteralPath $temporaryPath -Destination $path -Force }
    }
    finally { if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue } }
}

function Get-ClagnosPackageStatusCacheEntry {
    param([object[]]$Packages, [hashtable]$Options, [string]$Platform)

    $key = Get-ClagnosPackageStatusCacheKey -Packages $Packages -Options $Options -Platform $Platform
    if ($null -eq $script:ClagnosPackageStatusCache) { $script:ClagnosPackageStatusCache = @{} }
    $entry = if ($script:ClagnosPackageStatusCache.ContainsKey($key)) { $script:ClagnosPackageStatusCache[$key] } else { $null }
    $path = Get-ClagnosPackageStatusDiskCachePath -Key $key
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        try {
            $diskEntry = ConvertFrom-JsonCompat -InputObject ([string](Get-Content -LiteralPath $path -Raw -ErrorAction Stop))
            if ([string]::Equals([string]$diskEntry.CacheKey,$key,[System.StringComparison]::Ordinal)) {
                $diskCreatedAt = ConvertTo-ClagnosPackageStatusUtcDateTime -Value $diskEntry.CreatedAtUtc
                if ($null -eq $entry -or $diskCreatedAt -gt [DateTime]$entry.CreatedAtUtc) {
                    $entry = @{ CreatedAtUtc = $diskCreatedAt; Complete = [bool]$diskEntry.Complete; StatusByPackage = @{} }
                    foreach ($property in @($diskEntry.StatusByPackage.PSObject.Properties)) { $entry.StatusByPackage[[string]$property.Name] = [string]$property.Value }
                    $script:ClagnosPackageStatusCache[$key] = $entry
                }
            }
        }
        catch { if ($null -eq $entry) { $entry = $null } }
    }
    if ($null -eq $entry) { return $null }
    $ttlSeconds = if ([int]$script:ClagnosPackageStatusCacheTtlSeconds -gt 0) { [int]$script:ClagnosPackageStatusCacheTtlSeconds } else { 45 }
    $age = ([DateTime]::UtcNow - [DateTime]$entry.CreatedAtUtc).TotalSeconds
    return [pscustomobject]@{ Key = $key; Entry = $entry; IsFresh = ($age -lt $ttlSeconds -and [bool]$entry.Complete); AgeSeconds = [double]$age }
}

function Get-ClagnosPackageLifecycleSpecBase64 {
    param([object]$Package,[object]$Context = $null)
    $spec = [ordered]@{
        id = [string]$Package.Id
        displayName = [string]$Package.DisplayName
        statusCheck = $Package.StatusCheck
        uninstall = $Package.Uninstall
        updateStrategy = [string]$Package.UpdateStrategy
        updatePackageId = [string]$Package.UpdatePackageId
        repairStrategy = [string]$Package.RepairStrategy
        repairPackageId = [string]$Package.RepairPackageId
        repairProductCode = [string]$Package.RepairProductCode
    }
    if ($null -ne $Package.PSObject.Properties['StartupPolicy']) { $spec.startupPolicy = $Package.StartupPolicy }
    if ($null -ne $Package.PSObject.Properties['AppState'] -and $null -ne $Package.AppState) { $spec.appState = $Package.AppState }
    if ($null -ne $Context) {
        $targetUsers = @()
        foreach ($userName in @([string]$Context.VmUser,[string]$Context.VmAssistantUser)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$userName)) { $targetUsers += [string]$userName }
        }
        $spec.targetUsers = @($targetUsers)
    }
    $json = ConvertTo-Json -InputObject $spec -Depth 20 -Compress
    return [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes([string]$json))
}

function New-ClagnosPackageRepairWithAppStateBackupScript {
    param([string]$InnerScript,[object]$Package,[object]$Context)

    if ([string]::IsNullOrWhiteSpace([string]$InnerScript) -or $null -eq $Package.PackageTask.AppStateSpec) { return [string]$InnerScript }
    $capturePlan = Get-ClagnosTaskAppStateCapturePlan -TaskBlock $Package.PackageTask
    $planJson = ConvertTo-ClagnosTaskAppStateCapturePlanJson -CapturePlan $capturePlan
    if ([string]::IsNullOrWhiteSpace([string]$planJson)) { return [string]$InnerScript }
    $planBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes([string]$planJson))
    $innerBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes([string]$InnerScript))
    $taskName = Get-ClagnosTaskAppStateIdentity -TaskBlock $Package.PackageTask
    $managerUser = if ($null -ne $Context) { ([string]$Context.VmUser).Replace("'","''") } else { '' }
    $assistantUser = if ($null -ne $Context) { ([string]$Context.VmAssistantUser).Replace("'","''") } else { '' }
    $wrapper = @'
$ErrorActionPreference = 'Stop'
$taskName = '__CLAGNOS_REPAIR_TASK_NAME__'
$managerUser = '__CLAGNOS_REPAIR_MANAGER_USER__'
$assistantUser = '__CLAGNOS_REPAIR_ASSISTANT_USER__'
$planBase64 = '__CLAGNOS_REPAIR_PLAN_B64__'
$innerBase64 = '__CLAGNOS_REPAIR_INNER_B64__'
$helperPath = 'C:\Windows\Temp\clagnos-app-state-guest.psm1'
if (-not (Test-Path -LiteralPath $helperPath -PathType Leaf)) { throw ('Package repair state helper was not staged: ' + $helperPath) }
Import-Module $helperPath -Force -DisableNameChecking
$scratchRoot = Join-Path ([IO.Path]::GetTempPath()) ('clagnos-package-repair-' + [guid]::NewGuid().ToString('N'))
$planPath = Join-Path $scratchRoot 'capture-plan.json'
$backupZip = Join-Path $scratchRoot 'current-app-state.zip'
$emergencyRoot = Join-Path (Join-Path $env:ProgramData 'clagnos\state') 'package-repair-backups'
$safeTaskName = [regex]::Replace($taskName,'[^A-Za-z0-9._-]','_')
$emergencyZip = Join-Path $emergencyRoot ($safeTaskName + '.zip')
New-Item -ItemType Directory -Path $scratchRoot -Force | Out-Null
try {
$planJson = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($planBase64))
[IO.File]::WriteAllText($planPath,$planJson,(New-Object System.Text.UTF8Encoding($false)))
$capture = Invoke-ClagnosTaskAppStateCapture -TaskName $taskName -PlanPath $planPath -OutputZipPath $backupZip -ManagerUser $managerUser -AssistantUser $assistantUser
if (-not [bool]$capture.CreatedZip -or -not (Test-Path -LiteralPath $backupZip -PathType Leaf)) {
    Write-Output ('No app-state files were present to preserve for ' + $taskName + '; continuing same-version repair.')
    $innerScript = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($innerBase64))
    & ([scriptblock]::Create($innerScript))
    Remove-Item -LiteralPath $scratchRoot -Recurse -Force -ErrorAction SilentlyContinue
    return
}
New-Item -ItemType Directory -Path $emergencyRoot -Force | Out-Null
Copy-Item -LiteralPath $backupZip -Destination $emergencyZip -Force -ErrorAction Stop
try {
    $innerScript = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($innerBase64))
    & ([scriptblock]::Create($innerScript))
    $restore = Invoke-ClagnosTaskAppStateReplay -ZipPath $backupZip -TaskName $taskName -ManagerUser $managerUser -AssistantUser $assistantUser
    if (-not [bool]$restore.Verified -or [int]$restore.VerifyMismatchCount -gt 0) { throw 'The captured package settings did not verify after repair.' }
    if (Test-Path -LiteralPath $emergencyZip -PathType Leaf) { Remove-Item -LiteralPath $emergencyZip -Force -ErrorAction Stop }
    if (Test-Path -LiteralPath $emergencyZip -PathType Leaf) { throw 'The verified package repair backup could not be cleaned up.' }
    Write-Output ('Package repair restored and verified the target VC app-state for ' + $taskName + '.')
}
catch {
    throw ('Package repair failed; the captured app-state emergency backup remains on the VC at ' + $emergencyZip + '. ' + [string]$_.Exception.Message)
}
}
finally {
    Remove-Item -LiteralPath $scratchRoot -Recurse -Force -ErrorAction SilentlyContinue
}
'@
    $wrapper = $wrapper.Replace('__CLAGNOS_REPAIR_TASK_NAME__',$taskName)
    $wrapper = $wrapper.Replace('__CLAGNOS_REPAIR_MANAGER_USER__',$managerUser)
    $wrapper = $wrapper.Replace('__CLAGNOS_REPAIR_ASSISTANT_USER__',$assistantUser)
    $wrapper = $wrapper.Replace('__CLAGNOS_REPAIR_PLAN_B64__',$planBase64)
    $wrapper = $wrapper.Replace('__CLAGNOS_REPAIR_INNER_B64__',$innerBase64)
    return [string]$wrapper
}

function New-ClagnosPackageLifecycleScript {
    param(
        [ValidateSet('status','install','repair','update','uninstall')][string]$Action,
        [object]$Package,
        [object]$Context = $null
    )
    $template = switch ($Action) {
        'status' { [string]$Package.StatusScriptText }
        'update' { [string]$Package.UpdateScriptText }
        'uninstall' { [string]$Package.UninstallScriptText }
        'repair' { [string]$Package.RepairScriptText }
        'install' { '' }
    }
    if ([string]::IsNullOrWhiteSpace($template) -and $Action -in @('install','repair','update')) {
        if ($Action -eq 'install') {
            $template = @'
$ErrorActionPreference = 'Stop'
Import-Module 'C:\Windows\Temp\clagnos-package-operations.psm1' -Force -DisableNameChecking
Invoke-ClagnosPackageLifecycle -Action install -PackageSpecBase64 '__CLAGNOS_PACKAGE_SPEC_B64__' -InstallScriptBase64 '__CLAGNOS_INSTALL_SCRIPT_B64__'
'@
        }
        else {
            $scriptAction = $Action
            $template = @'
$ErrorActionPreference = 'Stop'
Import-Module 'C:\Windows\Temp\clagnos-package-operations.psm1' -Force -DisableNameChecking
Invoke-ClagnosPackageLifecycle -Action __CLAGNOS_ACTION__ -PackageSpecBase64 '__CLAGNOS_PACKAGE_SPEC_B64__' -InstallScriptBase64 '__CLAGNOS_INSTALL_SCRIPT_B64__'
'@
            $template = $template.Replace('__CLAGNOS_ACTION__',[string]$scriptAction)
        }
    }
    if ([string]::IsNullOrWhiteSpace($template)) { return '' }
    if ([string]$Action -eq 'uninstall' -and [string]$Package.Id -eq 'windscribe') {
        if ($null -eq $Context -or [string]::IsNullOrWhiteSpace([string]$Context.VmUser) -or [string]::IsNullOrWhiteSpace([string]$Context.VmPass)) {
            throw 'Windscribe uninstall requires the selected manager account to run its bounded firewall and package checks in an interactive session.'
        }
        $managerUserToken = ([string]$Context.VmUser).Replace("'","''")
        $managerPasswordToken = ([string]$Context.VmPass).Replace("'","''")
        $template = $template.Replace('__VM_ADMIN_USER__',$managerUserToken)
        $template = $template.Replace('__VM_ADMIN_PASS__',$managerPasswordToken)
    }
    $template = $template.Replace('__CLAGNOS_PACKAGE_SPEC_B64__',(Get-ClagnosPackageLifecycleSpecBase64 -Package $Package -Context $Context))
    if ($Action -in @('install','repair','update')) {
        $installSource = [string]$Package.PackageTask.Script
        if ($null -ne $Context) {
            $resolved = @(Apply-ClagnosTaskBlockReplacements -TaskBlocks @($Package.PackageTask) -Replacements (Get-ClagnosTaskTokenReplacements -Context $Context) -Context $Context)
            if ($resolved.Count -gt 0) { $installSource = [string]$resolved[0].Script }
        }
        $installBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($installSource))
        $template = $template.Replace('__CLAGNOS_INSTALL_SCRIPT_B64__',$installBase64)
    }
    if ($Action -eq 'repair') { $template = New-ClagnosPackageRepairWithAppStateBackupScript -InnerScript $template -Package $Package -Context $Context }
    return [string]$template
}

function Get-ClagnosPackageStructuredResult {
    param([psobject]$TaskResult)
    if ($null -eq $TaskResult -or $null -eq $TaskResult.Result -or @($TaskResult.Result.TaskOutputs).Count -eq 0) { return $null }
    $output = [string]$TaskResult.Result.TaskOutputs[0].Output
    $match = [regex]::Match($output,'(?m)^CLAGNOS_PACKAGE_RESULT:(?<json>\{.*\})\s*$')
    if (-not $match.Success) { return $null }
    return (ConvertFrom-JsonCompat -InputObject ([string]$match.Groups['json'].Value))
}

function New-ClagnosPackageGuestScript {
    param(
        [string]$Action,
        [object[]]$Packages,
        [ValidateSet('windows','linux')][string]$Platform,
        [psobject]$Context = $null
    )

    $payload = @(
        $Packages | ForEach-Object {
            [ordered]@{
                id = [string]$_.Id
                displayName = [string]$_.DisplayName
                statusCheck = $_.StatusCheck
                uninstall = $_.Uninstall
                startupPolicy = $_.StartupPolicy
                appState = $_.AppState
                targetUsers = @($(if ($null -ne $Context) { @([string]$Context.VmUser,[string]$Context.VmAssistantUser) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } } else { @() }))
            }
        }
    )
    $json = ConvertTo-Json -InputObject $payload -Depth 20 -Compress
    $base64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes([string]$json))
    if ([string]::Equals([string]$Platform,'linux',[System.StringComparison]::OrdinalIgnoreCase)) {
        if ([string]::Equals([string]$Action,'status',[System.StringComparison]::OrdinalIgnoreCase)) {
            $records = @($Packages | ForEach-Object { '{0}|{1}|{2}' -f [string]$_.Id,[string]$_.StatusCheck.kind,[string]$_.StatusCheck.value }) -join "`n"
            $recordBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes([string]$records))
            $bash = @'
records=$(printf '%s' '__RECORDS__' | base64 -d)
json='['
separator=''
while IFS='|' read -r id kind value; do
    [ -z "$id" ] && continue
    status='unknown'
    case "$kind" in
        command) if command -v "$value" >/dev/null 2>&1; then status='installed'; else status='not-installed'; fi ;;
        dpkg) if dpkg-query -W -f='${Status}' -- "$value" 2>/dev/null | grep -q 'install ok installed'; then status='installed'; else status='not-installed'; fi ;;
        rpm) if rpm -q -- "$value" >/dev/null 2>&1; then status='installed'; else status='not-installed'; fi ;;
    esac
    json="${json}${separator}{\"id\":\"${id}\",\"status\":\"${status}\"}"
    separator=','
done <<EOF
$records
EOF
json="${json}]"
printf 'CLAGNOS_PACKAGE_RESULTS:%s\n' "$json"
'@
            return $bash.Replace('__RECORDS__',$recordBase64)
        }
        $package = @($Packages)[0]
        $uninstall = $package.Uninstall
        $value = [string]$uninstall.value
        $quoteBreak = "'" + '"' + "'" + '"' + "'"
        $quoted = "'" + $value.Replace("'",$quoteBreak) + "'"
        $bashAction = switch ([string]$uninstall.kind) {
            'apt' { "sudo -n apt-get remove --purge -y $quoted" }
            'dnf' { "sudo -n dnf remove -y $quoted" }
            'snap' { "sudo -n snap remove $quoted" }
            default { throw ("Unsupported Linux uninstall kind '{0}'." -f [string]$uninstall.kind) }
        }
        return ("set -e`n{0}`nprintf 'CLAGNOS_PACKAGE_REMOVED:{1}\\n' '{1}'" -f $bashAction,[string]$package.Id)
    }
    if ([string]::Equals([string]$Action, 'status', [System.StringComparison]::OrdinalIgnoreCase)) {
        return @"
`$payload = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$base64'))
`$parsedPackageInput = ConvertFrom-Json -InputObject `$payload
Import-Module 'C:\Windows\Temp\clagnos-package-operations.psm1' -Force -DisableNameChecking
`$packages = @()
foreach (`$entry in @(`$parsedPackageInput)) {
    # Windows PowerShell 5.1 can return a JSON root array as one nested collection object.
    # Flatten it so a catalog status pass evaluates each package instead of one unknown row.
    if (`$entry -is [System.Collections.IList] -and `$entry -isnot [string]) {
        foreach (`$nestedPackage in `$entry) { `$packages += `$nestedPackage }
    }
    elseif (`$null -ne `$entry) { `$packages += `$entry }
}
`$hasWingetPackages = @(`$packages | Where-Object { [string]`$_.statusCheck.kind -eq 'winget' }).Count -gt 0
`$hasChocoPackages = @(`$packages | Where-Object { [string]`$_.statusCheck.kind -eq 'choco' }).Count -gt 0
`$hasNpmPackages = @(`$packages | Where-Object { [string]`$_.statusCheck.kind -eq 'npm' }).Count -gt 0
`$hasAppxPackages = @(`$packages | Where-Object { [string]`$_.statusCheck.kind -in @('appx','store-state') }).Count -gt 0
`$wingetInventory = ''
`$wingetInventoryReady = `$false
if (`$hasWingetPackages) {
    `$wingetExe = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (`$wingetExe) {
        Write-Output 'Doing: read one winget package inventory'
        `$wingetInventory = & `$wingetExe.Source list --accept-source-agreements --disable-interactivity 2>`$null | Out-String
        `$wingetInventoryReady = ([int]`$LASTEXITCODE -eq 0)
    }
}
`$chocoInventory = ''
`$chocoInventoryReady = `$false
if (`$hasChocoPackages) {
    `$chocoExe = Get-Command choco.exe -ErrorAction SilentlyContinue
    if (`$chocoExe) {
        Write-Output 'Doing: read one Chocolatey local package inventory'
        `$chocoInventory = & `$chocoExe.Source list --local-only --limit-output 2>`$null | Out-String
        `$chocoInventoryReady = ([int]`$LASTEXITCODE -eq 0)
    }
}
`$npmModulesRoot = Join-Path (Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::ApplicationData)) 'npm') 'node_modules'
`$appxInventory = @()
`$appxInventoryReady = `$false
if (`$hasAppxPackages) {
    try {
        Write-Output 'Doing: read one AppX package inventory'
        `$appxInventory = @(Get-AppxPackage -AllUsers -ErrorAction Stop)
        `$appxInventoryReady = `$true
    }
    catch { `$appxInventoryReady = `$false }
}
function Get-PackageStatus {
    param([object]`$Package)
    `$check = `$Package.statusCheck
    if (`$null -eq `$check -or [string]::IsNullOrWhiteSpace([string]`$check.kind) -or [string]::IsNullOrWhiteSpace([string]`$check.value)) { return 'unknown' }
    `$value = [string]`$check.value
    switch ([string]`$check.kind) {
        'command' { if ((Test-Path -LiteralPath `$value -PathType Leaf) -or (Get-Command `$value -ErrorAction SilentlyContinue)) { return 'installed' }; return 'not-installed' }
        'windscribe' { `$record = Get-ClagnosWindscribePackageRecord -Spec `$Package; return [string]`$record.Status }
        'wsl' { `$record = Get-ClagnosWslPackageRecord -DisplayName `$value; return [string]`$record.Status }
        'winget' {
            if (-not `$wingetInventoryReady) { return 'unknown' }
            if (`$wingetInventory -match ('(?im)(?:^|\s)' + [regex]::Escape(`$value) + '(?:\s|$)')) { return 'installed' }
            return 'not-installed'
        }
        'choco' {
            if (-not `$chocoInventoryReady) { return 'unknown' }
            if (`$chocoInventory -match ('(?im)^' + [regex]::Escape(`$value) + '\|[^|\s]+\s*$')) { return 'installed' }
            return 'not-installed'
        }
        'npm' {
            `$packagePath = [string]`$npmModulesRoot
            foreach (`$segment in @([string]`$value -split '/')) {
                if ([string]::IsNullOrWhiteSpace([string]`$segment) -or [string]`$segment -eq '.' -or [string]`$segment -eq '..') { return 'unknown' }
                `$packagePath = Join-Path `$packagePath ([string]`$segment)
            }
            if (-not (Test-Path -LiteralPath `$packagePath -PathType Container)) { return 'not-installed' }
            if (Test-Path -LiteralPath (Join-Path `$packagePath 'package.json') -PathType Leaf) { return 'installed' }
            return 'unknown'
        }
        'appx' {
            if (-not `$appxInventoryReady) { return 'unknown' }
            `$appMatches = @(`$appxInventory | Where-Object { `$_.Name -like ('*' + `$value + '*') -or `$_.PackageFamilyName -like ('*' + `$value + '*') -or `$_.PackageFullName -like ('*' + `$value + '*') })
            if (`$appMatches.Count -gt 0) { return 'installed' }
            return 'not-installed'
        }
        'store-state' {
            if (`$appxInventoryReady) {
                `$uninstallValue = [string]`$Package.uninstall.value
                `$appMatches = @(`$appxInventory | Where-Object { `$_.Name -like ('*' + `$uninstallValue + '*') -or `$_.PackageFamilyName -like ('*' + `$uninstallValue + '*') -or `$_.PackageFullName -like ('*' + `$uninstallValue + '*') })
                if (`$appMatches.Count -gt 0) { return 'installed' }
            }
            `$safeName = [regex]::Replace(`$value, '[^A-Za-z0-9._-]', '_')
            `$path = Join-Path (Join-Path `$env:ProgramData 'clagnos\state\store-installs') (`$safeName + '.json')
            if (-not (Test-Path -LiteralPath `$path)) { if (`$appxInventoryReady) { return 'not-installed' }; return 'unknown' }
            try { `$state = Get-Content -LiteralPath `$path -Raw | ConvertFrom-Json; if ([string]`$state.State -eq 'installed') { return 'unknown' }; return 'not-installed' } catch { return 'unknown' }
        }
        'choco-self' { if (Test-Path -LiteralPath (Join-Path `$env:ProgramData 'chocolatey\bin\choco.exe')) { return 'installed' }; return 'not-installed' }
        'sysinternals' { `$sysinternals = Get-ClagnosSysinternalsPackageRecord -Spec `$Package; return [string]`$sysinternals.Status }
        default { return 'unknown' }
    }
}
`$results = @()
foreach (`$package in `$packages) {
    `$status = Get-PackageStatus -Package `$package
    `$detail = ''
    if ([string]`$package.id -eq 'windscribe') {
        `$windscribeRecord = Get-ClagnosWindscribePackageRecord -Spec `$package
        `$status = [string]`$windscribeRecord.Status
        `$detail = [string]`$windscribeRecord.Detail
    }
    elseif ([string]`$package.id -eq 'windows-subsystem-linux') {
        `$wslRecord = Get-ClagnosWslPackageRecord -DisplayName ([string]`$package.statusCheck.value)
        `$status = [string]`$wslRecord.Status
        `$detail = [string]`$wslRecord.Detail
    }
    elseif (`$status -eq 'installed') {
        if ([string]`$package.id -eq 'jaws' -and @(`$package.targetUsers).Count -gt 0) {
            `$missingUsers = @(`$package.targetUsers | Where-Object { -not (Test-ClagnosJawsPostLogonStartup -UserName ([string]`$_) -Executable 'C:\Program Files\Freedom Scientific\JAWS\2025\jfw.exe') })
                `$logonScreenReady = Test-ClagnosJawsLogonScreenStartup
                `$jawsState = Get-ClagnosJawsPackageStatusDetails -Spec `$package
                if (`$missingUsers.Count -gt 0 -or -not `$logonScreenReady) {
                    `$detailParts = @()
                    if (`$missingUsers.Count -gt 0) { `$detailParts += 'post-logon startup is missing for: ' + (`$missingUsers -join ', ') }
                    if (-not `$logonScreenReady) { `$detailParts += 'logon-screen startup Run=1 is missing' }
                    if (-not [bool]`$jawsState.Healthy -and -not [string]::IsNullOrWhiteSpace([string]`$jawsState.Detail)) { `$detailParts += [string]`$jawsState.Detail }
                    `$detail = 'JAWS startup is incomplete: ' + (`$detailParts -join '; ')
                    `$status = 'installed-drifted'
                }
                elseif (-not [bool]`$jawsState.Healthy) { `$detail = [string]`$jawsState.Detail; `$status = 'installed-drifted' }
                else { `$detail = 'JAWS starts at the Windows logon screen and after logon for manager and assistant; ENU-only, offline, and app-state checks passed.' }
        }
        elseif ([string]`$package.id -in @('ollama','docker-desktop')) {
            `$detail = Test-ClagnosPackageStartupState -Spec `$package
            if (`$detail -match '(?i)missing|not verified') { `$status = 'installed-drifted' }
        }
    }
    `$results += [pscustomobject]@{ id = [string]`$package.id; status = `$status; detail = `$detail }
}
`$jsonResult = ConvertTo-Json -InputObject `$results -Depth 4 -Compress
`$global:LASTEXITCODE = 0
Write-Output ('CLAGNOS_PACKAGE_RESULTS:' + `$jsonResult)
"@
    }

    return @"
`$payload = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$base64'))
`$packages = @(ConvertFrom-Json -InputObject `$payload)
`$results = @()
foreach (`$package in `$packages) {
    `$check = `$package.statusCheck
    `$status = 'unknown'
    if (`$null -ne `$check) {
        switch ([string]`$check.kind) {
            'command' { if (Get-Command ([string]`$check.value) -ErrorAction SilentlyContinue) { `$status = 'installed' } else { `$status = 'not-installed' } }
            'dpkg' { if (Get-Command dpkg-query -ErrorAction SilentlyContinue) { dpkg-query -W -f='`${Status}' -- ([string]`$check.value) 2>/dev/null | grep -q 'install ok installed'; if (`$LASTEXITCODE -eq 0) { `$status = 'installed' } else { `$status = 'not-installed' } } }
            'rpm' { if (Get-Command rpm -ErrorAction SilentlyContinue) { rpm -q -- ([string]`$check.value) >/dev/null 2>&1; if (`$LASTEXITCODE -eq 0) { `$status = 'installed' } else { `$status = 'not-installed' } } }
        }
    }
    `$results += [pscustomobject]@{ id = [string]`$package.id; status = `$status }
}
`$jsonResult = ConvertTo-Json -InputObject `$results -Depth 4 -Compress
Write-Output ('CLAGNOS_PACKAGE_RESULTS:' + `$jsonResult)
"@
}

function New-ClagnosPackageUninstallScript {
    param([object]$Package, [ValidateSet('windows','linux')][string]$Platform = 'windows',[object]$Context = $null)

    if (-not [string]::IsNullOrWhiteSpace([string]$Package.UninstallScriptText)) {
        return (New-ClagnosPackageLifecycleScript -Action 'uninstall' -Package $Package -Context $Context)
    }

    $actionPackage = [pscustomobject]@{
        Id = [string]$Package.Id
        DisplayName = [string]$Package.DisplayName
        StatusCheck = $Package.StatusCheck
        Uninstall = $Package.Uninstall
    }
    $json = ConvertTo-Json -InputObject @($actionPackage) -Depth 20 -Compress
    $base64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes([string]$json))
    if ($Platform -eq 'linux') {
        $uninstall = $Package.Uninstall
        $value = [string]$uninstall.value
        $quoteBreak = "'" + '"' + "'" + '"' + "'"
        $quoted = "'" + $value.Replace("'",$quoteBreak) + "'"
        $bashAction = switch ([string]$uninstall.kind) {
            'apt' { "sudo -n apt-get remove --purge -y $quoted" }
            'dnf' { "sudo -n dnf remove -y $quoted" }
            'snap' { "sudo -n snap remove $quoted" }
            default { throw ("Unsupported Linux uninstall kind '{0}'." -f [string]$uninstall.kind) }
        }
        return ("set -e`n{0}`nprintf 'CLAGNOS_PACKAGE_REMOVED:{1}\\n' '{1}'" -f $bashAction,[string]$package.Id)
    }
    return @"
`$payload = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$base64'))
`$package = @(ConvertFrom-Json -InputObject `$payload)[0]
`$uninstall = `$package.uninstall
if (`$null -eq `$uninstall -or [string]::IsNullOrWhiteSpace([string]`$uninstall.kind) -or [string]::IsNullOrWhiteSpace([string]`$uninstall.value)) { throw 'This catalog entry has no safe uninstall action.' }
`$value = [string]`$uninstall.value
switch ([string]`$uninstall.kind) {
    'winget' { `$exe = Get-Command winget.exe -ErrorAction SilentlyContinue; if (-not `$exe) { throw 'Windows Package Manager is not available.' }; & `$exe.Source uninstall --id `$value --exact --silent --accept-source-agreements --disable-interactivity; if (`$LASTEXITCODE -ne 0) { throw ('winget uninstall failed with exit code ' + `$LASTEXITCODE) } }
    'choco' { `$exe = Get-Command choco.exe -ErrorAction SilentlyContinue; if (-not `$exe) { throw 'Chocolatey is not available.' }; & `$exe.Source uninstall `$value -y --no-progress; if (`$LASTEXITCODE -ne 0) { throw ('Chocolatey uninstall failed with exit code ' + `$LASTEXITCODE) } }
    'npm' { `$exe = Get-Command npm.cmd -ErrorAction SilentlyContinue; if (-not `$exe) { throw 'npm is not available.' }; & `$exe.Source uninstall -g `$value; if (`$LASTEXITCODE -ne 0) { throw ('npm uninstall failed with exit code ' + `$LASTEXITCODE) } }
    'appx' { `$packages = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { `$_.Name -like ('*' + `$value + '*') -or `$_.PackageFamilyName -like ('*' + `$value + '*') -or `$_.PackageFullName -like ('*' + `$value + '*') }); foreach (`$package in `$packages) { Remove-AppxPackage -Package `$package.PackageFullName -AllUsers -ErrorAction Stop } }
    'windows-feature' { Disable-WindowsOptionalFeature -Online -FeatureName `$value -NoRestart -ErrorAction Stop | Out-Null }
    'choco-self' { if (Test-Path -LiteralPath `$value) { Remove-Item -LiteralPath `$value -Recurse -Force }; Write-Output 'Chocolatey files removed.' }
    'sysinternals' { Remove-ClagnosSysinternalsPackage -Spec `$package }
    default { throw ('Unsupported safe uninstall type: ' + [string]`$uninstall.kind) }
}
if ([string]`$package.statusCheck.kind -eq 'store-state') {
    `$safeName = [regex]::Replace([string]`$package.statusCheck.value, '[^A-Za-z0-9._-]', '_')
    `$statePath = Join-Path (Join-Path `$env:ProgramData 'clagnos\state\store-installs') (`$safeName + '.json')
    if (Test-Path -LiteralPath `$statePath) { Remove-Item -LiteralPath `$statePath -Force }
}
Write-Output ('CLAGNOS_PACKAGE_REMOVED:' + [string]`$package.id)
"@
}

function Invoke-ClagnosPackageGuestScript {
    param(
        [hashtable]$Options,
        [string]$Platform,
        [string]$ScriptText,
        [string]$TaskLabel,
        [int]$TimeoutSeconds = 300,
        [psobject]$Runtime = $null,
        [psobject]$Target = $null
    )

    if ($null -eq $Runtime) {
        $Runtime = Initialize-ClagnosTaskExecutionRuntimeContext -AutoMode:$false -WindowsFlag:([string]$Platform -eq 'windows') -LinuxFlag:([string]$Platform -eq 'linux') -Options $Options
    }
    if ($null -eq $Target) {
        $Target = Resolve-ClagnosManagedVmTarget -Options $Options -ConfigMap $Runtime.EffectiveConfigMap -OperationName 'package'
    }
    $Runtime.Context.ResourceGroup = [string]$Target.ResourceGroup
    $Runtime.Context.VmName = [string]$Target.VmName
    $vmDetails = Get-ClagnosVmDetails -Context $Runtime.Context -AllowCachedInventory
    $sshHost = [string]$vmDetails.VmFqdn
    if ([string]::IsNullOrWhiteSpace($sshHost)) { $sshHost = [string]$vmDetails.PublicIP }
    if ([string]::IsNullOrWhiteSpace($sshHost)) { throw 'Package management could not resolve a guest host.' }
    $transport = Get-ClagnosPackageTransport -ConfigMap ([hashtable]$Runtime.EffectiveConfigMap)
    $block = [pscustomobject]@{
        Name = [string]$TaskLabel
        Script = [string]$ScriptText
        RelativePath = ('vm-packages/{0}' -f [string]$TaskLabel)
        DirectoryPath = (Get-ClagnosRepoRoot)
        TaskRootPath = (Get-ClagnosRepoRoot)
        StageRootDirectoryPath = (Get-ClagnosRepoRoot)
        TimeoutSeconds = [int]$TimeoutSeconds
        Priority = 1
        TaskType = 'package'
        Source = 'managed-package-catalog'
        TaskNumber = 1
        AssetCopies = @()
        AssetSpecs = @()
        AppStateSpec = $null
        PackageSpec = $null
        Extensions = $null
        DependsOn = @()
    }
    if ([string]$Platform -eq 'windows' -and $ScriptText -match 'clagnos-package-operations\.psm1') {
        $block.AssetSpecs = @([pscustomobject]@{
            LocalPath = (Join-Path (Get-ClagnosRepoRoot) 'modules/commands/package/clagnos-package-operations.psm1')
            RemotePath = 'C:/Windows/Temp/clagnos-package-operations.psm1'
        })
    }
    $resolvedBlock = Apply-ClagnosTaskBlockReplacements -TaskBlocks @($block) -Replacements (Get-ClagnosTaskTokenReplacements -Context $runtime.Context) -Context $runtime.Context
    if ($transport -eq 'winrm') {
        if ($Platform -ne 'windows') { throw 'PACKAGE_TRANSPORT=winrm is supported only for Windows package operations.' }
        if ($Runtime.Context.PSObject.Properties.Match('PowerShellPort').Count -eq 0) { $Runtime.Context | Add-Member -NotePropertyName PowerShellPort -NotePropertyValue (Get-ClagnosDefaultPowerShellPortText) }
        return (Invoke-ClagnosWinRmTaskBlocks `
            -Platform 'windows' `
            -HostName $sshHost `
            -Runtime $Runtime `
            -Target $Target `
            -TaskBlocks @($resolvedBlock) `
            -TaskOutcomeMode 'strict' `
            -PerfTaskCategory 'task-run')
    }
    $pySsh = Ensure-ClagnosPySshTools -RepoRoot (Get-ClagnosRepoRoot) -ConfiguredPySshClientPath ([string]$Runtime.ConfiguredPySshClientPath)
    return (Invoke-ClagnosSshTaskBlocks `
        -Platform $Platform `
        -RepoRoot (Get-ClagnosRepoRoot) `
        -SshHost $sshHost `
        -SshUser ([string]$Runtime.Context.VmUser) `
        -SshPassword ([string]$Runtime.Context.VmPass) `
        -SshPort ([string]$Runtime.Context.SshPort) `
        -AssistantUser ([string]$Runtime.Context.VmAssistantUser) `
        -ResourceGroup ([string]$Target.ResourceGroup) `
        -VmName ([string]$Target.VmName) `
        -TaskBlocks @($resolvedBlock) `
        -TaskOutcomeMode 'strict' `
        -PerfTaskCategory 'task-run' `
        -SshMaxRetries 1 `
        -SshTaskTimeoutSeconds ([int]$TimeoutSeconds) `
        -SshConnectTimeoutSeconds ([int]$Runtime.SshConnectTimeoutSeconds) `
        -ConfiguredPySshClientPath ([string]$Runtime.ConfiguredPySshClientPath))
}

function Get-ClagnosPackageStatusSnapshot {
    param(
        [object[]]$Packages,
        [hashtable]$Options,
        [string]$Platform,
        [switch]$Force,
        [int]$TimeoutSeconds = 0,
        [psobject]$Runtime = $null,
        [psobject]$Target = $null
    )

    $cacheInfo = Get-ClagnosPackageStatusCacheEntry -Packages $Packages -Options $Options -Platform $Platform
    $key = if ($null -ne $cacheInfo) { [string]$cacheInfo.Key } else { Get-ClagnosPackageStatusCacheKey -Packages $Packages -Options $Options -Platform $Platform }
    if (-not $Force -and $null -ne $cacheInfo -and [bool]$cacheInfo.IsFresh) { return $cacheInfo.Entry.StatusByPackage }
    if ($null -eq $Runtime) { $Runtime = Initialize-ClagnosTaskExecutionRuntimeContext -AutoMode:$false -WindowsFlag:([string]$Platform -eq 'windows') -LinuxFlag:([string]$Platform -eq 'linux') -Options $Options }
    if ($null -eq $Target) { $Target = Resolve-ClagnosManagedVmTarget -Options $Options -ConfigMap $Runtime.EffectiveConfigMap -OperationName 'package' }
    $Runtime.Context.ResourceGroup = [string]$Target.ResourceGroup
    $Runtime.Context.VmName = [string]$Target.VmName
    $requiresStartupDriftCheck = @($Packages | Where-Object { [string]$_.Id -in @('jaws','ollama','docker-desktop') }).Count -gt 0
    $scriptText = if (@($Packages).Count -eq 1 -and -not $requiresStartupDriftCheck -and -not [string]::IsNullOrWhiteSpace([string]$Packages[0].StatusScriptText)) {
        New-ClagnosPackageLifecycleScript -Action 'status' -Package $Packages[0] -Context $Runtime.Context
    }
    else { New-ClagnosPackageGuestScript -Action 'status' -Packages $Packages -Platform $Platform -Context $Runtime.Context }
    $statusTimeoutSeconds = 300
    if (@($Packages).Count -eq 1) { $statusTimeoutSeconds = Get-ClagnosPackageTimeoutSeconds -Package $Packages[0] -Action 'status' }
    else {
        $configuredStatusTimeouts = @($Packages | ForEach-Object { Get-ClagnosPackageTimeoutSeconds -Package $_ -Action 'status' })
        if ($configuredStatusTimeouts.Count -gt 0) { $statusTimeoutSeconds = [int](($configuredStatusTimeouts | Measure-Object -Maximum).Maximum) }
    }
    if ($TimeoutSeconds -gt 0) { $statusTimeoutSeconds = [Math]::Min($statusTimeoutSeconds,[int]$TimeoutSeconds) }
    $result = Invoke-ClagnosPackageGuestScript -Options $Options -Platform $Platform -ScriptText $scriptText -TaskLabel 'package-status' -TimeoutSeconds $statusTimeoutSeconds -Runtime $Runtime -Target $Target
    $output = ''
    if ($result.TaskOutputs.Count -gt 0) { $output = [string]$result.TaskOutputs[0].Output }
    $match = [regex]::Match($output,'(?m)^CLAGNOS_PACKAGE_RESULTS:(?<json>\[.*\])\s*$')
    if (-not $match.Success) {
        $singleMatch = [regex]::Match($output,'(?m)^CLAGNOS_PACKAGE_RESULT:(?<json>\{.*\})\s*$')
        if ($singleMatch.Success) {
            $singleRow = ConvertFrom-JsonCompat -InputObject ([string]$singleMatch.Groups['json'].Value)
            $match = [pscustomobject]@{ Success = $true; Groups = @{ json = [pscustomobject]@{ Value = ('[' + (ConvertTo-Json -InputObject $singleRow -Compress -Depth 8) + ']') } } }
        }
    }
    if (-not $match.Success) { throw 'Package status response could not be read from the VM.' }
    $rows = @(ConvertTo-ObjectArrayCompat -InputObject (ConvertFrom-JsonCompat -InputObject ([string]$match.Groups['json'].Value)))
    $map = @{}
    foreach ($row in @($rows)) {
        $rowStatus = [string]$row.status
        if ($rowStatus -eq 'installed' -and [string]$row.detail -match '(?i)missing|not verified') { $rowStatus = 'installed-drifted' }
        $map[[string]$row.id] = $rowStatus
    }
    $entry = @{ CreatedAtUtc = [DateTime]::UtcNow; Complete = $true; StatusByPackage = $map }
    $script:ClagnosPackageStatusCache[$key] = $entry
    Save-ClagnosPackageStatusCacheEntry -Key $key -Entry $entry
    return $map
}

function Get-ClagnosPackageStatus {
    param([object]$Package, [psobject]$Vm)
    $options = @{
        group = [string]$Vm.ClagnosResourceGroup
        'vm-name' = [string]$Vm.name
        'subscription-id' = [string]$Vm.ClagnosSubscriptionId
    }
    $platform = if ([string]::Equals([string]$Vm.storageProfile.osDisk.osType,'Windows',[System.StringComparison]::OrdinalIgnoreCase)) { 'windows' } else { 'linux' }
    $catalog = @(Get-ClagnosPackageCatalog -Platform $platform -Catalog ([string]$Package.Catalog))
    $snapshot = Get-ClagnosPackageStatusSnapshot -Packages $catalog -Options $options -Platform $platform
    if ($snapshot.ContainsKey([string]$Package.Id)) { return [string]$snapshot[[string]$Package.Id] }
    return 'unknown'
}

function Set-ClagnosPackageStatusCacheValue {
    param(
        [object[]]$Packages,
        [hashtable]$Options,
        [string]$Platform,
        [string]$PackageId,
        [string]$Status,
        [switch]$RefreshTimestamp,
        [switch]$MarkIncomplete
    )

    $key = Get-ClagnosPackageStatusCacheKey -Packages $Packages -Options $Options -Platform $Platform
    if ($null -eq $script:ClagnosPackageStatusCache) { $script:ClagnosPackageStatusCache = @{} }
    if (-not $script:ClagnosPackageStatusCache.ContainsKey($key)) {
        $initialStatuses = @{}
        foreach ($candidatePackage in @($Packages)) { $initialStatuses[[string]$candidatePackage.Id] = 'unknown' }
        $script:ClagnosPackageStatusCache[$key] = @{ CreatedAtUtc = [DateTime]::UtcNow; Complete = $false; StatusByPackage = $initialStatuses }
    }
    $entry = $script:ClagnosPackageStatusCache[$key]
    if ($null -eq $entry.StatusByPackage) { return }
    $entry.StatusByPackage[[string]$PackageId] = [string]$Status
    if ($RefreshTimestamp) { $entry.CreatedAtUtc = [DateTime]::UtcNow }
    if ($MarkIncomplete) { $entry.Complete = $false }
    Save-ClagnosPackageStatusCacheEntry -Key $key -Entry $entry
}

function Clear-ClagnosPackageStatusCache {
    $script:ClagnosPackageStatusCache = @{}
}

function Get-ClagnosPackageDependencyOrder {
    param([object[]]$Packages)

    $remaining = New-Object 'System.Collections.Generic.List[object]'
    foreach ($package in @($Packages | Sort-Object @{ Expression = { [int]$_.SortOrder } }, { [string]$_.DisplayName })) { $remaining.Add($package) }
    $ordered = New-Object 'System.Collections.Generic.List[object]'
    while ($remaining.Count -gt 0) {
        $ready = @($remaining | Where-Object {
            $candidate = $_
            $dependencies = @($candidate.PackageTask.DependsOn | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
            foreach ($dependency in $dependencies) {
                $matching = @($Packages | Where-Object { [string]::Equals([string]$_.Id,$dependency,[System.StringComparison]::OrdinalIgnoreCase) })
                if ($matching.Count -eq 0) { continue }
                if (@($ordered | Where-Object { [string]::Equals([string]$_.Id,$dependency,[System.StringComparison]::OrdinalIgnoreCase) }).Count -eq 0) { return $false }
            }
            return $true
        })
        if ($ready.Count -eq 0) { throw 'Package dependencies contain a cycle; setup-all was stopped before making changes.' }
        foreach ($package in @($ready)) {
            $ordered.Add($package)
            [void]$remaining.Remove($package)
        }
    }
    return @($ordered.ToArray())
}

function New-ClagnosPackageSetupPlan {
    param(
        [object[]]$Packages,
        [hashtable]$Options,
        [ValidateSet('windows','linux')][string]$Platform,
        [switch]$AutoMode,
        [switch]$WindowsFlag,
        [switch]$LinuxFlag
    )

    $runtime = Initialize-ClagnosTaskExecutionRuntimeContext -AutoMode:$AutoMode -WindowsFlag:$WindowsFlag -LinuxFlag:$LinuxFlag -Options $Options
    $target = Resolve-ClagnosManagedVmTarget -Options $Options -ConfigMap $runtime.EffectiveConfigMap -OperationName 'package'
    $runtime.Context.ResourceGroup = [string]$target.ResourceGroup
    $runtime.Context.VmName = [string]$target.VmName
    $Options['group'] = [string]$target.ResourceGroup
    $Options['vm-name'] = [string]$target.VmName
    $resolvedSubscription = Get-ClagnosResolvedSubscriptionContext
    if ($null -ne $resolvedSubscription) { $Options['subscription-id'] = [string]$resolvedSubscription.SubscriptionId }

    $orderedPackages = @(Get-ClagnosPackageDependencyOrder -Packages $Packages)
    $enabledPackages = @($orderedPackages | Where-Object { [bool]$_.Enabled })
    $statusByPackage = @{}
    if ($enabledPackages.Count -gt 0) {
        $statusByPackage = Get-ClagnosPackageStatusSnapshot -Packages $enabledPackages -Options $Options -Platform $Platform -Force -Runtime $runtime -Target $target
    }
    $rows = @(
        foreach ($package in @($orderedPackages)) {
            $status = if ([bool]$package.Enabled) {
                if ($statusByPackage.ContainsKey([string]$package.Id)) { [string]$statusByPackage[[string]$package.Id] } else { 'unknown' }
            }
            else { 'disabled' }
            $action = switch ($status) {
                'not-installed' { 'install' }
                'installed' { 'already-healthy' }
                'installed-drifted' { 'repair' }
                'disabled' { 'skip-disabled' }
                default { 'skip-unknown' }
            }
            $dependencies = @(
                @($package.PackageTask.DependsOn) |
                    ForEach-Object { [string]$_ } |
                    Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
            )
            if ($action -eq 'skip-unknown' -and $dependencies.Count -gt 0) { $action = 'recheck-after-dependencies' }
            [pscustomobject]@{
                Package = $package
                Status = $status
                Action = $action
                Reason = switch ($action) {
                    'install' { 'Package is absent; install it.' }
                    'already-healthy' { 'Package is installed; leave its current version and user state unchanged.' }
                    'repair' { 'A Clagnos-managed startup setting is missing; repair the installed version.' }
                    'recheck-after-dependencies' { 'Status is unknown until its declared dependencies are installed; recheck before deciding whether to install.' }
                    'skip-disabled' { 'Package is disabled in its catalog.' }
                    default { 'Status is unknown; no package mutation is safe.' }
                }
            }
        }
    )
    return [pscustomobject]@{
        Platform = $Platform
        Packages = @($orderedPackages)
        Rows = @($rows)
        StatusByPackage = $statusByPackage
        Runtime = $runtime
        Target = $target
        Options = $Options
        AutoMode = [bool]$AutoMode
    }
}

function Invoke-ClagnosPackageSetupPlan {
    param([Parameter(Mandatory = $true)][psobject]$Plan)

    $results = New-Object 'System.Collections.Generic.List[object]'
    $effectiveStatus = @{}
    foreach ($key in @($Plan.StatusByPackage.Keys)) { $effectiveStatus[[string]$key] = [string]$Plan.StatusByPackage[[string]$key] }
    foreach ($row in @($Plan.Rows)) {
        $package = $row.Package
        $dependencies = @(
            @($package.PackageTask.DependsOn) |
                ForEach-Object { [string]$_ } |
                Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
        )
        $action = [string]$row.Action
        if ($action -eq 'recheck-after-dependencies') {
            $blocked = @($dependencies | Where-Object {
                $dependency = [string]$_
                if (-not $effectiveStatus.ContainsKey($dependency)) { return $true }
                return ([string]$effectiveStatus[$dependency] -notin @('installed','installed-drifted'))
            } | Select-Object -First 1)
            if ($blocked.Count -gt 0) {
                $message = "Skipped because dependency '$($blocked[0])' is not verified as installed."
                $effectiveStatus[[string]$package.Id] = 'blocked'
                $results.Add([pscustomobject]@{ Package = $package; Outcome = 'skipped'; Message = $message })
                Write-Warning ("Package setup skipped for {0}: {1}" -f [string]$package.DisplayName,$message)
                continue
            }
            try {
                Write-ClagnosActionProgress -Action ("recheck package '{0}' after its dependencies were verified" -f [string]$package.Id)
                $refreshedStatus = Get-ClagnosPackageStatusSnapshot -Packages @($package) -Options $Plan.Options -Platform $Plan.Platform -Force -Runtime $Plan.Runtime -Target $Plan.Target
                $action = switch ([string]$refreshedStatus[[string]$package.Id]) {
                    'not-installed' { 'install' }
                    'installed' { 'already-healthy' }
                    'installed-drifted' { 'repair' }
                    default { 'skip-unknown' }
                }
                $effectiveStatus[[string]$package.Id] = [string]$refreshedStatus[[string]$package.Id]
                if ($action -eq 'already-healthy') {
                    $results.Add([pscustomobject]@{ Package = $package; Outcome = 'already-healthy'; Message = 'Package is installed; no repair or vendor upgrade was needed.' })
                    Write-Host ("Package setup verified: {0} (already healthy after dependency recheck)" -f [string]$package.DisplayName) -ForegroundColor Green
                    continue
                }
                if ($action -eq 'skip-unknown') {
                    $message = 'Package status remains unknown after its dependencies were installed; no package mutation is safe.'
                    $results.Add([pscustomobject]@{ Package = $package; Outcome = 'skip-unknown'; Message = $message })
                    Write-Warning ("Package setup skipped for {0}: {1}" -f [string]$package.DisplayName,$message)
                    continue
                }
            }
            catch {
                $effectiveStatus[[string]$package.Id] = 'unknown'
                $message = [string]$_.Exception.Message
                $results.Add([pscustomobject]@{ Package = $package; Outcome = 'skip-unknown'; Message = $message })
                Write-Warning ("Package status recheck failed for {0}: {1}" -f [string]$package.DisplayName,$message)
                continue
            }
        }
        if ($action -notin @('install','repair')) {
            $results.Add([pscustomobject]@{ Package = $package; Outcome = $action; Message = [string]$row.Reason })
            continue
        }
        $blockedDependency = @($dependencies | Where-Object {
            $dependency = [string]$_
            if (-not $effectiveStatus.ContainsKey($dependency)) { return $true }
            return ([string]$effectiveStatus[$dependency] -notin @('installed','installed-drifted'))
        } | Select-Object -First 1)
        if ($blockedDependency.Count -gt 0) {
            $message = "Skipped because dependency '$($blockedDependency[0])' is not verified as installed."
            $effectiveStatus[[string]$package.Id] = 'blocked'
            $results.Add([pscustomobject]@{ Package = $package; Outcome = 'skipped'; Message = $message })
            Write-Warning ("Package setup skipped for {0}: {1}" -f [string]$package.DisplayName,$message)
            continue
        }

        try {
            $packageAppState = Get-ClagnosTaskAppStatePluginInfo -TaskBlock ([psobject]$package.PackageTask)
            if ([string]::Equals([string]$packageAppState.Status,'invalid',[System.StringComparison]::OrdinalIgnoreCase)) {
                throw ("Package app-state archive is invalid: {0}" -f [string]$packageAppState.Message)
            }
            if ([string]::Equals([string]$packageAppState.Status,'ready',[System.StringComparison]::OrdinalIgnoreCase)) {
                Assert-ClagnosPackageAppStateArchivePortable -ZipPath ([string]$packageAppState.ZipPath)
            }
            $installTask = [pscustomobject]@{}
            foreach ($property in @($package.PackageTask.PSObject.Properties)) { $installTask | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value }
            $packageAction = if ($action -eq 'repair') { 'repair' } else { 'install' }
            if ($packageAction -eq 'repair' -and $installTask.PSObject.Properties['AppStateSpec']) { $installTask.AppStateSpec = $null }
            if ([string]$Plan.Platform -eq 'windows') { $installTask.Script = New-ClagnosPackageLifecycleScript -Action $packageAction -Package $package -Context $Plan.Runtime.Context }
            $run = Invoke-ClagnosTaskExecutionWithTarget -Runtime $Plan.Runtime -Options $Plan.Options -OperationName 'package' -Stage 'update' -Requested ([string]$package.Id) -PackageTaskBlock $installTask -AutoMode:([bool]$Plan.AutoMode) -TaskOutcomeModeOverride 'strict'
            if ([string]$Plan.Platform -eq 'windows') {
                $structured = Get-ClagnosPackageStructuredResult -TaskResult $run
                if ($null -eq $structured -or [string]$structured.status -ne 'installed') {
                    $message = if ($null -ne $structured) { [string]$structured.message } else { 'No structured install verification was returned.' }
                    throw ("Package {0} did not verify: {1}" -f $packageAction,$message)
                }
            }
            $effectiveStatus[[string]$package.Id] = 'installed'
            $successOutcome = if ($packageAction -eq 'repair') { 'repaired' } else { 'installed' }
            $results.Add([pscustomobject]@{ Package = $package; Outcome = $successOutcome; Message = ('{0} and verified.' -f $successOutcome) })
            Write-Host ("Package setup verified: {0} ({1})" -f [string]$package.DisplayName,$successOutcome) -ForegroundColor Green
        }
        catch {
            $effectiveStatus[[string]$package.Id] = 'failed'
            $message = [string]$_.Exception.Message
            $results.Add([pscustomobject]@{ Package = $package; Outcome = 'failed'; Message = $message })
            Write-Warning ("Package setup failed for {0}: {1}" -f [string]$package.DisplayName,$message)
        }
    }
    $failed = @($results.ToArray() | Where-Object { [string]$_.Outcome -eq 'failed' }).Count
    $skipped = @($results.ToArray() | Where-Object { [string]$_.Outcome -in @('skipped','skip-disabled','skip-unknown') }).Count
    $installed = @($results.ToArray() | Where-Object { [string]$_.Outcome -eq 'installed' }).Count
    $repaired = @($results.ToArray() | Where-Object { [string]$_.Outcome -eq 'repaired' }).Count
    if ($failed -eq 0 -and $skipped -eq 0) { Write-Host ("Setup all completed: installed={0}, repaired={1}, failed=0, skipped=0." -f $installed,$repaired) -ForegroundColor Green }
    else { Write-Host ("Setup all completed with warnings: installed={0}, repaired={1}, failed={2}, skipped={3}. Review the package results above." -f $installed,$repaired,$failed,$skipped) -ForegroundColor Yellow }
    return [pscustomobject]@{ Installed = $installed; Repaired = $repaired; Failed = $failed; Skipped = $skipped; Results = @($results.ToArray()) }
}

function Invoke-ClagnosPackageSetupAll {
    param(
        [hashtable]$Options,
        [switch]$AutoMode,
        [switch]$WindowsFlag,
        [switch]$LinuxFlag
    )

    Write-ClagnosActionProgress -Action 'review enabled builtin and custom packages for setup-all'
    $runtime = Initialize-ClagnosTaskCommandRuntimeContext -AutoMode:$AutoMode -WindowsFlag:$WindowsFlag -LinuxFlag:$LinuxFlag -Options $Options
    $platform = [string]$runtime.Platform
    $packages = @(
        @(Get-ClagnosPackageCatalog -Platform $platform -Catalog 'builtin') +
        @(Get-ClagnosPackageCatalog -Platform $platform -Catalog 'custom')
    )
    if ($packages.Count -eq 0) { throw ("No builtin or custom packages are available for platform '{0}'." -f $platform) }

    $plan = New-ClagnosPackageSetupPlan -Packages $packages -Options $Options -Platform $platform -AutoMode:$AutoMode -WindowsFlag:$WindowsFlag -LinuxFlag:$LinuxFlag
    Write-Host ''
    Write-Host ("Package setup plan for {0} VM '{1}' in resource group '{2}':" -f $platform,[string]$plan.Target.VmName,[string]$plan.Target.ResourceGroup) -ForegroundColor Cyan
    foreach ($row in @($plan.Rows)) {
        Write-Host ("- [{0}] {1}: {2} ({3})" -f [string]$row.Package.Catalog,[string]$row.Package.DisplayName,[string]$row.Action,[string]$row.Reason)
    }

    $approved = Get-ClagnosCliOptionBool -Options $Options -Name 'yes' -DefaultValue $false
    if (-not $approved) {
        $confirmation = Read-Host 'Type SETUP ALL to apply this package plan'
        if (-not [string]::Equals([string]$confirmation,'SETUP ALL',[System.StringComparison]::Ordinal)) {
            Write-Host 'Package setup-all canceled; no packages were changed.' -ForegroundColor Yellow
            return [pscustomobject]@{ Installed = 0; Repaired = 0; Failed = 0; Skipped = 0; Cancelled = $true; Results = @() }
        }
    }

    $result = Invoke-ClagnosPackageSetupPlan -Plan $plan
    $unsafe = @($result.Results | Where-Object { [string]$_.Outcome -in @('failed','skipped','skip-unknown') })
    if ($unsafe.Count -gt 0) {
        $names = @($unsafe | ForEach-Object { [string]$_.Package.DisplayName }) -join ', '
        Throw-FriendlyError `
            -Detail ("Package setup-all left one or more enabled packages unverified: {0}." -f $names) `
            -Code 66 `
            -Summary 'Package setup-all did not verify every enabled package.' `
            -Hint 'Review the per-package results, resolve the reported issue, and rerun setup-all.'
    }
    return $result
}

function Restart-ClagnosPackageVmForPendingReboot {
    param([psobject]$Runtime,[psobject]$Target,[hashtable]$Options,[switch]$AutoMode,[switch]$WindowsFlag,[switch]$LinuxFlag)

    $subscription = Get-ClagnosResolvedSubscriptionContext
    $subscriptionId = if ($null -ne $subscription) { [string]$subscription.SubscriptionId } else { [string](Get-ClagnosCliOptionText -Options $Options -Name 'subscription-id') }
    Write-ClagnosActionProgress -Action ("restart VM '{0}' because its completed package uninstall requested a reboot" -f [string]$Target.VmName)
    $restartArgs = @(
        '--vm-action=restart',
        ('--group={0}' -f [string]$Target.ResourceGroup),
        ('--vm-name={0}' -f [string]$Target.VmName),
        ('--subscription-id={0}' -f $subscriptionId)
    )
    $parsedRestart = Parse-ClagnosCliArguments -CommandToken 'do' -RawArgs $restartArgs
    Invoke-ClagnosCommandDispatcher -CommandName 'do' -Options ([hashtable]$parsedRestart.Options) -HelpTopic ([string]$parsedRestart.HelpTopic)

    $nextRuntime = Initialize-ClagnosTaskExecutionRuntimeContext -AutoMode:$AutoMode -WindowsFlag:$WindowsFlag -LinuxFlag:$LinuxFlag -Options $Options
    $nextTarget = Resolve-ClagnosManagedVmTarget -Options $Options -ConfigMap $nextRuntime.EffectiveConfigMap -OperationName 'package'
    $nextRuntime.Context.ResourceGroup = [string]$nextTarget.ResourceGroup
    $nextRuntime.Context.VmName = [string]$nextTarget.VmName
    $vmDetails = Get-ClagnosVmDetails -Context $nextRuntime.Context -AllowCachedInventory
    $hostName = [string]$vmDetails.VmFqdn
    if ([string]::IsNullOrWhiteSpace($hostName)) { $hostName = [string]$vmDetails.PublicIP }
    if ([string]::IsNullOrWhiteSpace($hostName)) { throw 'The VM restarted for package servicing, but its guest endpoint could not be resolved.' }
    $transport = Get-ClagnosPackageTransport -ConfigMap ([hashtable]$nextRuntime.EffectiveConfigMap)
    if ($transport -eq 'winrm') {
        $port = if ($nextRuntime.Context.PSObject.Properties.Match('PowerShellPort').Count -gt 0) { [int]$nextRuntime.Context.PowerShellPort } else { 5985 }
        if (-not (Wait-ClagnosTcpPortReachable -HostName $hostName -Port $port -MaxAttempts 40 -DelaySeconds 15 -TimeoutSeconds 5 -Label 'WinRM after package-requested reboot')) {
            throw 'WinRM did not become reachable within 10 minutes after the package-requested VM restart.'
        }
    }
    else {
        $port = if ($nextRuntime.Context.PSObject.Properties.Match('SshPort').Count -gt 0) { [int]$nextRuntime.Context.SshPort } else { 22 }
        if (-not (Wait-ClagnosTcpPortReachable -HostName $hostName -Port $port -MaxAttempts 40 -DelaySeconds 15 -TimeoutSeconds 5 -Label 'SSH after package-requested reboot')) {
            throw 'SSH did not become reachable within 10 minutes after the package-requested VM restart.'
        }
    }
    return [pscustomobject]@{ Runtime = $nextRuntime; Target = $nextTarget }
}

function Invoke-ClagnosPackageOperation {
    param(
        [string]$Action,
        [string]$PackageId,
        [ValidateSet('builtin','custom')][string]$Catalog,
        [string]$CatalogRoot = '',
        [hashtable]$Options,
        [switch]$AutoMode,
        [switch]$WindowsFlag,
        [switch]$LinuxFlag
    )

    if ([string]::IsNullOrWhiteSpace($PackageId) -and $Action -ne 'list') { throw 'A package id is required for this action.' }
    $packageProgressTarget = if ([string]::IsNullOrWhiteSpace($PackageId)) { 'catalog' } else { "package '$PackageId'" }
    Write-ClagnosActionProgress -Action ("{0} {1} in {2} catalog" -f [string]$Action,[string]$packageProgressTarget,[string]$Catalog)
    $catalogOnlyAction = $Action -in @('enable','disable') -or
        ($Action -in @('install','repair','update','reinstall') -and ($WindowsFlag -or $LinuxFlag))
    $taskRuntime = $null
    if ($catalogOnlyAction) {
        # Availability and disabled-package checks use the global catalog platform;
        # they must not require Azure access or a valid active VC profile.
        $repoRoot = Get-ClagnosRepoRoot
        $envFilePath = Join-Path $repoRoot 'clagnos.env'
        $globalConfigMap = Read-DotEnvFile -Path $envFilePath -GlobalOnly
        $catalogConfigMap = Merge-ClagnosVmEnvironmentConfig -GlobalConfigMap $globalConfigMap -IgnoreActiveSelection
        $platform = Resolve-ClagnosPlatformSelection -ConfigMap $catalogConfigMap -EnvFilePath $envFilePath -AutoMode:$AutoMode -WindowsFlag:$WindowsFlag -LinuxFlag:$LinuxFlag -ConfigOverrides $script:ConfigOverrides -DeferEnvWrite
    }
    else {
        $taskRuntime = Initialize-ClagnosTaskCommandRuntimeContext -AutoMode:$AutoMode -WindowsFlag:$WindowsFlag -LinuxFlag:$LinuxFlag -Options $Options
        $platform = [string]$taskRuntime.Platform
    }
    $packagesInCatalog = @(Get-ClagnosPackageCatalog -Platform $platform -Catalog $Catalog -CatalogRoot $CatalogRoot)
    if (@($packagesInCatalog).Count -eq 0 -and $Action -eq 'list') { Write-Host ("The {0} package catalog is empty for '{1}'." -f $Catalog, $platform) -ForegroundColor Yellow; return }
    if ($Action -in @('enable','disable')) {
        $selected = @($packagesInCatalog | Where-Object { [string]::Equals([string]$_.Id,[string]$PackageId,[System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
        if ($selected.Count -ne 1) { throw ("Package '{0}' was not found in the {1} catalog for {2}." -f $PackageId, $Catalog, $platform) }
        $package = $selected[0]
        $shouldEnable = $Action -eq 'enable'
        if ([bool]$package.Enabled -eq $shouldEnable) {
            Write-Host ("Package '{0}' is already {1}." -f $package.DisplayName, $(if ($shouldEnable) { 'enabled' } else { 'disabled' })) -ForegroundColor Yellow
            return [pscustomobject]@{ Package = $package; Enabled = [bool]$package.Enabled; Changed = $false }
        }
        $token = if ($shouldEnable) { 'ENABLE' } else { 'DISABLE' }
        $answer = Read-Host ("This changes the shared {0} package catalog for future VC operations. Type {1} to confirm {2} '{3}'" -f $Catalog, $token, $Action, $package.DisplayName)
        if (-not [string]::Equals([string]$answer, $token, [System.StringComparison]::Ordinal)) {
            Write-Host 'Package availability change canceled; no files were changed.' -ForegroundColor Yellow
            return [pscustomobject]@{ Package = $package; Enabled = [bool]$package.Enabled; Changed = $false }
        }
        Set-ClagnosTaskCatalogEnabled -Path ([string]$package.CatalogPath) -TaskId ([string]$package.Id) -Enabled $shouldEnable
        $verified = @(Get-ClagnosPackageCatalog -Platform $platform -Catalog $Catalog -CatalogRoot $CatalogRoot | Where-Object { [string]::Equals([string]$_.Id,[string]$PackageId,[System.StringComparison]::OrdinalIgnoreCase) })
        if ($verified.Count -ne 1 -or [bool]$verified[0].Enabled -ne $shouldEnable) { throw ("Package availability verification failed for '{0}'." -f $PackageId) }
        Write-Host ("Package '{0}' is now {1}." -f $package.DisplayName, $(if ($shouldEnable) { 'enabled' } else { 'disabled' })) -ForegroundColor Green
        return [pscustomobject]@{ Package = $verified[0]; Enabled = [bool]$shouldEnable; Changed = $true }
    }

    $catalogRuntime = @(Get-ClagnosPackageCatalog -Platform $platform -Catalog $Catalog -CatalogRoot $CatalogRoot)
    if ($Action -eq 'list') {
        $runtime = Initialize-ClagnosTaskExecutionRuntimeContext -AutoMode:$AutoMode -WindowsFlag:$WindowsFlag -LinuxFlag:$LinuxFlag -Options $Options
        $target = Resolve-ClagnosManagedVmTarget -Options $Options -ConfigMap $runtime.EffectiveConfigMap -OperationName 'package'
        $runtime.Context.ResourceGroup = [string]$target.ResourceGroup
        $runtime.Context.VmName = [string]$target.VmName
        $Options['group'] = [string]$target.ResourceGroup
        $Options['vm-name'] = [string]$target.VmName
        $Options['subscription-id'] = [string](Get-ClagnosResolvedSubscriptionContext).SubscriptionId
        $packageList = Get-ClagnosPackageStatusSnapshot -Packages $catalogRuntime -Options $Options -Platform $platform -Runtime $runtime -Target $target
        foreach ($package in @($catalogRuntime)) {
            $availability = if ([bool]$package.Enabled) { 'enabled' } else { ('disabled: ' + [string]$package.DisabledReason) }
            Write-Host ("{0} [{1}] | {2} | {3} | {4}" -f [string]$package.DisplayName,$Catalog,[string]$package.Category,$availability,[string]$packageList[[string]$package.Id])
        }
        return
    }
    $selected = @($catalogRuntime | Where-Object { [string]::Equals([string]$_.Id,[string]$PackageId,[System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
    if (@($selected).Count -eq 0) { throw ("Package '{0}' was not found in the {1} catalog for {2}." -f $PackageId,$Catalog,$platform) }
    $package = $selected[0]
    if ($Action -in @('install','repair','update','reinstall') -and -not [bool]$package.Enabled) {
        throw ("'{0}' is disabled in the {1} package catalog. Enable it before installing, repairing, or updating it." -f [string]$package.DisplayName,$Catalog)
    }
    if ($Action -notin @('status','install','repair','update','uninstall','reinstall')) { throw ("Unsupported package action '{0}'." -f $Action) }
    if ($Action -in @('uninstall','reinstall') -and $null -ne $package.UninstallPolicy -and $null -ne $package.UninstallPolicy.PSObject.Properties['supported'] -and -not [bool]$package.UninstallPolicy.supported) {
        $reason = [string]$package.UninstallPolicy.reason
        if ([string]::IsNullOrWhiteSpace($reason)) { $reason = 'This package cannot be safely removed on the selected Windows image.' }
        Throw-FriendlyError -Detail $reason -Code 66 -Summary ("'{0}' cannot be uninstalled on this Windows image." -f [string]$package.DisplayName) -Hint 'Keep the protected Windows component installed. Install, repair, update, and status remain available.'
    }
    if ($null -eq $taskRuntime) {
        $taskRuntime = Initialize-ClagnosTaskCommandRuntimeContext -AutoMode:$AutoMode -WindowsFlag:$WindowsFlag -LinuxFlag:$LinuxFlag -Options $Options
        $platform = [string]$taskRuntime.Platform
    }
    $runtime = Initialize-ClagnosTaskExecutionRuntimeContext -AutoMode:$AutoMode -WindowsFlag:$WindowsFlag -LinuxFlag:$LinuxFlag -Options $Options
    $target = Resolve-ClagnosManagedVmTarget -Options $Options -ConfigMap $runtime.EffectiveConfigMap -OperationName 'package'
    $runtime.Context.ResourceGroup = [string]$target.ResourceGroup
    $runtime.Context.VmName = [string]$target.VmName
    $resolvedSubscription = Get-ClagnosResolvedSubscriptionContext
    if ($null -ne $resolvedSubscription) { $Options['subscription-id'] = [string]$resolvedSubscription.SubscriptionId }
    if ($Action -eq 'status') {
        $requiresStartupDriftCheck = [string]$package.Id -in @('jaws','ollama','docker-desktop')
        $statusScriptText = if (-not $requiresStartupDriftCheck -and -not [string]::IsNullOrWhiteSpace([string]$package.StatusScriptText)) { New-ClagnosPackageLifecycleScript -Action 'status' -Package $package -Context $runtime.Context } else { New-ClagnosPackageGuestScript -Action 'status' -Packages @($package) -Platform $platform -Context $runtime.Context }
        $statusResult = Invoke-ClagnosPackageGuestScript -Options $Options -Platform $platform -ScriptText $statusScriptText -TaskLabel ('package-status-' + [string]$package.Id) -TimeoutSeconds (Get-ClagnosPackageTimeoutSeconds -Package $package -Action 'status') -Runtime $runtime -Target $target
        $statusOutput = if ($statusResult.TaskOutputs.Count -gt 0) { [string]$statusResult.TaskOutputs[0].Output } else { '' }
        $singleStatusMatch = [regex]::Match($statusOutput,'(?m)^CLAGNOS_PACKAGE_RESULT:(?<json>\{.*\})\s*$')
        $status = ''
        if ($singleStatusMatch.Success) {
            $statusRecord = ConvertFrom-JsonCompat -InputObject ([string]$singleStatusMatch.Groups['json'].Value)
            $status = [string]$statusRecord.status
            $statusMessage = [string]$statusRecord.message
            if ($status -eq 'installed' -and ([string]$statusRecord.detail + ' ' + [string]$statusMessage) -match '(?i)missing|not verified') { $status = 'installed-drifted' }
            if (-not [string]::IsNullOrWhiteSpace([string]$statusRecord.version)) { $statusMessage += (' Version: {0}.' -f [string]$statusRecord.version) }
            Write-Host ("{0}: {1}" -f [string]$package.DisplayName,$statusMessage)
        }
        else {
            $batchStatusMatch = [regex]::Match($statusOutput,'(?m)^CLAGNOS_PACKAGE_RESULTS:(?<json>\[.*\])\s*$')
            if (-not $batchStatusMatch.Success) { throw 'Package status response could not be read from the VM.' }
            $statusRow = @(ConvertTo-ObjectArrayCompat -InputObject (ConvertFrom-JsonCompat -InputObject ([string]$batchStatusMatch.Groups['json'].Value)) | Where-Object { [string]::Equals([string]$_.id,[string]$package.Id,[System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
            if ($statusRow.Count -ne 1) { throw 'Package status response did not include the selected package.' }
            $status = [string]$statusRow[0].status
            if ($status -eq 'installed' -and [string]$statusRow[0].detail -match '(?i)missing|not verified') { $status = 'installed-drifted' }
            Write-Host ("{0}: {1}" -f [string]$package.DisplayName,$status)
        }
        Set-ClagnosPackageStatusCacheValue -Packages $catalogRuntime -Options $Options -Platform $platform -PackageId ([string]$package.Id) -Status $status -RefreshTimestamp
        return
    }
    if ($Action -in @('install','repair')) {
        $actionDeadlineUtc = [DateTime]::UtcNow.AddSeconds((Get-ClagnosPackageTimeoutSeconds -Package $package -Action $Action))
        $remainingBeforeStatus = [int][Math]::Floor(($actionDeadlineUtc - [DateTime]::UtcNow).TotalSeconds)
        if ($remainingBeforeStatus -lt 30) { throw ("Package {0} ended before its preflight status check." -f $Action) }
        $before = Get-ClagnosPackageStatusSnapshot -Packages @($package) -Options $Options -Platform $platform -Force -TimeoutSeconds $remainingBeforeStatus -Runtime $runtime -Target $target
        $beforeStatus = [string]$before[[string]$package.Id]
        $effectivePackageAction = [string]$Action
        if ($beforeStatus -eq 'installed-drifted') { $beforeStatus = 'installed' }
        if ($Action -eq 'install' -and $beforeStatus -eq 'installed') {
            Write-Host ("{0} is already installed on VM '{1}'; no install operation was run." -f [string]$package.DisplayName,[string]$target.VmName) -ForegroundColor Cyan
            return [pscustomobject]@{ Package = $package; Action = 'install'; Status = 'installed'; Changed = $false }
        }
        if ($effectivePackageAction -eq 'install' -and $beforeStatus -ne 'not-installed') { throw ("Cannot safely install '{0}' because its current status is {1}." -f [string]$package.DisplayName,$beforeStatus) }
        if ($effectivePackageAction -eq 'repair' -and $beforeStatus -ne 'installed') { throw ("Cannot safely repair '{0}' because its current status is {1}; use install for an absent package." -f [string]$package.DisplayName,$beforeStatus) }
        if ($effectivePackageAction -eq 'repair' -and $platform -ne 'windows') { throw 'Same-version package repair is not yet defined for this platform; no package installer was run.' }
        $packageAppState = Get-ClagnosTaskAppStatePluginInfo -TaskBlock ([psobject]$package.PackageTask)
        if ([string]::Equals([string]$packageAppState.Status, 'invalid', [System.StringComparison]::OrdinalIgnoreCase)) {
            throw ("Package '{0}' has an invalid app-state archive: {1}" -f [string]$package.DisplayName, [string]$packageAppState.Message)
        }
        if ([string]::Equals([string]$packageAppState.Status, 'ready', [System.StringComparison]::OrdinalIgnoreCase)) {
            Assert-ClagnosPackageAppStateArchivePortable -ZipPath ([string]$packageAppState.ZipPath)
        }
        $installTask = [pscustomobject]@{}
        foreach ($property in @($package.PackageTask.PSObject.Properties)) { $installTask | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value }
        if ($effectivePackageAction -eq 'repair' -and $installTask.PSObject.Properties['AppStateSpec']) { $installTask.AppStateSpec = $null }
        if ($platform -eq 'windows') { $installTask.Script = New-ClagnosPackageLifecycleScript -Action $effectivePackageAction -Package $package -Context $runtime.Context }
        $remainingInstallSeconds = [int][Math]::Floor(($actionDeadlineUtc - [DateTime]::UtcNow).TotalSeconds)
        if ($remainingInstallSeconds -lt 30) { throw ("Package {0} ended before its {1} phase." -f $Action,$effectivePackageAction) }
        $installTask.TimeoutSeconds = [Math]::Min((Get-ClagnosPackageTimeoutSeconds -Package $package -Action $effectivePackageAction),$remainingInstallSeconds)
        $run = Invoke-ClagnosTaskExecutionWithTarget -Runtime $runtime -Options $Options -OperationName 'package' -Stage 'update' -Requested ([string]$package.Id) -PackageTaskBlock $installTask -AutoMode:$AutoMode -TaskOutcomeModeOverride 'strict'
        $structuredResult = if ($platform -eq 'windows') { Get-ClagnosPackageStructuredResult -TaskResult $run } else { $null }
        if ($platform -eq 'windows' -and ($null -eq $structuredResult -or [string]$structuredResult.status -ne 'installed')) {
            $detail = if ($null -ne $structuredResult) { [string]$structuredResult.message } else { 'No structured package lifecycle result was returned.' }
            throw ("Package {0} result verification failed for '{1}': {2}" -f $effectivePackageAction,[string]$package.DisplayName,$detail)
        }
        $afterStatus = if ($platform -eq 'windows') { [string]$structuredResult.status } else {
            $after = Get-ClagnosPackageStatusSnapshot -Packages @($package) -Options $Options -Platform $platform -Force -Runtime $runtime -Target $target
            [string]$after[[string]$package.Id]
        }
        Set-ClagnosPackageStatusCacheValue -Packages $catalogRuntime -Options $Options -Platform $platform -PackageId ([string]$package.Id) -Status $afterStatus -RefreshTimestamp -MarkIncomplete
        if ($afterStatus -ne 'installed') { throw ("Install script completed but '{0}' status verification returned {1}." -f [string]$package.DisplayName,$afterStatus) }
        $installMessage = if ($null -ne $structuredResult -and -not [string]::IsNullOrWhiteSpace([string]$structuredResult.message)) { [string]$structuredResult.message } else { ("Package {0} completed for {1}; target status verified." -f $effectivePackageAction,[string]$package.DisplayName) }
        Write-Host $installMessage -ForegroundColor Green
        return $run
    }
    if ($Action -eq 'update') {
        if ($platform -ne 'windows') { throw 'Separate package update scripts are currently supported only by the Windows package catalogs.' }
        $actionDeadlineUtc = [DateTime]::UtcNow.AddSeconds((Get-ClagnosPackageTimeoutSeconds -Package $package -Action 'update'))
        $remainingBeforeStatus = [int][Math]::Floor(($actionDeadlineUtc - [DateTime]::UtcNow).TotalSeconds)
        if ($remainingBeforeStatus -lt 30) { throw 'Package update ended before its preflight status check.' }
        $before = Get-ClagnosPackageStatusSnapshot -Packages @($package) -Options $Options -Platform $platform -Force -TimeoutSeconds $remainingBeforeStatus -Runtime $runtime -Target $target
        $beforeStatus = [string]$before[[string]$package.Id]
        if ($beforeStatus -eq 'not-installed') {
            Write-Host ("{0} is not installed on VM '{1}'; update was not run." -f [string]$package.DisplayName,[string]$target.VmName) -ForegroundColor Yellow
            return [pscustomobject]@{ Package = $package; Action = 'update'; Status = 'not-installed'; Changed = $false }
        }
        if ($beforeStatus -notin @('installed','installed-drifted')) { throw ("Cannot safely update '{0}' because its current status is {1}." -f [string]$package.DisplayName,$beforeStatus) }
        $packageAppState = Get-ClagnosTaskAppStatePluginInfo -TaskBlock ([psobject]$package.PackageTask)
        if ([string]::Equals([string]$packageAppState.Status,'invalid',[System.StringComparison]::OrdinalIgnoreCase)) {
            throw ("Package '{0}' has an invalid app-state archive: {1}" -f [string]$package.DisplayName,[string]$packageAppState.Message)
        }
        if ([string]::Equals([string]$packageAppState.Status,'ready',[System.StringComparison]::OrdinalIgnoreCase)) {
            Assert-ClagnosPackageAppStateArchivePortable -ZipPath ([string]$packageAppState.ZipPath)
        }
        $updateTask = [pscustomobject]@{}
        foreach ($property in @($package.PackageTask.PSObject.Properties)) { $updateTask | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value }
        $updateTask.Script = New-ClagnosPackageLifecycleScript -Action 'update' -Package $package -Context $runtime.Context
        $updateTask.Name = [string]$package.Id
        if ($updateTask.PSObject.Properties['RelativePath']) { $updateTask.RelativePath = ('{0}/update.ps1' -f [string]$package.Id) }
        if ($null -ne $package.LifecycleScriptPaths -and $null -ne $package.LifecycleScriptPaths['update']) { $updateTask.Path = [string]$package.LifecycleScriptPaths['update'] }
        if ($null -ne $updateTask.PackageSpec) {
            $updatedPackageSpec = [pscustomobject]@{}
            foreach ($property in @($updateTask.PackageSpec.PSObject.Properties)) {
                $propertyValue = if ($property.Name -eq 'PostInstallTasks') { @() } else { $property.Value }
                $updatedPackageSpec | Add-Member -NotePropertyName $property.Name -NotePropertyValue $propertyValue
            }
            $updateTask.PackageSpec = $updatedPackageSpec
        }
        $remainingUpdateSeconds = [int][Math]::Floor(($actionDeadlineUtc - [DateTime]::UtcNow).TotalSeconds)
        if ($remainingUpdateSeconds -lt 30) { throw "Package update ended before its vendor-update phase." }
        $updateTask.TimeoutSeconds = [Math]::Min((Get-ClagnosPackageTimeoutSeconds -Package $package -Action 'update'),$remainingUpdateSeconds)
        $run = Invoke-ClagnosTaskExecutionWithTarget -Runtime $runtime -Options $Options -OperationName 'package' -Stage 'update' -Requested ([string]$package.Id) -PackageTaskBlock $updateTask -AutoMode:$AutoMode -TaskOutcomeModeOverride 'strict'
        $structuredResult = Get-ClagnosPackageStructuredResult -TaskResult $run
        if ($null -eq $structuredResult -or [string]$structuredResult.status -ne 'installed') {
            $detail = if ($null -ne $structuredResult) { [string]$structuredResult.message } else { 'No structured package update result was returned.' }
            throw ("Update result verification failed for '{0}': {1}" -f [string]$package.DisplayName,$detail)
        }
        $afterStatus = [string]$structuredResult.status
        Set-ClagnosPackageStatusCacheValue -Packages $catalogRuntime -Options $Options -Platform $platform -PackageId ([string]$package.Id) -Status $afterStatus -RefreshTimestamp -MarkIncomplete
        if ($afterStatus -ne 'installed') { throw ("Update script completed but '{0}' status verification returned {1}." -f [string]$package.DisplayName,$afterStatus) }
        $updateMessage = if (-not [string]::IsNullOrWhiteSpace([string]$structuredResult.message)) { [string]$structuredResult.message } else { ("Updated {0}; target status verified." -f [string]$package.DisplayName) }
        Write-Host $updateMessage -ForegroundColor Green
        return $run
    }
    if ($Action -eq 'uninstall') {
        if ($null -eq $package.Uninstall -or [string]::IsNullOrWhiteSpace([string]$package.Uninstall.kind) -or [string]::IsNullOrWhiteSpace([string]$package.Uninstall.value)) {
            throw ("'{0}' has no validated uninstall action in its package manifest." -f [string]$package.DisplayName)
        }
        $approved = Get-ClagnosCliOptionBool -Options $Options -Name 'yes' -DefaultValue $false
        if (-not $approved -and -not $AutoMode) {
            $answer = Read-Host ("Uninstall {0} from VM '{1}'? Type UNINSTALL to confirm" -f [string]$package.DisplayName,[string]$target.VmName)
            $approved = [string]::Equals([string]$answer,'UNINSTALL',[System.StringComparison]::Ordinal)
        }
        if (-not $approved) { Write-Host 'Uninstall canceled.' -ForegroundColor Yellow; return }
        $scriptText = New-ClagnosPackageUninstallScript -Package $package -Platform $platform -Context $runtime.Context
        $result = Invoke-ClagnosPackageGuestScript -Options $Options -Platform $platform -ScriptText $scriptText -TaskLabel ('package-uninstall-' + [string]$package.Id) -TimeoutSeconds (Get-ClagnosPackageTimeoutSeconds -Package $package -Action 'uninstall') -Runtime $runtime -Target $target
        $structuredResult = if ($platform -eq 'windows') { Get-ClagnosPackageStructuredResult -TaskResult ([pscustomobject]@{ Result = $result }) } else { $null }
        if ($null -ne $structuredResult) {
            $uninstallStatus = [string]$structuredResult.status
            if ($uninstallStatus -ne 'not-installed') { throw ("Uninstall verification failed for {0}: {1}" -f [string]$package.DisplayName,[string]$structuredResult.message) }
        }
        else {
            $verify = Get-ClagnosPackageStatusSnapshot -Packages @($package) -Options $Options -Platform $platform -Force -Runtime $runtime -Target $target
            $uninstallStatus = [string]$verify[[string]$package.Id]
            if ($uninstallStatus -eq 'installed' -or $uninstallStatus -eq 'unknown') { throw ("Uninstall command completed but absence of {0} could not be verified (status: {1})." -f [string]$package.DisplayName,$uninstallStatus) }
        }
        Set-ClagnosPackageStatusCacheValue -Packages $catalogRuntime -Options $Options -Platform $platform -PackageId ([string]$package.Id) -Status $uninstallStatus -RefreshTimestamp -MarkIncomplete
        Write-Host ("Uninstall completed for {0}." -f [string]$package.DisplayName) -ForegroundColor Green
        return $result
    }
    if ($Action -eq 'reinstall') {
        $approved = Get-ClagnosCliOptionBool -Options $Options -Name 'yes' -DefaultValue $false
        if (-not $approved -and -not $AutoMode) {
            $answer = Read-Host ("Force uninstall and reinstall {0} on VM '{1}'? Type REINSTALL to confirm" -f [string]$package.DisplayName,[string]$target.VmName)
            $approved = [string]::Equals([string]$answer,'REINSTALL',[System.StringComparison]::Ordinal)
        }
        if (-not $approved) { Write-Host 'Reinstall canceled.' -ForegroundColor Yellow; return }

        $overallWatch = [Diagnostics.Stopwatch]::StartNew()
        $overallTimeout = Get-ClagnosPackageTimeoutSeconds -Package $package -Action 'reinstall'
        Write-ClagnosActionProgress -Action ("reinstall package '{0}' with a {1}s total operation budget" -f [string]$package.Id,$overallTimeout)
        Write-ClagnosActionProgress -Action ("reinstall phase 1/2: uninstall '{0}'" -f [string]$package.Id)
        $uninstallText = New-ClagnosPackageUninstallScript -Package $package -Platform $platform -Context $runtime.Context
        $remaining = [Math]::Max(30,($overallTimeout - [int][Math]::Ceiling($overallWatch.Elapsed.TotalSeconds)))
        $uninstallBudget = [Math]::Min((Get-ClagnosPackageTimeoutSeconds -Package $package -Action 'uninstall'),$remaining)
        $uninstallResult = Invoke-ClagnosPackageGuestScript -Options $Options -Platform $platform -ScriptText $uninstallText -TaskLabel ('package-reinstall-uninstall-' + [string]$package.Id) -TimeoutSeconds $uninstallBudget -Runtime $runtime -Target $target
        $uninstallRecord = if ($platform -eq 'windows') { Get-ClagnosPackageStructuredResult -TaskResult ([pscustomobject]@{ Result = $uninstallResult }) } else { $null }
        if ($platform -eq 'windows' -and ($null -eq $uninstallRecord -or [string]$uninstallRecord.status -ne 'not-installed')) {
            throw ("Reinstall failed during phase 'uninstall' for '{0}': absence was not verified." -f [string]$package.DisplayName)
        }
        if ($platform -eq 'windows' -and $null -ne $uninstallRecord -and [bool]$uninstallRecord.rebootRequired) {
            $restarted = Restart-ClagnosPackageVmForPendingReboot -Runtime $runtime -Target $target -Options $Options -AutoMode:$AutoMode -WindowsFlag:$WindowsFlag -LinuxFlag:$LinuxFlag
            $runtime = $restarted.Runtime
            $target = $restarted.Target
        }

        Write-ClagnosActionProgress -Action ("reinstall phase 2/2: install '{0}'" -f [string]$package.Id)
        $remaining = $overallTimeout - [int][Math]::Ceiling($overallWatch.Elapsed.TotalSeconds)
        if ($remaining -lt 30) { throw ("Reinstall failed during phase 'install' for '{0}': total operation budget expired after verified uninstall." -f [string]$package.DisplayName) }
        $installTask = [pscustomobject]@{}
        foreach ($property in @($package.PackageTask.PSObject.Properties)) { $installTask | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value }
        $installTask.Script = New-ClagnosPackageLifecycleScript -Action 'install' -Package $package -Context $runtime.Context
        $installTask.TimeoutSeconds = [Math]::Min((Get-ClagnosPackageTimeoutSeconds -Package $package -Action 'install'),$remaining)
        $installRun = Invoke-ClagnosTaskExecutionWithTarget -Runtime $runtime -Options $Options -OperationName 'package' -Stage 'update' -Requested ([string]$package.Id) -PackageTaskBlock $installTask -AutoMode:$AutoMode -TaskOutcomeModeOverride 'strict'
        $installRecord = Get-ClagnosPackageStructuredResult -TaskResult $installRun
        if ($null -eq $installRecord -or [string]$installRecord.status -ne 'installed') {
            $failureMessage = if ($null -ne $installRecord) { [string]$installRecord.message } else { 'No structured install result was returned.' }
            throw ("Reinstall failed during phase 'install' for '{0}': {1}" -f [string]$package.DisplayName,$failureMessage)
        }
        $overallWatch.Stop()
        Set-ClagnosPackageStatusCacheValue -Packages $catalogRuntime -Options $Options -Platform $platform -PackageId ([string]$package.Id) -Status 'installed' -RefreshTimestamp -MarkIncomplete
        Write-Host ("Reinstall completed for {0} in {1}s; installed state verified." -f [string]$package.DisplayName,[int]$overallWatch.Elapsed.TotalSeconds) -ForegroundColor Green
        return $installRun
    }
    throw ("Unsupported package action '{0}'." -f $Action)
}
