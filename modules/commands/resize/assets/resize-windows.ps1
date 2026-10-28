$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$requestJson = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__PRODICLOUD_RESIZE_REQUEST_B64__'))
$request = ConvertFrom-Json -InputObject $requestJson

function Get-TargetDisk {
    param($ResizeRequest)
    if ([string]$ResizeRequest.kind -eq 'os') {
        $systemLetter = $env:SystemDrive.TrimEnd(':')
        $systemPartition = Get-Partition -DriveLetter $systemLetter -ErrorAction Stop
        return (Get-Disk -Number ([int]$systemPartition.DiskNumber) -ErrorAction Stop)
    }
    $lunPattern = ('(?i)LUN\s+{0}(?:\D|$)' -f [int]$ResizeRequest.lun)
    $matches = @(Get-Disk | Where-Object { [string]$_.Location -match $lunPattern })
    if ($matches.Count -ne 1) { throw ('Could not resolve exactly one Windows disk for Azure LUN {0}.' -f [int]$ResizeRequest.lun) }
    return $matches[0]
}

function Write-ResizeResult {
    param([hashtable]$Result)
    $json = ConvertTo-Json -InputObject $Result -Depth 6 -Compress
    Write-Output ('PRODICLOUD_RESIZE_RESULT:' + $json)
}

$disk = Get-TargetDisk -ResizeRequest $request
$partitions = @(Get-Partition -DiskNumber ([int]$disk.Number) -ErrorAction Stop | Sort-Object Offset)
$partitionInventory = @(
    foreach ($partition in $partitions) {
        $partitionVolume = $null
        try {
            $partitionVolumes = @(Get-Volume -Partition $partition -ErrorAction Stop)
            if ($partitionVolumes.Count -gt 0) { $partitionVolume = $partitionVolumes[0] }
        }
        catch { }
        $volumeSizeBytes = [long]0
        $volumeUsedBytes = [long]0
        $volumeFreeBytes = [long]0
        $fileSystem = ''
        $driveLetter = ''
        $volumeLabel = ''
        $healthStatus = ''
        if ($null -ne $partitionVolume) {
            $fileSystem = [string]$partitionVolume.FileSystem
            $driveLetter = [string]$partitionVolume.DriveLetter
            $volumeLabel = [string]$partitionVolume.FileSystemLabel
            $healthStatus = [string]$partitionVolume.HealthStatus
            if ($null -ne $partitionVolume.Size) { $volumeSizeBytes = [long]$partitionVolume.Size }
            if ($null -ne $partitionVolume.Size -and $null -ne $partitionVolume.SizeRemaining) {
                $volumeUsedBytes = [Math]::Max([long]0,([long]$partitionVolume.Size - [long]$partitionVolume.SizeRemaining))
                $volumeFreeBytes = [Math]::Max([long]0,[long]$partitionVolume.SizeRemaining)
            }
        }
        [pscustomobject]@{
            Number = [int]$partition.PartitionNumber
            Offset = [long]$partition.Offset
            Size = [long]$partition.Size
            Type = [string]$partition.Type
            GptType = [string]$partition.GptType
            IsBoot = [bool]$partition.IsBoot
            IsSystem = [bool]$partition.IsSystem
            IsHidden = [bool]$partition.IsHidden
            DriveLetter = $driveLetter
            FileSystem = $fileSystem
            FileSystemLabel = $volumeLabel
            VolumeSizeBytes = $volumeSizeBytes
            UsedBytes = $volumeUsedBytes
            FreeBytes = $volumeFreeBytes
            HealthStatus = $healthStatus
            VolumePresent = ($null -ne $partitionVolume)
            VolumeObject = $partitionVolume
        }
    }
)
$volumes = @($partitionInventory | Where-Object { [bool]$_.VolumePresent } | ForEach-Object { $_.VolumeObject })
$filesystems = @($partitionInventory | ForEach-Object { [string]$_.FileSystem } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
$targetVolume = $null
$targetPartition = $null
if ([string]$request.kind -eq 'os') {
    $targetPartition = Get-Partition -DriveLetter $env:SystemDrive.TrimEnd(':') -ErrorAction Stop
    $targetVolume = Get-Volume -Partition $targetPartition -ErrorAction Stop
}
else {
    foreach ($partition in @($partitions | Sort-Object Offset -Descending)) {
        try {
            $candidateVolume = Get-Volume -Partition $partition -ErrorAction Stop
            if (-not [string]::IsNullOrWhiteSpace([string]$candidateVolume.FileSystem)) { $targetVolume = $candidateVolume; $targetPartition = $partition; break }
        }
        catch { }
    }
}
$usedBytes = [long]0
$freeBytes = [long]0
$volumeSizeBytes = [long]0
$partitionedBytes = [long]0
$nonFilesystemPartitionBytes = [long]0
foreach ($partitionRecord in @($partitionInventory)) {
    $partitionedBytes += [long]$partitionRecord.Size
    $volumeSizeBytes += [long]$partitionRecord.VolumeSizeBytes
    $usedBytes += [long]$partitionRecord.UsedBytes
    $freeBytes += [long]$partitionRecord.FreeBytes
    if ([string]::IsNullOrWhiteSpace([string]$partitionRecord.FileSystem)) { $nonFilesystemPartitionBytes += [long]$partitionRecord.Size }
}
$unallocatedBytes = [Math]::Max([long]0,([long]$disk.Size - $partitionedBytes))
$encrypted = $false
try {
    $bitLockerVolumes = @(Get-BitLockerVolume -ErrorAction Stop)
    if ([string]$request.kind -eq 'os') {
        $osLetter = $env:SystemDrive.TrimEnd(':')
        $encrypted = @($bitLockerVolumes | Where-Object { [string]$_.MountPoint -eq ($osLetter + ':') -and [string]$_.ProtectionStatus -eq 'On' }).Count -gt 0
    }
    else {
        $diskLetters = @($volumes | ForEach-Object { [string]$_.DriveLetter } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        $encrypted = @($bitLockerVolumes | Where-Object { [string]$_.ProtectionStatus -eq 'On' -and $diskLetters -contains ([string]$_.MountPoint).TrimEnd(':') }).Count -gt 0
    }
}
catch { }

if ([string]$request.action -eq 'inspect') {
    $shrinkCapable = $false
    $shrinkLayout = 'unsupported'
    $ignoredPartitionNumbers = @()
    if ([string]$request.kind -eq 'os') {
        $efiGuid = 'C12A7328-F81F-11D2-BA4B-00A0C93EC93B'
        $msrGuid = 'E3C9E316-0B5C-4DB8-817D-F92DF00215AE'
        $basicGuid = 'EBD0A0A2-B9E5-4433-87C0-68B6B72699C7'
        $recoveryGuid = 'DE94BBA4-06D1-4D40-A16A-BFD50179D6AC'
        $efiRecords = @($partitionInventory | Where-Object { [string]$_.GptType -match ('(?i)' + $efiGuid) })
        $msrRecords = @($partitionInventory | Where-Object { [string]$_.GptType -match ('(?i)' + $msrGuid) })
        $basicRecords = @($partitionInventory | Where-Object { [string]$_.GptType -match ('(?i)' + $basicGuid) })
        $recoveryRecords = @($partitionInventory | Where-Object { [string]$_.GptType -match ('(?i)' + $recoveryGuid) })
        $hasOneOfEachRequiredType = ($efiRecords.Count -eq 1 -and $basicRecords.Count -eq 1 -and $recoveryRecords.Count -eq 1)
        if (@($partitions).Count -eq 4 -and $hasOneOfEachRequiredType -and $msrRecords.Count -eq 1) {
            $shrinkLayout = 'GPT-UEFI-4-partition'
        }
        elseif (@($partitions).Count -eq 5 -and $hasOneOfEachRequiredType -and $msrRecords.Count -eq 2) {
            $efiOffset = [long]$efiRecords[0].Offset
            $basicOffset = [long]$basicRecords[0].Offset
            $canonicalMsr = @($msrRecords | Where-Object { [long]$_.Offset -gt $efiOffset -and [long]$_.Offset -lt $basicOffset })
            $leadingMsr = @($msrRecords | Where-Object { [long]$_.Offset -lt $efiOffset })
            if ($canonicalMsr.Count -eq 1 -and $leadingMsr.Count -eq 1) {
                $extraMsr = $leadingMsr[0]
                if ([string]$extraMsr.Type -eq 'Reserved' -and [long]$extraMsr.Offset -le 1MB -and [long]$extraMsr.Size -gt 0 -and [long]$extraMsr.Size -le 32MB -and [string]::IsNullOrWhiteSpace([string]$extraMsr.FileSystem) -and [string]::IsNullOrWhiteSpace([string]$extraMsr.DriveLetter) -and [long]$extraMsr.VolumeSizeBytes -eq 0) {
                    $shrinkLayout = 'GPT-UEFI-4-partition-with-empty-leading-MSR'
                    $ignoredPartitionNumbers = @([int]$extraMsr.Number)
                }
            }
        }
        $shrinkCapable = ([string]$disk.PartitionStyle -eq 'GPT' -and $shrinkLayout -ne 'unsupported' -and -not $encrypted -and $null -ne $targetVolume -and [string]$targetVolume.FileSystem -eq 'NTFS')
    }
    else {
        $shrinkCapable = (-not $encrypted -and @($partitions).Count -eq 1 -and @($filesystems | Where-Object { $_ -notin @('NTFS','ReFS') }).Count -eq 0)
    }
    $expandCapable = ($null -ne $targetPartition -and $null -ne $targetVolume -and [string]$targetVolume.FileSystem -in @('NTFS','ReFS') -and [int]$targetPartition.PartitionNumber -eq [int](@($partitions | Measure-Object -Property PartitionNumber -Maximum).Maximum))
    Write-ResizeResult -Result @{
        status = 'ok'
        action = 'inspect'
        kind = [string]$request.kind
        diskSizeBytes = [long]$disk.Size
        usedBytes = [long]$usedBytes
        freeBytes = [long]$freeBytes
        volumeSizeBytes = [long]$volumeSizeBytes
        partitionedBytes = [long]$partitionedBytes
        unallocatedBytes = [long]$unallocatedBytes
        nonFilesystemPartitionBytes = [long]$nonFilesystemPartitionBytes
        volumeCount = @($partitionInventory | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.FileSystem) }).Count
        volumes = @($partitionInventory | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.FileSystem) } | ForEach-Object { [pscustomobject]@{ PartitionNumber = [int]$_.Number; DriveLetter = [string]$_.DriveLetter; FileSystem = [string]$_.FileSystem; Label = [string]$_.FileSystemLabel; SizeBytes = [long]$_.VolumeSizeBytes; UsedBytes = [long]$_.UsedBytes; FreeBytes = [long]$_.FreeBytes; HealthStatus = [string]$_.HealthStatus } })
        fileSystems = @($filesystems)
        targetFileSystem = if ($null -ne $targetVolume) { [string]$targetVolume.FileSystem } else { '' }
        filesystemSizeBytes = if ($null -ne $targetVolume) { [long]$targetVolume.Size } else { 0 }
        partitionStyle = [string]$disk.PartitionStyle
        partitionCount = @($partitions).Count
        shrinkLayout = [string]$shrinkLayout
        ignoredPartitionNumbers = @($ignoredPartitionNumbers)
        encrypted = [bool]$encrypted
        shrinkCapable = [bool]$shrinkCapable
        expandCapable = [bool]$expandCapable
        driveLetters = @($volumes | ForEach-Object { [string]$_.DriveLetter } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
        diskNumber = [int]$disk.Number
        partitions = @($partitionInventory | ForEach-Object { [pscustomobject]@{ Number = [int]$_.Number; Offset = [long]$_.Offset; Size = [long]$_.Size; Type = [string]$_.Type; GptType = [string]$_.GptType; IsBoot = [bool]$_.IsBoot; IsSystem = [bool]$_.IsSystem; IsHidden = [bool]$_.IsHidden; DriveLetter = [string]$_.DriveLetter; FileSystem = [string]$_.FileSystem; VolumeSizeBytes = [long]$_.VolumeSizeBytes; UsedBytes = [long]$_.UsedBytes; FreeBytes = [long]$_.FreeBytes; HealthStatus = [string]$_.HealthStatus } })
    }
    return
}

if ([string]$request.action -eq 'restore-winre') {
    if ([string]$request.kind -ne 'os') { throw 'Windows RE restoration applies only to the selected OS disk.' }
    $reagentcPath = Join-Path $env:SystemRoot 'System32\reagentc.exe'
    $winreDirectory = Join-Path $env:SystemDrive 'Recovery\WindowsRE'
    $winreImagePath = Join-Path $winreDirectory 'winre.wim'
    if (-not (Test-Path -LiteralPath $winreImagePath -PathType Leaf)) { throw ('The copied Windows RE image was not found at {0}.' -f $winreImagePath) }
    $winreImage = Get-Item -LiteralPath $winreImagePath -Force -ErrorAction Stop
    if ([long]$winreImage.Length -le 0) { throw ('The copied Windows RE image is empty at {0}.' -f $winreImagePath) }
    $reagentInfo = (& $reagentcPath /info 2>&1 | Out-String)
    $reagentInfoExitCode = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
    if ($reagentInfoExitCode -ne 0) { throw ('REAgentC /info failed with exit code {0}.' -f $reagentInfoExitCode) }
    $locationMatch = [regex]::Match($reagentInfo,'(?im)^\s*Windows RE location:\s*(?<location>.+?)\s*$')
    $winreEnabled = ($reagentInfo -match '(?im)^\s*Windows RE status:\s*Enabled\s*$')
    if (-not $winreEnabled -or -not $locationMatch.Success -or [string]::IsNullOrWhiteSpace([string]$locationMatch.Groups['location'].Value)) {
        $setReimage = Start-Process -FilePath $reagentcPath -ArgumentList @('/setreimage','/path',$winreDirectory) -Wait -PassThru -WindowStyle Hidden
        if ($null -eq $setReimage -or [int]$setReimage.ExitCode -ne 0) { throw ('REAgentC could not register the copied Windows RE image at {0}.' -f $winreDirectory) }
        $enableRe = Start-Process -FilePath $reagentcPath -ArgumentList @('/enable') -Wait -PassThru -WindowStyle Hidden
        if ($null -eq $enableRe -or [int]$enableRe.ExitCode -ne 0) { throw 'REAgentC could not enable Windows Recovery Environment on the replacement OS disk.' }
        $reagentInfo = (& $reagentcPath /info 2>&1 | Out-String)
        $reagentInfoExitCode = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
        if ($reagentInfoExitCode -ne 0) { throw ('REAgentC /info verification failed with exit code {0}.' -f $reagentInfoExitCode) }
        $locationMatch = [regex]::Match($reagentInfo,'(?im)^\s*Windows RE location:\s*(?<location>.+?)\s*$')
        $winreEnabled = ($reagentInfo -match '(?im)^\s*Windows RE status:\s*Enabled\s*$')
    }
    if (-not $winreEnabled -or -not $locationMatch.Success -or [string]::IsNullOrWhiteSpace([string]$locationMatch.Groups['location'].Value)) { throw 'Windows RE did not return to the Enabled state with a verified location after disk cutover.' }
    Write-ResizeResult -Result @{ status = 'ok'; action = 'restore-winre'; kind = 'os'; winreEnabled = $true; winreLocation = [string]$locationMatch.Groups['location'].Value.Trim(); winreImageBytes = [long]$winreImage.Length }
    return
}

if ([string]$request.action -eq 'set-drive-letter') {
    if ([string]$request.kind -ne 'data' -or [string]$request.driveLetter -notmatch '^[A-Z]$') { throw 'A valid Windows data-disk drive letter is required.' }
    $dataPartitions = @(Get-Partition -DiskNumber ([int]$disk.Number) -ErrorAction Stop | Sort-Object Offset -Descending)
    $targetPartition = @($dataPartitions | Where-Object {
        try { $volume = Get-Volume -Partition $_ -ErrorAction Stop; -not [string]::IsNullOrWhiteSpace([string]$volume.FileSystem) }
        catch { $false }
    } | Select-Object -First 1)
    if ($targetPartition.Count -ne 1) { throw 'No Windows data partition was available for drive-letter restoration.' }
    $targetPartition = $targetPartition[0]
    $currentVolume = Get-Volume -Partition $targetPartition -ErrorAction Stop
    if ([string]$currentVolume.DriveLetter -ne [string]$request.driveLetter) {
        if (Get-Volume -DriveLetter ([string]$request.driveLetter) -ErrorAction SilentlyContinue) { throw ('Drive letter {0}: is already assigned to another volume.' -f [string]$request.driveLetter) }
        Set-Partition -DiskNumber ([int]$disk.Number) -PartitionNumber ([int]$targetPartition.PartitionNumber) -NewDriveLetter ([string]$request.driveLetter) -ErrorAction Stop
    }
    $verifiedVolume = Get-Volume -DriveLetter ([string]$request.driveLetter) -ErrorAction Stop
    Write-ResizeResult -Result @{ status = 'ok'; action = 'set-drive-letter'; kind = 'data'; driveLetter = [string]$verifiedVolume.DriveLetter; fileSystem = [string]$verifiedVolume.FileSystem }
    return
}

if ([string]$request.action -eq 'expand') {
    if ($null -eq $targetPartition) { throw 'No supported partition was found on the selected Windows disk.' }
    if ($null -eq $targetVolume) { throw 'No filesystem volume is associated with the selected Windows partition.' }
    if ([string]$targetVolume.FileSystem -notin @('NTFS','ReFS')) { throw ('Unsupported Windows filesystem on selected partition: {0}.' -f [string]$targetVolume.FileSystem) }
    $supported = Get-PartitionSupportedSize -DiskNumber ([int]$disk.Number) -PartitionNumber ([int]$targetPartition.PartitionNumber) -ErrorAction Stop
    if ([long]$supported.SizeMax -le [long]$targetPartition.Size) {
        Write-ResizeResult -Result @{ status = 'ok'; action = 'expand'; kind = [string]$request.kind; diskNumber = [int]$disk.Number; partitionNumber = [int]$targetPartition.PartitionNumber; partitionSizeBytes = [long]$targetPartition.Size; supportedPartitionSizeBytes = [long]$supported.SizeMax; fileSystems = @($filesystems); alreadyExpanded = $true }
        return
    }
    $originalPartitionSize = [long]$targetPartition.Size
    $originalFilesystemSize = [long]$targetVolume.Size
    $lastPartitionSize = $originalPartitionSize
    $lastFilesystemSize = $originalFilesystemSize
    $lastReadError = ''
    Resize-Partition -DiskNumber ([int]$disk.Number) -PartitionNumber ([int]$targetPartition.PartitionNumber) -Size ([long]$supported.SizeMax) -ErrorAction Stop
    for ($attempt = 1; $attempt -le 12; $attempt++) {
        Write-Output ("Doing: verify Windows partition and filesystem expansion (check {0}/12)" -f $attempt)
        try {
            $verified = Get-Partition -DiskNumber ([int]$disk.Number) -PartitionNumber ([int]$targetPartition.PartitionNumber) -ErrorAction Stop
            $verifiedVolume = Get-Volume -Partition $verified -ErrorAction Stop
            $lastPartitionSize = [long]$verified.Size
            $lastFilesystemSize = [long]$verifiedVolume.Size
            $lastReadError = ''
            if ($lastPartitionSize -gt $originalPartitionSize -and $lastFilesystemSize -gt $originalFilesystemSize) {
                Write-ResizeResult -Result @{ status = 'ok'; action = 'expand'; kind = [string]$request.kind; diskNumber = [int]$disk.Number; partitionNumber = [int]$verified.PartitionNumber; partitionSizeBytes = $lastPartitionSize; filesystemSizeBytes = $lastFilesystemSize; supportedPartitionSizeBytes = [long]$supported.SizeMax; fileSystems = @($filesystems); alreadyExpanded = $false }
                return
            }
        }
        catch { $lastReadError = [string]$_.Exception.Message }
        if ($attempt -lt 12) { Start-Sleep -Seconds 5 }
    }
    throw ("Windows partition/filesystem size did not stabilize above its original capacity within 60 seconds. Original partition={0} bytes, last partition={1} bytes, original filesystem={2} bytes, last filesystem={3} bytes. Last read error: {4}" -f $originalPartitionSize,$lastPartitionSize,$originalFilesystemSize,$lastFilesystemSize,$lastReadError)
}

throw ("Unsupported Windows guest resize action '{0}'." -f [string]$request.action)
