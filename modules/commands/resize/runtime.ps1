# Resize command runtime helpers.

# Handles Invoke-ClagnosResizeCommand.
function Get-ClagnosPlatformNameFromOsType {
    param(
        [string]$OsType
    )

    $osTypeText = [string]$OsType
    if ([string]::IsNullOrWhiteSpace([string]$osTypeText)) {
        return ''
    }

    $normalized = $osTypeText.Trim().ToLowerInvariant()
    switch ($normalized) {
        'windows' { return 'windows' }
        'linux' { return 'linux' }
        default { return '' }
    }
}

# Handles Test-ClagnosResizeDirectRequest.
function Test-ClagnosResizeDirectRequest {
    param(
        [hashtable]$Options
    )

    foreach ($requiredName in @('group','vm-name')) {
        if (-not (Test-ClagnosCliOptionPresent -Options $Options -Name $requiredName)) {
            return $false
        }
    }

    $hasVmSize = Test-ClagnosCliOptionPresent -Options $Options -Name 'vm-size'
    $hasDiskSize = Test-ClagnosCliOptionPresent -Options $Options -Name 'disk-size'
    $hasExpand = Get-ClagnosCliOptionBool -Options $Options -Name 'expand' -DefaultValue $false
    $hasShrink = Get-ClagnosCliOptionBool -Options $Options -Name 'shrink' -DefaultValue $false

    if ($hasVmSize) {
        $vmSizeValue = [string](Get-ClagnosCliOptionText -Options $Options -Name 'vm-size')
        return (-not [string]::IsNullOrWhiteSpace([string]$vmSizeValue))
    }

    if ($hasDiskSize -and ($hasExpand -xor $hasShrink)) {
        $diskSizeValue = [string](Get-ClagnosCliOptionText -Options $Options -Name 'disk-size')
        return (-not [string]::IsNullOrWhiteSpace([string]$diskSizeValue))
    }

    return $false
}

# Handles Resolve-ClagnosResizeTargetSize.
function Resolve-ClagnosResizeTargetSize {
    param(
        [hashtable]$Options,
        [string]$CurrentRegion,
        [string]$CurrentSize,
        [hashtable]$ConfigMap
    )

    $targetSize = [string](Get-ClagnosCliOptionText -Options $Options -Name 'vm-size')
    if (-not [string]::IsNullOrWhiteSpace([string]$targetSize)) {
        return $targetSize.Trim()
    }

    $priceHours = Get-PriceHoursFromConfig -Config $ConfigMap -DefaultHours 730
    while ($true) {
        $sizePick = Select-VmSkuInteractive -Location $CurrentRegion -DefaultVmSize $CurrentSize -PriceHours $priceHours
        if ([string]::Equals([string]$sizePick, (Get-ClagnosSkuPickerRegionBackToken), [System.StringComparison]::Ordinal)) {
            Write-Host "Resize command keeps the current region fixed. Select another VM size in the same region." -ForegroundColor Yellow
            continue
        }

        $resolvedSize = [string]$sizePick
        if (-not [string]::IsNullOrWhiteSpace([string]$resolvedSize)) {
            return $resolvedSize.Trim()
        }
    }
}

# Handles Assert-ClagnosResizePlatformExpectation.
function Assert-ClagnosResizePlatformExpectation {
    param(
        [string]$ActualPlatform,
        [switch]$WindowsFlag,
        [switch]$LinuxFlag,
        [string]$VmName,
        [string]$ResourceGroup
    )

    $expectedPlatform = ''
    if ($WindowsFlag) {
        $expectedPlatform = 'windows'
    }
    elseif ($LinuxFlag) {
        $expectedPlatform = 'linux'
    }

    if ([string]::IsNullOrWhiteSpace([string]$expectedPlatform)) {
        return
    }

    if ([string]::IsNullOrWhiteSpace([string]$ActualPlatform)) {
        Throw-FriendlyError `
            -Detail ("Resize command could not resolve the actual platform for VM '{0}' in resource group '{1}'." -f $VmName, $ResourceGroup) `
            -Code 62 `
            -Summary "Resize command cannot verify the target VM operating system." `
            -Hint "Check the VM metadata in Azure and retry without conflicting platform flags."
    }

    if (-not [string]::Equals([string]$expectedPlatform, [string]$ActualPlatform, [System.StringComparison]::OrdinalIgnoreCase)) {
        Throw-FriendlyError `
            -Detail ("Resize command expected a {0} VM, but '{1}' in resource group '{2}' is {3}." -f $expectedPlatform, $VmName, $ResourceGroup, $ActualPlatform) `
            -Code 62 `
            -Summary "Resize command platform flag does not match the target VM." `
            -Hint "Use the correct --windows or --linux flag for the existing VM, or omit the platform flag."
    }
}

function Resolve-ClagnosResizeOperationRequest {
    param(
        [hashtable]$Options
    )

    $hasVmSize = Test-ClagnosCliOptionPresent -Options $Options -Name 'vm-size'
    $hasDiskSize = Test-ClagnosCliOptionPresent -Options $Options -Name 'disk-size'
    $hasExpand = Get-ClagnosCliOptionBool -Options $Options -Name 'expand' -DefaultValue $false
    $hasShrink = Get-ClagnosCliOptionBool -Options $Options -Name 'shrink' -DefaultValue $false

    if ($hasExpand -and $hasShrink) {
        Throw-FriendlyError `
            -Detail "Options '--expand' and '--shrink' cannot be combined." `
            -Code 62 `
            -Summary "Resize command received conflicting disk intent flags." `
            -Hint "Use only one of --expand or --shrink."
    }

    if ($hasVmSize -and $hasDiskSize) {
        Throw-FriendlyError `
            -Detail "Options '--vm-size' and '--disk-size' cannot be combined." `
            -Code 62 `
            -Summary "Resize command received conflicting resize targets." `
            -Hint "Run VM SKU resize and disk-size resize as separate commands."
    }

    if (($hasExpand -or $hasShrink) -and -not $hasDiskSize) {
        Throw-FriendlyError `
            -Detail "Option '--disk-size' is required when using '--expand' or '--shrink'." `
            -Code 62 `
            -Summary "Resize command is missing the target disk size." `
            -Hint "Use --disk-size=<number>gb|mb together with --expand or --shrink."
    }

    if ($hasDiskSize -and -not ($hasExpand -or $hasShrink)) {
        Throw-FriendlyError `
            -Detail "Option '--disk-size' requires exactly one disk intent flag." `
            -Code 62 `
            -Summary "Resize command does not know whether to expand or shrink the disk." `
            -Hint "Use --disk-size=<number>gb|mb with either --expand or --shrink."
    }

    if ($hasDiskSize) {
        $diskRequest = Resolve-ClagnosResizeTargetDiskSize -Options $Options
        return [pscustomobject]@{
            Kind = 'disk'
            Intent = if ($hasExpand) { 'expand' } else { 'shrink' }
            TargetDiskSizeGb = [int]$diskRequest.TargetDiskSizeGb
            RawText = [string]$diskRequest.RawText
            Unit = [string]$diskRequest.Unit
            RequestedAmount = [int]$diskRequest.RequestedAmount
        }
    }

    return [pscustomobject]@{
        Kind = 'vm-size'
        Intent = 'vm-size'
        TargetDiskSizeGb = 0
        RawText = ''
        Unit = ''
        RequestedAmount = 0
    }
}

function Resolve-ClagnosResizeTargetDiskSize {
    param(
        [hashtable]$Options
    )

    $rawText = [string](Get-ClagnosCliOptionText -Options $Options -Name 'disk-size')
    if ([string]::IsNullOrWhiteSpace([string]$rawText)) {
        Throw-FriendlyError `
            -Detail "Option '--disk-size' requires a value." `
            -Code 62 `
            -Summary "Resize command is missing the target disk size." `
            -Hint "Use --disk-size=<number>gb|mb."
    }

    if ($rawText -notmatch '^\s*(\d+)\s*(gb|mb)\s*$') {
        Throw-FriendlyError `
            -Detail ("Option '--disk-size' received invalid value '{0}'." -f $rawText) `
            -Code 62 `
            -Summary "Resize command received an invalid disk size value." `
            -Hint "Use --disk-size=<number>gb or --disk-size=<number>mb."
    }

    $requestedAmount = [int]$Matches[1]
    $unit = ([string]$Matches[2]).Trim().ToLowerInvariant()
    if ($requestedAmount -lt 1) {
        Throw-FriendlyError `
            -Detail ("Option '--disk-size' must be greater than zero, actual '{0}'." -f $rawText) `
            -Code 62 `
            -Summary "Resize command received an invalid disk size value." `
            -Hint "Use a positive integer with gb or mb."
    }

    $targetDiskSizeGb = if ($unit -eq 'gb') { $requestedAmount } else { [int][Math]::Ceiling(($requestedAmount / 1024.0)) }
    return [pscustomobject]@{
        RawText = $rawText.Trim()
        RequestedAmount = $requestedAmount
        Unit = $unit
        TargetDiskSizeGb = $targetDiskSizeGb
    }
}

function Get-ClagnosResizeOsDiskContext {
    param(
        [psobject]$VmObject,
        [string]$ResourceGroup,
        [string]$VmName
    )

    $diskId = [string]$VmObject.storageProfile.osDisk.managedDisk.id
    if ([string]::IsNullOrWhiteSpace([string]$diskId)) {
        Throw-FriendlyError `
            -Detail ("Resize command could not resolve the managed OS disk id for VM '{0}'." -f $VmName) `
            -Code 62 `
            -Summary "Resize command cannot continue because the managed OS disk is unknown." `
            -Hint "Check the VM storage profile in Azure and retry."
    }

    $diskName = [string]$VmObject.storageProfile.osDisk.name
    if ([string]::IsNullOrWhiteSpace([string]$diskName)) {
        $diskNameParts = @($diskId -split '/')
        if (@($diskNameParts).Count -gt 0) {
            $diskName = [string]$diskNameParts[@($diskNameParts).Count - 1]
        }
    }

    $diskJson = az disk show --ids $diskId -o json --only-show-errors
    Assert-LastExitCode "az disk show (resize os disk)"
    $diskObject = ConvertFrom-JsonCompat -InputObject $diskJson
    if ($null -eq $diskObject) {
        throw "Managed OS disk metadata could not be parsed."
    }

    $diskSizeGbText = [string]$diskObject.diskSizeGb
    if (-not ($diskSizeGbText -match '^\d+$')) {
        Throw-FriendlyError `
            -Detail ("Managed OS disk '{0}' does not report a valid diskSizeGb value." -f $diskName) `
            -Code 62 `
            -Summary "Resize command cannot continue because current disk size is unknown." `
            -Hint "Check the managed disk metadata in Azure, then retry."
    }

    return [pscustomobject]@{
        DiskId = $diskId
        DiskName = $diskName
        DiskSizeGb = [int]$diskSizeGbText
        SkuName = [string]$diskObject.sku.name
    }
}

# Handles Get-ClagnosResizeVmSizeReadback.
function Get-ClagnosResizeVmSizeReadback {
    param(
        [string]$ResourceGroup,
        [string]$VmName
    )

    Write-ClagnosActionProgress -Action ("verify requested VM size for '{0}'" -f [string]$VmName)
    $sizeText = [string](az vm show -g $ResourceGroup -n $VmName --query 'hardwareProfile.vmSize' -o tsv --only-show-errors)
    Assert-LastExitCode 'az vm show (resize verification)'
    if ([string]::IsNullOrWhiteSpace([string]$sizeText)) {
        Throw-FriendlyError `
            -Detail ("Azure returned an empty VM size for '{0}' in '{1}' after resize." -f $VmName, $ResourceGroup) `
            -Code 62 `
            -Summary "Resize command could not verify the resulting VM size." `
            -Hint "Run clagnos show for the target VM and inspect its current hardware profile."
    }

    return $sizeText.Trim()
}

# Handles Get-ClagnosResizeDiskSizeReadback.
function Get-ClagnosResizeDiskSizeReadback {
    param(
        [string]$DiskId,
        [string]$DiskName
    )

    Write-ClagnosActionProgress -Action ("verify requested OS disk size for '{0}'" -f [string]$DiskName)
    $sizeText = [string](az disk show --ids $DiskId --query 'diskSizeGb' -o tsv --only-show-errors)
    Assert-LastExitCode 'az disk show (resize verification)'
    $sizeGb = 0
    if (-not [int]::TryParse([string]$sizeText, [ref]$sizeGb) -or $sizeGb -lt 1) {
        Throw-FriendlyError `
            -Detail ("Azure returned an invalid diskSizeGb value '{0}' for managed disk '{1}' after resize." -f $sizeText, $DiskName) `
            -Code 62 `
            -Summary "Resize command could not verify the resulting OS disk size." `
            -Hint "Run clagnos component --action=show --type=disk --name=<disk-name> and inspect the disk metadata."
    }

    return [int]$sizeGb
}

# Handles Get-ClagnosResizeLifecycleSnapshot.
function Get-ClagnosResizeLifecycleSnapshot {
    param(
        [string]$ResourceGroup,
        [string]$VmName,
        [string]$Stage
    )

    Write-ClagnosActionProgress -Action ("read {0} lifecycle snapshot for '{1}'" -f [string]$Stage, [string]$VmName)
    try {
        return (Get-ClagnosVmLifecycleSnapshot -ResourceGroup $ResourceGroup -VmName $VmName)
    }
    catch {
        Write-Warning ("Resize {0} lifecycle snapshot is unavailable: {1}" -f [string]$Stage, [string]$_.Exception.Message)
        return $null
    }
}

# Handles Write-ClagnosResizeStateSnapshot.
function Write-ClagnosResizeStateSnapshot {
    param(
        [string]$Stage,
        [string]$VmName,
        [string]$ResourceGroup,
        [string]$Region,
        [string]$VmSize,
        [string]$DiskName = '',
        [int]$DiskSizeGb = 0,
        [psobject]$LifecycleSnapshot = $null
    )

    $diskText = if ([string]::IsNullOrWhiteSpace([string]$DiskName)) { '(unchanged)' } else { ("{0}={1} GB" -f [string]$DiskName, [int]$DiskSizeGb) }
    $lifecycleText = if ($null -eq $LifecycleSnapshot) { 'lifecycle=(snapshot unavailable)' } else { Format-ClagnosVmLifecycleSummaryText -Snapshot $LifecycleSnapshot }
    Write-Host ("Resize {0} state snapshot: VM={1}/{2}; region={3}; size={4}; OS disk={5}; {6}" -f [string]$Stage, [string]$ResourceGroup, [string]$VmName, [string]$Region, [string]$VmSize, [string]$diskText, [string]$lifecycleText) -ForegroundColor DarkCyan
}

# Handles Assert-ClagnosResizeReadback.
function Assert-ClagnosResizeReadback {
    param(
        [ValidateSet('vm-size','disk-size')]
        [string]$Kind,
        [string]$ExpectedValue,
        [string]$ActualValue,
        [string]$ResourceGroup,
        [string]$VmName,
        [psobject]$LifecycleSnapshot = $null
    )

    if ([string]::Equals([string]$ExpectedValue, [string]$ActualValue, [System.StringComparison]::OrdinalIgnoreCase)) {
        return
    }

    $stateText = if ($null -eq $LifecycleSnapshot) { 'lifecycle=(snapshot unavailable)' } else { Format-ClagnosVmLifecycleSummaryText -Snapshot $LifecycleSnapshot }
    $resourceLabel = if ($Kind -eq 'vm-size') { 'VM size' } else { 'OS disk size (GB)' }
    Throw-FriendlyError `
        -Detail ("Resize readback mismatch for VM '{0}' in '{1}': expected {2}='{3}', actual='{4}'. {5}" -f $VmName, $ResourceGroup, $resourceLabel, $ExpectedValue, $ActualValue, $stateText) `
        -Code 62 `
        -Summary ("Resize command could not verify the requested {0}." -f $resourceLabel) `
        -Hint "Inspect the reported target state before retrying. The VM was started after the Azure resize request; no automatic rollback was attempted."
}

function Show-ClagnosResizeShrinkAlternatives {
    Write-Host "Supported alternatives for a smaller OS disk:" -ForegroundColor Cyan
    Write-Host "1. Create a new VM with the desired smaller OS disk size and migrate the workload."
    Write-Host "2. Move large data, caches, package stores, and build artifacts off the OS disk before rebuild."
    Write-Host "3. Place durable application data on separate data disks so future OS-disk rebuilds stay smaller."
    Write-Host "4. Use backup, image, or redeployment workflows to rebuild onto a right-sized VM instead of trying in-place shrink."
}
