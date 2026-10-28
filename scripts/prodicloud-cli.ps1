[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$CliTokens
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$env:PYTHONDONTWRITEBYTECODE = '1'

$script:ProdicloudUiRepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$script:ProdicloudUiBackendPath = Join-Path $script:ProdicloudUiRepoRoot 'prodicloud.ps1'
$script:ProdicloudUiStartupTokens = $null
if ($null -ne $CliTokens) {
    $script:ProdicloudUiStartupTokens = [string[]]@($CliTokens | ForEach-Object { [string]$_ })
}
$script:ProdicloudUiSubscription = $null
$script:ProdicloudUiSubscriptionError = ''
$script:ProdicloudUiSelectedResourceGroup = ''
$script:ProdicloudUiSelectedVmName = ''
$script:ProdicloudUiResourceCacheError = ''
$script:ProdicloudUiSubscriptionValidatedAtUtc = [DateTime]::MinValue
$script:ProdicloudUiCloudSubscriptionRows = $null
$script:ProdicloudUiCloudSubscriptionRowsValidatedAtUtc = [DateTime]::MinValue
$script:ProdicloudUiAzureCliActiveSubscriptionId = ''
$script:ProdicloudUiAzureCliActiveSubscriptionValidatedAtUtc = [DateTime]::MinValue
$script:ProdicloudUiInventoryCache = $null
$script:ProdicloudUiAzureReadCache = @{}
$script:ProdicloudUiInventoryValidationSeconds = 60
$script:ProdicloudUiReadCacheSeconds = 45
$script:ProdicloudUiInventoryMaximumStaleSeconds = 300
$script:ProdicloudUiCacheWorkerProcess = $null
$script:ProdicloudUiCacheWorkerSubscriptionId = ''
$script:ProdicloudUiCacheWorkerStopPath = ''
$script:ProdicloudUiTestMode = $false
$script:ProdicloudUiInventoryCacheFilePath = ''
$script:ProdicloudUiInventoryCacheFileLastWriteUtc = [DateTime]::MinValue
$script:ProdicloudUiCacheRootPath = ''
$script:ProdicloudUiCurrentScreen = 'Starting'
$script:ProdicloudUiCurrentAction = ''
$script:ProdicloudUiScrollRegionActive = $false
$script:ProdicloudUiLastStatusLines = $null
$script:ProdicloudUiLastStatusRenderWidth = -1
$script:ProdicloudUiTopStatusLinesEnabled = $false
$script:ProdicloudUiStatusCallback = $null

if (-not (Test-Path -LiteralPath $script:ProdicloudUiBackendPath)) {
    throw "Prodicloud runtime was not found: $script:ProdicloudUiBackendPath"
}

. $script:ProdicloudUiBackendPath

function Write-ProdicloudUiError {
    param([object]$ErrorRecord)

    $friendly = Resolve-ProdicloudFriendlyError -ErrorRecord $ErrorRecord -DefaultErrorSummary 'The operation did not complete.' -DefaultErrorHint "Review the reason and retry. Azure operations require 'az login'."
    Write-Host ''
    Write-Host ([string]$friendly.Summary) -ForegroundColor Red
    if (-not [string]::IsNullOrWhiteSpace([string]$friendly.ErrorMessage)) { Write-Host ([string]$friendly.ErrorMessage) -ForegroundColor Gray }
    if (-not [string]::IsNullOrWhiteSpace([string]$friendly.Hint)) { Write-Host ('Next: {0}' -f [string]$friendly.Hint) -ForegroundColor Cyan
    }
}

# The dot-sourced runtime declares the same CliTokens parameter. Restore the
# launcher arguments saved above before deciding between command and TUI mode.
$CliTokens = if ($null -ne $script:ProdicloudUiStartupTokens) { [string[]]$script:ProdicloudUiStartupTokens } else { $null }
if ($null -ne $CliTokens -and @($CliTokens).Count -gt 0) {
    if (@($CliTokens).Count -eq 1 -and [string]$CliTokens[0] -match '^(?i)--version(?:=(?:1|true|yes|on)?)?$') {
        Write-Host ("prodicloud version {0}" -f (Get-ProdicloudCliVersionInfo))
        return
    }
    try {
        $commandName = [string]$CliTokens[0]
        $rawArguments = if (@($CliTokens).Count -gt 1) { @($CliTokens[1..(@($CliTokens).Count - 1)]) } else { @() }
        $parsedCli = Parse-ProdicloudCliArguments -CommandToken $commandName -RawArgs $rawArguments
        Invoke-ProdicloudCommandDispatcher -CommandName ([string]$parsedCli.Command) -Options $parsedCli.Options -HelpTopic ([string]$parsedCli.HelpTopic)
        return
    }
    catch {
        Write-ProdicloudUiError -ErrorRecord $_
        exit 2
    }
}

function Update-ProdicloudUiSubscription {
    param([switch]$Force)

    if (-not $Force -and $null -ne $script:ProdicloudUiSubscription -and $script:ProdicloudUiSubscriptionValidatedAtUtc -ne [DateTime]::MinValue) {
        $subscriptionAge = ([DateTime]::UtcNow - $script:ProdicloudUiSubscriptionValidatedAtUtc).TotalSeconds
        if ($subscriptionAge -lt 60) { return }
    }

    $previousSubscriptionId = if ($null -ne $script:ProdicloudUiSubscription) { [string]$script:ProdicloudUiSubscription.SubscriptionId } else { '' }
    $envPath = Join-Path $script:ProdicloudUiRepoRoot 'prodicloud.env'
    $config = Read-DotEnvFile -Path $envPath -GlobalOnly
    $configuredId = if ($null -ne $config -and $config.ContainsKey('SELECTED_AZURE_SUBSCRIPTION_ID')) { [string]$config['SELECTED_AZURE_SUBSCRIPTION_ID'] } else { '' }
    if (-not [string]::IsNullOrWhiteSpace($configuredId) -and (Test-ProdicloudSubscriptionIdFormat -SubscriptionId $configuredId)) {
        $subscriptionName = $configuredId
        $tenantId = ''
        if ($null -ne $script:ProdicloudUiCloudSubscriptionRows) {
            $knownRow = @($script:ProdicloudUiCloudSubscriptionRows | Where-Object { [string]::Equals([string]$_.id,$configuredId,[System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
            if (@($knownRow).Count -gt 0) { $subscriptionName = [string]$knownRow[0].name; $tenantId = [string]$knownRow[0].tenantId }
        }
        if ($null -ne $script:ProdicloudUiSubscription -and [string]::Equals([string]$script:ProdicloudUiSubscription.SubscriptionId,$configuredId,[System.StringComparison]::OrdinalIgnoreCase) -and -not [string]::IsNullOrWhiteSpace([string]$script:ProdicloudUiSubscription.SubscriptionName)) {
            $subscriptionName = [string]$script:ProdicloudUiSubscription.SubscriptionName
            $tenantId = [string]$script:ProdicloudUiSubscription.TenantId
        }
        $script:ProdicloudUiSubscription = [pscustomobject]@{ SubscriptionId = $configuredId; SubscriptionName = $subscriptionName; TenantId = $tenantId; ResolutionSource = 'prodicloud.env' }
        if ($null -eq $script:ConfigOverrides) { $script:ConfigOverrides = @{} }
        $script:ConfigOverrides['SELECTED_AZURE_SUBSCRIPTION_ID'] = $configuredId
        Set-ProdicloudResolvedSubscriptionContext -SubscriptionId $configuredId -SubscriptionName $subscriptionName -TenantId $tenantId -ResolutionSource 'prodicloud.env'
        $script:ProdicloudUiSubscriptionError = ''
    }
    else {
        $script:ProdicloudUiSubscription = $null
        $script:ProdicloudUiSubscriptionError = 'No valid SELECTED_AZURE_SUBSCRIPTION_ID is configured.'
        Clear-ProdicloudResolvedSubscriptionContext
        try {
            Write-ProdicloudActionProgress -Action 'resolve the Azure CLI active subscription'
            $accountJson = Invoke-ProdicloudWithBypassedAzCliSubscription -Action {
                az account show -o json --only-show-errors 2>$null
            }
            if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace([string]$accountJson)) {
                $activeAccount = ConvertFrom-JsonCompat -InputObject ([string]$accountJson)
                $activeId = [string]$activeAccount.id
                if (Test-ProdicloudSubscriptionIdFormat -SubscriptionId $activeId) {
                    $script:ProdicloudUiSubscription = [pscustomobject]@{
                        SubscriptionId = $activeId
                        SubscriptionName = [string]$activeAccount.name
                        TenantId = [string]$activeAccount.tenantId
                        ResolutionSource = 'active'
                    }
                    if ($null -eq $script:ConfigOverrides) { $script:ConfigOverrides = @{} }
                    $script:ConfigOverrides['SELECTED_AZURE_SUBSCRIPTION_ID'] = $activeId
                    Set-ProdicloudResolvedSubscriptionContext -SubscriptionId $activeId -SubscriptionName ([string]$activeAccount.name) -TenantId ([string]$activeAccount.tenantId) -ResolutionSource 'active'
                    $script:ProdicloudUiSubscriptionError = ''
                }
            }
        }
        catch { $script:ProdicloudUiSubscriptionError = [string]$_.Exception.Message }
        finally { Set-ProdicloudUiStatusAction -Action '' }
    }

    $activeVmName = [string](Get-ConfigValue -Config $config -Key 'ACTIVE_VM_NAME' -DefaultValue '')
    $script:ProdicloudUiSelectedVmName = $activeVmName
    $script:ProdicloudUiSelectedResourceGroup = ''
    if (-not [string]::IsNullOrWhiteSpace($activeVmName)) {
        try {
            $vmEnvPath = Get-ProdicloudVmEnvPath -VmName $activeVmName -RepoRoot $script:ProdicloudUiRepoRoot
            if (Test-Path -LiteralPath $vmEnvPath -PathType Leaf) {
                $vmConfig = Read-DotEnvFile -Path $vmEnvPath -GlobalOnly
                if ([string]::Equals([string](Get-ConfigValue -Config $vmConfig -Key 'SELECTED_VM_NAME' -DefaultValue ''),$activeVmName,[System.StringComparison]::OrdinalIgnoreCase)) {
                    $script:ProdicloudUiSelectedResourceGroup = [string](Get-ConfigValue -Config $vmConfig -Key 'SELECTED_RESOURCE_GROUP' -DefaultValue '')
                }
            }
        }
        catch { $script:ProdicloudUiSelectedResourceGroup = '' }
    }

    $script:ProdicloudUiSubscriptionValidatedAtUtc = [DateTime]::UtcNow
    $currentSubscriptionId = if ($null -ne $script:ProdicloudUiSubscription) { [string]$script:ProdicloudUiSubscription.SubscriptionId } else { '' }
    if (-not [string]::Equals($previousSubscriptionId, $currentSubscriptionId, [System.StringComparison]::OrdinalIgnoreCase)) {
        Reset-ProdicloudUiResourceCache -Reason 'subscription changed'
    }
}

function Reset-ProdicloudUiResourceCache {
    param([string]$Reason = 'explicit refresh')

    $script:ProdicloudUiInventoryCache = $null
    $script:ProdicloudUiAzureReadCache = @{}
    $script:ProdicloudUiInventoryCacheFilePath = ''
    $script:ProdicloudUiInventoryCacheFileLastWriteUtc = [DateTime]::MinValue
}

function Test-ProdicloudUiBackgroundCacheWorkerDisabled {
    return ([string]$env:PRODICLOUD_TUI_DISABLE_BACKGROUND_CACHE_WORKER).Trim().ToLowerInvariant() -in @('1','true','yes','on')
}

function Get-ProdicloudUiInventoryCachePaths {
    param([string]$SubscriptionId)

    $root = [string]$env:PRODICLOUD_TUI_CACHE_ROOT
    if ([string]::IsNullOrWhiteSpace($root)) { $root = [string]$env:LOCALAPPDATA }
    if ([string]::IsNullOrWhiteSpace($root)) { $root = [System.IO.Path]::GetTempPath() }
    $cacheRoot = Join-Path $root 'Prodicloud\cache'
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

function ConvertTo-ProdicloudUiUtcDateTime {
    param([Parameter(Mandatory = $true)][object]$Value)

    if ($Value -is [DateTime]) { return ([DateTime]$Value).ToUniversalTime() }
    return [DateTime]::Parse([string]$Value,[System.Globalization.CultureInfo]::InvariantCulture,[System.Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
}

function Import-ProdicloudUiInventoryCacheFromDisk {
    param([switch]$Force)

    if ($null -eq $script:ProdicloudUiSubscription) { return $script:ProdicloudUiInventoryCache }
    $subscriptionId = [string]$script:ProdicloudUiSubscription.SubscriptionId
    $paths = Get-ProdicloudUiInventoryCachePaths -SubscriptionId $subscriptionId
    if (-not (Test-Path -LiteralPath $paths.Cache -PathType Leaf)) { return $script:ProdicloudUiInventoryCache }
    try {
        $file = Get-Item -LiteralPath $paths.Cache -ErrorAction Stop
        if (-not $Force -and [string]::Equals([string]$script:ProdicloudUiInventoryCacheFilePath,[string]$paths.Cache,[System.StringComparison]::OrdinalIgnoreCase) -and $file.LastWriteTimeUtc -eq $script:ProdicloudUiInventoryCacheFileLastWriteUtc) {
            return $script:ProdicloudUiInventoryCache
        }
        $loaded = ConvertFrom-JsonCompat -InputObject ([string](Get-Content -LiteralPath $paths.Cache -Raw -ErrorAction Stop))
        if ($null -eq $loaded -or -not [string]::Equals([string]$loaded.SubscriptionId,$subscriptionId,[System.StringComparison]::OrdinalIgnoreCase)) { return $null }
        $validatedAt = ConvertTo-ProdicloudUiUtcDateTime -Value $loaded.LastValidatedAtUtc
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
        if ($snapshotAge -gt [int]$script:ProdicloudUiInventoryMaximumStaleSeconds) {
            if ($null -ne $script:ProdicloudUiInventoryCache -and [string]::Equals([string]$script:ProdicloudUiInventoryCache.SubscriptionId,$subscriptionId,[System.StringComparison]::OrdinalIgnoreCase)) {
                $script:ProdicloudUiInventoryCache.IsDirty = $true
                $script:ProdicloudUiInventoryCache.DirtyReason = 'cached inventory exceeded its maximum age'
                if ($null -eq $script:ProdicloudUiInventoryCache.PSObject.Properties['DirtySinceUtc']) {
                    $script:ProdicloudUiInventoryCache | Add-Member -NotePropertyName 'DirtySinceUtc' -NotePropertyValue ([DateTime]::UtcNow)
                }
                else { $script:ProdicloudUiInventoryCache.DirtySinceUtc = [DateTime]::UtcNow }
            }
            return $script:ProdicloudUiInventoryCache
        }
        if ($null -ne $script:ProdicloudUiInventoryCache -and [bool]$script:ProdicloudUiInventoryCache.IsDirty) {
            $dirtySince = if ($null -ne $script:ProdicloudUiInventoryCache.DirtySinceUtc) { [DateTime]$script:ProdicloudUiInventoryCache.DirtySinceUtc } else { [DateTime]::MinValue }
            if ($validatedAt -le $dirtySince) { return $script:ProdicloudUiInventoryCache }
        }
        if ($null -eq $script:ProdicloudUiInventoryCache -or $validatedAt -ge [DateTime]$script:ProdicloudUiInventoryCache.LastValidatedAtUtc -or [bool]$script:ProdicloudUiInventoryCache.IsDirty) {
            $script:ProdicloudUiInventoryCache = $loaded
            $script:ProdicloudUiInventoryCache.LastValidatedAtUtc = $validatedAt
            if ($null -eq $script:ProdicloudUiInventoryCache.IsDirty) { $script:ProdicloudUiInventoryCache.IsDirty = $false }
            if ($null -eq $script:ProdicloudUiInventoryCache.PSObject.Properties['DirtySinceUtc']) {
                $script:ProdicloudUiInventoryCache | Add-Member -NotePropertyName 'DirtySinceUtc' -NotePropertyValue ([DateTime]::MinValue)
            }
            elseif ($null -eq $script:ProdicloudUiInventoryCache.DirtySinceUtc) { $script:ProdicloudUiInventoryCache.DirtySinceUtc = [DateTime]::MinValue }
        }
        $script:ProdicloudUiInventoryCacheFilePath = [string]$paths.Cache
        $script:ProdicloudUiInventoryCacheFileLastWriteUtc = [DateTime]$file.LastWriteTimeUtc
        return $script:ProdicloudUiInventoryCache
    }
    catch {
        $script:ProdicloudUiResourceCacheError = ('Cached inventory could not be read: {0}' -f [string]$_.Exception.Message)
        return $script:ProdicloudUiInventoryCache
    }
}

function Get-ProdicloudUiBackgroundCacheStatus {
    if ($null -eq $script:ProdicloudUiSubscription) { return $null }
    $paths = Get-ProdicloudUiInventoryCachePaths -SubscriptionId ([string]$script:ProdicloudUiSubscription.SubscriptionId)
    if (-not (Test-Path -LiteralPath $paths.Status -PathType Leaf)) { return $null }
    try { return (ConvertFrom-JsonCompat -InputObject ([string](Get-Content -LiteralPath $paths.Status -Raw -ErrorAction Stop))) }
    catch { return $null }
}

function Request-ProdicloudUiInventoryRefresh {
    param([switch]$Force)

    if ($null -eq $script:ProdicloudUiSubscription) { return $false }
    if (Test-ProdicloudUiBackgroundCacheWorkerDisabled) {
        Sync-ProdicloudUiResourceCache -Force:$Force | Out-Null
        return $true
    }
    $paths = Get-ProdicloudUiInventoryCachePaths -SubscriptionId ([string]$script:ProdicloudUiSubscription.SubscriptionId)
    if (-not (Test-Path -LiteralPath $paths.Root -PathType Container)) { New-Item -ItemType Directory -Path $paths.Root -Force | Out-Null }
    $writeRequest = $Force -or -not (Test-Path -LiteralPath $paths.Request -PathType Leaf)
    if (-not $writeRequest) {
        try {
            $pendingAt = [DateTime]::Parse([string](Get-Content -LiteralPath $paths.Request -Raw -ErrorAction Stop),[System.Globalization.CultureInfo]::InvariantCulture,[System.Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
            $writeRequest = (([DateTime]::UtcNow - $pendingAt).TotalSeconds -gt [int]$script:ProdicloudUiInventoryMaximumStaleSeconds)
        }
        catch { $writeRequest = $true }
    }
    if ($writeRequest) {
        $temporaryPath = '{0}.{1}.tmp' -f $paths.Request,$PID
        Set-Content -LiteralPath $temporaryPath -Value ([DateTime]::UtcNow.ToString('o')) -Encoding ASCII
        Move-Item -LiteralPath $temporaryPath -Destination $paths.Request -Force
    }
    Start-ProdicloudUiBackgroundCacheWorker | Out-Null
    return $true
}

function Start-ProdicloudUiBackgroundCacheWorker {
    if (Test-ProdicloudUiBackgroundCacheWorkerDisabled) { return $false }
    if ($null -eq $script:ProdicloudUiSubscription -or [string]::IsNullOrWhiteSpace([string]$script:ProdicloudUiSubscription.SubscriptionId)) { return $false }
    $subscriptionId = [string]$script:ProdicloudUiSubscription.SubscriptionId
    if ($null -ne $script:ProdicloudUiCacheWorkerProcess -and [string]::Equals([string]$script:ProdicloudUiCacheWorkerSubscriptionId,$subscriptionId,[System.StringComparison]::OrdinalIgnoreCase)) {
        try { if (-not $script:ProdicloudUiCacheWorkerProcess.HasExited) { return $true } } catch { }
    }

    $paths = Get-ProdicloudUiInventoryCachePaths -SubscriptionId $subscriptionId
    if (-not (Test-Path -LiteralPath $paths.Root -PathType Container)) { New-Item -ItemType Directory -Path $paths.Root -Force | Out-Null }
    if ($null -ne $script:ProdicloudUiCacheWorkerProcess -and -not [string]::IsNullOrWhiteSpace([string]$script:ProdicloudUiCacheWorkerStopPath)) {
        try { Set-Content -LiteralPath $script:ProdicloudUiCacheWorkerStopPath -Value 'stop' -Encoding ASCII } catch { }
        try {
            if (-not $script:ProdicloudUiCacheWorkerProcess.HasExited -and -not $script:ProdicloudUiCacheWorkerProcess.WaitForExit(500)) {
                Stop-Process -Id $script:ProdicloudUiCacheWorkerProcess.Id -Force -ErrorAction SilentlyContinue
                [void]$script:ProdicloudUiCacheWorkerProcess.WaitForExit(500)
            }
        }
        catch { }
        try { $script:ProdicloudUiCacheWorkerProcess.Dispose() } catch { }
    }
    if (Test-Path -LiteralPath $paths.Stop) { Remove-Item -LiteralPath $paths.Stop -Force -ErrorAction SilentlyContinue }

    $workerPath = Join-Path $script:ProdicloudUiRepoRoot 'scripts\prodicloud-cache-worker.ps1'
    if (-not (Test-Path -LiteralPath $workerPath -PathType Leaf)) {
        $script:ProdicloudUiResourceCacheError = ('Background cache worker was not found: {0}' -f $workerPath)
        return $false
    }
    $hostName = if ([string]$PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' }
    $hostCommand = Get-Command $hostName -ErrorAction SilentlyContinue
    if ($null -eq $hostCommand) {
        $script:ProdicloudUiResourceCacheError = ('Background cache worker host is unavailable: {0}' -f $hostName)
        return $false
    }
    $arguments = @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$workerPath,'-SubscriptionId',$subscriptionId,'-CachePath',$paths.Cache,'-StatusPath',$paths.Status,'-RequestPath',$paths.Request,'-PackageRequestPath',$paths.PackageRequest,'-StopPath',$paths.Stop,'-OwnerProcessId',[string]$PID,'-RepositoryRoot',$script:ProdicloudUiRepoRoot,'-RefreshIntervalSeconds',[string]$script:ProdicloudUiInventoryValidationSeconds)
    $argumentText = (@($arguments | ForEach-Object { Convert-ProdicloudProcessArgument -Value ([string]$_) }) -join ' ')
    try {
        $script:ProdicloudUiCacheWorkerProcess = Start-Process -FilePath $hostCommand.Source -ArgumentList $argumentText -WorkingDirectory ([System.IO.Path]::GetTempPath()) -WindowStyle Hidden -PassThru -ErrorAction Stop
        $script:ProdicloudUiCacheWorkerSubscriptionId = $subscriptionId
        $script:ProdicloudUiCacheWorkerStopPath = [string]$paths.Stop
        return $true
    }
    catch {
        $script:ProdicloudUiResourceCacheError = ('Background inventory worker could not start: {0}' -f [string]$_.Exception.Message)
        return $false
    }
}

function Stop-ProdicloudUiBackgroundCacheWorker {
    if ($null -eq $script:ProdicloudUiCacheWorkerProcess -or [string]::IsNullOrWhiteSpace([string]$script:ProdicloudUiCacheWorkerStopPath)) { return }
    try { Set-Content -LiteralPath $script:ProdicloudUiCacheWorkerStopPath -Value 'stop' -Encoding ASCII } catch { }
    try {
        if (-not $script:ProdicloudUiCacheWorkerProcess.HasExited -and -not $script:ProdicloudUiCacheWorkerProcess.WaitForExit(1000)) {
            Stop-Process -Id $script:ProdicloudUiCacheWorkerProcess.Id -Force -ErrorAction SilentlyContinue
            [void]$script:ProdicloudUiCacheWorkerProcess.WaitForExit(500)
        }
    }
    catch { }
    try { $script:ProdicloudUiCacheWorkerProcess.Dispose() } catch { }
    $script:ProdicloudUiCacheWorkerProcess = $null
}

function Request-ProdicloudUiPackageStatusRefresh {
    param(
        [psobject]$Vm,
        [string[]]$Catalogs = @('builtin'),
        [switch]$Force
    )

    if ($null -eq $Vm -or (Test-ProdicloudUiBackgroundCacheWorkerDisabled)) { return $false }
    $platform = if ([string]::Equals([string]$Vm.storageProfile.osDisk.osType,'Windows',[System.StringComparison]::OrdinalIgnoreCase)) { 'windows' } else { 'linux' }
    $options = New-ProdicloudUiTargetOptions -Vm $Vm
    $staleCatalogs = @()
    foreach ($catalog in @($Catalogs | Select-Object -Unique)) {
        $packages = if ([string]::Equals([string]$catalog,[string]$Catalogs[0],[System.StringComparison]::OrdinalIgnoreCase)) { @($statusRuntime) } else { @(Get-ProdicloudPackageCatalog -Platform $platform -Catalog ([string]$catalog)) }
        if (@($packages).Count -eq 0) { continue }
        $entry = Get-ProdicloudPackageStatusCacheEntry -Packages $packages -Options $options -Platform $platform
        if ($Force -or $null -eq $entry -or -not [bool]$entry.IsFresh) { $staleCatalogs += [string]$catalog }
    }
    if (@($staleCatalogs).Count -eq 0) { return $false }
    $subscriptionId = [string]$script:ProdicloudUiSubscription.SubscriptionId
    $paths = Get-ProdicloudUiInventoryCachePaths -SubscriptionId $subscriptionId
    if (-not (Test-Path -LiteralPath $paths.Root -PathType Container)) { New-Item -ItemType Directory -Path $paths.Root -Force | Out-Null }
    $request = [ordered]@{
        SubscriptionId = $subscriptionId
        ResourceGroup = [string]$Vm.ProdicloudResourceGroup
        VmName = [string]$Vm.name
        Platform = $platform
        Catalogs = @($staleCatalogs)
        RequestedAtUtc = [DateTime]::UtcNow.ToString('o')
    }
    $temporaryPath = '{0}.{1}.tmp' -f $paths.PackageRequest,$PID
    Set-Content -LiteralPath $temporaryPath -Value (ConvertTo-Json -InputObject $request -Depth 10 -Compress) -Encoding UTF8
    Move-Item -LiteralPath $temporaryPath -Destination $paths.PackageRequest -Force
    return (Start-ProdicloudUiBackgroundCacheWorker)
}

function Invalidate-ProdicloudUiResourceCache {
    param(
        [string]$Reason = 'resource mutation',
        [string]$ResourceGroup = ''
    )

    if ($null -eq $script:ProdicloudUiInventoryCache) { return }
    $script:ProdicloudUiInventoryCache.IsDirty = $true
    $script:ProdicloudUiInventoryCache.DirtyReason = [string]$Reason
    $script:ProdicloudUiInventoryCache.DirtySinceUtc = [DateTime]::UtcNow
    if (-not [string]::IsNullOrWhiteSpace([string]$ResourceGroup)) {
        $script:ProdicloudUiInventoryCache.DirtyResourceGroup = [string]$ResourceGroup
    }
    $script:ProdicloudUiAzureReadCache = @{}
    Request-ProdicloudUiInventoryRefresh -Force | Out-Null
}

function Get-ProdicloudUiManagedTagValue {
    param([psobject]$ResourceGroup)

    if ($null -eq $ResourceGroup -or $null -eq $ResourceGroup.tags) { return '' }
    $tag = @($ResourceGroup.tags.PSObject.Properties | Where-Object { [string]::Equals([string]$_.Name, 'managed-by', [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
    if (@($tag).Count -eq 0) { return '' }
    return [string]$tag[0].Value
}

function Get-ProdicloudUiResourceGroupNameFromResource {
    param([psobject]$Resource)

    if (-not [string]::IsNullOrWhiteSpace([string]$Resource.resourceGroup)) { return [string]$Resource.resourceGroup }
    $resourceId = [string]$Resource.id
    if ($resourceId -match '(?i)/resourceGroups/([^/]+)') { return [string]$Matches[1] }
    return ''
}

function Get-ProdicloudUiInventorySignature {
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
        $resourceGroup = Get-ProdicloudUiResourceGroupNameFromResource -Resource $resource
        $resourceState = [string]$resource.properties.provisioningState
        $resourceEtag = [string]$resource.etag
        $fallback = if ([string]::IsNullOrWhiteSpace([string]$resourceEtag)) { ConvertTo-Json -InputObject $resource -Depth 100 -Compress } else { '' }
        $signatureLines.Add(('resource|{0}|{1}|{2}|{3}|{4}|{5}' -f [string]$resource.id, [string]$resource.type, [string]$resourceEtag, $resourceGroup, $resourceState, $fallback))
    }
    foreach ($vm in @(ConvertTo-ObjectArrayCompat -InputObject $VirtualMachines | Sort-Object { [string]$_.id })) {
        $vmGroup = Get-ProdicloudUiResourceGroupNameFromResource -Resource $vm
        $vmEtag = [string]$vm.etag
        $vmFallback = if ([string]::IsNullOrWhiteSpace($vmEtag)) { ConvertTo-Json -InputObject $vm -Depth 100 -Compress } else { '' }
        $signatureLines.Add(('vm|{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}|{9}' -f [string]$vm.id, $vmEtag, $vmGroup, [string]$vm.hardwareProfile.vmSize, [string]$vm.powerState, [string]$vm.provisioningState, [string]$vm.privateIps, [string]$vm.publicIps, [string]$vm.fqdns, $vmFallback))
    }

    $payload = [System.Text.Encoding]::UTF8.GetBytes(($signatureLines.ToArray() -join "`n"))
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($payload))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Sync-ProdicloudUiResourceCache {
    param([switch]$Force)

    $subscriptionId = if ($null -ne $script:ProdicloudUiSubscription) { [string]$script:ProdicloudUiSubscription.SubscriptionId } else { '' }
    if ([string]::IsNullOrWhiteSpace([string]$subscriptionId)) {
        throw "Azure CLI sign-in is required to cache managed resources. Run 'az login' and retry."
    }

    if (-not $Force -and $null -ne $script:ProdicloudUiInventoryCache) {
        $sameSubscription = [string]::Equals([string]$script:ProdicloudUiInventoryCache.SubscriptionId, $subscriptionId, [System.StringComparison]::OrdinalIgnoreCase)
        $cacheAge = ([DateTime]::UtcNow - [DateTime]$script:ProdicloudUiInventoryCache.LastValidatedAtUtc).TotalSeconds
        if ($sameSubscription -and -not [bool]$script:ProdicloudUiInventoryCache.IsDirty -and $cacheAge -lt [int]$script:ProdicloudUiInventoryValidationSeconds) {
            return $script:ProdicloudUiInventoryCache
        }
    }

    $groupRows = @(ConvertTo-ObjectArrayCompat -InputObject (Invoke-ProdicloudUiAzJson -Arguments @('group','list') -ForceRefresh))
    $managedGroups = @($groupRows | Where-Object {
        $tagValue = Get-ProdicloudUiManagedTagValue -ResourceGroup $_
        [string]::Equals($tagValue, 'prodicloud', [System.StringComparison]::OrdinalIgnoreCase) -or
        [string]::Equals($tagValue, 'prodicloud', [System.StringComparison]::OrdinalIgnoreCase)
    } | Sort-Object { [string]$_.name })
    $managedGroupMap = @{}
    foreach ($group in @($managedGroups)) { $managedGroupMap[[string]$group.name.ToLowerInvariant()] = $group }

    $managedResources = @()
    foreach ($group in @($managedGroups)) {
        $groupName = [string]$group.name
        $groupResources = @(ConvertTo-ObjectArrayCompat -InputObject (Invoke-ProdicloudUiAzJson -Arguments @('resource','list','--resource-group',$groupName) -ForceRefresh))
        $managedResources += @($groupResources | Where-Object {
            $resourceGroupName = Get-ProdicloudUiResourceGroupNameFromResource -Resource $_
            [string]::IsNullOrWhiteSpace([string]$resourceGroupName) -or [string]::Equals([string]$resourceGroupName, $groupName, [System.StringComparison]::OrdinalIgnoreCase)
        })
    }
    $managedResources = @($managedResources | Sort-Object { [string]$_.id })

    $allVms = @()
    if (@($managedGroups).Count -gt 0) {
        $allVms = @(ConvertTo-ObjectArrayCompat -InputObject (Invoke-ProdicloudUiAzJson -Arguments @('vm','list','--show-details') -ForceRefresh))
    }
    $managedVms = @($allVms | Where-Object {
        $groupName = Get-ProdicloudUiResourceGroupNameFromResource -Resource $_
        -not [string]::IsNullOrWhiteSpace([string]$groupName) -and $managedGroupMap.ContainsKey([string]$groupName.ToLowerInvariant())
    } | Sort-Object { [string]$_.name }, { Get-ProdicloudUiResourceGroupNameFromResource -Resource $_ })
    foreach ($vm in @($managedVms)) {
        $groupName = Get-ProdicloudUiResourceGroupNameFromResource -Resource $vm
        $vm | Add-Member -NotePropertyName 'ProdicloudResourceGroup' -NotePropertyValue $groupName -Force
        $vm | Add-Member -NotePropertyName 'ProdicloudSubscriptionId' -NotePropertyValue $subscriptionId -Force
    }

    $signature = Get-ProdicloudUiInventorySignature -Groups $managedGroups -Resources $managedResources -VirtualMachines $managedVms
    $previousSignature = if ($null -ne $script:ProdicloudUiInventoryCache -and [string]::Equals([string]$script:ProdicloudUiInventoryCache.SubscriptionId, $subscriptionId, [System.StringComparison]::OrdinalIgnoreCase)) { [string]$script:ProdicloudUiInventoryCache.Signature } else { '' }
    $snapshotChanged = -not [string]::Equals($previousSignature, $signature, [System.StringComparison]::Ordinal)
    if (-not $snapshotChanged -and $null -ne $script:ProdicloudUiInventoryCache) {
        $script:ProdicloudUiInventoryCache.LastValidatedAtUtc = [DateTime]::UtcNow
        $script:ProdicloudUiInventoryCache.IsDirty = $false
        $script:ProdicloudUiInventoryCache.DirtyReason = ''
        $script:ProdicloudUiInventoryCache.DirtyResourceGroup = ''
        $script:ProdicloudUiInventoryCache.DirtySinceUtc = [DateTime]::MinValue
        $script:ProdicloudUiInventoryCache.Changed = $false
        return $script:ProdicloudUiInventoryCache
    }
    $script:ProdicloudUiAzureReadCache = @{}

    $script:ProdicloudUiInventoryCache = @{
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
    return $script:ProdicloudUiInventoryCache
}

function Ensure-ProdicloudUiResourceCache {
    $snapshot = Import-ProdicloudUiInventoryCacheFromDisk
    if (Test-ProdicloudUiBackgroundCacheWorkerDisabled) {
        if ($null -eq $snapshot -or [bool]$snapshot.IsDirty) { return (Sync-ProdicloudUiResourceCache -Force) }
        $cacheAge = ([DateTime]::UtcNow - [DateTime]$snapshot.LastValidatedAtUtc).TotalSeconds
        if ($cacheAge -ge [int]$script:ProdicloudUiInventoryValidationSeconds) { return (Sync-ProdicloudUiResourceCache -Force) }
        return $snapshot
    }

    if ($null -eq $snapshot) {
        $workerStarted = Start-ProdicloudUiBackgroundCacheWorker
        if (-not $workerStarted -and -not [string]::IsNullOrWhiteSpace([string]$script:ProdicloudUiResourceCacheError)) { throw [string]$script:ProdicloudUiResourceCacheError }
        $status = Get-ProdicloudUiBackgroundCacheStatus
        if ($null -ne $status -and [string]$status.State -eq 'error') { throw [string]$status.Message }
        throw 'Managed inventory is warming in the background. Return to this screen or request refresh in a moment.'
    }
    if ([bool]$snapshot.IsDirty) {
        Start-ProdicloudUiBackgroundCacheWorker | Out-Null
        Request-ProdicloudUiInventoryRefresh | Out-Null
        $status = Get-ProdicloudUiBackgroundCacheStatus
        if ($null -ne $status -and [string]$status.State -eq 'error') { throw ('Managed inventory refresh failed: {0}' -f [string]$status.Message) }
        throw ('Managed inventory is revalidating after {0}. Return to this screen in a moment.' -f [string]$snapshot.DirtyReason)
    }

    $cacheAge = ([DateTime]::UtcNow - [DateTime]$snapshot.LastValidatedAtUtc).TotalSeconds
    if ($cacheAge -ge [int]$script:ProdicloudUiInventoryValidationSeconds) {
        Request-ProdicloudUiInventoryRefresh -Force | Out-Null
        if ($cacheAge -gt [int]$script:ProdicloudUiInventoryMaximumStaleSeconds) {
            throw 'Managed inventory snapshot is too old to use while its background refresh runs.'
        }
    }
    return $snapshot
}

function Get-ProdicloudUiInventorySnapshotForSharedRuntime {
    param(
        [int]$MaximumAgeSeconds = 60,
        [string]$SubscriptionId = ''
    )

    $snapshot = $script:ProdicloudUiInventoryCache
    if ($null -eq $snapshot -or [bool]$snapshot.IsDirty) { return $null }
    if (-not [string]::IsNullOrWhiteSpace([string]$SubscriptionId) -and -not [string]::Equals([string]$snapshot.SubscriptionId,[string]$SubscriptionId,[System.StringComparison]::OrdinalIgnoreCase)) { return $null }
    try {
        $age = ([DateTime]::UtcNow - [DateTime]$snapshot.LastValidatedAtUtc).TotalSeconds
        if ($age -gt [Math]::Max([int]$MaximumAgeSeconds,0)) { return $null }
    }
    catch { return $null }
    return $snapshot
}

function Get-ProdicloudUiResourcesForGroup {
    param([string]$ResourceGroup)

    $snapshot = Ensure-ProdicloudUiResourceCache
    return @($snapshot.Resources | Where-Object { [string]::Equals((Get-ProdicloudUiResourceGroupNameFromResource -Resource $_), $ResourceGroup, [System.StringComparison]::OrdinalIgnoreCase) })
}

function Get-ProdicloudUiCachedResourceById {
    param([string]$ResourceId)

    if ([string]::IsNullOrWhiteSpace([string]$ResourceId)) { return $null }
    $snapshot = Ensure-ProdicloudUiResourceCache
    $match = @($snapshot.Resources | Where-Object { [string]::Equals([string]$_.id, $ResourceId, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
    if (@($match).Count -gt 0) { return $match[0] }
    return $null
}

function Get-ProdicloudUiCachedResourcesForType {
    param(
        [string]$Type,
        [string]$ResourceGroup = ''
    )

    $snapshot = Ensure-ProdicloudUiResourceCache
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
            ([string]::IsNullOrWhiteSpace([string]$ResourceGroup) -or [string]::Equals((Get-ProdicloudUiResourceGroupNameFromResource -Resource $_), $ResourceGroup, [System.StringComparison]::OrdinalIgnoreCase))
        }
    )
}

function Get-ProdicloudUiCachedComponentRows {
    param(
        [string]$Type,
        [string]$ResourceGroup = ''
    )

    $snapshot = Ensure-ProdicloudUiResourceCache
    $rows = New-Object 'System.Collections.Generic.List[object]'
    switch ([string]$Type) {
        'group' {
            foreach ($group in @($snapshot.Groups | Where-Object { [string]::IsNullOrWhiteSpace([string]$ResourceGroup) -or [string]::Equals([string]$_.name, $ResourceGroup, [System.StringComparison]::OrdinalIgnoreCase) })) {
                $rows.Add([pscustomobject]@{ Name = [string]$group.name; Parent = ''; Id = [string]$group.id; ResourceGroup = [string]$group.name; Type = 'Microsoft.Resources/resourceGroups'; Resource = $group })
            }
        }
        'vm' {
            foreach ($vm in @($snapshot.VirtualMachines | Where-Object { [string]::IsNullOrWhiteSpace([string]$ResourceGroup) -or [string]::Equals([string]$_.ProdicloudResourceGroup, $ResourceGroup, [System.StringComparison]::OrdinalIgnoreCase) })) {
                $rows.Add([pscustomobject]@{ Name = [string]$vm.name; Parent = ''; Id = [string]$vm.id; ResourceGroup = [string]$vm.ProdicloudResourceGroup; Type = 'Microsoft.Compute/virtualMachines'; Resource = $vm })
            }
        }
        'subnet' {
            foreach ($vnet in @(Get-ProdicloudUiCachedResourcesForType -Type 'vnet' -ResourceGroup $ResourceGroup)) {
                $vnetProperties = if ($null -ne $vnet.properties) { $vnet.properties } else { $vnet }
                foreach ($subnet in @(ConvertTo-ObjectArrayCompat -InputObject $vnetProperties.subnets)) {
                    $rows.Add([pscustomobject]@{ Name = [string]$subnet.name; Parent = [string]$vnet.name; Id = [string]$subnet.id; ResourceGroup = (Get-ProdicloudUiResourceGroupNameFromResource -Resource $vnet); Type = 'Microsoft.Network/virtualNetworks/subnets'; Resource = $subnet })
                }
            }
        }
        'nsg-rule' {
            foreach ($nsg in @(Get-ProdicloudUiCachedResourcesForType -Type 'nsg' -ResourceGroup $ResourceGroup)) {
                $nsgProperties = if ($null -ne $nsg.properties) { $nsg.properties } else { $nsg }
                foreach ($rule in @(ConvertTo-ObjectArrayCompat -InputObject $nsgProperties.securityRules)) {
                    $rows.Add([pscustomobject]@{ Name = [string]$rule.name; Parent = [string]$nsg.name; Id = [string]$rule.id; ResourceGroup = (Get-ProdicloudUiResourceGroupNameFromResource -Resource $nsg); Type = 'Microsoft.Network/networkSecurityGroups/securityRules'; Resource = $rule })
                }
            }
        }
        default {
            foreach ($resource in @(Get-ProdicloudUiCachedResourcesForType -Type $Type -ResourceGroup $ResourceGroup)) {
                $rows.Add([pscustomobject]@{ Name = [string]$resource.name; Parent = ''; Id = [string]$resource.id; ResourceGroup = (Get-ProdicloudUiResourceGroupNameFromResource -Resource $resource); Type = [string]$resource.type; Resource = $resource })
            }
        }
    }
    return @($rows.ToArray() | Sort-Object { [string]$_.ResourceGroup }, { [string]$_.Parent }, { [string]$_.Name })
}

function Get-ProdicloudUiCachedInventoryRows {
    param(
        [string]$TypeName,
        [string]$ResourceGroup = ''
    )

    $snapshot = Ensure-ProdicloudUiResourceCache
    $activeGroup = [string]$script:ProdicloudUiSelectedResourceGroup
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
    $rows = @(Get-ProdicloudUiCachedComponentRows -Type $componentType -ResourceGroup $ResourceGroup)
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

function Get-ProdicloudUiAzureCliActiveSubscriptionId {
    if (-not [string]::IsNullOrWhiteSpace([string]$script:ProdicloudUiAzureCliActiveSubscriptionId) -and $script:ProdicloudUiAzureCliActiveSubscriptionValidatedAtUtc -ne [DateTime]::MinValue) {
        $activeAge = ([DateTime]::UtcNow - [DateTime]$script:ProdicloudUiAzureCliActiveSubscriptionValidatedAtUtc).TotalSeconds
        if ($activeAge -lt 15) { return [string]$script:ProdicloudUiAzureCliActiveSubscriptionId }
    }
    Write-ProdicloudActionProgress -Action 'read the active Azure subscription id'
    $activeId = Invoke-ProdicloudWithBypassedAzCliSubscription -Action {
        az account show --query id -o tsv --only-show-errors 2>$null
    }
    Set-ProdicloudUiStatusAction -Action ''
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$activeId)) {
        throw "Azure CLI could not resolve its active subscription. Run 'az login' and retry."
    }
    $script:ProdicloudUiAzureCliActiveSubscriptionId = ([string]$activeId).Trim()
    $script:ProdicloudUiAzureCliActiveSubscriptionValidatedAtUtc = [DateTime]::UtcNow
    return [string]$script:ProdicloudUiAzureCliActiveSubscriptionId
}

function Get-ProdicloudUiCloudSubscriptionRows {
    if ($null -ne $script:ProdicloudUiCloudSubscriptionRows -and $script:ProdicloudUiCloudSubscriptionRowsValidatedAtUtc -ne [DateTime]::MinValue) {
        $cacheAge = ([DateTime]::UtcNow - [DateTime]$script:ProdicloudUiCloudSubscriptionRowsValidatedAtUtc).TotalSeconds
        if ($cacheAge -lt 30) { return @($script:ProdicloudUiCloudSubscriptionRows) }
    }
    Write-ProdicloudActionProgress -Action 'refresh the Azure subscription list'
    $raw = Invoke-ProdicloudWithBypassedAzCliSubscription -Action {
        az account list --all --refresh -o json --only-show-errors 2>$null
    }
    Set-ProdicloudUiStatusAction -Action ''
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$raw)) {
        throw "Azure CLI could not refresh the subscription list. Run 'az login' and retry."
    }
    $rows = @(ConvertTo-ObjectArrayCompat -InputObject (ConvertFrom-JsonCompat -InputObject $raw) | Where-Object {
        $_ -ne $null -and -not [string]::IsNullOrWhiteSpace([string]$_.id)
    })
    $script:ProdicloudUiCloudSubscriptionRows = @($rows | Sort-Object @{ Expression = { if ([bool]$_.isDefault) { 0 } else { 1 } } }, @{ Expression = { [string]$_.name } }, @{ Expression = { [string]$_.id } })
    $script:ProdicloudUiCloudSubscriptionRowsValidatedAtUtc = [DateTime]::UtcNow
    return @($script:ProdicloudUiCloudSubscriptionRows)
}

function Set-ProdicloudUiActiveSubscription {
    param([psobject]$Subscription)

    if ($null -eq $Subscription -or [string]::IsNullOrWhiteSpace([string]$Subscription.id)) {
        throw 'Select an accessible Azure subscription first.'
    }
    if (-not [string]::Equals([string]$Subscription.state, 'Enabled', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'A disabled Azure subscription cannot be activated.'
    }

    $previousCliId = Get-ProdicloudUiAzureCliActiveSubscriptionId
    $previousContext = Get-ProdicloudResolvedSubscriptionContext
    $subscriptionId = [string]$Subscription.id
    try {
        Write-ProdicloudActionProgress -Action ('set Azure CLI active subscription to {0}' -f $subscriptionId)
        az account set --subscription $subscriptionId --only-show-errors
        Assert-LastExitCode 'az account set'
        Set-ProdicloudUiStatusAction -Action ''
    }
    catch {
        if (-not [string]::IsNullOrWhiteSpace($previousCliId)) {
            Write-ProdicloudActionProgress -Action 'restore the previous Azure CLI subscription'
            az account set --subscription $previousCliId --only-show-errors
            $null = $LASTEXITCODE
        }
        throw
    }
    if (Get-Command Reset-ProdicloudAccessibleSubscriptionRowsCache -ErrorAction SilentlyContinue) { Reset-ProdicloudAccessibleSubscriptionRowsCache }
    $script:ProdicloudUiCloudSubscriptionRows = $null
    $script:ProdicloudUiCloudSubscriptionRowsValidatedAtUtc = [DateTime]::MinValue
    $script:ProdicloudUiAzureCliActiveSubscriptionId = $subscriptionId
    $script:ProdicloudUiAzureCliActiveSubscriptionValidatedAtUtc = [DateTime]::UtcNow

    $verifiedId = Get-ProdicloudUiAzureCliActiveSubscriptionId
    if (-not [string]::Equals($verifiedId, $subscriptionId, [System.StringComparison]::OrdinalIgnoreCase)) {
        if (-not [string]::IsNullOrWhiteSpace($previousCliId)) {
            Write-ProdicloudActionProgress -Action 'restore the previous Azure CLI subscription'
            az account set --subscription $previousCliId --only-show-errors
            $null = $LASTEXITCODE
        }
        throw 'Azure CLI did not confirm the selected active subscription; the previous CLI subscription was restored.'
    }

    try {
        Save-ProdicloudSubscriptionIdToDotEnv `
            -EnvFilePath (Join-Path $script:ProdicloudUiRepoRoot 'prodicloud.env') `
            -SubscriptionId $subscriptionId
    }
    catch {
        if (-not [string]::IsNullOrWhiteSpace($previousCliId)) {
            Write-ProdicloudActionProgress -Action 'restore the previous Azure CLI subscription'
            az account set --subscription $previousCliId --only-show-errors
            $null = $LASTEXITCODE
        }
        if ($null -ne $previousContext) {
            Set-ProdicloudResolvedSubscriptionContext `
                -SubscriptionId ([string]$previousContext.SubscriptionId) `
                -SubscriptionName ([string]$previousContext.SubscriptionName) `
                -TenantId ([string]$previousContext.TenantId) `
                -ResolutionSource ([string]$previousContext.ResolutionSource)
        }
        throw
    }

    Set-ProdicloudResolvedSubscriptionContext `
        -SubscriptionId $subscriptionId `
        -SubscriptionName ([string]$Subscription.name) `
        -TenantId ([string]$Subscription.tenantId) `
        -ResolutionSource 'interactive'
    if ($null -eq $script:ConfigOverrides) { $script:ConfigOverrides = @{} }
    $script:ConfigOverrides['SELECTED_AZURE_SUBSCRIPTION_ID'] = $subscriptionId
    $script:ProdicloudUiSubscription = [pscustomobject]@{
        SubscriptionId = $subscriptionId
        SubscriptionName = [string]$Subscription.name
        TenantId = [string]$Subscription.tenantId
        ResolutionSource = 'interactive'
    }
    $script:ProdicloudUiSubscriptionValidatedAtUtc = [DateTime]::UtcNow
    Reset-ProdicloudUiResourceCache -Reason 'subscription selected'
    Write-Host ('Active Azure subscription: {0} ({1})' -f [string]$Subscription.name, $subscriptionId) -ForegroundColor Green
    Set-ProdicloudUiStatusAction -Action ''
}

function Show-ProdicloudUiCloudSubscriptions {
    while ($true) {
        Update-ProdicloudUiSubscription
        Write-ProdicloudUiHeader -Title 'Cloud subscriptions'
        try {
            $rows = @(Get-ProdicloudUiCloudSubscriptionRows)
            $selectedContext = Get-ProdicloudResolvedSubscriptionContext
            if ($null -ne $script:ProdicloudUiSubscription) {
                $selectedSubscriptionRow = @($rows | Where-Object { [string]::Equals([string]$_.id,[string]$script:ProdicloudUiSubscription.SubscriptionId,[System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
                if (@($selectedSubscriptionRow).Count -gt 0) {
                    $script:ProdicloudUiSubscription.SubscriptionName = [string]$selectedSubscriptionRow[0].name
                    $script:ProdicloudUiSubscription.TenantId = [string]$selectedSubscriptionRow[0].tenantId
                    Set-ProdicloudResolvedSubscriptionContext -SubscriptionId ([string]$selectedSubscriptionRow[0].id) -SubscriptionName ([string]$selectedSubscriptionRow[0].name) -TenantId ([string]$selectedSubscriptionRow[0].tenantId) -ResolutionSource 'prodicloud.env'
                    $selectedContext = Get-ProdicloudResolvedSubscriptionContext
                }
            }
            $activeId = Get-ProdicloudUiAzureCliActiveSubscriptionId
            $selectedName = if ($null -ne $selectedContext) { [string]$selectedContext.SubscriptionName } else { '(none)' }
            $activeRow = @($rows | Where-Object { [string]::Equals([string]$_.id, $activeId, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
            $activeName = if (@($activeRow).Count -gt 0) { [string]$activeRow[0].name } else { $activeId }
            Write-Host ('Prodicloud selected: {0}' -f $selectedName)
            Write-Host ('Azure CLI active: {0}' -f $activeName)
            $subscriptionOptions = @(
                $rows | ForEach-Object {
                    $markers = @()
                    if ($null -ne $selectedContext -and [string]::Equals([string]$_.id, [string]$selectedContext.SubscriptionId, [System.StringComparison]::OrdinalIgnoreCase)) { $markers += 'Prodicloud selected' }
                    if ([string]::Equals([string]$_.id, $activeId, [System.StringComparison]::OrdinalIgnoreCase)) { $markers += 'Azure CLI active' }
                    $markerText = if ($markers.Count -gt 0) { ' [' + ($markers -join '; ') + ']' } else { '' }
                    $enabled = [string]::Equals([string]$_.state, 'Enabled', [System.StringComparison]::OrdinalIgnoreCase)
                    $stateText = if ($enabled) { 'Enabled' } else { 'not enabled' }
                    [pscustomobject]@{ Value = [string]$_.id; Label = ('{0} ({1})' -f [string]$_.name, [string]$_.id); Detail = (($markerText.Trim() + ' ' + $stateText).Trim()); Enabled = $enabled }
                }
            )
            $selection = Select-ProdicloudNumberedOptionPage -Options $subscriptionOptions -Prompt 'Select active cloud subscription' -DefaultValue ([string]$selectedContext.SubscriptionId) -PageSize 12
            if ([string]$selection.Action -eq 'back') { if ([string]$selection.Input -eq 'q') { Stop-ProdicloudUiBackgroundCacheWorker; exit }; return }
            if ([string]$selection.Action -eq 'close') { return }
            if ([string]$selection.Action -ne 'selected') { continue }
            $selectedRow = @($rows | Where-Object { [string]::Equals([string]$_.id, [string]$selection.Value, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
            if (@($selectedRow).Count -eq 0) { continue }
            Set-ProdicloudUiActiveSubscription -Subscription $selectedRow[0]
            Wait-ProdicloudUiContinue
        }
        catch {
            Write-ProdicloudUiError -ErrorRecord $_
            Wait-ProdicloudUiContinue
            return
        }
    }
}

function Update-ProdicloudUiStatusPreference {
    $enabledText = 'false'
    try {
        $config = Read-DotEnvFile -Path (Join-Path $script:ProdicloudUiRepoRoot 'prodicloud.env') -GlobalOnly
        if ($null -ne $config -and $config.ContainsKey('TOP_STATUS_LINES')) { $enabledText = [string]$config['TOP_STATUS_LINES'] }
    }
    catch { $enabledText = 'false' }

    $enabled = $false
    if (-not [bool]::TryParse([string]$enabledText,[ref]$enabled)) { $enabled = $false }
    $script:ProdicloudUiTopStatusLinesEnabled = $enabled
    if ($enabled) { $script:ProdicloudUiStatusCallback = { param([string]$Action) Set-ProdicloudUiStatusAction -Action $Action } }
    else { $script:ProdicloudUiStatusCallback = $null }
}

function Get-ProdicloudUiStatusText {
    if (-not [string]::IsNullOrWhiteSpace([string]$script:ProdicloudUiCurrentAction)) { return [string]$script:ProdicloudUiCurrentAction }
    if (-not [string]::IsNullOrWhiteSpace([string]$script:ProdicloudUiResourceCacheError)) { return ('Cache unavailable: {0}' -f [string]$script:ProdicloudUiResourceCacheError) }
    if ($null -eq $script:ProdicloudUiSubscription) { return 'Select a cloud subscription to load managed inventory' }
    $cacheStatus = Get-ProdicloudUiBackgroundCacheStatus
    if ($null -ne $cacheStatus -and [string]$cacheStatus.State -eq 'refreshing') { return [string]$cacheStatus.Message }
    if ($null -ne $cacheStatus -and [string]$cacheStatus.State -eq 'error') { return ('Cache issue: {0}' -f [string]$cacheStatus.Message) }
    if ($null -eq $script:ProdicloudUiInventoryCache) { return 'Inventory cache is warming in the background' }
    if ([bool]$script:ProdicloudUiInventoryCache.IsDirty) { return 'Inventory cache is being revalidated' }
    try {
        $age = [int]([DateTime]::UtcNow - [DateTime]$script:ProdicloudUiInventoryCache.LastValidatedAtUtc).TotalSeconds
        if ($age -gt [int]$script:ProdicloudUiInventoryMaximumStaleSeconds) { return 'Inventory is too old; waiting for refresh' }
        if ($age -ge [int]$script:ProdicloudUiInventoryValidationSeconds) { return 'Refresh pending' }
        return 'Ready'
    }
    catch { return 'Ready' }
}

function Get-ProdicloudUiStatusLines {
    $screen = if ([string]::IsNullOrWhiteSpace([string]$script:ProdicloudUiCurrentScreen)) { 'Prodicloud' } else { [string]$script:ProdicloudUiCurrentScreen }
    $vmName = if ([string]::IsNullOrWhiteSpace([string]$script:ProdicloudUiSelectedVmName)) { '(none)' } else { [string]$script:ProdicloudUiSelectedVmName }
    $line1 = 'PRODICLOUD | {0} | VC: {1}' -f $screen,$vmName
    $subscription = if ($null -ne $script:ProdicloudUiSubscription) {
        $name = [string]$script:ProdicloudUiSubscription.SubscriptionName
        $id = [string]$script:ProdicloudUiSubscription.SubscriptionId
        if ([string]::Equals($name,$id,[System.StringComparison]::OrdinalIgnoreCase)) { 'Azure subscription: {0}' -f $id }
        else { 'Azure subscription: {0} ({1})' -f $name,$id }
    }
    else { 'Azure subscription: not signed in' }
    $line2 = 'Status: {0} | {1}' -f (Get-ProdicloudUiStatusText),$subscription
    return @($line1,$line2)
}

function Write-ProdicloudUiStatusArea {
    param([switch]$InitializeScreen)

    if (-not [bool]$script:ProdicloudUiTopStatusLinesEnabled) { return }
    $lines = @(Get-ProdicloudUiStatusLines)
    $renderWidth = 0
    if (-not [Console]::IsOutputRedirected -and -not [bool]$script:ProdicloudUiTestMode) {
        try { $renderWidth = [Math]::Max(1,[Console]::WindowWidth) } catch { $renderWidth = 120 }
    }
    # Console rewrites trigger screen-reader announcements, so redraw only on meaningful status changes.
    if (-not $InitializeScreen -and $null -ne $script:ProdicloudUiLastStatusLines -and
        [int]$script:ProdicloudUiLastStatusRenderWidth -eq $renderWidth -and
        [string]::Equals([string]$script:ProdicloudUiLastStatusLines[0],[string]$lines[0],[System.StringComparison]::Ordinal) -and
        [string]::Equals([string]$script:ProdicloudUiLastStatusLines[1],[string]$lines[1],[System.StringComparison]::Ordinal)) {
        return
    }
    if ([Console]::IsOutputRedirected -or [bool]$script:ProdicloudUiTestMode) {
        if ($InitializeScreen) {
            Write-Host $lines[0] -ForegroundColor Cyan
            Write-Host $lines[1] -ForegroundColor Gray
        }
        $script:ProdicloudUiLastStatusLines = @($lines)
        $script:ProdicloudUiLastStatusRenderWidth = $renderWidth
        return
    }

    $escape = [string][char]27
    if ($InitializeScreen) {
        $initialWidth = 120
        try { $initialWidth = [Math]::Max(1,([Console]::WindowWidth - 1)) } catch { }
        $initialLines = @($lines | ForEach-Object { $text = [string]$_; if ($text.Length -gt $initialWidth) { $text = $text.Substring(0,$initialWidth) }; $text })
        Write-Host $initialLines[0] -ForegroundColor Cyan
        Write-Host $initialLines[1] -ForegroundColor Gray
        $height = 25
        try { $height = [Math]::Max(4,[Console]::WindowHeight) } catch { }
        try {
            [Console]::Write(('{0}[3;{1}r{0}[3;1H' -f $escape,$height))
            $script:ProdicloudUiScrollRegionActive = $true
        }
        catch { $script:ProdicloudUiScrollRegionActive = $false }
        $script:ProdicloudUiLastStatusLines = @($lines)
        $script:ProdicloudUiLastStatusRenderWidth = $renderWidth
        return
    }

    $width = 120
    $cursorTop = 2
    $cursorLeft = 0
    try { $width = [Math]::Max(1,[Console]::WindowWidth); $cursorTop = [Math]::Max(2,[Console]::CursorTop); $cursorLeft = [Math]::Max(0,[Console]::CursorLeft) } catch { }
    $padded = @($lines | ForEach-Object { $text = [string]$_; if ($text.Length -gt $width) { $text = $text.Substring(0,$width) }; $text.PadRight($width) })
    try {
        [Console]::Write(('{0}[1;1H{0}[2K{1}{0}[2;1H{0}[2K{2}{0}[{3};{4}H' -f $escape,$padded[0],$padded[1],($cursorTop + 1),($cursorLeft + 1)))
        $script:ProdicloudUiLastStatusLines = @($lines)
        $script:ProdicloudUiLastStatusRenderWidth = $renderWidth
    }
    catch { }
}

function Set-ProdicloudUiStatusAction {
    param([AllowEmptyString()][string]$Action = '')
    $script:ProdicloudUiCurrentAction = ([string]$Action).Trim()
    Write-ProdicloudUiStatusArea
}

function Reset-ProdicloudUiViewport {
    if (-not [Console]::IsOutputRedirected -and -not [bool]$script:ProdicloudUiTestMode -and $script:ProdicloudUiScrollRegionActive) {
        try { [Console]::Write(([string][char]27 + '[r')) } catch { }
    }
    $script:ProdicloudUiScrollRegionActive = $false
}

function Write-ProdicloudUiHeader {
    param([string]$Title = 'Prodicloud')

    Reset-ProdicloudUiViewport
    Update-ProdicloudUiStatusPreference
    Clear-Host
    $script:ProdicloudUiCurrentScreen = if ([string]::IsNullOrWhiteSpace([string]$Title)) { 'Prodicloud' } else { [string]$Title }
    $script:ProdicloudUiCurrentAction = ''
    if ($script:ProdicloudUiTopStatusLinesEnabled) {
        Write-ProdicloudUiStatusArea -InitializeScreen
        Write-Host 'one tool for all common cloud operations' -ForegroundColor DarkCyan
    }
    else {
        Write-Host 'PRODICLOUD' -ForegroundColor Cyan
        Write-Host 'one tool for all common cloud operations' -ForegroundColor DarkCyan
        if ($null -ne $script:ProdicloudUiSubscription) {
            Write-Host ('Azure subscription: {0} ({1})' -f [string]$script:ProdicloudUiSubscription.SubscriptionName,[string]$script:ProdicloudUiSubscription.SubscriptionId) -ForegroundColor Gray
        }
        else { Write-Host 'Azure subscription: not signed in' -ForegroundColor Yellow }
        $cacheStatus = Get-ProdicloudUiBackgroundCacheStatus
        if ($null -ne $cacheStatus -and [string]$cacheStatus.State -eq 'refreshing') { Write-Host ([string]$cacheStatus.Message) -ForegroundColor DarkGray }
        elseif ($null -ne $cacheStatus -and [string]$cacheStatus.State -eq 'error') { Write-Host ('Background inventory cache: {0}' -f [string]$cacheStatus.Message) -ForegroundColor Yellow }
        if (-not [string]::IsNullOrWhiteSpace([string]$Title)) {
            Write-Host ''
            Write-Host $Title -ForegroundColor White
        }
    }
    Write-Host ''
}

function Read-ProdicloudUiChoice {
    param([string]$Prompt = 'Select an option')
    if (-not (Test-ProdicloudUiBackgroundCacheWorkerDisabled)) { Import-ProdicloudUiInventoryCacheFromDisk | Out-Null }
    return ([string](Read-Host $Prompt)).Trim()
}

function Resolve-ProdicloudUiMenuChoice {
    param([AllowEmptyString()][string]$Value,[switch]$EscapePressed)
    if ($EscapePressed -or [string]::Equals([string]$Value,'esc',[System.StringComparison]::OrdinalIgnoreCase) -or [string]::Equals([string]$Value,'escape',[System.StringComparison]::OrdinalIgnoreCase)) { return 'b' }
    return ([string]$Value).Trim()
}

function Read-ProdicloudUiMenuChoice {
    param([string]$Prompt = 'Select an option')
    if (-not (Test-ProdicloudUiBackgroundCacheWorkerDisabled)) { Import-ProdicloudUiInventoryCacheFromDisk | Out-Null }
    Write-ProdicloudUiStatusArea
    $choice = ''
    if ([Console]::IsInputRedirected) {
        $choice = Resolve-ProdicloudUiMenuChoice -Value ([string](Read-ProdicloudUiChoice -Prompt $Prompt))
    }
    else {
        Write-Host ("{0}: " -f $Prompt) -NoNewline
        $inputBuffer = New-Object System.Text.StringBuilder
        $nextStatusRefreshAt = [DateTime]::UtcNow.AddSeconds(2)
        while ($true) {
            if (-not [Console]::KeyAvailable) {
                if ([DateTime]::UtcNow -ge $nextStatusRefreshAt) {
                    if (-not (Test-ProdicloudUiBackgroundCacheWorkerDisabled)) { Import-ProdicloudUiInventoryCacheFromDisk | Out-Null }
                    Write-ProdicloudUiStatusArea
                    $nextStatusRefreshAt = [DateTime]::UtcNow.AddSeconds(2)
                }
                Start-Sleep -Milliseconds 200
                continue
            }
            $key = [Console]::ReadKey($true)
            if ($key.Key -eq [ConsoleKey]::Escape) {
                Write-Host ''
                $choice = Resolve-ProdicloudUiMenuChoice -Value '' -EscapePressed
                break
            }
            if ($key.Key -eq [ConsoleKey]::Enter) {
                Write-Host ''
                $choice = Resolve-ProdicloudUiMenuChoice -Value $inputBuffer.ToString()
                break
            }
            if ($key.Key -eq [ConsoleKey]::Backspace) {
                if ($inputBuffer.Length -gt 0) {
                    [void]$inputBuffer.Remove($inputBuffer.Length - 1,1)
                    Write-Host "`b `b" -NoNewline
                }
                continue
            }
            if (-not [char]::IsControl([char]$key.KeyChar)) {
                [void]$inputBuffer.Append([char]$key.KeyChar)
                Write-Host ([string]$key.KeyChar) -NoNewline
            }
        }
    }
    if ([string]::Equals([string]$choice,'q',[System.StringComparison]::OrdinalIgnoreCase) -and -not [bool]$script:ProdicloudUiTestMode) {
        Stop-ProdicloudUiBackgroundCacheWorker
        exit
    }
    return [string]$choice
}

function Write-ProdicloudUiNavigationFooter {
    param([switch]$IncludeClose = $true,[switch]$AtRoot)
    $items = New-Object 'System.Collections.Generic.List[string]'
    $items.Add($(if ($AtRoot) { 'b/Esc: back (no parent)' } else { 'b/Esc: back' }))
    if ($IncludeClose) { $items.Add('c: close current flow') }
    $items.Add('q: quit')
    Write-Host (@($items.ToArray()) -join ' | ') -ForegroundColor DarkGray
}

function Read-ProdicloudUiValidatedText {
    param(
        [string]$Prompt,
        [scriptblock]$Validator,
        [switch]$AllowBlank
    )

    while ($true) {
        $raw = Read-ProdicloudUiChoice -Prompt $Prompt
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

function Wait-ProdicloudUiContinue {
    Write-Host 'Press Enter to continue:' -NoNewline
    [void][Console]::ReadLine()
}

function Invoke-ProdicloudUiCommand {
    param(
        [Parameter(Mandatory = $true)][string]$CommandName,
        [hashtable]$Options = @{},
        [hashtable]$FrontendContext = @{}
    )

    $commandFailed = $false
    Set-ProdicloudUiStatusAction -Action ('Doing: {0} operation' -f $CommandName)
    try {
        $showPowerShellOutput = ($CommandName -eq 'connect' -and (Test-ProdicloudCliOptionPresent -Options $Options -Name 'powershell') -and (Test-ProdicloudCliOptionPresent -Options $Options -Name 'command'))
        if ($showPowerShellOutput) {
            $remoteResult = Invoke-ProdicloudCommandDispatcher -CommandName $CommandName -Options $Options -FrontendContext $FrontendContext
            if ($null -ne $remoteResult) {
                $remoteText = (@($remoteResult) | Out-String -Width 4096).TrimEnd()
                if (-not [string]::IsNullOrWhiteSpace([string]$remoteText)) { Write-Host $remoteText }
            }
        }
        else {
            Invoke-ProdicloudCommandDispatcher -CommandName $CommandName -Options $Options -FrontendContext $FrontendContext | Out-Null
        }
    }
    catch {
        $commandFailed = $true
        Write-ProdicloudUiError -ErrorRecord $_
    }

    $packageAction = ([string](Get-ProdicloudCliOptionText -Options $Options -Name 'action')).ToLowerInvariant()
    $packageStateMayHaveChanged = ($CommandName -eq 'package' -and $packageAction -in @('install','uninstall','setup-all') -and $commandFailed)
    if ($CommandName -in @('initialize','update')) { $packageStateMayHaveChanged = $true }
    if ($CommandName -eq 'task' -and -not (
        (Test-ProdicloudCliOptionPresent -Options $Options -Name 'list') -or
        (Test-ProdicloudCliOptionPresent -Options $Options -Name 'history') -or
        (Test-ProdicloudCliOptionPresent -Options $Options -Name 'enable') -or
        (Test-ProdicloudCliOptionPresent -Options $Options -Name 'disable')
    )) { $packageStateMayHaveChanged = $true }
    if ($packageStateMayHaveChanged -and (Get-Command Clear-ProdicloudPackageStatusCache -ErrorAction SilentlyContinue)) {
        Clear-ProdicloudPackageStatusCache
    }

    $mutatesAzureInventory = $CommandName -in @('create','initialize','update','do','component','move','resize','set','delete','task')
    if ($CommandName -eq 'do' -and [string]::Equals([string](Get-ProdicloudCliOptionText -Options $Options -Name 'vm-action'), 'status', [System.StringComparison]::OrdinalIgnoreCase)) {
        $mutatesAzureInventory = $false
    }
    if ($CommandName -eq 'component' -and (Get-ProdicloudCliOptionText -Options $Options -Name 'action') -in @('list','show')) {
        $mutatesAzureInventory = $false
    }
    if ($CommandName -eq 'task' -and (
        (Test-ProdicloudCliOptionPresent -Options $Options -Name 'list') -or
        (Test-ProdicloudCliOptionPresent -Options $Options -Name 'history') -or
        (Test-ProdicloudCliOptionPresent -Options $Options -Name 'enable') -or
        (Test-ProdicloudCliOptionPresent -Options $Options -Name 'disable')
    )) { $mutatesAzureInventory = $false }
    if ($mutatesAzureInventory) {
        # A failed Azure mutation can be partial, so invalidate after any such
        # command attempt and let the next screen reconcile against Azure.
        Invalidate-ProdicloudUiResourceCache -Reason ("TUI {0} operation" -f $CommandName) -ResourceGroup ([string](Get-ProdicloudCliOptionText -Options $Options -Name 'group'))
    }
    Set-ProdicloudUiStatusAction -Action 'Operation complete; press Enter to continue'
    Wait-ProdicloudUiContinue
    Set-ProdicloudUiStatusAction -Action ''
    Update-ProdicloudUiSubscription
}

function Show-ProdicloudUiPackageStatusResult {
    param(
        [Parameter(Mandatory = $true)][psobject]$Vm,
        [Parameter(Mandatory = $true)][psobject]$Package,
        [ValidateSet('builtin','custom')][string]$Catalog,
        [ValidateSet('windows','linux')][string]$Platform
    )

    $options = New-ProdicloudUiTargetOptions -Vm $Vm
    $options['catalog'] = $Catalog
    $options['package'] = [string]$Package.Id
    $options[$Platform] = $true

    if (Test-ProdicloudUiBackgroundCacheWorkerDisabled) {
        $commandOptions = @{ action = 'status' }
        foreach ($optionName in $options.Keys) { $commandOptions[[string]$optionName] = $options[$optionName] }
        Invoke-ProdicloudUiCommand -CommandName 'package' -Options $commandOptions
        return
    }

    Write-ProdicloudUiHeader -Title ('Package status: {0}' -f [string]$Package.DisplayName)
    Write-Host ('Catalog: [{0}] | VC: {1}' -f $Catalog,[string]$Vm.name)
    Write-Host ("Doing: refresh package status for '{0}'" -f [string]$Package.DisplayName) -ForegroundColor DarkCyan

    $requestStartedAtUtc = [DateTime]::UtcNow
    try {
        $requestQueued = Request-ProdicloudUiPackageStatusRefresh -Vm $Vm -Catalogs @($Catalog) -Force
        if (-not [bool]$requestQueued) {
            throw 'The background package status worker could not accept the refresh request.'
        }

        $packages = @(Get-ProdicloudPackageCatalog -Platform $Platform -Catalog $Catalog)
        $deadline = [DateTime]::UtcNow.AddSeconds(300)
        $nextHeartbeat = [DateTime]::UtcNow.AddSeconds(30)
        $completedEntry = $null
        while ([DateTime]::UtcNow -lt $deadline) {
            $cacheEntry = Get-ProdicloudPackageStatusCacheEntry -Packages $packages -Options $options -Platform $Platform
            if ($null -ne $cacheEntry -and
                [bool]$cacheEntry.Entry.Complete -and
                [DateTime]$cacheEntry.Entry.CreatedAtUtc -gt $requestStartedAtUtc) {
                $completedEntry = $cacheEntry.Entry
                break
            }

            $workerStatus = Get-ProdicloudUiBackgroundCacheStatus
            if ($null -ne $workerStatus -and
                [string]$workerStatus.State -eq 'error' -and
                -not [string]::IsNullOrWhiteSpace([string]$workerStatus.UpdatedAtUtc) -and
                (ConvertTo-ProdicloudUiUtcDateTime -Value $workerStatus.UpdatedAtUtc) -gt $requestStartedAtUtc) {
                throw ([string]$workerStatus.Message)
            }

            if ([DateTime]::UtcNow -ge $nextHeartbeat) {
                $elapsedSeconds = [int]([DateTime]::UtcNow - $requestStartedAtUtc).TotalSeconds
                Write-Host ("Doing: package status refresh is still running ({0}s elapsed)" -f $elapsedSeconds) -ForegroundColor DarkCyan
                $nextHeartbeat = $nextHeartbeat.AddSeconds(30)
            }
            Start-Sleep -Milliseconds 500
        }

        if ($null -eq $completedEntry) {
            $workerStatus = Get-ProdicloudUiBackgroundCacheStatus
            $workerMessage = if ($null -ne $workerStatus -and -not [string]::IsNullOrWhiteSpace([string]$workerStatus.Message)) { ' ' + [string]$workerStatus.Message } else { '' }
            Write-Host ('Package status refresh did not finish within 300 seconds.{0}' -f $workerMessage) -ForegroundColor Yellow
            return
        }

        $status = if ($completedEntry.StatusByPackage.ContainsKey([string]$Package.Id)) { [string]$completedEntry.StatusByPackage[[string]$Package.Id] } else { 'unknown' }
        Write-Host ('Package: {0}' -f [string]$Package.DisplayName)
        Write-Host ('Catalog: [{0}]' -f $Catalog)
        Write-Host ('Status: {0}' -f $status) -ForegroundColor $(if ($status -eq 'installed') { 'Green' } elseif ($status -eq 'installed-drifted') { 'Yellow' } else { 'Cyan' })
        Write-Host ('Checked: {0} UTC' -f ([DateTime]$completedEntry.CreatedAtUtc).ToUniversalTime().ToString('u')) -ForegroundColor DarkGray
    }
    catch {
        Write-ProdicloudUiError -ErrorRecord $_
    }
    finally {
        Wait-ProdicloudUiContinue
    }
}

function Invoke-ProdicloudUiAzJson {
    param(
        [string[]]$Arguments,
        [switch]$ForceRefresh,
        [int]$CacheTtlSeconds = 45
    )

    $subscriptionId = if ($null -ne $script:ProdicloudUiSubscription) { [string]$script:ProdicloudUiSubscription.SubscriptionId } else { '' }
    if ([string]::IsNullOrWhiteSpace($subscriptionId)) {
        throw "Azure CLI sign-in is required. Run 'az login' and retry."
    }
    $cacheKey = $subscriptionId.ToLowerInvariant() + '|' + (@($Arguments | ForEach-Object { ([string]$_).Trim() }) -join [char]31)
    if (-not $ForceRefresh -and $CacheTtlSeconds -gt 0 -and $script:ProdicloudUiAzureReadCache.ContainsKey($cacheKey)) {
        $cachedEntry = $script:ProdicloudUiAzureReadCache[$cacheKey]
        $cachedAge = ([DateTime]::UtcNow - [DateTime]$cachedEntry.CreatedAtUtc).TotalSeconds
        if ($cachedAge -lt $CacheTtlSeconds) { return $cachedEntry.Value }
    }
    $azArguments = @($Arguments) + @('--subscription', $subscriptionId, '-o', 'json', '--only-show-errors')
    Write-ProdicloudActionProgress -Action ('read Azure data for the TUI: az {0}' -f (@($Arguments | ForEach-Object { [string]$_ }) -join ' '))
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
        $script:ProdicloudUiAzureReadCache[$cacheKey] = @{ CreatedAtUtc = [DateTime]::UtcNow; Value = $result }
    }
    return $result
}

function Get-ProdicloudUiManagedGroups {
    param([switch]$IncludeLegacy)

    $snapshot = Ensure-ProdicloudUiResourceCache
    $groups = @($snapshot.Groups)
    if (-not $IncludeLegacy) {
        $groups = @($groups | Where-Object { [string]::Equals((Get-ProdicloudUiManagedTagValue -ResourceGroup $_), 'prodicloud', [System.StringComparison]::OrdinalIgnoreCase) })
    }
    return @($groups | Sort-Object { [string]$_.name })
}

function Invoke-ProdicloudUiLegacyTagMigration {
    param([object[]]$LegacyGroups)

    if (@($LegacyGroups).Count -eq 0) {
        return
    }
    Write-Host 'Legacy managed resource groups were found:' -ForegroundColor Yellow
    foreach ($group in @($LegacyGroups | Sort-Object { [string]$_.name })) {
        Write-Host ('  - {0}' -f [string]$group.name)
    }
    $answer = (Read-ProdicloudUiChoice 'Move these groups to the Prodicloud management tag now? Type yes or no').ToLowerInvariant()
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
                        $value = 'prodicloud'
                    }
                    $tags += ('{0}={1}' -f $key, $value)
                }
            }
            if (-not (@($tags | Where-Object { $_ -like 'managed-by=*' }).Count -gt 0)) {
                $tags += 'managed-by=prodicloud'
            }
            $subscriptionId = [string]$script:ProdicloudUiSubscription.SubscriptionId
            Write-ProdicloudActionProgress -Action ('migrate resource group management tag on {0}' -f $groupName)
            & az group update --name $groupName --subscription $subscriptionId --tags @tags -o none --only-show-errors 2>$null
            Set-ProdicloudUiStatusAction -Action ''
            if ($LASTEXITCODE -ne 0) {
                throw 'Azure rejected the resource group tag update.'
            }
            Invalidate-ProdicloudUiResourceCache -Reason 'legacy group tag migration' -ResourceGroup $groupName
            Write-Host ('Migrated management tag: {0}' -f $groupName) -ForegroundColor Green
        }
        catch {
            Write-Host ('Tag migration failed for {0}: {1}' -f $groupName, $_.Exception.Message) -ForegroundColor Red
        }
    }
}

function Get-ProdicloudUiVirtualComputers {
    $groups = @(Get-ProdicloudUiManagedGroups -IncludeLegacy)
    $legacyGroups = @($groups | Where-Object {
        $value = ''
        if ($_.tags -and $_.tags.PSObject.Properties.Match('managed-by').Count -gt 0) { $value = [string]$_.tags.'managed-by' }
        [string]::Equals($value, 'az-vm', [System.StringComparison]::OrdinalIgnoreCase)
    })
    if (@($legacyGroups).Count -gt 0) {
        Invoke-ProdicloudUiLegacyTagMigration -LegacyGroups $legacyGroups
        $groups = @(Get-ProdicloudUiManagedGroups -IncludeLegacy)
    }

    $snapshot = Ensure-ProdicloudUiResourceCache
    return @($snapshot.VirtualMachines | Sort-Object { [string]$_.name }, { [string]$_.ProdicloudResourceGroup })
}

function Get-ProdicloudUiPowerState {
    param(
        [string]$ResourceGroup,
        [string]$VmName,
        [string]$CachedPowerState = ''
    )

    if (-not [string]::IsNullOrWhiteSpace([string]$CachedPowerState)) {
        return [string]$CachedPowerState
    }

    try {
        $instance = Invoke-ProdicloudUiAzJson -Arguments @('vm', 'get-instance-view', '--resource-group', $ResourceGroup, '--name', $VmName) -CacheTtlSeconds 15

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

function Get-ProdicloudUiNestedVirtualizationGuestStatus {
    param([psobject]$Vm, [string]$PowerState)

    $resourceGroup = [string]$Vm.ProdicloudResourceGroup
    $vmName = [string]$Vm.name
    if ([string]::IsNullOrWhiteSpace($resourceGroup) -or [string]::IsNullOrWhiteSpace($vmName)) {
        return [pscustomobject]@{ Known = $false; Enabled = $false; Evidence = @(); ErrorMessage = 'VM target details are incomplete.' }
    }
    if ([string]$PowerState -notmatch '(?i)running') {
        $powerStateKnownStopped = [string]$PowerState -match '(?i)(stopped|deallocated|hibernated|stopping|deallocating)'
        $errorMessage = if ($powerStateKnownStopped) { 'Guest validation requires a running VM.' } else { 'VM power state is unknown; guest validation was not run.' }
        return [pscustomobject]@{ Known = $false; AvailableToGuest = $null; Evidence = @(); ErrorMessage = $errorMessage }
    }

    if ($null -eq $script:ProdicloudUiAzureReadCache) { $script:ProdicloudUiAzureReadCache = @{} }
    $subscriptionId = [string]$Vm.ProdicloudSubscriptionId
    $osType = if ([string]::Equals([string]$Vm.storageProfile.osDisk.osType,'Windows',[System.StringComparison]::OrdinalIgnoreCase)) { 'windows' } else { 'linux' }
    $cacheKey = ('nested-guest|{0}|{1}|{2}|{3}' -f $subscriptionId.ToLowerInvariant(),$resourceGroup.ToLowerInvariant(),$vmName.ToLowerInvariant(),$osType)
    if ($script:ProdicloudUiAzureReadCache.ContainsKey($cacheKey)) {
        $cacheEntry = $script:ProdicloudUiAzureReadCache[$cacheKey]
        $cacheAge = ([DateTime]::UtcNow - [DateTime]$cacheEntry.CreatedAtUtc).TotalSeconds
        $cacheTtl = if ([bool]$cacheEntry.Value.Known) { 45 } else { 10 }
        if ($cacheAge -lt $cacheTtl) { return $cacheEntry.Value }
    }

    $status = Get-ProdicloudNestedVirtualizationGuestValidation `
        -ResourceGroup $resourceGroup `
        -VmName $vmName `
        -OsType $osType `
        -MaxAttempts 1 `
        -RetryDelaySeconds 1 `
        -SuppressError
    if ($null -eq $status) { $status = [pscustomobject]@{ Known = $false; AvailableToGuest = $null; Evidence = @(); ErrorMessage = 'Guest validation returned no result.' } }
    $script:ProdicloudUiAzureReadCache[$cacheKey] = @{ CreatedAtUtc = [DateTime]::UtcNow; Value = $status }
    return $status
}

function Get-ProdicloudUiCachedVm {
    param([psobject]$Vm)

    if ($null -eq $Vm) { return $null }
    $snapshot = Ensure-ProdicloudUiResourceCache
    $resourceGroup = [string]$Vm.ProdicloudResourceGroup
    $vmName = [string]$Vm.name
    $match = @(
        $snapshot.VirtualMachines |
            Where-Object {
                [string]::Equals([string]$_.name, $vmName, [System.StringComparison]::OrdinalIgnoreCase) -and
                [string]::Equals([string]$_.ProdicloudResourceGroup, $resourceGroup, [System.StringComparison]::OrdinalIgnoreCase)
            } |
            Select-Object -First 1
    )
    if (@($match).Count -gt 0) { return $match[0] }
    return $null
}

function Get-ProdicloudUiVmSizeFacts {
    param([string]$Location, [string]$Size)

    try {
        $sizes = @(ConvertTo-ObjectArrayCompat -InputObject (Invoke-ProdicloudUiAzJson -Arguments @('vm', 'list-sizes', '--location', $Location)))
        $match = @($sizes | Where-Object { [string]::Equals([string]$_.name, $Size, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
        if (@($match).Count -gt 0) {
            return [pscustomobject]@{ Cores = [string]$match[0].numberOfCores; MemoryMb = [string]$match[0].memoryInMb }
        }
    }
    catch { }
    return [pscustomobject]@{ Cores = 'Unknown'; MemoryMb = 'Unknown' }
}

function Get-ProdicloudUiCachedResourceModel {
    param([psobject]$Resource)

    if ($null -eq $Resource) { return $null }
    if ($null -ne $Resource.properties) { return $Resource.properties }
    return $Resource
}

function Format-ProdicloudUiDetailValue {
    param(
        [AllowNull()][object]$Value,
        [string]$EmptyText = '(not available)'
    )

    if ($null -eq $Value) { return $EmptyText }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $EmptyText }
    return $text
}

function Get-ProdicloudUiAzureResourceIdSegment {
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

function Show-ProdicloudUiVmDetails {
    param([psobject]$Vm)

    $resourceSnapshot = Ensure-ProdicloudUiResourceCache
    $group = [string]$Vm.ProdicloudResourceGroup
    $name = [string]$Vm.name
    $full = Get-ProdicloudUiCachedVm -Vm $Vm
    $hasDetailedStorage = $null -ne $full -and $null -ne $full.storageProfile -and $null -ne $full.storageProfile.osDisk
    $hasDetailedNetwork = $null -ne $full -and $null -ne $full.networkProfile -and @((ConvertTo-ObjectArrayCompat -InputObject $full.networkProfile.networkInterfaces)).Count -gt 0
    if (-not $hasDetailedStorage -or -not $hasDetailedNetwork) {
        $full = Invoke-ProdicloudUiAzJson -Arguments @('vm', 'show', '--resource-group', $group, '--name', $name)
    }
    $sizeName = [string]$full.hardwareProfile.vmSize
    $facts = Get-ProdicloudUiVmSizeFacts -Location ([string]$full.location) -Size $sizeName
    $memoryGb = if ($facts.MemoryMb -match '^\d+$') { ('{0:N1} GB' -f ([double]$facts.MemoryMb / 1024)) } else { 'Unknown' }
    $power = Get-ProdicloudUiPowerState -ResourceGroup $group -VmName $name -CachedPowerState ([string]$full.powerState)
    $nestedStatus = Get-ProdicloudUiNestedVirtualizationGuestStatus -Vm $Vm -PowerState $power
    $envPath = Join-Path $script:ProdicloudUiRepoRoot 'prodicloud.env'
    $globalConfig = Read-DotEnvFile -Path $envPath -GlobalOnly
    $config = Merge-ProdicloudVmEnvironmentConfig -GlobalConfigMap $globalConfig -VmName $name -VmEnvRoot $script:ProdicloudUiRepoRoot -RequireProfile

    $privateAddresses = @()
    $publicAddresses = @()
    $privateAddresses = @(([string]$full.privateIps -split ',') | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $publicIpValues = @(([string]$full.publicIps -split ',') | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $publicFqdns = @(([string]$full.fqdns -split ',') | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $cachedPublicIpResources = @(Get-ProdicloudUiCachedResourcesForType -Type 'ip' -ResourceGroup $group)
    for ($ipIndex = 0; $ipIndex -lt $publicIpValues.Count; $ipIndex++) {
        $ipValue = [string]$publicIpValues[$ipIndex]
        $ipResource = @(
            $cachedPublicIpResources | Where-Object {
                $ipProperties = Get-ProdicloudUiCachedResourceModel -Resource $_
                [string]::Equals([string]$ipProperties.ipAddress, $ipValue, [System.StringComparison]::OrdinalIgnoreCase)
            } | Select-Object -First 1
        )
        $ipObject = if (@($ipResource).Count -gt 0) { $ipResource[0] } else { $null }
        $ipProperties = Get-ProdicloudUiCachedResourceModel -Resource $ipObject
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
            $nicResource = Get-ProdicloudUiCachedResourceById -ResourceId ([string]$nicReference.id)
            $nicProperties = Get-ProdicloudUiCachedResourceModel -Resource $nicResource
            foreach ($ipConfig in @(ConvertTo-ObjectArrayCompat -InputObject $nicProperties.ipConfigurations)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$ipConfig.privateIPAddress)) { $privateAddresses += [string]$ipConfig.privateIPAddress }
            }
        }
        $privateAddresses = @($privateAddresses | Select-Object -Unique)
    }
    if ($publicAddresses.Count -eq 0) {
        foreach ($nicReference in @(ConvertTo-ObjectArrayCompat -InputObject $full.networkProfile.networkInterfaces)) {
            $nicResource = Get-ProdicloudUiCachedResourceById -ResourceId ([string]$nicReference.id)
            $nicProperties = Get-ProdicloudUiCachedResourceModel -Resource $nicResource
            foreach ($ipConfig in @(ConvertTo-ObjectArrayCompat -InputObject $nicProperties.ipConfigurations)) {
                $publicIpId = [string]$ipConfig.publicIPAddress.id
                if ([string]::IsNullOrWhiteSpace($publicIpId)) { continue }
                $publicIpResource = Get-ProdicloudUiCachedResourceById -ResourceId $publicIpId
                $publicIpProperties = Get-ProdicloudUiCachedResourceModel -Resource $publicIpResource
                $publicAddresses += [pscustomobject]@{
                    Name = if ($null -ne $publicIpResource) { [string]$publicIpResource.name } else { Get-ProdicloudUiAzureResourceIdSegment -ResourceId $publicIpId -SegmentName 'publicIPAddresses' }
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

    Write-ProdicloudUiHeader -Title ('Virtual computer: {0}' -f $name)
    Write-Host 'Virtual computer:' -ForegroundColor Cyan
    Write-Host ('  Name: {0}' -f $name)
    Write-Host ('Resource group: {0}' -f $group)
    Write-Host ('Subscription: {0} ({1})' -f (Format-ProdicloudUiDetailValue -Value $script:ProdicloudUiSubscription.SubscriptionName), (Format-ProdicloudUiDetailValue -Value $Vm.ProdicloudSubscriptionId))
    Write-Host ('Resource ID: {0}' -f (Format-ProdicloudUiDetailValue -Value $full.id))
    Write-Host ('VM ID: {0}' -f (Format-ProdicloudUiDetailValue -Value $full.vmId))
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
    Write-Host ('Computer name: {0}' -f (Format-ProdicloudUiDetailValue -Value $full.osProfile.computerName))
    Write-Host ('Availability zone: {0}' -f (Format-ProdicloudUiDetailValue -Value (@($full.zones) -join ', ')))
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
            $disk = Get-ProdicloudUiCachedResourceById -ResourceId ([string]$diskReference.Id)
            if ($null -eq $disk) {
                $diskMatches = @((Get-ProdicloudUiCachedResourcesForType -Type 'disk' -ResourceGroup $diskGroup) | Where-Object { [string]::Equals([string]$_.name, $diskName, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
                if (@($diskMatches).Count -gt 0) { $disk = $diskMatches[0] }
            }
            if ($null -eq $disk) { $disk = Invoke-ProdicloudUiAzJson -Arguments @('disk', 'show', '--resource-group', $diskGroup, '--name', $diskName) }
            $diskModel = Get-ProdicloudUiCachedResourceModel -Resource $disk
            $diskDisplayName = if (-not [string]::IsNullOrWhiteSpace([string]$disk.name)) { [string]$disk.name } else { $diskName }
            $diskSku = if ($null -ne $disk.sku) { [string]$disk.sku.name } elseif ($null -ne $diskModel.sku) { [string]$diskModel.sku.name } else { [string]$diskReference.StorageType }
            $sizeGb = if (-not [string]::IsNullOrWhiteSpace([string]$diskReference.SizeGb)) { [string]$diskReference.SizeGb } else { [string]$diskModel.diskSizeGb }
            $detail = ('  {0}: {1} | {2} GB | {3} | caching {4} | create {5}' -f [string]$diskReference.Kind, $diskDisplayName, $sizeGb, $diskSku, (Format-ProdicloudUiDetailValue -Value $diskReference.Caching), (Format-ProdicloudUiDetailValue -Value $diskReference.CreateOption))
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
        $nicName = Get-ProdicloudUiAzureResourceIdSegment -ResourceId ([string]$nicReference.id) -SegmentName 'networkInterfaces'
        if ([string]::IsNullOrWhiteSpace($nicName)) { continue }
        try {
            $nicResource = Get-ProdicloudUiCachedResourceById -ResourceId ([string]$nicReference.id)
            if ($null -ne $nicResource) {
                $nic = Get-ProdicloudUiCachedResourceModel -Resource $nicResource
                $nic | Add-Member -NotePropertyName 'name' -NotePropertyValue ([string]$nicResource.name) -Force
            }
            else {
                $nicGroup = [string]$nicReference.resourceGroup
                if ([string]::IsNullOrWhiteSpace($nicGroup)) { $nicGroup = $group }
                $nic = Invoke-ProdicloudUiAzJson -Arguments @('network', 'nic', 'show', '--resource-group', $nicGroup, '--name', $nicName)
            }
            Write-Host ('  NIC: {0} | primary {1} | accelerated networking {2} | IP forwarding {3}' -f [string]$nic.name, [bool]$nic.primary, [bool]$nic.enableAcceleratedNetworking, [bool]$nic.enableIPForwarding)
            $nsgName = Get-ProdicloudUiAzureResourceIdSegment -ResourceId ([string]$nic.networkSecurityGroup.id) -SegmentName 'networkSecurityGroups'
            if (-not [string]::IsNullOrWhiteSpace($nsgName)) { Write-Host ('    Network security group: {0}' -f $nsgName) }
            foreach ($ipConfig in @(ConvertTo-ObjectArrayCompat -InputObject $nic.ipConfigurations)) {
                $vnetName = Get-ProdicloudUiAzureResourceIdSegment -ResourceId ([string]$ipConfig.subnet.id) -SegmentName 'virtualNetworks'
                $subnetName = Get-ProdicloudUiAzureResourceIdSegment -ResourceId ([string]$ipConfig.subnet.id) -SegmentName 'subnets'
                Write-Host ('    IP config {0}: private {1} ({2}) | primary {3} | VNet {4} | subnet {5}' -f [string]$ipConfig.name, (Format-ProdicloudUiDetailValue -Value $ipConfig.privateIPAddress), (Format-ProdicloudUiDetailValue -Value $ipConfig.privateIPAllocationMethod), [bool]$ipConfig.primary, (Format-ProdicloudUiDetailValue -Value $vnetName), (Format-ProdicloudUiDetailValue -Value $subnetName))
                if ($null -ne $ipConfig.publicIPAddress -and -not [string]::IsNullOrWhiteSpace([string]$ipConfig.publicIPAddress.id)) {
                    Write-Host ('      Public IP resource: {0}' -f (Get-ProdicloudUiAzureResourceIdSegment -ResourceId ([string]$ipConfig.publicIPAddress.id) -SegmentName 'publicIPAddresses'))
                }
            }
        }
        catch { Write-Host ('  NIC: {0} | details unavailable' -f $nicName) -ForegroundColor Yellow }
    }
    if ($privateAddresses.Count -gt 0) { Write-Host ('  Private IP address(es): {0}' -f ($privateAddresses -join ', ')) }
    else { Write-Host '  Private IP address(es): (none reported)' -ForegroundColor Gray }
    if ($publicAddresses.Count -gt 0) {
        foreach ($publicAddress in @($publicAddresses)) {
            Write-Host ('  Public IP: {0} | resource {1}' -f (Format-ProdicloudUiDetailValue -Value $publicAddress.IpAddress), (Format-ProdicloudUiDetailValue -Value $publicAddress.Name))
            Write-Host ('    Public DNS: {0} | DNS label: {1}' -f (Format-ProdicloudUiDetailValue -Value $publicAddress.Fqdn -EmptyText '(not configured)'), (Format-ProdicloudUiDetailValue -Value $publicAddress.DnsLabel -EmptyText '(not configured)'))
            Write-Host ('    Allocation: {0} | SKU: {1} | zone: {2}' -f (Format-ProdicloudUiDetailValue -Value $publicAddress.Allocation), (Format-ProdicloudUiDetailValue -Value $publicAddress.Sku), (Format-ProdicloudUiDetailValue -Value $publicAddress.Zone))
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
    Write-Host ('  Hibernation enabled: {0}' -f (Format-ProdicloudUiDetailValue -Value $hibernationEnabled -EmptyText 'false'))
    Write-Host ('  Nested virtualization request ({0}.env): {1}' -f $name,$nestedVirtualization)
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
    Write-Host ('  Security type: {0}' -f (Format-ProdicloudUiDetailValue -Value $securityType))
    Write-Host ('  Secure Boot: {0} | vTPM: {1}' -f $secureBoot, $vTpm)
    Write-Host ('  Boot diagnostics: {0}' -f (Format-ProdicloudUiDetailValue -Value $full.diagnosticsProfile.bootDiagnostics.enabled))
    Write-Host ('  Managed identity: {0}' -f (Format-ProdicloudUiDetailValue -Value $full.identity.type '(none)'))
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
    $sshPort = [string](Get-ConfigValue -Config $config -Key 'VM_SSH_PORT' -DefaultValue (Get-ProdicloudDefaultSshPortText))
    $rdpPort = [string](Get-ConfigValue -Config $config -Key 'VM_RDP_PORT' -DefaultValue (Get-ProdicloudDefaultRdpPortText))
    $powerShellPort = Get-ProdicloudDefaultPowerShellPortText
    $connectionHost = if ($publicAddresses.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$publicAddresses[0].Fqdn)) { [string]$publicAddresses[0].Fqdn }
    elseif ($publicAddresses.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$publicAddresses[0].IpAddress)) { [string]$publicAddresses[0].IpAddress }
    elseif ($privateAddresses.Count -gt 0) { [string]$privateAddresses[0] }
    else { '(no reachable address reported)' }
    Write-Host 'Connection and login credentials:' -ForegroundColor Cyan
    Write-Host ('  SSH endpoint: {0}:{1} | default role: manager' -f $connectionHost, $sshPort)
    Write-Host ('    manager username: {0} | password: {1}' -f (Format-ProdicloudUiDetailValue -Value $adminUser -EmptyText '(not configured)'), (Format-ProdicloudUiDetailValue -Value $adminPass -EmptyText '(not configured)'))
    Write-Host ('    assistant username: {0} | password: {1}' -f (Format-ProdicloudUiDetailValue -Value $assistantUser -EmptyText '(not configured)'), (Format-ProdicloudUiDetailValue -Value $assistantPass -EmptyText '(not configured)'))
    if ([string]::Equals([string]$full.storageProfile.osDisk.osType, 'Windows', [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Host ('  RDP endpoint: {0}:{1} | default role: manager' -f $connectionHost, $rdpPort)
        Write-Host ('    manager username: {0} | password: {1}' -f (Format-ProdicloudUiDetailValue -Value $adminUser -EmptyText '(not configured)'), (Format-ProdicloudUiDetailValue -Value $adminPass -EmptyText '(not configured)'))
        Write-Host ('    assistant username: {0} | password: {1}' -f (Format-ProdicloudUiDetailValue -Value $assistantUser -EmptyText '(not configured)'), (Format-ProdicloudUiDetailValue -Value $assistantPass -EmptyText '(not configured)'))
        Write-Host ('  PowerShell remoting endpoint: {0}:{1} | roles: manager and assistant | authentication: Negotiate' -f $connectionHost, $powerShellPort)
    }
    else { Write-Host '  RDP: not applicable to this Linux VC.' }
    Write-Host ('  Credentials and VC-specific settings are read from {0}.env; passwords are excluded from progress and operation log messages.' -f $name) -ForegroundColor Gray
    Write-Host ''

    Write-Host 'Attached resources:' -ForegroundColor Cyan
    $resources = @(Get-ProdicloudUiResourcesForGroup -ResourceGroup $group)
    foreach ($resource in @($resources | Sort-Object { [string]$_.type }, { [string]$_.name })) {
        Write-Host ('  {0} | {1} | {2}' -f [string]$resource.type, [string]$resource.name, (Format-ProdicloudUiDetailValue -Value $resource.location))
    }
}

function New-ProdicloudUiTargetOptions {
    param([psobject]$Vm)

    $options = @{
        group = [string]$Vm.ProdicloudResourceGroup
        'vm-name' = [string]$Vm.name
        'subscription-id' = [string]$Vm.ProdicloudSubscriptionId
    }
    if ([string]::Equals([string]$Vm.storageProfile.osDisk.osType, 'Windows', [System.StringComparison]::OrdinalIgnoreCase)) {
        $options['windows'] = $true
    }
    else {
        $options['linux'] = $true
    }
    return $options
}

function Show-ProdicloudUiPackageAppStateMenu {
    param(
        [psobject]$Vm,
        [psobject]$Package,
        [ValidateSet('builtin','custom')][string]$Catalog,
        [string]$Platform
    )

    Write-ProdicloudUiHeader -Title ('App-state for {0}' -f [string]$Package.DisplayName)
    Write-Host '1. Save package app-state'
    Write-Host '2. Restore package app-state'
    Write-Host 'b: back'
    $choice = (Read-ProdicloudUiMenuChoice 'App-state action').ToLowerInvariant()
    if ($choice -eq 'b' -or $choice -notin @('1','2')) { return }
    $save = $choice -eq '1'
    Write-Host 'v: virtual computer | l: local Windows host'
    $surfaceChoice = (Read-ProdicloudUiMenuChoice 'App-state source or target').ToLowerInvariant()
    $surface = switch ($surfaceChoice) { 'v' { 'vm' } 'l' { 'lm' } default { '' } }
    if ([string]::IsNullOrWhiteSpace($surface)) { return }
    if ($surface -eq 'lm' -and $Platform -ne 'windows') {
        Write-Host 'Local-machine package app-state is available only on a Windows host.' -ForegroundColor Yellow
        Wait-ProdicloudUiContinue
        return
    }

    $options = New-ProdicloudUiTargetOptions -Vm $Vm
    $options['package'] = [string]$Package.Id
    $options['package-catalog'] = $Catalog
    $options[$(if ($save) { 'save-app-state' } else { 'restore-app-state' })] = $true
    $options[$(if ($save) { 'source' } else { 'target' })] = $surface
    $options['user'] = Read-ProdicloudUiValidatedText -Prompt 'User selector (.all., .current., a username, or comma-separated usernames)' -Validator {
        param($value)
        return (Resolve-ProdicloudUiAppStateUserSelection -Value ([string]$value))
    }
    Invoke-ProdicloudUiCommand -CommandName 'task' -Options $options
}

function Show-ProdicloudUiPackageCatalogMenu {
    param([psobject]$Vm, [ValidateSet('builtin','custom')][string]$Catalog)

    $platform = if ([string]::Equals([string]$Vm.storageProfile.osDisk.osType, 'Windows', [System.StringComparison]::OrdinalIgnoreCase)) { 'windows' } else { 'linux' }
    while ($true) {
        Write-ProdicloudUiHeader -Title (('{0} package catalog on {1}' -f $Catalog, [string]$Vm.name))
        $packages = @(Get-ProdicloudPackageCatalog -Platform $platform -Catalog $Catalog)
        $statusMap = @{}
        $statusChecking = $false
        $statusIsStale = $false
        if ($packages.Count -gt 0) {
            try {
                $statusOptions = New-ProdicloudUiTargetOptions -Vm $Vm
                if (Test-ProdicloudUiBackgroundCacheWorkerDisabled) {
                    $statusMap = Get-ProdicloudPackageStatusSnapshot -Packages $packages -Options $statusOptions -Platform $platform
                }
                else {
                    $cacheEntry = Get-ProdicloudPackageStatusCacheEntry -Packages $packages -Options $statusOptions -Platform $platform
                    if ($null -ne $cacheEntry) {
                        $statusMap = $cacheEntry.Entry.StatusByPackage
                        $statusIsStale = -not [bool]$cacheEntry.IsFresh
                    }
                    if ($null -eq $cacheEntry -or $statusIsStale) {
                        Request-ProdicloudUiPackageStatusRefresh -Vm $Vm -Catalogs @($Catalog) | Out-Null
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
            $emptyChoice = (Read-ProdicloudUiMenuChoice).ToLowerInvariant()
            if ($emptyChoice -eq 'b') { return }
            if ($emptyChoice -eq 'c') { return 'close' }
            if ($emptyChoice -eq 'q') { Stop-ProdicloudUiBackgroundCacheWorker; exit }
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
        $packageSelection = Select-ProdicloudNumberedOptionPage -Options $packageOptions -Prompt ("{0} packages on {1}" -f $Catalog, $platform) -PageSize 12 -ExtraKeys @('r','c') -ExtraKeyLabels @{ r = 'refresh package status'; c = 'close catalog' }
        if ([string]$packageSelection.Action -eq 'back') { if ([string]$packageSelection.Input -eq 'q') { Stop-ProdicloudUiBackgroundCacheWorker; exit }; return }
        if ([string]$packageSelection.Action -eq 'extra' -and [string]$packageSelection.ExtraKey -eq 'c') { return 'close' }
        if ([string]$packageSelection.Action -eq 'extra' -and [string]$packageSelection.ExtraKey -eq 'r') {
            Request-ProdicloudUiPackageStatusRefresh -Vm $Vm -Catalogs @($Catalog) -Force | Out-Null
            continue
        }
        if ([string]$packageSelection.Action -ne 'selected') { continue }
        $selectedPackage = @($packages | Where-Object { [string]::Equals([string]$_.Id, [string]$packageSelection.Value, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
        if (@($selectedPackage).Count -eq 0) { continue }
        $package = $selectedPackage[0]
        Write-ProdicloudUiHeader -Title ([string]$package.DisplayName)
        Write-Host ('Catalog: [{0}]' -f $Catalog)
        if (@($package.PackageTask.PackageSpec.DependsOn).Count -gt 0) {
            Write-Host ('Package prerequisites: {0}' -f (@($package.PackageTask.PackageSpec.DependsOn) -join ', ')) -ForegroundColor Yellow
        }
        Write-Host 'e: enable package'
        Write-Host 'd: disable package'
        $uninstallUnsupported = ($null -ne $package.UninstallPolicy -and $null -ne $package.UninstallPolicy.PSObject.Properties['supported'] -and -not [bool]$package.UninstallPolicy.supported)
        if ($uninstallUnsupported) {
            Write-Host ('u: uninstall (unsupported: {0})' -f [string]$package.UninstallPolicy.reason) -ForegroundColor Yellow
        }
        else { Write-Host 'u: uninstall' }
        Write-Host 'i: install (no-op when already installed)'
        Write-Host 'r: repair installed version'
        Write-Host 'v: update to a newer vendor version'
        if ($uninstallUnsupported) { Write-Host 'x: reinstall (unavailable for this protected Windows component)' -ForegroundColor Yellow }
        else { Write-Host 'x: force uninstall and reinstall' }
        Write-Host 's: status'
        if ($null -ne $package.PackageTask.AppStateSpec) { Write-Host 'a: manage package app-state' }
        Write-ProdicloudUiNavigationFooter
        $action = (Read-ProdicloudUiMenuChoice).ToLowerInvariant()
        if ($action -eq 'b') { continue }
        if ($action -eq 'c') { return 'close' }
        if ($action -eq 'q') { Stop-ProdicloudUiBackgroundCacheWorker; exit }
        if ($action -eq 'a' -and $null -ne $package.PackageTask.AppStateSpec) {
            Show-ProdicloudUiPackageAppStateMenu -Vm $Vm -Package $package -Catalog $Catalog -Platform $platform
            continue
        }
        if ($action -notin @('e','d','u','i','r','v','x','s')) { continue }
        $packageAction = switch ($action) { 'e' { 'enable' } 'd' { 'disable' } 'u' { 'uninstall' } 'i' { 'install' } 'r' { 'repair' } 'v' { 'update' } 'x' { 'reinstall' } 's' { 'status' } default { '' } }
        if ($packageAction -eq 'status' -and -not (Test-ProdicloudUiBackgroundCacheWorkerDisabled)) {
            Show-ProdicloudUiPackageStatusResult -Vm $Vm -Package $package -Catalog $Catalog -Platform $platform
            continue
        }
        $options = @{ catalog = $Catalog; package = [string]$package.Id }
        $options[$platform] = $true
        if ($packageAction -notin @('enable','disable')) {
            $targetOptions = New-ProdicloudUiTargetOptions -Vm $Vm
            foreach ($optionName in $targetOptions.Keys) { $options[[string]$optionName] = $targetOptions[$optionName] }
        }
        if ($packageAction -in @('uninstall','reinstall')) {
            $confirmationToken = if ($packageAction -eq 'uninstall') { 'UNINSTALL' } else { 'REINSTALL' }
            $confirm = (Read-ProdicloudUiChoice ('Type {0} to {1} {2}' -f $confirmationToken,$packageAction,[string]$package.DisplayName))
            if ($confirm -cne $confirmationToken) { continue }
            $options['yes'] = $true
        }
        $commandOptions = @{ action = $packageAction }
        foreach ($optionName in $options.Keys) { $commandOptions[[string]$optionName] = $options[$optionName] }
        Invoke-ProdicloudUiCommand -CommandName 'package' -Options $commandOptions
    }
}

function Show-ProdicloudUiSetupAllPackages {
    param([psobject]$Vm)

    $platform = if ([string]::Equals([string]$Vm.storageProfile.osDisk.osType,'Windows',[System.StringComparison]::OrdinalIgnoreCase)) { 'windows' } else { 'linux' }
    $packages = @(
        @(Get-ProdicloudPackageCatalog -Platform $platform -Catalog 'builtin') +
        @(Get-ProdicloudPackageCatalog -Platform $platform -Catalog 'custom')
    )
    Write-ProdicloudUiHeader -Title ('Setup all program packages on {0}' -f [string]$Vm.name)
    if ($packages.Count -eq 0) {
        Write-Host ('No packages are registered for the {0} platform.' -f $platform) -ForegroundColor Yellow
        Wait-ProdicloudUiContinue
        return
    }
    try {
        $options = New-ProdicloudUiTargetOptions -Vm $Vm
        $plan = New-ProdicloudPackageSetupPlan -Packages $packages -Options $options -Platform $platform -WindowsFlag:($platform -eq 'windows') -LinuxFlag:($platform -eq 'linux')
    }
    catch {
        Write-ProdicloudUiError -ErrorRecord $_
        Wait-ProdicloudUiContinue
        return
    }

    Write-Host 'Review plan (enabled packages only; dependency order):' -ForegroundColor Cyan
    foreach ($row in @($plan.Rows)) {
        $package = $row.Package
        $catalogLabel = if ([string]$package.Catalog -eq 'builtin') { '[builtin]' } else { '[custom]' }
        $color = if ([string]$row.Action -eq 'install') { 'Yellow' } elseif ([string]$row.Action -eq 'repair') { 'Cyan' } elseif ([string]$row.Action -eq 'already-healthy') { 'Green' } else { 'DarkGray' }
        Write-Host ('  {0} {1} | {2} | {3}' -f $catalogLabel,[string]$package.DisplayName,[string]$row.Status,[string]$row.Reason) -ForegroundColor $color
    }
    Write-Host ''
    Write-Host 'a: apply setup plan'
    Write-ProdicloudUiNavigationFooter
    while ($true) {
        $choice = (Read-ProdicloudUiMenuChoice 'Setup action').ToLowerInvariant()
        if ($choice -in @('b','c')) { return }
        if ($choice -eq 'q') { Stop-ProdicloudUiBackgroundCacheWorker; exit }
        if ($choice -ne 'a') { continue }
        $null = Invoke-ProdicloudPackageSetupPlan -Plan $plan
        Wait-ProdicloudUiContinue
        return
    }
}

function Show-ProdicloudUiPackageMenu {
    param([psobject]$Vm)

    if (-not (Test-ProdicloudUiBackgroundCacheWorkerDisabled)) {
        Request-ProdicloudUiPackageStatusRefresh -Vm $Vm -Catalogs @('builtin','custom') | Out-Null
    }

    while ($true) {
        Write-ProdicloudUiHeader -Title ('Manage programs on {0}' -f [string]$Vm.name)
        Write-Host '1. Builtin package catalog'
        Write-Host '2. Custom package catalog'
        Write-ProdicloudUiNavigationFooter
        $choice = (Read-ProdicloudUiMenuChoice).ToLowerInvariant()
        if ($choice -in @('b','c')) { return }
        if ($choice -eq 'q') { Stop-ProdicloudUiBackgroundCacheWorker; exit }
        switch ($choice) {
            '1' { if ((Show-ProdicloudUiPackageCatalogMenu -Vm $Vm -Catalog 'builtin') -eq 'close') { return } }
            '2' { if ((Show-ProdicloudUiPackageCatalogMenu -Vm $Vm -Catalog 'custom') -eq 'close') { return } }
        }
    }
}

function Show-ProdicloudUiCachedComponentAction {
    param(
        [psobject]$Vm,
        [string]$Type,
        [ValidateSet('list','show')][string]$Action
    )

    try {
        $resourceGroup = [string]$Vm.ProdicloudResourceGroup
        $rows = @(Get-ProdicloudUiCachedComponentRows -Type $Type -ResourceGroup $resourceGroup)
        Write-ProdicloudUiHeader -Title (('{0} components in {1}' -f $Type, $resourceGroup))
        if ($rows.Count -eq 0) {
            Write-Host ('No cached {0} components were found in {1}.' -f $Type, $resourceGroup) -ForegroundColor Yellow
            Wait-ProdicloudUiContinue
            return
        }
        if ($Action -eq 'list') {
            for ($index = 0; $index -lt $rows.Count; $index++) {
                $parent = if (-not [string]::IsNullOrWhiteSpace([string]$rows[$index].Parent)) { (' | parent={0}' -f [string]$rows[$index].Parent) } else { '' }
                $location = [string]$rows[$index].Resource.location
                if ([string]::IsNullOrWhiteSpace([string]$location)) { $location = [string]$Vm.location }
                Write-Host ('{0}. {1}{2} | {3}' -f ($index + 1), [string]$rows[$index].Name, $parent, $location)
            }
            Write-Host ('Snapshot validated: {0} UTC' -f ([DateTime]$script:ProdicloudUiInventoryCache.LastValidatedAtUtc).ToString('u')) -ForegroundColor DarkGray
            Wait-ProdicloudUiContinue
            return
        }

        $pickerOptions = @(
            $rows | ForEach-Object {
                $detailText = if (-not [string]::IsNullOrWhiteSpace([string]$_.Parent)) { [string]$_.Parent } else { [string]$_.ResourceGroup }
                [pscustomobject]@{ Value = [string]$_.Id; Label = [string]$_.Name; Detail = $detailText }
            }
        )
        $selection = Select-ProdicloudNumberedOptionPage -Options $pickerOptions -Prompt ('Select {0} to show' -f $Type) -DefaultValue $(if ($rows.Count -eq 1) { [string]$rows[0].Id } else { '' })
        if ([string]$selection.Action -ne 'selected') { return }
        $selected = @($rows | Where-Object { [string]::Equals([string]$_.Id, [string]$selection.Value, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
        if (@($selected).Count -eq 0) { return }
        Write-Host ''
        Write-Host ('{0}: {1}' -f $Type, [string]$selected[0].Name) -ForegroundColor Cyan
        $resource = $selected[0].Resource
        if ($null -eq $resource) { Write-Host '(properties are not included in this resource snapshot)' -ForegroundColor Yellow }
        else { ConvertTo-Json -InputObject $resource -Depth 20 | Write-Host }
        Write-Host ('Snapshot validated: {0} UTC' -f ([DateTime]$script:ProdicloudUiInventoryCache.LastValidatedAtUtc).ToString('u')) -ForegroundColor DarkGray
        Wait-ProdicloudUiContinue
    }
    catch {
        Write-ProdicloudUiError -ErrorRecord $_
        Wait-ProdicloudUiContinue
    }
}

function Show-ProdicloudUiComponentMenu {
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
        Write-ProdicloudUiHeader -Title ('Components of {0}' -f [string]$Vm.name)
        for ($index = 0; $index -lt $types.Count; $index++) {
            Write-Host ('{0}. {1}' -f ($index + 1), [string]$types[$index].Label)
        }
        Write-Host 'b: back'
        Write-Host 'c: close component menu'
        Write-Host 'q: exit'
        $choice = (Read-ProdicloudUiMenuChoice).ToLowerInvariant()
        if ($choice -in @('b','c')) { return }
        if ($choice -eq 'q') { Stop-ProdicloudUiBackgroundCacheWorker; exit }
        $number = 0
        if (-not [int]::TryParse($choice, [ref]$number) -or $number -lt 1 -or $number -gt $types.Count) { continue }
        $type = $types[$number - 1]
        Write-ProdicloudUiHeader -Title ([string]$type.Label)
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
        $actionChoice = (Read-ProdicloudUiMenuChoice).ToLowerInvariant()
        if ($actionChoice -eq 'b') { continue }
        if ($actionChoice -eq 'q') { Stop-ProdicloudUiBackgroundCacheWorker; exit }
        if ($actionChoice -in @('a','t') -and $type.Id -in @('disk','nic')) {
            $options = New-ProdicloudUiTargetOptions -Vm $Vm
            $options['type'] = [string]$type.Id
            $options['action'] = if ($actionChoice -eq 'a') { 'attach' } else { 'detach' }
            Invoke-ProdicloudUiCommand -CommandName 'component' -Options $options
            continue
        }
        $action = switch ($actionChoice) { 'l' { 'list' } 's' { 'show' } 'c' { 'create' } 'u' { 'update' } 'd' { 'delete' } default { '' } }
        if ([string]::IsNullOrWhiteSpace($action)) { continue }
        if ($action -in @('list','show')) {
            Show-ProdicloudUiCachedComponentAction -Vm $Vm -Type ([string]$type.Id) -Action $action
            continue
        }
        $options = New-ProdicloudUiTargetOptions -Vm $Vm
        $options['type'] = [string]$type.Id
        $options['action'] = $action
        Invoke-ProdicloudUiCommand -CommandName 'component' -Options $options
    }
}

function Get-ProdicloudUiTaskRowsForStage {
    param([psobject]$Vm, [ValidateSet('init','update')][string]$Stage)

    $platform = if ([string]::Equals([string]$Vm.storageProfile.osDisk.osType, 'Windows', [System.StringComparison]::OrdinalIgnoreCase)) { 'windows' } else { 'linux' }
    $options = New-ProdicloudUiTargetOptions -Vm $Vm
    $runtime = if ($platform -eq 'windows') {
        Initialize-ProdicloudTaskCommandRuntimeContext -AutoMode:$false -WindowsFlag -Options $options
    }
    else {
        Initialize-ProdicloudTaskCommandRuntimeContext -AutoMode:$false -LinuxFlag -Options $options
    }
    $stageRoot = if ($Stage -eq 'init') { [string]$runtime.VmInitTaskDir } else { [string]$runtime.VmUpdateTaskDir }
    $catalog = Get-ProdicloudTaskBlocksFromDirectory -DirectoryPath $stageRoot -Platform $platform -Stage $Stage -SuppressSkipMessages
    return @($catalog.InventoryTasks)
}

function Select-ProdicloudUiTaskName {
    param(
        [psobject]$Vm,
        [ValidateSet('init','update')][string]$Stage,
        [switch]$EnabledOnly,
        [switch]$AllowDisabledSelection
    )

    $tasks = @(Get-ProdicloudUiTaskRowsForStage -Vm $Vm -Stage $Stage)
    if ($EnabledOnly) { $tasks = @($tasks | Where-Object { [bool]$_.Enabled }) }
    if ($tasks.Count -eq 0) {
        Write-Host 'No selectable tasks are registered for this stage.' -ForegroundColor Yellow
        Wait-ProdicloudUiContinue
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
    $selection = Select-ProdicloudNumberedOptionPage -Options $taskOptions -Prompt (('{0} tasks' -f $Stage)) -PageSize 12
    if ([string]$selection.Action -eq 'back') {
        if ([string]$selection.Input -eq 'q') { Stop-ProdicloudUiBackgroundCacheWorker; exit }
        return ''
    }
    if ([string]$selection.Action -ne 'selected') { return '' }
    return [string]$selection.Value
}

function Resolve-ProdicloudUiAppStateUserSelection {
    param([string]$Value)

    $tokens = @(Resolve-ProdicloudTaskAppStateRequestedUsers -UserOptionValue ([string]$Value))
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

function Show-ProdicloudUiTaskAvailabilityMenu {
    param([psobject]$Vm)

    $platform = if ([string]::Equals([string]$Vm.storageProfile.osDisk.osType, 'Windows', [System.StringComparison]::OrdinalIgnoreCase)) { 'windows' } else { 'linux' }

    while ($true) {
        Write-ProdicloudUiHeader -Title ('Task availability for {0}' -f [string]$Vm.name)
        Write-Host 'Task availability is shared by this repository and affects future runs on matching VMs.' -ForegroundColor Yellow
        Write-Host '1. Initialization tasks'
        Write-Host '2. Maintenance tasks'
        Write-Host 'b: back'
        Write-Host 'c: close availability screen'
        Write-Host 'q: exit'
        $stageChoice = (Read-ProdicloudUiMenuChoice 'Task stage').ToLowerInvariant()
        if ($stageChoice -in @('b','c')) { return }
        if ($stageChoice -eq 'q') { Stop-ProdicloudUiBackgroundCacheWorker; exit }
        if ($stageChoice -notin @('1','2')) { continue }

        $stage = if ($stageChoice -eq '1') { 'init' } else { 'update' }
        $tasks = @(Get-ProdicloudUiTaskRowsForStage -Vm $Vm -Stage $stage)
        if ($tasks.Count -eq 0) {
            Write-Host 'No tasks are registered for this stage.' -ForegroundColor Yellow
            Wait-ProdicloudUiContinue
            continue
        }

        $taskOptions = @($tasks | ForEach-Object {
            $state = if ([bool]$_.Enabled) { 'enabled' } else { 'disabled: ' + [string]$_.DisabledReason }
            [pscustomobject]@{ Value = [string]$_.Name; Label = ('#{0} {1}' -f [int]$_.TaskNumber, [string]$_.Name); Detail = $state; Enabled = $true }
        })
        $taskSelection = Select-ProdicloudNumberedOptionPage -Options $taskOptions -Prompt ('{0} tasks' -f $(if ($stage -eq 'init') { 'Initialization' } else { 'Maintenance' })) -PageSize 12
        if ([string]$taskSelection.Action -eq 'back') {
            if ([string]$taskSelection.Input -eq 'q') { Stop-ProdicloudUiBackgroundCacheWorker; exit }
            continue
        }
        if ([string]$taskSelection.Action -eq 'close') { return }
        if ([string]$taskSelection.Action -ne 'selected') { continue }
        $selectedTask = @($tasks | Where-Object { [string]::Equals([string]$_.Name, [string]$taskSelection.Value, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
        if (@($selectedTask).Count -eq 0) { continue }
        $selectedTask = $selectedTask[0]
        Write-ProdicloudUiHeader -Title ([string]$selectedTask.Name)
        Write-Host 'e: enable'
        Write-Host 'd: disable'
        Write-Host 'b: back'
        Write-Host 'c: close availability screen'
        Write-Host 'q: exit'
        $action = (Read-ProdicloudUiMenuChoice 'Availability action').ToLowerInvariant()
        if ($action -eq 'b') { continue }
        if ($action -eq 'c') { return }
        if ($action -eq 'q') { Stop-ProdicloudUiBackgroundCacheWorker; exit }
        if ($action -notin @('e','d')) { continue }

        $options = @{}
        $options[('vm-{0}-task' -f $stage)] = [string]$selectedTask.Name
        $options[$(if ($action -eq 'e') { 'enable' } else { 'disable' })] = $true
        $options[$platform] = $true
        Invoke-ProdicloudUiCommand -CommandName 'task' -Options $options
    }
}

function Show-ProdicloudUiTaskMenu {
    param([psobject]$Vm)

    while ($true) {
        Write-ProdicloudUiHeader -Title ('Tasks on {0}' -f [string]$Vm.name)
        Write-Host '1. List init and update tasks'
        Write-Host '2. Run one init task'
        Write-Host '3. Run one update task'
        Write-Host '4. Save task app-state'
        Write-Host '5. Restore task app-state'
        Write-Host '6. List disabled tasks'
        Write-Host '7. Enable/disable a task'
        Write-Host '8. View recent task run history'
        Write-Host 'b: back'
        Write-Host 'c: close task menu'
        Write-Host 'q: exit'
        $choice = (Read-ProdicloudUiMenuChoice).ToLowerInvariant()
        if ($choice -in @('b','c')) { return }
        if ($choice -eq 'q') { Stop-ProdicloudUiBackgroundCacheWorker; exit }
        $target = New-ProdicloudUiTargetOptions -Vm $Vm
        switch ($choice) {
            '1' { $target['list'] = $true; $target['vm-init'] = $true; $target['vm-update'] = $true; Invoke-ProdicloudUiCommand -CommandName 'task' -Options $target }
            '2' {
                $taskName = Select-ProdicloudUiTaskName -Vm $Vm -Stage 'init' -EnabledOnly
                if (-not [string]::IsNullOrWhiteSpace([string]$taskName)) { $target['run-vm-init'] = $taskName; Invoke-ProdicloudUiCommand -CommandName 'task' -Options $target }
            }
            '3' {
                $taskName = Select-ProdicloudUiTaskName -Vm $Vm -Stage 'update' -EnabledOnly
                if (-not [string]::IsNullOrWhiteSpace([string]$taskName)) { $target['run-vm-update'] = $taskName; Invoke-ProdicloudUiCommand -CommandName 'task' -Options $target }
            }
            { $_ -in @('4','5','6') } {
                if ($choice -eq '6') {
                    $target['list'] = $true
                    $target['vm-init'] = $true
                    $target['vm-update'] = $true
                    $target['disabled'] = $true
                    Invoke-ProdicloudUiCommand -CommandName 'task' -Options $target
                    break
                }
                Write-Host 'i: init | u: update'
                $stageChoice = (Read-ProdicloudUiMenuChoice 'Task stage').ToLowerInvariant()
                if ($stageChoice -in @('b','c')) { continue }
                $stage = switch ($stageChoice) { 'i' { 'init' } 'u' { 'update' } default { '' } }
                if ([string]::IsNullOrWhiteSpace($stage)) { continue }
                $taskName = Select-ProdicloudUiTaskName -Vm $Vm -Stage $stage
                if ([string]::IsNullOrWhiteSpace([string]$taskName)) { continue }
                $target[('vm-{0}-task' -f $stage)] = [string]$taskName
                $target[$(if ($choice -eq '4') { 'save-app-state' } else { 'restore-app-state' })] = $true
                Write-Host 'v: virtual computer | l: local Windows host'
                $surfaceChoice = (Read-ProdicloudUiMenuChoice 'App-state target').ToLowerInvariant()
                if ($surfaceChoice -in @('b','c')) { continue }
                $surface = switch ($surfaceChoice) { 'v' { 'vm' } 'l' { 'lm' } default { '' } }
                if ($surface -in @('vm','lm')) { $target[$(if ($choice -eq '4') { 'source' } else { 'target' })] = $surface }
                else { continue }
                $target['user'] = Read-ProdicloudUiValidatedText -Prompt 'User selector (.all., .current., a username, or comma-separated usernames)' -Validator {
                    param($value)
                    return (Resolve-ProdicloudUiAppStateUserSelection -Value ([string]$value))
                }
                Invoke-ProdicloudUiCommand -CommandName 'task' -Options $target
            }
            '7' { Show-ProdicloudUiTaskAvailabilityMenu -Vm $Vm }
            '8' { Invoke-ProdicloudUiCommand -CommandName 'task' -Options @{ history = $true } }
        }
    }
}

function Show-ProdicloudUiResizeHardwareWizard {
    param([psobject]$Vm)

    $group = [string]$Vm.ProdicloudResourceGroup
    $name = [string]$Vm.name
    Write-ProdicloudActionProgress -Action ("refresh current hardware profile for '{0}'" -f $name)
    try { $currentVm = Invoke-ProdicloudUiAzJson -Arguments @('vm','show','--resource-group',$group,'--name',$name) -ForceRefresh }
    catch { Write-ProdicloudUiError -ErrorRecord $_; Wait-ProdicloudUiContinue; return }
    $region = [string]$currentVm.location
    if ([string]::IsNullOrWhiteSpace($region)) {
        Write-ProdicloudUiError -ErrorRecord ([System.Exception]::new('The selected VC region could not be resolved.'))
        Wait-ProdicloudUiContinue
        return
    }

    $osType = [string]$currentVm.storageProfile.osDisk.osType
    $defaultSku = [string]$currentVm.hardwareProfile.vmSize

    Write-ProdicloudUiHeader -Title ('Resize VM hardware: {0}' -f [string]$Vm.name)
    Write-Host ('Region: {0} (fixed)' -f $region)
    Write-Host ('Current SKU: {0}' -f $defaultSku)
    $processorDefault = Get-ProdicloudVmSkuProcessorVendor -SkuName $defaultSku
    if ($processorDefault -notin @('Intel','AMD')) { $processorDefault = '' }
    $processorOptions = @(
        [pscustomobject]@{ Value = 'Intel'; Label = 'Intel'; Detail = 'x86-64 Intel processor families'; Enabled = $true },
        [pscustomobject]@{ Value = 'AMD'; Label = 'AMD'; Detail = 'AMD processor families'; Enabled = $true }
    )
    $processorResult = Select-ProdicloudNumberedOptionPage -Options $processorOptions -Prompt 'Processor type' -DefaultValue $processorDefault -PageSize 12
    if ([string]$processorResult.Action -ne 'selected') { return }
    $processor = [string]$processorResult.Value

    $memoryOptions = @(1,2,4,8,16,32,64,128 | ForEach-Object {
        [pscustomobject]@{ Value = [string]$_; Label = ('{0} GB' -f $_); Detail = 'Requested RAM capacity' }
    })
    $currentRam = 8.0
    try {
        $currentFacts = Get-ProdicloudUiVmSizeFacts -Location $region -Size $defaultSku
        if ($null -ne $currentFacts -and [string]$currentFacts.MemoryMb -match '^\d+$') { $currentRam = [double]$currentFacts.MemoryMb / 1024.0 }
    }
    catch { }
    $ramDefault = [string](@(1,2,4,8,16,32,64,128 | Where-Object { [double]$_ -ge $currentRam } | Select-Object -First 1))
    if ([string]::IsNullOrWhiteSpace($ramDefault)) { $ramDefault = '128' }
    $exactRam = $false
    $ram = ''
    while ($true) {
        Write-ProdicloudUiHeader -Title ('Resize VM hardware: RAM ({0})' -f $processor)
        Write-Host ('Exact RAM match: {0}' -f $(if ($exactRam) { 'on' } else { 'off; show SKU RAM at or below the selected value' }))
        $ramResult = Select-ProdicloudNumberedOptionPage -Options $memoryOptions -Prompt 'RAM capacity' -DefaultValue $ramDefault -PageSize 12 -ExtraKeys @('x') -ExtraKeyLabels @{ x = 'toggle exact RAM match' }
        if ([string]$ramResult.Action -eq 'extra' -and [string]$ramResult.ExtraKey -eq 'x') { $exactRam = -not $exactRam; continue }
        if ([string]$ramResult.Action -ne 'selected') { return }
        $ram = [string]$ramResult.Value
        break
    }

    Write-ProdicloudActionProgress -Action ("load {0} VM SKUs in {1} for RAM {2} GB" -f $processor,$region,$ram)
    try {
        $allSkus = @(Get-LocationSkusForSelection -Location $region -SkuLike '')
        $allRows = @(Build-VmSkuSelectionRows -Skus $allSkus -AvailabilityMap @{} -PriceMap @{} -PriceHours 730)
    }
    catch {
        Write-ProdicloudUiError -ErrorRecord $_
        Wait-ProdicloudUiContinue
        return
    }

    $matchingRows = @(
        $allRows | Where-Object {
            [string]::Equals([string]$_.Processor,$processor,[System.StringComparison]::OrdinalIgnoreCase) -and
            $(if ($exactRam) { [double]$_.RAM_GB -eq [double]$ram } else { [double]$_.RAM_GB -le [double]$ram })
        } | Sort-Object @{ Expression = { [string]$_.Category } }, @{ Expression = { [double]$_.RAM_GB } }, @{ Expression = { [int]$_.vCPU } }, @{ Expression = { [string]$_.Sku } }
    )
    if ($matchingRows.Count -eq 0) {
        Write-ProdicloudUiHeader -Title 'No matching VM sizes'
        Write-Host ('No {0} SKU matched RAM {1} GB ({2}) in {3}.' -f $processor,$ram,$(if ($exactRam) { 'exact' } else { 'at or below' }),$region) -ForegroundColor Yellow
        Write-Host 'b: return to RAM selection | c: close wizard'
        $retry = (Read-ProdicloudUiMenuChoice 'Next action').ToLowerInvariant()
        if ($retry -eq 'c') { return }
        if ($retry -eq 'b') { return (Show-ProdicloudUiResizeHardwareWizard -Vm $Vm) }
        return
    }

    Write-ProdicloudActionProgress -Action ("validate subscription availability for {0} matching VM SKUs" -f $matchingRows.Count)
    try { $availability = Get-SkuAvailabilityMap -Location $region -SkuNames @($matchingRows | ForEach-Object { [string]$_.Sku }) }
    catch { Write-ProdicloudUiError -ErrorRecord $_; Wait-ProdicloudUiContinue; return }
    $availableNames = @($matchingRows | Where-Object { $availability.ContainsKey([string]$_.Sku) -and [string]$availability[[string]$_.Sku] -eq 'yes' } | ForEach-Object { [string]$_.Sku })
    $availableSkus = @($allSkus | Where-Object { $availableNames -contains [string]$_.name })
    if ($availableSkus.Count -eq 0) {
        Write-ProdicloudUiHeader -Title 'No subscription-available VM sizes'
        Write-Host ('Azure has no available {0} SKUs matching RAM {1} GB in {2} for the selected subscription.' -f $processor,$ram,$region) -ForegroundColor Yellow
        Wait-ProdicloudUiContinue
        return
    }
    $configPath = Join-Path $script:ProdicloudUiRepoRoot 'prodicloud.env'
    $globalConfig = Read-DotEnvFile -Path $configPath -GlobalOnly
    $profile = Merge-ProdicloudVmEnvironmentConfig -GlobalConfigMap $globalConfig -VmName ([string]$Vm.name) -VmEnvRoot $script:ProdicloudUiRepoRoot -RequireProfile
    $priceHours = Get-PriceHoursFromConfig -Config $profile -DefaultHours 730

    $priceMap = @{}
    try {
        $priceMap = Get-SkuPriceMap -Location $region -SkuNames $availableNames
    }
    catch { Write-Host ('Price lookup unavailable; SKU selection will continue: {0}' -f $_.Exception.Message) -ForegroundColor Yellow }
    $candidates = @(Build-VmSkuSelectionRows -Skus $availableSkus -AvailabilityMap $availability -PriceMap $priceMap -PriceHours $priceHours | Where-Object {
        [string]::Equals([string]$_.Processor,$processor,[System.StringComparison]::OrdinalIgnoreCase) -and
        $(if ($exactRam) { [double]$_.RAM_GB -eq [double]$ram } else { [double]$_.RAM_GB -le [double]$ram })
    } | Sort-Object @{ Expression = { [string]$_.Category } }, @{ Expression = { [double]$_.RAM_GB } }, @{ Expression = { [int]$_.vCPU } }, @{ Expression = { [string]$_.Sku } })

    $preferredSku = if ($processor -eq 'AMD') { 'Standard_B2as_v2' } else { 'Standard_B2s_v2' }
    $defaultCandidate = @($candidates | Where-Object { [string]::Equals([string]$_.Sku,$preferredSku,[System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
    if (@($defaultCandidate).Count -eq 0) { $defaultCandidate = @($candidates | Where-Object { [string]::Equals([string]$_.Sku,$defaultSku,[System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1) }
    $candidateDefault = if (@($defaultCandidate).Count -gt 0) { [string]$defaultCandidate[0].Sku } else { '' }
    $skuOptions = @(
        $candidates | ForEach-Object {
            $linuxPriceProperty = 'Linux_{0}h' -f $priceHours
            $windowsPriceProperty = 'Windows_{0}h' -f $priceHours
            $detail = ('{0} | {1} vCPU | {2} GB RAM | temp disk {3} GB | {4} NICs | Linux {5}/mo | Windows {6}/mo' -f [string]$_.Category,[int]$_.vCPU,[double]$_.RAM_GB,[double]$_.ResourceDisk_GB,[int]$_.MaxNICs,[string]$_.$linuxPriceProperty,[string]$_.$windowsPriceProperty)
            [pscustomobject]@{ Value = [string]$_.Sku; Label = ('{0} ({1})' -f [string]$_.Sku,[string]$_.Family); Detail = $detail; Enabled = $true }
        }
    )
    $skuSelection = Select-ProdicloudNumberedOptionPage -Options $skuOptions -Prompt ('Available VM SKUs in {0} ({1}; RAM {2} GB {3})' -f $region,$processor,$ram,$(if ($exactRam) { 'exact' } else { 'at or below' })) -DefaultValue $candidateDefault -PageSize 12
    if ([string]$skuSelection.Action -ne 'selected') { return }
    $selected = @($candidates | Where-Object { [string]::Equals([string]$_.Sku,[string]$skuSelection.Value,[System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)[0]

    Write-ProdicloudUiHeader -Title 'Resize VM hardware — review'
    Write-Host ('VC: {0} | OS: {1} | Region: {2}' -f [string]$Vm.name,$osType,$region)
    Write-Host ('Current SKU: {0}' -f $defaultSku)
    Write-Host ('Target SKU: {0} | {1} | {2} vCPU | {3} GB RAM' -f [string]$selected.Sku,[string]$selected.Category,[int]$selected.vCPU,[double]$selected.RAM_GB)
    Write-Host 'Network and disks: unchanged'
    Write-Host 'VM power state: restored to its original state after verification'
    Write-Host 'a: apply resize | c: close wizard'
    $apply = (Read-ProdicloudUiMenuChoice 'Resize action').ToLowerInvariant()
    if ($apply -ne 'a') { return }
    $options = New-ProdicloudUiTargetOptions -Vm $Vm
    $options['vm-size'] = [string]$selected.Sku
    Invoke-ProdicloudUiCommand -CommandName 'resize' -Options $options
}

function Show-ProdicloudUiResizeDiskWizard {
    param([psobject]$Vm)

    $group = [string]$Vm.ProdicloudResourceGroup
    $name = [string]$Vm.name
    Write-ProdicloudUiHeader -Title ('Resize VM disk: {0}' -f $name)
    try {
        Write-ProdicloudActionProgress -Action ("read attached disks for '{0}'" -f $name)
        $fullVm = Invoke-ProdicloudUiAzJson -Arguments @('vm','show','--resource-group',$group,'--name',$name) -ForceRefresh
        $diskOptions = @()
        $osDisk = $fullVm.storageProfile.osDisk
        if ($null -ne $osDisk) {
            $diskOptions += [pscustomobject]@{ Value = [string]$osDisk.name; Label = ('OS disk: {0}' -f [string]$osDisk.name); Detail = ('{0} GB | {1}' -f [string]$osDisk.diskSizeGb,[string]$osDisk.managedDisk.storageAccountType); Enabled = $true }
        }
        foreach ($disk in @(ConvertTo-ObjectArrayCompat -InputObject $fullVm.storageProfile.dataDisks)) {
            $diskOptions += [pscustomobject]@{ Value = [string]$disk.name; Label = ('Data disk LUN {0}: {1}' -f [string]$disk.lun,[string]$disk.name); Detail = ('{0} GB | {1} | {2}' -f [string]$disk.diskSizeGb,[string]$disk.managedDisk.storageAccountType,[string]$disk.caching); Enabled = $true }
        }
        if ($diskOptions.Count -eq 0) { throw 'No managed OS or data disks were found for this VC.' }
        $diskSelection = Select-ProdicloudNumberedOptionPage -Options $diskOptions -Prompt 'Select a managed disk' -DefaultValue ([string]$osDisk.name) -PageSize 12
        if ([string]$diskSelection.Action -ne 'selected') { return }
        $selectedDisk = @($diskOptions | Where-Object { [string]::Equals([string]$_.Value,[string]$diskSelection.Value,[System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)[0]
        $rawSize = Read-ProdicloudUiValidatedText -Prompt 'Desired disk size (for example 128GB or 1TB)' -Validator {
            param($value)
            $parsed = Resolve-ProdicloudResizeTargetDiskSize -Options @{ 'disk-size' = [string]$value } -MaximumDiskSizeGb 4095
            return [string]$parsed.RawText
        }
        $parsedSize = Resolve-ProdicloudResizeTargetDiskSize -Options @{ 'disk-size' = [string]$rawSize } -MaximumDiskSizeGb 4095
        $currentSize = 0
        foreach ($option in $diskOptions) { if ($option.Value -eq $selectedDisk.Value) { [void][int]::TryParse(([string]$option.Detail -split ' ')[0],[ref]$currentSize) } }
        $intent = if ([int]$parsedSize.TargetDiskSizeGb -gt $currentSize) { 'expand' } elseif ([int]$parsedSize.TargetDiskSizeGb -lt $currentSize) { 'shrink' } else { 'same' }

        Write-ProdicloudUiHeader -Title 'Resize VM disk — review'
        Write-Host ('VC: {0} | Region: {1}' -f $name,[string]$Vm.location)
        Write-Host ('Disk: {0} | Current: {1} GB | Requested: {2} GB | Action: {3}' -f [string]$selectedDisk.Label,$currentSize,[int]$parsedSize.TargetDiskSizeGb,$intent)
        Write-Host 'Azure disk capacity and the guest partition/filesystem will both be verified.'
        if ($intent -eq 'shrink') { Write-Host 'Shrink preflight requires used data at least 10 GiB below the target; the original disk is removed only after the replacement verifies.' -ForegroundColor Yellow }
        Write-Host 'a: apply resize | c: close wizard'
        $apply = (Read-ProdicloudUiMenuChoice 'Resize action').ToLowerInvariant()
        if ($apply -ne 'a' -or $intent -eq 'same') { return }
        if ($intent -eq 'shrink' -and (Read-ProdicloudUiChoice 'Type SHRINK to authorize disk replacement and post-verification source cleanup') -cne 'SHRINK') { return }

        $options = New-ProdicloudUiTargetOptions -Vm $Vm
        $options['disk-name'] = [string]$selectedDisk.Value
        $options['disk-size'] = [string]$rawSize
        $options[$intent] = $true
        if ($intent -eq 'shrink') { $options['yes'] = $true }
        Invoke-ProdicloudUiCommand -CommandName 'resize' -Options $options
    }
    catch {
        Write-ProdicloudUiError -ErrorRecord $_
        Wait-ProdicloudUiContinue
    }
}

function Show-ProdicloudUiOperationsMenu {
    param([psobject]$Vm)

    while ($true) {
        Write-ProdicloudUiHeader -Title ('VC Operations for {0}' -f [string]$Vm.name)
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
        Write-Host 'c: close operations menu'
        Write-Host 'q: exit'
        $choice = (Read-ProdicloudUiMenuChoice).ToLowerInvariant()
        if ($choice -in @('b','c')) { return }
        if ($choice -eq 'q') { Stop-ProdicloudUiBackgroundCacheWorker; exit }
        $options = New-ProdicloudUiTargetOptions -Vm $Vm
        switch ($choice) {
            '1' {
                $actions = @(
                    [pscustomobject]@{ Action = 'status'; Label = 'status (read-only)' },
                    [pscustomobject]@{ Action = 'start'; Label = 'start VC' },
                    [pscustomobject]@{ Action = 'shutdown'; Label = 'shutdown/stop gracefully (remains allocated)' },
                    [pscustomobject]@{ Action = 'shutdown-deallocate'; Label = 'shutdown gracefully and deallocate' }
                )
                $isWindowsVm = [string]::Equals([string]$Vm.storageProfile.osDisk.osType,'Windows',[System.StringComparison]::OrdinalIgnoreCase)
                if ($isWindowsVm) {
                    $actions += [pscustomobject]@{ Action = 'hibernate-stop'; Label = 'hibernate guest (Windows; remains allocated)' }
                }
                $actions += @(
                    [pscustomobject]@{ Action = 'hibernate-deallocate'; Label = 'hibernate and deallocate (Azure)' },
                    [pscustomobject]@{ Action = 'resume'; Label = 'resume hibernated VC' },
                    [pscustomobject]@{ Action = 'restart'; Label = 'restart VC' },
                    [pscustomobject]@{ Action = 'power-off'; Label = 'force power off (skip guest shutdown; remains allocated)' },
                    [pscustomobject]@{ Action = 'power-off-deallocate'; Label = 'force power off and deallocate' },
                    [pscustomobject]@{ Action = 'reset'; Label = 'reboot / force reset through Azure redeploy' },
                    [pscustomobject]@{ Action = 'deallocate'; Label = 'deallocate VC' },
                    [pscustomobject]@{ Action = 'reapply'; Label = 'reapply VC configuration' },
                    [pscustomobject]@{ Action = 'redeploy'; Label = 'redeploy VC to Azure host' }
                )
                for ($index = 0; $index -lt $actions.Count; $index++) { Write-Host ('{0}. {1}' -f ($index + 1), [string]$actions[$index].Label) }
                $actionChoice = Read-ProdicloudUiMenuChoice 'VM action number'
                if ($actionChoice -in @('b','c')) { continue }
                $actionIndex = 0
                if (-not [int]::TryParse($actionChoice, [ref]$actionIndex) -or $actionIndex -lt 1 -or $actionIndex -gt $actions.Count) { continue }
                $selectedAction = [string]$actions[$actionIndex - 1].Action
                if ($selectedAction -eq 'power-off') {
                    if ((Read-ProdicloudUiChoice 'Type POWER OFF to force an immediate guest power-off') -cne 'POWER OFF') { continue }
                }
                elseif ($selectedAction -eq 'power-off-deallocate') {
                    if ((Read-ProdicloudUiChoice 'Type POWER OFF AND DEALLOCATE to force power off and release compute') -cne 'POWER OFF AND DEALLOCATE') { continue }
                }
                elseif ($selectedAction -eq 'reset') {
                    if ((Read-ProdicloudUiChoice 'Type RESET to force reboot through Azure redeploy') -cne 'RESET') { continue }
                }
                $options['vm-action'] = $selectedAction
                [void]$options.Remove('windows')
                [void]$options.Remove('linux')
                Invoke-ProdicloudUiCommand -CommandName 'do' -Options $options
            }
            '2' {
                Write-Host '1. Resize VM hardware'
                Write-Host '2. Resize VM disk'
                $resizeChoice = Read-ProdicloudUiMenuChoice 'Resize wizard'
                if ($resizeChoice -in @('b','c')) { continue }
                if ($resizeChoice -eq '1') {
                    Show-ProdicloudUiResizeHardwareWizard -Vm $Vm
                }
                elseif ($resizeChoice -eq '2') { Show-ProdicloudUiResizeDiskWizard -Vm $Vm }
                else { continue }
            }
            '3' {
                $options['vm-region'] = Select-AzLocationInteractive -DefaultLocation ([string]$Vm.location)
                Invoke-ProdicloudUiCommand -CommandName 'move' -Options $options
            }
            '4' {
                Write-Host 'h: hibernation | n: nested virtualization'
                $feature = (Read-ProdicloudUiMenuChoice 'Feature').ToLowerInvariant()
                if ($feature -in @('b','c')) { continue }
                Write-Host '1: enable | 2: disable'
                $valueChoice = Read-ProdicloudUiMenuChoice 'Feature state'
                if ($valueChoice -in @('b','c')) { continue }
                $value = switch ($valueChoice) { '1' { 'true' } '2' { 'false' } default { '' } }
                if ([string]::IsNullOrWhiteSpace($value)) { continue }
                if ($feature -eq 'h') { $options['hibernation'] = $value }
                elseif ($feature -eq 'n') { $options['nested-virtualization'] = $value }
                else { continue }
                Invoke-ProdicloudUiCommand -CommandName 'set' -Options $options
            }
            '5' {
                $isWindowsVm = [string]::Equals([string]$Vm.storageProfile.osDisk.osType, 'Windows', [System.StringComparison]::OrdinalIgnoreCase)
                if ($isWindowsVm) {
                    Write-Host 's: SSH | r: RDP | t: test SSH | d: test RDP | p: PowerShell session | c: PowerShell command | w: test PowerShell'
                }
                else {
                    Write-Host 's: SSH | t: test SSH'
                }
                $transport = (Read-ProdicloudUiMenuChoice 'Connection').ToLowerInvariant()
                if ($transport -in @('s','t')) { $options['ssh'] = $true }
                elseif ($transport -in @('r','d') -and $isWindowsVm) { $options['rdp'] = $true }
                elseif ($transport -in @('p','c','w') -and $isWindowsVm) { $options['powershell'] = $true }
                else { continue }
                if ($transport -in @('t','d','w')) { $options['test'] = $true }
                if ($transport -eq 'c') { $options['command'] = Read-ProdicloudUiChoice 'Remote PowerShell command' }
                [void]$options.Remove('windows')
                [void]$options.Remove('linux')
                Invoke-ProdicloudUiCommand -CommandName 'connect' -Options $options
            }
            '6' {
                $command = Read-ProdicloudUiChoice 'Remote command (leave blank for interactive shell)'
                if (-not [string]::IsNullOrWhiteSpace($command)) { $options['command'] = $command }
                Invoke-ProdicloudUiCommand -CommandName 'exec' -Options $options
            }
            '7' { Show-ProdicloudUiTaskMenu -Vm $Vm }
            '8' { Show-ProdicloudUiComponentMenu -Vm $Vm }
            '9' {
                Write-Host 't: show report on screen | j: export redacted JSON'
                $reportMode = (Read-ProdicloudUiMenuChoice 'Report output').ToLowerInvariant()
                if ($reportMode -in @('b','c')) { continue }
                if ($reportMode -eq 'j') {
                    $exportPath = Read-ProdicloudUiValidatedText -Prompt 'JSON export path (press Enter to cancel)' -AllowBlank -Validator {
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
                        if ((Read-ProdicloudUiChoice 'Type OVERWRITE to replace the existing report file') -cne 'OVERWRITE') { continue }
                        $options['overwrite'] = $true
                    }
                }
                elseif ($reportMode -notin @('','t')) {
                    continue
                }
                Invoke-ProdicloudUiCommand -CommandName 'show' -Options $options
            }
        }
    }
}

function Show-ProdicloudUiVmMenu {
    param([psobject]$Vm)

    while ($true) {
        try { Show-ProdicloudUiVmDetails -Vm $Vm }
        catch { Write-ProdicloudUiHeader -Title ('Virtual computer: {0}' -f [string]$Vm.name); Write-ProdicloudUiError -ErrorRecord $_ }
        Write-Host 'p: setup all program packages'
        Write-Host 'i: initialize VC'
        Write-Host ("k: reset managed-user passwords from {0}.env" -f [string]$Vm.name)
        Write-Host 'u: update VC'
        Write-Host 'm: manage program packages'
        Write-Host 'x: manage VC components'
        Write-Host 'o: VC Operations'
        Write-Host 'd: delete VC and its resources'
        Write-Host 'r: refresh details'
        Write-ProdicloudUiNavigationFooter
        $choice = (Read-ProdicloudUiMenuChoice).ToLowerInvariant()
        if ($choice -in @('b','c')) { return }
        if ($choice -eq 'q') { Stop-ProdicloudUiBackgroundCacheWorker; exit }
        $target = New-ProdicloudUiTargetOptions -Vm $Vm
        switch ($choice) {
            'p' { Show-ProdicloudUiSetupAllPackages -Vm $Vm }
            'i' { Invoke-ProdicloudUiCommand -CommandName 'initialize' -Options $target }
            'k' {
                $resetOptions = @{}; foreach ($optionName in $target.Keys) { $resetOptions[[string]$optionName] = $target[$optionName] }
                $resetOptions['reset-managed-user-passwords'] = $true
                Invoke-ProdicloudUiCommand -CommandName 'initialize' -Options $resetOptions
            }
            'u' { Invoke-ProdicloudUiCommand -CommandName 'update' -Options $target }
            'm' { Show-ProdicloudUiPackageMenu -Vm $Vm }
            'x' { Show-ProdicloudUiComponentMenu -Vm $Vm }
            'o' { Show-ProdicloudUiOperationsMenu -Vm $Vm }
            'd' {
                try {
                    $resources = @(Get-ProdicloudUiResourcesForGroup -ResourceGroup ([string]$Vm.ProdicloudResourceGroup))
                    Write-Host 'The following Azure resources will be removed:' -ForegroundColor Yellow
                    foreach ($resource in @($resources | Sort-Object { [string]$_.type }, { [string]$_.name })) { Write-Host ('  - {0}: {1}' -f [string]$resource.type, [string]$resource.name) }
                    $confirm = Read-ProdicloudUiChoice "Type DELETE ALL to remove this VC's complete resource group"
                    if ($confirm -ceq 'DELETE ALL') {
                        $target['target'] = 'group'
                        $target['yes'] = $true
                        Invoke-ProdicloudUiCommand -CommandName 'delete' -Options $target
                        return
                    }
                }
                catch { Write-ProdicloudUiError -ErrorRecord $_; Wait-ProdicloudUiContinue }
            }
        }
    }
}

function Resolve-ProdicloudUiWizardPageStep {
    param(
        [object[]]$Options,
        [string]$Prompt,
        [string]$DefaultValue = '',
        [string[]]$ExtraKeys = @(),
        [switch]$Required
    )

    while ($true) {
        $selection = Select-ProdicloudNumberedOptionPage -Options $Options -Prompt $Prompt -DefaultValue $DefaultValue -PageSize 12 -WizardControls -ExtraKeys $ExtraKeys
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

function Get-ProdicloudUiWizardBooleanDefault {
    param([hashtable]$Config, [string]$Key, [bool]$DefaultValue)

    try {
        return ([string](Resolve-ProdicloudBooleanConfigValue -RawValue ([string](Get-ConfigValue -Config $Config -Key $Key -DefaultValue ([string]$DefaultValue))) -KeyName $Key -DefaultValue $DefaultValue -TreatEmptyAsDefault)).ToLowerInvariant()
    }
    catch {
        Write-Host ("Configured default for {0} is invalid: {1}. Select a value in the wizard." -f $Key, [string]$_.Exception.Message) -ForegroundColor Yellow
        return ''
    }
}

function Read-ProdicloudUiWizardTextStep {
    param(
        [string]$Title,
        [string]$DefaultValue = '',
        [string]$Example = '',
        [switch]$Required,
        [scriptblock]$Validator
    )

    while ($true) {
        Write-ProdicloudUiHeader -Title $Title
        if (-not [string]::IsNullOrWhiteSpace([string]$DefaultValue)) { Write-Host ('> Current/default value: {0}' -f $DefaultValue) -ForegroundColor Green }
        elseif ($Required) { Write-Host 'Required value: no default is configured.' -ForegroundColor Yellow }
        if (-not [string]::IsNullOrWhiteSpace([string]$Example)) { Write-Host ('Example: {0}' -f $Example) -ForegroundColor Gray }
        Write-Host 's: skip (keep default) | k: skip all remaining | a: apply default | l: apply all defaults | c: close wizard'
        $raw = Read-ProdicloudUiMenuChoice 'Enter value'
        $command = $raw.ToLowerInvariant()
        if ($command -in @('b','c')) { return [pscustomobject]@{ Action = 'close'; Value = '' } }
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

function Get-ProdicloudUiCreateDefaultValue {
    param([hashtable]$Config,[string]$DefaultKey,[string]$LegacyKey = '',[string]$Fallback = '')

    $value = [string](Get-ConfigValue -Config $Config -Key $DefaultKey -DefaultValue '')
    if ([string]::IsNullOrWhiteSpace($value) -and -not [string]::IsNullOrWhiteSpace($LegacyKey)) {
        $value = [string](Get-ConfigValue -Config $Config -Key $LegacyKey -DefaultValue '')
    }
    if ([string]::IsNullOrWhiteSpace($value)) { $value = [string]$Fallback }
    return [string]$value
}

function Show-ProdicloudUiCreateWizard {
    $envPath = Join-Path $script:ProdicloudUiRepoRoot 'prodicloud.env'
    $globalConfig = Read-DotEnvFile -Path $envPath -GlobalOnly
    $config = Merge-ProdicloudVmEnvironmentConfig -GlobalConfigMap $globalConfig -IgnoreActiveSelection
    $subscriptionId = if ($null -ne $script:ProdicloudUiSubscription) { [string]$script:ProdicloudUiSubscription.SubscriptionId } else { '' }
    if ([string]::IsNullOrWhiteSpace([string]$subscriptionId)) {
        Write-ProdicloudUiError -ErrorRecord ([System.Exception]::new("Select an active Azure subscription and run 'az login' before creating a virtual computer."))
        Wait-ProdicloudUiContinue
        return
    }

    $platformDefault = (Get-ProdicloudUiCreateDefaultValue -Config $config -DefaultKey 'DEFAULT_VM_OS' -LegacyKey 'SELECTED_VM_OS' -Fallback 'windows').Trim().ToLowerInvariant()
    if ($platformDefault -notin @('windows','linux')) { $platformDefault = '' }
    $wizardValues = @{}
    $wizardSources = @{}
    $skipRemaining = $false

    $platformOptions = @(
        [pscustomobject]@{ Value = 'windows'; Label = 'Windows'; Detail = 'Windows Server or Windows client image' },
        [pscustomobject]@{ Value = 'linux'; Label = 'Linux'; Detail = 'Linux server image' }
    )
    $platformResult = Resolve-ProdicloudUiWizardPageStep -Options $platformOptions -Prompt 'Operating system' -DefaultValue $platformDefault -Required
    if ($platformResult.Action -eq 'close') { return }
    $platform = [string]$platformResult.Value
    $wizardSources['SELECTED_VM_OS'] = if ($platformResult.Action -in @('skip','apply-default','skip-all','apply-all')) { 'default' } else { 'selected' }
    if ($platformResult.Action -in @('skip-all','apply-all')) { $skipRemaining = $true }

    $platformDefaults = Get-ProdicloudPlatformDefaults -Platform $platform
    $vmNameDefault = [string](Get-ConfigValue -Config $config -Key 'SELECTED_VM_NAME' -DefaultValue '')
    $regionDefault = Get-ProdicloudUiCreateDefaultValue -Config $config -DefaultKey 'DEFAULT_AZURE_REGION' -LegacyKey 'SELECTED_AZURE_REGION'
    $vmSizeKey = Get-ProdicloudPlatformVmConfigKey -Platform $platform -BaseKey 'VM_SIZE'
    $imageKey = Get-ProdicloudPlatformVmConfigKey -Platform $platform -BaseKey 'VM_IMAGE'
    $diskKey = Get-ProdicloudPlatformVmConfigKey -Platform $platform -BaseKey 'VM_DISK_SIZE_GB'
    $defaultPlatformPrefix = if ($platform -eq 'windows') { 'WIN' } else { 'LIN' }
    $vmSizeDefaultKey = 'DEFAULT_{0}_VM_SIZE' -f $defaultPlatformPrefix
    $imageDefaultKey = 'DEFAULT_{0}_VM_IMAGE' -f $defaultPlatformPrefix
    $diskDefaultKey = 'DEFAULT_{0}_VM_DISK_SIZE_GB' -f $defaultPlatformPrefix
    $vmSizeDefault = Get-ProdicloudUiCreateDefaultValue -Config $config -DefaultKey $vmSizeDefaultKey -LegacyKey $vmSizeKey -Fallback ([string]$platformDefaults.VmSizeDefault)
    $imageRawDefault = Get-ProdicloudUiCreateDefaultValue -Config $config -DefaultKey $imageDefaultKey -LegacyKey $imageKey -Fallback ([string]$platformDefaults.VmImageDefault)
    $storageSkuDefault = Get-ProdicloudUiCreateDefaultValue -Config $config -DefaultKey 'DEFAULT_VM_STORAGE_SKU' -LegacyKey 'VM_STORAGE_SKU' -Fallback 'StandardSSD_LRS'
    if ([string]::IsNullOrWhiteSpace([string]$storageSkuDefault)) { $storageSkuDefault = 'StandardSSD_LRS' }
    $securityDefault = ''
    try { $securityDefault = [string](Resolve-ProdicloudSecurityTypeValue -RawValue (Get-ProdicloudUiCreateDefaultValue -Config $config -DefaultKey 'DEFAULT_VM_SECURITY_TYPE' -LegacyKey 'VM_SECURITY_TYPE' -Fallback 'Standard')) }
    catch { Write-Host ('Configured VM_SECURITY_TYPE is invalid: {0}. Select a security type in the wizard.' -f [string]$_.Exception.Message) -ForegroundColor Yellow }
    if ([string]::IsNullOrWhiteSpace([string]$securityDefault)) { $securityDefault = 'Standard' }
    $hibernationDefault = Get-ProdicloudUiWizardBooleanDefault -Config @{ VM_ENABLE_HIBERNATION = (Get-ProdicloudUiCreateDefaultValue -Config $config -DefaultKey 'DEFAULT_VM_ENABLE_HIBERNATION' -LegacyKey 'VM_ENABLE_HIBERNATION' -Fallback 'true') } -Key 'VM_ENABLE_HIBERNATION' -DefaultValue $true
    $nestedDefault = Get-ProdicloudUiWizardBooleanDefault -Config @{ VM_ENABLE_NESTED_VIRTUALIZATION = (Get-ProdicloudUiCreateDefaultValue -Config $config -DefaultKey 'DEFAULT_VM_ENABLE_NESTED_VIRTUALIZATION' -LegacyKey 'VM_ENABLE_NESTED_VIRTUALIZATION' -Fallback 'true') } -Key 'VM_ENABLE_NESTED_VIRTUALIZATION' -DefaultValue $true
    $secureBootDefault = Get-ProdicloudUiWizardBooleanDefault -Config @{ VM_ENABLE_SECURE_BOOT = (Get-ProdicloudUiCreateDefaultValue -Config $config -DefaultKey 'DEFAULT_VM_ENABLE_SECURE_BOOT' -LegacyKey 'VM_ENABLE_SECURE_BOOT' -Fallback 'true') } -Key 'VM_ENABLE_SECURE_BOOT' -DefaultValue $true
    $vtpmDefault = Get-ProdicloudUiWizardBooleanDefault -Config @{ VM_ENABLE_VTPM = (Get-ProdicloudUiCreateDefaultValue -Config $config -DefaultKey 'DEFAULT_VM_ENABLE_VTPM' -LegacyKey 'VM_ENABLE_VTPM' -Fallback 'true') } -Key 'VM_ENABLE_VTPM' -DefaultValue $true
    $diskDefaultRaw = Get-ProdicloudUiCreateDefaultValue -Config $config -DefaultKey $diskDefaultKey -LegacyKey $diskKey -Fallback ([string]$platformDefaults.VmDiskSizeDefault)
    $diskDefault = ''
    try { $diskDefault = ConvertTo-ProdicloudOsDiskSizeGb -Value $diskDefaultRaw -FieldName $diskKey }
    catch { Write-Host ('Disk default will need an entered value: {0}' -f [string]$_.Exception.Message) -ForegroundColor Yellow }
    $imageDefault = Resolve-ProdicloudTemplate -Template $imageRawDefault -Tokens @{ SELECTED_VM_NAME = $vmNameDefault }
    $sshPortDefaultRaw = Get-ProdicloudUiCreateDefaultValue -Config $config -DefaultKey 'DEFAULT_VM_SSH_PORT' -LegacyKey 'VM_SSH_PORT' -Fallback (Get-ProdicloudDefaultSshPortText)
    $sshPortDefault = ''
    try { $sshPortDefault = Resolve-ProdicloudTcpPortNumber -Value $sshPortDefaultRaw -Label 'VM_SSH_PORT' }
    catch { Write-Host ('SSH port default will need correction: {0}' -f [string]$_.Exception.Message) -ForegroundColor Yellow }
    $rdpPortDefaultRaw = Get-ProdicloudUiCreateDefaultValue -Config $config -DefaultKey 'DEFAULT_VM_RDP_PORT' -LegacyKey 'VM_RDP_PORT' -Fallback (Get-ProdicloudDefaultRdpPortText)
    $rdpPortDefault = ''
    if ($platform -eq 'windows') {
        try { $rdpPortDefault = Resolve-ProdicloudTcpPortNumber -Value $rdpPortDefaultRaw -Label 'VM_RDP_PORT' }
        catch { Write-Host ('RDP port default will need correction: {0}' -f [string]$_.Exception.Message) -ForegroundColor Yellow }
    }
    $requiredPorts = @()
    if (-not [string]::IsNullOrWhiteSpace([string]$sshPortDefault)) { $requiredPorts += $sshPortDefault }
    if (-not [string]::IsNullOrWhiteSpace([string]$rdpPortDefault)) { $requiredPorts += $rdpPortDefault }
    $wizardValues['SshPort'] = [string]$sshPortDefault
    if ($platform -eq 'windows') { $wizardValues['RdpPort'] = [string]$rdpPortDefault }
    $portsDefaultRaw = Get-ProdicloudUiCreateDefaultValue -Config $config -DefaultKey 'DEFAULT_TCP_PORTS' -LegacyKey 'TCP_PORTS' -Fallback (Get-ProdicloudDefaultTcpPortsCsv)
    $portsDefault = ''
    try { $portsDefault = [string](Resolve-ProdicloudTcpPortSpecification -Text $portsDefaultRaw -RequiredPorts $requiredPorts).CanonicalText }
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

    if (-not $skipRemaining -or [string]::IsNullOrWhiteSpace([string]$vmNameDefault)) {
        $nameResult = Read-ProdicloudUiWizardTextStep -Title 'Virtual computer name' -DefaultValue $vmNameDefault -Example '3-16 characters, starts with a letter' -Required -Validator {
            param($value)
            $candidate = ([string]$value).Trim()
            if (-not (Test-ProdicloudVmNameFormat -VmName $candidate)) { throw 'VM name must contain 3-16 characters, start with a letter, and use only letters, numbers, or hyphens.' }
            return $candidate
        }
        if ($nameResult.Action -eq 'close') { return }
        $wizardValues['VmName'] = [string]$nameResult.Value
        $wizardSources['SELECTED_VM_NAME'] = if ($nameResult.Action -in @('skip','apply-default','skip-all','apply-all')) { 'default' } else { 'selected' }
        if ($nameResult.Action -in @('skip-all','apply-all')) { $skipRemaining = $true }
    }
    else { $wizardValues['VmName'] = $vmNameDefault }

    $vmNameForTokens = if (-not [string]::IsNullOrWhiteSpace([string]$wizardValues['VmName'])) { [string]$wizardValues['VmName'] } else { [string]$vmNameDefault }
    $imageDefault = Resolve-ProdicloudTemplate -Template $imageRawDefault -Tokens @{ SELECTED_VM_NAME = $vmNameForTokens }
    $diskDefaultValue = $diskDefault
    $portDefaultValue = $portsDefault
    $regionValue = $regionDefault
    $sizeValue = $vmSizeDefault

    if (-not $skipRemaining -or [string]::IsNullOrWhiteSpace([string]$regionDefault)) {
        try { $locations = @(Get-AzLocationCatalog) }
        catch {
            Write-ProdicloudUiError -ErrorRecord $_
            Wait-ProdicloudUiContinue
            return
        }
        $locationOptions = @($locations | ForEach-Object {
            $locationName = [string]$_.Name
            $displayName = if ([string]::IsNullOrWhiteSpace([string]$_.DisplayName)) { $locationName } else { [string]$_.DisplayName }
            [pscustomobject]@{ Value = $locationName; Label = $displayName; Detail = $locationName }
        })
        if (@($locationOptions).Count -eq 0) {
            Write-ProdicloudUiError -ErrorRecord ([System.Exception]::new('Azure returned no selectable regions for the active subscription.'))
            Wait-ProdicloudUiContinue
            return
        }
        $regionResult = Resolve-ProdicloudUiWizardPageStep -Options $locationOptions -Prompt 'Azure region' -DefaultValue $regionDefault -Required
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
                Write-ProdicloudUiError -ErrorRecord $_
                Wait-ProdicloudUiContinue
                return
            }
            if (@($skuRows).Count -eq 0) {
                Write-ProdicloudUiHeader -Title ("VM size/SKU in {0}" -f $regionValue)
                Write-Host ('No VM sizes matched the current filter "{0}".' -f $skuFilter) -ForegroundColor Yellow
                Write-Host 'x: change or clear SKU filter'
                Write-Host 'r: restart wizard and choose another region'
                Write-Host 'c: close wizard'
            $emptySkuChoice = (Read-ProdicloudUiMenuChoice 'SKU list action').ToLowerInvariant()
                if ($emptySkuChoice -eq 'x') {
                    $skuFilter = Read-ProdicloudUiValidatedText -Prompt 'Filter SKU names (letters, numbers, _, -, ., *, ?; Enter clears filter)' -AllowBlank -Validator {
                        param($value)
                        $candidate = ([string]$value).Trim()
                        if ($candidate.Length -gt 80 -or $candidate -notmatch '^[a-zA-Z0-9_*?.-]*$') { throw 'SKU filter may use only letters, numbers, period, underscore, hyphen, * and ? (maximum 80 characters).' }
                        return $candidate
                    }
                    continue
                }
                if ($emptySkuChoice -eq 'r') { return (Show-ProdicloudUiCreateWizard) }
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
            $skuResult = Resolve-ProdicloudUiWizardPageStep -Options $skuOptions -Prompt ("VM size/SKU in {0}" -f $regionValue) -DefaultValue $vmSizeDefault -ExtraKeys @('x') -Required
            if ($skuResult.Action -eq 'close') { return }
            if ($skuResult.Action -eq 'extra' -and [string]$skuResult.ExtraKey -eq 'x') {
                $skuFilter = Read-ProdicloudUiValidatedText -Prompt 'Filter SKU names (letters, numbers, _, -, ., *, ?; Enter clears filter)' -AllowBlank -Validator {
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
        $imageChoice = Resolve-ProdicloudUiWizardPageStep -Options $imageChoiceOptions -Prompt 'OS image' -DefaultValue 'default' -Required
        if ($imageChoice.Action -eq 'close') { return }
        if ($imageChoice.Value -eq 'custom') {
            $imageResult = Read-ProdicloudUiWizardTextStep -Title 'Custom OS image' -DefaultValue '' -Example 'publisher:offer:sku:latest or a full Azure image resource ID' -Required -Validator {
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
        if ($storageSkuDefault -notin @($storageOptions | ForEach-Object { [string]$_.Value })) { $storageOptions = @([pscustomobject]@{ Value = $storageSkuDefault; Label = ('Configured: {0}' -f $storageSkuDefault); Detail = 'current global create default' }) + @($storageOptions) }
        $storageResult = Resolve-ProdicloudUiWizardPageStep -Options $storageOptions -Prompt 'OS disk storage performance tier' -DefaultValue $storageSkuDefault -Required
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
        $securityResult = Resolve-ProdicloudUiWizardPageStep -Options $securityOptions -Prompt 'VM security type' -DefaultValue $securityDefault -Required
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
        $hibernationResult = Resolve-ProdicloudUiWizardPageStep -Options $toggleOptions -Prompt 'Hibernation' -DefaultValue $hibernationDefault -Required
        if ($hibernationResult.Action -eq 'close') { return }
        $hibernationValue = [string]$hibernationResult.Value
        $wizardSources['VM_ENABLE_HIBERNATION'] = if ($hibernationResult.Action -in @('skip','apply-default','skip-all','apply-all')) { 'default' } else { 'selected' }
        if ($hibernationResult.Action -in @('skip-all','apply-all')) { $skipRemaining = $true }
    }

    if (-not $skipRemaining) {
        $toggleOptions = @([pscustomobject]@{ Value = 'true'; Label = 'Enabled'; Detail = '' }, [pscustomobject]@{ Value = 'false'; Label = 'Disabled'; Detail = '' })
        $nestedResult = Resolve-ProdicloudUiWizardPageStep -Options $toggleOptions -Prompt 'Nested virtualization' -DefaultValue $nestedDefault -Required
        if ($nestedResult.Action -eq 'close') { return }
        $nestedValue = [string]$nestedResult.Value
        $wizardSources['VM_ENABLE_NESTED_VIRTUALIZATION'] = if ($nestedResult.Action -in @('skip','apply-default','skip-all','apply-all')) { 'default' } else { 'selected' }
        if ($nestedResult.Action -in @('skip-all','apply-all')) { $skipRemaining = $true }
    }

    if (-not $skipRemaining -and $securityValue -eq 'TrustedLaunch') {
        $toggleOptions = @([pscustomobject]@{ Value = 'true'; Label = 'Enabled'; Detail = '' }, [pscustomobject]@{ Value = 'false'; Label = 'Disabled'; Detail = '' })
        $secureBootResult = Resolve-ProdicloudUiWizardPageStep -Options $toggleOptions -Prompt 'Secure Boot (Trusted Launch)' -DefaultValue $secureBootDefault -Required
        if ($secureBootResult.Action -eq 'close') { return }
        $secureBootValue = [string]$secureBootResult.Value
        $wizardSources['VM_ENABLE_SECURE_BOOT'] = if ($secureBootResult.Action -in @('skip','apply-default','skip-all','apply-all')) { 'default' } else { 'selected' }
        if ($secureBootResult.Action -in @('skip-all','apply-all')) { $skipRemaining = $true }
        if (-not $skipRemaining) {
            $vtpmResult = Resolve-ProdicloudUiWizardPageStep -Options $toggleOptions -Prompt 'vTPM (Trusted Launch)' -DefaultValue $vtpmDefault -Required
            if ($vtpmResult.Action -eq 'close') { return }
            $vtpmValue = [string]$vtpmResult.Value
            $wizardSources['VM_ENABLE_VTPM'] = if ($vtpmResult.Action -in @('skip','apply-default','skip-all','apply-all')) { 'default' } else { 'selected' }
            if ($vtpmResult.Action -in @('skip-all','apply-all')) { $skipRemaining = $true }
        }
    }

    if (-not $skipRemaining) {
        $sshPortResult = Read-ProdicloudUiWizardTextStep -Title 'SSH connection port' -DefaultValue $sshPortDefault -Example '22 or 2222' -Required -Validator {
            param($value)
            return (Resolve-ProdicloudTcpPortNumber -Value ([string]$value) -Label 'SSH port')
        }
        if ($sshPortResult.Action -eq 'close') { return }
        $wizardValues['SshPort'] = [string]$sshPortResult.Value
        $wizardSources['VM_SSH_PORT'] = if ($sshPortResult.Action -in @('skip','apply-default','skip-all','apply-all')) { 'default' } else { 'selected' }
        if ($sshPortResult.Action -in @('skip-all','apply-all')) { $skipRemaining = $true }
    }
    if (-not $skipRemaining -and $platform -eq 'windows') {
        $rdpPortResult = Read-ProdicloudUiWizardTextStep -Title 'RDP connection port' -DefaultValue $rdpPortDefault -Example '3389 or 3390' -Required -Validator {
            param($value)
            return (Resolve-ProdicloudTcpPortNumber -Value ([string]$value) -Label 'RDP port')
        }
        if ($rdpPortResult.Action -eq 'close') { return }
        $wizardValues['RdpPort'] = [string]$rdpPortResult.Value
        $wizardSources['VM_RDP_PORT'] = if ($rdpPortResult.Action -in @('skip','apply-default','skip-all','apply-all')) { 'default' } else { 'selected' }
        if ($rdpPortResult.Action -in @('skip-all','apply-all')) { $skipRemaining = $true }
    }

    if (-not $skipRemaining) {
        $diskResult = Read-ProdicloudUiWizardTextStep -Title 'OS disk size' -DefaultValue $diskDefaultValue -Example '1MB, 128GB, or 1TB (Azure maximum: 4095GB)' -Required -Validator {
            param($value)
            return (ConvertTo-ProdicloudOsDiskSizeGb -Value ([string]$value) -FieldName 'OS disk size')
        }
        if ($diskResult.Action -eq 'close') { return }
        $wizardValues['DiskSizeGb'] = [string]$diskResult.Value
        $wizardSources[$diskKey] = if ($diskResult.Action -in @('skip','apply-default','skip-all','apply-all')) { 'default' } else { 'selected' }
        if ($diskResult.Action -in @('skip-all','apply-all')) { $skipRemaining = $true }
    }

    if (-not $skipRemaining) {
        $portsResult = Read-ProdicloudUiWizardTextStep -Title 'Inbound TCP ports' -DefaultValue $portDefaultValue -Example '22,80,443,3000-3300' -Required -Validator {
            param($value)
            $required = @([string]$wizardValues['SshPort'])
            if ($platform -eq 'windows') { $required += [string]$wizardValues['RdpPort'] }
            return [string](Resolve-ProdicloudTcpPortSpecification -Text ([string]$value) -RequiredPorts $required).CanonicalText
        }
        if ($portsResult.Action -eq 'close') { return }
        $wizardValues['TcpPorts'] = [string]$portsResult.Value
        $wizardSources['TCP_PORTS'] = if ($portsResult.Action -in @('skip','apply-default','skip-all','apply-all')) { 'default' } else { 'selected' }
    }

    if (-not $wizardValues.ContainsKey('DiskSizeGb')) { $wizardValues['DiskSizeGb'] = [string]$diskDefaultValue }
    if (-not $wizardValues.ContainsKey('TcpPorts')) { $wizardValues['TcpPorts'] = [string]$portDefaultValue }
    $finalRequiredPorts = @([string]$wizardValues['SshPort'])
    if ($platform -eq 'windows') { $finalRequiredPorts += [string]$wizardValues['RdpPort'] }
    try { $wizardValues['TcpPorts'] = [string](Resolve-ProdicloudTcpPortSpecification -Text ([string]$wizardValues['TcpPorts']) -RequiredPorts $finalRequiredPorts).CanonicalText }
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
        Write-ProdicloudUiHeader -Title 'Create wizard — incomplete configuration'
        Write-Host ('Required defaults or selections are missing: {0}.' -f ($missingValues -join ', ')) -ForegroundColor Yellow
        Write-Host 'r: restart wizard'
        Write-Host 'c: close'
        if ((Read-ProdicloudUiMenuChoice 'Create wizard action').ToLowerInvariant() -eq 'r') { return (Show-ProdicloudUiCreateWizard) }
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

    Write-ProdicloudUiHeader -Title 'Create wizard — review'
    Write-Host ('Azure subscription: {0} ({1})' -f [string]$script:ProdicloudUiSubscription.SubscriptionName, [string]$script:ProdicloudUiSubscription.SubscriptionId)
    foreach ($reviewRow in @($reviewRows)) {
        $marker = if ($wizardSources.ContainsKey([string]$reviewRow.Key) -and [string]$wizardSources[[string]$reviewRow.Key] -eq 'default') { '>' } else { ' ' }
        Write-Host ('{0} {1}: {2}' -f $marker, [string]$reviewRow.Label, [string]$reviewRow.Value)
    }
    Write-Host 'a: apply selected setup'
    Write-Host 'l: apply all (keep all remaining configured defaults)'
    Write-Host 'c: close without creating'
    $finalChoice = (Read-ProdicloudUiMenuChoice 'Create virtual computer').ToLowerInvariant()
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
    Invoke-ProdicloudUiCommand -CommandName 'create' -Options $options -FrontendContext @{ CreateWizardMode = $true; CreateWizardValues = $wizardAnswers }
}

function Show-ProdicloudUiVirtualComputers {
    while ($true) {
        Write-ProdicloudUiHeader -Title 'Virtual computers'
        try {
            $vms = @(Get-ProdicloudUiVirtualComputers)
            $resourceSnapshot = Ensure-ProdicloudUiResourceCache
        }
        catch { Write-ProdicloudUiError -ErrorRecord $_; $vms = @() }
        if ($vms.Count -eq 0) {
            $cacheUnavailable = $null -eq $script:ProdicloudUiInventoryCache -or [bool]$script:ProdicloudUiInventoryCache.IsDirty
            if ($cacheUnavailable) { Write-Host 'Managed inventory is loading or refreshing in the background.' -ForegroundColor Yellow }
            else { Write-Host 'No managed virtual computers were found.' -ForegroundColor Yellow }
            Write-Host 'c: create virtual computer'
            Write-Host 'r: check or refresh managed resource cache'
            Write-Host 'b: back'
            Write-Host 'q: exit'
            $emptyChoice = (Read-ProdicloudUiMenuChoice).ToLowerInvariant()
            if ($emptyChoice -eq 'b') { return }
            if ($emptyChoice -eq 'q') { Stop-ProdicloudUiBackgroundCacheWorker; exit }
            if ($emptyChoice -eq 'c') { Show-ProdicloudUiCreateWizard; continue }
            if ($emptyChoice -eq 'r') { Update-ProdicloudUiSubscription; Request-ProdicloudUiInventoryRefresh -Force | Out-Null; continue }
            continue
        }

        $vmOptions = @(
            $vms | ForEach-Object {
                $power = Get-ProdicloudUiPowerState -ResourceGroup ([string]$_.ProdicloudResourceGroup) -VmName ([string]$_.name) -CachedPowerState ([string]$_.powerState)
                $vmOs = [string]$_.storageProfile.osDisk.osType
                $value = '{0}|{1}' -f [string]$_.ProdicloudResourceGroup, [string]$_.name
                [pscustomobject]@{ Value = $value; Label = [string]$_.name; Detail = ('{0} | {1} | {2} | {3}' -f $vmOs, [string]$_.hardwareProfile.vmSize, [string]$_.location, $power) }
            }
        )
        $defaultVm = '{0}|{1}' -f [string]$script:ProdicloudUiSelectedResourceGroup, [string]$script:ProdicloudUiSelectedVmName
        $selection = Select-ProdicloudNumberedOptionPage -Options $vmOptions -Prompt 'Virtual computers' -DefaultValue $defaultVm -PageSize 12 -ExtraKeys @('c','r') -ExtraKeyLabels @{ c = 'create virtual computer'; r = 'refresh managed resource cache' }
        if ([string]$selection.Action -eq 'back') { if ([string]$selection.Input -eq 'q') { Stop-ProdicloudUiBackgroundCacheWorker; exit }; return }
        if ([string]$selection.Action -eq 'extra' -and [string]$selection.ExtraKey -eq 'c') { Show-ProdicloudUiCreateWizard; continue }
        if ([string]$selection.Action -eq 'extra' -and [string]$selection.ExtraKey -eq 'r') { Update-ProdicloudUiSubscription; Request-ProdicloudUiInventoryRefresh -Force | Out-Null; continue }
        if ([string]$selection.Action -ne 'selected') { continue }
        $selectedParts = @(([string]$selection.Value -split '\|', 2))
        $selectedVm = @($vms | Where-Object {
            [string]::Equals([string]$_.ProdicloudResourceGroup, [string]$selectedParts[0], [System.StringComparison]::OrdinalIgnoreCase) -and
            [string]::Equals([string]$_.name, [string]$selectedParts[1], [System.StringComparison]::OrdinalIgnoreCase)
        } | Select-Object -First 1)
        if (@($selectedVm).Count -gt 0) {
            $selectedVmName = [string]$selectedVm[0].name
            Set-DotEnvValue -Path (Join-Path $script:ProdicloudUiRepoRoot 'prodicloud.env') -Key 'SELECTED_VM_NAME' -Value $selectedVmName
            $script:ProdicloudUiSelectedVmName = $selectedVmName
            $script:ProdicloudUiSelectedResourceGroup = [string]$selectedVm[0].ProdicloudResourceGroup
            Show-ProdicloudUiVmMenu -Vm $selectedVm[0]
        }
    }
}

function Show-ProdicloudUiInventoryMenu {
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
        Write-ProdicloudUiHeader -Title 'Managed resource inventory'
        if ($null -eq $script:ProdicloudUiInventoryCache -or [bool]$script:ProdicloudUiInventoryCache.IsDirty) {
            Write-Host 'Managed inventory is loading or refreshing in the background.' -ForegroundColor Yellow
            Write-Host 'r: request cache refresh'
            Write-Host 'b: back'
            Write-Host 'q: exit'
            $warmingChoice = (Read-ProdicloudUiMenuChoice).ToLowerInvariant()
            if ($warmingChoice -in @('b','c')) { return }
            if ($warmingChoice -eq 'q') { Stop-ProdicloudUiBackgroundCacheWorker; exit }
            if ($warmingChoice -eq 'r') { Request-ProdicloudUiInventoryRefresh -Force | Out-Null }
            continue
        }
        Write-Host '1. All managed resource types'
        for ($index = 0; $index -lt $types.Count; $index++) {
            Write-Host ('{0}. {1}' -f ($index + 2), [string]$types[$index].Label)
        }
        Write-Host 'b: back'
        Write-Host 'c: close inventory menu'
        Write-Host 'r: refresh managed resource cache'
        Write-Host 'q: exit'
        $choice = (Read-ProdicloudUiMenuChoice).ToLowerInvariant()
        if ($choice -in @('b','c')) { return }
        if ($choice -eq 'q') { Stop-ProdicloudUiBackgroundCacheWorker; exit }
        if ($choice -eq 'r') {
            Update-ProdicloudUiSubscription
            Request-ProdicloudUiInventoryRefresh -Force | Out-Null
            continue
        }

        $number = 0
        if (-not [int]::TryParse($choice, [ref]$number) -or $number -lt 1 -or $number -gt ($types.Count + 1)) { continue }
        $group = ''
        try {
            $groupSnapshot = Ensure-ProdicloudUiResourceCache
            $groupOptions = @([pscustomobject]@{ Value = '__all__'; Label = 'All managed resource groups'; Detail = '' })
            $groupOptions += @($groupSnapshot.Groups | Sort-Object { [string]$_.name } | ForEach-Object {
                [pscustomobject]@{ Value = [string]$_.name; Label = [string]$_.name; Detail = [string]$_.location }
            })
            $groupDefault = '__all__'
            $groupSelection = Select-ProdicloudNumberedOptionPage -Options $groupOptions -Prompt 'Filter by resource group' -DefaultValue $groupDefault -PageSize 12
            if ([string]$groupSelection.Action -eq 'back') { continue }
            if ([string]$groupSelection.Action -eq 'close') { return }
            if ([string]$groupSelection.Action -ne 'selected') { continue }
            if ([string]$groupSelection.Value -ne '__all__') { $group = [string]$groupSelection.Value }
        }
        catch {
            Write-ProdicloudUiError -ErrorRecord $_
            Wait-ProdicloudUiContinue
            continue
        }
        $typeName = if ($number -gt 1) { [string]$types[$number - 2].Id } else { '' }
        try {
            if (-not [string]::IsNullOrWhiteSpace([string]$group)) {
                $snapshot = Ensure-ProdicloudUiResourceCache
                $groupMatch = @($snapshot.Groups | Where-Object { [string]::Equals([string]$_.name, [string]$group, [System.StringComparison]::OrdinalIgnoreCase) })
                if (@($groupMatch).Count -eq 0) {
                    Write-Host ('No managed resource group named {0} exists in the current cache.' -f $group) -ForegroundColor Yellow
                    Wait-ProdicloudUiContinue
                    continue
                }
            }
            $rows = @(Get-ProdicloudUiCachedInventoryRows -TypeName $typeName -ResourceGroup $group)
            Write-Host ''
            Write-Host 'Managed Prodicloud inventory (cached snapshot):' -ForegroundColor Cyan
            if ([string]::IsNullOrWhiteSpace([string]$typeName)) { $displayTypes = @($types | ForEach-Object { [string]$_.Id }) }
            else { $displayTypes = @($typeName) }
            foreach ($displayType in @($displayTypes)) {
                $displayRows = if ([string]::IsNullOrWhiteSpace([string]$typeName)) { @(Get-ProdicloudUiCachedInventoryRows -TypeName $displayType -ResourceGroup $group) } else { @($rows) }
                Write-Host ''
                Write-Host ($displayType.ToUpperInvariant() + ':') -ForegroundColor Cyan
                if (@($displayRows).Count -eq 0) { Write-Host '- (none)' }
                else { foreach ($row in @($displayRows)) { Write-Host ('- {0}' -f [string]$row) } }
            }
            Write-Host ''
            Write-Host ('Snapshot validated: {0} UTC | resources cached: {1}' -f ([DateTime]$snapshot.LastValidatedAtUtc).ToString('u'), @($snapshot.Resources).Count) -ForegroundColor DarkGray
            Wait-ProdicloudUiContinue
        }
        catch {
            Write-ProdicloudUiError -ErrorRecord $_
            Wait-ProdicloudUiContinue
        }
    }
}

function Show-ProdicloudUiHome {
    while ($true) {
        Update-ProdicloudUiStatusPreference
        if ($script:ProdicloudUiTopStatusLinesEnabled) {
            Write-ProdicloudUiHeader -Title 'Main menu'
            Update-ProdicloudUiSubscription
        }
        else {
            Update-ProdicloudUiSubscription
            Write-ProdicloudUiHeader -Title 'Main menu'
        }
        $script:ProdicloudUiResourceCacheError = ''
        try {
            if (Test-ProdicloudUiBackgroundCacheWorkerDisabled) {
                Ensure-ProdicloudUiResourceCache | Out-Null
            }
            else {
                Import-ProdicloudUiInventoryCacheFromDisk | Out-Null
                $workerStarted = Start-ProdicloudUiBackgroundCacheWorker
                if (-not $workerStarted -and $null -ne $script:ProdicloudUiSubscription -and -not [string]::IsNullOrWhiteSpace([string]$script:ProdicloudUiResourceCacheError)) {
                    throw [string]$script:ProdicloudUiResourceCacheError
                }
            }
            Write-ProdicloudUiStatusArea
        }
        catch {
            $script:ProdicloudUiResourceCacheError = [string]$_.Exception.Message
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$script:ProdicloudUiResourceCacheError)) {
            Write-Host ('Managed resource cache unavailable: {0}' -f [string]$script:ProdicloudUiResourceCacheError) -ForegroundColor Yellow
        }
        Write-Host '1. Virtual computers'
        Write-Host '2. Managed resource inventory'
        Write-Host '3. Cloud subscriptions'
        Write-Host 'c: configure settings'
        Write-Host 'h: help'
        Write-Host 'q: exit'
        $choice = (Read-ProdicloudUiMenuChoice).ToLowerInvariant()
        switch ($choice) {
            '1' { Show-ProdicloudUiVirtualComputers }
            '2' { Show-ProdicloudUiInventoryMenu }
            '3' { Show-ProdicloudUiCloudSubscriptions }
            'c' { Invoke-ProdicloudUiCommand -CommandName 'configure' -Options @{} }
            'h' { Invoke-ProdicloudUiCommand -CommandName 'help' -Options @{} }
            'q' { return }
        }
    }
}

try { Show-ProdicloudUiHome }
finally { Reset-ProdicloudUiViewport; Stop-ProdicloudUiBackgroundCacheWorker }
