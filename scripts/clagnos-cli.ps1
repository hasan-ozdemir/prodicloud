[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$CliTokens
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$env:PYTHONDONTWRITEBYTECODE = '1'

$script:ClagnosUiRepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$script:ClagnosUiBackendPath = Join-Path $script:ClagnosUiRepoRoot 'clagnos.ps1'
$script:ClagnosUiStartupTokens = $null
if ($null -ne $CliTokens) {
    $script:ClagnosUiStartupTokens = [string[]]@($CliTokens | ForEach-Object { [string]$_ })
}
$script:ClagnosUiSubscription = $null
$script:ClagnosUiSubscriptionError = ''
$script:ClagnosUiSelectedResourceGroup = ''
$script:ClagnosUiSelectedVmName = ''
$script:ClagnosUiResourceCacheError = ''
$script:ClagnosUiSubscriptionValidatedAtUtc = [DateTime]::MinValue
$script:ClagnosUiCloudSubscriptionRows = $null
$script:ClagnosUiCloudSubscriptionRowsValidatedAtUtc = [DateTime]::MinValue
$script:ClagnosUiAzureCliActiveSubscriptionId = ''
$script:ClagnosUiAzureCliActiveSubscriptionValidatedAtUtc = [DateTime]::MinValue
$script:ClagnosUiInventoryCache = $null
$script:ClagnosUiAzureReadCache = @{}
$script:ClagnosUiInventoryValidationSeconds = 60
$script:ClagnosUiReadCacheSeconds = 45
$script:ClagnosUiInventoryMaximumStaleSeconds = 300
$script:ClagnosUiCacheWorkerProcess = $null
$script:ClagnosUiCacheWorkerSubscriptionId = ''
$script:ClagnosUiCacheWorkerStopPath = ''
$script:ClagnosUiInventoryCacheFilePath = ''
$script:ClagnosUiInventoryCacheFileLastWriteUtc = [DateTime]::MinValue
$script:ClagnosUiCacheRootPath = ''

if (-not (Test-Path -LiteralPath $script:ClagnosUiBackendPath)) {
    throw "Clagnos runtime was not found: $script:ClagnosUiBackendPath"
}

. $script:ClagnosUiBackendPath

# The dot-sourced runtime declares the same CliTokens parameter. Restore the
# launcher arguments saved above before deciding between command and TUI mode.
$CliTokens = if ($null -ne $script:ClagnosUiStartupTokens) { [string[]]$script:ClagnosUiStartupTokens } else { $null }
if ($null -ne $CliTokens -and @($CliTokens).Count -gt 0) {
    if (@($CliTokens).Count -eq 1 -and [string]$CliTokens[0] -match '^(?i)--version(?:=(?:1|true|yes|on)?)?$') {
        Write-Host ("clagnos version {0}" -f (Get-ClagnosCliVersionInfo))
        return
    }
    try {
        $commandName = [string]$CliTokens[0]
        $rawArguments = if (@($CliTokens).Count -gt 1) { @($CliTokens[1..(@($CliTokens).Count - 1)]) } else { @() }
        $parsedCli = Parse-ClagnosCliArguments -CommandToken $commandName -RawArgs $rawArguments
        Invoke-ClagnosCommandDispatcher -CommandName ([string]$parsedCli.Command) -Options $parsedCli.Options -HelpTopic ([string]$parsedCli.HelpTopic)
        return
    }
    catch {
        Write-ClagnosUiError -ErrorRecord $_
        exit 2
    }
}

function Update-ClagnosUiSubscription {
    param([switch]$Force)

    if (-not $Force -and $null -ne $script:ClagnosUiSubscription -and $script:ClagnosUiSubscriptionValidatedAtUtc -ne [DateTime]::MinValue) {
        $subscriptionAge = ([DateTime]::UtcNow - $script:ClagnosUiSubscriptionValidatedAtUtc).TotalSeconds
        if ($subscriptionAge -lt 60) { return }
    }

    $previousSubscriptionId = if ($null -ne $script:ClagnosUiSubscription) { [string]$script:ClagnosUiSubscription.SubscriptionId } else { '' }
    try {
        $script:ClagnosUiSubscription = Initialize-ClagnosCommandSubscriptionState -CommandName 'list' -Options @{}
        $script:ClagnosUiSubscriptionError = ''
    }
    catch {
        $script:ClagnosUiSubscription = $null
        $script:ClagnosUiSubscriptionError = [string]$_.Exception.Message
    }

    $envPath = Join-Path $script:ClagnosUiRepoRoot '.env'
    $config = Read-DotEnvFile -Path $envPath
    $script:ClagnosUiSelectedResourceGroup = [string](Get-ConfigValue -Config $config -Key 'SELECTED_RESOURCE_GROUP' -DefaultValue '')
    $script:ClagnosUiSelectedVmName = [string](Get-ConfigValue -Config $config -Key 'SELECTED_VM_NAME' -DefaultValue '')
    if ($null -eq $script:ClagnosUiSubscription) {
        $configuredId = [string](Get-ConfigValue -Config $config -Key 'SELECTED_AZURE_SUBSCRIPTION_ID' -DefaultValue '')
        if (-not [string]::IsNullOrWhiteSpace($configuredId)) {
            $script:ClagnosUiSubscription = [pscustomobject]@{
                SubscriptionId = $configuredId
                SubscriptionName = 'Sign-in required to resolve subscription name'
                ResolutionSource = 'env'
            }
        }
    }

    $script:ClagnosUiSubscriptionValidatedAtUtc = [DateTime]::UtcNow
    $currentSubscriptionId = if ($null -ne $script:ClagnosUiSubscription) { [string]$script:ClagnosUiSubscription.SubscriptionId } else { '' }
    if (-not [string]::Equals($previousSubscriptionId, $currentSubscriptionId, [System.StringComparison]::OrdinalIgnoreCase)) {
        Reset-ClagnosUiResourceCache -Reason 'subscription changed'
    }
}

function Reset-ClagnosUiResourceCache {
    param([string]$Reason = 'explicit refresh')

    $script:ClagnosUiInventoryCache = $null
    $script:ClagnosUiAzureReadCache = @{}
    $script:ClagnosUiInventoryCacheFilePath = ''
    $script:ClagnosUiInventoryCacheFileLastWriteUtc = [DateTime]::MinValue
}

function Test-ClagnosUiBackgroundCacheWorkerDisabled {
    return ([string]$env:CLAGNOS_TUI_DISABLE_BACKGROUND_CACHE_WORKER).Trim().ToLowerInvariant() -in @('1','true','yes','on')
}

function Get-ClagnosUiInventoryCachePaths {
    param([string]$SubscriptionId)

    $root = [string]$env:CLAGNOS_TUI_CACHE_ROOT
    if ([string]::IsNullOrWhiteSpace($root)) { $root = [string]$env:LOCALAPPDATA }
    if ([string]::IsNullOrWhiteSpace($root)) { $root = [System.IO.Path]::GetTempPath() }
    $cacheRoot = Join-Path $root 'Clagnos\cache'
    $bytes = [System.Text.Encoding]::UTF8.GetBytes(([string]$SubscriptionId).ToLowerInvariant())
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $key = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
    return [pscustomobject]@{
        Root = $cacheRoot
        Cache = Join-Path $cacheRoot ('azure-inventory-{0}.json' -f $key)
        Status = Join-Path $cacheRoot ('azure-inventory-{0}.status.json' -f $key)
        Request = Join-Path $cacheRoot ('azure-inventory-{0}.refresh' -f $key)
        PackageRequest = Join-Path $cacheRoot ('azure-inventory-{0}.package-refresh.json' -f $key)
        Stop = Join-Path $cacheRoot ('azure-inventory-{0}.stop' -f $key)
    }
}

function ConvertTo-ClagnosUiUtcDateTime {
    param([Parameter(Mandatory = $true)][object]$Value)

    if ($Value -is [DateTime]) { return ([DateTime]$Value).ToUniversalTime() }
    return [DateTime]::Parse([string]$Value,[System.Globalization.CultureInfo]::InvariantCulture,[System.Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
}

function Import-ClagnosUiInventoryCacheFromDisk {
    param([switch]$Force)

    if ($null -eq $script:ClagnosUiSubscription) { return $script:ClagnosUiInventoryCache }
    $subscriptionId = [string]$script:ClagnosUiSubscription.SubscriptionId
    $paths = Get-ClagnosUiInventoryCachePaths -SubscriptionId $subscriptionId
    if (-not (Test-Path -LiteralPath $paths.Cache -PathType Leaf)) { return $script:ClagnosUiInventoryCache }
    try {
        $file = Get-Item -LiteralPath $paths.Cache -ErrorAction Stop
        if (-not $Force -and [string]::Equals([string]$script:ClagnosUiInventoryCacheFilePath,[string]$paths.Cache,[System.StringComparison]::OrdinalIgnoreCase) -and $file.LastWriteTimeUtc -eq $script:ClagnosUiInventoryCacheFileLastWriteUtc) {
            return $script:ClagnosUiInventoryCache
        }
        $loaded = ConvertFrom-JsonCompat -InputObject ([string](Get-Content -LiteralPath $paths.Cache -Raw -ErrorAction Stop))
        if ($null -eq $loaded -or -not [string]::Equals([string]$loaded.SubscriptionId,$subscriptionId,[System.StringComparison]::OrdinalIgnoreCase)) { return $null }
        $validatedAt = ConvertTo-ClagnosUiUtcDateTime -Value $loaded.LastValidatedAtUtc
        if (Test-Path -LiteralPath $paths.Request -PathType Leaf) {
            try {
                $requestText = [string](Get-Content -LiteralPath $paths.Request -Raw -ErrorAction Stop)
                $requestedAt = [DateTime]::MinValue
                if ([DateTime]::TryParse($requestText,[System.Globalization.CultureInfo]::InvariantCulture,[System.Globalization.DateTimeStyles]::RoundtripKind,[ref]$requestedAt)) {
                    $requestedAt = $requestedAt.ToUniversalTime()
                    if ($requestedAt -gt $validatedAt) {
                        $loaded.IsDirty = $true
                        $loaded.DirtyReason = 'a persisted inventory refresh is pending'
                        if ($null -ne $loaded.PSObject.Properties['DirtySinceUtc']) { $loaded.DirtySinceUtc = $requestedAt }
                        else { $loaded | Add-Member -NotePropertyName 'DirtySinceUtc' -NotePropertyValue $requestedAt }
                    }
                }
            }
            catch { }
        }
        $snapshotAge = ([DateTime]::UtcNow - $validatedAt).TotalSeconds
        if ($snapshotAge -gt [int]$script:ClagnosUiInventoryMaximumStaleSeconds) { return $script:ClagnosUiInventoryCache }
        if ($null -ne $script:ClagnosUiInventoryCache -and [bool]$script:ClagnosUiInventoryCache.IsDirty) {
            $dirtySince = if ($null -ne $script:ClagnosUiInventoryCache.DirtySinceUtc) { [DateTime]$script:ClagnosUiInventoryCache.DirtySinceUtc } else { [DateTime]::MinValue }
            if ($validatedAt -le $dirtySince) { return $script:ClagnosUiInventoryCache }
        }
        if ($null -eq $script:ClagnosUiInventoryCache -or $validatedAt -ge [DateTime]$script:ClagnosUiInventoryCache.LastValidatedAtUtc -or [bool]$script:ClagnosUiInventoryCache.IsDirty) {
            $script:ClagnosUiInventoryCache = $loaded
            $script:ClagnosUiInventoryCache.LastValidatedAtUtc = $validatedAt
            if ($null -eq $script:ClagnosUiInventoryCache.IsDirty) { $script:ClagnosUiInventoryCache.IsDirty = $false }
            if ($null -eq $script:ClagnosUiInventoryCache.PSObject.Properties['DirtySinceUtc']) {
                $script:ClagnosUiInventoryCache | Add-Member -NotePropertyName 'DirtySinceUtc' -NotePropertyValue ([DateTime]::MinValue)
            }
            elseif ($null -eq $script:ClagnosUiInventoryCache.DirtySinceUtc) { $script:ClagnosUiInventoryCache.DirtySinceUtc = [DateTime]::MinValue }
        }
        $script:ClagnosUiInventoryCacheFilePath = [string]$paths.Cache
        $script:ClagnosUiInventoryCacheFileLastWriteUtc = [DateTime]$file.LastWriteTimeUtc
        return $script:ClagnosUiInventoryCache
    }
    catch {
        $script:ClagnosUiResourceCacheError = ('Cached inventory could not be read: {0}' -f [string]$_.Exception.Message)
        return $script:ClagnosUiInventoryCache
    }
}

function Get-ClagnosUiBackgroundCacheStatus {
    if ($null -eq $script:ClagnosUiSubscription) { return $null }
    $paths = Get-ClagnosUiInventoryCachePaths -SubscriptionId ([string]$script:ClagnosUiSubscription.SubscriptionId)
    if (-not (Test-Path -LiteralPath $paths.Status -PathType Leaf)) { return $null }
    try { return (ConvertFrom-JsonCompat -InputObject ([string](Get-Content -LiteralPath $paths.Status -Raw -ErrorAction Stop))) }
    catch { return $null }
}

function Request-ClagnosUiInventoryRefresh {
    param([switch]$Force)

    if ($null -eq $script:ClagnosUiSubscription) { return $false }
    if (Test-ClagnosUiBackgroundCacheWorkerDisabled) {
        Sync-ClagnosUiResourceCache -Force:$Force | Out-Null
        return $true
    }
    $paths = Get-ClagnosUiInventoryCachePaths -SubscriptionId ([string]$script:ClagnosUiSubscription.SubscriptionId)
    if (-not (Test-Path -LiteralPath $paths.Root -PathType Container)) { New-Item -ItemType Directory -Path $paths.Root -Force | Out-Null }
    Set-Content -LiteralPath $paths.Request -Value ([DateTime]::UtcNow.ToString('o')) -Encoding ASCII
    Start-ClagnosUiBackgroundCacheWorker | Out-Null
    return $true
}

function Start-ClagnosUiBackgroundCacheWorker {
    if (Test-ClagnosUiBackgroundCacheWorkerDisabled) { return $false }
    if ($null -eq $script:ClagnosUiSubscription -or [string]::IsNullOrWhiteSpace([string]$script:ClagnosUiSubscription.SubscriptionId)) { return $false }
    $subscriptionId = [string]$script:ClagnosUiSubscription.SubscriptionId
    if ($null -ne $script:ClagnosUiCacheWorkerProcess -and [string]::Equals([string]$script:ClagnosUiCacheWorkerSubscriptionId,$subscriptionId,[System.StringComparison]::OrdinalIgnoreCase)) {
        try { if (-not $script:ClagnosUiCacheWorkerProcess.HasExited) { return $true } } catch { }
    }

    $paths = Get-ClagnosUiInventoryCachePaths -SubscriptionId $subscriptionId
    if (-not (Test-Path -LiteralPath $paths.Root -PathType Container)) { New-Item -ItemType Directory -Path $paths.Root -Force | Out-Null }
    if ($null -ne $script:ClagnosUiCacheWorkerProcess -and -not [string]::IsNullOrWhiteSpace([string]$script:ClagnosUiCacheWorkerStopPath)) {
        try { Set-Content -LiteralPath $script:ClagnosUiCacheWorkerStopPath -Value 'stop' -Encoding ASCII } catch { }
        try { if (-not $script:ClagnosUiCacheWorkerProcess.HasExited) { [void]$script:ClagnosUiCacheWorkerProcess.WaitForExit(500) } } catch { }
        try { $script:ClagnosUiCacheWorkerProcess.Dispose() } catch { }
    }
    if (Test-Path -LiteralPath $paths.Stop) { Remove-Item -LiteralPath $paths.Stop -Force -ErrorAction SilentlyContinue }

    $workerPath = Join-Path $script:ClagnosUiRepoRoot 'scripts\clagnos-cache-worker.ps1'
    if (-not (Test-Path -LiteralPath $workerPath -PathType Leaf)) {
        $script:ClagnosUiResourceCacheError = ('Background cache worker was not found: {0}' -f $workerPath)
        return $false
    }
    $hostName = if ([string]$PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' }
    $hostCommand = Get-Command $hostName -ErrorAction SilentlyContinue
    if ($null -eq $hostCommand) {
        $script:ClagnosUiResourceCacheError = ('Background cache worker host is unavailable: {0}' -f $hostName)
        return $false
    }
    $arguments = @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$workerPath,'-SubscriptionId',$subscriptionId,'-CachePath',$paths.Cache,'-StatusPath',$paths.Status,'-RequestPath',$paths.Request,'-PackageRequestPath',$paths.PackageRequest,'-StopPath',$paths.Stop,'-OwnerProcessId',[string]$PID,'-RepositoryRoot',$script:ClagnosUiRepoRoot,'-RefreshIntervalSeconds',[string]$script:ClagnosUiInventoryValidationSeconds)
    $argumentText = (@($arguments | ForEach-Object { Convert-ClagnosProcessArgument -Value ([string]$_) }) -join ' ')
    try {
        $script:ClagnosUiCacheWorkerProcess = Start-Process -FilePath $hostCommand.Source -ArgumentList $argumentText -WorkingDirectory ([System.IO.Path]::GetTempPath()) -WindowStyle Hidden -PassThru -ErrorAction Stop
        $script:ClagnosUiCacheWorkerSubscriptionId = $subscriptionId
        $script:ClagnosUiCacheWorkerStopPath = [string]$paths.Stop
        return $true
    }
    catch {
        $script:ClagnosUiResourceCacheError = ('Background inventory worker could not start: {0}' -f [string]$_.Exception.Message)
        return $false
    }
}

function Stop-ClagnosUiBackgroundCacheWorker {
    if ($null -eq $script:ClagnosUiCacheWorkerProcess -or [string]::IsNullOrWhiteSpace([string]$script:ClagnosUiCacheWorkerStopPath)) { return }
    try { Set-Content -LiteralPath $script:ClagnosUiCacheWorkerStopPath -Value 'stop' -Encoding ASCII } catch { }
    try {
        if (-not $script:ClagnosUiCacheWorkerProcess.HasExited -and -not $script:ClagnosUiCacheWorkerProcess.WaitForExit(5000)) {
            Stop-Process -Id $script:ClagnosUiCacheWorkerProcess.Id -Force -ErrorAction SilentlyContinue
            [void]$script:ClagnosUiCacheWorkerProcess.WaitForExit(1000)
        }
    }
    catch { }
    try { $script:ClagnosUiCacheWorkerProcess.Dispose() } catch { }
    $script:ClagnosUiCacheWorkerProcess = $null
}

function Request-ClagnosUiPackageStatusRefresh {
    param(
        [psobject]$Vm,
        [string[]]$Catalogs = @('builtin'),
        [switch]$Force
    )

    if ($null -eq $Vm -or (Test-ClagnosUiBackgroundCacheWorkerDisabled)) { return $false }
    $platform = if ([string]::Equals([string]$Vm.storageProfile.osDisk.osType,'Windows',[System.StringComparison]::OrdinalIgnoreCase)) { 'windows' } else { 'linux' }
    $options = New-ClagnosUiTargetOptions -Vm $Vm
    $staleCatalogs = @()
    foreach ($catalog in @($Catalogs | Select-Object -Unique)) {
        $packages = if ([string]::Equals([string]$catalog,[string]$Catalogs[0],[System.StringComparison]::OrdinalIgnoreCase)) { @($statusRuntime) } else { @(Get-ClagnosPackageCatalog -Platform $platform -Catalog ([string]$catalog)) }
        if (@($packages).Count -eq 0) { continue }
        $entry = Get-ClagnosPackageStatusCacheEntry -Packages $packages -Options $options -Platform $platform
        if ($Force -or $null -eq $entry -or -not [bool]$entry.IsFresh) { $staleCatalogs += [string]$catalog }
    }
    if (@($staleCatalogs).Count -eq 0) { return $false }
    $subscriptionId = [string]$script:ClagnosUiSubscription.SubscriptionId
    $paths = Get-ClagnosUiInventoryCachePaths -SubscriptionId $subscriptionId
    if (-not (Test-Path -LiteralPath $paths.Root -PathType Container)) { New-Item -ItemType Directory -Path $paths.Root -Force | Out-Null }
    $request = [ordered]@{
        SubscriptionId = $subscriptionId
        ResourceGroup = [string]$Vm.ClagnosResourceGroup
        VmName = [string]$Vm.name
        Platform = $platform
        Catalogs = @($staleCatalogs)
        RequestedAtUtc = [DateTime]::UtcNow.ToString('o')
    }
    $temporaryPath = '{0}.{1}.tmp' -f $paths.PackageRequest,$PID
    Set-Content -LiteralPath $temporaryPath -Value (ConvertTo-Json -InputObject $request -Depth 10 -Compress) -Encoding UTF8
    Move-Item -LiteralPath $temporaryPath -Destination $paths.PackageRequest -Force
    return (Start-ClagnosUiBackgroundCacheWorker)
}

function Invalidate-ClagnosUiResourceCache {
    param(
        [string]$Reason = 'resource mutation',
        [string]$ResourceGroup = ''
    )

    if ($null -eq $script:ClagnosUiInventoryCache) { return }
    $script:ClagnosUiInventoryCache.IsDirty = $true
    $script:ClagnosUiInventoryCache.DirtyReason = [string]$Reason
    $script:ClagnosUiInventoryCache.DirtySinceUtc = [DateTime]::UtcNow
    if (-not [string]::IsNullOrWhiteSpace([string]$ResourceGroup)) {
        $script:ClagnosUiInventoryCache.DirtyResourceGroup = [string]$ResourceGroup
    }
    $script:ClagnosUiAzureReadCache = @{}
    Request-ClagnosUiInventoryRefresh -Force | Out-Null
}

function Get-ClagnosUiManagedTagValue {
    param([psobject]$ResourceGroup)

    if ($null -eq $ResourceGroup -or $null -eq $ResourceGroup.tags) { return '' }
    $tag = @($ResourceGroup.tags.PSObject.Properties | Where-Object { [string]::Equals([string]$_.Name, 'managed-by', [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
    if (@($tag).Count -eq 0) { return '' }
    return [string]$tag[0].Value
}

function Get-ClagnosUiResourceGroupNameFromResource {
    param([psobject]$Resource)

    if (-not [string]::IsNullOrWhiteSpace([string]$Resource.resourceGroup)) { return [string]$Resource.resourceGroup }
    $resourceId = [string]$Resource.id
    if ($resourceId -match '(?i)/resourceGroups/([^/]+)') { return [string]$Matches[1] }
    return ''
}

function Get-ClagnosUiInventorySignature {
    param(
        [object[]]$Groups,
        [object[]]$Resources,
        [object[]]$VirtualMachines
    )

    $signatureLines = New-Object 'System.Collections.Generic.List[string]'
    foreach ($group in @(ConvertTo-ObjectArrayCompat -InputObject $Groups | Sort-Object { [string]$_.id })) {
        $tagText = if ($null -ne $group.tags) { @($group.tags.PSObject.Properties | Sort-Object Name | ForEach-Object { '{0}={1}' -f [string]$_.Name, [string]$_.Value }) -join ';' } else { '' }
        $groupEtag = [string]$group.etag
        $groupFallback = if ([string]::IsNullOrWhiteSpace($groupEtag)) { ConvertTo-Json -InputObject $group -Depth 100 -Compress } else { '' }
        $signatureLines.Add(('group|{0}|{1}|{2}|{3}|{4}|{5}|{6}' -f [string]$group.id, [string]$group.name, $groupEtag, [string]$group.location, [string]$group.properties.provisioningState, $tagText, $groupFallback))
    }
    foreach ($resource in @(ConvertTo-ObjectArrayCompat -InputObject $Resources | Sort-Object { [string]$_.id })) {
        $resourceGroup = Get-ClagnosUiResourceGroupNameFromResource -Resource $resource
        $resourceState = [string]$resource.properties.provisioningState
        $resourceEtag = [string]$resource.etag
        $fallback = if ([string]::IsNullOrWhiteSpace([string]$resourceEtag)) { ConvertTo-Json -InputObject $resource -Depth 100 -Compress } else { '' }
        $signatureLines.Add(('resource|{0}|{1}|{2}|{3}|{4}|{5}' -f [string]$resource.id, [string]$resource.type, [string]$resourceEtag, $resourceGroup, $resourceState, $fallback))
    }
    foreach ($vm in @(ConvertTo-ObjectArrayCompat -InputObject $VirtualMachines | Sort-Object { [string]$_.id })) {
        $vmGroup = Get-ClagnosUiResourceGroupNameFromResource -Resource $vm
        $vmEtag = [string]$vm.etag
        $vmFallback = if ([string]::IsNullOrWhiteSpace($vmEtag)) { ConvertTo-Json -InputObject $vm -Depth 100 -Compress } else { '' }
        $signatureLines.Add(('vm|{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}|{9}' -f [string]$vm.id, $vmEtag, $vmGroup, [string]$vm.hardwareProfile.vmSize, [string]$vm.powerState, [string]$vm.provisioningState, [string]$vm.privateIps, [string]$vm.publicIps, [string]$vm.fqdns, $vmFallback))
    }

    $payload = [System.Text.Encoding]::UTF8.GetBytes(($signatureLines.ToArray() -join "`n"))
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($payload))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Sync-ClagnosUiResourceCache {
    param([switch]$Force)

    $subscriptionId = if ($null -ne $script:ClagnosUiSubscription) { [string]$script:ClagnosUiSubscription.SubscriptionId } else { '' }
    if ([string]::IsNullOrWhiteSpace([string]$subscriptionId)) {
        throw "Azure CLI sign-in is required to cache managed resources. Run 'az login' and retry."
    }

    if (-not $Force -and $null -ne $script:ClagnosUiInventoryCache) {
        $sameSubscription = [string]::Equals([string]$script:ClagnosUiInventoryCache.SubscriptionId, $subscriptionId, [System.StringComparison]::OrdinalIgnoreCase)
        $cacheAge = ([DateTime]::UtcNow - [DateTime]$script:ClagnosUiInventoryCache.LastValidatedAtUtc).TotalSeconds
        if ($sameSubscription -and -not [bool]$script:ClagnosUiInventoryCache.IsDirty -and $cacheAge -lt [int]$script:ClagnosUiInventoryValidationSeconds) {
            return $script:ClagnosUiInventoryCache
        }
    }

    $groupRows = @(ConvertTo-ObjectArrayCompat -InputObject (Invoke-ClagnosUiAzJson -Arguments @('group','list') -ForceRefresh))
    $managedGroups = @($groupRows | Where-Object {
        $tagValue = Get-ClagnosUiManagedTagValue -ResourceGroup $_
        [string]::Equals($tagValue, 'clagnos', [System.StringComparison]::OrdinalIgnoreCase) -or
        [string]::Equals($tagValue, 'az-vm', [System.StringComparison]::OrdinalIgnoreCase)
    } | Sort-Object { [string]$_.name })
    $managedGroupMap = @{}
    foreach ($group in @($managedGroups)) { $managedGroupMap[[string]$group.name.ToLowerInvariant()] = $group }

    $managedResources = @()
    foreach ($group in @($managedGroups)) {
        $groupName = [string]$group.name
        $groupResources = @(ConvertTo-ObjectArrayCompat -InputObject (Invoke-ClagnosUiAzJson -Arguments @('resource','list','--resource-group',$groupName) -ForceRefresh))
        $managedResources += @($groupResources | Where-Object {
            $resourceGroupName = Get-ClagnosUiResourceGroupNameFromResource -Resource $_
            [string]::IsNullOrWhiteSpace([string]$resourceGroupName) -or [string]::Equals([string]$resourceGroupName, $groupName, [System.StringComparison]::OrdinalIgnoreCase)
        })
    }
    $managedResources = @($managedResources | Sort-Object { [string]$_.id })

    $allVms = @()
    if (@($managedGroups).Count -gt 0) {
        $allVms = @(ConvertTo-ObjectArrayCompat -InputObject (Invoke-ClagnosUiAzJson -Arguments @('vm','list','--show-details') -ForceRefresh))
    }
    $managedVms = @($allVms | Where-Object {
        $groupName = Get-ClagnosUiResourceGroupNameFromResource -Resource $_
        -not [string]::IsNullOrWhiteSpace([string]$groupName) -and $managedGroupMap.ContainsKey([string]$groupName.ToLowerInvariant())
    } | Sort-Object { [string]$_.name }, { Get-ClagnosUiResourceGroupNameFromResource -Resource $_ })
    foreach ($vm in @($managedVms)) {
        $groupName = Get-ClagnosUiResourceGroupNameFromResource -Resource $vm
        $vm | Add-Member -NotePropertyName 'ClagnosResourceGroup' -NotePropertyValue $groupName -Force
        $vm | Add-Member -NotePropertyName 'ClagnosSubscriptionId' -NotePropertyValue $subscriptionId -Force
    }

    $signature = Get-ClagnosUiInventorySignature -Groups $managedGroups -Resources $managedResources -VirtualMachines $managedVms
    $previousSignature = if ($null -ne $script:ClagnosUiInventoryCache -and [string]::Equals([string]$script:ClagnosUiInventoryCache.SubscriptionId, $subscriptionId, [System.StringComparison]::OrdinalIgnoreCase)) { [string]$script:ClagnosUiInventoryCache.Signature } else { '' }
    $snapshotChanged = -not [string]::Equals($previousSignature, $signature, [System.StringComparison]::Ordinal)
    if (-not $snapshotChanged -and $null -ne $script:ClagnosUiInventoryCache) {
        $script:ClagnosUiInventoryCache.LastValidatedAtUtc = [DateTime]::UtcNow
        $script:ClagnosUiInventoryCache.IsDirty = $false
        $script:ClagnosUiInventoryCache.DirtyReason = ''
        $script:ClagnosUiInventoryCache.DirtyResourceGroup = ''
        $script:ClagnosUiInventoryCache.DirtySinceUtc = [DateTime]::MinValue
        $script:ClagnosUiInventoryCache.Changed = $false
        return $script:ClagnosUiInventoryCache
    }
    $script:ClagnosUiAzureReadCache = @{}

    $script:ClagnosUiInventoryCache = @{
        SubscriptionId = $subscriptionId
        Groups = @($managedGroups)
        Resources = @($managedResources)
        VirtualMachines = @($managedVms)
        Signature = $signature
        LastValidatedAtUtc = [DateTime]::UtcNow
        IsDirty = $false
        DirtyReason = ''
        DirtyResourceGroup = ''
        DirtySinceUtc = [DateTime]::MinValue
        Changed = $snapshotChanged
    }
    return $script:ClagnosUiInventoryCache
}

function Ensure-ClagnosUiResourceCache {
    $snapshot = Import-ClagnosUiInventoryCacheFromDisk
    if (Test-ClagnosUiBackgroundCacheWorkerDisabled) {
        if ($null -eq $snapshot -or [bool]$snapshot.IsDirty) { return (Sync-ClagnosUiResourceCache -Force) }
        $cacheAge = ([DateTime]::UtcNow - [DateTime]$snapshot.LastValidatedAtUtc).TotalSeconds
        if ($cacheAge -ge [int]$script:ClagnosUiInventoryValidationSeconds) { return (Sync-ClagnosUiResourceCache -Force) }
        return $snapshot
    }

    if ($null -eq $snapshot) {
        $workerStarted = Start-ClagnosUiBackgroundCacheWorker
        if (-not $workerStarted -and -not [string]::IsNullOrWhiteSpace([string]$script:ClagnosUiResourceCacheError)) { throw [string]$script:ClagnosUiResourceCacheError }
        $status = Get-ClagnosUiBackgroundCacheStatus
        if ($null -ne $status -and [string]$status.State -eq 'error') { throw [string]$status.Message }
        throw 'Managed inventory is warming in the background. Return to this screen or request refresh in a moment.'
    }
    if ([bool]$snapshot.IsDirty) {
        Start-ClagnosUiBackgroundCacheWorker | Out-Null
        Request-ClagnosUiInventoryRefresh -Force | Out-Null
        $status = Get-ClagnosUiBackgroundCacheStatus
        if ($null -ne $status -and [string]$status.State -eq 'error') { throw ('Managed inventory refresh failed: {0}' -f [string]$status.Message) }
        throw ('Managed inventory is revalidating after {0}. Return to this screen in a moment.' -f [string]$snapshot.DirtyReason)
    }

    $cacheAge = ([DateTime]::UtcNow - [DateTime]$snapshot.LastValidatedAtUtc).TotalSeconds
    if ($cacheAge -ge [int]$script:ClagnosUiInventoryValidationSeconds) {
        Request-ClagnosUiInventoryRefresh -Force | Out-Null
        if ($cacheAge -gt [int]$script:ClagnosUiInventoryMaximumStaleSeconds) {
            throw 'Managed inventory snapshot is too old to use while its background refresh runs.'
        }
    }
    return $snapshot
}

function Get-ClagnosUiInventorySnapshotForSharedRuntime {
    param(
        [int]$MaximumAgeSeconds = 60,
        [string]$SubscriptionId = ''
    )

    $snapshot = $script:ClagnosUiInventoryCache
    if ($null -eq $snapshot -or [bool]$snapshot.IsDirty) { return $null }
    if (-not [string]::IsNullOrWhiteSpace([string]$SubscriptionId) -and -not [string]::Equals([string]$snapshot.SubscriptionId,[string]$SubscriptionId,[System.StringComparison]::OrdinalIgnoreCase)) { return $null }
    try {
        $age = ([DateTime]::UtcNow - [DateTime]$snapshot.LastValidatedAtUtc).TotalSeconds
        if ($age -gt [Math]::Max([int]$MaximumAgeSeconds,0)) { return $null }
    }
    catch { return $null }
    return $snapshot
}

function Get-ClagnosUiResourcesForGroup {
    param([string]$ResourceGroup)

    $snapshot = Ensure-ClagnosUiResourceCache
    return @($snapshot.Resources | Where-Object { [string]::Equals((Get-ClagnosUiResourceGroupNameFromResource -Resource $_), $ResourceGroup, [System.StringComparison]::OrdinalIgnoreCase) })
}

function Get-ClagnosUiCachedResourceById {
    param([string]$ResourceId)

    if ([string]::IsNullOrWhiteSpace([string]$ResourceId)) { return $null }
    $snapshot = Ensure-ClagnosUiResourceCache
    $match = @($snapshot.Resources | Where-Object { [string]::Equals([string]$_.id, $ResourceId, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
    if (@($match).Count -gt 0) { return $match[0] }
    return $null
}

function Get-ClagnosUiCachedResourcesForType {
    param(
        [string]$Type,
        [string]$ResourceGroup = ''
    )

    $snapshot = Ensure-ClagnosUiResourceCache
    $typeMap = @{
        disk = 'Microsoft.Compute/disks'
        vnet = 'Microsoft.Network/virtualNetworks'
        subnet = 'Microsoft.Network/virtualNetworks/subnets'
        nic = 'Microsoft.Network/networkInterfaces'
        ip = 'Microsoft.Network/publicIPAddresses'
        nsg = 'Microsoft.Network/networkSecurityGroups'
        'nsg-rule' = 'Microsoft.Network/networkSecurityGroups/securityRules'
    }
    if (-not $typeMap.ContainsKey([string]$Type)) { return @() }
    $resourceType = [string]$typeMap[[string]$Type]
    return @(
        $snapshot.Resources | Where-Object {
            [string]::Equals([string]$_.type, $resourceType, [System.StringComparison]::OrdinalIgnoreCase) -and
            ([string]::IsNullOrWhiteSpace([string]$ResourceGroup) -or [string]::Equals((Get-ClagnosUiResourceGroupNameFromResource -Resource $_), $ResourceGroup, [System.StringComparison]::OrdinalIgnoreCase))
        }
    )
}

function Get-ClagnosUiCachedComponentRows {
    param(
        [string]$Type,
        [string]$ResourceGroup = ''
    )

    $snapshot = Ensure-ClagnosUiResourceCache
    $rows = New-Object 'System.Collections.Generic.List[object]'
    switch ([string]$Type) {
        'group' {
            foreach ($group in @($snapshot.Groups | Where-Object { [string]::IsNullOrWhiteSpace([string]$ResourceGroup) -or [string]::Equals([string]$_.name, $ResourceGroup, [System.StringComparison]::OrdinalIgnoreCase) })) {
                $rows.Add([pscustomobject]@{ Name = [string]$group.name; Parent = ''; Id = [string]$group.id; ResourceGroup = [string]$group.name; Type = 'Microsoft.Resources/resourceGroups'; Resource = $group })
            }
        }
        'vm' {
            foreach ($vm in @($snapshot.VirtualMachines | Where-Object { [string]::IsNullOrWhiteSpace([string]$ResourceGroup) -or [string]::Equals([string]$_.ClagnosResourceGroup, $ResourceGroup, [System.StringComparison]::OrdinalIgnoreCase) })) {
                $rows.Add([pscustomobject]@{ Name = [string]$vm.name; Parent = ''; Id = [string]$vm.id; ResourceGroup = [string]$vm.ClagnosResourceGroup; Type = 'Microsoft.Compute/virtualMachines'; Resource = $vm })
            }
        }
        'subnet' {
            foreach ($vnet in @(Get-ClagnosUiCachedResourcesForType -Type 'vnet' -ResourceGroup $ResourceGroup)) {
                $vnetProperties = if ($null -ne $vnet.properties) { $vnet.properties } else { $vnet }
                foreach ($subnet in @(ConvertTo-ObjectArrayCompat -InputObject $vnetProperties.subnets)) {
                    $rows.Add([pscustomobject]@{ Name = [string]$subnet.name; Parent = [string]$vnet.name; Id = [string]$subnet.id; ResourceGroup = (Get-ClagnosUiResourceGroupNameFromResource -Resource $vnet); Type = 'Microsoft.Network/virtualNetworks/subnets'; Resource = $subnet })
                }
            }
        }
        'nsg-rule' {
            foreach ($nsg in @(Get-ClagnosUiCachedResourcesForType -Type 'nsg' -ResourceGroup $ResourceGroup)) {
                $nsgProperties = if ($null -ne $nsg.properties) { $nsg.properties } else { $nsg }
                foreach ($rule in @(ConvertTo-ObjectArrayCompat -InputObject $nsgProperties.securityRules)) {
                    $rows.Add([pscustomobject]@{ Name = [string]$rule.name; Parent = [string]$nsg.name; Id = [string]$rule.id; ResourceGroup = (Get-ClagnosUiResourceGroupNameFromResource -Resource $nsg); Type = 'Microsoft.Network/networkSecurityGroups/securityRules'; Resource = $rule })
                }
            }
        }
        default {
            foreach ($resource in @(Get-ClagnosUiCachedResourcesForType -Type $Type -ResourceGroup $ResourceGroup)) {
                $rows.Add([pscustomobject]@{ Name = [string]$resource.name; Parent = ''; Id = [string]$resource.id; ResourceGroup = (Get-ClagnosUiResourceGroupNameFromResource -Resource $resource); Type = [string]$resource.type; Resource = $resource })
            }
        }
    }
    return @($rows.ToArray() | Sort-Object { [string]$_.ResourceGroup }, { [string]$_.Parent }, { [string]$_.Name })
}

function Get-ClagnosUiCachedInventoryRows {
    param(
        [string]$TypeName,
        [string]$ResourceGroup = ''
    )

    $snapshot = Ensure-ClagnosUiResourceCache
    $activeGroup = [string]$script:ClagnosUiSelectedResourceGroup
    if ($TypeName -eq 'group') {
        return @(
            $snapshot.Groups |
                Where-Object { [string]::IsNullOrWhiteSpace([string]$ResourceGroup) -or [string]::Equals([string]$_.name, $ResourceGroup, [System.StringComparison]::OrdinalIgnoreCase) } |
                ForEach-Object {
                    $activeLabel = if ([string]::Equals([string]$_.name, $activeGroup, [System.StringComparison]::OrdinalIgnoreCase)) { ' [active]' } else { '' }
                    $location = if ([string]::IsNullOrWhiteSpace([string]$_.location)) { '(unknown)' } else { [string]$_.location }
                    $state = if ([string]::IsNullOrWhiteSpace([string]$_.properties.provisioningState)) { '(unknown)' } else { [string]$_.properties.provisioningState }
                    '{0}{1} | location={2} | provisioning={3}' -f [string]$_.name, $activeLabel, $location, $state
                } |
                Sort-Object -Unique
        )
    }

    $componentType = if ($TypeName -eq 'vm') { 'vm' } else { [string]$TypeName }
    $rows = @(Get-ClagnosUiCachedComponentRows -Type $componentType -ResourceGroup $ResourceGroup)
    if ($TypeName -eq 'vm') {
        return @($rows | ForEach-Object { '{0} | {1}' -f [string]$_.ResourceGroup, [string]$_.Name } | Sort-Object -Unique)
    }
    if ($TypeName -eq 'subnet') {
        return @($rows | ForEach-Object { '{0} | {1} | {2}' -f [string]$_.ResourceGroup, [string]$_.Parent, [string]$_.Name } | Sort-Object -Unique)
    }
    if ($TypeName -eq 'nsg-rule') {
        return @($rows | ForEach-Object { '{0} | {1} | {2}' -f [string]$_.ResourceGroup, [string]$_.Parent, [string]$_.Name } | Sort-Object -Unique)
    }
    return @($rows | ForEach-Object { '{0} | {1}' -f [string]$_.ResourceGroup, [string]$_.Name } | Sort-Object -Unique)
}

function Get-ClagnosUiAzureCliActiveSubscriptionId {
    if (-not [string]::IsNullOrWhiteSpace([string]$script:ClagnosUiAzureCliActiveSubscriptionId) -and $script:ClagnosUiAzureCliActiveSubscriptionValidatedAtUtc -ne [DateTime]::MinValue) {
        $activeAge = ([DateTime]::UtcNow - [DateTime]$script:ClagnosUiAzureCliActiveSubscriptionValidatedAtUtc).TotalSeconds
        if ($activeAge -lt 15) { return [string]$script:ClagnosUiAzureCliActiveSubscriptionId }
    }
    $activeId = Invoke-ClagnosWithBypassedAzCliSubscription -Action {
        az account show --query id -o tsv --only-show-errors 2>$null
    }
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$activeId)) {
        throw "Azure CLI could not resolve its active subscription. Run 'az login' and retry."
    }
    $script:ClagnosUiAzureCliActiveSubscriptionId = ([string]$activeId).Trim()
    $script:ClagnosUiAzureCliActiveSubscriptionValidatedAtUtc = [DateTime]::UtcNow
    return [string]$script:ClagnosUiAzureCliActiveSubscriptionId
}

function Get-ClagnosUiCloudSubscriptionRows {
    if ($null -ne $script:ClagnosUiCloudSubscriptionRows -and $script:ClagnosUiCloudSubscriptionRowsValidatedAtUtc -ne [DateTime]::MinValue) {
        $cacheAge = ([DateTime]::UtcNow - [DateTime]$script:ClagnosUiCloudSubscriptionRowsValidatedAtUtc).TotalSeconds
        if ($cacheAge -lt 30) { return @($script:ClagnosUiCloudSubscriptionRows) }
    }
    $raw = Invoke-ClagnosWithBypassedAzCliSubscription -Action {
        az account list --all --refresh -o json --only-show-errors 2>$null
    }
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$raw)) {
        throw "Azure CLI could not refresh the subscription list. Run 'az login' and retry."
    }
    $rows = @(ConvertTo-ObjectArrayCompat -InputObject (ConvertFrom-JsonCompat -InputObject $raw) | Where-Object {
        $_ -ne $null -and -not [string]::IsNullOrWhiteSpace([string]$_.id)
    })
    $script:ClagnosUiCloudSubscriptionRows = @($rows | Sort-Object @{ Expression = { if ([bool]$_.isDefault) { 0 } else { 1 } } }, @{ Expression = { [string]$_.name } }, @{ Expression = { [string]$_.id } })
    $script:ClagnosUiCloudSubscriptionRowsValidatedAtUtc = [DateTime]::UtcNow
    return @($script:ClagnosUiCloudSubscriptionRows)
}

function Set-ClagnosUiActiveSubscription {
    param([psobject]$Subscription)

    if ($null -eq $Subscription -or [string]::IsNullOrWhiteSpace([string]$Subscription.id)) {
        throw 'Select an accessible Azure subscription first.'
    }
    if (-not [string]::Equals([string]$Subscription.state, 'Enabled', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'A disabled Azure subscription cannot be activated.'
    }

    $previousCliId = Get-ClagnosUiAzureCliActiveSubscriptionId
    $previousContext = Get-ClagnosResolvedSubscriptionContext
    $subscriptionId = [string]$Subscription.id
    try {
        az account set --subscription $subscriptionId --only-show-errors
        Assert-LastExitCode 'az account set'
    }
    catch {
        if (-not [string]::IsNullOrWhiteSpace($previousCliId)) {
            az account set --subscription $previousCliId --only-show-errors
            $null = $LASTEXITCODE
        }
        throw
    }
    if (Get-Command Reset-ClagnosAccessibleSubscriptionRowsCache -ErrorAction SilentlyContinue) { Reset-ClagnosAccessibleSubscriptionRowsCache }
    $script:ClagnosUiCloudSubscriptionRows = $null
    $script:ClagnosUiCloudSubscriptionRowsValidatedAtUtc = [DateTime]::MinValue
    $script:ClagnosUiAzureCliActiveSubscriptionId = $subscriptionId
    $script:ClagnosUiAzureCliActiveSubscriptionValidatedAtUtc = [DateTime]::UtcNow

    $verifiedId = Get-ClagnosUiAzureCliActiveSubscriptionId
    if (-not [string]::Equals($verifiedId, $subscriptionId, [System.StringComparison]::OrdinalIgnoreCase)) {
        if (-not [string]::IsNullOrWhiteSpace($previousCliId)) {
            az account set --subscription $previousCliId --only-show-errors
            $null = $LASTEXITCODE
        }
        throw 'Azure CLI did not confirm the selected active subscription; the previous CLI subscription was restored.'
    }

    try {
        Save-ClagnosSubscriptionIdToDotEnv `
            -EnvFilePath (Join-Path $script:ClagnosUiRepoRoot '.env') `
            -SubscriptionId $subscriptionId
    }
    catch {
        if (-not [string]::IsNullOrWhiteSpace($previousCliId)) {
            az account set --subscription $previousCliId --only-show-errors
            $null = $LASTEXITCODE
        }
        if ($null -ne $previousContext) {
            Set-ClagnosResolvedSubscriptionContext `
                -SubscriptionId ([string]$previousContext.SubscriptionId) `
                -SubscriptionName ([string]$previousContext.SubscriptionName) `
                -TenantId ([string]$previousContext.TenantId) `
                -ResolutionSource ([string]$previousContext.ResolutionSource)
        }
        throw
    }

    Set-ClagnosResolvedSubscriptionContext `
        -SubscriptionId $subscriptionId `
        -SubscriptionName ([string]$Subscription.name) `
        -TenantId ([string]$Subscription.tenantId) `
        -ResolutionSource 'interactive'
    $script:ClagnosUiSubscription = [pscustomobject]@{
        SubscriptionId = $subscriptionId
        SubscriptionName = [string]$Subscription.name
        TenantId = [string]$Subscription.tenantId
        ResolutionSource = 'interactive'
    }
    $script:ClagnosUiSubscriptionValidatedAtUtc = [DateTime]::UtcNow
    Reset-ClagnosUiResourceCache -Reason 'subscription selected'
    Write-Host ('Active Azure subscription: {0} ({1})' -f [string]$Subscription.name, $subscriptionId) -ForegroundColor Green
}

function Show-ClagnosUiCloudSubscriptions {
    while ($true) {
        Update-ClagnosUiSubscription
        Write-ClagnosUiHeader -Title 'Cloud subscriptions'
        try {
            $rows = @(Get-ClagnosUiCloudSubscriptionRows)
            $selectedContext = Get-ClagnosResolvedSubscriptionContext
            $activeId = Get-ClagnosUiAzureCliActiveSubscriptionId
            $selectedName = if ($null -ne $selectedContext) { [string]$selectedContext.SubscriptionName } else { '(none)' }
            $activeRow = @($rows | Where-Object { [string]::Equals([string]$_.id, $activeId, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
            $activeName = if (@($activeRow).Count -gt 0) { [string]$activeRow[0].name } else { $activeId }
            Write-Host ('Clagnos selected: {0}' -f $selectedName)
            Write-Host ('Azure CLI active: {0}' -f $activeName)
            $subscriptionOptions = @(
                $rows | ForEach-Object {
                    $markers = @()
                    if ($null -ne $selectedContext -and [string]::Equals([string]$_.id, [string]$selectedContext.SubscriptionId, [System.StringComparison]::OrdinalIgnoreCase)) { $markers += 'Clagnos selected' }
                    if ([string]::Equals([string]$_.id, $activeId, [System.StringComparison]::OrdinalIgnoreCase)) { $markers += 'Azure CLI active' }
                    $markerText = if ($markers.Count -gt 0) { ' [' + ($markers -join '; ') + ']' } else { '' }
                    $enabled = [string]::Equals([string]$_.state, 'Enabled', [System.StringComparison]::OrdinalIgnoreCase)
                    $stateText = if ($enabled) { 'Enabled' } else { 'not enabled' }
                    [pscustomobject]@{ Value = [string]$_.id; Label = ('{0} ({1})' -f [string]$_.name, [string]$_.id); Detail = (($markerText.Trim() + ' ' + $stateText).Trim()); Enabled = $enabled }
                }
            )
            $selection = Select-ClagnosNumberedOptionPage -Options $subscriptionOptions -Prompt 'Select active cloud subscription' -DefaultValue ([string]$selectedContext.SubscriptionId) -PageSize 12
            if ([string]$selection.Action -eq 'back') { if ([string]$selection.Input -eq 'q') { Stop-ClagnosUiBackgroundCacheWorker; exit }; return }
            if ([string]$selection.Action -ne 'selected') { continue }
            $selectedRow = @($rows | Where-Object { [string]::Equals([string]$_.id, [string]$selection.Value, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
            if (@($selectedRow).Count -eq 0) { continue }
            Set-ClagnosUiActiveSubscription -Subscription $selectedRow[0]
            Wait-ClagnosUiContinue
        }
        catch {
            Write-ClagnosUiError -ErrorRecord $_
            Wait-ClagnosUiContinue
            return
        }
    }
}

function Write-ClagnosUiHeader {
    param([string]$Title = 'Clagnos')

    Clear-Host
    Write-Host 'CLAGNOS' -ForegroundColor Cyan
    Write-Host 'one tool for all common cloud operations' -ForegroundColor DarkCyan
    if ($null -ne $script:ClagnosUiSubscription) {
        Write-Host ('Azure subscription: {0} ({1})' -f [string]$script:ClagnosUiSubscription.SubscriptionName, [string]$script:ClagnosUiSubscription.SubscriptionId) -ForegroundColor Gray
    }
    else {
        Write-Host 'Azure subscription: not signed in' -ForegroundColor Yellow
    }
    $cacheStatus = Get-ClagnosUiBackgroundCacheStatus
    if ($null -ne $cacheStatus -and [string]$cacheStatus.State -eq 'refreshing') {
        Write-Host ([string]$cacheStatus.Message) -ForegroundColor DarkGray
    }
    elseif ($null -ne $cacheStatus -and [string]$cacheStatus.State -eq 'error') {
        Write-Host ('Background inventory cache: {0}' -f [string]$cacheStatus.Message) -ForegroundColor Yellow
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$Title)) {
        Write-Host ''
        Write-Host $Title -ForegroundColor White
    }
    Write-Host ''
}

function Read-ClagnosUiChoice {
    param([string]$Prompt = 'Select an option')
    if (-not (Test-ClagnosUiBackgroundCacheWorkerDisabled)) { Import-ClagnosUiInventoryCacheFromDisk | Out-Null }
    return ([string](Read-Host $Prompt)).Trim()
}

function Read-ClagnosUiValidatedText {
    param(
        [string]$Prompt,
        [scriptblock]$Validator,
        [switch]$AllowBlank
    )

    while ($true) {
        $raw = Read-ClagnosUiChoice -Prompt $Prompt
        if ([string]::IsNullOrWhiteSpace([string]$raw) -and $AllowBlank) { return '' }
        try {
            if ($Validator) { return [string](& $Validator ([string]$raw)) }
            return ([string]$raw).Trim()
        }
        catch {
            Write-Host ([string]$_.Exception.Message) -ForegroundColor Yellow
        }
    }
}

function Wait-ClagnosUiContinue {
    [void](Read-Host 'Press Enter to return')
}

function Write-ClagnosUiError {
    param([object]$ErrorRecord)

    $friendly = Resolve-ClagnosFriendlyError -ErrorRecord $ErrorRecord -DefaultErrorSummary 'The operation did not complete.' -DefaultErrorHint "Review the reason and retry. Azure operations require 'az login'."
    Write-Host ''
    Write-Host ([string]$friendly.Summary) -ForegroundColor Red
    if (-not [string]::IsNullOrWhiteSpace([string]$friendly.ErrorMessage)) {
        Write-Host ([string]$friendly.ErrorMessage) -ForegroundColor Gray
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$friendly.Hint)) {
        Write-Host ('Next: {0}' -f [string]$friendly.Hint) -ForegroundColor Cyan
    }
}

function Invoke-ClagnosUiCommand {
    param(
        [Parameter(Mandatory = $true)][string]$CommandName,
        [hashtable]$Options = @{},
        [hashtable]$FrontendContext = @{}
    )

    $commandFailed = $false
    try {
        Invoke-ClagnosCommandDispatcher -CommandName $CommandName -Options $Options -FrontendContext $FrontendContext | Out-Null
    }
    catch {
        $commandFailed = $true
        Write-ClagnosUiError -ErrorRecord $_
    }

    $packageAction = ([string](Get-ClagnosCliOptionText -Options $Options -Name 'action')).ToLowerInvariant()
    $packageStateMayHaveChanged = ($CommandName -eq 'package' -and $packageAction -in @('install','uninstall') -and $commandFailed)
    if ($CommandName -in @('initialize','update')) { $packageStateMayHaveChanged = $true }
    if ($CommandName -eq 'task' -and -not (
        (Test-ClagnosCliOptionPresent -Options $Options -Name 'list') -or
        (Test-ClagnosCliOptionPresent -Options $Options -Name 'history') -or
        (Test-ClagnosCliOptionPresent -Options $Options -Name 'enable') -or
        (Test-ClagnosCliOptionPresent -Options $Options -Name 'disable')
    )) { $packageStateMayHaveChanged = $true }
    if ($packageStateMayHaveChanged -and (Get-Command Clear-ClagnosPackageStatusCache -ErrorAction SilentlyContinue)) {
        Clear-ClagnosPackageStatusCache
    }

    $mutatesAzureInventory = $CommandName -in @('create','initialize','update','do','component','move','resize','set','delete','task')
    if ($CommandName -eq 'do' -and [string]::Equals([string](Get-ClagnosCliOptionText -Options $Options -Name 'vm-action'), 'status', [System.StringComparison]::OrdinalIgnoreCase)) {
        $mutatesAzureInventory = $false
    }
    if ($CommandName -eq 'component' -and (Get-ClagnosCliOptionText -Options $Options -Name 'action') -in @('list','show')) {
        $mutatesAzureInventory = $false
    }
    if ($CommandName -eq 'task' -and (
        (Test-ClagnosCliOptionPresent -Options $Options -Name 'list') -or
        (Test-ClagnosCliOptionPresent -Options $Options -Name 'history') -or
        (Test-ClagnosCliOptionPresent -Options $Options -Name 'enable') -or
        (Test-ClagnosCliOptionPresent -Options $Options -Name 'disable')
    )) { $mutatesAzureInventory = $false }
    if ($mutatesAzureInventory) {
        # A failed Azure mutation can be partial, so invalidate after any such
        # command attempt and let the next screen reconcile against Azure.
        Invalidate-ClagnosUiResourceCache -Reason ("TUI {0} operation" -f $CommandName) -ResourceGroup ([string](Get-ClagnosCliOptionText -Options $Options -Name 'group'))
    }
    Wait-ClagnosUiContinue
    Update-ClagnosUiSubscription
}

function Invoke-ClagnosUiAzJson {
    param(
        [string[]]$Arguments,
        [switch]$ForceRefresh,
        [int]$CacheTtlSeconds = 45
    )

    $subscriptionId = if ($null -ne $script:ClagnosUiSubscription) { [string]$script:ClagnosUiSubscription.SubscriptionId } else { '' }
    if ([string]::IsNullOrWhiteSpace($subscriptionId)) {
        throw "Azure CLI sign-in is required. Run 'az login' and retry."
    }
    $cacheKey = $subscriptionId.ToLowerInvariant() + '|' + (@($Arguments | ForEach-Object { ([string]$_).Trim() }) -join [char]31)
    if (-not $ForceRefresh -and $CacheTtlSeconds -gt 0 -and $script:ClagnosUiAzureReadCache.ContainsKey($cacheKey)) {
        $cachedEntry = $script:ClagnosUiAzureReadCache[$cacheKey]
        $cachedAge = ([DateTime]::UtcNow - [DateTime]$cachedEntry.CreatedAtUtc).TotalSeconds
        if ($cachedAge -lt $CacheTtlSeconds) { return $cachedEntry.Value }
    }
    $azArguments = @($Arguments) + @('--subscription', $subscriptionId, '-o', 'json', '--only-show-errors')
    Write-ClagnosActionProgress -Action ('read Azure data for the TUI: az {0}' -f (@($Arguments | ForEach-Object { [string]$_ }) -join ' '))
    $json = & az @azArguments 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI could not complete the read request. Run 'az login' and verify the selected subscription."
    }
    if ([string]::IsNullOrWhiteSpace([string]$json)) {
        $result = @()
    }
    else {
        $result = ConvertFrom-JsonCompat -InputObject ([string]$json)
    }
    if ($CacheTtlSeconds -gt 0) {
        $script:ClagnosUiAzureReadCache[$cacheKey] = @{ CreatedAtUtc = [DateTime]::UtcNow; Value = $result }
    }
    return $result
}

function Get-ClagnosUiManagedGroups {
    param([switch]$IncludeLegacy)

    $snapshot = Ensure-ClagnosUiResourceCache
    $groups = @($snapshot.Groups)
    if (-not $IncludeLegacy) {
        $groups = @($groups | Where-Object { [string]::Equals((Get-ClagnosUiManagedTagValue -ResourceGroup $_), 'clagnos', [System.StringComparison]::OrdinalIgnoreCase) })
    }
    return @($groups | Sort-Object { [string]$_.name })
}

function Invoke-ClagnosUiLegacyTagMigration {
    param([object[]]$LegacyGroups)

    if (@($LegacyGroups).Count -eq 0) {
        return
    }
    Write-Host 'Legacy managed resource groups were found:' -ForegroundColor Yellow
    foreach ($group in @($LegacyGroups | Sort-Object { [string]$_.name })) {
        Write-Host ('  - {0}' -f [string]$group.name)
    }
    $answer = (Read-ClagnosUiChoice 'Move these groups to the Clagnos management tag now? Type yes or no').ToLowerInvariant()
    if ($answer -notin @('yes', 'y')) {
        Write-Host 'Legacy groups remain visible and were not changed.' -ForegroundColor Yellow
        return
    }

    foreach ($group in @($LegacyGroups)) {
        $groupName = [string]$group.name
        try {
            $tags = @()
            if ($null -ne $group.tags) {
                foreach ($property in @($group.tags.PSObject.Properties)) {
                    $key = [string]$property.Name
                    $value = [string]$property.Value
                    if ([string]::Equals($key, 'managed-by', [System.StringComparison]::OrdinalIgnoreCase)) {
                        $value = 'clagnos'
                    }
                    $tags += ('{0}={1}' -f $key, $value)
                }
            }
            if (-not (@($tags | Where-Object { $_ -like 'managed-by=*' }).Count -gt 0)) {
                $tags += 'managed-by=clagnos'
            }
            $subscriptionId = [string]$script:ClagnosUiSubscription.SubscriptionId
            & az group update --name $groupName --subscription $subscriptionId --tags @tags -o none --only-show-errors 2>$null
            if ($LASTEXITCODE -ne 0) {
                throw 'Azure rejected the resource group tag update.'
            }
            Invalidate-ClagnosUiResourceCache -Reason 'legacy group tag migration' -ResourceGroup $groupName
            Write-Host ('Migrated management tag: {0}' -f $groupName) -ForegroundColor Green
        }
        catch {
            Write-Host ('Tag migration failed for {0}: {1}' -f $groupName, $_.Exception.Message) -ForegroundColor Red
        }
    }
}

function Get-ClagnosUiVirtualComputers {
    $groups = @(Get-ClagnosUiManagedGroups -IncludeLegacy)
    $legacyGroups = @($groups | Where-Object {
        $value = ''
        if ($_.tags -and $_.tags.PSObject.Properties.Match('managed-by').Count -gt 0) { $value = [string]$_.tags.'managed-by' }
        [string]::Equals($value, 'az-vm', [System.StringComparison]::OrdinalIgnoreCase)
    })
    if (@($legacyGroups).Count -gt 0) {
        Invoke-ClagnosUiLegacyTagMigration -LegacyGroups $legacyGroups
        $groups = @(Get-ClagnosUiManagedGroups -IncludeLegacy)
    }

    $snapshot = Ensure-ClagnosUiResourceCache
    return @($snapshot.VirtualMachines | Sort-Object { [string]$_.name }, { [string]$_.ClagnosResourceGroup })
}

function Get-ClagnosUiPowerState {
    param(
        [string]$ResourceGroup,
        [string]$VmName,
        [string]$CachedPowerState = ''
    )

    if (-not [string]::IsNullOrWhiteSpace([string]$CachedPowerState)) {
        return [string]$CachedPowerState
    }

    try {
        $instance = Invoke-ClagnosUiAzJson -Arguments @('vm', 'get-instance-view', '--resource-group', $ResourceGroup, '--name', $VmName) -CacheTtlSeconds 15

        # Azure CLI wraps the Compute instance view under instanceView, while
        # the direct Compute Instance View REST response exposes statuses at
        # the root. Accept both documented response shapes.
        $statusRows = @()
        if ($null -ne $instance.instanceView) {
            $statusRows += @(ConvertTo-ObjectArrayCompat -InputObject $instance.instanceView.statuses)
        }
        if ($null -ne $instance.statuses) {
            $statusRows += @(ConvertTo-ObjectArrayCompat -InputObject $instance.statuses)
        }
        if ($null -ne $instance.properties -and $null -ne $instance.properties.instanceView) {
            $statusRows += @(ConvertTo-ObjectArrayCompat -InputObject $instance.properties.instanceView.statuses)
        }

        foreach ($status in @($statusRows)) {
            $statusCode = [string]$status.code
            if ($statusCode -match '^(?i)PowerState/(?<state>.+)$') {
                $displayStatus = [string]$status.displayStatus
                if (-not [string]::IsNullOrWhiteSpace($displayStatus)) {
                    return $displayStatus.Trim()
                }

                $powerState = [string]$Matches.state
                switch ($powerState.ToLowerInvariant()) {
                    'starting' { return 'VM starting' }
                    'running' { return 'VM running' }
                    'stopping' { return 'VM stopping' }
                    'stopped' { return 'VM stopped' }
                    'deallocating' { return 'VM deallocating' }
                    'deallocated' { return 'VM deallocated' }
                    default { return ('VM {0}' -f $powerState) }
                }
            }
        }
    }
    catch { return 'Unknown' }
    return 'Unknown'
}

function Get-ClagnosUiNestedVirtualizationGuestStatus {
    param([psobject]$Vm, [string]$PowerState)

    $resourceGroup = [string]$Vm.ClagnosResourceGroup
    $vmName = [string]$Vm.name
    if ([string]::IsNullOrWhiteSpace($resourceGroup) -or [string]::IsNullOrWhiteSpace($vmName)) {
        return [pscustomobject]@{ Known = $false; Enabled = $false; Evidence = @(); ErrorMessage = 'VM target details are incomplete.' }
    }
    if ([string]$PowerState -notmatch '(?i)running') {
        $powerStateKnownStopped = [string]$PowerState -match '(?i)(stopped|deallocated|hibernated|stopping|deallocating)'
        $errorMessage = if ($powerStateKnownStopped) { 'Guest validation requires a running VM.' } else { 'VM power state is unknown; guest validation was not run.' }
        return [pscustomobject]@{ Known = $false; AvailableToGuest = $null; Evidence = @(); ErrorMessage = $errorMessage }
    }

    if ($null -eq $script:ClagnosUiAzureReadCache) { $script:ClagnosUiAzureReadCache = @{} }
    $subscriptionId = [string]$Vm.ClagnosSubscriptionId
    $osType = if ([string]::Equals([string]$Vm.storageProfile.osDisk.osType,'Windows',[System.StringComparison]::OrdinalIgnoreCase)) { 'windows' } else { 'linux' }
    $cacheKey = ('nested-guest|{0}|{1}|{2}|{3}' -f $subscriptionId.ToLowerInvariant(),$resourceGroup.ToLowerInvariant(),$vmName.ToLowerInvariant(),$osType)
    if ($script:ClagnosUiAzureReadCache.ContainsKey($cacheKey)) {
        $cacheEntry = $script:ClagnosUiAzureReadCache[$cacheKey]
        $cacheAge = ([DateTime]::UtcNow - [DateTime]$cacheEntry.CreatedAtUtc).TotalSeconds
        $cacheTtl = if ([bool]$cacheEntry.Value.Known) { 45 } else { 10 }
        if ($cacheAge -lt $cacheTtl) { return $cacheEntry.Value }
    }

    $status = Get-ClagnosNestedVirtualizationGuestValidation `
        -ResourceGroup $resourceGroup `
        -VmName $vmName `
        -OsType $osType `
        -MaxAttempts 1 `
        -RetryDelaySeconds 1 `
        -SuppressError
    if ($null -eq $status) { $status = [pscustomobject]@{ Known = $false; AvailableToGuest = $null; Evidence = @(); ErrorMessage = 'Guest validation returned no result.' } }
    $script:ClagnosUiAzureReadCache[$cacheKey] = @{ CreatedAtUtc = [DateTime]::UtcNow; Value = $status }
    return $status
}

function Get-ClagnosUiCachedVm {
    param([psobject]$Vm)

    if ($null -eq $Vm) { return $null }
    $snapshot = Ensure-ClagnosUiResourceCache
    $resourceGroup = [string]$Vm.ClagnosResourceGroup
    $vmName = [string]$Vm.name
    $match = @(
        $snapshot.VirtualMachines |
            Where-Object {
                [string]::Equals([string]$_.name, $vmName, [System.StringComparison]::OrdinalIgnoreCase) -and
                [string]::Equals([string]$_.ClagnosResourceGroup, $resourceGroup, [System.StringComparison]::OrdinalIgnoreCase)
            } |
            Select-Object -First 1
    )
    if (@($match).Count -gt 0) { return $match[0] }
    return $null
}

function Get-ClagnosUiVmSizeFacts {
    param([string]$Location, [string]$Size)

    try {
        $sizes = @(ConvertTo-ObjectArrayCompat -InputObject (Invoke-ClagnosUiAzJson -Arguments @('vm', 'list-sizes', '--location', $Location)))
        $match = @($sizes | Where-Object { [string]::Equals([string]$_.name, $Size, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
        if (@($match).Count -gt 0) {
            return [pscustomobject]@{ Cores = [string]$match[0].numberOfCores; MemoryMb = [string]$match[0].memoryInMb }
        }
    }
    catch { }
    return [pscustomobject]@{ Cores = 'Unknown'; MemoryMb = 'Unknown' }
}

function Get-ClagnosUiCachedResourceModel {
    param([psobject]$Resource)

    if ($null -eq $Resource) { return $null }
    if ($null -ne $Resource.properties) { return $Resource.properties }
    return $Resource
}

function Format-ClagnosUiDetailValue {
    param(
        [AllowNull()][object]$Value,
        [string]$EmptyText = '(not available)'
    )

    if ($null -eq $Value) { return $EmptyText }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $EmptyText }
    return $text
}

function Get-ClagnosUiAzureResourceIdSegment {
    param(
        [string]$ResourceId,
        [string]$SegmentName
    )

    $parts = @(([string]$ResourceId).Trim('/') -split '/')
    for ($index = 0; $index -lt ($parts.Count - 1); $index++) {
        if ([string]::Equals([string]$parts[$index], [string]$SegmentName, [System.StringComparison]::OrdinalIgnoreCase)) {
            return [string]$parts[$index + 1]
        }
    }
    return ''
}

function Show-ClagnosUiVmDetails {
    param([psobject]$Vm)

    $resourceSnapshot = Ensure-ClagnosUiResourceCache
    $group = [string]$Vm.ClagnosResourceGroup
    $name = [string]$Vm.name
    $full = Get-ClagnosUiCachedVm -Vm $Vm
    $hasDetailedStorage = $null -ne $full -and $null -ne $full.storageProfile -and $null -ne $full.storageProfile.osDisk
    $hasDetailedNetwork = $null -ne $full -and $null -ne $full.networkProfile -and @((ConvertTo-ObjectArrayCompat -InputObject $full.networkProfile.networkInterfaces)).Count -gt 0
    if (-not $hasDetailedStorage -or -not $hasDetailedNetwork) {
        $full = Invoke-ClagnosUiAzJson -Arguments @('vm', 'show', '--resource-group', $group, '--name', $name)
    }
    $sizeName = [string]$full.hardwareProfile.vmSize
    $facts = Get-ClagnosUiVmSizeFacts -Location ([string]$full.location) -Size $sizeName
    $memoryGb = if ($facts.MemoryMb -match '^\d+$') { ('{0:N1} GB' -f ([double]$facts.MemoryMb / 1024)) } else { 'Unknown' }
    $power = Get-ClagnosUiPowerState -ResourceGroup $group -VmName $name -CachedPowerState ([string]$full.powerState)
    $nestedStatus = Get-ClagnosUiNestedVirtualizationGuestStatus -Vm $Vm -PowerState $power
    $envPath = Join-Path $script:ClagnosUiRepoRoot '.env'
    $config = Read-DotEnvFile -Path $envPath

    $privateAddresses = @()
    $publicAddresses = @()
    $privateAddresses = @(([string]$full.privateIps -split ',') | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $publicIpValues = @(([string]$full.publicIps -split ',') | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $publicFqdns = @(([string]$full.fqdns -split ',') | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $cachedPublicIpResources = @(Get-ClagnosUiCachedResourcesForType -Type 'ip' -ResourceGroup $group)
    for ($ipIndex = 0; $ipIndex -lt $publicIpValues.Count; $ipIndex++) {
        $ipValue = [string]$publicIpValues[$ipIndex]
        $ipResource = @(
            $cachedPublicIpResources | Where-Object {
                $ipProperties = Get-ClagnosUiCachedResourceModel -Resource $_
                [string]::Equals([string]$ipProperties.ipAddress, $ipValue, [System.StringComparison]::OrdinalIgnoreCase)
            } | Select-Object -First 1
        )
        $ipObject = if (@($ipResource).Count -gt 0) { $ipResource[0] } else { $null }
        $ipProperties = Get-ClagnosUiCachedResourceModel -Resource $ipObject
        $publicAddresses += [pscustomobject]@{
            Name = if ($null -ne $ipObject) { [string]$ipObject.name } else { '' }
            IpAddress = $ipValue
            Fqdn = if ($null -ne $ipProperties -and -not [string]::IsNullOrWhiteSpace([string]$ipProperties.dnsSettings.fqdn)) { [string]$ipProperties.dnsSettings.fqdn } elseif ($ipIndex -lt $publicFqdns.Count) { [string]$publicFqdns[$ipIndex] } else { '' }
            DnsLabel = if ($null -ne $ipProperties) { [string]$ipProperties.dnsSettings.domainNameLabel } else { '' }
            Allocation = if ($null -ne $ipProperties) { [string]$ipProperties.publicIPAllocationMethod } else { '' }
            Sku = if ($null -ne $ipObject -and $null -ne $ipObject.sku) { [string]$ipObject.sku.name } elseif ($null -ne $ipProperties.sku) { [string]$ipProperties.sku.name } else { '' }
            Zone = if ($null -ne $ipObject) { (@($ipObject.zones) -join ', ') } else { '' }
        }
    }

    if ($privateAddresses.Count -eq 0) {
        foreach ($nicReference in @(ConvertTo-ObjectArrayCompat -InputObject $full.networkProfile.networkInterfaces)) {
            $nicResource = Get-ClagnosUiCachedResourceById -ResourceId ([string]$nicReference.id)
            $nicProperties = Get-ClagnosUiCachedResourceModel -Resource $nicResource
            foreach ($ipConfig in @(ConvertTo-ObjectArrayCompat -InputObject $nicProperties.ipConfigurations)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$ipConfig.privateIPAddress)) { $privateAddresses += [string]$ipConfig.privateIPAddress }
            }
        }
        $privateAddresses = @($privateAddresses | Select-Object -Unique)
    }
    if ($publicAddresses.Count -eq 0) {
        foreach ($nicReference in @(ConvertTo-ObjectArrayCompat -InputObject $full.networkProfile.networkInterfaces)) {
            $nicResource = Get-ClagnosUiCachedResourceById -ResourceId ([string]$nicReference.id)
            $nicProperties = Get-ClagnosUiCachedResourceModel -Resource $nicResource
            foreach ($ipConfig in @(ConvertTo-ObjectArrayCompat -InputObject $nicProperties.ipConfigurations)) {
                $publicIpId = [string]$ipConfig.publicIPAddress.id
                if ([string]::IsNullOrWhiteSpace($publicIpId)) { continue }
                $publicIpResource = Get-ClagnosUiCachedResourceById -ResourceId $publicIpId
                $publicIpProperties = Get-ClagnosUiCachedResourceModel -Resource $publicIpResource
                $publicAddresses += [pscustomobject]@{
                    Name = if ($null -ne $publicIpResource) { [string]$publicIpResource.name } else { Get-ClagnosUiAzureResourceIdSegment -ResourceId $publicIpId -SegmentName 'publicIPAddresses' }
                    IpAddress = [string]$publicIpProperties.ipAddress
                    Fqdn = [string]$publicIpProperties.dnsSettings.fqdn
                    DnsLabel = [string]$publicIpProperties.dnsSettings.domainNameLabel
                    Allocation = [string]$publicIpProperties.publicIPAllocationMethod
                    Sku = if ($null -ne $publicIpResource.sku) { [string]$publicIpResource.sku.name } else { [string]$publicIpProperties.sku.name }
                    Zone = if ($null -ne $publicIpResource) { (@($publicIpResource.zones) -join ', ') } else { '' }
                }
            }
        }
    }

    Write-ClagnosUiHeader -Title ('Virtual computer: {0}' -f $name)
    Write-Host 'Virtual computer:' -ForegroundColor Cyan
    Write-Host ('  Name: {0}' -f $name)
    Write-Host ('Resource group: {0}' -f $group)
    Write-Host ('Subscription: {0} ({1})' -f (Format-ClagnosUiDetailValue -Value $script:ClagnosUiSubscription.SubscriptionName), (Format-ClagnosUiDetailValue -Value $Vm.ClagnosSubscriptionId))
    Write-Host ('Resource ID: {0}' -f (Format-ClagnosUiDetailValue -Value $full.id))
    Write-Host ('VM ID: {0}' -f (Format-ClagnosUiDetailValue -Value $full.vmId))
    Write-Host ('Operating system: {0}' -f [string]$full.storageProfile.osDisk.osType)
    Write-Host ('State: {0} | Provisioning: {1}' -f $power, [string]$full.provisioningState)
    Write-Host ('Region: {0} | Size: {1}' -f [string]$full.location, $sizeName)
    Write-Host ('Resource snapshot validated: {0} UTC' -f ([DateTime]$resourceSnapshot.LastValidatedAtUtc).ToString('u')) -ForegroundColor DarkGray
    Write-Host ('CPU: {0} vCPU | RAM: {1}' -f [string]$facts.Cores, $memoryGb)
    $image = $full.storageProfile.imageReference
    if ($null -ne $image) {
        $imageText = '{0}:{1}:{2}:{3}' -f [string]$image.publisher, [string]$image.offer, [string]$image.sku, [string]$image.version
        if (-not [string]::IsNullOrWhiteSpace([string]$image.id)) { $imageText = [string]$image.id }
        if (-not [string]::IsNullOrWhiteSpace([string]$image.exactVersion)) { $imageText += (' (exact version {0})' -f [string]$image.exactVersion) }
        Write-Host ('Image: {0}' -f $imageText)
    }
    elseif (-not [string]::IsNullOrWhiteSpace([string]$full.storageProfile.osDisk.image)) {
        Write-Host ('Image: {0}' -f [string]$full.storageProfile.osDisk.image)
    }
    Write-Host ('Computer name: {0}' -f (Format-ClagnosUiDetailValue -Value $full.osProfile.computerName))
    Write-Host ('Availability zone: {0}' -f (Format-ClagnosUiDetailValue -Value (@($full.zones) -join ', ')))
    Write-Host ''

    Write-Host 'Storage and disks:' -ForegroundColor Cyan
    $diskReferences = @()
    if ($null -ne $full.storageProfile.osDisk) {
        $diskReferences += [pscustomobject]@{
            Kind = 'OS disk'
            Name = [string]$full.storageProfile.osDisk.name
            Id = [string]$full.storageProfile.osDisk.managedDisk.id
            ResourceGroup = [string]$full.storageProfile.osDisk.managedDisk.resourceGroup
            SizeGb = [string]$full.storageProfile.osDisk.diskSizeGb
            Caching = [string]$full.storageProfile.osDisk.caching
            Lun = ''
            CreateOption = [string]$full.storageProfile.osDisk.createOption
            DeleteOption = [string]$full.storageProfile.osDisk.deleteOption
            StorageType = [string]$full.storageProfile.osDisk.managedDisk.storageAccountType
        }
    }
    foreach ($dataDisk in @($full.storageProfile.dataDisks)) {
        $diskReferences += [pscustomobject]@{
            Kind = 'Data disk'
            Name = [string]$dataDisk.name
            Id = [string]$dataDisk.managedDisk.id
            ResourceGroup = [string]$dataDisk.managedDisk.resourceGroup
            SizeGb = [string]$dataDisk.diskSizeGb
            Caching = [string]$dataDisk.caching
            Lun = [string]$dataDisk.lun
            CreateOption = [string]$dataDisk.createOption
            DeleteOption = [string]$dataDisk.deleteOption
            StorageType = [string]$dataDisk.managedDisk.storageAccountType
        }
    }
    foreach ($diskReference in @($diskReferences)) {
        $diskName = [string]$diskReference.Name
        if ([string]::IsNullOrWhiteSpace($diskName)) { continue }
        $diskGroup = [string]$diskReference.ResourceGroup
        if ([string]::IsNullOrWhiteSpace($diskGroup)) { $diskGroup = $group }
        try {
            $disk = Get-ClagnosUiCachedResourceById -ResourceId ([string]$diskReference.Id)
            if ($null -eq $disk) {
                $diskMatches = @((Get-ClagnosUiCachedResourcesForType -Type 'disk' -ResourceGroup $diskGroup) | Where-Object { [string]::Equals([string]$_.name, $diskName, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
                if (@($diskMatches).Count -gt 0) { $disk = $diskMatches[0] }
            }
            if ($null -eq $disk) { $disk = Invoke-ClagnosUiAzJson -Arguments @('disk', 'show', '--resource-group', $diskGroup, '--name', $diskName) }
            $diskModel = Get-ClagnosUiCachedResourceModel -Resource $disk
            $diskDisplayName = if (-not [string]::IsNullOrWhiteSpace([string]$disk.name)) { [string]$disk.name } else { $diskName }
            $diskSku = if ($null -ne $disk.sku) { [string]$disk.sku.name } elseif ($null -ne $diskModel.sku) { [string]$diskModel.sku.name } else { [string]$diskReference.StorageType }
            $sizeGb = if (-not [string]::IsNullOrWhiteSpace([string]$diskReference.SizeGb)) { [string]$diskReference.SizeGb } else { [string]$diskModel.diskSizeGb }
            $detail = ('  {0}: {1} | {2} GB | {3} | caching {4} | create {5}' -f [string]$diskReference.Kind, $diskDisplayName, $sizeGb, $diskSku, (Format-ClagnosUiDetailValue -Value $diskReference.Caching), (Format-ClagnosUiDetailValue -Value $diskReference.CreateOption))
            if (-not [string]::IsNullOrWhiteSpace([string]$diskReference.Lun)) { $detail += (' | LUN {0}' -f [string]$diskReference.Lun) }
            if (-not [string]::IsNullOrWhiteSpace([string]$diskReference.DeleteOption)) { $detail += (' | delete {0}' -f [string]$diskReference.DeleteOption) }
            if (-not [string]::IsNullOrWhiteSpace([string]$diskReference.StorageType)) { $detail += (' | storage {0}' -f [string]$diskReference.StorageType) }
            if (-not [string]::IsNullOrWhiteSpace([string]$diskModel.encryption.type)) { $detail += (' | encryption {0}' -f [string]$diskModel.encryption.type) }
            Write-Host $detail
        }
        catch { Write-Host ('  {0}: {1} | details unavailable' -f [string]$diskReference.Kind, $diskName) -ForegroundColor Yellow }
    }
    if ($diskReferences.Count -eq 0) { Write-Host '  (no managed disks reported)' -ForegroundColor Gray }
    Write-Host ''

    Write-Host 'Networking:' -ForegroundColor Cyan
    $nicReferences = @(ConvertTo-ObjectArrayCompat -InputObject $full.networkProfile.networkInterfaces)
    foreach ($nicReference in @($nicReferences)) {
        $nicName = Get-ClagnosUiAzureResourceIdSegment -ResourceId ([string]$nicReference.id) -SegmentName 'networkInterfaces'
        if ([string]::IsNullOrWhiteSpace($nicName)) { continue }
        try {
            $nicResource = Get-ClagnosUiCachedResourceById -ResourceId ([string]$nicReference.id)
            if ($null -ne $nicResource) {
                $nic = Get-ClagnosUiCachedResourceModel -Resource $nicResource
                $nic | Add-Member -NotePropertyName 'name' -NotePropertyValue ([string]$nicResource.name) -Force
            }
            else {
                $nicGroup = [string]$nicReference.resourceGroup
                if ([string]::IsNullOrWhiteSpace($nicGroup)) { $nicGroup = $group }
                $nic = Invoke-ClagnosUiAzJson -Arguments @('network', 'nic', 'show', '--resource-group', $nicGroup, '--name', $nicName)
            }
            Write-Host ('  NIC: {0} | primary {1} | accelerated networking {2} | IP forwarding {3}' -f [string]$nic.name, [bool]$nic.primary, [bool]$nic.enableAcceleratedNetworking, [bool]$nic.enableIPForwarding)
            $nsgName = Get-ClagnosUiAzureResourceIdSegment -ResourceId ([string]$nic.networkSecurityGroup.id) -SegmentName 'networkSecurityGroups'
            if (-not [string]::IsNullOrWhiteSpace($nsgName)) { Write-Host ('    Network security group: {0}' -f $nsgName) }
            foreach ($ipConfig in @(ConvertTo-ObjectArrayCompat -InputObject $nic.ipConfigurations)) {
                $vnetName = Get-ClagnosUiAzureResourceIdSegment -ResourceId ([string]$ipConfig.subnet.id) -SegmentName 'virtualNetworks'
                $subnetName = Get-ClagnosUiAzureResourceIdSegment -ResourceId ([string]$ipConfig.subnet.id) -SegmentName 'subnets'
                Write-Host ('    IP config {0}: private {1} ({2}) | primary {3} | VNet {4} | subnet {5}' -f [string]$ipConfig.name, (Format-ClagnosUiDetailValue -Value $ipConfig.privateIPAddress), (Format-ClagnosUiDetailValue -Value $ipConfig.privateIPAllocationMethod), [bool]$ipConfig.primary, (Format-ClagnosUiDetailValue -Value $vnetName), (Format-ClagnosUiDetailValue -Value $subnetName))
                if ($null -ne $ipConfig.publicIPAddress -and -not [string]::IsNullOrWhiteSpace([string]$ipConfig.publicIPAddress.id)) {
                    Write-Host ('      Public IP resource: {0}' -f (Get-ClagnosUiAzureResourceIdSegment -ResourceId ([string]$ipConfig.publicIPAddress.id) -SegmentName 'publicIPAddresses'))
                }
            }
        }
        catch { Write-Host ('  NIC: {0} | details unavailable' -f $nicName) -ForegroundColor Yellow }
    }
    if ($privateAddresses.Count -gt 0) { Write-Host ('  Private IP address(es): {0}' -f ($privateAddresses -join ', ')) }
    else { Write-Host '  Private IP address(es): (none reported)' -ForegroundColor Gray }
    if ($publicAddresses.Count -gt 0) {
        foreach ($publicAddress in @($publicAddresses)) {
            Write-Host ('  Public IP: {0} | resource {1}' -f (Format-ClagnosUiDetailValue -Value $publicAddress.IpAddress), (Format-ClagnosUiDetailValue -Value $publicAddress.Name))
            Write-Host ('    Public DNS: {0} | DNS label: {1}' -f (Format-ClagnosUiDetailValue -Value $publicAddress.Fqdn -EmptyText '(not configured)'), (Format-ClagnosUiDetailValue -Value $publicAddress.DnsLabel -EmptyText '(not configured)'))
            Write-Host ('    Allocation: {0} | SKU: {1} | zone: {2}' -f (Format-ClagnosUiDetailValue -Value $publicAddress.Allocation), (Format-ClagnosUiDetailValue -Value $publicAddress.Sku), (Format-ClagnosUiDetailValue -Value $publicAddress.Zone))
        }
    }
    else { Write-Host '  Public IP/DNS: (no public endpoint reported)' -ForegroundColor Gray }
    Write-Host ''

    $hibernationEnabled = if ($null -ne $full.additionalCapabilities) { [string]$full.additionalCapabilities.hibernationEnabled } else { 'false' }
    $securityType = [string]$full.securityProfile.securityType
    $secureBoot = if ($null -ne $full.securityProfile.uefiSettings) { [string]$full.securityProfile.uefiSettings.secureBootEnabled } else { '(not reported)' }
    $vTpm = if ($null -ne $full.securityProfile.uefiSettings) { [string]$full.securityProfile.uefiSettings.vTpmEnabled } else { '(not reported)' }
    $nestedVirtualization = [string](Get-ConfigValue -Config $config -Key 'VM_ENABLE_NESTED_VIRTUALIZATION' -DefaultValue '')
    if ([string]::IsNullOrWhiteSpace($nestedVirtualization)) { $nestedVirtualization = '(not configured)' }
    Write-Host 'Security and VM features:' -ForegroundColor Cyan
    Write-Host ('  Hibernation enabled: {0}' -f (Format-ClagnosUiDetailValue -Value $hibernationEnabled -EmptyText 'false'))
    Write-Host ('  Nested virtualization request (.env): {0}' -f $nestedVirtualization)
    $nestedStatusText = if ([string]$power -match '(?i)running') {
        if (-not [bool]$nestedStatus.Known) { 'unknown' }
        elseif ([bool]$nestedStatus.AvailableToGuest) { 'available' }
        else { 'unavailable' }
    }
    elseif ([string]$power -match '(?i)(stopped|deallocated|hibernated|stopping|deallocating)') { 'not checked (VM is not running)' }
    else { 'not checked (VM power state is unknown)' }
    Write-Host ('  Nested virtualization available to guest: {0}' -f $nestedStatusText)
    if (@($nestedStatus.Evidence).Count -gt 0) { Write-Host ('    Guest evidence: {0}' -f (@($nestedStatus.Evidence) -join '; ')) -ForegroundColor DarkGray }
    elseif (-not [bool]$nestedStatus.Known -and -not [string]::IsNullOrWhiteSpace([string]$nestedStatus.ErrorMessage)) { Write-Host ('    Guest validation: {0}' -f [string]$nestedStatus.ErrorMessage) -ForegroundColor DarkGray }
    Write-Host ('  Security type: {0}' -f (Format-ClagnosUiDetailValue -Value $securityType))
    Write-Host ('  Secure Boot: {0} | vTPM: {1}' -f $secureBoot, $vTpm)
    Write-Host ('  Boot diagnostics: {0}' -f (Format-ClagnosUiDetailValue -Value $full.diagnosticsProfile.bootDiagnostics.enabled))
    Write-Host ('  Managed identity: {0}' -f (Format-ClagnosUiDetailValue -Value $full.identity.type '(none)'))
    if ($null -ne $full.tags) {
        foreach ($tag in @($full.tags.PSObject.Properties | Sort-Object Name)) {
            Write-Host ('  Tag {0}: {1}' -f [string]$tag.Name, [string]$tag.Value)
        }
    }
    Write-Host ''

    $adminUser = [string](Get-ConfigValue -Config $config -Key 'VM_ADMIN_USER' -DefaultValue '')
    $adminPass = [string](Get-ConfigValue -Config $config -Key 'VM_ADMIN_PASS' -DefaultValue '')
    $assistantUser = [string](Get-ConfigValue -Config $config -Key 'VM_ASSISTANT_USER' -DefaultValue '')
    $assistantPass = [string](Get-ConfigValue -Config $config -Key 'VM_ASSISTANT_PASS' -DefaultValue '')
    $sshPort = [string](Get-ConfigValue -Config $config -Key 'VM_SSH_PORT' -DefaultValue (Get-ClagnosDefaultSshPortText))
    $rdpPort = [string](Get-ConfigValue -Config $config -Key 'VM_RDP_PORT' -DefaultValue (Get-ClagnosDefaultRdpPortText))
    $powerShellPort = Get-ClagnosDefaultPowerShellPortText
    $connectionHost = if ($publicAddresses.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$publicAddresses[0].Fqdn)) { [string]$publicAddresses[0].Fqdn }
    elseif ($publicAddresses.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$publicAddresses[0].IpAddress)) { [string]$publicAddresses[0].IpAddress }
    elseif ($privateAddresses.Count -gt 0) { [string]$privateAddresses[0] }
    else { '(no reachable address reported)' }
    Write-Host 'Connection and login credentials (.env):' -ForegroundColor Cyan
    Write-Host ('  SSH endpoint: {0}:{1} | default role: manager' -f $connectionHost, $sshPort)
    Write-Host ('    manager username: {0} | password: {1}' -f (Format-ClagnosUiDetailValue -Value $adminUser -EmptyText '(not configured)'), (Format-ClagnosUiDetailValue -Value $adminPass -EmptyText '(not configured)'))
    Write-Host ('    assistant username: {0} | password: {1}' -f (Format-ClagnosUiDetailValue -Value $assistantUser -EmptyText '(not configured)'), (Format-ClagnosUiDetailValue -Value $assistantPass -EmptyText '(not configured)'))
    if ([string]::Equals([string]$full.storageProfile.osDisk.osType, 'Windows', [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Host ('  RDP endpoint: {0}:{1} | default role: manager' -f $connectionHost, $rdpPort)
        Write-Host ('    manager username: {0} | password: {1}' -f (Format-ClagnosUiDetailValue -Value $adminUser -EmptyText '(not configured)'), (Format-ClagnosUiDetailValue -Value $adminPass -EmptyText '(not configured)'))
        Write-Host ('    assistant username: {0} | password: {1}' -f (Format-ClagnosUiDetailValue -Value $assistantUser -EmptyText '(not configured)'), (Format-ClagnosUiDetailValue -Value $assistantPass -EmptyText '(not configured)'))
        Write-Host ('  PowerShell remoting endpoint: {0}:{1} | roles: manager and assistant | authentication: Negotiate' -f $connectionHost, $powerShellPort)
    }
    else { Write-Host '  RDP: not applicable to this Linux VC.' }
    Write-Host '  Credentials are read from .env; passwords are excluded from progress and operation log messages.' -ForegroundColor Gray
    Write-Host ''

    Write-Host 'Attached resources:' -ForegroundColor Cyan
    $resources = @(Get-ClagnosUiResourcesForGroup -ResourceGroup $group)
    foreach ($resource in @($resources | Sort-Object { [string]$_.type }, { [string]$_.name })) {
        Write-Host ('  {0} | {1} | {2}' -f [string]$resource.type, [string]$resource.name, (Format-ClagnosUiDetailValue -Value $resource.location))
    }
}

function New-ClagnosUiTargetOptions {
    param([psobject]$Vm)

    $options = @{
        group = [string]$Vm.ClagnosResourceGroup
        'vm-name' = [string]$Vm.name
        'subscription-id' = [string]$Vm.ClagnosSubscriptionId
    }
    if ([string]::Equals([string]$Vm.storageProfile.osDisk.osType, 'Windows', [System.StringComparison]::OrdinalIgnoreCase)) {
        $options['windows'] = $true
    }
    else {
        $options['linux'] = $true
    }
    return $options
}

function Show-ClagnosUiPackageAppStateMenu {
    param(
        [psobject]$Vm,
        [psobject]$Package,
        [ValidateSet('builtin','custom')][string]$Catalog,
        [string]$Platform
    )

    Write-ClagnosUiHeader -Title ('App-state for {0}' -f [string]$Package.DisplayName)
    Write-Host '1. Save package app-state'
    Write-Host '2. Restore package app-state'
    Write-Host 'b: back'
    $choice = (Read-ClagnosUiChoice 'App-state action').ToLowerInvariant()
    if ($choice -eq 'b' -or $choice -notin @('1','2')) { return }
    $save = $choice -eq '1'
    Write-Host 'v: virtual computer | l: local Windows host'
    $surfaceChoice = (Read-ClagnosUiChoice 'App-state source or target').ToLowerInvariant()
    $surface = switch ($surfaceChoice) { 'v' { 'vm' } 'l' { 'lm' } default { '' } }
    if ([string]::IsNullOrWhiteSpace($surface)) { return }
    if ($surface -eq 'lm' -and $Platform -ne 'windows') {
        Write-Host 'Local-machine package app-state is available only on a Windows host.' -ForegroundColor Yellow
        Wait-ClagnosUiContinue
        return
    }

    $options = New-ClagnosUiTargetOptions -Vm $Vm
    $options['package'] = [string]$Package.Id
    $options['package-catalog'] = $Catalog
    $options[$(if ($save) { 'save-app-state' } else { 'restore-app-state' })] = $true
    $options[$(if ($save) { 'source' } else { 'target' })] = $surface
    $options['user'] = Read-ClagnosUiValidatedText -Prompt 'User selector (.all., .current., a username, or comma-separated usernames)' -Validator {
        param($value)
        return (Resolve-ClagnosUiAppStateUserSelection -Value ([string]$value))
    }
    Invoke-ClagnosUiCommand -CommandName 'task' -Options $options
}

function Show-ClagnosUiPackageCatalogMenu {
    param([psobject]$Vm, [ValidateSet('builtin','custom')][string]$Catalog)

    $platform = if ([string]::Equals([string]$Vm.storageProfile.osDisk.osType, 'Windows', [System.StringComparison]::OrdinalIgnoreCase)) { 'windows' } else { 'linux' }
    while ($true) {
        Write-ClagnosUiHeader -Title (('{0} package catalog on {1}' -f $Catalog, [string]$Vm.name))
        $packages = @(Get-ClagnosPackageCatalog -Platform $platform -Catalog $Catalog)
        $statusMap = @{}
        $statusChecking = $false
        $statusIsStale = $false
        if ($packages.Count -gt 0) {
            try {
                $statusOptions = New-ClagnosUiTargetOptions -Vm $Vm
                if (Test-ClagnosUiBackgroundCacheWorkerDisabled) {
                    $statusMap = Get-ClagnosPackageStatusSnapshot -Packages $packages -Options $statusOptions -Platform $platform
                }
                else {
                    $cacheEntry = Get-ClagnosPackageStatusCacheEntry -Packages $packages -Options $statusOptions -Platform $platform
                    if ($null -ne $cacheEntry) {
                        $statusMap = $cacheEntry.Entry.StatusByPackage
                        $statusIsStale = -not [bool]$cacheEntry.IsFresh
                    }
                    if ($null -eq $cacheEntry -or $statusIsStale) {
                        Request-ClagnosUiPackageStatusRefresh -Vm $Vm -Catalogs @($Catalog) | Out-Null
                        $statusChecking = $true
                    }
                }
            }
            catch {
                Write-Host ('Package status could not be read: {0}' -f $_.Exception.Message) -ForegroundColor Yellow
            }
        }
        if ($packages.Count -eq 0) {
            Write-Host ('No packages are registered in the {0} catalog for {1}.' -f $Catalog, $platform) -ForegroundColor Yellow
            Write-Host 'b: back'
            Write-Host 'q: exit'
            $emptyChoice = (Read-ClagnosUiChoice).ToLowerInvariant()
            if ($emptyChoice -eq 'b') { return }
            if ($emptyChoice -eq 'q') { Stop-ClagnosUiBackgroundCacheWorker; exit }
            continue
        }
        $packageOptions = @()
        if ($packages.Count -gt 0) {
            for ($index = 0; $index -lt $packages.Count; $index++) {
                $status = if ($statusMap.ContainsKey([string]$packages[$index].Id)) { [string]$statusMap[[string]$packages[$index].Id] } elseif ($statusChecking) { 'checking' } else { 'unavailable' }
                if ($statusIsStale -and $statusMap.ContainsKey([string]$packages[$index].Id)) { $status += ' (last cached)' }
                $disabledLabel = if ([bool]$packages[$index].Enabled) { '' } else { ' (disabled)' }
                $catalogLabel = if ($Catalog -eq 'builtin') { '[builtin]' } else { '[custom]' }
                $packageOptions += [pscustomobject]@{
                    Value = [string]$packages[$index].Id
                    Label = ('{0} {1}{2}' -f [string]$packages[$index].DisplayName, $catalogLabel, $disabledLabel)
                    Detail = ('[{0}]' -f $status)
                    Enabled = $true
                }
            }
        }
        $packageSelection = Select-ClagnosNumberedOptionPage -Options $packageOptions -Prompt ("{0} packages on {1}" -f $Catalog, $platform) -PageSize 12 -ExtraKeys @('r') -ExtraKeyLabels @{ r = 'refresh package status' }
        if ([string]$packageSelection.Action -eq 'back') { if ([string]$packageSelection.Input -eq 'q') { Stop-ClagnosUiBackgroundCacheWorker; exit }; return }
        if ([string]$packageSelection.Action -eq 'extra' -and [string]$packageSelection.ExtraKey -eq 'r') {
            Request-ClagnosUiPackageStatusRefresh -Vm $Vm -Catalogs @($Catalog) -Force | Out-Null
            continue
        }
        if ([string]$packageSelection.Action -ne 'selected') { continue }
        $selectedPackage = @($packages | Where-Object { [string]::Equals([string]$_.Id, [string]$packageSelection.Value, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
        if (@($selectedPackage).Count -eq 0) { continue }
        $package = $selectedPackage[0]
        Write-ClagnosUiHeader -Title ([string]$package.DisplayName)
        Write-Host ('Catalog: [{0}]' -f $Catalog)
        if (@($package.PackageTask.PackageSpec.DependsOn).Count -gt 0) {
            Write-Host ('Package prerequisites: {0}' -f (@($package.PackageTask.PackageSpec.DependsOn) -join ', ')) -ForegroundColor Yellow
        }
        Write-Host 'e: enable package'
        Write-Host 'd: disable package'
        Write-Host 'u: uninstall'
        Write-Host 'i: install'
        Write-Host 'v: update'
        Write-Host 's: status'
        if ($null -ne $package.PackageTask.AppStateSpec) { Write-Host 'a: manage package app-state' }
        Write-Host 'b: back'
        Write-Host 'q: exit'
        $action = (Read-ClagnosUiChoice).ToLowerInvariant()
        if ($action -eq 'b') { continue }
        if ($action -eq 'q') { Stop-ClagnosUiBackgroundCacheWorker; exit }
        if ($action -eq 'a' -and $null -ne $package.PackageTask.AppStateSpec) {
            Show-ClagnosUiPackageAppStateMenu -Vm $Vm -Package $package -Catalog $Catalog -Platform $platform
            continue
        }
        if ($action -notin @('e','d','u','i','v','s')) { continue }
        $packageAction = switch ($action) { 'e' { 'enable' } 'd' { 'disable' } 'u' { 'uninstall' } 'i' { 'install' } 'v' { 'update' } 's' { 'status' } default { '' } }
        if ($packageAction -eq 'status' -and -not (Test-ClagnosUiBackgroundCacheWorkerDisabled)) {
            Request-ClagnosUiPackageStatusRefresh -Vm $Vm -Catalogs @($Catalog) -Force | Out-Null
            Write-Host ('Status check requested for {0}; the catalog will show the result when the background check finishes.' -f [string]$package.DisplayName) -ForegroundColor DarkGray
            continue
        }
        $options = @{ catalog = $Catalog; package = [string]$package.Id }
        $options[$platform] = $true
        if ($packageAction -notin @('enable','disable')) {
            $targetOptions = New-ClagnosUiTargetOptions -Vm $Vm
            foreach ($optionName in $targetOptions.Keys) { $options[[string]$optionName] = $targetOptions[$optionName] }
        }
        if ($packageAction -eq 'uninstall') {
            $confirm = (Read-ClagnosUiChoice ('Type UNINSTALL to remove {0}' -f [string]$package.DisplayName))
            if ($confirm -cne 'UNINSTALL') { continue }
            $options['yes'] = $true
        }
        $commandOptions = @{ action = $packageAction }
        foreach ($optionName in $options.Keys) { $commandOptions[[string]$optionName] = $options[$optionName] }
        Invoke-ClagnosUiCommand -CommandName 'package' -Options $commandOptions
    }
}

function Show-ClagnosUiPackageMenu {
    param([psobject]$Vm)

    if (-not (Test-ClagnosUiBackgroundCacheWorkerDisabled)) {
        Request-ClagnosUiPackageStatusRefresh -Vm $Vm -Catalogs @('builtin','custom') | Out-Null
    }

    while ($true) {
        Write-ClagnosUiHeader -Title ('Manage programs on {0}' -f [string]$Vm.name)
        Write-Host '1. Builtin package catalog'
        Write-Host '2. Custom package catalog'
        Write-Host 'b: back'
        Write-Host 'q: exit'
        $choice = (Read-ClagnosUiChoice).ToLowerInvariant()
        if ($choice -eq 'b') { return }
        if ($choice -eq 'q') { Stop-ClagnosUiBackgroundCacheWorker; exit }
        switch ($choice) {
            '1' { Show-ClagnosUiPackageCatalogMenu -Vm $Vm -Catalog 'builtin' }
            '2' { Show-ClagnosUiPackageCatalogMenu -Vm $Vm -Catalog 'custom' }
        }
    }
}

function Show-ClagnosUiCachedComponentAction {
    param(
        [psobject]$Vm,
        [string]$Type,
        [ValidateSet('list','show')][string]$Action
    )

    try {
        $resourceGroup = [string]$Vm.ClagnosResourceGroup
        $rows = @(Get-ClagnosUiCachedComponentRows -Type $Type -ResourceGroup $resourceGroup)
        Write-ClagnosUiHeader -Title (('{0} components in {1}' -f $Type, $resourceGroup))
        if ($rows.Count -eq 0) {
            Write-Host ('No cached {0} components were found in {1}.' -f $Type, $resourceGroup) -ForegroundColor Yellow
            Wait-ClagnosUiContinue
            return
        }
        if ($Action -eq 'list') {
            for ($index = 0; $index -lt $rows.Count; $index++) {
                $parent = if (-not [string]::IsNullOrWhiteSpace([string]$rows[$index].Parent)) { (' | parent={0}' -f [string]$rows[$index].Parent) } else { '' }
                $location = [string]$rows[$index].Resource.location
                if ([string]::IsNullOrWhiteSpace([string]$location)) { $location = [string]$Vm.location }
                Write-Host ('{0}. {1}{2} | {3}' -f ($index + 1), [string]$rows[$index].Name, $parent, $location)
            }
            Write-Host ('Snapshot validated: {0} UTC' -f ([DateTime]$script:ClagnosUiInventoryCache.LastValidatedAtUtc).ToString('u')) -ForegroundColor DarkGray
            Wait-ClagnosUiContinue
            return
        }

        $pickerOptions = @(
            $rows | ForEach-Object {
                $detailText = if (-not [string]::IsNullOrWhiteSpace([string]$_.Parent)) { [string]$_.Parent } else { [string]$_.ResourceGroup }
                [pscustomobject]@{ Value = [string]$_.Id; Label = [string]$_.Name; Detail = $detailText }
            }
        )
        $selection = Select-ClagnosNumberedOptionPage -Options $pickerOptions -Prompt ('Select {0} to show' -f $Type) -DefaultValue $(if ($rows.Count -eq 1) { [string]$rows[0].Id } else { '' })
        if ([string]$selection.Action -ne 'selected') { return }
        $selected = @($rows | Where-Object { [string]::Equals([string]$_.Id, [string]$selection.Value, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
        if (@($selected).Count -eq 0) { return }
        Write-Host ''
        Write-Host ('{0}: {1}' -f $Type, [string]$selected[0].Name) -ForegroundColor Cyan
        $resource = $selected[0].Resource
        if ($null -eq $resource) { Write-Host '(properties are not included in this resource snapshot)' -ForegroundColor Yellow }
        else { ConvertTo-Json -InputObject $resource -Depth 20 | Write-Host }
        Write-Host ('Snapshot validated: {0} UTC' -f ([DateTime]$script:ClagnosUiInventoryCache.LastValidatedAtUtc).ToString('u')) -ForegroundColor DarkGray
        Wait-ClagnosUiContinue
    }
    catch {
        Write-ClagnosUiError -ErrorRecord $_
        Wait-ClagnosUiContinue
    }
}

function Show-ClagnosUiComponentMenu {
    param([psobject]$Vm)

    $types = @(
        @{ Id = 'group'; Label = 'Resource group' },
        @{ Id = 'vm'; Label = 'Virtual machine' },
        @{ Id = 'disk'; Label = 'Managed disk' },
        @{ Id = 'vnet'; Label = 'Virtual network' },
        @{ Id = 'subnet'; Label = 'Subnet' },
        @{ Id = 'nic'; Label = 'Network interface' },
        @{ Id = 'ip'; Label = 'Public IP' },
        @{ Id = 'nsg'; Label = 'Network security group' },
        @{ Id = 'nsg-rule'; Label = 'Network security rule' }
    )
    while ($true) {
        Write-ClagnosUiHeader -Title ('Components of {0}' -f [string]$Vm.name)
        for ($index = 0; $index -lt $types.Count; $index++) {
            Write-Host ('{0}. {1}' -f ($index + 1), [string]$types[$index].Label)
        }
        Write-Host 'b: back'
        Write-Host 'q: exit'
        $choice = (Read-ClagnosUiChoice).ToLowerInvariant()
        if ($choice -eq 'b') { return }
        if ($choice -eq 'q') { Stop-ClagnosUiBackgroundCacheWorker; exit }
        $number = 0
        if (-not [int]::TryParse($choice, [ref]$number) -or $number -lt 1 -or $number -gt $types.Count) { continue }
        $type = $types[$number - 1]
        Write-ClagnosUiHeader -Title ([string]$type.Label)
        Write-Host 'l: list'
        Write-Host 's: show properties'
        Write-Host 'c: create'
        Write-Host 'u: update properties'
        Write-Host 'd: delete'
        if ($type.Id -in @('disk','nic')) {
            Write-Host 'a: attach'
            Write-Host 't: detach'
        }
        Write-Host 'b: back'
        Write-Host 'q: exit'
        $actionChoice = (Read-ClagnosUiChoice).ToLowerInvariant()
        if ($actionChoice -eq 'b') { continue }
        if ($actionChoice -eq 'q') { Stop-ClagnosUiBackgroundCacheWorker; exit }
        if ($actionChoice -in @('a','t') -and $type.Id -in @('disk','nic')) {
            $options = New-ClagnosUiTargetOptions -Vm $Vm
            $options['type'] = [string]$type.Id
            $options['action'] = if ($actionChoice -eq 'a') { 'attach' } else { 'detach' }
            Invoke-ClagnosUiCommand -CommandName 'component' -Options $options
            continue
        }
        $action = switch ($actionChoice) { 'l' { 'list' } 's' { 'show' } 'c' { 'create' } 'u' { 'update' } 'd' { 'delete' } default { '' } }
        if ([string]::IsNullOrWhiteSpace($action)) { continue }
        if ($action -in @('list','show')) {
            Show-ClagnosUiCachedComponentAction -Vm $Vm -Type ([string]$type.Id) -Action $action
            continue
        }
        $options = New-ClagnosUiTargetOptions -Vm $Vm
        $options['type'] = [string]$type.Id
        $options['action'] = $action
        Invoke-ClagnosUiCommand -CommandName 'component' -Options $options
    }
}

function Get-ClagnosUiTaskRowsForStage {
    param([psobject]$Vm, [ValidateSet('init','update')][string]$Stage)

    $platform = if ([string]::Equals([string]$Vm.storageProfile.osDisk.osType, 'Windows', [System.StringComparison]::OrdinalIgnoreCase)) { 'windows' } else { 'linux' }
    $runtime = if ($platform -eq 'windows') {
        Initialize-ClagnosTaskCommandRuntimeContext -AutoMode:$false -WindowsFlag
    }
    else {
        Initialize-ClagnosTaskCommandRuntimeContext -AutoMode:$false -LinuxFlag
    }
    $stageRoot = if ($Stage -eq 'init') { [string]$runtime.VmInitTaskDir } else { [string]$runtime.VmUpdateTaskDir }
    $catalog = Get-ClagnosTaskBlocksFromDirectory -DirectoryPath $stageRoot -Platform $platform -Stage $Stage -SuppressSkipMessages
    return @($catalog.InventoryTasks)
}

function Select-ClagnosUiTaskName {
    param(
        [psobject]$Vm,
        [ValidateSet('init','update')][string]$Stage,
        [switch]$EnabledOnly,
        [switch]$AllowDisabledSelection
    )

    $tasks = @(Get-ClagnosUiTaskRowsForStage -Vm $Vm -Stage $Stage)
    if ($EnabledOnly) { $tasks = @($tasks | Where-Object { [bool]$_.Enabled }) }
    if ($tasks.Count -eq 0) {
        Write-Host 'No selectable tasks are registered for this stage.' -ForegroundColor Yellow
        Wait-ClagnosUiContinue
        return ''
    }

    $taskOptions = @(
        $tasks | ForEach-Object {
            $state = if ([bool]$_.Enabled) { 'enabled' } else { 'disabled: ' + [string]$_.DisabledReason }
            [pscustomobject]@{
                Value = [string]$_.Name
                Label = ('#{0} {1}' -f [int]$_.TaskNumber, [string]$_.Name)
                Detail = $state
                Enabled = ([bool]$_.Enabled -or $AllowDisabledSelection -or -not $EnabledOnly)
            }
        }
    )
    $selection = Select-ClagnosNumberedOptionPage -Options $taskOptions -Prompt (('{0} tasks' -f $Stage)) -PageSize 12
    if ([string]$selection.Action -eq 'back') {
        if ([string]$selection.Input -eq 'q') { Stop-ClagnosUiBackgroundCacheWorker; exit }
        return ''
    }
    if ([string]$selection.Action -ne 'selected') { return '' }
    return [string]$selection.Value
}

function Resolve-ClagnosUiAppStateUserSelection {
    param([string]$Value)

    $tokens = @(Resolve-ClagnosTaskAppStateRequestedUsers -UserOptionValue ([string]$Value))
    if ($tokens.Count -eq 0) { return '.all.' }
    if (@($tokens | Where-Object { $_ -in @('.all.','.current.') }).Count -gt 0 -and $tokens.Count -gt 1) {
        throw 'Use .all. or .current. alone, or enter a comma-separated list of usernames.'
    }
    foreach ($token in @($tokens)) {
        if ([string]$token -in @('.all.','.current.')) { continue }
        if ([string]$token -notmatch '^[a-zA-Z0-9][a-zA-Z0-9._-]{0,63}$') {
            throw ('User selector value "{0}" is invalid. Use letters, numbers, period, underscore, or hyphen.' -f [string]$token)
        }
    }
    return (@($tokens | ForEach-Object { [string]$_ }) -join ',')
}

function Show-ClagnosUiTaskAvailabilityMenu {
    param([psobject]$Vm)

    $platform = if ([string]::Equals([string]$Vm.storageProfile.osDisk.osType, 'Windows', [System.StringComparison]::OrdinalIgnoreCase)) { 'windows' } else { 'linux' }

    while ($true) {
        Write-ClagnosUiHeader -Title ('Task availability for {0}' -f [string]$Vm.name)
        Write-Host 'Task availability is shared by this repository and affects future runs on matching VMs.' -ForegroundColor Yellow
        Write-Host '1. Initialization tasks'
        Write-Host '2. Maintenance tasks'
        Write-Host 'b: back'
        Write-Host 'q: exit'
        $stageChoice = (Read-ClagnosUiChoice 'Task stage').ToLowerInvariant()
        if ($stageChoice -eq 'b') { return }
        if ($stageChoice -eq 'q') { Stop-ClagnosUiBackgroundCacheWorker; exit }
        if ($stageChoice -notin @('1','2')) { continue }

        $stage = if ($stageChoice -eq '1') { 'init' } else { 'update' }
        $tasks = @(Get-ClagnosUiTaskRowsForStage -Vm $Vm -Stage $stage)
        if ($tasks.Count -eq 0) {
            Write-Host 'No tasks are registered for this stage.' -ForegroundColor Yellow
            Wait-ClagnosUiContinue
            continue
        }

        $taskOptions = @($tasks | ForEach-Object {
            $state = if ([bool]$_.Enabled) { 'enabled' } else { 'disabled: ' + [string]$_.DisabledReason }
            [pscustomobject]@{ Value = [string]$_.Name; Label = ('#{0} {1}' -f [int]$_.TaskNumber, [string]$_.Name); Detail = $state; Enabled = $true }
        })
        $taskSelection = Select-ClagnosNumberedOptionPage -Options $taskOptions -Prompt ('{0} tasks' -f $(if ($stage -eq 'init') { 'Initialization' } else { 'Maintenance' })) -PageSize 12
        if ([string]$taskSelection.Action -eq 'back') {
            if ([string]$taskSelection.Input -eq 'q') { Stop-ClagnosUiBackgroundCacheWorker; exit }
            continue
        }
        if ([string]$taskSelection.Action -ne 'selected') { continue }
        $selectedTask = @($tasks | Where-Object { [string]::Equals([string]$_.Name, [string]$taskSelection.Value, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
        if (@($selectedTask).Count -eq 0) { continue }
        $selectedTask = $selectedTask[0]
        Write-ClagnosUiHeader -Title ([string]$selectedTask.Name)
        Write-Host 'e: enable'
        Write-Host 'd: disable'
        Write-Host 'b: back'
        Write-Host 'q: exit'
        $action = (Read-ClagnosUiChoice 'Availability action').ToLowerInvariant()
        if ($action -eq 'b') { continue }
        if ($action -eq 'q') { Stop-ClagnosUiBackgroundCacheWorker; exit }
        if ($action -notin @('e','d')) { continue }

        $options = @{}
        $options[('vm-{0}-task' -f $stage)] = [string]$selectedTask.Name
        $options[$(if ($action -eq 'e') { 'enable' } else { 'disable' })] = $true
        $options[$platform] = $true
        Invoke-ClagnosUiCommand -CommandName 'task' -Options $options
    }
}

function Show-ClagnosUiTaskMenu {
    param([psobject]$Vm)

    while ($true) {
        Write-ClagnosUiHeader -Title ('Tasks on {0}' -f [string]$Vm.name)
        Write-Host '1. List init and update tasks'
        Write-Host '2. Run one init task'
        Write-Host '3. Run one update task'
        Write-Host '4. Save task app-state'
        Write-Host '5. Restore task app-state'
        Write-Host '6. List disabled tasks'
        Write-Host '7. Enable/disable a task'
        Write-Host '8. View recent task run history'
        Write-Host 'b: back'
        Write-Host 'q: exit'
        $choice = (Read-ClagnosUiChoice).ToLowerInvariant()
        if ($choice -eq 'b') { return }
        if ($choice -eq 'q') { Stop-ClagnosUiBackgroundCacheWorker; exit }
        $target = New-ClagnosUiTargetOptions -Vm $Vm
        switch ($choice) {
            '1' { $target['list'] = $true; $target['vm-init'] = $true; $target['vm-update'] = $true; Invoke-ClagnosUiCommand -CommandName 'task' -Options $target }
            '2' {
                $taskName = Select-ClagnosUiTaskName -Vm $Vm -Stage 'init' -EnabledOnly
                if (-not [string]::IsNullOrWhiteSpace([string]$taskName)) { $target['run-vm-init'] = $taskName; Invoke-ClagnosUiCommand -CommandName 'task' -Options $target }
            }
            '3' {
                $taskName = Select-ClagnosUiTaskName -Vm $Vm -Stage 'update' -EnabledOnly
                if (-not [string]::IsNullOrWhiteSpace([string]$taskName)) { $target['run-vm-update'] = $taskName; Invoke-ClagnosUiCommand -CommandName 'task' -Options $target }
            }
            { $_ -in @('4','5','6') } {
                if ($choice -eq '6') {
                    $target['list'] = $true
                    $target['vm-init'] = $true
                    $target['vm-update'] = $true
                    $target['disabled'] = $true
                    Invoke-ClagnosUiCommand -CommandName 'task' -Options $target
                    break
                }
                Write-Host 'i: init | u: update'
                $stageChoice = (Read-ClagnosUiChoice 'Task stage').ToLowerInvariant()
                $stage = switch ($stageChoice) { 'i' { 'init' } 'u' { 'update' } default { '' } }
                if ([string]::IsNullOrWhiteSpace($stage)) { continue }
                $taskName = Select-ClagnosUiTaskName -Vm $Vm -Stage $stage
                if ([string]::IsNullOrWhiteSpace([string]$taskName)) { continue }
                $target[('vm-{0}-task' -f $stage)] = [string]$taskName
                $target[$(if ($choice -eq '4') { 'save-app-state' } else { 'restore-app-state' })] = $true
                Write-Host 'v: virtual computer | l: local Windows host'
                $surfaceChoice = (Read-ClagnosUiChoice 'App-state target').ToLowerInvariant()
                $surface = switch ($surfaceChoice) { 'v' { 'vm' } 'l' { 'lm' } default { '' } }
                if ($surface -in @('vm','lm')) { $target[$(if ($choice -eq '4') { 'source' } else { 'target' })] = $surface }
                else { continue }
                $target['user'] = Read-ClagnosUiValidatedText -Prompt 'User selector (.all., .current., a username, or comma-separated usernames)' -Validator {
                    param($value)
                    return (Resolve-ClagnosUiAppStateUserSelection -Value ([string]$value))
                }
                Invoke-ClagnosUiCommand -CommandName 'task' -Options $target
            }
            '7' { Show-ClagnosUiTaskAvailabilityMenu -Vm $Vm }
            '8' { Invoke-ClagnosUiCommand -CommandName 'task' -Options @{ history = $true } }
        }
    }
}

function Show-ClagnosUiOperationsMenu {
    param([psobject]$Vm)

    while ($true) {
        Write-ClagnosUiHeader -Title ('Operations for {0}' -f [string]$Vm.name)
        Write-Host '1. Power, status, and repair'
        Write-Host '2. Resize VM or disk'
        Write-Host '3. Move to another region'
        Write-Host '4. VM features'
        Write-Host '5. Connect by SSH, RDP, or PowerShell'
        Write-Host '6. Run a remote command or shell'
        Write-Host '7. Tasks and app-state'
        Write-Host '8. Component CRUD'
        Write-Host '9. Full read-only report'
        Write-Host 'b: back'
        Write-Host 'q: exit'
        $choice = (Read-ClagnosUiChoice).ToLowerInvariant()
        if ($choice -eq 'b') { return }
        if ($choice -eq 'q') { Stop-ClagnosUiBackgroundCacheWorker; exit }
        $options = New-ClagnosUiTargetOptions -Vm $Vm
        switch ($choice) {
            '1' {
                $actions = @(
                    [pscustomobject]@{ Action = 'status'; Label = 'status (read-only)' },
                    [pscustomobject]@{ Action = 'start'; Label = 'start VM' },
                    [pscustomobject]@{ Action = 'shutdown'; Label = 'shutdown gracefully (stays allocated)' },
                    [pscustomobject]@{ Action = 'hibernate-stop'; Label = 'hibernate through guest OS (stays allocated)' },
                    [pscustomobject]@{ Action = 'hibernate-deallocate'; Label = 'hibernate and deallocate' },
                    [pscustomobject]@{ Action = 'resume'; Label = 'resume hibernated VM' },
                    [pscustomobject]@{ Action = 'restart'; Label = 'restart VM' },
                    [pscustomobject]@{ Action = 'power-off'; Label = 'power off immediately (skip guest shutdown)' },
                    [pscustomobject]@{ Action = 'reset'; Label = 'reset (force restart through Azure redeploy)' },
                    [pscustomobject]@{ Action = 'deallocate'; Label = 'deallocate VM' },
                    [pscustomobject]@{ Action = 'reapply'; Label = 'reapply VM configuration' },
                    [pscustomobject]@{ Action = 'redeploy'; Label = 'redeploy VM to Azure host' }
                )
                for ($index = 0; $index -lt $actions.Count; $index++) { Write-Host ('{0}. {1}' -f ($index + 1), [string]$actions[$index].Label) }
                $actionChoice = Read-ClagnosUiChoice 'VM action number'
                $actionIndex = 0
                if (-not [int]::TryParse($actionChoice, [ref]$actionIndex) -or $actionIndex -lt 1 -or $actionIndex -gt $actions.Count) { continue }
                $selectedAction = [string]$actions[$actionIndex - 1].Action
                if ($selectedAction -eq 'power-off') {
                    if ((Read-ClagnosUiChoice 'Type POWER OFF to force an immediate guest power-off') -cne 'POWER OFF') { continue }
                }
                elseif ($selectedAction -eq 'reset') {
                    if ((Read-ClagnosUiChoice 'Type RESET to force a restart through Azure redeploy') -cne 'RESET') { continue }
                }
                $options['vm-action'] = $selectedAction
                [void]$options.Remove('windows')
                [void]$options.Remove('linux')
                Invoke-ClagnosUiCommand -CommandName 'do' -Options $options
            }
            '2' {
                Write-Host '1. Change VM size'
                Write-Host '2. Expand OS disk'
                Write-Host '3. Show safe shrink guidance'
                $resizeChoice = Read-ClagnosUiChoice 'Resize action'
                if ($resizeChoice -eq '1') {
                    # The resize runtime opens the region-aware Azure SKU picker.
                }
                elseif ($resizeChoice -in @('2','3')) {
                    $options['disk-size'] = Read-ClagnosUiValidatedText -Prompt 'Target OS disk size (for example 128GB, 1TB; maximum 4095GB)' -Validator {
                        param($value)
                        [void](ConvertTo-ClagnosOsDiskSizeGb -Value ([string]$value) -FieldName 'OS disk size')
                        return ([string]$value).Trim()
                    }
                    $options[$(if ($resizeChoice -eq '2') { 'expand' } else { 'shrink' })] = $true
                }
                else { continue }
                Invoke-ClagnosUiCommand -CommandName 'resize' -Options $options
            }
            '3' {
                $options['vm-region'] = Select-AzLocationInteractive -DefaultLocation ([string]$Vm.location)
                Invoke-ClagnosUiCommand -CommandName 'move' -Options $options
            }
            '4' {
                Write-Host 'h: hibernation | n: nested virtualization'
                $feature = (Read-ClagnosUiChoice 'Feature').ToLowerInvariant()
                Write-Host '1: enable | 2: disable'
                $valueChoice = Read-ClagnosUiChoice 'Feature state'
                $value = switch ($valueChoice) { '1' { 'true' } '2' { 'false' } default { '' } }
                if ([string]::IsNullOrWhiteSpace($value)) { continue }
                if ($feature -eq 'h') { $options['hibernation'] = $value }
                elseif ($feature -eq 'n') { $options['nested-virtualization'] = $value }
                else { continue }
                Invoke-ClagnosUiCommand -CommandName 'set' -Options $options
            }
            '5' {
                $isWindowsVm = [string]::Equals([string]$Vm.storageProfile.osDisk.osType, 'Windows', [System.StringComparison]::OrdinalIgnoreCase)
                if ($isWindowsVm) {
                    Write-Host 's: SSH | r: RDP | t: test SSH | d: test RDP | p: PowerShell session | c: PowerShell command | w: test PowerShell'
                }
                else {
                    Write-Host 's: SSH | t: test SSH'
                }
                $transport = (Read-ClagnosUiChoice 'Connection').ToLowerInvariant()
                if ($transport -in @('s','t')) { $options['ssh'] = $true }
                elseif ($transport -in @('r','d') -and $isWindowsVm) { $options['rdp'] = $true }
                elseif ($transport -in @('p','c','w') -and $isWindowsVm) { $options['powershell'] = $true }
                else { continue }
                if ($transport -in @('t','d','w')) { $options['test'] = $true }
                if ($transport -eq 'c') { $options['command'] = Read-ClagnosUiChoice 'Remote PowerShell command' }
                Invoke-ClagnosUiCommand -CommandName 'connect' -Options $options
            }
            '6' {
                $command = Read-ClagnosUiChoice 'Remote command (leave blank for interactive shell)'
                if (-not [string]::IsNullOrWhiteSpace($command)) { $options['command'] = $command }
                Invoke-ClagnosUiCommand -CommandName 'exec' -Options $options
            }
            '7' { Show-ClagnosUiTaskMenu -Vm $Vm }
            '8' { Show-ClagnosUiComponentMenu -Vm $Vm }
            '9' {
                Write-Host 't: show report on screen | j: export redacted JSON'
                $reportMode = (Read-ClagnosUiChoice 'Report output').ToLowerInvariant()
                if ($reportMode -eq 'j') {
                    $exportPath = Read-ClagnosUiValidatedText -Prompt 'JSON export path (press Enter to cancel)' -AllowBlank -Validator {
                        param($value)
                        $candidate = ([string]$value).Trim()
                        if ([string]::IsNullOrWhiteSpace($candidate)) { throw 'Enter a file path for the JSON export.' }
                        try { $fullPath = [System.IO.Path]::GetFullPath($candidate) }
                        catch { throw 'Enter a valid file path for the JSON export.' }
                        if ([string]::IsNullOrWhiteSpace([System.IO.Path]::GetFileName($fullPath))) { throw 'The JSON export path must include a file name.' }
                        return $candidate
                    }
                    if ([string]::IsNullOrWhiteSpace([string]$exportPath)) { continue }
                    $options['export-json'] = $exportPath
                    if (Test-Path -LiteralPath $exportPath -PathType Leaf) {
                        if ((Read-ClagnosUiChoice 'Type OVERWRITE to replace the existing report file') -cne 'OVERWRITE') { continue }
                        $options['overwrite'] = $true
                    }
                }
                elseif ($reportMode -notin @('','t')) {
                    continue
                }
                Invoke-ClagnosUiCommand -CommandName 'show' -Options $options
            }
        }
    }
}

function Show-ClagnosUiVmMenu {
    param([psobject]$Vm)

    while ($true) {
        try { Show-ClagnosUiVmDetails -Vm $Vm }
        catch { Write-ClagnosUiHeader -Title ('Virtual computer: {0}' -f [string]$Vm.name); Write-ClagnosUiError -ErrorRecord $_ }
        Write-Host 'p: manage programs'
        Write-Host 'i: initialize VC'
        Write-Host 'u: update VC'
        Write-Host 'm: manage VC components'
        Write-Host 'o: operations'
        Write-Host 'd: delete VC and its resources'
        Write-Host 'r: refresh details'
        Write-Host 'b: back to virtual computers'
        Write-Host 'q: exit'
        $choice = (Read-ClagnosUiChoice).ToLowerInvariant()
        if ($choice -eq 'b') { return }
        if ($choice -eq 'q') { Stop-ClagnosUiBackgroundCacheWorker; exit }
        $target = New-ClagnosUiTargetOptions -Vm $Vm
        switch ($choice) {
            'p' { Show-ClagnosUiPackageMenu -Vm $Vm }
            'i' { Invoke-ClagnosUiCommand -CommandName 'initialize' -Options $target }
            'u' { Invoke-ClagnosUiCommand -CommandName 'update' -Options $target }
            'm' { Show-ClagnosUiComponentMenu -Vm $Vm }
            'o' { Show-ClagnosUiOperationsMenu -Vm $Vm }
            'd' {
                try {
                    $resources = @(Get-ClagnosUiResourcesForGroup -ResourceGroup ([string]$Vm.ClagnosResourceGroup))
                    Write-Host 'The following Azure resources will be removed:' -ForegroundColor Yellow
                    foreach ($resource in @($resources | Sort-Object { [string]$_.type }, { [string]$_.name })) { Write-Host ('  - {0}: {1}' -f [string]$resource.type, [string]$resource.name) }
                    $confirm = Read-ClagnosUiChoice "Type DELETE ALL to remove this VC's complete resource group"
                    if ($confirm -ceq 'DELETE ALL') {
                        $target['target'] = 'group'
                        $target['yes'] = $true
                        Invoke-ClagnosUiCommand -CommandName 'delete' -Options $target
                        return
                    }
                }
                catch { Write-ClagnosUiError -ErrorRecord $_; Wait-ClagnosUiContinue }
            }
        }
    }
}

function Resolve-ClagnosUiWizardPageStep {
    param(
        [object[]]$Options,
        [string]$Prompt,
        [string]$DefaultValue = '',
        [string[]]$ExtraKeys = @(),
        [switch]$Required
    )

    while ($true) {
        $selection = Select-ClagnosNumberedOptionPage -Options $Options -Prompt $Prompt -DefaultValue $DefaultValue -PageSize 12 -WizardControls -ExtraKeys $ExtraKeys
        if ([string]$selection.Action -eq 'close') { return [pscustomobject]@{ Action = 'close'; Value = '' } }
        if ([string]$selection.Action -eq 'extra') { return $selection }
        if ([string]$selection.Action -in @('skip-all','apply-all')) {
            if ($Required -and [string]::IsNullOrWhiteSpace([string]$selection.Value)) {
                Write-Host 'This required step has no default; choose a numbered option first.' -ForegroundColor Yellow
                continue
            }
            return [pscustomobject]@{ Action = [string]$selection.Action; Value = [string]$selection.Value }
        }
        if ([string]$selection.Action -eq 'skip') {
            if ($Required -and [string]::IsNullOrWhiteSpace([string]$selection.Value)) {
                Write-Host 'This required step has no default; choose a numbered option first.' -ForegroundColor Yellow
                continue
            }
            return [pscustomobject]@{ Action = 'skip'; Value = [string]$selection.Value }
        }
        if ([string]$selection.Action -in @('selected','apply-default')) {
            return [pscustomobject]@{ Action = [string]$selection.Action; Value = [string]$selection.Value }
        }
        Write-Host 'This step has no selectable options. Review the displayed choices or close the wizard.' -ForegroundColor Yellow
    }
}

function Get-ClagnosUiWizardBooleanDefault {
    param([hashtable]$Config, [string]$Key, [bool]$DefaultValue)

    try {
        return ([string](Resolve-ClagnosBooleanConfigValue -RawValue ([string](Get-ConfigValue -Config $Config -Key $Key -DefaultValue ([string]$DefaultValue))) -KeyName $Key -DefaultValue $DefaultValue -TreatEmptyAsDefault)).ToLowerInvariant()
    }
    catch {
        Write-Host ("Configured default for {0} is invalid: {1}. Select a value in the wizard." -f $Key, [string]$_.Exception.Message) -ForegroundColor Yellow
        return ''
    }
}

function Read-ClagnosUiWizardTextStep {
    param(
        [string]$Title,
        [string]$DefaultValue = '',
        [string]$Example = '',
        [switch]$Required,
        [scriptblock]$Validator
    )

    while ($true) {
        Write-ClagnosUiHeader -Title $Title
        if (-not [string]::IsNullOrWhiteSpace([string]$DefaultValue)) { Write-Host ('> Current/default value: {0}' -f $DefaultValue) -ForegroundColor Green }
        elseif ($Required) { Write-Host 'Required value: no default is configured.' -ForegroundColor Yellow }
        if (-not [string]::IsNullOrWhiteSpace([string]$Example)) { Write-Host ('Example: {0}' -f $Example) -ForegroundColor Gray }
        Write-Host 's: skip (keep default) | k: skip all remaining | a: apply default | l: apply all defaults | c: close wizard'
        $raw = Read-ClagnosUiChoice 'Enter value'
        $command = $raw.ToLowerInvariant()
        if ($command -eq 'c') { return [pscustomobject]@{ Action = 'close'; Value = '' } }
        if ($command -in @('s','a','k','l')) {
            if ([string]::IsNullOrWhiteSpace([string]$DefaultValue)) {
                if ($Required) { Write-Host 'This required step has no default; enter a value.' -ForegroundColor Yellow; continue }
                if ($command -in @('k','l')) { return [pscustomobject]@{ Action = $(if ($command -eq 'k') { 'skip-all' } else { 'apply-all' }); Value = '' } }
                return [pscustomobject]@{ Action = 'skip'; Value = '' }
            }
            try {
                $normalizedDefault = if ($Validator) { [string](& $Validator $DefaultValue) } else { [string]$DefaultValue }
                $action = switch ($command) { 's' { 'skip' } 'a' { 'apply-default' } 'k' { 'skip-all' } 'l' { 'apply-all' } }
                return [pscustomobject]@{ Action = $action; Value = $normalizedDefault }
            }
            catch {
                Write-Host ('Configured default is invalid: {0}' -f [string]$_.Exception.Message) -ForegroundColor Yellow
                if ($command -in @('k','l')) { Write-Host 'Enter a valid value before skipping the remaining required setup.' -ForegroundColor Yellow }
                continue
            }
        }

        $candidate = if ([string]::IsNullOrWhiteSpace([string]$raw)) { [string]$DefaultValue } else { [string]$raw }
        if ($Required -and [string]::IsNullOrWhiteSpace([string]$candidate)) {
            Write-Host 'A value is required for this step.' -ForegroundColor Yellow
            continue
        }
        try {
            $normalizedValue = if ($Validator) { [string](& $Validator $candidate) } else { [string]$candidate.Trim() }
            return [pscustomobject]@{ Action = 'value'; Value = $normalizedValue }
        }
        catch {
            Write-Host ([string]$_.Exception.Message) -ForegroundColor Yellow
        }
    }
}

function Show-ClagnosUiCreateWizard {
    $envPath = Join-Path $script:ClagnosUiRepoRoot '.env'
    $config = Read-DotEnvFile -Path $envPath
    $subscriptionId = if ($null -ne $script:ClagnosUiSubscription) { [string]$script:ClagnosUiSubscription.SubscriptionId } else { '' }
    if ([string]::IsNullOrWhiteSpace([string]$subscriptionId)) {
        Write-ClagnosUiError -ErrorRecord ([System.Exception]::new("Select an active Azure subscription and run 'az login' before creating a virtual computer."))
        Wait-ClagnosUiContinue
        return
    }

    $platformDefault = ([string](Get-ConfigValue -Config $config -Key 'SELECTED_VM_OS' -DefaultValue '')).Trim().ToLowerInvariant()
    if ($platformDefault -notin @('windows','linux')) { $platformDefault = '' }
    $wizardValues = @{}
    $wizardSources = @{}
    $skipRemaining = $false

    $platformOptions = @(
        [pscustomobject]@{ Value = 'windows'; Label = 'Windows'; Detail = 'Windows Server or Windows client image' },
        [pscustomobject]@{ Value = 'linux'; Label = 'Linux'; Detail = 'Linux server image' }
    )
    $platformResult = Resolve-ClagnosUiWizardPageStep -Options $platformOptions -Prompt 'Operating system' -DefaultValue $platformDefault -Required
    if ($platformResult.Action -eq 'close') { return }
    $platform = [string]$platformResult.Value
    $wizardSources['SELECTED_VM_OS'] = if ($platformResult.Action -in @('skip','apply-default','skip-all','apply-all')) { 'default' } else { 'selected' }
    if ($platformResult.Action -in @('skip-all','apply-all')) { $skipRemaining = $true }

    $platformDefaults = Get-ClagnosPlatformDefaults -Platform $platform
    $vmNameDefault = [string](Get-ConfigValue -Config $config -Key 'SELECTED_VM_NAME' -DefaultValue '')
    $regionDefault = [string](Get-ConfigValue -Config $config -Key 'SELECTED_AZURE_REGION' -DefaultValue '')
    $vmSizeKey = Get-ClagnosPlatformVmConfigKey -Platform $platform -BaseKey 'VM_SIZE'
    $imageKey = Get-ClagnosPlatformVmConfigKey -Platform $platform -BaseKey 'VM_IMAGE'
    $diskKey = Get-ClagnosPlatformVmConfigKey -Platform $platform -BaseKey 'VM_DISK_SIZE_GB'
    $vmSizeDefault = [string](Get-ConfigValue -Config $config -Key $vmSizeKey -DefaultValue ([string]$platformDefaults.VmSizeDefault))
    $imageRawDefault = [string](Get-ConfigValue -Config $config -Key $imageKey -DefaultValue ([string]$platformDefaults.VmImageDefault))
    $storageSkuDefault = [string](Get-ConfigValue -Config $config -Key 'VM_STORAGE_SKU' -DefaultValue 'StandardSSD_LRS')
    if ([string]::IsNullOrWhiteSpace([string]$storageSkuDefault)) { $storageSkuDefault = 'StandardSSD_LRS' }
    $securityDefault = ''
    try { $securityDefault = [string](Resolve-ClagnosSecurityTypeValue -RawValue ([string](Get-ConfigValue -Config $config -Key 'VM_SECURITY_TYPE' -DefaultValue 'Standard'))) }
    catch { Write-Host ('Configured VM_SECURITY_TYPE is invalid: {0}. Select a security type in the wizard.' -f [string]$_.Exception.Message) -ForegroundColor Yellow }
    if ([string]::IsNullOrWhiteSpace([string]$securityDefault) -and [string]::IsNullOrWhiteSpace([string](Get-ConfigValue -Config $config -Key 'VM_SECURITY_TYPE' -DefaultValue 'Standard'))) { $securityDefault = 'Standard' }
    $hibernationDefault = Get-ClagnosUiWizardBooleanDefault -Config $config -Key 'VM_ENABLE_HIBERNATION' -DefaultValue $true
    $nestedDefault = Get-ClagnosUiWizardBooleanDefault -Config $config -Key 'VM_ENABLE_NESTED_VIRTUALIZATION' -DefaultValue $true
    $secureBootDefault = Get-ClagnosUiWizardBooleanDefault -Config $config -Key 'VM_ENABLE_SECURE_BOOT' -DefaultValue $true
    $vtpmDefault = Get-ClagnosUiWizardBooleanDefault -Config $config -Key 'VM_ENABLE_VTPM' -DefaultValue $true
    $diskDefaultRaw = [string](Get-ConfigValue -Config $config -Key $diskKey -DefaultValue ([string]$platformDefaults.VmDiskSizeDefault))
    $diskDefault = ''
    try { $diskDefault = ConvertTo-ClagnosOsDiskSizeGb -Value $diskDefaultRaw -FieldName $diskKey }
    catch { Write-Host ('Disk default will need an entered value: {0}' -f [string]$_.Exception.Message) -ForegroundColor Yellow }
    $imageDefault = Resolve-ClagnosTemplate -Template $imageRawDefault -Tokens @{ SELECTED_VM_NAME = $vmNameDefault }
    $sshPortDefaultRaw = [string](Get-ConfigValue -Config $config -Key 'VM_SSH_PORT' -DefaultValue (Get-ClagnosDefaultSshPortText))
    $sshPortDefault = ''
    try { $sshPortDefault = Resolve-ClagnosTcpPortNumber -Value $sshPortDefaultRaw -Label 'VM_SSH_PORT' }
    catch { Write-Host ('SSH port default will need correction: {0}' -f [string]$_.Exception.Message) -ForegroundColor Yellow }
    $rdpPortDefaultRaw = [string](Get-ConfigValue -Config $config -Key 'VM_RDP_PORT' -DefaultValue (Get-ClagnosDefaultRdpPortText))
    $rdpPortDefault = ''
    if ($platform -eq 'windows') {
        try { $rdpPortDefault = Resolve-ClagnosTcpPortNumber -Value $rdpPortDefaultRaw -Label 'VM_RDP_PORT' }
        catch { Write-Host ('RDP port default will need correction: {0}' -f [string]$_.Exception.Message) -ForegroundColor Yellow }
    }
    $requiredPorts = @()
    if (-not [string]::IsNullOrWhiteSpace([string]$sshPortDefault)) { $requiredPorts += $sshPortDefault }
    if (-not [string]::IsNullOrWhiteSpace([string]$rdpPortDefault)) { $requiredPorts += $rdpPortDefault }
    $wizardValues['SshPort'] = [string]$sshPortDefault
    if ($platform -eq 'windows') { $wizardValues['RdpPort'] = [string]$rdpPortDefault }
    $portsDefaultRaw = [string](Get-ConfigValue -Config $config -Key 'TCP_PORTS' -DefaultValue (Get-ClagnosDefaultTcpPortsCsv))
    $portsDefault = ''
    try { $portsDefault = [string](Resolve-ClagnosTcpPortSpecification -Text $portsDefaultRaw -RequiredPorts $requiredPorts).CanonicalText }
    catch { Write-Host ('Port default will need correction: {0}' -f [string]$_.Exception.Message) -ForegroundColor Yellow }
    if (-not [string]::IsNullOrWhiteSpace([string]$vmNameDefault)) { $wizardSources['SELECTED_VM_NAME'] = 'default' }
    if (-not [string]::IsNullOrWhiteSpace([string]$regionDefault)) { $wizardSources['SELECTED_AZURE_REGION'] = 'default' }
    if (-not [string]::IsNullOrWhiteSpace([string]$vmSizeDefault)) { $wizardSources[$vmSizeKey] = 'default' }
    if (-not [string]::IsNullOrWhiteSpace([string]$imageDefault)) { $wizardSources[$imageKey] = 'default' }
    if (-not [string]::IsNullOrWhiteSpace([string]$diskDefault)) { $wizardSources[$diskKey] = 'default' }
    if (-not [string]::IsNullOrWhiteSpace([string]$storageSkuDefault)) { $wizardSources['VM_STORAGE_SKU'] = 'default' }
    if (-not [string]::IsNullOrWhiteSpace([string]$securityDefault)) { $wizardSources['VM_SECURITY_TYPE'] = 'default' }
    if (-not [string]::IsNullOrWhiteSpace([string]$hibernationDefault)) { $wizardSources['VM_ENABLE_HIBERNATION'] = 'default' }
    if (-not [string]::IsNullOrWhiteSpace([string]$nestedDefault)) { $wizardSources['VM_ENABLE_NESTED_VIRTUALIZATION'] = 'default' }
    if ($securityDefault -eq 'TrustedLaunch') {
        $wizardSources['VM_ENABLE_SECURE_BOOT'] = 'default'
        $wizardSources['VM_ENABLE_VTPM'] = 'default'
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$sshPortDefault)) { $wizardSources['VM_SSH_PORT'] = 'default' }
    if ($platform -eq 'windows' -and -not [string]::IsNullOrWhiteSpace([string]$rdpPortDefault)) { $wizardSources['VM_RDP_PORT'] = 'default' }
    if (-not [string]::IsNullOrWhiteSpace([string]$portsDefault)) { $wizardSources['TCP_PORTS'] = 'default' }

    if (-not $skipRemaining) {
        $nameResult = Read-ClagnosUiWizardTextStep -Title 'Virtual computer name' -DefaultValue $vmNameDefault -Example '3-16 characters, starts with a letter' -Required -Validator {
            param($value)
            $candidate = ([string]$value).Trim()
            if (-not (Test-ClagnosVmNameFormat -VmName $candidate)) { throw 'VM name must contain 3-16 characters, start with a letter, and use only letters, numbers, or hyphens.' }
            return $candidate
        }
        if ($nameResult.Action -eq 'close') { return }
        $wizardValues['VmName'] = [string]$nameResult.Value
        $wizardSources['SELECTED_VM_NAME'] = if ($nameResult.Action -in @('skip','apply-default','skip-all','apply-all')) { 'default' } else { 'selected' }
        if ($nameResult.Action -in @('skip-all','apply-all')) { $skipRemaining = $true }
    }
    else { $wizardValues['VmName'] = $vmNameDefault }

    $vmNameForTokens = if (-not [string]::IsNullOrWhiteSpace([string]$wizardValues['VmName'])) { [string]$wizardValues['VmName'] } else { [string]$vmNameDefault }
    $imageDefault = Resolve-ClagnosTemplate -Template $imageRawDefault -Tokens @{ SELECTED_VM_NAME = $vmNameForTokens }
    $diskDefaultValue = $diskDefault
    $portDefaultValue = $portsDefault
    $regionValue = $regionDefault
    $sizeValue = $vmSizeDefault

    if (-not $skipRemaining) {
        try { $locations = @(Get-AzLocationCatalog) }
        catch {
            Write-ClagnosUiError -ErrorRecord $_
            Wait-ClagnosUiContinue
            return
        }
        $locationOptions = @($locations | ForEach-Object {
            $locationName = [string]$_.Name
            $displayName = if ([string]::IsNullOrWhiteSpace([string]$_.DisplayName)) { $locationName } else { [string]$_.DisplayName }
            [pscustomobject]@{ Value = $locationName; Label = $displayName; Detail = $locationName }
        })
        if (@($locationOptions).Count -eq 0) {
            Write-ClagnosUiError -ErrorRecord ([System.Exception]::new('Azure returned no selectable regions for the active subscription.'))
            Wait-ClagnosUiContinue
            return
        }
        $regionResult = Resolve-ClagnosUiWizardPageStep -Options $locationOptions -Prompt 'Azure region' -DefaultValue $regionDefault -Required
        if ($regionResult.Action -eq 'close') { return }
        $regionValue = [string]$regionResult.Value
        $wizardSources['SELECTED_AZURE_REGION'] = if ($regionResult.Action -in @('skip','apply-default','skip-all','apply-all')) { 'default' } else { 'selected' }
        if ($regionResult.Action -in @('skip-all','apply-all')) { $skipRemaining = $true }
    }

    if (-not $skipRemaining) {
        $skuFilter = ''
        $skuChosen = $false
        while (-not $skuChosen) {
            try { $skuRows = @(Get-LocationSkusForSelection -Location $regionValue -SkuLike $skuFilter) }
            catch {
                Write-ClagnosUiError -ErrorRecord $_
                Wait-ClagnosUiContinue
                return
            }
            if (@($skuRows).Count -eq 0) {
                Write-ClagnosUiHeader -Title ("VM size/SKU in {0}" -f $regionValue)
                Write-Host ('No VM sizes matched the current filter "{0}".' -f $skuFilter) -ForegroundColor Yellow
                Write-Host 'x: change or clear SKU filter'
                Write-Host 'r: restart wizard and choose another region'
                Write-Host 'c: close wizard'
                $emptySkuChoice = (Read-ClagnosUiChoice 'SKU list action').ToLowerInvariant()
                if ($emptySkuChoice -eq 'x') {
                    $skuFilter = Read-ClagnosUiValidatedText -Prompt 'Filter SKU names (letters, numbers, _, -, ., *, ?; Enter clears filter)' -AllowBlank -Validator {
                        param($value)
                        $candidate = ([string]$value).Trim()
                        if ($candidate.Length -gt 80 -or $candidate -notmatch '^[a-zA-Z0-9_*?.-]*$') { throw 'SKU filter may use only letters, numbers, period, underscore, hyphen, * and ? (maximum 80 characters).' }
                        return $candidate
                    }
                    continue
                }
                if ($emptySkuChoice -eq 'r') { return (Show-ClagnosUiCreateWizard) }
                return
            }
            $skuAvailability = @{}
            try {
                $skuAvailability = Get-SkuAvailabilityMap -Location $regionValue -SkuNames @($skuRows | ForEach-Object { [string]$_.name })
            }
            catch {
                Write-Host ('VM-size availability could not be read: {0}. The create workflow will revalidate before Azure mutation.' -f [string]$_.Exception.Message) -ForegroundColor Yellow
                foreach ($sku in @($skuRows)) { $skuAvailability[[string]$sku.name] = 'unknown' }
            }
            $skuOptions = @($skuRows | ForEach-Object {
                $availability = if ($skuAvailability.ContainsKey([string]$_.name)) { [string]$skuAvailability[[string]$_.name] } else { 'unknown' }
                $ramGb = [Math]::Round(([double]$_.memoryInMb / 1024.0), 2)
                [pscustomobject]@{ Value = [string]$_.name; Label = [string]$_.name; Detail = ('{0} vCPU | {1} GB RAM | {2}' -f [int]$_.numberOfCores, $ramGb, $availability); Enabled = ($availability -ne 'no') }
            })
            $skuResult = Resolve-ClagnosUiWizardPageStep -Options $skuOptions -Prompt ("VM size/SKU in {0}" -f $regionValue) -DefaultValue $vmSizeDefault -ExtraKeys @('x') -Required
            if ($skuResult.Action -eq 'close') { return }
            if ($skuResult.Action -eq 'extra' -and [string]$skuResult.ExtraKey -eq 'x') {
                $skuFilter = Read-ClagnosUiValidatedText -Prompt 'Filter SKU names (letters, numbers, _, -, ., *, ?; Enter clears filter)' -AllowBlank -Validator {
                    param($value)
                    $candidate = ([string]$value).Trim()
                    if ($candidate.Length -gt 80 -or $candidate -notmatch '^[a-zA-Z0-9_*?.-]*$') { throw 'SKU filter may use only letters, numbers, period, underscore, hyphen, * and ? (maximum 80 characters).' }
                    return $candidate
                }
                if ($skuFilter -eq '*') { $skuFilter = '' }
                continue
            }
            $sizeValue = [string]$skuResult.Value
            $wizardSources[$vmSizeKey] = if ($skuResult.Action -in @('skip','apply-default','skip-all','apply-all')) { 'default' } else { 'selected' }
            if ($skuResult.Action -in @('skip-all','apply-all')) { $skipRemaining = $true }
            $skuChosen = -not [string]::IsNullOrWhiteSpace([string]$sizeValue)
        }
    }

    $imageValue = $imageDefault
    $storageSkuValue = $storageSkuDefault
    $securityValue = $securityDefault
    $hibernationValue = $hibernationDefault
    $nestedValue = $nestedDefault
    $secureBootValue = $secureBootDefault
    $vtpmValue = $vtpmDefault
    if (-not $skipRemaining) {
        $imageChoiceOptions = @(
            [pscustomobject]@{ Value = 'default'; Label = 'Use configured image'; Detail = $imageDefault },
            [pscustomobject]@{ Value = 'custom'; Label = 'Enter a custom image URN'; Detail = 'publisher:offer:sku:version' }
        )
        $imageChoice = Resolve-ClagnosUiWizardPageStep -Options $imageChoiceOptions -Prompt 'OS image' -DefaultValue 'default' -Required
        if ($imageChoice.Action -eq 'close') { return }
        if ($imageChoice.Value -eq 'custom') {
            $imageResult = Read-ClagnosUiWizardTextStep -Title 'Custom OS image' -DefaultValue '' -Example 'publisher:offer:sku:latest or a full Azure image resource ID' -Required -Validator {
                param($value)
                $candidate = ([string]$value).Trim()
                if ($candidate -notmatch '^[^:\s]+:[^:\s]+:[^:\s]+:[^:\s]+$' -and $candidate -notmatch '^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\.Compute/images/[^/]+$') { throw 'Image must be a four-part marketplace URN or a Compute image resource ID.' }
                return $candidate
            }
            if ($imageResult.Action -eq 'close') { return }
            $imageValue = [string]$imageResult.Value
            $wizardSources[$imageKey] = 'selected'
            if ($imageResult.Action -in @('skip-all','apply-all')) { $skipRemaining = $true }
        }
        else { $wizardSources[$imageKey] = 'default' }
    }

    if (-not $skipRemaining) {
        $storageOptions = @(
            [pscustomobject]@{ Value = 'Standard_LRS'; Label = 'Standard HDD'; Detail = 'Standard_LRS' },
            [pscustomobject]@{ Value = 'StandardSSD_LRS'; Label = 'Standard SSD'; Detail = 'StandardSSD_LRS' },
            [pscustomobject]@{ Value = 'Premium_LRS'; Label = 'Premium SSD'; Detail = 'Premium_LRS' }
        )
        if ($storageSkuDefault -notin @($storageOptions | ForEach-Object { [string]$_.Value })) { $storageOptions = @([pscustomobject]@{ Value = $storageSkuDefault; Label = ('Configured: {0}' -f $storageSkuDefault); Detail = 'current .env default' }) + @($storageOptions) }
        $storageResult = Resolve-ClagnosUiWizardPageStep -Options $storageOptions -Prompt 'OS disk storage performance tier' -DefaultValue $storageSkuDefault -Required
        if ($storageResult.Action -eq 'close') { return }
        $storageSkuValue = [string]$storageResult.Value
        $wizardSources['VM_STORAGE_SKU'] = if ($storageResult.Action -in @('skip','apply-default','skip-all','apply-all')) { 'default' } else { 'selected' }
        if ($storageResult.Action -in @('skip-all','apply-all')) { $skipRemaining = $true }
    }

    if (-not $skipRemaining) {
        $securityOptions = @(
            [pscustomobject]@{ Value = 'Standard'; Label = 'Standard'; Detail = 'Standard security profile' },
            [pscustomobject]@{ Value = 'TrustedLaunch'; Label = 'Trusted Launch'; Detail = 'Secure Boot and vTPM settings apply' }
        )
        $securityResult = Resolve-ClagnosUiWizardPageStep -Options $securityOptions -Prompt 'VM security type' -DefaultValue $securityDefault -Required
        if ($securityResult.Action -eq 'close') { return }
        $securityValue = [string]$securityResult.Value
        $wizardSources['VM_SECURITY_TYPE'] = if ($securityResult.Action -in @('skip','apply-default','skip-all','apply-all')) { 'default' } else { 'selected' }
        if ($securityValue -eq 'TrustedLaunch') {
            if (-not [string]::IsNullOrWhiteSpace([string]$secureBootDefault)) { $wizardSources['VM_ENABLE_SECURE_BOOT'] = 'default' }
            if (-not [string]::IsNullOrWhiteSpace([string]$vtpmDefault)) { $wizardSources['VM_ENABLE_VTPM'] = 'default' }
        }
        if ($securityResult.Action -in @('skip-all','apply-all')) { $skipRemaining = $true }
    }

    if (-not $skipRemaining) {
        $toggleOptions = @([pscustomobject]@{ Value = 'true'; Label = 'Enabled'; Detail = '' }, [pscustomobject]@{ Value = 'false'; Label = 'Disabled'; Detail = '' })
        $hibernationResult = Resolve-ClagnosUiWizardPageStep -Options $toggleOptions -Prompt 'Hibernation' -DefaultValue $hibernationDefault -Required
        if ($hibernationResult.Action -eq 'close') { return }
        $hibernationValue = [string]$hibernationResult.Value
        $wizardSources['VM_ENABLE_HIBERNATION'] = if ($hibernationResult.Action -in @('skip','apply-default','skip-all','apply-all')) { 'default' } else { 'selected' }
        if ($hibernationResult.Action -in @('skip-all','apply-all')) { $skipRemaining = $true }
    }

    if (-not $skipRemaining) {
        $toggleOptions = @([pscustomobject]@{ Value = 'true'; Label = 'Enabled'; Detail = '' }, [pscustomobject]@{ Value = 'false'; Label = 'Disabled'; Detail = '' })
        $nestedResult = Resolve-ClagnosUiWizardPageStep -Options $toggleOptions -Prompt 'Nested virtualization' -DefaultValue $nestedDefault -Required
        if ($nestedResult.Action -eq 'close') { return }
        $nestedValue = [string]$nestedResult.Value
        $wizardSources['VM_ENABLE_NESTED_VIRTUALIZATION'] = if ($nestedResult.Action -in @('skip','apply-default','skip-all','apply-all')) { 'default' } else { 'selected' }
        if ($nestedResult.Action -in @('skip-all','apply-all')) { $skipRemaining = $true }
    }

    if (-not $skipRemaining -and $securityValue -eq 'TrustedLaunch') {
        $toggleOptions = @([pscustomobject]@{ Value = 'true'; Label = 'Enabled'; Detail = '' }, [pscustomobject]@{ Value = 'false'; Label = 'Disabled'; Detail = '' })
        $secureBootResult = Resolve-ClagnosUiWizardPageStep -Options $toggleOptions -Prompt 'Secure Boot (Trusted Launch)' -DefaultValue $secureBootDefault -Required
        if ($secureBootResult.Action -eq 'close') { return }
        $secureBootValue = [string]$secureBootResult.Value
        $wizardSources['VM_ENABLE_SECURE_BOOT'] = if ($secureBootResult.Action -in @('skip','apply-default','skip-all','apply-all')) { 'default' } else { 'selected' }
        if ($secureBootResult.Action -in @('skip-all','apply-all')) { $skipRemaining = $true }
        if (-not $skipRemaining) {
            $vtpmResult = Resolve-ClagnosUiWizardPageStep -Options $toggleOptions -Prompt 'vTPM (Trusted Launch)' -DefaultValue $vtpmDefault -Required
            if ($vtpmResult.Action -eq 'close') { return }
            $vtpmValue = [string]$vtpmResult.Value
            $wizardSources['VM_ENABLE_VTPM'] = if ($vtpmResult.Action -in @('skip','apply-default','skip-all','apply-all')) { 'default' } else { 'selected' }
            if ($vtpmResult.Action -in @('skip-all','apply-all')) { $skipRemaining = $true }
        }
    }

    if (-not $skipRemaining) {
        $sshPortResult = Read-ClagnosUiWizardTextStep -Title 'SSH connection port' -DefaultValue $sshPortDefault -Example '22 or 2222' -Required -Validator {
            param($value)
            return (Resolve-ClagnosTcpPortNumber -Value ([string]$value) -Label 'SSH port')
        }
        if ($sshPortResult.Action -eq 'close') { return }
        $wizardValues['SshPort'] = [string]$sshPortResult.Value
        $wizardSources['VM_SSH_PORT'] = if ($sshPortResult.Action -in @('skip','apply-default','skip-all','apply-all')) { 'default' } else { 'selected' }
        if ($sshPortResult.Action -in @('skip-all','apply-all')) { $skipRemaining = $true }
    }
    if (-not $skipRemaining -and $platform -eq 'windows') {
        $rdpPortResult = Read-ClagnosUiWizardTextStep -Title 'RDP connection port' -DefaultValue $rdpPortDefault -Example '3389 or 3390' -Required -Validator {
            param($value)
            return (Resolve-ClagnosTcpPortNumber -Value ([string]$value) -Label 'RDP port')
        }
        if ($rdpPortResult.Action -eq 'close') { return }
        $wizardValues['RdpPort'] = [string]$rdpPortResult.Value
        $wizardSources['VM_RDP_PORT'] = if ($rdpPortResult.Action -in @('skip','apply-default','skip-all','apply-all')) { 'default' } else { 'selected' }
        if ($rdpPortResult.Action -in @('skip-all','apply-all')) { $skipRemaining = $true }
    }

    if (-not $skipRemaining) {
        $diskResult = Read-ClagnosUiWizardTextStep -Title 'OS disk size' -DefaultValue $diskDefaultValue -Example '1MB, 128GB, or 1TB (Azure maximum: 4095GB)' -Required -Validator {
            param($value)
            return (ConvertTo-ClagnosOsDiskSizeGb -Value ([string]$value) -FieldName 'OS disk size')
        }
        if ($diskResult.Action -eq 'close') { return }
        $wizardValues['DiskSizeGb'] = [string]$diskResult.Value
        $wizardSources[$diskKey] = if ($diskResult.Action -in @('skip','apply-default','skip-all','apply-all')) { 'default' } else { 'selected' }
        if ($diskResult.Action -in @('skip-all','apply-all')) { $skipRemaining = $true }
    }

    if (-not $skipRemaining) {
        $portsResult = Read-ClagnosUiWizardTextStep -Title 'Inbound TCP ports' -DefaultValue $portDefaultValue -Example '22,80,443,3000-3300' -Required -Validator {
            param($value)
            $required = @([string]$wizardValues['SshPort'])
            if ($platform -eq 'windows') { $required += [string]$wizardValues['RdpPort'] }
            return [string](Resolve-ClagnosTcpPortSpecification -Text ([string]$value) -RequiredPorts $required).CanonicalText
        }
        if ($portsResult.Action -eq 'close') { return }
        $wizardValues['TcpPorts'] = [string]$portsResult.Value
        $wizardSources['TCP_PORTS'] = if ($portsResult.Action -in @('skip','apply-default','skip-all','apply-all')) { 'default' } else { 'selected' }
    }

    if (-not $wizardValues.ContainsKey('DiskSizeGb')) { $wizardValues['DiskSizeGb'] = [string]$diskDefaultValue }
    if (-not $wizardValues.ContainsKey('TcpPorts')) { $wizardValues['TcpPorts'] = [string]$portDefaultValue }
    $finalRequiredPorts = @([string]$wizardValues['SshPort'])
    if ($platform -eq 'windows') { $finalRequiredPorts += [string]$wizardValues['RdpPort'] }
    try { $wizardValues['TcpPorts'] = [string](Resolve-ClagnosTcpPortSpecification -Text ([string]$wizardValues['TcpPorts']) -RequiredPorts $finalRequiredPorts).CanonicalText }
    catch { $wizardValues['TcpPorts'] = '' }

    $missingValues = @()
    if ([string]::IsNullOrWhiteSpace([string]$wizardValues['VmName'])) { $missingValues += 'VM name' }
    if ([string]::IsNullOrWhiteSpace([string]$regionValue)) { $missingValues += 'Azure region' }
    if ([string]::IsNullOrWhiteSpace([string]$sizeValue)) { $missingValues += 'VM size/SKU' }
    if ([string]::IsNullOrWhiteSpace([string]$imageValue)) { $missingValues += 'OS image' }
    if ([string]::IsNullOrWhiteSpace([string]$wizardValues['DiskSizeGb'])) { $missingValues += 'OS disk size' }
    if ([string]::IsNullOrWhiteSpace([string]$wizardValues['TcpPorts'])) { $missingValues += 'TCP ports' }
    if ([string]::IsNullOrWhiteSpace([string]$wizardValues['SshPort'])) { $missingValues += 'SSH port' }
    if ($platform -eq 'windows' -and [string]::IsNullOrWhiteSpace([string]$wizardValues['RdpPort'])) { $missingValues += 'RDP port' }
    if ($securityValue -eq 'TrustedLaunch' -and [string]::IsNullOrWhiteSpace([string]$secureBootValue)) { $missingValues += 'Secure Boot state' }
    if ($securityValue -eq 'TrustedLaunch' -and [string]::IsNullOrWhiteSpace([string]$vtpmValue)) { $missingValues += 'vTPM state' }
    if (@($missingValues).Count -gt 0) {
        Write-ClagnosUiHeader -Title 'Create wizard — incomplete configuration'
        Write-Host ('Required defaults or selections are missing: {0}.' -f ($missingValues -join ', ')) -ForegroundColor Yellow
        Write-Host 'r: restart wizard'
        Write-Host 'c: close'
        if ((Read-ClagnosUiChoice 'Create wizard action').ToLowerInvariant() -eq 'r') { return (Show-ClagnosUiCreateWizard) }
        return
    }

    $reviewRows = @(
        [pscustomobject]@{ Label = 'Operating system'; Value = $platform; Key = 'SELECTED_VM_OS' },
        [pscustomobject]@{ Label = 'VM name'; Value = [string]$wizardValues['VmName']; Key = 'SELECTED_VM_NAME' },
        [pscustomobject]@{ Label = 'Azure region'; Value = [string]$regionValue; Key = 'SELECTED_AZURE_REGION' },
        [pscustomobject]@{ Label = 'VM size'; Value = [string]$sizeValue; Key = $vmSizeKey },
        [pscustomobject]@{ Label = 'OS image'; Value = [string]$imageValue; Key = $imageKey },
        [pscustomobject]@{ Label = 'OS disk size'; Value = ('{0} GB' -f [string]$wizardValues['DiskSizeGb']); Key = $diskKey },
        [pscustomobject]@{ Label = 'SSH port'; Value = [string]$wizardValues['SshPort']; Key = 'VM_SSH_PORT' },
        [pscustomobject]@{ Label = 'Storage SKU'; Value = [string]$storageSkuValue; Key = 'VM_STORAGE_SKU' },
        [pscustomobject]@{ Label = 'Security type'; Value = [string]$securityValue; Key = 'VM_SECURITY_TYPE' },
        [pscustomobject]@{ Label = 'Hibernation'; Value = [string]$hibernationValue; Key = 'VM_ENABLE_HIBERNATION' },
        [pscustomobject]@{ Label = 'Nested virtualization requested'; Value = [string]$nestedValue; Key = 'VM_ENABLE_NESTED_VIRTUALIZATION' },
        [pscustomobject]@{ Label = 'Inbound TCP ports'; Value = [string]$wizardValues['TcpPorts']; Key = 'TCP_PORTS' }
    )
    if ($platform -eq 'windows') {
        $reviewRows += [pscustomobject]@{ Label = 'RDP port'; Value = [string]$wizardValues['RdpPort']; Key = 'VM_RDP_PORT' }
    }
    if ($securityValue -eq 'TrustedLaunch') {
        $reviewRows += @([pscustomobject]@{ Label = 'Secure Boot'; Value = [string]$secureBootValue; Key = 'VM_ENABLE_SECURE_BOOT' }, [pscustomobject]@{ Label = 'vTPM'; Value = [string]$vtpmValue; Key = 'VM_ENABLE_VTPM' })
    }

    Write-ClagnosUiHeader -Title 'Create wizard — review'
    Write-Host ('Azure subscription: {0} ({1})' -f [string]$script:ClagnosUiSubscription.SubscriptionName, [string]$script:ClagnosUiSubscription.SubscriptionId)
    foreach ($reviewRow in @($reviewRows)) {
        $marker = if ($wizardSources.ContainsKey([string]$reviewRow.Key) -and [string]$wizardSources[[string]$reviewRow.Key] -eq 'default') { '>' } else { ' ' }
        Write-Host ('{0} {1}: {2}' -f $marker, [string]$reviewRow.Label, [string]$reviewRow.Value)
    }
    Write-Host 'a: apply selected setup'
    Write-Host 'l: apply all (keep all remaining configured defaults)'
    Write-Host 'c: close without creating'
    $finalChoice = (Read-ClagnosUiChoice 'Create virtual computer').ToLowerInvariant()
    if ($finalChoice -notin @('a','l')) { return }

    $options = @{
        'subscription-id' = $subscriptionId
        'vm-name' = [string]$wizardValues['VmName']
        'vm-region' = [string]$regionValue
        'vm-size' = [string]$sizeValue
    }
    $options[$platform] = $true
    $wizardAnswers = @{
        Image = [string]$imageValue
        DiskSizeGb = [string]$wizardValues['DiskSizeGb']
        TcpPorts = [string]$wizardValues['TcpPorts']
        StorageSku = [string]$storageSkuValue
        SecurityType = [string]$securityValue
        Hibernation = [string]$hibernationValue
        NestedVirtualization = [string]$nestedValue
        SecureBoot = [string]$secureBootValue
        Vtpm = [string]$vtpmValue
        SshPort = [string]$wizardValues['SshPort']
    }
    if ($platform -eq 'windows') { $wizardAnswers['RdpPort'] = [string]$wizardValues['RdpPort'] }
    Invoke-ClagnosUiCommand -CommandName 'create' -Options $options -FrontendContext @{ CreateWizardMode = $true; CreateWizardValues = $wizardAnswers }
}

function Show-ClagnosUiVirtualComputers {
    while ($true) {
        Write-ClagnosUiHeader -Title 'Virtual computers'
        try {
            $vms = @(Get-ClagnosUiVirtualComputers)
            $resourceSnapshot = Ensure-ClagnosUiResourceCache
        }
        catch { Write-ClagnosUiError -ErrorRecord $_; $vms = @() }
        if ($vms.Count -eq 0) {
            $cacheUnavailable = $null -eq $script:ClagnosUiInventoryCache -or [bool]$script:ClagnosUiInventoryCache.IsDirty
            if ($cacheUnavailable) { Write-Host 'Managed inventory is loading or refreshing in the background.' -ForegroundColor Yellow }
            else { Write-Host 'No managed virtual computers were found.' -ForegroundColor Yellow }
            Write-Host 'c: create virtual computer'
            Write-Host 'r: check or refresh managed resource cache'
            Write-Host 'b: back'
            Write-Host 'q: exit'
            $emptyChoice = (Read-ClagnosUiChoice).ToLowerInvariant()
            if ($emptyChoice -eq 'b') { return }
            if ($emptyChoice -eq 'q') { Stop-ClagnosUiBackgroundCacheWorker; exit }
            if ($emptyChoice -eq 'c') { Show-ClagnosUiCreateWizard; continue }
            if ($emptyChoice -eq 'r') { Update-ClagnosUiSubscription; Request-ClagnosUiInventoryRefresh -Force | Out-Null; continue }
            continue
        }

        $vmOptions = @(
            $vms | ForEach-Object {
                $power = Get-ClagnosUiPowerState -ResourceGroup ([string]$_.ClagnosResourceGroup) -VmName ([string]$_.name) -CachedPowerState ([string]$_.powerState)
                $vmOs = [string]$_.storageProfile.osDisk.osType
                $value = '{0}|{1}' -f [string]$_.ClagnosResourceGroup, [string]$_.name
                [pscustomobject]@{ Value = $value; Label = [string]$_.name; Detail = ('{0} | {1} | {2} | {3}' -f $vmOs, [string]$_.hardwareProfile.vmSize, [string]$_.location, $power) }
            }
        )
        $defaultVm = '{0}|{1}' -f [string]$script:ClagnosUiSelectedResourceGroup, [string]$script:ClagnosUiSelectedVmName
        $selection = Select-ClagnosNumberedOptionPage -Options $vmOptions -Prompt 'Virtual computers' -DefaultValue $defaultVm -PageSize 12 -ExtraKeys @('c','r') -ExtraKeyLabels @{ c = 'create virtual computer'; r = 'refresh managed resource cache' }
        if ([string]$selection.Action -eq 'back') { if ([string]$selection.Input -eq 'q') { Stop-ClagnosUiBackgroundCacheWorker; exit }; return }
        if ([string]$selection.Action -eq 'extra' -and [string]$selection.ExtraKey -eq 'c') { Show-ClagnosUiCreateWizard; continue }
        if ([string]$selection.Action -eq 'extra' -and [string]$selection.ExtraKey -eq 'r') { Update-ClagnosUiSubscription; Request-ClagnosUiInventoryRefresh -Force | Out-Null; continue }
        if ([string]$selection.Action -ne 'selected') { continue }
        $selectedParts = @(([string]$selection.Value -split '\|', 2))
        $selectedVm = @($vms | Where-Object {
            [string]::Equals([string]$_.ClagnosResourceGroup, [string]$selectedParts[0], [System.StringComparison]::OrdinalIgnoreCase) -and
            [string]::Equals([string]$_.name, [string]$selectedParts[1], [System.StringComparison]::OrdinalIgnoreCase)
        } | Select-Object -First 1)
        if (@($selectedVm).Count -gt 0) { Show-ClagnosUiVmMenu -Vm $selectedVm[0] }
    }
}

function Show-ClagnosUiInventoryMenu {
    $types = @(
        @{ Id = 'group'; Label = 'Resource groups' },
        @{ Id = 'vm'; Label = 'Virtual machines' },
        @{ Id = 'disk'; Label = 'Managed disks' },
        @{ Id = 'vnet'; Label = 'Virtual networks' },
        @{ Id = 'subnet'; Label = 'Subnets' },
        @{ Id = 'nic'; Label = 'Network interfaces' },
        @{ Id = 'ip'; Label = 'Public IP addresses' },
        @{ Id = 'nsg'; Label = 'Network security groups' },
        @{ Id = 'nsg-rule'; Label = 'Network security rules' }
    )

    while ($true) {
        Write-ClagnosUiHeader -Title 'Managed resource inventory'
        if ($null -eq $script:ClagnosUiInventoryCache -or [bool]$script:ClagnosUiInventoryCache.IsDirty) {
            Write-Host 'Managed inventory is loading or refreshing in the background.' -ForegroundColor Yellow
            Write-Host 'r: request cache refresh'
            Write-Host 'b: back'
            Write-Host 'q: exit'
            $warmingChoice = (Read-ClagnosUiChoice).ToLowerInvariant()
            if ($warmingChoice -eq 'b') { return }
            if ($warmingChoice -eq 'q') { Stop-ClagnosUiBackgroundCacheWorker; exit }
            if ($warmingChoice -eq 'r') { Request-ClagnosUiInventoryRefresh -Force | Out-Null }
            continue
        }
        Write-Host '1. All managed resource types'
        for ($index = 0; $index -lt $types.Count; $index++) {
            Write-Host ('{0}. {1}' -f ($index + 2), [string]$types[$index].Label)
        }
        Write-Host 'b: back'
        Write-Host 'r: refresh managed resource cache'
        Write-Host 'q: exit'
        $choice = (Read-ClagnosUiChoice).ToLowerInvariant()
        if ($choice -eq 'b') { return }
        if ($choice -eq 'q') { Stop-ClagnosUiBackgroundCacheWorker; exit }
        if ($choice -eq 'r') {
            Update-ClagnosUiSubscription
            Request-ClagnosUiInventoryRefresh -Force | Out-Null
            continue
        }

        $number = 0
        if (-not [int]::TryParse($choice, [ref]$number) -or $number -lt 1 -or $number -gt ($types.Count + 1)) { continue }
        $group = ''
        try {
            $groupSnapshot = Ensure-ClagnosUiResourceCache
            $groupOptions = @([pscustomobject]@{ Value = '__all__'; Label = 'All managed resource groups'; Detail = '' })
            $groupOptions += @($groupSnapshot.Groups | Sort-Object { [string]$_.name } | ForEach-Object {
                [pscustomobject]@{ Value = [string]$_.name; Label = [string]$_.name; Detail = [string]$_.location }
            })
            $groupDefault = '__all__'
            $groupSelection = Select-ClagnosNumberedOptionPage -Options $groupOptions -Prompt 'Filter by resource group' -DefaultValue $groupDefault -PageSize 12
            if ([string]$groupSelection.Action -eq 'back') { continue }
            if ([string]$groupSelection.Action -ne 'selected') { continue }
            if ([string]$groupSelection.Value -ne '__all__') { $group = [string]$groupSelection.Value }
        }
        catch {
            Write-ClagnosUiError -ErrorRecord $_
            Wait-ClagnosUiContinue
            continue
        }
        $typeName = if ($number -gt 1) { [string]$types[$number - 2].Id } else { '' }
        try {
            if (-not [string]::IsNullOrWhiteSpace([string]$group)) {
                $snapshot = Ensure-ClagnosUiResourceCache
                $groupMatch = @($snapshot.Groups | Where-Object { [string]::Equals([string]$_.name, [string]$group, [System.StringComparison]::OrdinalIgnoreCase) })
                if (@($groupMatch).Count -eq 0) {
                    Write-Host ('No managed resource group named {0} exists in the current cache.' -f $group) -ForegroundColor Yellow
                    Wait-ClagnosUiContinue
                    continue
                }
            }
            $rows = @(Get-ClagnosUiCachedInventoryRows -TypeName $typeName -ResourceGroup $group)
            Write-Host ''
            Write-Host 'Managed Clagnos inventory (cached snapshot):' -ForegroundColor Cyan
            if ([string]::IsNullOrWhiteSpace([string]$typeName)) { $displayTypes = @($types | ForEach-Object { [string]$_.Id }) }
            else { $displayTypes = @($typeName) }
            foreach ($displayType in @($displayTypes)) {
                $displayRows = if ([string]::IsNullOrWhiteSpace([string]$typeName)) { @(Get-ClagnosUiCachedInventoryRows -TypeName $displayType -ResourceGroup $group) } else { @($rows) }
                Write-Host ''
                Write-Host ($displayType.ToUpperInvariant() + ':') -ForegroundColor Cyan
                if (@($displayRows).Count -eq 0) { Write-Host '- (none)' }
                else { foreach ($row in @($displayRows)) { Write-Host ('- {0}' -f [string]$row) } }
            }
            Write-Host ''
            Write-Host ('Snapshot validated: {0} UTC | resources cached: {1}' -f ([DateTime]$snapshot.LastValidatedAtUtc).ToString('u'), @($snapshot.Resources).Count) -ForegroundColor DarkGray
            Wait-ClagnosUiContinue
        }
        catch {
            Write-ClagnosUiError -ErrorRecord $_
            Wait-ClagnosUiContinue
        }
    }
}

function Show-ClagnosUiHome {
    while ($true) {
        Update-ClagnosUiSubscription
        try {
            if (Test-ClagnosUiBackgroundCacheWorkerDisabled) {
                Ensure-ClagnosUiResourceCache | Out-Null
            }
            else {
                Import-ClagnosUiInventoryCacheFromDisk | Out-Null
                Start-ClagnosUiBackgroundCacheWorker | Out-Null
                if ($null -ne $script:ClagnosUiInventoryCache) { Ensure-ClagnosUiResourceCache | Out-Null }
                else { throw 'Managed inventory is warming in the background.' }
            }
            $script:ClagnosUiResourceCacheError = ''
        }
        catch {
            $script:ClagnosUiResourceCacheError = [string]$_.Exception.Message
        }
        Write-ClagnosUiHeader -Title 'Main menu'
        if (-not [string]::IsNullOrWhiteSpace([string]$script:ClagnosUiResourceCacheError)) {
            Write-Host ('Managed resource cache unavailable: {0}' -f [string]$script:ClagnosUiResourceCacheError) -ForegroundColor Yellow
        }
        Write-Host '1. Virtual computers'
        Write-Host '2. Managed resource inventory'
        Write-Host '3. Cloud subscriptions'
        Write-Host 'c: configure settings'
        Write-Host 'h: help'
        Write-Host 'q: exit'
        $choice = (Read-ClagnosUiChoice).ToLowerInvariant()
        switch ($choice) {
            '1' { Show-ClagnosUiVirtualComputers }
            '2' { Show-ClagnosUiInventoryMenu }
            '3' { Show-ClagnosUiCloudSubscriptions }
            'c' { Invoke-ClagnosUiCommand -CommandName 'configure' -Options @{} }
            'h' { Invoke-ClagnosUiCommand -CommandName 'help' -Options @{} }
            'q' { return }
        }
    }
}

try { Show-ClagnosUiHome }
finally { Stop-ClagnosUiBackgroundCacheWorker }
