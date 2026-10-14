[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SubscriptionId,
    [Parameter(Mandatory = $true)][string]$CachePath,
    [Parameter(Mandatory = $true)][string]$StatusPath,
    [Parameter(Mandatory = $true)][string]$RequestPath,
    [Parameter(Mandatory = $true)][string]$PackageRequestPath,
    [Parameter(Mandatory = $true)][string]$StopPath,
    [Parameter(Mandatory = $true)][int]$OwnerProcessId,
    [Parameter(Mandatory = $true)][string]$RepositoryRoot,
    [ValidateRange(15, 3600)][int]$RefreshIntervalSeconds = 60,
    [switch]$Once
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Write-ClagnosWorkerJsonAtomically {
    param([string]$Path, [object]$Value)

    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    $temporaryPath = '{0}.{1}.{2}.tmp' -f $Path, $PID, [Guid]::NewGuid().ToString('N')
    $json = ConvertTo-Json -InputObject $Value -Depth 100 -Compress
    Set-Content -LiteralPath $temporaryPath -Value $json -Encoding UTF8
    try {
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            try { [System.IO.File]::Replace($temporaryPath, $Path, $null) }
            catch { Move-Item -LiteralPath $temporaryPath -Destination $Path -Force }
        }
        else {
            Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
        }
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue }
    }
}

function Write-ClagnosWorkerStatus {
    param([string]$State, [string]$Message, [string]$LastSuccessfulAtUtc = '')

    Write-ClagnosWorkerJsonAtomically -Path $StatusPath -Value ([ordered]@{
        State = $State
        Message = $Message
        UpdatedAtUtc = [DateTime]::UtcNow.ToString('o')
        LastSuccessfulAtUtc = $LastSuccessfulAtUtc
    })
}

function ConvertTo-ClagnosWorkerUtcDateTime {
    param([Parameter(Mandatory = $true)][object]$Value)

    if ($Value -is [DateTime]) { return ([DateTime]$Value).ToUniversalTime() }
    return [DateTime]::Parse([string]$Value,[System.Globalization.CultureInfo]::InvariantCulture,[System.Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
}

function Get-ClagnosWorkerResourceGroup {
    param([psobject]$Resource)

    if (-not [string]::IsNullOrWhiteSpace([string]$Resource.resourceGroup)) { return [string]$Resource.resourceGroup }
    if ([string]$Resource.id -match '(?i)/resourceGroups/([^/]+)') { return [string]$Matches[1] }
    return ''
}

function Get-ClagnosWorkerTag {
    param([psobject]$Group, [string]$Name)

    if ($null -eq $Group -or $null -eq $Group.tags) { return '' }
    $property = @($Group.tags.PSObject.Properties | Where-Object { [string]::Equals([string]$_.Name, $Name, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
    if ($property.Count -eq 0) { return '' }
    return [string]$property[0].Value
}

function Get-ClagnosWorkerJsonRows {
    param([string[]]$Arguments, [string]$Doing)

    Write-ClagnosWorkerStatus -State 'refreshing' -Message ('Doing: {0}' -f $Doing) -LastSuccessfulAtUtc $script:LastSuccessfulAtUtc
    $azArguments = @($Arguments) + @('--subscription', $SubscriptionId, '-o', 'json', '--only-show-errors')
    $json = & az @azArguments 2>$null
    if ($LASTEXITCODE -ne 0) { throw ('Azure CLI read failed: az {0}' -f ($Arguments -join ' ')) }
    if ([string]::IsNullOrWhiteSpace([string]$json)) { return }
    # Windows PowerShell 5.1 preserves a JSON root array as one pipeline object
    # when it is wrapped directly in @(...). Emit each decoded row explicitly
    # so callers always receive a flat list of Azure resource objects.
    $parsed = ConvertFrom-Json -InputObject ([string]$json)
    if ($null -eq $parsed) { return }
    if ($parsed -is [System.Array]) {
        foreach ($row in $parsed) { Write-Output -NoEnumerate $row }
        return
    }
    Write-Output -NoEnumerate $parsed
}

function Get-ClagnosWorkerSnapshotSignature {
    param([object[]]$Groups, [object[]]$Resources, [object[]]$VirtualMachines)

    $lines = New-Object 'System.Collections.Generic.List[string]'
    foreach ($group in @($Groups | Sort-Object { [string]$_.id })) {
        $tags = if ($null -ne $group.tags) { @($group.tags.PSObject.Properties | Sort-Object Name | ForEach-Object { '{0}={1}' -f [string]$_.Name,[string]$_.Value }) -join ';' } else { '' }
        $fallback = if ([string]::IsNullOrWhiteSpace([string]$group.etag)) { ConvertTo-Json -InputObject $group -Depth 100 -Compress } else { '' }
        $lines.Add(('group|{0}|{1}|{2}|{3}|{4}|{5}|{6}' -f [string]$group.id,[string]$group.name,[string]$group.etag,[string]$group.location,[string]$group.properties.provisioningState,$tags,$fallback))
    }
    foreach ($resource in @($Resources | Sort-Object { [string]$_.id })) {
        $fallback = if ([string]::IsNullOrWhiteSpace([string]$resource.etag)) { ConvertTo-Json -InputObject $resource -Depth 100 -Compress } else { '' }
        $lines.Add(('resource|{0}|{1}|{2}|{3}|{4}|{5}' -f [string]$resource.id,[string]$resource.type,[string]$resource.etag,(Get-ClagnosWorkerResourceGroup -Resource $resource),[string]$resource.properties.provisioningState,$fallback))
    }
    foreach ($vm in @($VirtualMachines | Sort-Object { [string]$_.id })) {
        $fallback = if ([string]::IsNullOrWhiteSpace([string]$vm.etag)) { ConvertTo-Json -InputObject $vm -Depth 100 -Compress } else { '' }
        $lines.Add(('vm|{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}|{9}' -f [string]$vm.id,[string]$vm.etag,(Get-ClagnosWorkerResourceGroup -Resource $vm),[string]$vm.hardwareProfile.vmSize,[string]$vm.powerState,[string]$vm.provisioningState,[string]$vm.privateIps,[string]$vm.publicIps,[string]$vm.fqdns,$fallback))
    }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($lines.ToArray() -join "`n"))
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Invoke-ClagnosWorkerInventoryRefresh {
    $scanStartedAtUtc = [DateTime]::UtcNow
    $allGroups = @(Get-ClagnosWorkerJsonRows -Arguments @('group','list') -Doing 'list resource groups')
    $groups = @($allGroups | Where-Object { (Get-ClagnosWorkerTag -Group $_ -Name 'managed-by') -in @('clagnos','az-vm') } | Sort-Object { [string]$_.name })
    $groupMap = @{}
    foreach ($group in @($groups)) { $groupMap[[string]$group.name.ToLowerInvariant()] = $true }

    $resources = @()
    foreach ($group in @($groups)) {
        $groupName = [string]$group.name
        $groupResources = @(Get-ClagnosWorkerJsonRows -Arguments @('resource','list','--resource-group',$groupName) -Doing ('list resources in {0}' -f $groupName))
        $resources += @($groupResources | Where-Object {
            $resourceGroup = Get-ClagnosWorkerResourceGroup -Resource $_
            [string]::IsNullOrWhiteSpace([string]$resourceGroup) -or [string]::Equals([string]$resourceGroup,$groupName,[System.StringComparison]::OrdinalIgnoreCase)
        })
    }
    $resources = @($resources | Sort-Object { [string]$_.id })

    $allVms = @()
    if (@($groups).Count -gt 0) {
        $allVms = @(Get-ClagnosWorkerJsonRows -Arguments @('vm','list','--show-details') -Doing 'list VM details and power states')
    }
    $vms = @($allVms | Where-Object {
        $groupName = Get-ClagnosWorkerResourceGroup -Resource $_
        -not [string]::IsNullOrWhiteSpace([string]$groupName) -and $groupMap.ContainsKey([string]$groupName.ToLowerInvariant())
    } | Sort-Object { [string]$_.name }, { Get-ClagnosWorkerResourceGroup -Resource $_ })
    foreach ($vm in @($vms)) {
        $groupName = Get-ClagnosWorkerResourceGroup -Resource $vm
        $vm | Add-Member -NotePropertyName 'ClagnosResourceGroup' -NotePropertyValue $groupName -Force
        $vm | Add-Member -NotePropertyName 'ClagnosSubscriptionId' -NotePropertyValue $SubscriptionId -Force
    }

    $signature = Get-ClagnosWorkerSnapshotSignature -Groups $groups -Resources $resources -VirtualMachines $vms
    $previous = $null
    if (Test-Path -LiteralPath $CachePath -PathType Leaf) {
        try { $previous = ConvertFrom-Json -InputObject ([string](Get-Content -LiteralPath $CachePath -Raw)) } catch { $previous = $null }
    }

    # If a mutation requested another refresh while this scan was running,
    # discard this potentially mid-operation snapshot and retry immediately.
    if (Test-Path -LiteralPath $RequestPath -PathType Leaf) {
        $requestText = [string](Get-Content -LiteralPath $RequestPath -Raw -ErrorAction SilentlyContinue)
        $requestTime = [DateTime]::MinValue
        if ([DateTime]::TryParse($requestText,[System.Globalization.CultureInfo]::InvariantCulture,[System.Globalization.DateTimeStyles]::RoundtripKind,[ref]$requestTime) -and $requestTime.ToUniversalTime() -gt $scanStartedAtUtc) { return $false }
    }

    $changed = $null -eq $previous -or -not [string]::Equals([string]$previous.Signature,$signature,[System.StringComparison]::Ordinal)
    $snapshot = [ordered]@{
        SubscriptionId = $SubscriptionId
        Groups = @($groups)
        Resources = @($resources)
        VirtualMachines = @($vms)
        Signature = $signature
        LastValidatedAtUtc = [DateTime]::UtcNow.ToString('o')
        IsDirty = $false
        DirtyReason = ''
        DirtyResourceGroup = ''
        Changed = [bool]$changed
    }
    Write-ClagnosWorkerJsonAtomically -Path $CachePath -Value $snapshot
    $script:LastSuccessfulAtUtc = [string]$snapshot.LastValidatedAtUtc
    Write-ClagnosWorkerStatus -State 'ready' -Message ($(if ($changed) { 'Inventory snapshot updated.' } else { 'Inventory snapshot is current.' })) -LastSuccessfulAtUtc $script:LastSuccessfulAtUtc

    if (Test-Path -LiteralPath $RequestPath -PathType Leaf) {
        $requestText = [string](Get-Content -LiteralPath $RequestPath -Raw -ErrorAction SilentlyContinue)
        $requestTime = [DateTime]::MinValue
        if ([DateTime]::TryParse($requestText,[ref]$requestTime) -and $requestTime.ToUniversalTime() -le $scanStartedAtUtc) {
            Remove-Item -LiteralPath $RequestPath -Force -ErrorAction SilentlyContinue
        }
    }
    return $true
}

function Test-ClagnosWorkerOwner {
    try { return ($null -ne (Get-Process -Id $OwnerProcessId -ErrorAction Stop)) }
    catch { return $false }
}

function Get-ClagnosUiInventorySnapshotForSharedRuntime {
    param([int]$MaximumAgeSeconds = 30, [string]$SubscriptionId = '')
    if ($null -eq $script:ClagnosUiInventoryCache -or [bool]$script:ClagnosUiInventoryCache.IsDirty) { return $null }
    if (-not [string]::IsNullOrWhiteSpace($SubscriptionId) -and -not [string]::Equals([string]$script:ClagnosUiInventoryCache.SubscriptionId,$SubscriptionId,[System.StringComparison]::OrdinalIgnoreCase)) { return $null }
    try {
        if (([DateTime]::UtcNow - [DateTime]$script:ClagnosUiInventoryCache.LastValidatedAtUtc).TotalSeconds -gt $MaximumAgeSeconds) { return $null }
    }
    catch { return $null }
    return $script:ClagnosUiInventoryCache
}

function Test-ClagnosWorkerPackageRequestSuperseded {
    param([DateTime]$RequestStartedAtUtc)
    if (-not (Test-Path -LiteralPath $PackageRequestPath -PathType Leaf)) { return $false }
    try {
        $newRequest = ConvertFrom-Json -InputObject ([string](Get-Content -LiteralPath $PackageRequestPath -Raw -ErrorAction Stop))
        $newRequestTime = ConvertTo-ClagnosWorkerUtcDateTime -Value $newRequest.RequestedAtUtc
        return ($newRequestTime -gt $RequestStartedAtUtc)
    }
    catch { return $true }
}

function Invoke-ClagnosWorkerPackageStatusRequest {
    if ([string]::IsNullOrWhiteSpace($PackageRequestPath) -or -not (Test-Path -LiteralPath $PackageRequestPath -PathType Leaf)) { return $false }
    $requestPath = '{0}.{1}.processing' -f $PackageRequestPath,$PID
    try { Move-Item -LiteralPath $PackageRequestPath -Destination $requestPath -Force -ErrorAction Stop }
    catch { return $false }
    try {
        $request = ConvertFrom-Json -InputObject ([string](Get-Content -LiteralPath $requestPath -Raw -ErrorAction Stop))
        if (-not [string]::Equals([string]$request.SubscriptionId,$SubscriptionId,[System.StringComparison]::OrdinalIgnoreCase)) { return $true }
        $requestStartedAtUtc = ConvertTo-ClagnosWorkerUtcDateTime -Value $request.RequestedAtUtc
        Write-ClagnosWorkerStatus -State 'refreshing' -Message ('Doing: refresh package status on {0}' -f [string]$request.VmName) -LastSuccessfulAtUtc $script:LastSuccessfulAtUtc

        $inventory = $null
        if (Test-Path -LiteralPath $CachePath -PathType Leaf) {
            try { $inventory = ConvertFrom-Json -InputObject ([string](Get-Content -LiteralPath $CachePath -Raw -ErrorAction Stop)) } catch { $inventory = $null }
        }
        if ($null -eq $inventory -or -not [string]::Equals([string]$inventory.SubscriptionId,$SubscriptionId,[System.StringComparison]::OrdinalIgnoreCase)) { throw 'The current managed VM inventory snapshot is not ready for package status warming.' }
        try {
            $inventoryAge = ([DateTime]::UtcNow - (ConvertTo-ClagnosWorkerUtcDateTime -Value $inventory.LastValidatedAtUtc)).TotalSeconds
            if ($inventoryAge -gt 300 -or [bool]$inventory.IsDirty) { throw 'The managed VM inventory snapshot is too old for package status warming.' }
        }
        catch { throw 'The managed VM inventory snapshot is too old or invalid for package status warming.' }

        $runtimePath = Join-Path $RepositoryRoot 'clagnos.ps1'
        . $runtimePath
        $script:ConfigOverrides['SELECTED_AZURE_SUBSCRIPTION_ID'] = $SubscriptionId
        $script:ClagnosUiInventoryCache = $inventory
        Set-ClagnosResolvedSubscriptionContext -SubscriptionId $SubscriptionId -SubscriptionName '' -TenantId '' -ResolutionSource 'background-cache-worker'
        $platform = ([string]$request.Platform).ToLowerInvariant()
        if ($platform -notin @('windows','linux')) { throw 'Package status worker received an unsupported guest platform.' }
        $isWindows = $platform -eq 'windows'
        $runtime = Initialize-ClagnosTaskExecutionRuntimeContext -AutoMode:$false -WindowsFlag:$isWindows -LinuxFlag:(-not $isWindows)
        $target = [pscustomobject]@{ ResourceGroup = [string]$request.ResourceGroup; VmName = [string]$request.VmName }
        $options = @{ 'subscription-id' = $SubscriptionId; group = [string]$request.ResourceGroup; 'vm-name' = [string]$request.VmName }
        $previousNoDiskWrite = [string]$env:CLAGNOS_PACKAGE_STATUS_CACHE_NO_DISK_WRITE
        $env:CLAGNOS_PACKAGE_STATUS_CACHE_NO_DISK_WRITE = '1'
        foreach ($catalog in @($request.Catalogs)) {
            if ([string]$catalog -notin @('builtin','custom')) { continue }
            $packages = @(Get-ClagnosPackageCatalog -Platform $platform -Catalog ([string]$catalog))
            if (@($packages).Count -eq 0) { continue }
            Get-ClagnosPackageStatusSnapshot -Packages $packages -Options $options -Platform $platform -Force -Runtime $runtime -Target $target | Out-Null
            if (Test-ClagnosWorkerPackageRequestSuperseded -RequestStartedAtUtc $requestStartedAtUtc) { return $true }
            $cacheKey = Get-ClagnosPackageStatusCacheKey -Packages $packages -Options $options -Platform $platform
            $cacheEntry = Get-ClagnosPackageStatusCacheEntry -Packages $packages -Options $options -Platform $platform
            if ($null -ne $cacheEntry) {
                $env:CLAGNOS_PACKAGE_STATUS_CACHE_NO_DISK_WRITE = $previousNoDiskWrite
                Save-ClagnosPackageStatusCacheEntry -Key $cacheKey -Entry $cacheEntry.Entry
                $env:CLAGNOS_PACKAGE_STATUS_CACHE_NO_DISK_WRITE = '1'
            }
        }
        $env:CLAGNOS_PACKAGE_STATUS_CACHE_NO_DISK_WRITE = $previousNoDiskWrite
        Write-ClagnosWorkerStatus -State 'ready' -Message ('Package status refreshed for {0}.' -f [string]$request.VmName) -LastSuccessfulAtUtc $script:LastSuccessfulAtUtc
        return $true
    }
    catch {
        Write-ClagnosWorkerStatus -State 'error' -Message ('Package status refresh failed: {0}' -f [string]$_.Exception.Message) -LastSuccessfulAtUtc $script:LastSuccessfulAtUtc
        return $true
    }
    finally {
        if ($null -ne $previousNoDiskWrite) { $env:CLAGNOS_PACKAGE_STATUS_CACHE_NO_DISK_WRITE = $previousNoDiskWrite }
        else { Remove-Item Env:\CLAGNOS_PACKAGE_STATUS_CACHE_NO_DISK_WRITE -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $requestPath) { Remove-Item -LiteralPath $requestPath -Force -ErrorAction SilentlyContinue }
    }
}

$script:LastSuccessfulAtUtc = ''
$script:InventoryRefreshFailureCount = 0
$script:NextInventoryRefreshAttemptAtUtc = [DateTime]::MinValue
$script:WorkerLockStream = $null
$workerLockPath = $CachePath + '.worker.lock'
try {
    $script:WorkerLockStream = [System.IO.File]::Open($workerLockPath,[System.IO.FileMode]::OpenOrCreate,[System.IO.FileAccess]::ReadWrite,[System.IO.FileShare]::None)
}
catch {
    # Another TUI instance already owns this subscription's worker. Let it
    # keep the shared cache warm rather than duplicating Azure list traffic.
    exit 0
}
if (Test-Path -LiteralPath $CachePath -PathType Leaf) {
    try { $script:LastSuccessfulAtUtc = [string](ConvertFrom-Json -InputObject ([string](Get-Content -LiteralPath $CachePath -Raw))).LastValidatedAtUtc } catch { }
}

try {
    while ($true) {
        if ($Once) {
            Invoke-ClagnosWorkerInventoryRefresh | Out-Null
            break
        }
        if ((Test-Path -LiteralPath $StopPath -PathType Leaf) -or -not (Test-ClagnosWorkerOwner)) { break }
        $forceRefresh = Test-Path -LiteralPath $RequestPath -PathType Leaf
        $cacheAge = [double]::PositiveInfinity
        if (Test-Path -LiteralPath $CachePath -PathType Leaf) {
            try {
                $cached = ConvertFrom-Json -InputObject ([string](Get-Content -LiteralPath $CachePath -Raw))
                $cacheAge = ([DateTime]::UtcNow - (ConvertTo-ClagnosWorkerUtcDateTime -Value $cached.LastValidatedAtUtc)).TotalSeconds
            }
            catch { $cacheAge = [double]::PositiveInfinity }
        }
        $refreshDue = $forceRefresh -or $cacheAge -ge $RefreshIntervalSeconds
        if ($refreshDue -and [DateTime]::UtcNow -ge $script:NextInventoryRefreshAttemptAtUtc) {
            try {
                $refreshCompleted = [bool](Invoke-ClagnosWorkerInventoryRefresh)
                if ($refreshCompleted) {
                    $script:InventoryRefreshFailureCount = 0
                    $script:NextInventoryRefreshAttemptAtUtc = [DateTime]::MinValue
                }
            }
            catch {
                $script:InventoryRefreshFailureCount++
                $backoffExponent = [Math]::Min(([int]$script:InventoryRefreshFailureCount - 1),4)
                $backoffSeconds = [int][Math]::Min(60,(5 * [Math]::Pow(2,$backoffExponent)))
                $script:NextInventoryRefreshAttemptAtUtc = [DateTime]::UtcNow.AddSeconds($backoffSeconds)
                Write-ClagnosWorkerStatus -State 'error' -Message ('{0} (retry in {1}s)' -f [string]$_.Exception.Message,$backoffSeconds) -LastSuccessfulAtUtc $script:LastSuccessfulAtUtc
            }
            continue
        }
        if (Invoke-ClagnosWorkerPackageStatusRequest) { continue }
        Start-Sleep -Seconds 2
    }
}
catch {
    try { Write-ClagnosWorkerStatus -State 'error' -Message ([string]$_.Exception.Message) -LastSuccessfulAtUtc $script:LastSuccessfulAtUtc } catch { }
    if ($Once) { throw }
}
finally {
    if (Test-Path -LiteralPath $StopPath -PathType Leaf) { Remove-Item -LiteralPath $StopPath -Force -ErrorAction SilentlyContinue }
    if ($null -ne $script:WorkerLockStream) { $script:WorkerLockStream.Dispose(); $script:WorkerLockStream = $null }
}
