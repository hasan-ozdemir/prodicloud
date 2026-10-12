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

        $enabled = Convert-ClagnosTaskCatalogBool -Value $manifest.enabled -DefaultValue $true
        $timeoutSeconds = Convert-ClagnosTaskCatalogTimeout -Value $manifest.timeout -DefaultValue (Get-ClagnosTaskDefaultTimeoutSeconds)
        $sortOrder = 0
        if ($null -ne $manifest.sortOrder -and [string]$manifest.sortOrder -match '^\d+$') { $sortOrder = [int]$manifest.sortOrder }
        $assetSpecs = @()
        if ($null -ne $manifest.assets) { $assetSpecs = @(ConvertTo-ClagnosTaskFolderAssetSpecs -Assets $manifest.assets -TaskLabel $id) }
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
            ObservedDurationSeconds = [double]::PositiveInfinity
        }
        $packages += [pscustomobject]@{
            Id = $id
            DisplayName = $displayName.Trim()
            Category = $category
            StatusCheck = $statusCheck
            Uninstall = $uninstall
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
    $catalogIdentity = @($Packages | ForEach-Object { '{0}:{1}' -f [string]$_.Catalog,[string]$_.Id } | Sort-Object) -join ','
    return ('{0}|{1}|{2}|{3}|{4}' -f [string](Get-ClagnosCliOptionText -Options $Options -Name 'subscription-id'), [string](Get-ClagnosCliOptionText -Options $Options -Name 'group'), [string](Get-ClagnosCliOptionText -Options $Options -Name 'vm-name'), [string]$Platform, $catalogIdentity).ToLowerInvariant()
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
`$packages = @(ConvertFrom-Json -InputObject `$payload)
function Get-PackageStatus {
    param([object]`$Package)
    `$check = `$Package.statusCheck
    if (`$null -eq `$check -or [string]::IsNullOrWhiteSpace([string]`$check.kind) -or [string]::IsNullOrWhiteSpace([string]`$check.value)) { return 'unknown' }
    `$value = [string]`$check.value
    switch ([string]`$check.kind) {
        'command' { if (Get-Command `$value -ErrorAction SilentlyContinue) { return 'installed' }; return 'not-installed' }
        'winget' {
            `$exe = Get-Command winget.exe -ErrorAction SilentlyContinue
            if (-not `$exe) { return 'not-installed' }
            `$output = & `$exe.Source list --id `$value --exact --accept-source-agreements --disable-interactivity 2>`$null | Out-String
            if (`$LASTEXITCODE -eq 0 -and `$output -match [regex]::Escape(`$value)) { return 'installed' }
            return 'not-installed'
        }
        'choco' {
            `$exe = Get-Command choco.exe -ErrorAction SilentlyContinue
            if (-not `$exe) { return 'not-installed' }
            `$output = & `$exe.Source list --local-only --exact --limit-output `$value 2>`$null | Out-String
            if (`$LASTEXITCODE -eq 0 -and `$output -match ('(?im)^' + [regex]::Escape(`$value) + '\|')) { return 'installed' }
            return 'not-installed'
        }
        'npm' {
            `$exe = Get-Command npm.cmd -ErrorAction SilentlyContinue
            if (-not `$exe) { return 'not-installed' }
            `$output = & `$exe.Source list -g --depth=0 `$value 2>`$null | Out-String
            if (`$LASTEXITCODE -eq 0 -and `$output.Contains(`$value)) { return 'installed' }
            return 'not-installed'
        }
        'appx' {
            `$matches = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { `$_.Name -like ('*' + `$value + '*') -or `$_.PackageFamilyName -like ('*' + `$value + '*') -or `$_.PackageFullName -like ('*' + `$value + '*') })
            if (`$matches.Count -gt 0) { return 'installed' }
            return 'not-installed'
        }
        'store-state' {
            `$safeName = [regex]::Replace(`$value, '[^A-Za-z0-9._-]', '_')
            `$path = Join-Path 'C:\PackageData\clagnos\state\store-installs' (`$safeName + '.json')
            if (-not (Test-Path -LiteralPath `$path)) { return 'unknown' }
            try { `$state = Get-Content -LiteralPath `$path -Raw | ConvertFrom-Json; if ([string]`$state.State -eq 'installed') { return 'installed' }; return 'not-installed' } catch { return 'unknown' }
        }
        'choco-self' { if (Test-Path -LiteralPath 'C:\PackageData\chocolatey') { return 'installed' }; return 'not-installed' }
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
    param([object]$Package, [ValidateSet('windows','linux')][string]$Platform = 'windows')

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
    `$statePath = Join-Path 'C:\PackageData\clagnos\state\store-installs' (`$safeName + '.json')
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
        [string]$TaskLabel
    )

    $runtime = Initialize-ClagnosTaskExecutionRuntimeContext -AutoMode:$false -WindowsFlag:([string]$Platform -eq 'windows') -LinuxFlag:([string]$Platform -eq 'linux')
    $target = Resolve-ClagnosManagedVmTarget -Options $Options -ConfigMap $runtime.EffectiveConfigMap -OperationName 'package'
    $runtime.Context.ResourceGroup = [string]$target.ResourceGroup
    $runtime.Context.VmName = [string]$target.VmName
    $vmDetails = Get-ClagnosVmDetails -Context $runtime.Context
    $sshHost = [string]$vmDetails.VmFqdn
    if ([string]::IsNullOrWhiteSpace($sshHost)) { $sshHost = [string]$vmDetails.PublicIP }
    if ([string]::IsNullOrWhiteSpace($sshHost)) { throw 'Package management could not resolve the VM SSH host.' }
    $pySsh = Ensure-ClagnosPySshTools -RepoRoot (Get-ClagnosRepoRoot) -ConfiguredPySshClientPath ([string]$runtime.ConfiguredPySshClientPath)
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
        AppStateSpec = $null
        PackageSpec = $null
        Extensions = $null
        DependsOn = @()
    }
    $resolvedBlock = Apply-ClagnosTaskBlockReplacements -TaskBlocks @($block) -Replacements (Get-ClagnosTaskTokenReplacements -Context $runtime.Context) -Context $runtime.Context
    return (Invoke-ClagnosSshTaskBlocks `
        -Platform $Platform `
        -RepoRoot (Get-ClagnosRepoRoot) `
        -SshHost $sshHost `
        -SshUser ([string]$runtime.Context.VmUser) `
        -SshPassword ([string]$runtime.Context.VmPass) `
        -SshPort ([string]$runtime.Context.SshPort) `
        -AssistantUser ([string]$runtime.Context.VmAssistantUser) `
        -ResourceGroup ([string]$target.ResourceGroup) `
        -VmName ([string]$target.VmName) `
        -TaskBlocks @($resolvedBlock) `
        -TaskOutcomeMode 'strict' `
        -PerfTaskCategory 'task-run' `
        -SshMaxRetries 1 `
        -SshTaskTimeoutSeconds 300 `
        -SshConnectTimeoutSeconds ([int]$runtime.SshConnectTimeoutSeconds) `
        -ConfiguredPySshClientPath ([string]$runtime.ConfiguredPySshClientPath))
}

function Get-ClagnosPackageStatusSnapshot {
    param(
        [object[]]$Packages,
        [hashtable]$Options,
        [string]$Platform
    )

    $key = Get-ClagnosPackageStatusCacheKey -Packages $Packages -Options $Options -Platform $Platform
    if ($null -eq $script:ClagnosPackageStatusCache) { $script:ClagnosPackageStatusCache = @{} }
    if ($script:ClagnosPackageStatusCache -and $script:ClagnosPackageStatusCache.ContainsKey($key)) {
        return $script:ClagnosPackageStatusCache[$key]
    }
    $scriptText = New-ClagnosPackageGuestScript -Action 'status' -Packages $Packages -Platform $Platform
    $result = Invoke-ClagnosPackageGuestScript -Options $Options -Platform $Platform -ScriptText $scriptText -TaskLabel 'package-status'
    $output = ''
    if ($result.TaskOutputs.Count -gt 0) { $output = [string]$result.TaskOutputs[0].Output }
    $match = [regex]::Match($output,'(?m)^CLAGNOS_PACKAGE_RESULTS:(?<json>\[.*\])\s*$')
    if (-not $match.Success) { throw 'Package status response could not be read from the VM.' }
    $rows = @(ConvertTo-ObjectArrayCompat -InputObject (ConvertFrom-JsonCompat -InputObject ([string]$match.Groups['json'].Value)))
    $map = @{}
    foreach ($row in @($rows)) { $map[[string]$row.id] = [string]$row.status }
    $script:ClagnosPackageStatusCache[$key] = $map
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
        $packageList = Get-ClagnosPackageStatusSnapshot -Packages $catalogRuntime -Options $Options -Platform $platform
        foreach ($package in @($catalogRuntime)) {
            $availability = if ([bool]$package.Enabled) { 'enabled' } else { ('disabled: ' + [string]$package.DisabledReason) }
            Write-Host ("{0} [{1}] | {2} | {3} | {4}" -f [string]$package.DisplayName,$Catalog,[string]$package.Category,$availability,[string]$packageList[[string]$package.Id])
        }
        return
    }
    $selected = @($catalogRuntime | Where-Object { [string]::Equals([string]$_.Id,[string]$PackageId,[System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
    if (@($selected).Count -eq 0) { throw ("Package '{0}' was not found in the {1} catalog for {2}." -f $PackageId,$Catalog,$platform) }
    $package = $selected[0]
    if ($Action -eq 'install' -and -not [bool]$package.Enabled) {
        throw ("'{0}' is disabled in the {1} package catalog. Enable it before installing or updating it." -f [string]$package.DisplayName,$Catalog)
    }
    if ($Action -notin @('status','install','uninstall')) { throw ("Unsupported package action '{0}'." -f $Action) }
    $runtime = Initialize-ClagnosTaskExecutionRuntimeContext -AutoMode:$AutoMode -WindowsFlag:$WindowsFlag -LinuxFlag:$LinuxFlag
    $target = Resolve-ClagnosManagedVmTarget -Options $Options -ConfigMap $runtime.EffectiveConfigMap -OperationName 'package'
    $runtime.Context.ResourceGroup = [string]$target.ResourceGroup
    $runtime.Context.VmName = [string]$target.VmName
    $script:ClagnosPackageStatusCache = @{}
    if ($Action -eq 'status') {
        $snapshot = Get-ClagnosPackageStatusSnapshot -Packages @($package) -Options $Options -Platform $platform
        Write-Host ("{0}: {1}" -f [string]$package.DisplayName,[string]$snapshot[[string]$package.Id])
        return
    }
    if ($Action -eq 'install') {
        $packageAppState = Get-ClagnosTaskAppStatePluginInfo -TaskBlock ([psobject]$package.PackageTask)
        if ([string]::Equals([string]$packageAppState.Status, 'invalid', [System.StringComparison]::OrdinalIgnoreCase)) {
            throw ("Package '{0}' has an invalid app-state archive: {1}" -f [string]$package.DisplayName, [string]$packageAppState.Message)
        }
        if ([string]::Equals([string]$packageAppState.Status, 'ready', [System.StringComparison]::OrdinalIgnoreCase)) {
            Assert-ClagnosPackageAppStateArchivePortable -ZipPath ([string]$packageAppState.ZipPath)
        }
        $run = Invoke-ClagnosTaskExecutionWithTarget -Runtime $runtime -Options $Options -OperationName 'package' -Stage 'update' -Requested ([string]$package.Id) -PackageTaskBlock ([psobject]$package.PackageTask) -AutoMode:$AutoMode -TaskOutcomeModeOverride 'strict'
        Write-Host ("Installed or updated {0}." -f [string]$package.DisplayName) -ForegroundColor Green
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
        $scriptText = New-ClagnosPackageUninstallScript -Package $package -Platform $platform
        $result = Invoke-ClagnosPackageGuestScript -Options $Options -Platform $platform -ScriptText $scriptText -TaskLabel ('package-uninstall-' + [string]$package.Id)
        $script:ClagnosPackageStatusCache = @{}
        $verify = Get-ClagnosPackageStatusSnapshot -Packages @($package) -Options $Options -Platform $platform
        if ([string]$verify[[string]$package.Id] -eq 'installed') {
            throw ("The uninstall command completed but {0} is still detected on the VM." -f [string]$package.DisplayName)
        }
        Write-Host ("Uninstall completed for {0}." -f [string]$package.DisplayName) -ForegroundColor Green
        return $result
    }
    throw ("Unsupported package action '{0}'." -f $Action)
}
