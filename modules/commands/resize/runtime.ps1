# Resize command runtime helpers.

# Handles Invoke-ProdicloudResizeCommand.
function Get-ProdicloudPlatformNameFromOsType {
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

function Get-ProdicloudResizePerformanceProfile {
    return [pscustomobject]@{
        HelperVmSize = 'Standard_D8ds_v5'
        HelperOsDiskSizeGb = 128
        HelperOsDiskSku = 'StandardSSD_LRS'
        TransferDiskSku = 'Premium_LRS'
        TransferDiskTier = 'P40'
        TransferDiskIops = 7500
        TransferDiskThroughputMbps = 250
        HelperUncachedDiskIops = 12800
        HelperUncachedDiskThroughputMbps = 290
    }
}

function Write-ProdicloudResizePerformancePlan {
    param([int]$SourceDiskSizeGb,[int]$TargetDiskSizeGb)
    $resizeProfile = Get-ProdicloudResizePerformanceProfile
    $payloadCeilingMbps = [Math]::Min([double]$resizeProfile.TransferDiskThroughputMbps,([double]$resizeProfile.HelperUncachedDiskThroughputMbps / 2))
    $combinedDiskIops = [int]$resizeProfile.TransferDiskIops * 2
    Write-Host ("Shrink performance plan: source clone={0} GiB {1}/{2}; replacement={3} GiB {1}/{2}; disks={4} IOPS and {5} MB/s each; helper={6} ({7} uncached IOPS, {8} MB/s), OS={9} GiB {10} with no tier update. Estimated payload ceiling=min({5},{5},{8}/2)={11} MB/s; combined disk IOPS={12}/{7}. These are Azure hardware limits, not a throughput guarantee." -f $SourceDiskSizeGb,$resizeProfile.TransferDiskSku,$resizeProfile.TransferDiskTier,$TargetDiskSizeGb,$resizeProfile.TransferDiskIops,$resizeProfile.TransferDiskThroughputMbps,$resizeProfile.HelperVmSize,$resizeProfile.HelperUncachedDiskIops,$resizeProfile.HelperUncachedDiskThroughputMbps,$resizeProfile.HelperOsDiskSizeGb,$resizeProfile.HelperOsDiskSku,$payloadCeilingMbps,$combinedDiskIops) -ForegroundColor DarkCyan
}

# Handles Test-ProdicloudResizeDirectRequest.
function Test-ProdicloudResizeDirectRequest {
    param(
        [hashtable]$Options
    )

    foreach ($requiredName in @('group','vm-name')) {
        if (-not (Test-ProdicloudCliOptionPresent -Options $Options -Name $requiredName)) {
            return $false
        }
    }

    $hasVmSize = Test-ProdicloudCliOptionPresent -Options $Options -Name 'vm-size'
    $hasDiskSize = Test-ProdicloudCliOptionPresent -Options $Options -Name 'disk-size'
    $hasExpand = Get-ProdicloudCliOptionBool -Options $Options -Name 'expand' -DefaultValue $false
    $hasShrink = Get-ProdicloudCliOptionBool -Options $Options -Name 'shrink' -DefaultValue $false

    if ($hasVmSize) {
        $vmSizeValue = [string](Get-ProdicloudCliOptionText -Options $Options -Name 'vm-size')
        return (-not [string]::IsNullOrWhiteSpace([string]$vmSizeValue))
    }

    if ($hasDiskSize -and ($hasExpand -xor $hasShrink)) {
        $diskSizeValue = [string](Get-ProdicloudCliOptionText -Options $Options -Name 'disk-size')
        return (-not [string]::IsNullOrWhiteSpace([string]$diskSizeValue))
    }

    return $false
}

# Handles Resolve-ProdicloudResizeTargetSize.
function Resolve-ProdicloudResizeTargetSize {
    param(
        [hashtable]$Options,
        [string]$CurrentRegion,
        [string]$CurrentSize,
        [hashtable]$ConfigMap
    )

    $targetSize = [string](Get-ProdicloudCliOptionText -Options $Options -Name 'vm-size')
    if (-not [string]::IsNullOrWhiteSpace([string]$targetSize)) {
        return $targetSize.Trim()
    }

    $priceHours = Get-PriceHoursFromConfig -Config $ConfigMap -DefaultHours 730
    while ($true) {
        $sizePick = Select-VmSkuInteractive -Location $CurrentRegion -DefaultVmSize $CurrentSize -PriceHours $priceHours
        if ([string]::Equals([string]$sizePick, (Get-ProdicloudSkuPickerRegionBackToken), [System.StringComparison]::Ordinal)) {
            Write-Host "Resize command keeps the current region fixed. Select another VM size in the same region." -ForegroundColor Yellow
            continue
        }

        $resolvedSize = [string]$sizePick
        if (-not [string]::IsNullOrWhiteSpace([string]$resolvedSize)) {
            return $resolvedSize.Trim()
        }
    }
}

# Handles Assert-ProdicloudResizePlatformExpectation.
function Assert-ProdicloudResizePlatformExpectation {
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

function Resolve-ProdicloudResizeOperationRequest {
    param(
        [hashtable]$Options
    )

    $hasVmSize = Test-ProdicloudCliOptionPresent -Options $Options -Name 'vm-size'
    $hasDiskName = Test-ProdicloudCliOptionPresent -Options $Options -Name 'disk-name'
    $hasDiskSize = Test-ProdicloudCliOptionPresent -Options $Options -Name 'disk-size'
    $hasExpand = Get-ProdicloudCliOptionBool -Options $Options -Name 'expand' -DefaultValue $false
    $hasShrink = Get-ProdicloudCliOptionBool -Options $Options -Name 'shrink' -DefaultValue $false

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
    if ($hasDiskName -and -not $hasDiskSize) {
        Throw-FriendlyError `
            -Detail "Option '--disk-name' requires '--disk-size' with exactly one disk intent flag." `
            -Code 62 `
            -Summary "Resize command received a disk name without a resize request." `
            -Hint "Use --disk-name <managed-disk> --disk-size <size> with --expand or --shrink."
    }
    if ($hasVmSize -and $hasDiskName) {
        Throw-FriendlyError `
            -Detail "Options '--vm-size' and '--disk-name' cannot be combined." `
            -Code 62 `
            -Summary "Resize command received conflicting resize targets." `
            -Hint "Run VM hardware resize and disk resize as separate commands."
    }

    if (($hasExpand -or $hasShrink) -and -not $hasDiskSize) {
        Throw-FriendlyError `
            -Detail "Option '--disk-size' is required when using '--expand' or '--shrink'." `
            -Code 62 `
            -Summary "Resize command is missing the target disk size." `
            -Hint "Use --disk-size=<size>MB|GB|TB together with --expand or --shrink, for example 128GB or 1TB."
    }

    if ($hasDiskSize -and -not ($hasExpand -or $hasShrink)) {
        Throw-FriendlyError `
            -Detail "Option '--disk-size' requires exactly one disk intent flag." `
            -Code 62 `
            -Summary "Resize command does not know whether to expand or shrink the disk." `
            -Hint "Use --disk-size=<size>MB|GB|TB with either --expand or --shrink."
    }

    if ($hasDiskSize) {
        $maximumDiskSizeGb = 4095
        $diskRequest = Resolve-ProdicloudResizeTargetDiskSize -Options $Options -MaximumDiskSizeGb $maximumDiskSizeGb
        return [pscustomobject]@{
            Kind = 'disk'
            DiskName = [string](Get-ProdicloudCliOptionText -Options $Options -Name 'disk-name')
            Intent = if ($hasExpand) { 'expand' } else { 'shrink' }
            TargetDiskSizeGb = [int]$diskRequest.TargetDiskSizeGb
            RawText = [string]$diskRequest.RawText
            Unit = [string]$diskRequest.Unit
            RequestedAmount = [double]$diskRequest.RequestedAmount
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

function Resolve-ProdicloudResizeTargetDiskSize {
    param(
        [hashtable]$Options,
        [ValidateRange(1,65536)][int]$MaximumDiskSizeGb = 4095,
        [string]$FieldName = 'managed disk size'
    )

    $rawText = [string](Get-ProdicloudCliOptionText -Options $Options -Name 'disk-size')
    if ([string]::IsNullOrWhiteSpace([string]$rawText)) {
        Throw-FriendlyError `
            -Detail "Option '--disk-size' requires a value." `
            -Code 62 `
            -Summary "Resize command is missing the target disk size." `
            -Hint "Use --disk-size=<size>MB|GB|TB, such as 128GB or 1TB."
    }

    try {
        if ($MaximumDiskSizeGb -le 4095) {
            $targetDiskSizeGb = [int](ConvertTo-ProdicloudOsDiskSizeGb -Value $rawText -FieldName $FieldName)
        }
        else {
            $sizeMatch = [regex]::Match($rawText.Trim(), '^(?<amount>\d+(?:\.\d+)?)\s*(?<unit>mb|gb|tb)?$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            if (-not $sizeMatch.Success) { throw ("{0} '{1}' is invalid. Use a positive number with MB, GB, or TB." -f $FieldName,$rawText) }
            $amount = 0.0
            if (-not [double]::TryParse([string]$sizeMatch.Groups['amount'].Value,[System.Globalization.NumberStyles]::AllowDecimalPoint,[System.Globalization.CultureInfo]::InvariantCulture,[ref]$amount) -or $amount -le 0) { throw ("{0} must be greater than zero." -f $FieldName) }
            $targetDiskSizeGb = [int][Math]::Ceiling($(switch ($sizeMatch.Groups['unit'].Value.ToLowerInvariant()) { 'mb' { $amount / 1024.0 } 'tb' { $amount * 1024.0 } default { $amount } }))
            if ($targetDiskSizeGb -lt 1 -or $targetDiskSizeGb -gt $MaximumDiskSizeGb) { throw ("{0} must normalize to a size between 1 and {1} GiB." -f $FieldName,$MaximumDiskSizeGb) }
        }
    }
    catch {
        Throw-FriendlyError `
            -Detail ("Option '--disk-size' received invalid value '{0}'." -f $rawText) `
            -Code 62 `
            -Summary "Resize command received an invalid disk size value." `
            -Hint ("Use --disk-size=<size>MB|GB|TB within the supported {0} GiB limit." -f $MaximumDiskSizeGb)
    }

    $amountMatch = [regex]::Match($rawText.Trim(), '^(?<amount>\d+(?:\.\d+)?)\s*(?<unit>mb|gb|tb)?$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $requestedAmount = if ($amountMatch.Success) { [double]::Parse($amountMatch.Groups['amount'].Value, [System.Globalization.CultureInfo]::InvariantCulture) } else { [double]$targetDiskSizeGb }
    $unit = if ($amountMatch.Success -and -not [string]::IsNullOrWhiteSpace($amountMatch.Groups['unit'].Value)) { $amountMatch.Groups['unit'].Value.ToLowerInvariant() } else { 'gb' }
    return [pscustomobject]@{
        RawText = $rawText.Trim()
        RequestedAmount = $requestedAmount
        Unit = $unit
        TargetDiskSizeGb = $targetDiskSizeGb
    }
}

function Get-ProdicloudResizeDiskContext {
    param(
        [psobject]$VmObject,
        [string]$ResourceGroup,
        [string]$VmName,
        [string]$RequestedDiskName = ''
    )

    $osDisk = $VmObject.storageProfile.osDisk
    $dataDisks = @(ConvertTo-ObjectArrayCompat -InputObject $VmObject.storageProfile.dataDisks)
    $selected = $null
    $kind = ''
    if ([string]::IsNullOrWhiteSpace([string]$RequestedDiskName) -or [string]::Equals([string]$RequestedDiskName,[string]$osDisk.name,[System.StringComparison]::OrdinalIgnoreCase)) {
        $selected = $osDisk
        $kind = 'os'
    }
    else {
        $matches = @($dataDisks | Where-Object { [string]::Equals([string]$_.name,[string]$RequestedDiskName,[System.StringComparison]::OrdinalIgnoreCase) })
        if ($matches.Count -ne 1) {
            Throw-FriendlyError `
                -Detail ("Disk '{0}' is not the managed OS disk or a data disk attached to VM '{1}'." -f $RequestedDiskName,$VmName) `
                -Code 62 `
                -Summary "Resize command cannot resolve the selected disk." `
                -Hint "Select one of the managed disks currently attached to the VC."
        }
        $selected = $matches[0]
        $kind = 'data'
    }
    $diskId = [string]$selected.managedDisk.id
    $diskName = [string]$selected.name
    if ([string]::IsNullOrWhiteSpace([string]$diskId)) {
        Throw-FriendlyError `
            -Detail ("Managed disk id could not be resolved for '{0}'." -f $diskName) `
            -Code 62 `
            -Summary "Resize command cannot resolve the selected managed disk." `
            -Hint "Check the VM storage profile in Azure, then retry."
    }
    Write-ProdicloudActionProgress -Action ("read selected {0} disk '{1}' metadata" -f $kind,$diskName)
    $diskJson = az disk show --ids $diskId -o json --only-show-errors
    Assert-LastExitCode 'az disk show (resize selected disk)'
    $diskObject = ConvertFrom-JsonCompat -InputObject $diskJson
    $sizeGb = 0
    if ($null -eq $diskObject -or -not [int]::TryParse([string]$diskObject.diskSizeGb,[ref]$sizeGb) -or $sizeGb -lt 1) {
        Throw-FriendlyError `
            -Detail ("Managed disk '{0}' did not report a valid diskSizeGb value." -f $diskName) `
            -Code 62 `
            -Summary "Resize command cannot resolve the selected disk capacity." `
            -Hint "Check the managed disk metadata in Azure, then retry."
    }
    return [pscustomobject]@{
        Kind = $kind
        DiskId = $diskId
        DiskName = $diskName
        DiskSizeGb = $sizeGb
        SkuName = [string]$diskObject.sku.name
        DiskObject = $diskObject
        HyperVGeneration = [string]$diskObject.hyperVGeneration
        Lun = if ($kind -eq 'data') { [int]$selected.lun } else { -1 }
        Caching = [string]$selected.caching
        WriteAcceleratorEnabled = [bool]$selected.writeAcceleratorEnabled
        DeleteOption = [string]$selected.deleteOption
    }
}

# Handles Get-ProdicloudResizeVmSizeReadback.
function Get-ProdicloudResizeVmSizeReadback {
    param(
        [string]$ResourceGroup,
        [string]$VmName
    )

    Write-ProdicloudActionProgress -Action ("verify requested VM size for '{0}'" -f [string]$VmName)
    $sizeText = [string](az vm show -g $ResourceGroup -n $VmName --query 'hardwareProfile.vmSize' -o tsv --only-show-errors)
    Assert-LastExitCode 'az vm show (resize verification)'
    if ([string]::IsNullOrWhiteSpace([string]$sizeText)) {
        Throw-FriendlyError `
            -Detail ("Azure returned an empty VM size for '{0}' in '{1}' after resize." -f $VmName, $ResourceGroup) `
            -Code 62 `
            -Summary "Resize command could not verify the resulting VM size." `
            -Hint "Run prodicloud show for the target VM and inspect its current hardware profile."
    }

    return $sizeText.Trim()
}

# Handles Get-ProdicloudResizeDiskSizeReadback.
function Get-ProdicloudResizeDiskSizeReadback {
    param(
        [string]$DiskId,
        [string]$DiskName,
        [int]$ExpectedSizeGb = 0,
        [ValidateRange(30,900)][int]$TimeoutSeconds = 300
    )
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $lastState = ''
    $lastSizeGb = 0
    $lastHeartbeat = -30
    while ($watch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        Write-ProdicloudActionProgress -Action ("read managed disk '{0}' size and provisioning state" -f [string]$DiskName)
        $diskJson = az disk show --ids $DiskId --query '{sizeGB:diskSizeGB,provisioningState:provisioningState}' -o json --only-show-errors
        Assert-LastExitCode 'az disk show (resize verification)'
        $disk = ConvertFrom-JsonCompat -InputObject (@($diskJson) -join "`n")
        $lastState = [string]$disk.provisioningState
        $lastSizeGb = [int]$disk.sizeGB
        if ([string]::Equals($lastState,'Failed',[System.StringComparison]::OrdinalIgnoreCase)) { throw ("Managed disk '{0}' entered provisioning state Failed during resize." -f $DiskName) }
        if ($lastSizeGb -gt 0 -and [string]::Equals($lastState,'Succeeded',[System.StringComparison]::OrdinalIgnoreCase) -and ($ExpectedSizeGb -le 0 -or $lastSizeGb -eq $ExpectedSizeGb)) { return [int]$lastSizeGb }
        $elapsedSeconds = [int][Math]::Floor($watch.Elapsed.TotalSeconds)
        if (($elapsedSeconds - $lastHeartbeat) -ge 30) {
            $lastHeartbeat = $elapsedSeconds
            Write-ProdicloudActionProgress -Action ("Managed disk '{0}' is {1} GiB and provisioning='{2}' while expecting {3} GiB ({4}s of {5}s maximum)" -f $DiskName,$lastSizeGb,$lastState,$ExpectedSizeGb,$elapsedSeconds,$TimeoutSeconds)
        }
        Start-Sleep -Seconds 5
    }
    Throw-FriendlyError `
        -Detail ("Managed disk '{0}' did not stabilize at the requested size {1} GiB within {2}s. Last size={3} GiB; provisioning='{4}'." -f $DiskName,$ExpectedSizeGb,$TimeoutSeconds,$lastSizeGb,$lastState) `
        -Code 62 `
        -Summary "Resize command could not verify the resulting managed disk size." `
        -Hint "Run prodicloud component --action=show --type=disk --name=<disk-name> and inspect the disk metadata."
}

# Handles Get-ProdicloudResizeLifecycleSnapshot.
function Get-ProdicloudResizeLifecycleSnapshot {
    param(
        [string]$ResourceGroup,
        [string]$VmName,
        [string]$Stage
    )

    Write-ProdicloudActionProgress -Action ("read {0} lifecycle snapshot for '{1}'" -f [string]$Stage, [string]$VmName)
    try {
        return (Get-ProdicloudVmLifecycleSnapshot -ResourceGroup $ResourceGroup -VmName $VmName)
    }
    catch {
        Write-Warning ("Resize {0} lifecycle snapshot is unavailable: {1}" -f [string]$Stage, [string]$_.Exception.Message)
        return $null
    }
}

# Handles Write-ProdicloudResizeStateSnapshot.
function Write-ProdicloudResizeStateSnapshot {
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
    $lifecycleText = if ($null -eq $LifecycleSnapshot) { 'lifecycle=(snapshot unavailable)' } else { Format-ProdicloudVmLifecycleSummaryText -Snapshot $LifecycleSnapshot }
    Write-Host ("Resize {0} state snapshot: VM={1}/{2}; region={3}; size={4}; OS disk={5}; {6}" -f [string]$Stage, [string]$ResourceGroup, [string]$VmName, [string]$Region, [string]$VmSize, [string]$diskText, [string]$lifecycleText) -ForegroundColor DarkCyan
}

function Write-ProdicloudResizeDiskInventory {
    param(
        [ValidateSet('before','after')][string]$Stage,
        [psobject]$Inspection,
        [long]$AzureDiskSizeBytes = 0
    )
    if ($null -eq $Inspection) { return }
    $guestDiskBytes = if ($null -ne $Inspection.PSObject.Properties['diskSizeBytes']) { [long]$Inspection.diskSizeBytes } else { [long]0 }
    $filesystemUsedBytes = if ($null -ne $Inspection.PSObject.Properties['usedBytes']) { [long]$Inspection.usedBytes } else { [long]0 }
    $filesystemFreeBytes = if ($null -ne $Inspection.PSObject.Properties['freeBytes']) { [long]$Inspection.freeBytes } else { [long]0 }
    $volumeCapacityBytes = if ($null -ne $Inspection.PSObject.Properties['volumeSizeBytes']) { [long]$Inspection.volumeSizeBytes } else { [long]0 }
    $partitionedBytes = if ($null -ne $Inspection.PSObject.Properties['partitionedBytes']) { [long]$Inspection.partitionedBytes } else { [long]0 }
    $unallocatedBytes = if ($null -ne $Inspection.PSObject.Properties['unallocatedBytes']) { [long]$Inspection.unallocatedBytes } else { [long]0 }
    $nonFilesystemBytes = if ($null -ne $Inspection.PSObject.Properties['nonFilesystemPartitionBytes']) { [long]$Inspection.nonFilesystemPartitionBytes } else { [long]0 }
    $azureCapacityText = if ($AzureDiskSizeBytes -gt 0) { ('{0:N2} GiB' -f ($AzureDiskSizeBytes / 1GB)) } else { 'unavailable' }
    $guestCapacityText = if ($guestDiskBytes -gt 0) { ('{0:N2} GiB' -f ($guestDiskBytes / 1GB)) } else { 'unavailable' }
    Write-Host ("Disk inventory ({0}): Azure provisioned={1}; guest raw={2}; partitioned={3:N2} GiB; unallocated={4:N2} GiB; non-filesystem partitions={5:N2} GiB; filesystem capacity={6:N2} GiB; used={7:N2} GiB; free={8:N2} GiB." -f $Stage,$azureCapacityText,$guestCapacityText,($partitionedBytes / 1GB),($unallocatedBytes / 1GB),($nonFilesystemBytes / 1GB),($volumeCapacityBytes / 1GB),($filesystemUsedBytes / 1GB),($filesystemFreeBytes / 1GB)) -ForegroundColor DarkCyan
    foreach ($partition in @(ConvertTo-ObjectArrayCompat -InputObject $Inspection.partitions)) {
        $number = if ($null -ne $partition.PSObject.Properties['Number']) { [string]$partition.Number } else { [string]$partition.number }
        $partitionBytes = if ($null -ne $partition.PSObject.Properties['Size']) { [long]$partition.Size } elseif ($null -ne $partition.PSObject.Properties['partitionSizeBytes']) { [long]$partition.partitionSizeBytes } else { [long]0 }
        $partitionUsedBytes = if ($null -ne $partition.PSObject.Properties['UsedBytes']) { [long]$partition.UsedBytes } else { [long]0 }
        $partitionFreeBytes = if ($null -ne $partition.PSObject.Properties['FreeBytes']) { [long]$partition.FreeBytes } else { [long]0 }
        $partitionVolumeBytes = if ($null -ne $partition.PSObject.Properties['VolumeSizeBytes']) { [long]$partition.VolumeSizeBytes } elseif ($null -ne $partition.PSObject.Properties['volumeSizeBytes']) { [long]$partition.volumeSizeBytes } else { [long]0 }
        $fileSystem = if ($null -ne $partition.PSObject.Properties['FileSystem']) { [string]$partition.FileSystem } else { '' }
        $mountPoint = if ($null -ne $partition.PSObject.Properties['DriveLetter'] -and -not [string]::IsNullOrWhiteSpace([string]$partition.DriveLetter)) { ([string]$partition.DriveLetter + ':') } elseif ($null -ne $partition.PSObject.Properties['mountPoint']) { [string]$partition.mountPoint } else { '' }
        $locationText = if ([string]::IsNullOrWhiteSpace($mountPoint)) { 'unmounted' } else { $mountPoint }
        $volumeText = if ($partitionVolumeBytes -gt 0) { ('volume={0:N2} GiB used={1:N2} GiB free={2:N2} GiB' -f ($partitionVolumeBytes / 1GB),($partitionUsedBytes / 1GB),($partitionFreeBytes / 1GB)) } else { 'no mounted filesystem volume' }
        Write-Host ("  Partition {0}: {1}; {2}; partition={3:N2} GiB; {4}" -f $number,$locationText,$fileSystem,($partitionBytes / 1GB),$volumeText)
    }
}

function Write-ProdicloudResizeShrinkEstimate {
    param([int]$TargetSizeGb,[psobject]$Inspection,[long]$MinimumFreeBytes = 10GB)
    $targetBytes = [long]$TargetSizeGb * 1GB
    $usedBytes = [long]$Inspection.usedBytes
    $expectedHeadroomBytes = $targetBytes - $usedBytes
    $usableAfterSafetyBytes = $expectedHeadroomBytes - $MinimumFreeBytes
    Write-Host ("Shrink estimate: target={0} GiB; measured filesystem use={1:N2} GiB; estimated headroom={2:N2} GiB; required safety headroom={3:N2} GiB; remaining sizing allowance={4:N2} GiB." -f $TargetSizeGb,($usedBytes / 1GB),($expectedHeadroomBytes / 1GB),($MinimumFreeBytes / 1GB),($usableAfterSafetyBytes / 1GB)) -ForegroundColor Yellow
}

function Get-ProdicloudResizeWindowsOsLayoutSupport {
    param([object[]]$Partitions)
    $parts = @($Partitions)
    $efiGuid = 'C12A7328-F81F-11D2-BA4B-00A0C93EC93B'
    $msrGuid = 'E3C9E316-0B5C-4DB8-817D-F92DF00215AE'
    $basicGuid = 'EBD0A0A2-B9E5-4433-87C0-68B6B72699C7'
    $recoveryGuid = 'DE94BBA4-06D1-4D40-A16A-BFD50179D6AC'
    $normalized = @(
        foreach ($partition in $parts) {
            $offset = if ($null -ne $partition.PSObject.Properties['Offset']) { [long]$partition.Offset } elseif ($null -ne $partition.PSObject.Properties['OffsetBytes']) { [long]$partition.OffsetBytes } else { [long]0 }
            $size = if ($null -ne $partition.PSObject.Properties['Size']) { [long]$partition.Size } elseif ($null -ne $partition.PSObject.Properties['PartitionSizeBytes']) { [long]$partition.PartitionSizeBytes } else { [long]0 }
            $guid = ([string]$partition.GptType -replace '[{}]','').ToUpperInvariant()
            $type = if ($null -ne $partition.PSObject.Properties['Type']) { [string]$partition.Type } elseif ($guid -eq $msrGuid) { 'Reserved' } else { '' }
            [pscustomobject]@{
                Partition = $partition
                Guid = $guid
                Offset = $offset
                Size = $size
                Type = $type
            }
        }
    )
    $efi = @($normalized | Where-Object { $_.Guid -eq $efiGuid })
    $msr = @($normalized | Where-Object { $_.Guid -eq $msrGuid })
    $basic = @($normalized | Where-Object { $_.Guid -eq $basicGuid })
    $recovery = @($normalized | Where-Object { $_.Guid -eq $recoveryGuid })
    $hasKnownTypes = ($efi.Count -eq 1 -and $basic.Count -eq 1 -and $recovery.Count -eq 1)
    if ($parts.Count -eq 4 -and $hasKnownTypes -and $msr.Count -eq 1) {
        return [pscustomobject]@{ IsSupported = $true; LayoutId = 'GPT-UEFI-4-partition'; IgnoredPartitionNumbers = @(); Reason = '' }
    }
    if ($parts.Count -eq 5 -and $hasKnownTypes -and $msr.Count -eq 2) {
        $efiOffset = [long]$efi[0].Offset
        $basicOffset = [long]$basic[0].Offset
        $canonicalMsr = @($msr | Where-Object { [long]$_.Offset -gt $efiOffset -and [long]$_.Offset -lt $basicOffset })
        $leadingMsr = @($msr | Where-Object { [long]$_.Offset -lt $efiOffset })
        if ($canonicalMsr.Count -eq 1 -and $leadingMsr.Count -eq 1) {
            $extra = $leadingMsr[0].Partition
            $extraSize = [long]$leadingMsr[0].Size
            $extraOffset = [long]$leadingMsr[0].Offset
            $extraType = [string]$leadingMsr[0].Type
            $extraFileSystem = if ($null -ne $extra.PSObject.Properties['FileSystem']) { [string]$extra.FileSystem } else { '' }
            $extraDriveLetter = if ($null -ne $extra.PSObject.Properties['DriveLetter']) { [string]$extra.DriveLetter } else { '' }
            $extraVolumeBytes = if ($null -ne $extra.PSObject.Properties['VolumeSizeBytes']) { [long]$extra.VolumeSizeBytes } else { [long]0 }
            $extraIsBoot = ($null -ne $extra.PSObject.Properties['IsBoot'] -and [bool]$extra.IsBoot)
            $extraIsSystem = ($null -ne $extra.PSObject.Properties['IsSystem'] -and [bool]$extra.IsSystem)
            if ($extraType -eq 'Reserved' -and -not $extraIsBoot -and -not $extraIsSystem -and $extraOffset -le 1MB -and $extraSize -gt 0 -and $extraSize -le 32MB -and [string]::IsNullOrWhiteSpace($extraFileSystem) -and [string]::IsNullOrWhiteSpace($extraDriveLetter) -and $extraVolumeBytes -eq 0) {
                return [pscustomobject]@{ IsSupported = $true; LayoutId = 'GPT-UEFI-4-partition-with-empty-leading-MSR'; IgnoredPartitionNumbers = @([int]$extra.Number); Reason = '' }
            }
        }
    }
    return [pscustomobject]@{ IsSupported = $false; LayoutId = 'unsupported'; IgnoredPartitionNumbers = @(); Reason = 'Windows OS shrink supports the standard four-partition GPT/UEFI layout or that layout with one small, empty leading MSR partition.' }
}

# Handles Assert-ProdicloudResizeReadback.
function Assert-ProdicloudResizeReadback {
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

    $stateText = if ($null -eq $LifecycleSnapshot) { 'lifecycle=(snapshot unavailable)' } else { Format-ProdicloudVmLifecycleSummaryText -Snapshot $LifecycleSnapshot }
    $resourceLabel = if ($Kind -eq 'vm-size') { 'VM size' } else { 'managed disk size (GB)' }
    Throw-FriendlyError `
        -Detail ("Resize readback mismatch for VM '{0}' in '{1}': expected {2}='{3}', actual='{4}'. {5}" -f $VmName, $ResourceGroup, $resourceLabel, $ExpectedValue, $ActualValue, $stateText) `
        -Code 62 `
        -Summary ("Resize command could not verify the requested {0}." -f $resourceLabel) `
        -Hint "Inspect the reported target state before retrying. The requested Azure resize was not automatically rolled back."
}

function Assert-ProdicloudResizeLifecycleStateSupported {
    param([psobject]$Snapshot,[string]$VmName)
    $state = [string]$Snapshot.NormalizedState
    if ($state -notin @('started','stopped','deallocated')) {
        Throw-FriendlyError `
            -Detail ("VM '{0}' is in lifecycle state '{1}', which this resize workflow cannot safely preserve." -f $VmName,$state) `
            -Code 62 `
            -Summary 'Resize is unavailable for the current VM lifecycle state.' `
            -Hint 'Wait for Azure operations to finish; resume a hibernated VM before retrying.'
    }
    return $state
}

function Invoke-ProdicloudResizeAzureVmStep {
    param([string]$Label,[string[]]$Arguments,[string]$Context)
    Invoke-TrackedAction -Label $Label -Action {
        az @Arguments
        Assert-LastExitCode $Context
    } | Out-Null
}

function Wait-ProdicloudResizePowerState {
    param([string]$ResourceGroup,[string]$VmName,[ValidateSet('VM running','VM stopped','VM deallocated')][string]$DesiredState,[ValidateRange(1,240)][int]$MaxAttempts = 120,[ValidateRange(1,3)][int]$RequiredStableSamples = 2,[switch]$RedeployAttempted)
    $desiredNormalizedState = switch ($DesiredState) {
        'VM running' { 'started' }
        'VM stopped' { 'stopped' }
        'VM deallocated' { 'deallocated' }
    }
    $lastPowerState = ''
    $lastProvisioningState = ''
    $lastProvisioningCode = ''
    $lastError = ''
    $stableSamples = 0
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        Write-ProdicloudActionProgress -Action ("read resize VM power and provisioning state '{0}/{1}' (check {2}/{3})" -f $ResourceGroup,$VmName,$attempt,$MaxAttempts)
        try {
            $snapshot = Get-ProdicloudVmLifecycleSnapshot -ResourceGroup $ResourceGroup -VmName $VmName
            $lastPowerState = [string]$snapshot.NormalizedState
            $lastProvisioningState = [string]$snapshot.ProvisioningStateDisplay
            $lastProvisioningCode = [string]$snapshot.ProvisioningStateCode
            $lastError = ''
            if ([string]$snapshot.ProvisioningStateCode -match '(?i)failed' -or [string]$snapshot.ProvisioningStateDisplay -match '(?i)failed') {
                throw ("VM provisioning entered '{0}' while waiting for '{1}'." -f $lastProvisioningState,$DesiredState)
            }
            if ([string]::Equals($lastPowerState,[string]$desiredNormalizedState,[System.StringComparison]::OrdinalIgnoreCase) -and (Test-ProdicloudVmProvisioningSucceeded -Snapshot $snapshot)) {
                $stableSamples++
                if ($stableSamples -ge $RequiredStableSamples) { return $true }
            }
            else { $stableSamples = 0 }
        }
        catch {
            if ([string]$_.Exception.Message -match '(?i)provisioning entered') { throw }
            $lastError = [string]$_.Exception.Message
        }
        if (($attempt % 6) -eq 0 -or -not [string]::IsNullOrWhiteSpace($lastError)) {
            $powerText = if ([string]::IsNullOrWhiteSpace($lastPowerState)) { 'unknown' } else { $lastPowerState }
            $provisioningText = if ([string]::IsNullOrWhiteSpace($lastProvisioningState)) { 'unknown' } else { $lastProvisioningState }
            $errorSuffix = if ([string]::IsNullOrWhiteSpace($lastError)) { '' } else { '; last Azure read: ' + $lastError }
            Write-ProdicloudActionProgress -Action ("resize VM is power='{0}', provisioning='{1}', stable={2}/{3} while waiting for '{4}' (check {5}/{6}){7}" -f $powerText,$provisioningText,$stableSamples,$RequiredStableSamples,$DesiredState,$attempt,$MaxAttempts,$errorSuffix)
        }
        if ($attempt -lt $MaxAttempts) { Start-Sleep -Seconds 5 }
    }
    $isUpdating = ([string]$lastProvisioningState -match '(?i)^updating$') -or ([string]$lastProvisioningCode -match '(?i)provisioningstate/updating$')
    if (-not $RedeployAttempted -and $DesiredState -eq 'VM running' -and $isUpdating) {
        Write-Warning ("VM '{0}' remained in provisioning state Updating during resize startup stabilization; attempting one bounded Azure redeploy repair." -f $VmName)
        Invoke-ProdicloudResizeAzureVmStep -Label ("az vm redeploy -g {0} -n {1} --no-wait (resize recovery)" -f $ResourceGroup,$VmName) -Arguments @('vm','redeploy','-g',$ResourceGroup,'-n',$VmName,'--no-wait','-o','none','--only-show-errors') -Context 'az vm redeploy (resize stuck-provisioning repair)'
        return (Wait-ProdicloudResizePowerState -ResourceGroup $ResourceGroup -VmName $VmName -DesiredState $DesiredState -MaxAttempts $MaxAttempts -RequiredStableSamples $RequiredStableSamples -RedeployAttempted)
    }
    throw ("VM '{0}' did not stabilize at '{1}' with successful provisioning after {2} five-second checks. Last power='{3}', provisioning='{4}'." -f $VmName,$DesiredState,$MaxAttempts,$lastPowerState,$lastProvisioningState)
}

function Set-ProdicloudResizeVmPowerState {
    param([string]$ResourceGroup,[string]$VmName,[ValidateSet('started','stopped','deallocated')][string]$DesiredState)
    $snapshot = Get-ProdicloudVmLifecycleSnapshot -ResourceGroup $ResourceGroup -VmName $VmName
    $current = [string]$snapshot.NormalizedState
    if (-not (Test-ProdicloudVmProvisioningSucceeded -Snapshot $snapshot)) {
        $stableState = switch ($current) {
            'started' { 'VM running' }
            'stopped' { 'VM stopped' }
            'deallocated' { 'VM deallocated' }
            default { '' }
        }
        if ([string]::IsNullOrWhiteSpace($stableState)) { throw ("VM '{0}' has no stable supported lifecycle state while provisioning is '{1}'." -f $VmName,[string]$snapshot.ProvisioningStateDisplay) }
        Wait-ProdicloudResizePowerState -ResourceGroup $ResourceGroup -VmName $VmName -DesiredState $stableState -RequiredStableSamples 2 | Out-Null
        $snapshot = Get-ProdicloudVmLifecycleSnapshot -ResourceGroup $ResourceGroup -VmName $VmName
        $current = [string]$snapshot.NormalizedState
    }
    if ($current -eq $DesiredState) {
        if (Test-ProdicloudVmProvisioningSucceeded -Snapshot $snapshot) { return }
        $stableState = switch ($DesiredState) {
            'started' { 'VM running' }
            'stopped' { 'VM stopped' }
            'deallocated' { 'VM deallocated' }
        }
        Wait-ProdicloudResizePowerState -ResourceGroup $ResourceGroup -VmName $VmName -DesiredState $stableState -RequiredStableSamples 2 | Out-Null
        return
    }
    if ($DesiredState -eq 'started') {
        Invoke-ProdicloudResizeAzureVmStep -Label ("az vm start -g {0} -n {1} --no-wait" -f $ResourceGroup,$VmName) -Arguments @('vm','start','-g',$ResourceGroup,'-n',$VmName,'--no-wait','-o','none','--only-show-errors') -Context 'az vm start (resize state restore)'
        Wait-ProdicloudResizePowerState -ResourceGroup $ResourceGroup -VmName $VmName -DesiredState 'VM running' | Out-Null
        return
    }
    if ($DesiredState -eq 'stopped') {
        if ($current -eq 'deallocated') {
            Invoke-ProdicloudResizeAzureVmStep -Label ("az vm start -g {0} -n {1} --no-wait before restoring stopped state" -f $ResourceGroup,$VmName) -Arguments @('vm','start','-g',$ResourceGroup,'-n',$VmName,'--no-wait','-o','none','--only-show-errors') -Context 'az vm start (restore allocated stopped state)'
            Wait-ProdicloudResizePowerState -ResourceGroup $ResourceGroup -VmName $VmName -DesiredState 'VM running' | Out-Null
        }
        Invoke-ProdicloudResizeAzureVmStep -Label ("az vm stop -g {0} -n {1} --no-wait to restore stopped state" -f $ResourceGroup,$VmName) -Arguments @('vm','stop','-g',$ResourceGroup,'-n',$VmName,'--no-wait','-o','none','--only-show-errors') -Context 'az vm stop (resize state restore)'
        Wait-ProdicloudResizePowerState -ResourceGroup $ResourceGroup -VmName $VmName -DesiredState 'VM stopped' | Out-Null
        return
    }
    Invoke-ProdicloudResizeAzureVmStep -Label ("az vm deallocate -g {0} -n {1} --no-wait to restore deallocated state" -f $ResourceGroup,$VmName) -Arguments @('vm','deallocate','-g',$ResourceGroup,'-n',$VmName,'--no-wait','-o','none','--only-show-errors') -Context 'az vm deallocate (resize state restore)'
    Wait-ProdicloudResizePowerState -ResourceGroup $ResourceGroup -VmName $VmName -DesiredState 'VM deallocated' | Out-Null
}

function Get-ProdicloudResizeGuestRuntime {
    param([string]$ResourceGroup,[string]$VmName,[ValidateSet('windows','linux')][string]$Platform)
    $options = @{ 'group' = $ResourceGroup; 'vm-name' = $VmName }
    $windowsFlag = ($Platform -eq 'windows')
    $runtime = if ($windowsFlag) {
        Initialize-ProdicloudTaskExecutionRuntimeContext -AutoMode -WindowsFlag -Options $options
    }
    else {
        Initialize-ProdicloudTaskExecutionRuntimeContext -AutoMode -LinuxFlag -Options $options
    }
    $target = Resolve-ProdicloudManagedVmTarget -Options $options -ConfigMap $runtime.EffectiveConfigMap -OperationName 'resize'
    $runtime.Context.ResourceGroup = [string]$target.ResourceGroup
    $runtime.Context.VmName = [string]$target.VmName
    $details = Get-ProdicloudVmDetails -Context $runtime.Context -AllowCachedInventory
    $hostName = [string]$details.VmFqdn
    if ([string]::IsNullOrWhiteSpace($hostName)) { $hostName = [string]$details.PublicIP }
    if ([string]::IsNullOrWhiteSpace($hostName)) { throw 'Resize guest transport could not resolve the VM FQDN or public IP.' }
    $transport = if ($Platform -eq 'windows') { Get-ProdicloudPackageTransport -ConfigMap ([hashtable]$runtime.EffectiveConfigMap) } else { 'ssh' }
    return [pscustomobject]@{ Runtime = $runtime; Target = $target; HostName = $hostName; Platform = $Platform; Transport = $transport; Options = $options }
}

function Get-ProdicloudResizeGuestTransportPort {
    param([psobject]$GuestRuntime)
    $portText = ''
    if ([string]$GuestRuntime.Transport -eq 'winrm') {
        if ($null -ne $GuestRuntime.Runtime.Context.PSObject.Properties['PowerShellPort']) { $portText = [string]$GuestRuntime.Runtime.Context.PowerShellPort }
        if ([string]::IsNullOrWhiteSpace($portText)) { $portText = [string](Get-ProdicloudDefaultPowerShellPortText) }
    }
    else { $portText = [string]$GuestRuntime.Runtime.Context.SshPort }
    $port = 0
    if (-not [int]::TryParse($portText,[ref]$port) -or $port -lt 1 -or $port -gt 65535) { throw ("Resize guest transport '{0}' has invalid port '{1}'." -f [string]$GuestRuntime.Transport,$portText) }
    return $port
}

function Wait-ProdicloudResizeGuestTransportStable {
    param(
        [psobject]$GuestRuntime,
        [ValidateRange(1,3)][int]$RequiredSuccesses = 1,
        [ValidateRange(5,900)][int]$TimeoutSeconds = 120,
        [ValidateRange(5,10)][int]$PollSeconds = 5
    )
    $port = Get-ProdicloudResizeGuestTransportPort -GuestRuntime $GuestRuntime
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $successes = 0
    $lastReportSeconds = -30
    while ($watch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        Write-ProdicloudActionProgress -Action ("probe {0} endpoint '{1}:{2}' for stable resize access (success {3}/{4})" -f [string]$GuestRuntime.Transport,[string]$GuestRuntime.HostName,$port,$successes,$RequiredSuccesses)
        if (Test-ProdicloudTcpPortReachable -HostName ([string]$GuestRuntime.HostName) -Port $port -TimeoutSeconds 5) {
            $successes++
            if ($successes -ge $RequiredSuccesses) { return $true }
        }
        else { $successes = 0 }
        $elapsedSeconds = [int][Math]::Floor($watch.Elapsed.TotalSeconds)
        if (($elapsedSeconds - $lastReportSeconds) -ge 30) {
            $lastReportSeconds = $elapsedSeconds
            Write-ProdicloudActionProgress -Action ("resize guest transport has {0}/{1} consecutive successful probes ({2}s of {3}s maximum)" -f $successes,$RequiredSuccesses,$elapsedSeconds,$TimeoutSeconds)
        }
        if ($watch.Elapsed.TotalSeconds -lt $TimeoutSeconds) { Start-Sleep -Seconds $PollSeconds }
    }
    throw ("Resize guest transport '{0}' at '{1}:{2}' did not stabilize after {3}s; required {4} consecutive successful probes, observed {5}." -f [string]$GuestRuntime.Transport,[string]$GuestRuntime.HostName,$port,$TimeoutSeconds,$RequiredSuccesses,$successes)
}

function Invoke-ProdicloudResizeGuestOperation {
    param(
        [string]$ResourceGroup,
        [string]$VmName,
        [ValidateSet('windows','linux')][string]$Platform,
        [ValidateSet('inspect','expand','set-drive-letter','restore-winre')][string]$Action,
        [psobject]$Disk,
        [bool]$VmRecentlyStarted = $false
    )
    $guest = Get-ProdicloudResizeGuestRuntime -ResourceGroup $ResourceGroup -VmName $VmName -Platform $Platform
    $request = [ordered]@{ action = $Action; kind = [string]$Disk.Kind; lun = [int]$Disk.Lun; targetSizeGb = [int]$Disk.TargetSizeGb; driveLetter = [string]$Disk.DriveLetter }
    $assetPath = Join-Path (Get-ProdicloudRepoRoot) ('modules/commands/resize/assets/resize-{0}.{1}' -f $Platform,$(if ($Platform -eq 'windows') { 'ps1' } else { 'sh' }))
    if (-not (Test-Path -LiteralPath $assetPath -PathType Leaf)) { throw ("Resize guest script is missing: {0}" -f $assetPath) }
    $scriptText = Get-Content -LiteralPath $assetPath -Raw
    if ($Platform -eq 'windows') {
        $requestJson = ConvertTo-Json -InputObject $request -Depth 4 -Compress
        $requestB64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($requestJson))
        $scriptText = $scriptText.Replace('__PRODICLOUD_RESIZE_REQUEST_B64__',$requestB64)
    }
    else {
        $scriptText = $scriptText.Replace('__PRODICLOUD_RESIZE_ACTION__',[string]$Action).Replace('__PRODICLOUD_RESIZE_KIND__',[string]$Disk.Kind).Replace('__PRODICLOUD_RESIZE_LUN__',[string][int]$Disk.Lun)
    }
    $startupTimeoutSeconds = if ($VmRecentlyStarted) { 300 } else { 120 }
    $stableSuccesses = if ($VmRecentlyStarted) { 2 } else { 1 }
    try { [void](Wait-ProdicloudResizeGuestTransportStable -GuestRuntime $guest -RequiredSuccesses $stableSuccesses -TimeoutSeconds $startupTimeoutSeconds -PollSeconds 5) }
    catch { throw ("The configured {0} endpoint did not stabilize; disk guest operation '{1}' stopped before mutation. {2}" -f $guest.Transport,$Action,[string]$_.Exception.Message) }
    $task = [pscustomobject]@{
        Name = ('resize-{0}-{1}' -f $Action,[string]$Disk.Kind)
        Script = [string]$scriptText
        TimeoutSeconds = 600
        TaskType = 'task'
        AssetCopies = @()
        AppStateSpec = $null
        TaskNumber = 0
        DependsOn = @()
    }
    Write-ProdicloudActionProgress -Action ("run {0} guest disk {1} over {2}" -f $Action,[string]$Disk.Kind,[string]$guest.Transport)
    if ($Platform -eq 'windows' -and $guest.Transport -eq 'winrm') {
        $result = Invoke-ProdicloudWinRmTaskBlocks -Platform 'windows' -HostName $guest.HostName -Runtime $guest.Runtime -Target $guest.Target -TaskBlocks @($task) -TaskOutcomeMode 'strict' -PerfTaskCategory 'task-run'
    }
    else {
        $result = Invoke-ProdicloudSshTaskBlocks `
            -Platform $Platform `
            -RepoRoot (Get-ProdicloudRepoRoot) `
            -SshHost $guest.HostName `
            -SshUser ([string]$guest.Runtime.Context.VmUser) `
            -SshPassword ([string]$guest.Runtime.Context.VmPass) `
            -SshPort ([string]$guest.Runtime.Context.SshPort) `
            -AssistantUser ([string]$guest.Runtime.Context.VmAssistantUser) `
            -ResourceGroup $ResourceGroup `
            -VmName $VmName `
            -TaskBlocks @($task) `
            -TaskOutcomeMode 'strict' `
            -PerfTaskCategory 'task-run' `
            -SshMaxRetries 1 `
            -SshTaskTimeoutSeconds 600 `
            -SshConnectTimeoutSeconds ([int]$guest.Runtime.SshConnectTimeoutSeconds) `
            -ConfiguredPySshClientPath ([string]$guest.Runtime.ConfiguredPySshClientPath)
    }
    $output = @($result.TaskOutputs | ForEach-Object { [string]$_.Output }) -join "`n"
    $marker = @($output -split "`r?`n" | Where-Object { $_ -match '^PRODICLOUD_RESIZE_RESULT:' } | Select-Object -Last 1)
    if ($marker.Count -eq 0) { throw ("Guest disk {0} did not return a structured verification record." -f $Action) }
    $payload = ([string]$marker[0]).Substring('PRODICLOUD_RESIZE_RESULT:'.Length)
    try { $structured = ConvertFrom-JsonCompat -InputObject $payload }
    catch { throw ("Guest disk {0} returned invalid structured output: {1}" -f $Action,$_.Exception.Message) }
    if ([string]$structured.status -ne 'ok') { throw ("Guest disk {0} verification failed: {1}" -f $Action,[string]$structured.message) }
    return $structured
}

function Wait-ProdicloudResizeGuestDiskCapacity {
    param(
        [string]$ResourceGroup,
        [string]$VmName,
        [ValidateSet('windows','linux')][string]$Platform,
        [psobject]$Disk,
        [int]$TargetDiskSizeGb,
        [long]$MinimumFreeBytes = 0,
        [ValidateRange(1,3)][int]$RequiredStableSamples = 2,
        [ValidateRange(30,900)][int]$TimeoutSeconds = 300
    )
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $targetBytes = [long]$TargetDiskSizeGb * 1GB
    $minimumFilesystemBytes = [Math]::Max([long]0,($targetBytes - (2GB)))
    $lastHeartbeat = -30
    $lastObserved = ''
    $lastCapacitySignature = ''
    $stableSamples = 0
    while ($watch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        $inspection = Invoke-ProdicloudResizeGuestOperation -ResourceGroup $ResourceGroup -VmName $VmName -Platform $Platform -Action 'inspect' -Disk $Disk
        $diskBytes = [long]$inspection.diskSizeBytes
        $filesystemBytes = [long]$inspection.filesystemSizeBytes
        $usedBytes = [long]$inspection.usedBytes
        $freeBytes = [long]$inspection.freeBytes
        $lastObserved = ("disk={0:N2} GiB; filesystem={1:N2} GiB; used={2:N2} GiB; free={3:N2} GiB" -f ($diskBytes / 1GB),($filesystemBytes / 1GB),($usedBytes / 1GB),($freeBytes / 1GB))
        if ($diskBytes -ge $targetBytes -and $filesystemBytes -ge $minimumFilesystemBytes) {
            if ($MinimumFreeBytes -gt 0 -and ($usedBytes + $MinimumFreeBytes -gt $diskBytes -or $freeBytes -lt $MinimumFreeBytes)) {
                throw ("Guest capacity reached {0} GiB but did not retain the required free headroom of {1:N2} GiB. {2}" -f $TargetDiskSizeGb,($MinimumFreeBytes / 1GB),$lastObserved)
            }
            $capacitySignature = '{0}|{1}' -f $diskBytes,$filesystemBytes
            if ($capacitySignature -eq $lastCapacitySignature) { $stableSamples++ } else { $lastCapacitySignature = $capacitySignature; $stableSamples = 1 }
            if ($stableSamples -ge $RequiredStableSamples) { return $inspection }
        }
        else { $lastCapacitySignature = ''; $stableSamples = 0 }
        $elapsedSeconds = [int][Math]::Floor($watch.Elapsed.TotalSeconds)
        if (($elapsedSeconds - $lastHeartbeat) -ge 30) {
            $lastHeartbeat = $elapsedSeconds
            Write-ProdicloudActionProgress -Action ("guest disk capacity is converging to {0} GiB, stable={1}/{2} ({3}s of {4}s maximum): {5}" -f $TargetDiskSizeGb,$stableSamples,$RequiredStableSamples,$elapsedSeconds,$TimeoutSeconds,$lastObserved)
        }
        Start-Sleep -Seconds 5
    }
    throw ("Guest disk '{0}' did not verify Azure capacity {1} GiB and the matching filesystem size within {2}s. Last measurement: {3}." -f [string]$Disk.Kind,$TargetDiskSizeGb,$TimeoutSeconds,$lastObserved)
}

function Wait-ProdicloudResizeHelperGuestAgent {
    param([string]$ResourceGroup,[string]$VmName,[ValidateRange(30,600)][int]$TimeoutSeconds = 180)
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $lastHeartbeat = 0
    $lastReadError = ''
    $readySamples = 0
    while ($watch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        Write-ProdicloudActionProgress -Action ("read Azure Guest Agent readiness for temporary vc-helper '{0}'" -f $VmName)
        $agentStatusText = ''
        try {
            $agentStatusResult = az vm get-instance-view -g $ResourceGroup -n $VmName --query "instanceView.vmAgent.statuses[?code=='ProvisioningState/succeeded'].displayStatus | [0]" -o tsv --only-show-errors
            if ($null -ne $agentStatusResult) { $agentStatusText = @($agentStatusResult | ForEach-Object { [string]$_ }) -join '' }
            $agentReadExitCode = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
            if ($agentReadExitCode -ne 0) { throw ("az vm get-instance-view returned exit code {0}." -f $agentReadExitCode) }
            $lastReadError = ''
        }
        catch { $lastReadError = [string]$_.Exception.Message }
        if ([string]::Equals($agentStatusText.Trim(),'Ready',[System.StringComparison]::OrdinalIgnoreCase)) {
            $readySamples++
            if ($readySamples -ge 2) { return $true }
        }
        else { $readySamples = 0 }
        $elapsedSeconds = [int][Math]::Floor($watch.Elapsed.TotalSeconds)
        if (($elapsedSeconds - $lastHeartbeat) -ge 30) {
            $lastHeartbeat = $elapsedSeconds
            $statusText = if ([string]::IsNullOrWhiteSpace($agentStatusText)) { 'not ready' } else { $agentStatusText.Trim() }
            if (-not [string]::IsNullOrWhiteSpace($lastReadError) -and $lastReadError.Length -gt 180) { $lastReadError = $lastReadError.Substring(0,180) + ' [diagnostic truncated]' }
            $errorSuffix = if ([string]::IsNullOrWhiteSpace($lastReadError)) { '' } else { '; last Azure read: ' + $lastReadError }
            Write-ProdicloudActionProgress -Action ("vc-helper Guest Agent is '{0}' ({1}/2 stable checks, {2}s of {3}s maximum){4}" -f $statusText,$readySamples,$elapsedSeconds,$TimeoutSeconds,$errorSuffix)
        }
        Start-Sleep -Seconds 5
    }
    $timeoutDetail = if ([string]::IsNullOrWhiteSpace($lastReadError)) { '' } else { ' Last Azure read: ' + $lastReadError }
    throw ("vc-helper Guest Agent did not become Ready within {0} seconds; no disk cloning or cutover was attempted.{1}" -f $TimeoutSeconds,$timeoutDetail)
}

function Wait-ProdicloudResizeHelperVmProvisioned {
    param([psobject]$Helper,[ValidateRange(30,1800)][int]$TimeoutSeconds = 1200)
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $lastHeartbeat = 0
    $lastReadError = ''
    $provisioningState = 'Creating'
    $powerState = ''
    $readySamples = 0
    while ($watch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        Write-ProdicloudActionProgress -Action ("read temporary vc-helper '{0}' provisioning state" -f [string]$Helper.VmName)
        $powerState = ''
        try {
            $helperVmJson = az vm show -d -g ([string]$Helper.ResourceGroup) -n ([string]$Helper.VmName) --query '{id:id,provisioningState:provisioningState,powerState:powerState}' -o json --only-show-errors
            Assert-LastExitCode 'az vm show (vc-helper provisioning state)'
            $helperVmReadback = ConvertFrom-JsonCompat -InputObject ([string]$helperVmJson)
            $provisioningState = [string]$helperVmReadback.provisioningState
            $powerState = [string]$helperVmReadback.powerState
            if ([string]::Equals($provisioningState,'Failed',[System.StringComparison]::OrdinalIgnoreCase)) { throw "vc-helper provisioning failed; no disk attachment or cutover was attempted." }
            if ([string]::Equals($provisioningState,'Succeeded',[System.StringComparison]::OrdinalIgnoreCase) -and [string]::Equals($powerState,'VM running',[System.StringComparison]::OrdinalIgnoreCase)) {
                $readySamples++
                if ($readySamples -ge 2) {
                    if ([string]::IsNullOrWhiteSpace([string]$helperVmReadback.id)) { throw 'Azure reported the helper VM as provisioned without returning its resource id.' }
                    $Helper.ResourceId = [string]$helperVmReadback.id
                    return $Helper
                }
            }
            else { $readySamples = 0 }
            $lastReadError = ''
        }
        catch {
            if ([string]$_.Exception.Message -match 'provisioning failed|without returning its resource id') { throw }
            $lastReadError = [string]$_.Exception.Message
            $readySamples = 0
        }
        $elapsedSeconds = [int][Math]::Floor($watch.Elapsed.TotalSeconds)
        if (($elapsedSeconds - $lastHeartbeat) -ge 30) {
            $lastHeartbeat = $elapsedSeconds
            $stateText = if ([string]::IsNullOrWhiteSpace($provisioningState)) { 'creating' } else { $provisioningState }
            $powerText = if ([string]::IsNullOrWhiteSpace($powerState)) { 'unknown power state' } else { $powerState }
            $errorSuffix = if ([string]::IsNullOrWhiteSpace($lastReadError)) { '' } else { '; last Azure read: ' + $lastReadError }
            Write-ProdicloudActionProgress -Action ("vc-helper provisioning='{0}', power='{1}', stable={2}/2 ({3}s of {4}s maximum){5}" -f $stateText,$powerText,$readySamples,$elapsedSeconds,$TimeoutSeconds,$errorSuffix)
        }
        Start-Sleep -Seconds 5
    }
    throw ("vc-helper VM did not reach provisioning state Succeeded within {0} seconds; no disk attachment or cutover was attempted.{1}" -f $TimeoutSeconds,$(if ([string]::IsNullOrWhiteSpace($lastReadError)) { '' } else { ' Last Azure read: ' + $lastReadError }))
}

function Wait-ProdicloudResizeDiskReady {
    param(
        [string]$ResourceGroup,
        [string]$DiskName,
        [int]$ExpectedSizeGb = 0,
        [string]$ExpectedSku = '',
        [string]$ExpectedTier = '',
        [bool]$RequireHibernation = $false,
        [ValidateRange(30,1800)][int]$TimeoutSeconds = 600
    )
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $lastState = ''
    $lastHeartbeat = -30
    $lastReadError = ''
    while ($watch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        Write-ProdicloudActionProgress -Action ("read managed disk '{0}' provisioning, size, SKU, tier, and ownership" -f $DiskName)
        $diskOutput = @(az disk show -g $ResourceGroup -n $DiskName --query '{id:id,name:name,sizeGB:diskSizeGB,sku:sku.name,tier:tier,supportsHibernation:supportsHibernation,managedBy:managedBy,provisioningState:provisioningState,createOption:creationData.createOption}' -o json --only-show-errors 2>&1)
        $diskReadExitCode = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
        $diskReadText = @($diskOutput | ForEach-Object { [string]$_ }) -join "`n"
        if ($diskReadExitCode -eq 0) {
            $jsonMatch = [regex]::Match($diskReadText,'(?s)\{.*\}')
            if (-not $jsonMatch.Success) { throw ("Azure returned no disk JSON while checking '{0}'." -f $DiskName) }
            $disk = ConvertFrom-JsonCompat -InputObject $jsonMatch.Value
            $state = [string]$disk.provisioningState
            $lastState = $state
            $lastReadError = ''
            if ([string]::Equals($state,'Failed',[System.StringComparison]::OrdinalIgnoreCase)) { throw ("Managed disk '{0}' provisioning failed." -f $DiskName) }
            $isReady = [string]::Equals($state,'Succeeded',[System.StringComparison]::OrdinalIgnoreCase)
            if ($ExpectedSizeGb -gt 0 -and [int]$disk.sizeGB -ne $ExpectedSizeGb) { $isReady = $false }
            if (-not [string]::IsNullOrWhiteSpace($ExpectedSku) -and -not [string]::Equals([string]$disk.sku,$ExpectedSku,[System.StringComparison]::OrdinalIgnoreCase)) { $isReady = $false }
            if (-not [string]::IsNullOrWhiteSpace($ExpectedTier) -and -not [string]::Equals([string]$disk.tier,$ExpectedTier,[System.StringComparison]::OrdinalIgnoreCase)) { $isReady = $false }
            if ($RequireHibernation -and -not [bool]$disk.supportsHibernation) { $isReady = $false }
            if ($isReady) { return $disk }
        }
        else {
            $lastReadError = $diskReadText
            if ($lastReadError -notmatch '(?i)ResourceNotFound|ResourceGroupNotFound|\b404\b|was not found|not found|temporar|timeout|timed out|connection|service unavailable|anotheroperationinprogress|conflict') {
                throw ("az disk show (resize resource readiness) failed with exit code {0}: {1}" -f $diskReadExitCode,$lastReadError)
            }
        }
        $elapsedSeconds = [int][Math]::Floor($watch.Elapsed.TotalSeconds)
        if ($lastState -ne '' -or (($elapsedSeconds - $lastHeartbeat) -ge 30)) {
            if (($elapsedSeconds - $lastHeartbeat) -ge 30 -or -not [string]::IsNullOrWhiteSpace($lastReadError)) {
                $lastHeartbeat = $elapsedSeconds
                $stateText = if ([string]::IsNullOrWhiteSpace($lastState)) { 'not yet visible' } else { $lastState }
                $errorSuffix = if ([string]::IsNullOrWhiteSpace($lastReadError)) { '' } else { '; last read: ' + $lastReadError }
                Write-ProdicloudActionProgress -Action ("managed disk '{0}' is provisioning='{1}' ({2}s of {3}s maximum){4}" -f $DiskName,$stateText,$elapsedSeconds,$TimeoutSeconds,$errorSuffix)
            }
        }
        Start-Sleep -Seconds 5
    }
    throw ("Managed disk '{0}' did not reach the requested provisioned state within {1}s. Last state='{2}'." -f $DiskName,$TimeoutSeconds,$lastState)
}

function Confirm-ProdicloudResizeHelperOsDiskProfile {
    param([psobject]$Helper)
    $resizeProfile = Get-ProdicloudResizePerformanceProfile
    $resourceGroup = [string]$Helper.ResourceGroup
    $vmName = [string]$Helper.VmName
    Write-ProdicloudActionProgress -Action ("verify vc-helper '{0}' OS disk is {1} GiB {2} without a performance-tier update" -f $vmName,$resizeProfile.HelperOsDiskSizeGb,$resizeProfile.HelperOsDiskSku)
    $diskName = [string](az vm show -g $resourceGroup -n $vmName --query 'storageProfile.osDisk.name' -o tsv --only-show-errors)
    Assert-LastExitCode 'az vm show (vc-helper OS disk identity)'
    $diskName = $diskName.Trim()
    if ([string]::IsNullOrWhiteSpace($diskName)) { throw ("Azure did not return the managed OS disk name for vc-helper '{0}'." -f $vmName) }

    $disk = Wait-ProdicloudResizeDiskReady -ResourceGroup $resourceGroup -DiskName $diskName -ExpectedSizeGb ([int]$resizeProfile.HelperOsDiskSizeGb) -ExpectedSku ([string]$resizeProfile.HelperOsDiskSku) -TimeoutSeconds 600
    if ([int]$disk.sizeGB -ne [int]$resizeProfile.HelperOsDiskSizeGb -or [string]$disk.sku -ne [string]$resizeProfile.HelperOsDiskSku) {
        throw ("vc-helper OS disk profile verification failed for '{0}': expected {1} GiB {2}; actual {3} GiB {4}." -f $diskName,$resizeProfile.HelperOsDiskSizeGb,$resizeProfile.HelperOsDiskSku,[int]$disk.sizeGB,[string]$disk.sku)
    }
    return $disk
}

function Wait-ProdicloudResizeSnapshotReady {
    param([string]$ResourceGroup,[string]$SnapshotName,[ValidateRange(30,1800)][int]$TimeoutSeconds = 600)
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $lastState = ''
    $lastHeartbeat = -30
    while ($watch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        Write-ProdicloudActionProgress -Action ("read temporary source snapshot '{0}' provisioning state" -f $SnapshotName)
        $snapshot = $null
        $snapshotOutput = @(az snapshot show -g $ResourceGroup -n $SnapshotName --query '{id:id,provisioningState:provisioningState}' -o json --only-show-errors 2>&1)
        $snapshotExitCode = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
        $snapshotText = @($snapshotOutput | ForEach-Object { [string]$_ }) -join "`n"
        if ($snapshotExitCode -eq 0) {
            $snapshot = ConvertFrom-JsonCompat -InputObject $snapshotText
            $lastState = [string]$snapshot.provisioningState
        }
        else {
            if ($snapshotText -match '(?i)ResourceNotFound|ResourceGroupNotFound|\b404\b|was not found|not found|temporar|timeout|timed out|connection|service unavailable|anotheroperationinprogress|conflict') { $lastState = 'not yet visible' }
            else { throw ("az snapshot show (resize source snapshot readiness) failed with exit code {0}: {1}" -f $snapshotExitCode,$snapshotText) }
        }
        if ([string]::Equals($lastState,'Failed',[System.StringComparison]::OrdinalIgnoreCase)) { throw ("Source snapshot '{0}' entered provisioning state Failed." -f $SnapshotName) }
        if ($null -ne $snapshot -and [string]::Equals($lastState,'Succeeded',[System.StringComparison]::OrdinalIgnoreCase) -and -not [string]::IsNullOrWhiteSpace([string]$snapshot.id)) { return $snapshot }
        $elapsedSeconds = [int][Math]::Floor($watch.Elapsed.TotalSeconds)
        if (($elapsedSeconds - $lastHeartbeat) -ge 30) {
            $lastHeartbeat = $elapsedSeconds
            Write-ProdicloudActionProgress -Action ("source snapshot '{0}' is provisioning='{1}' ({2}s of {3}s maximum)" -f $SnapshotName,$lastState,$elapsedSeconds,$TimeoutSeconds)
        }
        Start-Sleep -Seconds 5
    }
    throw ("Source snapshot '{0}' did not reach Succeeded within {1}s; last state='{2}'." -f $SnapshotName,$TimeoutSeconds,$lastState)
}

function Wait-ProdicloudResizeDiskAttachment {
    param(
        [string]$VmResourceGroup,
        [string]$VmName,
        [string]$DiskResourceGroup,
        [string]$DiskName,
        [string]$DiskId,
        [ValidateSet('os','data')][string]$DiskKind,
        [int]$Lun = -1,
        [bool]$ShouldBeAttached = $true,
        [ValidateRange(30,900)][int]$TimeoutSeconds = 300
    )
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $lastState = ''
    $lastHeartbeat = -30
    $diskIdNormalized = ([string]$DiskId).TrimEnd('/').ToLowerInvariant()
    while ($watch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        Write-ProdicloudActionProgress -Action ("read VM '{0}' disk profile for '{1}' attachment at {2}" -f $VmName,$DiskName,$(if ($DiskKind -eq 'os') { 'OS disk' } else { ('LUN {0}' -f $Lun) }))
        $vmJson = az vm show -g $VmResourceGroup -n $VmName --query '{id:id,osDiskId:storageProfile.osDisk.managedDisk.id,dataDisks:storageProfile.dataDisks[].{id:managedDisk.id,lun:lun}}' -o json --only-show-errors
        Assert-LastExitCode 'az vm show (resize disk attachment verification)'
        $vm = ConvertFrom-JsonCompat -InputObject (@($vmJson) -join "`n")
        $vmId = ([string]$vm.id).TrimEnd('/').ToLowerInvariant()
        $diskIsInVmModel = $false
        if ($DiskKind -eq 'os') {
            $diskIsInVmModel = [string]::Equals(([string]$vm.osDiskId).TrimEnd('/'),[string]$DiskIdNormalized,[System.StringComparison]::OrdinalIgnoreCase)
        }
        else {
            $dataDisks = @(ConvertTo-ObjectArrayCompat -InputObject $vm.dataDisks)
            $matchingDataDisks = @($dataDisks | Where-Object {
                [string]::Equals(([string]$_.id).TrimEnd('/'),[string]$DiskIdNormalized,[System.StringComparison]::OrdinalIgnoreCase) -and [int]$_.lun -eq $Lun
            })
            $diskIsInVmModel = ($matchingDataDisks.Count -eq 1)
        }
        Write-ProdicloudActionProgress -Action ("read managed disk '{0}' owner after VM profile update" -f $DiskName)
        $diskJson = az disk show -g $DiskResourceGroup -n $DiskName --query '{managedBy:managedBy,provisioningState:provisioningState}' -o json --only-show-errors
        Assert-LastExitCode 'az disk show (resize disk attachment verification)'
        $disk = ConvertFrom-JsonCompat -InputObject (@($diskJson) -join "`n")
        $managedBy = ([string]$disk.managedBy).TrimEnd('/').ToLowerInvariant()
        $diskOwnedByVm = [string]::Equals($managedBy,$vmId,[System.StringComparison]::OrdinalIgnoreCase)
        $diskProvisioned = [string]::Equals([string]$disk.provisioningState,'Succeeded',[System.StringComparison]::OrdinalIgnoreCase)
        $ready = if ($ShouldBeAttached) { $diskIsInVmModel -and $diskOwnedByVm -and $diskProvisioned } else { -not $diskIsInVmModel -and [string]::IsNullOrWhiteSpace($managedBy) -and $diskProvisioned }
        if ($ready) { return $true }
        $lastState = ("vm-model={0}; managedBy={1}; provisioning={2}" -f $diskIsInVmModel,$managedBy,[string]$disk.provisioningState)
        $elapsedSeconds = [int][Math]::Floor($watch.Elapsed.TotalSeconds)
        if (($elapsedSeconds - $lastHeartbeat) -ge 30) {
            $lastHeartbeat = $elapsedSeconds
            Write-ProdicloudActionProgress -Action ("disk '{0}' attachment is stabilizing ({1}s of {2}s maximum): {3}" -f $DiskName,$elapsedSeconds,$TimeoutSeconds,$lastState)
        }
        Start-Sleep -Seconds 5
    }
    throw ("Disk '{0}' attachment did not stabilize within {1}s. Expected attached={2}, VM='{3}', kind='{4}', LUN={5}; last state: {6}." -f $DiskName,$TimeoutSeconds,$ShouldBeAttached,$VmName,$DiskKind,$Lun,$lastState)
}

function Wait-ProdicloudResizeResourceGroupReady {
    param([string]$ResourceGroup,[ValidateRange(30,600)][int]$TimeoutSeconds = 300)
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $lastState = ''
    $lastHeartbeat = -30
    while ($watch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        Write-ProdicloudActionProgress -Action ("read temporary resource group '{0}' provisioning state" -f $ResourceGroup)
        $stateOutput = @(az group show -n $ResourceGroup --query 'properties.provisioningState' -o tsv --only-show-errors 2>&1)
        $stateExitCode = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
        $stateText = @($stateOutput | ForEach-Object { [string]$_ }) -join "`n"
        if ($stateExitCode -eq 0) {
            $lastState = [string]$stateText.Trim()
        }
        elseif ($stateText -match '(?i)ResourceGroupNotFound|ResourceNotFound|\b404\b|was not found|not found|temporar|timeout|timed out|connection|service unavailable|anotheroperationinprogress|conflict') {
            $lastState = 'not yet visible'
        }
        else { throw ("az group show (temporary resize resource-group readiness) failed with exit code {0}: {1}" -f $stateExitCode,$stateText) }
        if ([string]::Equals($lastState,'Succeeded',[System.StringComparison]::OrdinalIgnoreCase)) { return $true }
        if ([string]::Equals($lastState,'Failed',[System.StringComparison]::OrdinalIgnoreCase)) { throw ("Temporary resource group '{0}' entered provisioning state Failed." -f $ResourceGroup) }
        $elapsedSeconds = [int][Math]::Floor($watch.Elapsed.TotalSeconds)
        if (($elapsedSeconds - $lastHeartbeat) -ge 30) {
            $lastHeartbeat = $elapsedSeconds
            Write-ProdicloudActionProgress -Action ("temporary resource group '{0}' is provisioning='{1}' ({2}s of {3}s maximum)" -f $ResourceGroup,$lastState,$elapsedSeconds,$TimeoutSeconds)
        }
        Start-Sleep -Seconds 5
    }
    throw ("Temporary resource group '{0}' did not reach Succeeded within {1}s; last state='{2}'." -f $ResourceGroup,$TimeoutSeconds,$lastState)
}

function New-ProdicloudResizeHelperVm {
    param(
        [psobject]$VmObject,
        [string]$ResourceGroup,
        [string]$VmName,
        [string]$Region,
        [string]$Platform,
        [psobject]$Runtime
    )
    $image = $VmObject.storageProfile.imageReference
    $helperImageVersion = if (-not [string]::IsNullOrWhiteSpace([string]$image.exactVersion)) { [string]$image.exactVersion } elseif (-not [string]::IsNullOrWhiteSpace([string]$image.version)) { [string]$image.version } else { 'latest' }
    $targetImageSpec = if (-not [string]::IsNullOrWhiteSpace([string]$image.id)) { [string]$image.id } elseif (-not [string]::IsNullOrWhiteSpace([string]$image.publisher) -and -not [string]::IsNullOrWhiteSpace([string]$image.offer) -and -not [string]::IsNullOrWhiteSpace([string]$image.sku)) { '{0}:{1}:{2}:{3}' -f [string]$image.publisher,[string]$image.offer,[string]$image.sku,$helperImageVersion } else { '' }
    # Use the standard Datacenter Core image rather than Azure Edition Core.
    # Azure Edition is Hotpatch-compatible and requires AutomaticByPlatform
    # patch settings; disk attach/update calls can otherwise be rejected while
    # Azure validates the helper VM model. The helper is temporary and does not
    # need Hotpatch, so keep its patch configuration explicit and conventional.
    $imageSpec = if ($Platform -eq 'windows') { 'MicrosoftWindowsServer:WindowsServer:2022-datacenter-core:latest' } else { [string]$targetImageSpec }
    if ([string]::IsNullOrWhiteSpace([string]$imageSpec)) { throw 'OS disk shrink requires a VM with a resolvable marketplace or gallery image for vc-helper.' }
    if ($Platform -eq 'windows') {
        Write-ProdicloudActionProgress -Action ("verify lightweight Windows Server Core vc-helper image in '{0}'" -f $Region)
        $helperImageId = [string](az vm image show -l $Region --urn $imageSpec --query id -o tsv --only-show-errors)
        Assert-LastExitCode 'az vm image show (Windows Server Core vc-helper image)'
        if ([string]::IsNullOrWhiteSpace($helperImageId)) { throw 'Azure did not confirm the Windows Server Core vc-helper image in the target region.' }
    }
    $vmSecurityType = [string]$VmObject.securityProfile.securityType
    if (-not [string]::IsNullOrWhiteSpace([string]$vmSecurityType) -and $vmSecurityType -notin @('Standard','')) { throw ("OS disk shrink does not support security type '{0}' in the current helper workflow." -f $vmSecurityType) }
    $adminUser = [string]$Runtime.Context.VmUser
    $adminPassword = [string]$Runtime.Context.VmPass
    if ([string]::IsNullOrWhiteSpace($adminUser) -or [string]::IsNullOrWhiteSpace($adminPassword)) { throw 'vc-helper requires the selected VC manager credentials from its local VC profile.' }
    $targetSize = [string]$VmObject.hardwareProfile.vmSize
    if ([string]::IsNullOrWhiteSpace($targetSize)) { throw 'vc-helper could not resolve a verified VM size from the existing target.' }
    $performanceProfile = Get-ProdicloudResizePerformanceProfile
    $helperSize = [string]$performanceProfile.HelperVmSize
    Write-ProdicloudActionProgress -Action ("use temporary vc-helper size '{0}' with {1} GiB {2} OS storage and no tier update; the target VM remains '{3}'" -f $helperSize,$performanceProfile.HelperOsDiskSizeGb,$performanceProfile.HelperOsDiskSku,$targetSize)
    $stamp = [DateTime]::UtcNow.ToString('yyMMddHHmmss') + (Get-Random -Minimum 10 -Maximum 99)
    $safeVmSegment = ([string]$VmName -replace '[^a-zA-Z0-9-]','-').ToLowerInvariant()
    if ($safeVmSegment.Length -gt 38) { $safeVmSegment = $safeVmSegment.Substring(0,38).TrimEnd('-') }
    $helperGroup = ('rg-prodicloud-vc-helper-{0}-{1}' -f $safeVmSegment,$stamp).ToLowerInvariant()
    $helperVm = 'vc-helper'
    $tags = @('managed-by=prodicloud','prodicloud-role=temporary-vc-helper','prodicloud-target=' + $VmName)
    Invoke-TrackedAction -Label ("az group create -n {0} -l {1} (temporary vc-helper)" -f $helperGroup,$Region) -Action {
        az group create -n $helperGroup -l $Region --tags @tags -o none --only-show-errors
        Assert-LastExitCode 'az group create (temporary vc-helper)'
    } | Out-Null
    # az group create is synchronous; launch the no-wait helper VM immediately after its success.
    try {
        $arguments = @(
            'vm','create','--resource-group',$helperGroup,'--name',$helperVm,
            '--image',$imageSpec,'--size',$helperSize,
            '--admin-username',$adminUser,'--admin-password',$adminPassword,'--authentication-type','password',
            '--enable-agent','--enable-auto-update','true','--patch-mode','AutomaticByOS',
            '--storage-sku',[string]$performanceProfile.HelperOsDiskSku,'--os-disk-size-gb',[string][int]$performanceProfile.HelperOsDiskSizeGb,'--public-ip-address','','--nsg','',
            '--tags','managed-by=prodicloud','prodicloud-role=temporary-vc-helper','prodicloud-target=' + $VmName,
            '--no-wait','-o','none','--only-show-errors'
        )
        Write-ProdicloudActionProgress -Action ("create temporary vc-helper in '{0}' without a public IP" -f $Region)
        Invoke-ProdicloudWithAzCliTimeoutSeconds -TimeoutSeconds 1200 -Action {
            Invoke-TrackedAction -Label ("az vm create -g {0} -n vc-helper (credentials redacted)" -f $helperGroup) -Action {
                az @arguments
                Assert-LastExitCode 'az vm create (temporary vc-helper)'
            } | Out-Null
        } | Out-Null
        $subscription = Get-ProdicloudResolvedSubscriptionContext
        $helperResourceId = '/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.Compute/virtualMachines/{2}' -f [string]$subscription.SubscriptionId,$helperGroup,$helperVm
        return [pscustomobject]@{ ResourceGroup = $helperGroup; VmName = $helperVm; Region = $Region; Platform = $Platform; Image = $imageSpec; Size = $helperSize; ResourceId = $helperResourceId; SubscriptionId = [string]$subscription.SubscriptionId; TargetResourceGroup = $ResourceGroup; TargetVmName = $VmName }
    }
    catch {
        try { Remove-ProdicloudResizeHelper -Helper ([pscustomobject]@{ ResourceGroup = $helperGroup; VmName = $helperVm }) -DeferWait }
        catch { Write-Warning ("Temporary vc-helper cleanup after provisioning failure also failed: {0}" -f [string]$_.Exception.Message) }
        throw
    }
}

function ConvertFrom-ProdicloudResizeHelperMetricPayload {
    param([string]$Json)
    if ([string]::IsNullOrWhiteSpace([string]$Json)) { return $null }
    try { $payload = ConvertFrom-JsonCompat -InputObject $Json }
    catch { return $null }
    $metricValues = @{
        'Data Disk Read Bytes/sec' = 'DataDiskReadBytesPerSecond'
        'Data Disk Write Bytes/sec' = 'DataDiskWriteBytesPerSecond'
        'OS Disk Read Bytes/sec' = 'OsDiskReadBytesPerSecond'
        'OS Disk Write Bytes/sec' = 'OsDiskWriteBytesPerSecond'
        'Network In' = 'NetworkInBytesPerSecond'
        'Network Out' = 'NetworkOutBytesPerSecond'
        'Percentage CPU' = 'CpuPercent'
        'Available Memory Bytes' = 'AvailableMemoryBytes'
    }
    $result = [ordered]@{
        SampleAtUtc = [DateTime]::MinValue
        DataDiskReadBytesPerSecond = [double]0
        DataDiskWriteBytesPerSecond = [double]0
        OsDiskReadBytesPerSecond = [double]0
        OsDiskWriteBytesPerSecond = [double]0
        NetworkInBytesPerSecond = [double]0
        NetworkOutBytesPerSecond = [double]0
        CpuPercent = [double]0
        AvailableMemoryBytes = [double]0
    }
    foreach ($metric in @(ConvertTo-ObjectArrayCompat -InputObject $payload.value)) {
        $metricName = if ($null -ne $metric.name -and $null -ne $metric.name.PSObject.Properties['value']) { [string]$metric.name.value } else { [string]$metric.name }
        if (-not $metricValues.ContainsKey($metricName)) { continue }
        $points = @(
            foreach ($series in @(ConvertTo-ObjectArrayCompat -InputObject $metric.timeseries)) {
                foreach ($point in @(ConvertTo-ObjectArrayCompat -InputObject $series.data)) {
                    if ($null -eq $point.average -or [string]::IsNullOrWhiteSpace([string]$point.timeStamp)) { continue }
                    try {
                        $pointTime = if ($point.timeStamp -is [DateTime]) { ([DateTime]$point.timeStamp).ToUniversalTime() } else { [DateTime]::Parse([string]$point.timeStamp,[System.Globalization.CultureInfo]::InvariantCulture,[System.Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime() }
                        [pscustomobject]@{ Time = $pointTime; Value = [double]$point.average }
                    }
                    catch { }
                }
            }
        )
        if ($points.Count -eq 0) { continue }
        $latestTime = [DateTime]::MinValue
        foreach ($point in $points) { if ([DateTime]$point.Time -gt $latestTime) { $latestTime = [DateTime]$point.Time } }
        $latestValues = @($points | Where-Object { [DateTime]$_.Time -eq $latestTime } | ForEach-Object { [double]$_.Value })
        $sum = [double]0
        foreach ($value in $latestValues) { $sum += [double]$value }
        $targetKey = [string]$metricValues[$metricName]
        $result[$targetKey] = $sum
        if ($latestTime -gt [DateTime]$result.SampleAtUtc) { $result.SampleAtUtc = $latestTime }
    }
    if ([DateTime]$result.SampleAtUtc -eq [DateTime]::MinValue) { return $null }
    return [pscustomobject]$result
}

function Get-ProdicloudResizeHelperActivityMetrics {
    param([psobject]$Helper)
    if ([string]::IsNullOrWhiteSpace([string]$Helper.ResourceId) -or [string]::IsNullOrWhiteSpace([string]$Helper.SubscriptionId)) { return $null }
    $endTime = [DateTime]::UtcNow
    $startTime = $endTime.AddMinutes(-5)
    $previousAzTimeoutSeconds = [int]$script:AzCommandTimeoutSeconds
    $script:AzCommandTimeoutSeconds = [Math]::Min(60,[Math]::Max(30,$previousAzTimeoutSeconds))
    try {
        $raw = az monitor metrics list `
            --subscription ([string]$Helper.SubscriptionId) `
            --resource ([string]$Helper.ResourceId) `
            --metrics 'Data Disk Read Bytes/sec' 'Data Disk Write Bytes/sec' 'OS Disk Read Bytes/sec' 'OS Disk Write Bytes/sec' 'Network In' 'Network Out' 'Percentage CPU' 'Available Memory Bytes' `
            --start-time ($startTime.ToString('yyyy-MM-ddTHH:mm:ssZ')) `
            --end-time ($endTime.ToString('yyyy-MM-ddTHH:mm:ssZ')) `
            --interval PT1M --aggregation Average -o json --only-show-errors
        Assert-LastExitCode 'az monitor metrics list (vc-helper activity)'
        $jsonText = @($raw | ForEach-Object { [string]$_ }) -join "`n"
        return (ConvertFrom-ProdicloudResizeHelperMetricPayload -Json $jsonText)
    }
    catch { return $null }
    finally { $script:AzCommandTimeoutSeconds = $previousAzTimeoutSeconds }
}

function Stop-ProdicloudResizeHelperAzProcessTree {
    param([string]$ProcessIdPath,[string]$ActionLabel)
    if ([string]::IsNullOrWhiteSpace([string]$ProcessIdPath) -or -not (Test-Path -LiteralPath $ProcessIdPath -PathType Leaf)) { return $false }
    $marker = [string](Get-Content -LiteralPath $ProcessIdPath -Raw -ErrorAction Stop)
    if ($marker -notmatch '^\s*(?<pid>\d+)\|(?<startTicks>\d+)\s*$') { return $false }
    $processId = 0
    $startTicks = [long]0
    if (-not [int]::TryParse([string]$Matches.pid,[ref]$processId) -or -not [long]::TryParse([string]$Matches.startTicks,[ref]$startTicks) -or $processId -lt 1 -or $processId -eq $PID) { return $false }
    $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
    if ($null -eq $process) { return $true }
    try { $actualStartTicks = [long]$process.StartTime.ToUniversalTime().Ticks }
    catch { return $false }
    if ($actualStartTicks -ne $startTicks) { return $false }
    Write-ProdicloudActionProgress -Action ("stop timed-out Azure CLI helper request for '{0}' and its child processes" -f $ActionLabel)
    $taskKillPath = Join-Path ([string]$env:SystemRoot) 'System32\taskkill.exe'
    if (Test-Path -LiteralPath $taskKillPath -PathType Leaf) {
        $stopper = Start-Process -FilePath $taskKillPath -ArgumentList @('/PID',[string]$processId,'/T','/F') -WindowStyle Hidden -PassThru -Wait -ErrorAction Stop
        if ([int]$stopper.ExitCode -ne 0 -and $null -ne (Get-Process -Id $processId -ErrorAction SilentlyContinue)) {
            throw ("taskkill could not stop the Azure CLI helper request process tree (exit {0})." -f [int]$stopper.ExitCode)
        }
    }
    else {
        $process.Kill()
        if (-not $process.WaitForExit(10000)) { throw 'Timed-out Azure CLI helper request process did not exit after termination.' }
    }
    return $true
}

function Get-ProdicloudResizeManagedRunCommandState {
    param([psobject]$Response)
    $instanceView = $Response.instanceView
    if ($null -eq $instanceView -and $null -ne $Response.properties) { $instanceView = $Response.properties.instanceView }
    if ($null -eq $instanceView) { return [pscustomobject]@{ State = 'Starting'; ExitCode = $null; Output = ''; Error = ''; StartTime = ''; EndTime = '' } }
    $state = [string]$instanceView.executionState
    if ([string]::IsNullOrWhiteSpace($state)) {
        $stateRows = @(ConvertTo-ObjectArrayCompat -InputObject $instanceView.statuses)
        $executionRow = @($stateRows | Where-Object { [string]$_.code -match '(?i)executionstate|execution/state' } | Select-Object -Last 1)
        if ($executionRow.Count -gt 0) { $state = [string]$executionRow[0].displayStatus }
    }
    if ([string]::IsNullOrWhiteSpace($state)) { $state = 'Starting' }
    $exitCode = $null
    if ($null -ne $instanceView.exitCode -and -not [string]::IsNullOrWhiteSpace([string]$instanceView.exitCode)) {
        try { $exitCode = [int]$instanceView.exitCode } catch { }
    }
    $output = if ($instanceView.output -is [string]) { [string]$instanceView.output } elseif ($null -ne $instanceView.output.output) { [string]$instanceView.output.output } else { '' }
    $errorText = if ($instanceView.error -is [string]) { [string]$instanceView.error } elseif ($null -ne $instanceView.error.message) { [string]$instanceView.error.message } else { '' }
    return [pscustomobject]@{
        State = $state
        ExitCode = $exitCode
        Output = $output
        Error = $errorText
        StartTime = [string]$instanceView.startTime
        EndTime = [string]$instanceView.endTime
    }
}

function Invoke-ProdicloudResizeManagedRunCommand {
    param(
        [psobject]$Helper,
        [string]$ScriptText,
        [string]$ActionLabel,
        [ValidateRange(1,7200)][int]$ExecutionTimeoutSeconds = 3600
    )
    $runCommandName = ('prodicloud-rz-{0}' -f [guid]::NewGuid().ToString('N'))
    $previousTimeoutSeconds = [int]$script:AzCommandTimeoutSeconds
    $script:AzCommandTimeoutSeconds = 180
    $startedAtUtc = [DateTime]::UtcNow
    $lastReportSeconds = -30
    $lastMetricsSeconds = 0
    $lastMetricSampleUtc = $startedAtUtc
    $lastGuestProgressUtc = $startedAtUtc
    $lastProgressMarker = ''
    $lastPhase = 'starting'
    $lastReportedResizePhase = ''
    $consecutiveIdleSamples = 0
    $latestOutput = ''
    $lastState = 'Starting'
    $reportedGuestCopyWarnings = @{}
    $managedScriptPath = Join-Path ([System.IO.Path]::GetTempPath()) ('prodicloud-resize-managed-runcommand-{0}.ps1' -f [guid]::NewGuid().ToString('N'))
    $managedScriptWritten = $false
    try {
        [System.IO.File]::WriteAllText($managedScriptPath,[string]$ScriptText,([System.Text.UTF8Encoding]::new($false)))
        $managedScriptWritten = $true
        Write-ProdicloudActionProgress -Action ("start asynchronous managed Run Command for vc-helper '{0}'" -f $ActionLabel)
        $createOutput = az vm run-command create `
            --subscription ([string]$Helper.SubscriptionId) `
            -g ([string]$Helper.ResourceGroup) `
            --vm-name ([string]$Helper.VmName) `
            --name $runCommandName `
            --location ([string]$Helper.Region) `
            --script ('@' + $managedScriptPath) `
            --async-execution true `
            --timeout-in-seconds ([string]$ExecutionTimeoutSeconds) `
            -o json --only-show-errors
        Assert-LastExitCode 'az vm run-command create (asynchronous resize helper)'
        $script:AzCommandTimeoutSeconds = [Math]::Max(30,[Math]::Min($previousTimeoutSeconds,180))

        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        while ($watch.Elapsed.TotalSeconds -lt $ExecutionTimeoutSeconds) {
            $elapsedSeconds = [int][Math]::Floor($watch.Elapsed.TotalSeconds)
            $runCommandOutput = $null
            $showSucceeded = $false
            $showErrorText = ''
            for ($showAttempt = 1; $showAttempt -le 3; $showAttempt++) {
                try {
                    $pollLabel = if ($showAttempt -eq 1) { "read managed resize Run Command status '{0}'" -f $runCommandName } else { "retry managed resize Run Command status '{0}' (attempt {1}/3)" -f $runCommandName,$showAttempt }
                    Write-ProdicloudActionProgress -Action $pollLabel
                    $runCommandOutput = az vm run-command show `
                        --subscription ([string]$Helper.SubscriptionId) `
                        -g ([string]$Helper.ResourceGroup) `
                        --vm-name ([string]$Helper.VmName) `
                        --name $runCommandName --instance-view -o json --only-show-errors
                    Assert-LastExitCode 'az vm run-command show (asynchronous resize helper)'
                    $showSucceeded = $true
                    break
                }
                catch {
                    $showErrorText = [string]$_.Exception.Message
                    if ($showAttempt -ge 3) { break }
                    $backoffSeconds = [Math]::Min(15,5 * $showAttempt)
                    Write-Warning ("Managed resize status request failed ({0}/3): {1}. Retrying in {2}s; guest command remains active." -f $showAttempt,$showErrorText,$backoffSeconds)
                    Start-Sleep -Seconds $backoffSeconds
                }
            }
            if (-not $showSucceeded) { throw ("Managed resize Run Command status remained unavailable after three attempts; guest phase '{0}' is retained for diagnostics. Last status error: {1}" -f $lastPhase,$showErrorText) }
            $runCommandJson = @($runCommandOutput | ForEach-Object { [string]$_ }) -join "`n"
            $runCommand = ConvertFrom-JsonCompat -InputObject $runCommandJson
            $state = Get-ProdicloudResizeManagedRunCommandState -Response $runCommand
            $lastState = [string]$state.State
            $latestOutput = [string]$state.Output
            if (-not [string]::IsNullOrWhiteSpace([string]$state.Error)) { $latestOutput = (@($latestOutput,[string]$state.Error) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) -join "`n" }

            $markers = @($latestOutput -split "`r?`n" | Where-Object { $_ -match 'PRODICLOUD_RESIZE_(?:PHASE|PROGRESS):' })
            if ($markers.Count -gt 0) {
                $lastProgressMarker = [string]$markers[-1]
                $markerStart = $lastProgressMarker.IndexOf('{')
                if ($markerStart -ge 0) {
                    try {
                        $progressRecord = ConvertFrom-JsonCompat -InputObject $lastProgressMarker.Substring($markerStart)
                        if (-not [string]::IsNullOrWhiteSpace([string]$progressRecord.phase)) { $lastPhase = [string]$progressRecord.phase }
                        foreach ($guestWarning in @(ConvertTo-ObjectArrayCompat -InputObject $progressRecord.copyWarnings)) {
                            $warningKey = [string]$guestWarning.message
                            if (-not [string]::IsNullOrWhiteSpace($warningKey) -and -not $reportedGuestCopyWarnings.ContainsKey($warningKey)) {
                                $reportedGuestCopyWarnings[$warningKey] = $true
                                Write-Warning ("Resize guest copy policy: {0}" -f $warningKey)
                            }
                        }
                        $markerUtcText = [string]$progressRecord.heartbeatAtUtc
                        if ([string]::IsNullOrWhiteSpace($markerUtcText)) { $markerUtcText = [string]$progressRecord.progressAtUtc }
                        if ([string]::IsNullOrWhiteSpace($markerUtcText)) { $markerUtcText = [string]$progressRecord.timestampUtc }
                        $markerUtc = [DateTime]::MinValue
                        if ([DateTime]::TryParse($markerUtcText,[ref]$markerUtc) -and $markerUtc.ToUniversalTime() -gt $lastGuestProgressUtc) { $lastGuestProgressUtc = $markerUtc.ToUniversalTime() }
                    }
                    catch { }
                }
            }

            if ($lastState -match '(?i)^succeeded$' -or ($lastState -match '(?i)succeeded' -and $null -ne $state.ExitCode)) {
                if ($null -ne $state.ExitCode -and [int]$state.ExitCode -ne 0) { throw ("Managed resize Run Command failed in phase '{0}' with exit code {1}: {2}" -f $lastPhase,[int]$state.ExitCode,$latestOutput) }
                $resultLine = @($latestOutput -split "`r?`n" | Where-Object { $_ -match 'PRODICLOUD_RESIZE_RESULT:' } | Select-Object -Last 1)
                if ($resultLine.Count -eq 0) { throw ("Managed resize Run Command succeeded without a structured guest result in phase '{0}'. Output: {1}" -f $lastPhase,$latestOutput) }
                $payloadText = ([string]$resultLine[0]) -replace '^.*PRODICLOUD_RESIZE_RESULT:',''
                $structured = ConvertFrom-JsonCompat -InputObject $payloadText
                if ([string]$structured.status -ne 'ok') { throw ("Windows resize guest step '{0}' failed during phase '{1}': {2}" -f $ActionLabel,$lastPhase,[string]$structured.message) }
                foreach ($guestWarning in @(ConvertTo-ObjectArrayCompat -InputObject $structured.copyWarnings)) {
                    $warningKey = [string]$guestWarning.message
                    if (-not [string]::IsNullOrWhiteSpace($warningKey) -and -not $reportedGuestCopyWarnings.ContainsKey($warningKey)) {
                        $reportedGuestCopyWarnings[$warningKey] = $true
                        Write-Warning ("Resize guest copy policy: {0}" -f $warningKey)
                    }
                }
                Write-ProdicloudActionProgress -Action ("managed resize Run Command '{0}' completed in {1}s (phase '{2}')" -f $runCommandName,$elapsedSeconds,$lastPhase)
                # The unique temporary helper VM/resource group is deleted by the caller after the copy.
                # Let that parent cleanup remove this child resource instead of waiting on a second ARM delete.
                return $structured
            }
            if ($lastState -match '(?i)^failed$' -or ($lastState -match '(?i)failed' -and $null -ne $state.ExitCode)) {
                throw ("Managed resize Run Command failed in phase '{0}' (exit {1}): {2}" -f $lastPhase,[string]$state.ExitCode,$latestOutput)
            }
            if ($state.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($latestOutput) -and $latestOutput -match 'PRODICLOUD_RESIZE_RESULT:') {
                $resultLine = @($latestOutput -split "`r?`n" | Where-Object { $_ -match 'PRODICLOUD_RESIZE_RESULT:' } | Select-Object -Last 1)
                if ($resultLine.Count -gt 0) {
                    $payloadText = ([string]$resultLine[0]) -replace '^.*PRODICLOUD_RESIZE_RESULT:',''
                    $structured = ConvertFrom-JsonCompat -InputObject $payloadText
                    if ([string]$structured.status -eq 'ok') {
                        foreach ($guestWarning in @(ConvertTo-ObjectArrayCompat -InputObject $structured.copyWarnings)) {
                            $warningKey = [string]$guestWarning.message
                            if (-not [string]::IsNullOrWhiteSpace($warningKey) -and -not $reportedGuestCopyWarnings.ContainsKey($warningKey)) {
                                $reportedGuestCopyWarnings[$warningKey] = $true
                                Write-Warning ("Resize guest copy policy: {0}" -f $warningKey)
                            }
                        }
                        return $structured
                    }
                }
            }

            if ($lastPhase -ne $lastReportedResizePhase -or ($elapsedSeconds - $lastReportSeconds) -ge 30) {
                $lastReportedResizePhase = $lastPhase
                $lastReportSeconds = $elapsedSeconds
                Write-ProdicloudActionProgress -Action ("managed resize guest step '{0}' running ({1}s elapsed; state='{2}'; phase='{3}')" -f $ActionLabel,$elapsedSeconds,$lastState,$lastPhase)
                if (-not [string]::IsNullOrWhiteSpace($lastProgressMarker)) { Write-Host ("Resize progress: {0}" -f $lastProgressMarker) -ForegroundColor DarkGray }
            }

            if (($elapsedSeconds - $lastMetricsSeconds) -ge 60) {
                $lastMetricsSeconds = $elapsedSeconds
                $metrics = Get-ProdicloudResizeHelperActivityMetrics -Helper $Helper
                if ($null -ne $metrics -and [DateTime]$metrics.SampleAtUtc -gt $startedAtUtc -and [DateTime]$metrics.SampleAtUtc -gt $lastMetricSampleUtc) {
                    $lastMetricSampleUtc = [DateTime]$metrics.SampleAtUtc
                    $diskRead = [double]$metrics.DataDiskReadBytesPerSecond + [double]$metrics.OsDiskReadBytesPerSecond
                    $diskWrite = [double]$metrics.DataDiskWriteBytesPerSecond + [double]$metrics.OsDiskWriteBytesPerSecond
                    $network = [double]$metrics.NetworkInBytesPerSecond + [double]$metrics.NetworkOutBytesPerSecond
                    $hasActivity = ($diskRead -ge 1MB) -or ($diskWrite -ge 1MB) -or ($network -ge 64KB) -or ([double]$metrics.CpuPercent -ge 3)
                    if ($hasActivity) {
                        $consecutiveIdleSamples = 0
                        Write-ProdicloudActionProgress -Action ("vc-helper activity: CPU={0:N0}%; disk read={1:N1} MiB/s, write={2:N1} MiB/s; network={3:N1} MiB/s; free RAM={4:N0} MiB" -f [double]$metrics.CpuPercent,($diskRead / 1MB),($diskWrite / 1MB),($network / 1MB),([double]$metrics.AvailableMemoryBytes / 1MB))
                    }
                    else {
                        $guestProgressAge = ([DateTime]::UtcNow - $lastGuestProgressUtc).TotalSeconds
                        if ($guestProgressAge -lt 90) {
                            Write-ProdicloudActionProgress -Action ("Azure Monitor is idle, but guest phase '{0}' reported progress {1}s ago; continuing bounded run" -f $lastPhase,[int]$guestProgressAge)
                        }
                        else {
                            $consecutiveIdleSamples++
                            Write-Warning ("vc-helper has no measurable Azure or guest activity in fresh sample {0}/3 (phase '{1}', last guest progress {2}s ago)." -f $consecutiveIdleSamples,$lastPhase,[int]$guestProgressAge)
                            if ($consecutiveIdleSamples -ge 3) {
                                throw ("Resize helper step '{0}' stalled during phase '{1}': three fresh Azure Monitor samples and guest progress checks showed no activity. Last output: {2}" -f $ActionLabel,$lastPhase,$latestOutput)
                            }
                        }
                    }
                }
            }
            if ($watch.Elapsed.TotalSeconds -lt $ExecutionTimeoutSeconds) { Start-Sleep -Seconds 10 }
        }
        $watch.Stop()
        throw ("Resize helper step '{0}' exceeded its {1}-second execution bound during phase '{2}' (state '{3}'). Last output: {4}" -f $ActionLabel,$ExecutionTimeoutSeconds,$lastPhase,$lastState,$latestOutput)
    }
    catch {
        throw
    }
    finally {
        if ($managedScriptWritten -and (Test-Path -LiteralPath $managedScriptPath -PathType Leaf)) { Remove-Item -LiteralPath $managedScriptPath -Force -ErrorAction SilentlyContinue }
        $script:AzCommandTimeoutSeconds = $previousTimeoutSeconds
    }
}

function Invoke-ProdicloudResizeHelperScript {
    param(
        [psobject]$Helper,
        [string]$ScriptText,
        [string]$ActionLabel,
        [ValidateRange(1,7200)][int]$ExecutionTimeoutSeconds = 3600
    )
    if ([string]$Helper.Platform -eq 'windows') {
        return (Invoke-ProdicloudResizeManagedRunCommand -Helper $Helper -ScriptText $ScriptText -ActionLabel $ActionLabel -ExecutionTimeoutSeconds $ExecutionTimeoutSeconds)
    }
    $commandId = if ([string]$Helper.Platform -eq 'windows') { 'RunPowerShellScript' } else { 'RunShellScript' }
    $extension = if ([string]$Helper.Platform -eq 'windows') { '.ps1' } else { '.sh' }
    $scriptPath = Join-Path ([System.IO.Path]::GetTempPath()) ('prodicloud-resize-helper-{0}{1}' -f [guid]::NewGuid().ToString('N'),$extension)
    $processIdPath = $scriptPath + '.pid'
    [System.IO.File]::WriteAllText($scriptPath,[string]$ScriptText,([System.Text.UTF8Encoding]::new($false)))
    Write-ProdicloudActionProgress -Action ("run temporary vc-helper guest step '{0}'" -f $ActionLabel)
    $job = $null
    try {
        $azExecutable = Get-ProdicloudAzCliExecutable
        $startedAtUtc = [DateTime]::UtcNow
        $runCommandArguments = @('vm','run-command','invoke','--subscription',[string]$Helper.SubscriptionId,'-g',[string]$Helper.ResourceGroup,'-n',[string]$Helper.VmName,'--command-id',$commandId,'--scripts',('@' + $scriptPath),'-o','json','--only-show-errors')
        $useCmdHost = -not ([string]$azExecutable).ToLowerInvariant().EndsWith('.exe')
        $commandHost = if ([string]::IsNullOrWhiteSpace([string]$env:ComSpec)) { 'cmd.exe' } else { [string]$env:ComSpec }
        if ($useCmdHost) {
            $processFile = $commandHost
            $processArguments = (@(@('/d','/c',[string]$azExecutable) + $runCommandArguments) | ForEach-Object { Convert-ProdicloudProcessArgument -Value ([string]$_) }) -join ' '
        }
        else {
            $processFile = [string]$azExecutable
            $processArguments = (@($runCommandArguments) | ForEach-Object { Convert-ProdicloudProcessArgument -Value ([string]$_) }) -join ' '
        }
        $job = Start-Job -Name 'ProdicloudResizeHelperRunCommand' -ScriptBlock {
            param([string]$Executable,[string]$Arguments,[string]$ProcessIdPath)
            $process = $null
            try {
                $psi = New-Object System.Diagnostics.ProcessStartInfo
                $psi.FileName = $Executable
                $psi.Arguments = $Arguments
                $psi.UseShellExecute = $false
                $psi.CreateNoWindow = $true
                $psi.RedirectStandardOutput = $true
                $psi.RedirectStandardError = $true
                $process = New-Object System.Diagnostics.Process
                $process.StartInfo = $psi
                [void]$process.Start()
                $processMarker = '{0}|{1}' -f [int]$process.Id,[long]$process.StartTime.ToUniversalTime().Ticks
                [System.IO.File]::WriteAllText($ProcessIdPath,$processMarker,[System.Text.Encoding]::ASCII)
                $stdoutTask = $process.StandardOutput.ReadToEndAsync()
                $stderrTask = $process.StandardError.ReadToEndAsync()
                [void]$process.WaitForExit()
                $stdout = [string]$stdoutTask.Result
                $stderr = [string]$stderrTask.Result
                $output = if ([int]$process.ExitCode -eq 0) { $stdout } else { (@($stderr,$stdout) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) -join "`n" }
                [pscustomobject]@{ ExitCode = [int]$process.ExitCode; Output = [string]$output }
            }
            catch {
                if ($null -ne $process) { try { if (-not $process.HasExited) { $process.Kill() } } catch { } }
                [pscustomobject]@{ ExitCode = 1; Output = [string]$_.Exception.Message }
            }
        } -ArgumentList @([string]$processFile,[string]$processArguments,[string]$processIdPath) -ErrorAction Stop
        Write-ProdicloudActionProgress -Action ("az vm run-command invoke for vc-helper started asynchronously ({0})" -f $ActionLabel)

        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        $lastHeartbeatSeconds = 0
        $lastMetricsSeconds = 0
        $lastMetricSampleUtc = $startedAtUtc
        $consecutiveIdleSamples = 0
        $metricsUnavailableReported = $false
        while ([string]$job.State -notin @('Completed','Failed','Stopped')) {
            [void](Wait-Job -Job $job -Timeout 5)
            if ([string]$job.State -in @('Completed','Failed','Stopped')) { break }
            $elapsedSeconds = [int][Math]::Floor($watch.Elapsed.TotalSeconds)
            if (($elapsedSeconds - $lastHeartbeatSeconds) -ge 30) {
                $lastHeartbeatSeconds = $elapsedSeconds
                Write-ProdicloudActionProgress -Action ("vc-helper guest step '{0}' is still running ({1}s elapsed; {2}s maximum)" -f $ActionLabel,$elapsedSeconds,$ExecutionTimeoutSeconds)
            }
            if (($elapsedSeconds - $lastMetricsSeconds) -ge 60) {
                $lastMetricsSeconds = $elapsedSeconds
                $metrics = Get-ProdicloudResizeHelperActivityMetrics -Helper $Helper
                if ($null -eq $metrics) {
                    if (-not $metricsUnavailableReported) {
                        Write-Warning ("Azure Monitor has not returned vc-helper activity metrics yet; the resize step remains under its {0}-second bound." -f $ExecutionTimeoutSeconds)
                        $metricsUnavailableReported = $true
                    }
                }
                elseif ([DateTime]$metrics.SampleAtUtc -gt $startedAtUtc -and [DateTime]$metrics.SampleAtUtc -gt $lastMetricSampleUtc) {
                    $lastMetricSampleUtc = [DateTime]$metrics.SampleAtUtc
                    $diskRead = [double]$metrics.DataDiskReadBytesPerSecond + [double]$metrics.OsDiskReadBytesPerSecond
                    $diskWrite = [double]$metrics.DataDiskWriteBytesPerSecond + [double]$metrics.OsDiskWriteBytesPerSecond
                    $network = [double]$metrics.NetworkInBytesPerSecond + [double]$metrics.NetworkOutBytesPerSecond
                    $hasActivity = ($diskRead -ge 1MB) -or ($diskWrite -ge 1MB) -or ($network -ge 64KB) -or ([double]$metrics.CpuPercent -ge 3)
                    if ($hasActivity) {
                        $consecutiveIdleSamples = 0
                        Write-ProdicloudActionProgress -Action ("vc-helper activity: CPU={0:N0}%; disk read={1:N1} MiB/s, write={2:N1} MiB/s; network={3:N1} MiB/s; free RAM={4:N0} MiB" -f [double]$metrics.CpuPercent,($diskRead / 1MB),($diskWrite / 1MB),($network / 1MB),([double]$metrics.AvailableMemoryBytes / 1MB))
                    }
                    else {
                        $consecutiveIdleSamples++
                        Write-Warning ("vc-helper has no measurable CPU, disk, or network activity in fresh Azure Monitor sample {0}/3." -f $consecutiveIdleSamples)
                        if ($consecutiveIdleSamples -ge 3) { throw ("Resize helper step '{0}' stalled: three consecutive fresh Azure Monitor samples showed no guest activity. No disk cutover was attempted." -f $ActionLabel) }
                    }
                }
            }
            if ($watch.Elapsed.TotalSeconds -ge $ExecutionTimeoutSeconds) { throw ("Resize helper step '{0}' exceeded its {1}-second execution bound. No disk cutover was attempted." -f $ActionLabel,$ExecutionTimeoutSeconds) }
        }
        $jobOutput = @(Receive-Job -Job $job -Wait -ErrorAction SilentlyContinue)
        $jobResult = @($jobOutput | Where-Object { $null -ne $_.PSObject.Properties['ExitCode'] -and $null -ne $_.PSObject.Properties['Output'] } | Select-Object -Last 1)
        if ([string]$job.State -ne 'Completed' -or $jobResult.Count -ne 1) {
            $jobErrors = @($job.ChildJobs | ForEach-Object { $_.JobStateInfo.Reason } | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_.Message }) -join "`n"
            throw ("az vm run-command invoke (vc-helper) did not complete successfully. {0}" -f $jobErrors)
        }
        if ([int]$jobResult[0].ExitCode -ne 0) { throw ("az vm run-command invoke (vc-helper) failed with exit code {0}. {1}" -f [int]$jobResult[0].ExitCode,[string]$jobResult[0].Output) }
        $raw = [string]$jobResult[0].Output
    }
    catch {
        $helperFailure = $_
        if ($null -ne $job -and [string]$job.State -in @('NotStarted','Running')) {
            try { Stop-ProdicloudResizeHelperAzProcessTree -ProcessIdPath $processIdPath -ActionLabel $ActionLabel | Out-Null }
            catch { Write-Warning ("Timed-out Azure CLI helper process tree cleanup failed: {0}" -f [string]$_.Exception.Message) }
            [void](Wait-Job -Job $job -Timeout 10)
            if ([string]$job.State -in @('NotStarted','Running')) { Stop-Job -Job $job -ErrorAction SilentlyContinue }
        }
        throw $helperFailure
    }
    finally {
        if ($null -ne $job) { Remove-Job -Job $job -Force -ErrorAction SilentlyContinue }
        Remove-Item -LiteralPath $scriptPath -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $processIdPath -Force -ErrorAction SilentlyContinue
    }
    $responseObject = ConvertFrom-JsonCompat -InputObject ([string]$raw)
    $messageText = @((ConvertTo-ObjectArrayCompat -InputObject $responseObject.value) | ForEach-Object { [string]$_.message }) -join "`n"
    $resultLine = @($messageText -split "`r?`n" | Where-Object { $_ -match 'PRODICLOUD_RESIZE_RESULT:' } | Select-Object -Last 1)
    if ($resultLine.Count -eq 0) {
        $failedCode = @((ConvertTo-ObjectArrayCompat -InputObject $responseObject.value) | Where-Object { [string]$_.code -match '(?i)error|failed' } | Select-Object -First 1)
        $failureText = if ($failedCode.Count -gt 0) { [string]$failedCode[0].message } else { $messageText }
        if ([string]::IsNullOrWhiteSpace([string]$failureText)) { $failureText = [string]$raw }
        if ([string]$failureText.Length -gt 4000) { $failureText = [string]$failureText.Substring(0,4000) + ' [diagnostic truncated]' }
        throw ("vc-helper step '{0}' returned no verified result. {1}" -f $ActionLabel,$failureText)
    }
    $payloadText = ([string]$resultLine[0]) -replace '^.*PRODICLOUD_RESIZE_RESULT:',''
    $structured = ConvertFrom-JsonCompat -InputObject $payloadText
    if ([string]$structured.status -ne 'ok') { throw ("vc-helper step '{0}' failed: {1}" -f $ActionLabel,[string]$structured.message) }
    return $structured
}

function Get-ProdicloudResizeDiskRecordOrNull {
    param([string]$ResourceGroup,[string]$DiskName)
    Write-ProdicloudActionProgress -Action ("list managed disks in '{0}' to verify cleanup of '{1}'" -f $ResourceGroup,$DiskName)
    $raw = @(az disk list -g $ResourceGroup --query '[].{name:name,managedBy:managedBy,provisioningState:provisioningState}' -o json --only-show-errors 2>&1)
    $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
    $rawText = @($raw | ForEach-Object { [string]$_ }) -join "`n"
    if ($exitCode -ne 0) {
        throw ("Could not list managed disks in '{0}' while verifying cleanup of '{1}' (az exit {2}): {3}" -f $ResourceGroup,$DiskName,$exitCode,$rawText)
    }
    $jsonMatch = [regex]::Match($rawText,'(?s)\[.*\]')
    if (-not $jsonMatch.Success) { throw ("Azure returned no managed-disk list for '{0}' while verifying cleanup of '{1}'." -f $ResourceGroup,$DiskName) }
    $records = @(ConvertTo-ObjectArrayCompat -InputObject (ConvertFrom-JsonCompat -InputObject $jsonMatch.Value))
    $diskMatches = @(
        foreach ($record in $records) {
            if ([string]::Equals([string]$record.name,$DiskName,[System.StringComparison]::OrdinalIgnoreCase)) { $record }
        }
    )
    if ($diskMatches.Count -eq 0) { return $null }
    if ($diskMatches.Count -gt 1) { throw ("Azure returned multiple managed disks named '{0}' in '{1}' during cleanup verification." -f $DiskName,$ResourceGroup) }
    return $diskMatches[0]
}

function Wait-ProdicloudResizeDiskDeleted {
    param([string]$ResourceGroup,[string]$DiskName,[ValidateRange(30,1800)][int]$TimeoutSeconds = 600)
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $lastHeartbeat = -30
    $deleteRetried = $false
    $lastState = ''
    while ($watch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        $disk = Get-ProdicloudResizeDiskRecordOrNull -ResourceGroup $ResourceGroup -DiskName $DiskName
        if ($null -eq $disk) { Write-ProdicloudActionProgress -Action ("verified managed disk '{0}' is absent" -f $DiskName); return $true }
        $lastState = [string]$disk.provisioningState
        if (-not [string]::IsNullOrWhiteSpace([string]$disk.managedBy)) { throw ("Managed disk '{0}' cannot be purged while it remains attached to '{1}'." -f $DiskName,[string]$disk.managedBy) }
        $elapsedSeconds = [int][Math]::Floor($watch.Elapsed.TotalSeconds)
        if (-not $deleteRetried -and $elapsedSeconds -ge 60 -and $lastState -notmatch '(?i)delet|remov') {
            $deleteRetried = $true
            Write-ProdicloudActionProgress -Action ("retry delete for detached managed disk '{0}' after the first purge request left it present" -f $DiskName)
            Invoke-ProdicloudResizeAzureVmStep -Label ("az disk delete -g {0} -n {1} (bounded purge retry)" -f $ResourceGroup,$DiskName) -Arguments @('disk','delete','-g',$ResourceGroup,'-n',$DiskName,'--yes','--no-wait','-o','none','--only-show-errors') -Context 'az disk delete (resize purge retry)'
        }
        if (($elapsedSeconds - $lastHeartbeat) -ge 30) {
            $lastHeartbeat = $elapsedSeconds
            Write-ProdicloudActionProgress -Action ("managed disk '{0}' purge is provisioning='{1}' ({2}s of {3}s maximum)" -f $DiskName,$lastState,$elapsedSeconds,$TimeoutSeconds)
        }
        Start-Sleep -Seconds 10
    }
    throw ("Managed disk '{0}' remained present after {1}s of purge checks; last provisioning state='{2}'." -f $DiskName,$TimeoutSeconds,$lastState)
}

function Wait-ProdicloudResizeResourceGroupDeleted {
    param([string]$ResourceGroup,[ValidateRange(60,3600)][int]$TimeoutSeconds = 1200)
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $lastHeartbeat = -30
    $lastStateReadSeconds = -30
    $lastState = 'unknown'
    $deleteRetried = $false
    while ($watch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        Write-ProdicloudActionProgress -Action ("check temporary resource group '{0}' purge state" -f $ResourceGroup)
        $existsText = [string](az group exists -n $ResourceGroup --only-show-errors)
        Assert-LastExitCode 'az group exists (resize helper purge polling)'
        if ([string]::Equals($existsText.Trim(),'false',[System.StringComparison]::OrdinalIgnoreCase)) {
            Write-ProdicloudActionProgress -Action ("verified temporary resource group '{0}' is absent" -f $ResourceGroup)
            return $true
        }
        if (-not [string]::Equals($existsText.Trim(),'true',[System.StringComparison]::OrdinalIgnoreCase)) { throw ("Azure returned an invalid resource-group existence value '{0}' while purging '{1}'." -f $existsText,$ResourceGroup) }
        $elapsedSeconds = [int][Math]::Floor($watch.Elapsed.TotalSeconds)
        if (($elapsedSeconds - $lastStateReadSeconds) -ge 30) {
            $lastStateReadSeconds = $elapsedSeconds
            Write-ProdicloudActionProgress -Action ("read temporary resource group '{0}' provisioning state" -f $ResourceGroup)
            $groupOutput = @(az group show -n $ResourceGroup --query 'properties.provisioningState' -o tsv --only-show-errors 2>&1)
            $groupExitCode = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
            $groupText = @($groupOutput | ForEach-Object { [string]$_ }) -join "`n"
            if ($groupExitCode -eq 0) {
                $lastState = [string]$groupText.Trim()
            }
            elseif ($groupText -match '(?i)ResourceGroupNotFound|ResourceNotFound|\b404\b|was not found|not found') {
                return $true
            }
            elseif ($groupText -match '(?i)temporar|timeout|timed out|connection|service unavailable|anotheroperationinprogress|conflict') {
                $lastState = 'status read unavailable'
            }
            else {
                throw ("az group show (resize helper purge state) failed with exit code {0}: {1}" -f $groupExitCode,$groupText)
            }
        }
        if (-not $deleteRetried -and $elapsedSeconds -ge 60 -and -not [string]::Equals($lastState,'Deleting',[System.StringComparison]::OrdinalIgnoreCase)) {
            $deleteRetried = $true
            Write-ProdicloudActionProgress -Action ("retry asynchronous delete for temporary resource group '{0}' while Azure still reports it present" -f $ResourceGroup)
            try {
                Invoke-ProdicloudResizeAzureVmStep -Label ("az group delete -n {0} --yes --no-wait (bounded purge retry)" -f $ResourceGroup) -Arguments @('group','delete','-n',$ResourceGroup,'--yes','--no-wait','--only-show-errors') -Context 'az group delete (resize purge retry)'
            }
            catch { Write-Warning ("Resource group delete retry returned: {0}" -f [string]$_.Exception.Message) }
        }
        if (($elapsedSeconds - $lastHeartbeat) -ge 30) {
            $lastHeartbeat = $elapsedSeconds
            Write-ProdicloudActionProgress -Action ("temporary resource group '{0}' is still present (state='{1}', {2}s of {3}s maximum)" -f $ResourceGroup,$lastState,$elapsedSeconds,$TimeoutSeconds)
        }
        Start-Sleep -Seconds 10
    }
    throw ("Temporary resource group '{0}' remained present after {1}s of purge checks; last provisioning state='{2}'." -f $ResourceGroup,$TimeoutSeconds,$lastState)
}

function Remove-ProdicloudResizeHelper {
    param(
        [Parameter(Mandatory = $true)][psobject]$Helper,
        [switch]$DeferWait,
        [string]$CandidateResourceGroup = '',
        [string]$CandidateDiskName = ''
    )
    if ([string]::IsNullOrWhiteSpace([string]$Helper.ResourceGroup)) { return }
    Write-ProdicloudActionProgress -Action ("check temporary helper resource group '{0}' before purge" -f [string]$Helper.ResourceGroup)
    $exists = [string](az group exists -n ([string]$Helper.ResourceGroup) --only-show-errors)
    Assert-LastExitCode 'az group exists (vc-helper cleanup)'
    $pendingCleanup = $null
    if ($DeferWait) {
        if ($null -eq $script:ProdicloudPendingResizeHelperCleanups) { $script:ProdicloudPendingResizeHelperCleanups = @() }
        $pendingCleanup = [pscustomobject]@{
            ResourceGroup = [string]$Helper.ResourceGroup
            CandidateResourceGroup = [string]$CandidateResourceGroup
            CandidateDiskName = [string]$CandidateDiskName
            DeleteRequested = $false
        }
        $script:ProdicloudPendingResizeHelperCleanups += $pendingCleanup
    }
    if ([string]::Equals($exists.Trim(),'false',[System.StringComparison]::OrdinalIgnoreCase)) { return }
    if (-not [string]::Equals($exists.Trim(),'true',[System.StringComparison]::OrdinalIgnoreCase)) { throw ("Azure returned an invalid resource-group existence value '{0}' while cleaning temporary helper '{1}'." -f $exists,[string]$Helper.ResourceGroup) }
    Invoke-ProdicloudResizeAzureVmStep -Label ("az group delete -n {0} --yes --no-wait (temporary vc-helper purge)" -f [string]$Helper.ResourceGroup) -Arguments @('group','delete','-n',[string]$Helper.ResourceGroup,'--yes','--no-wait','--only-show-errors') -Context 'az group delete (temporary vc-helper)'
    if ($null -ne $pendingCleanup) { $pendingCleanup.DeleteRequested = $true }
    if ($DeferWait) { return }
    [void](Wait-ProdicloudResizeResourceGroupDeleted -ResourceGroup ([string]$Helper.ResourceGroup) -TimeoutSeconds 1200)
}

function Complete-ProdicloudResizeHelperCleanups {
    param([switch]$RequireComplete)
    if ($null -eq $script:ProdicloudPendingResizeHelperCleanups -or @($script:ProdicloudPendingResizeHelperCleanups).Count -eq 0) { return }
    $remaining = New-Object 'System.Collections.Generic.List[object]'
    foreach ($cleanup in @($script:ProdicloudPendingResizeHelperCleanups)) {
        $cleanupSucceeded = $false
        try {
            $exists = [string](az group exists -n ([string]$cleanup.ResourceGroup) --only-show-errors)
            Assert-LastExitCode 'az group exists (vc-helper cleanup verification)'
            if (-not [string]::Equals($exists.Trim(),'true',[System.StringComparison]::OrdinalIgnoreCase) -and -not [string]::Equals($exists.Trim(),'false',[System.StringComparison]::OrdinalIgnoreCase)) { throw ("Azure returned an invalid resource-group existence value '{0}' while resuming purge of '{1}'." -f $exists,[string]$cleanup.ResourceGroup) }
            if ([string]::Equals($exists.Trim(),'true',[System.StringComparison]::OrdinalIgnoreCase) -and -not [bool]$cleanup.DeleteRequested) {
                try {
                    Invoke-ProdicloudResizeAzureVmStep -Label ("az group delete -n {0} --yes --no-wait (resume temporary purge)" -f [string]$cleanup.ResourceGroup) -Arguments @('group','delete','-n',[string]$cleanup.ResourceGroup,'--yes','--no-wait','--only-show-errors') -Context 'az group delete (resume resize purge)'
                    $cleanup.DeleteRequested = $true
                }
                catch { Write-Warning ("Resource group purge is already active or could not be restarted: {0}" -f [string]$_.Exception.Message) }
            }
            if ([string]::Equals($exists.Trim(),'true',[System.StringComparison]::OrdinalIgnoreCase)) {
                [void](Wait-ProdicloudResizeResourceGroupDeleted -ResourceGroup ([string]$cleanup.ResourceGroup) -TimeoutSeconds 1200)
            }
            $cleanupSucceeded = $true
        }
        catch {
            Write-Warning ("Temporary vc-helper resource group '{0}' is still pending cleanup: {1}" -f [string]$cleanup.ResourceGroup,[string]$_.Exception.Message)
        }
        if (-not $cleanupSucceeded) { $remaining.Add($cleanup) | Out-Null; continue }
        if ([string]::IsNullOrWhiteSpace([string]$cleanup.CandidateDiskName)) { continue }
        try {
            $candidate = Get-ProdicloudResizeDiskRecordOrNull -ResourceGroup ([string]$cleanup.CandidateResourceGroup) -DiskName ([string]$cleanup.CandidateDiskName)
            if ($null -eq $candidate) { continue }
            if (-not [string]::IsNullOrWhiteSpace([string]$candidate.managedBy)) { throw ("Replacement disk is still attached to '{0}' after helper purge." -f [string]$candidate.managedBy) }
            Invoke-ProdicloudResizeAzureVmStep -Label ("az disk delete -g {0} -n {1} (failed shrink cleanup)" -f [string]$cleanup.CandidateResourceGroup,[string]$cleanup.CandidateDiskName) -Arguments @('disk','delete','-g',[string]$cleanup.CandidateResourceGroup,'-n',[string]$cleanup.CandidateDiskName,'--yes','--no-wait','-o','none','--only-show-errors') -Context 'az disk delete (uncommitted resize candidate cleanup)'
            [void](Wait-ProdicloudResizeDiskDeleted -ResourceGroup ([string]$cleanup.CandidateResourceGroup) -DiskName ([string]$cleanup.CandidateDiskName) -TimeoutSeconds 600)
        }
        catch {
            Write-Warning ("Uncommitted resize candidate '{0}' remains pending cleanup: {1}" -f [string]$cleanup.CandidateDiskName,[string]$_.Exception.Message)
            $remaining.Add($cleanup) | Out-Null
        }
    }
    $script:ProdicloudPendingResizeHelperCleanups = @($remaining.ToArray())
    if ($RequireComplete -and $remaining.Count -gt 0) {
        $pendingNames = @($remaining | ForEach-Object { if ([string]::IsNullOrWhiteSpace([string]$_.CandidateDiskName)) { [string]$_.ResourceGroup } else { '{0} / {1}' -f [string]$_.ResourceGroup,[string]$_.CandidateDiskName } }) -join '; '
        throw ("Temporary resize resources could not be fully purged and verified: {0}" -f $pendingNames)
    }
}

function New-ProdicloudResizeCandidateDiskName {
    param([string]$VmName,[string]$Region,[hashtable]$ConfigMap)
    $regionCode = Get-ProdicloudRegionCode -Location $Region
    $allocator = New-ProdicloudManagedResourceIndexAllocator
    $template = [string](Get-ConfigValue -Config $ConfigMap -Key 'VM_DISK_NAME_TEMPLATE' -DefaultValue 'disk-{SELECTED_VM_NAME}-{REGION_CODE}-n{N}')
    return (Resolve-ProdicloudNameFromTemplate -Template $template -ResourceType 'disk' -VmName $VmName -RegionCode $regionCode -UseNextIndex -IndexAllocator $allocator -LogicalName 'resize-candidate-disk')
}

function Invoke-ProdicloudResizeDiskClone {
    param(
        [psobject]$VmObject,
        [psobject]$Disk,
        [psobject]$Inspection,
        [int]$TargetDiskSizeGb,
        [string]$ResourceGroup,
        [string]$VmName,
        [string]$Region,
        [string]$Platform,
        [psobject]$Runtime,
        [hashtable]$Options,
        [string]$OriginalPowerState
    )
    $supportedSkuNames = @('Standard_LRS','StandardSSD_LRS','Premium_LRS','Premium_ZRS','StandardSSD_ZRS')
    if ([string]$Disk.SkuName -notin $supportedSkuNames) { throw ("Shrink clone currently supports Standard/Premium managed disks; selected SKU '{0}' is unsupported." -f [string]$Disk.SkuName) }
    if ([bool]$Disk.DiskObject.encryptionSettingsCollection.enabled -or [int]$Disk.DiskObject.maxShares -gt 1) { throw 'Encrypted or shared managed disks are not supported by the shrink clone workflow.' }
    $diskType = [string]$Disk.Kind
    if ($diskType -eq 'os' -and [string]$Disk.HyperVGeneration -ne 'V2') { throw 'OS disk shrink clone currently requires a Gen2/UEFI VM.' }
    if ($Platform -eq 'windows') {
        if ($diskType -eq 'os') {
            $layoutSupport = Get-ProdicloudResizeWindowsOsLayoutSupport -Partitions (ConvertTo-ObjectArrayCompat -InputObject $Inspection.partitions)
            if ([string]$Disk.HyperVGeneration -ne 'V2' -or -not [bool]$Inspection.shrinkCapable -or -not [bool]$layoutSupport.IsSupported) { throw 'Windows OS shrink requires a supported unencrypted GPT/UEFI layout with EFI, MSR, NTFS OS, and Recovery partitions.' }
            if (@($layoutSupport.IgnoredPartitionNumbers).Count -gt 0) { Write-Host ("Source partition(s) {0} are empty leading MSR entries with no filesystem data; all source filesystems remain in the copy. The replacement layout will be read back before cutover." -f (@($layoutSupport.IgnoredPartitionNumbers) -join ', ')) -ForegroundColor Yellow }
        }
        if ($diskType -eq 'data' -and ([string]$Inspection.fileSystems -notmatch 'NTFS|ReFS' -or [int]$Inspection.partitionCount -ne 1)) { throw 'Windows data-disk shrink requires one NTFS or ReFS data partition.' }
    }
    else {
        if (-not [bool]$Inspection.shrinkCapable) { throw 'Linux shrink requires a supported unencrypted GPT partition layout without LVM.' }
        if ($diskType -eq 'os' -and ([string]$Inspection.fileSystem -ne 'ext4' -or [int]$Inspection.partitionCount -ne 2 -or [string]$Inspection.partitionStyle -ne 'gpt')) { throw 'Linux OS shrink currently supports only GPT UEFI disks with one EFI and one ext4 root partition.' }
    }

    $candidateDiskName = New-ProdicloudResizeCandidateDiskName -VmName $VmName -Region $Region -ConfigMap ([hashtable]$Runtime.EffectiveConfigMap)
    $stamp = [DateTime]::UtcNow.ToString('yyMMddHHmmss') + (Get-Random -Minimum 10 -Maximum 99)
    $snapshotName = ('snap-rz-src-{0}' -f $stamp)
    $sourceCloneName = ('prodicloud-rz-src-{0}' -f $stamp)
    $helper = $null
    $helperResourceGroup = ''
    $candidateCreated = $false
    $sourceCloneCreated = $false
    $snapshotCreated = $false
    $candidateAttachedToTarget = $false
    $targetWasCutOver = $false
    $helperCleanupQueued = $false
    $operationFailed = $false
    $sourceDiskId = [string]$Disk.DiskId
    $candidateDiskId = ''
    $sourceCloneId = ''
    $copyDiskSku = [string]$Disk.SkuName
    $copyDiskTier = ''
    $performanceProfile = Get-ProdicloudResizePerformanceProfile
    $usePremiumCopySku = ([string]$Disk.SkuName -eq 'StandardSSD_LRS' -and [int]$Disk.DiskSizeGb -ge 4 -and $TargetDiskSizeGb -ge 4)
    if ($usePremiumCopySku) {
        $copyDiskSku = [string]$performanceProfile.TransferDiskSku
        $copyDiskTier = [string]$performanceProfile.TransferDiskTier
        Write-ProdicloudActionProgress -Action ("use same-capacity {0} {1} source clone and requested-size replacement with the {2} helper for this Standard SSD shrink copy; restore the original disk SKU before cutover" -f $copyDiskSku,$copyDiskTier,$performanceProfile.HelperVmSize)
        Write-ProdicloudResizePerformancePlan -SourceDiskSizeGb ([int]$Disk.DiskSizeGb) -TargetDiskSizeGb $TargetDiskSizeGb
    }
    $candidateRequiresHibernation = ($diskType -eq 'os' -and [bool]$VmObject.additionalCapabilities.hibernationEnabled)
    $hibernationImageReference = ''
    $targetSubscription = Get-ProdicloudResolvedSubscriptionContext
    try {
        if ($candidateRequiresHibernation) {
            $sourceImageReference = $VmObject.storageProfile.imageReference
            $imagePublisher = [string]$sourceImageReference.publisher
            $imageOffer = [string]$sourceImageReference.offer
            $imageSku = [string]$sourceImageReference.sku
            $imageVersion = [string]$sourceImageReference.exactVersion
            if ([string]::IsNullOrWhiteSpace($imageVersion)) { $imageVersion = [string]$sourceImageReference.version }
            if ([string]::IsNullOrWhiteSpace($imagePublisher) -or [string]::IsNullOrWhiteSpace($imageOffer) -or [string]::IsNullOrWhiteSpace($imageSku) -or [string]::IsNullOrWhiteSpace($imageVersion)) {
                throw 'The hibernation-enabled VM does not expose an exact Marketplace image reference; shrink cannot safely preserve hibernation metadata.'
            }
            $imageJson = Invoke-TrackedAction -Label ("az vm image show (hibernation source {0}:{1}:{2}:{3})" -f $imagePublisher,$imageOffer,$imageSku,$imageVersion) -Action {
                $imageOutput = az vm image show --location $Region --publisher $imagePublisher --offer $imageOffer --sku $imageSku --version $imageVersion -o json --only-show-errors
                Assert-LastExitCode 'az vm image show (hibernation candidate source)'
                return (@($imageOutput) -join "`n")
            }
            $imageMetadata = ConvertFrom-JsonCompat -InputObject ([string]$imageJson)
            $imageSupportsHibernation = $false
            foreach ($imageFeature in @(ConvertTo-ObjectArrayCompat -InputObject $imageMetadata.features)) {
                if ([string]$imageFeature.name -eq 'IsHibernateSupported' -and [string]$imageFeature.value -ieq 'true') {
                    $imageSupportsHibernation = $true
                    break
                }
            }
            if (-not $imageSupportsHibernation) { throw ("Marketplace image '{0}:{1}:{2}:{3}' does not advertise Azure hibernation support; refusing an OS disk shrink that could lose the VM's current hibernation capability." -f $imagePublisher,$imageOffer,$imageSku,$imageVersion) }
            $hibernationImageReference = '{0}:{1}:{2}:{3}' -f $imagePublisher,$imageOffer,$imageSku,$imageVersion
        }

        $helper = New-ProdicloudResizeHelperVm -VmObject $VmObject -ResourceGroup $ResourceGroup -VmName $VmName -Region $Region -Platform $Platform -Runtime $Runtime
        $helperResourceGroup = [string]$helper.ResourceGroup
        Invoke-ProdicloudResizeAzureVmStep -Label ("az snapshot create -g {0} -n {1} --no-wait" -f [string]$helper.ResourceGroup,$snapshotName) -Arguments @('snapshot','create','-g',[string]$helper.ResourceGroup,'-n',$snapshotName,'--source',$sourceDiskId,'--location',$Region,'--sku','Standard_LRS','--no-wait','-o','none','--only-show-errors') -Context 'az snapshot create (disk shrink source clone)'
        $snapshotCreated = $true
        $snapshot = Wait-ProdicloudResizeSnapshotReady -ResourceGroup ([string]$helper.ResourceGroup) -SnapshotName $snapshotName -TimeoutSeconds 600
        $snapshotId = [string]$snapshot.id
        if ([string]::IsNullOrWhiteSpace($snapshotId)) { throw 'Source disk snapshot id could not be resolved.' }
        $sourceCloneArgs = @('disk','create','-g',[string]$helper.ResourceGroup,'-n',$sourceCloneName,'--source',$snapshotId,'--location',$Region,'--sku',$copyDiskSku)
        if (-not [string]::IsNullOrWhiteSpace($copyDiskTier)) { $sourceCloneArgs += @('--tier',$copyDiskTier) }
        $sourceCloneArgs += @('--no-wait','-o','none','--only-show-errors')
        Invoke-ProdicloudResizeAzureVmStep -Label ("az disk create -g {0} -n {1} from source snapshot" -f [string]$helper.ResourceGroup,$sourceCloneName) -Arguments $sourceCloneArgs -Context 'az disk create (disk shrink working clone)'
        $sourceCloneCreated = $true
        $sourceCloneObject = Wait-ProdicloudResizeDiskReady -ResourceGroup ([string]$helper.ResourceGroup) -DiskName $sourceCloneName -ExpectedSizeGb ([int]$Disk.DiskSizeGb) -ExpectedSku $copyDiskSku -ExpectedTier $copyDiskTier -TimeoutSeconds 600
        $sourceCloneId = [string]$sourceCloneObject.id
        if ([string]::IsNullOrWhiteSpace($sourceCloneId)) { throw 'Source working clone id could not be resolved.' }
        if ([string]$sourceCloneObject.sku -ne $copyDiskSku) { throw ("Azure created the source clone with SKU '{0}', expected temporary copy SKU '{1}'." -f [string]$sourceCloneObject.sku,$copyDiskSku) }
        if (-not [string]::IsNullOrWhiteSpace($copyDiskTier) -and [string]$sourceCloneObject.tier -ne $copyDiskTier) { throw ("Azure created the source clone with performance tier '{0}', expected '{1}'." -f [string]$sourceCloneObject.tier,$copyDiskTier) }
        $candidateArgs = @('disk','create','-g',$ResourceGroup,'-n',$candidateDiskName,'--location',$Region,'--size-gb',[string]$TargetDiskSizeGb,'--sku',$copyDiskSku,'--tags','managed-by=prodicloud','prodicloud-role=resize-candidate','prodicloud-source-vm=' + $VmName)
        if (-not [string]::IsNullOrWhiteSpace($copyDiskTier)) { $candidateArgs += @('--tier',$copyDiskTier) }
        if ($diskType -eq 'os') {
            if ($candidateRequiresHibernation) {
                $candidateArgs += @('--image-reference',$hibernationImageReference)
            }
            else {
                $candidateArgs += @('--os-type',[string]$VmObject.storageProfile.osDisk.osType,'--hyper-v-generation',[string]$Disk.HyperVGeneration)
            }
        }
        $candidateArgs += @('--no-wait','-o','none','--only-show-errors')
        Invoke-ProdicloudResizeAzureVmStep -Label ("az disk create -g {0} -n {1} ({2} GB shrink candidate)" -f $ResourceGroup,$candidateDiskName,$TargetDiskSizeGb) -Arguments $candidateArgs -Context 'az disk create (resize candidate)'
        $candidateCreated = $true
        $candidateDiskObject = Wait-ProdicloudResizeDiskReady -ResourceGroup $ResourceGroup -DiskName $candidateDiskName -ExpectedSizeGb $TargetDiskSizeGb -ExpectedSku $copyDiskSku -ExpectedTier $copyDiskTier -TimeoutSeconds 600
        $candidateDiskId = [string]$candidateDiskObject.id
        if ([string]::IsNullOrWhiteSpace($candidateDiskId)) { throw 'Candidate disk id could not be resolved.' }
        if ([string]$candidateDiskObject.sku -ne $copyDiskSku) { throw ("Azure created the resize candidate with SKU '{0}', expected temporary copy SKU '{1}'." -f [string]$candidateDiskObject.sku,$copyDiskSku) }
        if (-not [string]::IsNullOrWhiteSpace($copyDiskTier) -and [string]$candidateDiskObject.tier -ne $copyDiskTier) { throw ("Azure created the resize candidate with performance tier '{0}', expected '{1}'." -f [string]$candidateDiskObject.tier,$copyDiskTier) }
        if ($candidateRequiresHibernation) {
            if ([string]$candidateDiskObject.createOption -ne 'FromImage') { throw 'The hibernation-preserving OS disk candidate was not created from the same Marketplace platform image.' }
            Invoke-ProdicloudResizeAzureVmStep -Label ("enable hibernation support on OS candidate '{0}' --no-wait" -f $candidateDiskName) -Arguments @('disk','update','-g',$ResourceGroup,'-n',$candidateDiskName,'--set','supportsHibernation=true','--no-wait','-o','none','--only-show-errors') -Context 'az disk update (hibernation-preserving OS candidate)'
            $candidateDiskObject = Wait-ProdicloudResizeDiskReady -ResourceGroup $ResourceGroup -DiskName $candidateDiskName -ExpectedSizeGb $TargetDiskSizeGb -ExpectedSku $copyDiskSku -ExpectedTier $copyDiskTier -RequireHibernation $true -TimeoutSeconds 300
        }

        [void](Wait-ProdicloudResizeHelperVmProvisioned -Helper $helper -TimeoutSeconds 1200)
        [void](Confirm-ProdicloudResizeHelperOsDiskProfile -Helper $helper)
        Invoke-ProdicloudResizeAzureVmStep -Label ("attach source clone to vc-helper at LUN 10") -Arguments @('vm','disk','attach','-g',[string]$helper.ResourceGroup,'--vm-name',[string]$helper.VmName,'--name',$sourceCloneId,'--lun','10','--caching','ReadOnly','-o','none','--only-show-errors') -Context 'az vm disk attach (vc-helper source clone)'
        [void](Wait-ProdicloudResizeDiskAttachment -VmResourceGroup ([string]$helper.ResourceGroup) -VmName ([string]$helper.VmName) -DiskResourceGroup ([string]$helper.ResourceGroup) -DiskName $sourceCloneName -DiskId $sourceCloneId -DiskKind 'data' -Lun 10 -ShouldBeAttached $true)
        Invoke-ProdicloudResizeAzureVmStep -Label ("attach resize candidate to vc-helper at LUN 11") -Arguments @('vm','disk','attach','-g',[string]$helper.ResourceGroup,'--vm-name',[string]$helper.VmName,'--name',$candidateDiskId,'--lun','11','--caching','None','-o','none','--only-show-errors') -Context 'az vm disk attach (vc-helper resize candidate)'
        [void](Wait-ProdicloudResizeDiskAttachment -VmResourceGroup ([string]$helper.ResourceGroup) -VmName ([string]$helper.VmName) -DiskResourceGroup $ResourceGroup -DiskName $candidateDiskName -DiskId $candidateDiskId -DiskKind 'data' -Lun 11 -ShouldBeAttached $true)
        [void](Wait-ProdicloudResizeHelperGuestAgent -ResourceGroup ([string]$helper.ResourceGroup) -VmName ([string]$helper.VmName) -TimeoutSeconds 180)

        $helperAsset = Join-Path (Get-ProdicloudRepoRoot) ('modules/commands/resize/assets/resize-helper-{0}.{1}' -f $Platform,$(if ($Platform -eq 'windows') { 'ps1' } else { 'sh' }))
        if (-not (Test-Path -LiteralPath $helperAsset -PathType Leaf)) { throw ("Resize helper guest script is missing: {0}" -f $helperAsset) }
        $helperScript = Get-Content -LiteralPath $helperAsset -Raw
        if ($Platform -eq 'windows') {
        $helperRequest = ConvertTo-Json -InputObject ([ordered]@{ kind = $diskType; targetSizeGb = $TargetDiskSizeGb; expectedSourceUsedBytes = [long]$Inspection.usedBytes; minimumFreeBytes = [long](10GB) }) -Compress
            $helperRequestB64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($helperRequest))
            $helperScript = $helperScript.Replace('__PRODICLOUD_RESIZE_REQUEST_B64__',$helperRequestB64)
        }
        else {
            $helperScript = $helperScript.Replace('__PRODICLOUD_RESIZE_KIND__',$diskType).Replace('__PRODICLOUD_RESIZE_TARGET_GB__',[string]$TargetDiskSizeGb).Replace('__PRODICLOUD_RESIZE_EXPECTED_SOURCE_USED_BYTES__',[string][long]$Inspection.usedBytes).Replace('__PRODICLOUD_RESIZE_MINIMUM_FREE_BYTES__',[string](10GB))
        }
        $helperResult = Invoke-ProdicloudResizeHelperScript -Helper $helper -ScriptText $helperScript -ActionLabel ("prepare {0} replacement disk" -f $diskType)
        if ([string]$helperResult.kind -ne $diskType) { throw 'The helper returned a result for the wrong disk type.' }
        $ignoredSourcePartitionNumbers = @(ConvertTo-ObjectArrayCompat -InputObject $helperResult.ignoredSourcePartitionNumbers)
        if ($ignoredSourcePartitionNumbers.Count -gt 0) { Write-Host ("Source partition(s) {0} contained no filesystem data and were excluded from file-copy mapping; all source filesystems were copied." -f (@($ignoredSourcePartitionNumbers | ForEach-Object { [string]$_ }) -join ', ')) -ForegroundColor Yellow }
        if ($diskType -eq 'os' -and $Platform -eq 'windows') {
            $candidatePartitions = @(ConvertTo-ObjectArrayCompat -InputObject $helperResult.partitions)
            $candidateLayout = Get-ProdicloudResizeWindowsOsLayoutSupport -Partitions $candidatePartitions
            if (-not [bool]$candidateLayout.IsSupported) { throw ("Windows replacement OS candidate has an unsupported GPT/UEFI layout; the original disk remains attached. {0}" -f [string]$candidateLayout.Reason) }
            Write-Host ("Replacement OS layout verified before cutover: {0}; {1} GPT partition(s)." -f [string]$candidateLayout.LayoutId,$candidatePartitions.Count) -ForegroundColor DarkCyan
        }
        $helperSourceUsedBytes = if ($null -ne $helperResult.PSObject.Properties['sourceUsedBytes']) { [long]$helperResult.sourceUsedBytes } elseif ($null -ne $helperResult.PSObject.Properties['usedBytes']) { [long]$helperResult.usedBytes } else { throw 'The resize helper did not return the remeasured source filesystem usage.' }
        $helperReplacementUsedBytes = if ($null -ne $helperResult.PSObject.Properties['replacementUsedBytes']) { [long]$helperResult.replacementUsedBytes } else { throw 'The resize helper did not return the replacement filesystem usage.' }
        $helperReplacementFreeBytes = if ($null -ne $helperResult.PSObject.Properties['replacementFreeBytes']) { [long]$helperResult.replacementFreeBytes } else { throw 'The resize helper did not return the replacement filesystem free space.' }
        $helperReplacementSizeBytes = if ($null -ne $helperResult.PSObject.Properties['replacementSizeBytes']) { [long]$helperResult.replacementSizeBytes } else { throw 'The resize helper did not return the replacement raw disk capacity.' }
        $expectedTargetBytes = [long]$TargetDiskSizeGb * 1GB
        if ($helperReplacementSizeBytes -lt $expectedTargetBytes) { throw ("Resize helper candidate capacity is too small before cutover: expected at least {0} bytes, actual {1} bytes." -f $expectedTargetBytes,$helperReplacementSizeBytes) }
        if ($helperSourceUsedBytes + (10GB) -gt $helperReplacementSizeBytes) { throw ("Source clone remeasurement no longer fits the selected target: source used={0:N2} GiB, target={1:N2} GiB, required headroom=10 GiB. The original disk remains attached." -f ($helperSourceUsedBytes / 1GB),($helperReplacementSizeBytes / 1GB)) }
        if ($helperReplacementUsedBytes + (10GB) -gt $helperReplacementSizeBytes -or $helperReplacementFreeBytes -lt (10GB)) { throw ("Replacement disk failed its pre-cutover headroom check: used={0:N2} GiB, free={1:N2} GiB, raw capacity={2:N2} GiB, required free headroom=10 GiB. The original disk remains attached." -f ($helperReplacementUsedBytes / 1GB),($helperReplacementFreeBytes / 1GB),($helperReplacementSizeBytes / 1GB)) }
        $remeasurementDeltaBytes = $helperSourceUsedBytes - [long]$Inspection.usedBytes
        Write-Host ("Shrink copy verification: source-clone used={0:N2} GiB (change since initial inventory={1:+0.00;-0.00;0.00} GiB); candidate used={2:N2} GiB; candidate free={3:N2} GiB; raw capacity={4:N2} GiB; minimum free headroom=10 GiB." -f ($helperSourceUsedBytes / 1GB),($remeasurementDeltaBytes / 1GB),($helperReplacementUsedBytes / 1GB),($helperReplacementFreeBytes / 1GB),($helperReplacementSizeBytes / 1GB)) -ForegroundColor DarkCyan

        Invoke-ProdicloudResizeAzureVmStep -Label 'detach source clone from vc-helper' -Arguments @('vm','disk','detach','-g',[string]$helper.ResourceGroup,'--vm-name',[string]$helper.VmName,'--name',$sourceCloneName,'-o','none','--only-show-errors') -Context 'az vm disk detach (vc-helper source clone)'
        [void](Wait-ProdicloudResizeDiskAttachment -VmResourceGroup ([string]$helper.ResourceGroup) -VmName ([string]$helper.VmName) -DiskResourceGroup ([string]$helper.ResourceGroup) -DiskName $sourceCloneName -DiskId $sourceCloneId -DiskKind 'data' -Lun 10 -ShouldBeAttached $false)
        Invoke-ProdicloudResizeAzureVmStep -Label 'detach candidate disk from vc-helper' -Arguments @('vm','disk','detach','-g',[string]$helper.ResourceGroup,'--vm-name',[string]$helper.VmName,'--name',$candidateDiskName,'-o','none','--only-show-errors') -Context 'az vm disk detach (vc-helper candidate)'
        [void](Wait-ProdicloudResizeDiskAttachment -VmResourceGroup ([string]$helper.ResourceGroup) -VmName ([string]$helper.VmName) -DiskResourceGroup $ResourceGroup -DiskName $candidateDiskName -DiskId $candidateDiskId -DiskKind 'data' -Lun 11 -ShouldBeAttached $false)
        Remove-ProdicloudResizeHelper -Helper $helper -DeferWait
        $helperCleanupQueued = $true
        $helper = $null

        if ($copyDiskSku -ne [string]$Disk.SkuName) {
            Invoke-ProdicloudResizeAzureVmStep -Label ("restore original disk SKU '{0}' on the detached replacement before cutover" -f [string]$Disk.SkuName) -Arguments @('disk','update','--ids',$candidateDiskId,'--sku',[string]$Disk.SkuName,'--no-wait','-o','none','--only-show-errors') -Context 'az disk update (restore replacement disk SKU)'
        }
        $finalCandidate = Wait-ProdicloudResizeDiskReady -ResourceGroup $ResourceGroup -DiskName $candidateDiskName -ExpectedSizeGb $TargetDiskSizeGb -ExpectedSku ([string]$Disk.SkuName) -RequireHibernation ([bool]$candidateRequiresHibernation) -TimeoutSeconds 600
        if ([int]$finalCandidate.sizeGB -ne $TargetDiskSizeGb) { throw ("Replacement disk size verification failed before cutover: expected {0} GiB, actual {1} GiB." -f $TargetDiskSizeGb,[int]$finalCandidate.sizeGB) }
        if ([string]$finalCandidate.sku -ne [string]$Disk.SkuName) { throw ("Replacement disk SKU verification failed before cutover: expected '{0}', actual '{1}'." -f [string]$Disk.SkuName,[string]$finalCandidate.sku) }
        if ($candidateRequiresHibernation -and -not [bool]$finalCandidate.supportsHibernation) { throw 'The replacement OS disk lost hibernation support when restoring the original storage SKU; the original disk remains attached.' }

        if ($diskType -eq 'os') {
            Invoke-ProdicloudResizeAzureVmStep -Label ("swap VM '{0}' to the verified replacement OS disk --no-wait" -f $VmName) -Arguments @('vm','update','-g',$ResourceGroup,'-n',$VmName,'--os-disk',$candidateDiskId,'--no-wait','-o','none','--only-show-errors') -Context 'az vm update --os-disk (resize cutover)'
            $targetWasCutOver = $true
            [void](Wait-ProdicloudResizeDiskAttachment -VmResourceGroup $ResourceGroup -VmName $VmName -DiskResourceGroup $ResourceGroup -DiskName $candidateDiskName -DiskId $candidateDiskId -DiskKind 'os' -ShouldBeAttached $true)
            [void](Wait-ProdicloudResizeDiskAttachment -VmResourceGroup $ResourceGroup -VmName $VmName -DiskResourceGroup $ResourceGroup -DiskName ([string]$Disk.DiskName) -DiskId $sourceDiskId -DiskKind 'os' -ShouldBeAttached $false)
        }
        else {
            Invoke-ProdicloudResizeAzureVmStep -Label ("detach source data disk '{0}' from target VM" -f [string]$Disk.DiskName) -Arguments @('vm','disk','detach','-g',$ResourceGroup,'--vm-name',$VmName,'--name',[string]$Disk.DiskName,'-o','none','--only-show-errors') -Context 'az vm disk detach (data disk shrink cutover)'
            $targetWasCutOver = $true
            [void](Wait-ProdicloudResizeDiskAttachment -VmResourceGroup $ResourceGroup -VmName $VmName -DiskResourceGroup $ResourceGroup -DiskName ([string]$Disk.DiskName) -DiskId $sourceDiskId -DiskKind 'data' -Lun ([int]$Disk.Lun) -ShouldBeAttached $false)
            Invoke-ProdicloudResizeAzureVmStep -Label ("attach replacement data disk '{0}' to target LUN {1}" -f $candidateDiskName,[int]$Disk.Lun) -Arguments @('vm','disk','attach','-g',$ResourceGroup,'--vm-name',$VmName,'--name',$candidateDiskId,'--lun',[string][int]$Disk.Lun,'--caching',[string]$Disk.Caching,'-o','none','--only-show-errors') -Context 'az vm disk attach (data disk shrink cutover)'
            $candidateAttachedToTarget = $true
            [void](Wait-ProdicloudResizeDiskAttachment -VmResourceGroup $ResourceGroup -VmName $VmName -DiskResourceGroup $ResourceGroup -DiskName $candidateDiskName -DiskId $candidateDiskId -DiskKind 'data' -Lun ([int]$Disk.Lun) -ShouldBeAttached $true)
            $targetWasCutOver = $true
        }
        $candidateReadback = [int]$finalCandidate.sizeGB
        Set-ProdicloudResizeVmPowerState -ResourceGroup $ResourceGroup -VmName $VmName -DesiredState 'started'
        $guestRuntime = Get-ProdicloudResizeGuestRuntime -ResourceGroup $ResourceGroup -VmName $VmName -Platform $Platform
        [void](Wait-ProdicloudResizeGuestTransportStable -GuestRuntime $guestRuntime -RequiredSuccesses 2 -TimeoutSeconds 600 -PollSeconds 5)
        if ($diskType -eq 'data' -and $Platform -eq 'windows' -and -not [string]::IsNullOrWhiteSpace([string]$Inspection.driveLetters[0])) {
            $verifyDisk = [pscustomobject]@{ Kind = 'data'; Lun = [int]$Disk.Lun; DriveLetter = [string]$Inspection.driveLetters[0] }
            [void](Invoke-ProdicloudResizeGuestOperation -ResourceGroup $ResourceGroup -VmName $VmName -Platform $Platform -Action 'set-drive-letter' -Disk $verifyDisk)
        }
        $verifyDisk = [pscustomobject]@{ Kind = $diskType; Lun = [int]$Disk.Lun; DriveLetter = '' }
        if ($diskType -eq 'os' -and $Platform -eq 'windows') {
            $winreVerification = Invoke-ProdicloudResizeGuestOperation -ResourceGroup $ResourceGroup -VmName $VmName -Platform $Platform -Action 'restore-winre' -Disk $verifyDisk
            if (-not [bool]$winreVerification.winreEnabled) { throw 'Windows Recovery Environment was not enabled and verified on the replacement OS disk.' }
        }
        $guestVerification = Wait-ProdicloudResizeGuestDiskCapacity -ResourceGroup $ResourceGroup -VmName $VmName -Platform $Platform -Disk $verifyDisk -TargetDiskSizeGb $TargetDiskSizeGb -MinimumFreeBytes (10GB) -TimeoutSeconds 300
        if ($diskType -eq 'os' -and $Platform -eq 'windows') {
            $postCutoverLayout = Get-ProdicloudResizeWindowsOsLayoutSupport -Partitions @(ConvertTo-ObjectArrayCompat -InputObject $guestVerification.partitions)
            if (-not [bool]$postCutoverLayout.IsSupported) { throw ("Post-cutover Windows OS partition layout is unsupported; the original disk has not been deleted. {0}" -f [string]$postCutoverLayout.Reason) }
        }
        if ([long]$guestVerification.diskSizeBytes -lt ([long]$TargetDiskSizeGb * 1GB)) { throw 'Guest disk size is smaller than the requested replacement size.' }
        if ([long]$guestVerification.usedBytes + (10GB) -gt ([long]$guestVerification.diskSizeBytes)) { throw 'Post-cutover guest data verification did not leave the required 10 GiB headroom.' }
        Write-ProdicloudResizeDiskInventory -Stage 'after' -Inspection $guestVerification -AzureDiskSizeBytes ([long]$candidateReadback * 1GB)
        Write-ProdicloudActionProgress -Action ("restore VC '{0}' to its original power state '{1}' after disk verification" -f $VmName,$OriginalPowerState)
        Set-ProdicloudResizeVmPowerState -ResourceGroup $ResourceGroup -VmName $VmName -DesiredState $OriginalPowerState

        if ($diskType -eq 'os') {
            Write-ProdicloudActionProgress -Action ("persist verified {0} GiB OS disk size and replacement identity to '{1}.env'" -f $TargetDiskSizeGb,$VmName)
            $profilePath = Get-ProdicloudVmEnvPath -VmName $VmName
            $configBefore = Read-DotEnvFile -Path $profilePath
            $persist = @{ SELECTED_VM_NAME = $VmName; SELECTED_RESOURCE_GROUP = $ResourceGroup; VM_DISK_NAME = $candidateDiskName }
            $diskSizeKey = Get-ProdicloudPlatformVmConfigKey -Platform $Platform -BaseKey 'VM_DISK_SIZE_GB'
            $persist[$diskSizeKey] = [string]$TargetDiskSizeGb
            [void](Save-ProdicloudConfigToDotEnv -EnvFilePath $profilePath -ConfigBefore $configBefore -PersistMap $persist)
        }
        Write-ProdicloudActionProgress -Action 'finish temporary helper and candidate cleanup verification before deleting the source disk'
        Complete-ProdicloudResizeHelperCleanups -RequireComplete
        Write-ProdicloudActionProgress -Action ("delete verified source disk '{0}' after successful shrink" -f [string]$Disk.DiskName)
        $sourceDiskPurged = $false
        try {
            Invoke-ProdicloudResizeAzureVmStep -Label ("az disk delete -g {0} -n {1} (verified source cleanup)" -f $ResourceGroup,[string]$Disk.DiskName) -Arguments @('disk','delete','-g',$ResourceGroup,'-n',[string]$Disk.DiskName,'--yes','--no-wait','-o','none','--only-show-errors') -Context 'az disk delete (verified resize source cleanup)'
            [void](Wait-ProdicloudResizeDiskDeleted -ResourceGroup $ResourceGroup -DiskName ([string]$Disk.DiskName) -TimeoutSeconds 600)
            $sourceDiskPurged = $true
        }
        catch { Write-Warning ("Disk shrink and guest verification succeeded, but source disk '{0}' purge was not verified and must be retried: {1}" -f [string]$Disk.DiskName,[string]$_.Exception.Message) }
        if ($sourceDiskPurged) {
            Write-Host ("Disk shrink completed: {0} -> {1} GiB; guest/Azure capacities verified and source disk purge confirmed." -f [string]$Disk.DiskName,$TargetDiskSizeGb) -ForegroundColor Green
        }
        else {
            Write-Warning ("Disk shrink completed at {0} GiB, but the source-disk hard purge remains unverified." -f $TargetDiskSizeGb)
        }
        return [pscustomobject]@{ DiskName = $candidateDiskName; DiskId = $candidateDiskId; SizeGb = $TargetDiskSizeGb; Kind = $diskType; Guest = $guestVerification; SourceDiskPurged = $sourceDiskPurged }
    }
    catch {
        $operationFailed = $true
        $failure = $_
        if (-not [string]::IsNullOrWhiteSpace([string]$failure.ScriptStackTrace)) { Write-Warning ("Disk shrink failure stack: {0}" -f [string]$failure.ScriptStackTrace) }
        if ($targetWasCutOver) {
            Write-Warning ("Disk shrink failed after candidate cutover; retaining the source disk and starting rollback. Failure: {0}" -f [string]$failure.Exception.Message)
            try {
                Set-ProdicloudResizeVmPowerState -ResourceGroup $ResourceGroup -VmName $VmName -DesiredState 'deallocated'
                if ($diskType -eq 'os') {
                    Invoke-ProdicloudResizeAzureVmStep -Label ("rollback OS disk to original '{0}' --no-wait" -f [string]$Disk.DiskName) -Arguments @('vm','update','-g',$ResourceGroup,'-n',$VmName,'--os-disk',$sourceDiskId,'--no-wait','-o','none','--only-show-errors') -Context 'az vm update --os-disk (shrink rollback)'
                    [void](Wait-ProdicloudResizeDiskAttachment -VmResourceGroup $ResourceGroup -VmName $VmName -DiskResourceGroup $ResourceGroup -DiskName ([string]$Disk.DiskName) -DiskId $sourceDiskId -DiskKind 'os' -ShouldBeAttached $true)
                    [void](Wait-ProdicloudResizeDiskAttachment -VmResourceGroup $ResourceGroup -VmName $VmName -DiskResourceGroup $ResourceGroup -DiskName $candidateDiskName -DiskId $candidateDiskId -DiskKind 'os' -ShouldBeAttached $false)
                }
                else {
                    if ($candidateAttachedToTarget) {
                        Invoke-ProdicloudResizeAzureVmStep -Label 'detach failed replacement data disk from target' -Arguments @('vm','disk','detach','-g',$ResourceGroup,'--vm-name',$VmName,'--name',$candidateDiskName,'-o','none','--only-show-errors') -Context 'az vm disk detach (shrink rollback)'
                        [void](Wait-ProdicloudResizeDiskAttachment -VmResourceGroup $ResourceGroup -VmName $VmName -DiskResourceGroup $ResourceGroup -DiskName $candidateDiskName -DiskId $candidateDiskId -DiskKind 'data' -Lun ([int]$Disk.Lun) -ShouldBeAttached $false)
                    }
                    Invoke-ProdicloudResizeAzureVmStep -Label ("restore original data disk '{0}' at LUN {1}" -f [string]$Disk.DiskName,[int]$Disk.Lun) -Arguments @('vm','disk','attach','-g',$ResourceGroup,'--vm-name',$VmName,'--name',$sourceDiskId,'--lun',[string][int]$Disk.Lun,'--caching',[string]$Disk.Caching,'-o','none','--only-show-errors') -Context 'az vm disk attach (shrink rollback)'
                    [void](Wait-ProdicloudResizeDiskAttachment -VmResourceGroup $ResourceGroup -VmName $VmName -DiskResourceGroup $ResourceGroup -DiskName ([string]$Disk.DiskName) -DiskId $sourceDiskId -DiskKind 'data' -Lun ([int]$Disk.Lun) -ShouldBeAttached $true)
                }
                Set-ProdicloudResizeVmPowerState -ResourceGroup $ResourceGroup -VmName $VmName -DesiredState $OriginalPowerState
                if ($diskType -eq 'os') {
                    $profilePath = Get-ProdicloudVmEnvPath -VmName $VmName
                    $configBefore = Read-DotEnvFile -Path $profilePath
                    $restoreMap = @{ SELECTED_VM_NAME = $VmName; SELECTED_RESOURCE_GROUP = $ResourceGroup; VM_DISK_NAME = [string]$Disk.DiskName }
                    $restoreDiskSizeKey = Get-ProdicloudPlatformVmConfigKey -Platform $Platform -BaseKey 'VM_DISK_SIZE_GB'
                    $restoreMap[$restoreDiskSizeKey] = [string]$Disk.DiskSizeGb
                    [void](Save-ProdicloudConfigToDotEnv -EnvFilePath $profilePath -ConfigBefore $configBefore -PersistMap $restoreMap)
                }
                $targetWasCutOver = $false
                Write-Warning 'Disk cutover failed; the original disk was restored and remains available.'
            }
            catch {
                throw ("Disk shrink failed and automatic rollback was not verified. Original disk '{0}' and candidate '{1}' were retained for manual recovery. Operation error: {2}; rollback error: {3}" -f [string]$Disk.DiskName,$candidateDiskName,[string]$failure.Exception.Message,[string]$_.Exception.Message)
            }
        }
        throw $failure
    }
    finally {
        if ($null -ne $helper) {
            try {
                $candidateCleanupName = if ($candidateCreated -and -not $targetWasCutOver) { $candidateDiskName } else { '' }
                if ($operationFailed) {
                    Remove-ProdicloudResizeHelper -Helper $helper -DeferWait -CandidateResourceGroup $ResourceGroup -CandidateDiskName $candidateCleanupName
                    $helperCleanupQueued = $true
                }
                else { Remove-ProdicloudResizeHelper -Helper $helper }
            }
            catch { Write-Warning ("Temporary vc-helper resources remain in '{0}': {1}" -f [string]$helper.ResourceGroup,[string]$_.Exception.Message) }
        }
        if ($operationFailed -and $candidateCreated -and -not $targetWasCutOver -and $helperCleanupQueued -and -not [string]::IsNullOrWhiteSpace($helperResourceGroup)) {
            foreach ($cleanup in @($script:ProdicloudPendingResizeHelperCleanups | Where-Object { [string]$_.ResourceGroup -eq $helperResourceGroup })) {
                $cleanup.CandidateResourceGroup = $ResourceGroup
                $cleanup.CandidateDiskName = $candidateDiskName
            }
        }
        if ($candidateCreated -and -not $targetWasCutOver -and $null -eq $helper -and -not $helperCleanupQueued) {
            try {
                Invoke-ProdicloudResizeAzureVmStep -Label ("delete uncommitted resize candidate '{0}'" -f $candidateDiskName) -Arguments @('disk','delete','-g',$ResourceGroup,'-n',$candidateDiskName,'--yes','--no-wait','-o','none','--only-show-errors') -Context 'az disk delete (uncommitted resize candidate)'
                [void](Wait-ProdicloudResizeDiskDeleted -ResourceGroup $ResourceGroup -DiskName $candidateDiskName -TimeoutSeconds 600)
            }
            catch { Write-Warning ("Uncommitted resize candidate '{0}' remains pending cleanup: {1}" -f $candidateDiskName,[string]$_.Exception.Message) }
        }
    }
}

function Invoke-ProdicloudResizeDiskOperation {
    param(
        [hashtable]$Options,
        [psobject]$VmObject,
        [psobject]$OperationRequest,
        [string]$ResourceGroup,
        [string]$VmName,
        [string]$Region,
        [string]$Platform,
        [psobject]$InitialSnapshot
    )
    $disk = Get-ProdicloudResizeDiskContext -VmObject $VmObject -ResourceGroup $ResourceGroup -VmName $VmName -RequestedDiskName ([string]$OperationRequest.DiskName)
    $targetSize = [int]$OperationRequest.TargetDiskSizeGb
    if ($null -eq $disk.PSObject.Properties['TargetSizeGb']) { $disk | Add-Member -NotePropertyName TargetSizeGb -NotePropertyValue $targetSize }
    if ($targetSize -gt 4095) { throw 'This resize operation is limited to 4095 GiB by the current Azure CLI and disk API contract.' }
    $azureCapacityAlreadyMatches = ($targetSize -eq [int]$disk.DiskSizeGb)
    if ($azureCapacityAlreadyMatches) {
        if ($OperationRequest.Intent -eq 'expand' -and $Platform -eq 'windows') { Write-Host ("Azure disk '{0}' already has {1} GiB; checking and repairing guest volume capacity." -f [string]$disk.DiskName,[int]$disk.DiskSizeGb) -ForegroundColor Yellow }
        else { Write-Host ("No disk resize is needed; '{0}' is already {1} GiB." -f [string]$disk.DiskName,[int]$disk.DiskSizeGb) -ForegroundColor Yellow; return }
    }
    $azureCapacityIncreaseNeeded = ($targetSize -gt [int]$disk.DiskSizeGb)
    if ($OperationRequest.Intent -eq 'expand' -and $targetSize -lt [int]$disk.DiskSizeGb) { throw 'Expand target must be larger than the current disk size.' }
    if ($OperationRequest.Intent -eq 'shrink' -and $targetSize -gt [int]$disk.DiskSizeGb) { throw 'Shrink target must be smaller than the current disk size.' }
    if ($OperationRequest.Intent -eq 'shrink') {
        $confirmed = Get-ProdicloudCliOptionBool -Options $Options -Name 'yes' -DefaultValue $false
        if (-not $confirmed) {
            if (Get-ProdicloudCliOptionBool -Options $Options -Name 'auto' -DefaultValue $false) { throw 'Automated disk shrink requires --yes after the operator has reviewed the replacement and source-cleanup consequences.' }
            if ((Read-Host ("Disk shrink replaces '{0}' and deletes the source disk only after verification. Type SHRINK to continue" -f [string]$disk.DiskName)) -cne 'SHRINK') { Write-Host 'Disk shrink canceled; no Azure disk mutation was made.' -ForegroundColor Yellow; return }
        }
        if ([bool]$disk.DiskObject.encryptionSettingsCollection.enabled -or [int]$disk.DiskObject.maxShares -gt 1) { throw 'Encrypted or shared managed disks are not supported by the shrink clone workflow.' }
        if ([string]$disk.SkuName -notin @('Standard_LRS','StandardSSD_LRS','Premium_LRS','Premium_ZRS','StandardSSD_ZRS')) { throw ("Managed disk SKU '{0}' is not supported by the shrink clone workflow." -f [string]$disk.SkuName) }
    }
    $initialState = Assert-ProdicloudResizeLifecycleStateSupported -Snapshot $InitialSnapshot -VmName $VmName
    $guestDisk = [pscustomobject]@{ Kind = [string]$disk.Kind; Lun = [int]$disk.Lun; DriveLetter = '' }
    $startedTemporarily = ($initialState -ne 'started')
    $inspection = $null
    try {
        if ($startedTemporarily) { Set-ProdicloudResizeVmPowerState -ResourceGroup $ResourceGroup -VmName $VmName -DesiredState 'started' }
        $inspection = Invoke-ProdicloudResizeGuestOperation -ResourceGroup $ResourceGroup -VmName $VmName -Platform $Platform -Action 'inspect' -Disk $guestDisk -VmRecentlyStarted ([bool]$startedTemporarily)
        Write-ProdicloudResizeDiskInventory -Stage 'before' -Inspection $inspection -AzureDiskSizeBytes ([long]$disk.DiskSizeGb * 1GB)
        if ($OperationRequest.Intent -eq 'shrink') {
            $minimumFreeBytes = 10GB
            $targetBytes = [long]$targetSize * 1GB
            $usedBytes = [long]$inspection.usedBytes
            Write-ProdicloudResizeShrinkEstimate -TargetSizeGb $targetSize -Inspection $inspection -MinimumFreeBytes $minimumFreeBytes
            if ($usedBytes + $minimumFreeBytes -gt $targetBytes) {
                throw ("Shrink rejected before Azure disk changes: guest reports {0:N2} GiB used, but target {1} GiB requires at least 10 GiB free ({2:N2} GiB maximum used)." -f ($usedBytes / 1GB),$targetSize,(($targetBytes - $minimumFreeBytes) / 1GB))
            }
            if (-not [bool]$inspection.shrinkCapable) { throw ("Shrink rejected before Azure disk changes: the {0} guest filesystem/partition layout is outside the supported clone set." -f $Platform) }
            if ($disk.Kind -eq 'os' -and $Platform -eq 'windows') {
                $layout = @(ConvertTo-ObjectArrayCompat -InputObject $inspection.partitions)
                $layoutSupport = Get-ProdicloudResizeWindowsOsLayoutSupport -Partitions $layout
                if (-not [bool]$layoutSupport.IsSupported) { throw ("Windows OS shrink requires a supported GPT/UEFI partition layout; no Azure disk change was made. {0}" -f [string]$layoutSupport.Reason) }
                if (@($layoutSupport.IgnoredPartitionNumbers).Count -gt 0) { Write-Host ("Windows shrink will exclude empty leading MSR partition(s) {0} from the source file-copy mapping; the replacement GPT layout will be verified before and after cutover." -f (@($layoutSupport.IgnoredPartitionNumbers) -join ', ')) -ForegroundColor Yellow }
            }
            if ($disk.Kind -eq 'os' -and $Platform -eq 'linux' -and ([string]$inspection.fileSystem -ne 'ext4' -or [string]$inspection.partitionStyle -ne 'gpt' -or [int]$inspection.partitionCount -ne 2 -or [bool]$inspection.lvm)) { throw 'Linux OS shrink requires a two-partition GPT UEFI disk with one ext4 root partition and no LVM.' }
            if ($disk.Kind -eq 'os') {
                if ([string]$disk.HyperVGeneration -ne 'V2') { throw 'OS disk shrink is limited to Gen2/UEFI images in this workflow.' }
                $imageReference = $VmObject.storageProfile.imageReference
                if ($null -eq $imageReference -or [string]::IsNullOrWhiteSpace([string]$imageReference.publisher) -or [string]::IsNullOrWhiteSpace([string]$imageReference.offer) -or [string]::IsNullOrWhiteSpace([string]$imageReference.sku)) { throw 'OS disk shrink requires a resolvable Marketplace image minimum-size check; custom/specialized OS images are rejected before Azure disk changes.' }
                $imageVersion = if (-not [string]::IsNullOrWhiteSpace([string]$imageReference.exactVersion)) { [string]$imageReference.exactVersion } elseif (-not [string]::IsNullOrWhiteSpace([string]$imageReference.version)) { [string]$imageReference.version } else { 'latest' }
                $imageUrn = '{0}:{1}:{2}:{3}' -f [string]$imageReference.publisher,[string]$imageReference.offer,[string]$imageReference.sku,$imageVersion
                Write-ProdicloudActionProgress -Action ("verify shrink target against Marketplace OS image minimum size for '{0}'" -f [string]$imageReference.sku)
                $imageId = [string](az vm image show -l $Region --urn $imageUrn --query id -o tsv --only-show-errors)
                Assert-LastExitCode 'az vm image show (OS disk shrink minimum size)'
                if ([string]::IsNullOrWhiteSpace($imageId)) { throw 'Azure did not return OS image metadata; OS disk shrink stopped before mutation.' }
                $minimumText = [string](az rest --method get --url ("https://management.azure.com{0}" -f $imageId) --uri-parameters 'api-version=2024-03-01' --query 'properties.osDiskImage.sizeInGb' -o tsv --only-show-errors)
                Assert-LastExitCode 'az rest (OS disk shrink image minimum size)'
                $minimumSize = 0
                if (-not [int]::TryParse($minimumText,[ref]$minimumSize) -or $minimumSize -lt 1) { throw 'Azure did not report the Marketplace OS image minimum disk size; OS shrink stopped before mutation.' }
                if ($targetSize -lt $minimumSize) { throw ("OS shrink target {0} GiB is below the Marketplace image minimum of {1} GiB; no Azure disk mutation was made." -f $targetSize,$minimumSize) }
            }
        }
        else {
            $supportedFilesystems = if ($Platform -eq 'windows') { @('NTFS','ReFS') } else { @('ext4','xfs') }
            $observed = if ($Platform -eq 'windows') { @([string]$inspection.targetFileSystem) } else { @([string]$inspection.fileSystem) }
            if (@($observed | Where-Object { $_ -and $_ -notin $supportedFilesystems }).Count -gt 0) { throw ("Automatic guest expansion does not support filesystem '{0}'." -f (@($observed) -join ', ')) }
            if (-not [bool]$inspection.expandCapable) { throw 'Guest partition layout is not safely expandable by the supported Windows/Linux resize scripts; no Azure disk change was made.' }
        }
        if ($OperationRequest.Intent -eq 'shrink') {
            if ($startedTemporarily) { Set-ProdicloudResizeVmPowerState -ResourceGroup $ResourceGroup -VmName $VmName -DesiredState $initialState }
            Set-ProdicloudResizeVmPowerState -ResourceGroup $ResourceGroup -VmName $VmName -DesiredState 'deallocated'
            $disk.TargetSizeGb = $targetSize
            if ($Platform -eq 'windows' -and $disk.Kind -eq 'data' -and @($inspection.driveLetters).Count -gt 0) { $disk.DriveLetter = [string]$inspection.driveLetters[0] }
            $runtime = if ($Platform -eq 'windows') { Initialize-ProdicloudTaskExecutionRuntimeContext -AutoMode -WindowsFlag -Options $Options } else { Initialize-ProdicloudTaskExecutionRuntimeContext -AutoMode -LinuxFlag -Options $Options }
            $runtime.Context.ResourceGroup = $ResourceGroup
            $runtime.Context.VmName = $VmName
            return (Invoke-ProdicloudResizeDiskClone -VmObject $VmObject -Disk $disk -Inspection $inspection -TargetDiskSizeGb $targetSize -ResourceGroup $ResourceGroup -VmName $VmName -Region $Region -Platform $Platform -Runtime $runtime -Options $Options -OriginalPowerState $initialState)
        }

        $beforeSnapshot = Get-ProdicloudResizeLifecycleSnapshot -ResourceGroup $ResourceGroup -VmName $VmName -Stage 'before disk expansion'
        Write-ProdicloudResizeStateSnapshot -Stage 'before' -VmName $VmName -ResourceGroup $ResourceGroup -Region $Region -VmSize ([string]$VmObject.hardwareProfile.vmSize) -DiskName ([string]$disk.DiskName) -DiskSizeGb ([int]$disk.DiskSizeGb) -LifecycleSnapshot $beforeSnapshot
        if ($azureCapacityIncreaseNeeded) {
            Set-ProdicloudResizeVmPowerState -ResourceGroup $ResourceGroup -VmName $VmName -DesiredState 'deallocated'
            Invoke-ProdicloudResizeAzureVmStep -Label ("az disk update -g {0} -n {1} --size-gb {2} --no-wait" -f $ResourceGroup,[string]$disk.DiskName,$targetSize) -Arguments @('disk','update','-g',$ResourceGroup,'-n',[string]$disk.DiskName,'--size-gb',[string]$targetSize,'--no-wait','-o','none','--only-show-errors') -Context 'az disk update (resize expansion)'
            [void](Wait-ProdicloudResizeDiskReady -ResourceGroup $ResourceGroup -DiskName ([string]$disk.DiskName) -ExpectedSizeGb $targetSize -ExpectedSku ([string]$disk.SkuName) -TimeoutSeconds 600)
            Set-ProdicloudResizeVmPowerState -ResourceGroup $ResourceGroup -VmName $VmName -DesiredState 'started'
        }
        else { Write-ProdicloudActionProgress -Action 'reconcile the Windows guest partition to the already-expanded Azure disk without another deallocation' }
        $disk.TargetSizeGb = $targetSize
        $guestResult = Invoke-ProdicloudResizeGuestOperation -ResourceGroup $ResourceGroup -VmName $VmName -Platform $Platform -Action 'expand' -Disk $guestDisk -VmRecentlyStarted ([bool]($azureCapacityIncreaseNeeded -or $startedTemporarily))
        $actualSize = Get-ProdicloudResizeDiskSizeReadback -DiskId ([string]$disk.DiskId) -DiskName ([string]$disk.DiskName) -ExpectedSizeGb $targetSize
        if ($actualSize -ne $targetSize) { throw ("Azure disk size verification failed: expected {0} GiB, actual {1} GiB." -f $targetSize,$actualSize) }
        $expandedInspection = Wait-ProdicloudResizeGuestDiskCapacity -ResourceGroup $ResourceGroup -VmName $VmName -Platform $Platform -Disk $guestDisk -TargetDiskSizeGb $targetSize
        if ($azureCapacityIncreaseNeeded -and [long]$expandedInspection.filesystemSizeBytes -le [long]$inspection.filesystemSizeBytes) { throw 'The guest filesystem did not report increased capacity after the Azure disk expansion.' }
        Write-ProdicloudResizeDiskInventory -Stage 'after' -Inspection $expandedInspection -AzureDiskSizeBytes ([long]$actualSize * 1GB)
        Set-ProdicloudResizeVmPowerState -ResourceGroup $ResourceGroup -VmName $VmName -DesiredState $initialState
        if ($disk.Kind -eq 'os') {
            $profilePath = Get-ProdicloudVmEnvPath -VmName $VmName
            $configBefore = Read-DotEnvFile -Path $profilePath
            $diskSizeKey = Get-ProdicloudPlatformVmConfigKey -Platform $Platform -BaseKey 'VM_DISK_SIZE_GB'
            $persist = @{ SELECTED_VM_NAME = $VmName; SELECTED_RESOURCE_GROUP = $ResourceGroup; $diskSizeKey = [string]$targetSize }
            [void](Save-ProdicloudConfigToDotEnv -EnvFilePath $profilePath -ConfigBefore $configBefore -PersistMap $persist)
        }
        $afterSnapshot = Get-ProdicloudResizeLifecycleSnapshot -ResourceGroup $ResourceGroup -VmName $VmName -Stage 'after disk expansion'
        Write-ProdicloudResizeStateSnapshot -Stage 'after' -VmName $VmName -ResourceGroup $ResourceGroup -Region $Region -VmSize ([string]$VmObject.hardwareProfile.vmSize) -DiskName ([string]$disk.DiskName) -DiskSizeGb $actualSize -LifecycleSnapshot $afterSnapshot
        Write-Host ("Disk expansion completed: Azure capacity and guest filesystem for '{0}' are now {1} GiB." -f [string]$disk.DiskName,$targetSize) -ForegroundColor Green
        return [pscustomobject]@{ DiskName = [string]$disk.DiskName; DiskId = [string]$disk.DiskId; SizeGb = $targetSize; Kind = [string]$disk.Kind; Guest = $guestResult }
    }
    catch {
        $failure = $_
        try { Set-ProdicloudResizeVmPowerState -ResourceGroup $ResourceGroup -VmName $VmName -DesiredState $initialState }
        catch { Write-Warning ("VM power state could not be restored after disk resize failure: {0}" -f [string]$_.Exception.Message) }
        try { Complete-ProdicloudResizeHelperCleanups }
        catch { Write-Warning ("Temporary resize helper cleanup could not be verified after recovery: {0}" -f [string]$_.Exception.Message) }
        throw $failure
    }
}
