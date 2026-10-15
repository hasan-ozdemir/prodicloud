# Package catalog, status, and managed guest install/uninstall operations.

function Get-ClagnosPackageCatalog {
    param(
        [ValidateSet('windows','linux')][string]$Platform,
        [ValidateSet('builtin','custom')][string]$Catalog,
        [string]$CatalogRoot = ''
    )

    $repoRoot = Get-ClagnosRepoRoot
    $root = if ([string]::IsNullOrWhiteSpace([string]$CatalogRoot)) {
        Join-Path $repoRoot (Join-Path 'packages' (Join-Path $Catalog $Platform))
    }
    else {
        [System.IO.Path]::GetFullPath($CatalogRoot)
    }
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { return @() }
    $expectedExtension = if ($Platform -eq 'windows') { '.ps1' } else { '.sh' }
    $packages = @()
    foreach ($folder in @(Get-ChildItem -LiteralPath $root -Directory -Force | Sort-Object Name)) {
        if ($folder.Name.StartsWith('.') -or [string]::Equals($folder.Name, 'backup-app-states', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
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
        if ([string]$statusCheck.kind -notin @('command','winget','choco','npm','appx','store-state','choco-self','dpkg','rpm')) {
            throw ("Package '{0}' has unsupported status check '{1}'." -f $id, [string]$statusCheck.kind)
        }
        if ([string]$uninstall.kind -notin @('winget','choco','npm','appx','windows-feature','choco-self','apt','dnf','snap')) {
            throw ("Package '{0}' has unsupported uninstall action '{1}'." -f $id, [string]$uninstall.kind)
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
        if ($Platform -eq 'windows') {
            if ($Catalog -eq 'builtin') {
                foreach ($lifecycleAction in @('status','update','uninstall')) {
                $manifestKey = '{0}Script' -f $lifecycleAction
                $scriptName = [string]$manifest.$manifestKey
                if ([string]::IsNullOrWhiteSpace($scriptName)) { $scriptName = ('{0}.ps1' -f $lifecycleAction) }
                if ([System.IO.Path]::GetFileName($scriptName) -cne $scriptName -or [System.IO.Path]::GetExtension($scriptName) -cne '.ps1') {
                    throw ("Package '{0}' {1}Script must be a PowerShell file directly inside its package folder." -f $id,$lifecycleAction)
                }
                $scriptPath = Join-Path $folder.FullName $scriptName
                if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) { throw ("Package '{0}' {1} script was not found: {2}" -f $id,$lifecycleAction,$scriptPath) }
                $lifecycleScriptPaths[$lifecycleAction] = [string]$scriptPath
                $lifecycleScriptText[$lifecycleAction] = [string](Get-Content -LiteralPath $scriptPath -Raw -ErrorAction Stop)
            }
            }
            $updateStrategy = [string]$manifest.updateStrategy
            if ([string]::IsNullOrWhiteSpace($updateStrategy)) {
                $updateStrategy = switch ([string]$statusCheck.kind) {
                    'winget' { 'winget' }
                    'choco' { 'choco' }
                    'npm' { 'npm' }
                    'choco-self' { 'choco-self' }
                    default { 'installer' }
                }
            }
            if ($updateStrategy -notin @('winget','choco','npm','choco-self','installer')) { throw ("Package '{0}' has unsupported updateStrategy '{1}'" -f $id,$updateStrategy) }
            $operationsModulePath = Join-Path $repoRoot 'modules/commands/package/clagnos-package-operations.psm1'
            if (-not (Test-Path -LiteralPath $operationsModulePath -PathType Leaf)) { throw "The package lifecycle helper module is missing." }
        }
        else { $updateStrategy = '' }

        $enabled = Convert-ClagnosTaskCatalogBool -Value $manifest.enabled -DefaultValue $true
        $timeoutSeconds = Convert-ClagnosTaskCatalogTimeout -Value $manifest.timeout -DefaultValue (Get-ClagnosTaskDefaultTimeoutSeconds)
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
        $postInstallTasks = @()
        if ($null -ne $manifest.postInstallTasks) { $postInstallTasks = @($manifest.postInstallTasks | ForEach-Object { [string]$_ }) }
        $disabledReason = if ($enabled) { '' } else { 'disabled-in-package-manifest' }

        $packageSpec = [pscustomobject]@{
            Id = $id
            DisplayName = $displayName.Trim()
            Category = $category
            StatusCheck = $statusCheck
            Uninstall = $uninstall
            UpdateStrategy = [string]$updateStrategy
            StartupPolicy = $manifest.startupPolicy
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
            RelativePath = ('{0}/{1}' -f $id, $installScript)
            DirectoryPath = [string]$folder.FullName
            StageRootDirectoryPath = [string]$root
            TimeoutSeconds = [int]$timeoutSeconds
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
            StartupPolicy = $manifest.startupPolicy
            ObservedDurationSeconds = [double]::PositiveInfinity
        }
        $packages += [pscustomobject]@{
            Id = $id
            DisplayName = $displayName.Trim()
            Category = $category
            StatusCheck = $statusCheck
            Uninstall = $uninstall
            UpdateStrategy = [string]$updateStrategy
            StartupPolicy = $manifest.startupPolicy
            LifecycleScriptPaths = $lifecycleScriptPaths
            StatusScriptText = [string]$lifecycleScriptText['status']
            UpdateScriptText = [string]$lifecycleScriptText['update']
            UninstallScriptText = [string]$lifecycleScriptText['uninstall']
            Catalog = $Catalog
            CatalogRoot = [string]$root
            ManifestPath = [string]$manifestPath
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
        $configPath = Join-Path (Get-ClagnosRepoRoot) '.env'
        if (Test-Path -LiteralPath $configPath -PathType Leaf) { $transport = Get-ClagnosPackageTransport -ConfigMap (Read-DotEnvFile -Path $configPath) }
    }
    catch { $transport = 'invalid' }
    $catalogIdentity = @($Packages | ForEach-Object {
        $statusCheck = ConvertTo-Json -InputObject $_.StatusCheck -Depth 20 -Compress
        '{0}:{1}:{2}' -f [string]$_.Catalog,[string]$_.Id,[string]$statusCheck
    } | Sort-Object) -join ','
    return ('{0}|{1}|{2}|{3}|{4}|{5}' -f [string](Get-ClagnosCliOptionText -Options $Options -Name 'subscription-id'), [string](Get-ClagnosCliOptionText -Options $Options -Name 'group'), [string](Get-ClagnosCliOptionText -Options $Options -Name 'vm-name'), [string]$Platform, $transport, $catalogIdentity).ToLowerInvariant()
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
    }
    if ($null -ne $Package.PSObject.Properties['StartupPolicy']) { $spec.startupPolicy = $Package.StartupPolicy }
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

function New-ClagnosPackageLifecycleScript {
    param(
        [ValidateSet('status','install','update','uninstall')][string]$Action,
        [object]$Package,
        [object]$Context = $null
    )
    $template = switch ($Action) {
        'status' { [string]$Package.StatusScriptText }
        'update' { [string]$Package.UpdateScriptText }
        'uninstall' { [string]$Package.UninstallScriptText }
        'install' { '' }
    }
    if ([string]::IsNullOrWhiteSpace($template) -and $Action -in @('install','update')) {
        if ($Action -eq 'install') {
            $template = @'
$ErrorActionPreference = 'Stop'
Import-Module 'C:\Windows\Temp\clagnos-package-operations.psm1' -Force -DisableNameChecking
Invoke-ClagnosPackageLifecycle -Action install -PackageSpecBase64 '__CLAGNOS_PACKAGE_SPEC_B64__' -InstallScriptBase64 '__CLAGNOS_INSTALL_SCRIPT_B64__'
'@
        }
        else {
            $template = @'
$ErrorActionPreference = 'Stop'
Import-Module 'C:\Windows\Temp\clagnos-package-operations.psm1' -Force -DisableNameChecking
Invoke-ClagnosPackageLifecycle -Action update -PackageSpecBase64 '__CLAGNOS_PACKAGE_SPEC_B64__' -InstallScriptBase64 '__CLAGNOS_INSTALL_SCRIPT_B64__'
'@
        }
    }
    if ([string]::IsNullOrWhiteSpace($template)) { return '' }
    $template = $template.Replace('__CLAGNOS_PACKAGE_SPEC_B64__',(Get-ClagnosPackageLifecycleSpecBase64 -Package $Package -Context $Context))
    if ($Action -in @('install','update')) {
        $installSource = [string]$Package.PackageTask.Script
        if ($null -ne $Context) {
            $resolved = @(Apply-ClagnosTaskBlockReplacements -TaskBlocks @($Package.PackageTask) -Replacements (Get-ClagnosTaskTokenReplacements -Context $Context) -Context $Context)
            if ($resolved.Count -gt 0) { $installSource = [string]$resolved[0].Script }
        }
        $installBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($installSource))
        $template = $template.Replace('__CLAGNOS_INSTALL_SCRIPT_B64__',$installBase64)
    }
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
        [ValidateSet('windows','linux')][string]$Platform
    )

    $payload = @(
        $Packages | ForEach-Object {
            [ordered]@{
                id = [string]$_.Id
                displayName = [string]$_.DisplayName
                statusCheck = $_.StatusCheck
                uninstall = $_.Uninstall
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
`$npmInventory = `$null
`$npmInventoryReady = `$false
if (`$hasNpmPackages) {
    `$npmExe = Get-Command npm.cmd -ErrorAction SilentlyContinue
    if (-not `$npmExe) { `$npmExe = Get-Command npm -ErrorAction SilentlyContinue }
    if (`$npmExe) {
        Write-Output 'Doing: read one global npm package inventory'
        `$npmOutput = & `$npmExe.Source list --global --depth=0 --json 2>`$null | Out-String
        if ([int]`$LASTEXITCODE -eq 0 -or `$npmOutput -match '"dependencies"') {
            try { `$npmInventory = ConvertFrom-Json -InputObject `$npmOutput; `$npmInventoryReady = `$true } catch { `$npmInventoryReady = `$false }
        }
    }
}
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
            if (-not `$npmInventoryReady) { return 'unknown' }
            if (`$null -ne `$npmInventory.dependencies.PSObject.Properties[[string]`$value]) { return 'installed' }
            return 'not-installed'
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
        default { return 'unknown' }
    }
}
`$results = @()
foreach (`$package in `$packages) {
    `$results += [pscustomobject]@{ id = [string]`$package.id; status = (Get-PackageStatus -Package `$package) }
}
`$jsonResult = ConvertTo-Json -InputObject `$results -Depth 4 -Compress
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
        [psobject]$Runtime = $null,
        [psobject]$Target = $null
    )

    if ($null -eq $Runtime) {
        $Runtime = Initialize-ClagnosTaskExecutionRuntimeContext -AutoMode:$false -WindowsFlag:([string]$Platform -eq 'windows') -LinuxFlag:([string]$Platform -eq 'linux')
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
        RelativePath = ('packages/{0}' -f [string]$TaskLabel)
        DirectoryPath = (Get-ClagnosRepoRoot)
        TaskRootPath = (Get-ClagnosRepoRoot)
        StageRootDirectoryPath = (Get-ClagnosRepoRoot)
        TimeoutSeconds = 300
        Priority = 1
        TaskType = 'normal'
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
        -SshTaskTimeoutSeconds 300 `
        -SshConnectTimeoutSeconds ([int]$Runtime.SshConnectTimeoutSeconds) `
        -ConfiguredPySshClientPath ([string]$Runtime.ConfiguredPySshClientPath))
}

function Get-ClagnosPackageStatusSnapshot {
    param(
        [object[]]$Packages,
        [hashtable]$Options,
        [string]$Platform,
        [switch]$Force,
        [psobject]$Runtime = $null,
        [psobject]$Target = $null
    )

    $cacheInfo = Get-ClagnosPackageStatusCacheEntry -Packages $Packages -Options $Options -Platform $Platform
    $key = if ($null -ne $cacheInfo) { [string]$cacheInfo.Key } else { Get-ClagnosPackageStatusCacheKey -Packages $Packages -Options $Options -Platform $Platform }
    if (-not $Force -and $null -ne $cacheInfo -and [bool]$cacheInfo.IsFresh) { return $cacheInfo.Entry.StatusByPackage }
    if ($null -eq $Runtime) { $Runtime = Initialize-ClagnosTaskExecutionRuntimeContext -AutoMode:$false -WindowsFlag:([string]$Platform -eq 'windows') -LinuxFlag:([string]$Platform -eq 'linux') }
    if ($null -eq $Target) { $Target = Resolve-ClagnosManagedVmTarget -Options $Options -ConfigMap $Runtime.EffectiveConfigMap -OperationName 'package' }
    $Runtime.Context.ResourceGroup = [string]$Target.ResourceGroup
    $Runtime.Context.VmName = [string]$Target.VmName
    $scriptText = if (@($Packages).Count -eq 1 -and -not [string]::IsNullOrWhiteSpace([string]$Packages[0].StatusScriptText)) {
        New-ClagnosPackageLifecycleScript -Action 'status' -Package $Packages[0] -Context $Runtime.Context
    }
    else { New-ClagnosPackageGuestScript -Action 'status' -Packages $Packages -Platform $Platform }
    $result = Invoke-ClagnosPackageGuestScript -Options $Options -Platform $Platform -ScriptText $scriptText -TaskLabel 'package-status' -Runtime $Runtime -Target $Target
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
    foreach ($row in @($rows)) { $map[[string]$row.id] = [string]$row.status }
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

function Set-ClagnosPackageManifestEnabled {
    param([string]$ManifestPath, [bool]$Enabled)

    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { throw ("Package manifest was not found: {0}" -f $ManifestPath) }
    $manifest = ConvertFrom-JsonCompat -InputObject ([string](Get-Content -LiteralPath $ManifestPath -Raw -ErrorAction Stop))
    if ($null -eq $manifest -or $manifest -isnot [psobject]) { throw ("Package manifest is not a JSON object: {0}" -f $ManifestPath) }
    $enabledProperty = $manifest.PSObject.Properties['enabled']
    if ($null -eq $enabledProperty) { $manifest | Add-Member -NotePropertyName 'enabled' -NotePropertyValue ([bool]$Enabled) }
    else { $enabledProperty.Value = [bool]$Enabled }

    $directory = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($ManifestPath))
    $tempPath = Join-Path $directory ('.package.json.clagnos-{0}.tmp' -f ([guid]::NewGuid().ToString('N')))
    try {
        $serialized = ConvertTo-Json -InputObject $manifest -Depth 100
        [System.IO.File]::WriteAllText($tempPath,([string]$serialized + [Environment]::NewLine),[System.Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $tempPath -Destination $ManifestPath -Force -ErrorAction Stop
    }
    finally {
        if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue }
    }
    $verified = ConvertFrom-JsonCompat -InputObject ([string](Get-Content -LiteralPath $ManifestPath -Raw -ErrorAction Stop))
    if ($null -eq $verified -or [bool]$verified.enabled -ne [bool]$Enabled) { throw 'Package availability did not verify after updating package.json.' }
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
    $taskRuntime = Initialize-ClagnosTaskCommandRuntimeContext -AutoMode:$AutoMode -WindowsFlag:$WindowsFlag -LinuxFlag:$LinuxFlag
    $platform = [string]$taskRuntime.Platform
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
        Set-ClagnosPackageManifestEnabled -ManifestPath ([string]$package.ManifestPath) -Enabled $shouldEnable
        $verified = @(Get-ClagnosPackageCatalog -Platform $platform -Catalog $Catalog -CatalogRoot $CatalogRoot | Where-Object { [string]::Equals([string]$_.Id,[string]$PackageId,[System.StringComparison]::OrdinalIgnoreCase) })
        if ($verified.Count -ne 1 -or [bool]$verified[0].Enabled -ne $shouldEnable) { throw ("Package availability verification failed for '{0}'." -f $PackageId) }
        Write-Host ("Package '{0}' is now {1}." -f $package.DisplayName, $(if ($shouldEnable) { 'enabled' } else { 'disabled' })) -ForegroundColor Green
        return [pscustomobject]@{ Package = $verified[0]; Enabled = [bool]$shouldEnable; Changed = $true }
    }

    $catalogRuntime = @(Get-ClagnosPackageCatalog -Platform $platform -Catalog $Catalog -CatalogRoot $CatalogRoot)
    if ($Action -eq 'list') {
        $runtime = Initialize-ClagnosTaskExecutionRuntimeContext -AutoMode:$AutoMode -WindowsFlag:$WindowsFlag -LinuxFlag:$LinuxFlag
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
    if ($Action -in @('install','update') -and -not [bool]$package.Enabled) {
        throw ("'{0}' is disabled in the {1} package catalog. Enable it before installing or updating it." -f [string]$package.DisplayName,$Catalog)
    }
    if ($Action -notin @('status','install','update','uninstall')) { throw ("Unsupported package action '{0}'." -f $Action) }
    $runtime = Initialize-ClagnosTaskExecutionRuntimeContext -AutoMode:$AutoMode -WindowsFlag:$WindowsFlag -LinuxFlag:$LinuxFlag
    $target = Resolve-ClagnosManagedVmTarget -Options $Options -ConfigMap $runtime.EffectiveConfigMap -OperationName 'package'
    $runtime.Context.ResourceGroup = [string]$target.ResourceGroup
    $runtime.Context.VmName = [string]$target.VmName
    $resolvedSubscription = Get-ClagnosResolvedSubscriptionContext
    if ($null -ne $resolvedSubscription) { $Options['subscription-id'] = [string]$resolvedSubscription.SubscriptionId }
    if ($Action -eq 'status') {
        $statusScriptText = if (-not [string]::IsNullOrWhiteSpace([string]$package.StatusScriptText)) { New-ClagnosPackageLifecycleScript -Action 'status' -Package $package -Context $runtime.Context } else { New-ClagnosPackageGuestScript -Action 'status' -Packages @($package) -Platform $platform }
        $statusResult = Invoke-ClagnosPackageGuestScript -Options $Options -Platform $platform -ScriptText $statusScriptText -TaskLabel ('package-status-' + [string]$package.Id) -Runtime $runtime -Target $target
        $statusOutput = if ($statusResult.TaskOutputs.Count -gt 0) { [string]$statusResult.TaskOutputs[0].Output } else { '' }
        $singleStatusMatch = [regex]::Match($statusOutput,'(?m)^CLAGNOS_PACKAGE_RESULT:(?<json>\{.*\})\s*$')
        $status = ''
        if ($singleStatusMatch.Success) {
            $statusRecord = ConvertFrom-JsonCompat -InputObject ([string]$singleStatusMatch.Groups['json'].Value)
            $status = [string]$statusRecord.status
            $statusMessage = [string]$statusRecord.message
            if (-not [string]::IsNullOrWhiteSpace([string]$statusRecord.version)) { $statusMessage += (' Version: {0}.' -f [string]$statusRecord.version) }
            Write-Host ("{0}: {1}" -f [string]$package.DisplayName,$statusMessage)
        }
        else {
            $batchStatusMatch = [regex]::Match($statusOutput,'(?m)^CLAGNOS_PACKAGE_RESULTS:(?<json>\[.*\])\s*$')
            if (-not $batchStatusMatch.Success) { throw 'Package status response could not be read from the VM.' }
            $statusRow = @(ConvertTo-ObjectArrayCompat -InputObject (ConvertFrom-JsonCompat -InputObject ([string]$batchStatusMatch.Groups['json'].Value)) | Where-Object { [string]::Equals([string]$_.id,[string]$package.Id,[System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
            if ($statusRow.Count -ne 1) { throw 'Package status response did not include the selected package.' }
            $status = [string]$statusRow[0].status
            Write-Host ("{0}: {1}" -f [string]$package.DisplayName,$status)
        }
        Set-ClagnosPackageStatusCacheValue -Packages $catalogRuntime -Options $Options -Platform $platform -PackageId ([string]$package.Id) -Status $status -RefreshTimestamp
        return
    }
    if ($Action -eq 'install') {
        $before = Get-ClagnosPackageStatusSnapshot -Packages @($package) -Options $Options -Platform $platform -Force -Runtime $runtime -Target $target
        $beforeStatus = [string]$before[[string]$package.Id]
        if ($beforeStatus -eq 'installed') {
            Write-Host ("{0} is already installed on VM '{1}'; no install was run." -f [string]$package.DisplayName,[string]$target.VmName) -ForegroundColor Yellow
            return [pscustomobject]@{ Package = $package; Action = 'install'; Status = 'installed'; Changed = $false }
        }
        if ($beforeStatus -ne 'not-installed') { throw ("Cannot safely install '{0}' because its current status is {1}." -f [string]$package.DisplayName,$beforeStatus) }
        $packageAppState = Get-ClagnosTaskAppStatePluginInfo -TaskBlock ([psobject]$package.PackageTask)
        if ([string]::Equals([string]$packageAppState.Status, 'invalid', [System.StringComparison]::OrdinalIgnoreCase)) {
            throw ("Package '{0}' has an invalid app-state archive: {1}" -f [string]$package.DisplayName, [string]$packageAppState.Message)
        }
        if ([string]::Equals([string]$packageAppState.Status, 'ready', [System.StringComparison]::OrdinalIgnoreCase)) {
            Assert-ClagnosPackageAppStateArchivePortable -ZipPath ([string]$packageAppState.ZipPath)
        }
        $installTask = [pscustomobject]@{}
        foreach ($property in @($package.PackageTask.PSObject.Properties)) { $installTask | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value }
        if ($platform -eq 'windows') { $installTask.Script = New-ClagnosPackageLifecycleScript -Action 'install' -Package $package -Context $runtime.Context }
        $run = Invoke-ClagnosTaskExecutionWithTarget -Runtime $runtime -Options $Options -OperationName 'package' -Stage 'update' -Requested ([string]$package.Id) -PackageTaskBlock $installTask -AutoMode:$AutoMode -TaskOutcomeModeOverride 'strict'
        $structuredResult = if ($platform -eq 'windows') { Get-ClagnosPackageStructuredResult -TaskResult $run } else { $null }
        if ($platform -eq 'windows' -and ($null -eq $structuredResult -or [string]$structuredResult.status -ne 'installed')) {
            $detail = if ($null -ne $structuredResult) { [string]$structuredResult.message } else { 'No structured package install result was returned.' }
            throw ("Install result verification failed for '{0}': {1}" -f [string]$package.DisplayName,$detail)
        }
        $afterStatus = if ($platform -eq 'windows') { [string]$structuredResult.status } else {
            $after = Get-ClagnosPackageStatusSnapshot -Packages @($package) -Options $Options -Platform $platform -Force -Runtime $runtime -Target $target
            [string]$after[[string]$package.Id]
        }
        Set-ClagnosPackageStatusCacheValue -Packages $catalogRuntime -Options $Options -Platform $platform -PackageId ([string]$package.Id) -Status $afterStatus -RefreshTimestamp -MarkIncomplete
        if ($afterStatus -ne 'installed') { throw ("Install script completed but '{0}' status verification returned {1}." -f [string]$package.DisplayName,$afterStatus) }
        $installMessage = if ($null -ne $structuredResult -and -not [string]::IsNullOrWhiteSpace([string]$structuredResult.message)) { [string]$structuredResult.message } else { ("Installed {0}; target status verified." -f [string]$package.DisplayName) }
        Write-Host $installMessage -ForegroundColor Green
        return $run
    }
    if ($Action -eq 'update') {
        if ($platform -ne 'windows') { throw 'Separate package update scripts are currently supported only by the Windows package catalogs.' }
        $before = Get-ClagnosPackageStatusSnapshot -Packages @($package) -Options $Options -Platform $platform -Force -Runtime $runtime -Target $target
        $beforeStatus = [string]$before[[string]$package.Id]
        if ($beforeStatus -eq 'not-installed') {
            Write-Host ("{0} is not installed on VM '{1}'; update was not run." -f [string]$package.DisplayName,[string]$target.VmName) -ForegroundColor Yellow
            return [pscustomobject]@{ Package = $package; Action = 'update'; Status = 'not-installed'; Changed = $false }
        }
        if ($beforeStatus -ne 'installed') { throw ("Cannot safely update '{0}' because its current status is {1}." -f [string]$package.DisplayName,$beforeStatus) }
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
        $result = Invoke-ClagnosPackageGuestScript -Options $Options -Platform $platform -ScriptText $scriptText -TaskLabel ('package-uninstall-' + [string]$package.Id) -Runtime $runtime -Target $target
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
    throw ("Unsupported package action '{0}'." -f $Action)
}
