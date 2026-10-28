$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$requestJson = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__PRODICLOUD_RESIZE_REQUEST_B64__'))
$request = ConvertFrom-Json -InputObject $requestJson
$sourceLun = 10
$targetLun = 11
$script:ResizeStatusPath = Join-Path $env:SystemRoot 'Temp\prodicloud-resize-helper-status.json'
$script:ResizeCopyLogPath = Join-Path $env:SystemRoot 'Temp\prodicloud-resize-helper-robocopy.log'
$script:ResizeCurrentPhase = 'started'
$script:ResizeLastProgressOutputAt = [DateTime]::MinValue
$script:ResizeCopyWarnings = @()

function Write-ResizePhase {
    param([string]$Phase)
    $script:ResizeCurrentPhase = [string]$Phase
    $now = [DateTime]::UtcNow.ToString('o')
    $record = [ordered]@{ phase = [string]$Phase; phaseAtUtc = $now; progressAtUtc = $now; progress = [ordered]@{} }
    [System.IO.File]::WriteAllText($script:ResizeStatusPath,(ConvertTo-Json -InputObject $record -Compress),[System.Text.Encoding]::ASCII)
    [System.Console]::Out.WriteLine(('PRODICLOUD_RESIZE_PHASE:' + (ConvertTo-Json -InputObject ([ordered]@{ phase = [string]$Phase; timestampUtc = $now }) -Compress)))
}
function Write-ResizeProgress {
    param([hashtable]$Progress,[switch]$Activity)
    $phaseAtUtc = [DateTime]::UtcNow.ToString('o')
    $progressAtUtc = $phaseAtUtc
    if (Test-Path -LiteralPath $script:ResizeStatusPath -PathType Leaf) {
        try {
            $current = Get-Content -LiteralPath $script:ResizeStatusPath -Raw | ConvertFrom-Json
            if (-not [string]::IsNullOrWhiteSpace([string]$current.phaseAtUtc)) { $phaseAtUtc = [string]$current.phaseAtUtc }
            if (-not [string]::IsNullOrWhiteSpace([string]$current.progressAtUtc)) { $progressAtUtc = [string]$current.progressAtUtc }
        }
        catch { }
    }
    $heartbeatUtc = [DateTime]::UtcNow.ToString('o')
    if ($Activity) { $progressAtUtc = $heartbeatUtc }
    $record = [ordered]@{ phase = [string]$script:ResizeCurrentPhase; phaseAtUtc = $phaseAtUtc; progressAtUtc = $progressAtUtc; heartbeatAtUtc = $heartbeatUtc; progress = $Progress; copyWarnings = @($script:ResizeCopyWarnings) }
    [System.IO.File]::WriteAllText($script:ResizeStatusPath,(ConvertTo-Json -InputObject $record -Depth 5 -Compress),[System.Text.Encoding]::ASCII)
    if ($Activity -or ([DateTime]::UtcNow - $script:ResizeLastProgressOutputAt).TotalSeconds -ge 30) {
        $script:ResizeLastProgressOutputAt = [DateTime]::UtcNow
        [System.Console]::Out.WriteLine(('PRODICLOUD_RESIZE_PROGRESS:' + (ConvertTo-Json -InputObject $record -Depth 5 -Compress)))
    }
}

function Get-DiskByLun {
    param([int]$Lun)
    $pattern = ('(?i)LUN\s+{0}(?:\D|$)' -f $Lun)
    $matchingDisks = @(Get-Disk | Where-Object { [string]$_.Location -match $pattern })
    if ($matchingDisks.Count -gt 1) { throw ('Expected one disk at helper LUN {0}; found {1}.' -f $Lun,$matchingDisks.Count) }
    if ($matchingDisks.Count -eq 0) { return $null }
    return $matchingDisks[0]
}
function Wait-DiskByLun {
    param([int]$Lun,[ValidateRange(5,600)][int]$TimeoutSeconds = 180)
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $lastHeartbeat = -30
    $storageCacheRefreshed = $false
    while ($watch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        Write-ResizePhase -Phase ("wait-for-lun-{0}" -f $Lun)
        $disk = Get-DiskByLun -Lun $Lun
        if ($null -ne $disk -and [string]$disk.OperationalStatus -notmatch '(?i)starting|connecting|no media|unknown') { return $disk }
        if (-not $storageCacheRefreshed) {
            $storageCacheRefreshed = $true
            if (Get-Command Update-HostStorageCache -ErrorAction SilentlyContinue) {
                Write-ResizePhase -Phase ("refresh-storage-cache-lun-{0}" -f $Lun)
                try { Update-HostStorageCache -ErrorAction Stop } catch { }
            }
        }
        $elapsedSeconds = [int][Math]::Floor($watch.Elapsed.TotalSeconds)
        if (($elapsedSeconds - $lastHeartbeat) -ge 30) {
            $lastHeartbeat = $elapsedSeconds
            Write-ResizeProgress -Activity -Progress ([ordered]@{ phase = ("wait-for-lun-{0}" -f $Lun); elapsedSeconds = $elapsedSeconds; timeoutSeconds = $TimeoutSeconds; diskFound = ($null -ne $disk); operationalStatus = if ($null -ne $disk) { [string]$disk.OperationalStatus } else { 'not visible' } })
        }
        Start-Sleep -Seconds 5
    }
    throw ('Azure-attached disk at helper LUN {0} did not become ready within {1}s.' -f $Lun,$TimeoutSeconds)
}
function Set-TemporaryDriveLetter {
    param($Partition,[char]$Preferred)
    $letter = [string]$Preferred
    if (Get-Volume -DriveLetter $letter -ErrorAction SilentlyContinue) {
        $free = @('Z','Y','X','W','V','U','T','S','R','Q','P','O','N','M','L','K','J','I','H','G','F','E','D') | Where-Object { -not (Get-Volume -DriveLetter $_ -ErrorAction SilentlyContinue) } | Select-Object -First 1
        if (-not $free) { throw 'No temporary drive letter is available for disk preparation.' }
        $letter = [string]$free
    }
    Set-Partition -DiskNumber ([int]$Partition.DiskNumber) -PartitionNumber ([int]$Partition.PartitionNumber) -NewDriveLetter $letter -ErrorAction Stop
    return $letter
}
function Get-ResizeWindowsCopyExclusions {
    param([string]$SourceOsRoot)
    $paths = New-Object 'System.Collections.Generic.List[string]'
    $perUserExclusions = @('AppData\Local\Microsoft\WindowsApps','AppData\Local\Docker\run','AppData\Local\docker-secrets-engine')
    $usersRoot = Join-Path $SourceOsRoot 'Users'
    if (Test-Path -LiteralPath $usersRoot -PathType Container) {
        foreach ($profile in @(Get-ChildItem -LiteralPath $usersRoot -Directory -Force -ErrorAction SilentlyContinue)) {
            foreach ($relativePath in $perUserExclusions) {
                $excludedDirectory = Join-Path $profile.FullName $relativePath
                if (Test-Path -LiteralPath $excludedDirectory -PathType Container) { $paths.Add([string]$excludedDirectory) | Out-Null }
            }
        }
    }
    foreach ($systemProfile in @('Windows\System32\config\systemprofile','Windows\SysWOW64\config\systemprofile')) {
        foreach ($relativePath in $perUserExclusions) {
            $excludedDirectory = Join-Path (Join-Path $SourceOsRoot $systemProfile) $relativePath
            if (Test-Path -LiteralPath $excludedDirectory -PathType Container) { $paths.Add([string]$excludedDirectory) | Out-Null }
        }
    }
    return @($paths.ToArray() | Sort-Object -Unique)
}
function Write-ResizeResult {
    param([hashtable]$Result)
    [System.Console]::Out.WriteLine(('PRODICLOUD_RESIZE_RESULT:' + (ConvertTo-Json -InputObject $Result -Depth 5 -Compress)))
}
function Get-ResizeDiskMetrics {
    param([int]$DiskNumber)
    $metricDisk = Get-Disk -Number $DiskNumber -ErrorAction Stop
    $metricPartitions = @(Get-Partition -DiskNumber $DiskNumber -ErrorAction Stop | Sort-Object Offset)
    $partitionedBytes = [long]0
    $usedBytes = [long]0
    $freeBytes = [long]0
    $volumeSizeBytes = [long]0
    $nonFilesystemPartitionBytes = [long]0
    $partitionRows = @(
        foreach ($partition in $metricPartitions) {
            $partitionedBytes += [long]$partition.Size
            $volume = $null
            try {
                $volumes = @(Get-Volume -Partition $partition -ErrorAction Stop)
                if ($volumes.Count -gt 0) { $volume = $volumes[0] }
            }
            catch { }
            $fileSystem = if ($null -ne $volume) { [string]$volume.FileSystem } else { '' }
            $size = if ($null -ne $volume -and $null -ne $volume.Size) { [long]$volume.Size } else { [long]0 }
            $remaining = if ($null -ne $volume -and $null -ne $volume.SizeRemaining) { [long]$volume.SizeRemaining } else { [long]0 }
            $used = if ($size -gt 0) { [Math]::Max([long]0,($size - $remaining)) } else { [long]0 }
            $free = if ($size -gt 0) { [Math]::Max([long]0,$remaining) } else { [long]0 }
            if ([string]::IsNullOrWhiteSpace($fileSystem)) { $nonFilesystemPartitionBytes += [long]$partition.Size }
            else { $volumeSizeBytes += $size; $usedBytes += $used; $freeBytes += $free }
            [pscustomobject]@{
                Number = [int]$partition.PartitionNumber
                Offset = [long]$partition.Offset
                Size = [long]$partition.Size
                Type = [string]$partition.Type
                OffsetBytes = [long]$partition.Offset
                PartitionSizeBytes = [long]$partition.Size
                GptType = [string]$partition.GptType
                IsBoot = [bool]$partition.IsBoot
                IsSystem = [bool]$partition.IsSystem
                IsHidden = [bool]$partition.IsHidden
                DriveLetter = if ($null -ne $volume) { [string]$volume.DriveLetter } else { '' }
                FileSystem = $fileSystem
                VolumeSizeBytes = $size
                UsedBytes = $used
                FreeBytes = $free
                HealthStatus = if ($null -ne $volume) { [string]$volume.HealthStatus } else { '' }
            }
        }
    )
    return [pscustomobject]@{
        DiskSizeBytes = [long]$metricDisk.Size
        PartitionedBytes = [long]$partitionedBytes
        UnallocatedBytes = [Math]::Max([long]0,([long]$metricDisk.Size - $partitionedBytes))
        NonFilesystemPartitionBytes = [long]$nonFilesystemPartitionBytes
        VolumeSizeBytes = [long]$volumeSizeBytes
        UsedBytes = [long]$usedBytes
        FreeBytes = [long]$freeBytes
        Partitions = @($partitionRows)
    }
}
function Stop-ResizeRobocopy {
    param([System.Diagnostics.Process]$Process)
    if ($null -eq $Process) { return }
    try {
        $Process.Refresh()
        if ($Process.HasExited) { return }
        $taskKillPath = Join-Path $env:SystemRoot 'System32\taskkill.exe'
        if (Test-Path -LiteralPath $taskKillPath -PathType Leaf) {
            $stopper = Start-Process -FilePath $taskKillPath -ArgumentList @('/PID',[string][int]$Process.Id,'/T','/F') -Wait -PassThru -WindowStyle Hidden
            if ([int]$stopper.ExitCode -ne 0) { throw ('taskkill could not stop Robocopy process {0} (exit {1}).' -f [int]$Process.Id,[int]$stopper.ExitCode) }
        }
        else { $Process.Kill() }
        if (-not $Process.WaitForExit(10000)) { throw ('Robocopy process {0} did not exit after termination.' -f [int]$Process.Id) }
    }
    catch { throw ("Could not stop stalled Robocopy process safely: {0}" -f [string]$_.Exception.Message) }
}
function Get-ResizeRobocopyFailureDetails {
    param([string]$Phase,[int]$ExitCode)
    $tail = @()
    if (Test-Path -LiteralPath $script:ResizeCopyLogPath -PathType Leaf) {
        try { $tail = @(Get-Content -LiteralPath $script:ResizeCopyLogPath -Tail 120 -ErrorAction Stop) } catch { }
    }
    $errors = New-Object 'System.Collections.Generic.List[object]'
    for ($index = 0; $index -lt @($tail).Count; $index++) {
        $line = [string]$tail[$index]
        if ($line -match '(?i)\bERROR\s+(?<code>\d+)\s+\((?<hex>0x[0-9a-f]+)\)\s*(?<detail>.*)$') {
            $win32Code = [int]$Matches.code
            $hexCode = [string]$Matches.hex
            $errorDetail = [string]$Matches.detail
            $fileName = ''
            $relativePath = ''
            if ($line -match '(?i)Copying\s+File\s+(?<path>[A-Z]:\\.*)$') {
                $copyPath = ([string]$Matches.path).Trim().Trim('"')
                try { $fileName = [System.IO.Path]::GetFileName($copyPath) } catch { }
                $relativePath = $copyPath -replace '(?i)^[A-Z]:\\Users\\[^\\]+','%USERPROFILE%'
                $relativePath = $relativePath -replace '^[A-Z]:\\',''
                if ($relativePath.Length -gt 240) { $relativePath = $relativePath.Substring($relativePath.Length - 240) }
            }
            $detail = $errorDetail
            if ($index + 1 -lt @($tail).Count -and [string]$tail[$index + 1] -notmatch '(?i)^\s*ERROR\s+\d+') { $detail = (@($detail,[string]$tail[$index + 1]) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) -join ' ' }
            $detail = $detail -replace '(?i)[A-Z]:\\(?:[^\\\s]+\\)*[^\\\s]*','[path]'
            $detail = $detail -replace '\s+',' '
            $errors.Add([ordered]@{ win32Code = $win32Code; hexCode = $hexCode; fileName = $fileName; relativePath = $relativePath; message = $detail.Trim() }) | Out-Null
        }
    }
    $summaryLines = @($tail | Where-Object { [string]$_ -match '^\s*(?:Total|Dirs|Files|Bytes|Times|Ended)\s*:' } | Select-Object -Last 12 | ForEach-Object { ([string]$_).Trim() })
    $errorRecords = @($errors.ToArray() | Select-Object -Last 12)
    return [pscustomobject]@{
        phase = [string]$Phase
        exitCode = [int]$ExitCode
        logBytes = if (Test-Path -LiteralPath $script:ResizeCopyLogPath -PathType Leaf) { [long](Get-Item -LiteralPath $script:ResizeCopyLogPath).Length } else { [long]0 }
        errors = @($errorRecords)
        summary = @($summaryLines)
    }
}
function Invoke-ResizeRobocopy {
    param(
        [string[]]$Arguments,
        [string]$Phase,
        [ValidateRange(60,3600)][int]$TimeoutSeconds = 3300,
        [ValidateRange(30,180)][int]$IdleSeconds = 60
    )
    $robocopyPath = Join-Path $env:SystemRoot 'System32\robocopy.exe'
    if (-not (Test-Path -LiteralPath $robocopyPath -PathType Leaf)) { throw 'Windows Robocopy is unavailable on the temporary helper.' }
    $totalWatch = [System.Diagnostics.Stopwatch]::StartNew()
    $previousFailures = New-Object 'System.Collections.Generic.List[object]'
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        $null = Write-ResizePhase -Phase $Phase
        $process = Start-Process -FilePath $robocopyPath -ArgumentList $Arguments -PassThru -WindowStyle Hidden
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        $lastProgressAt = [DateTime]::UtcNow
        $lastLogBytes = [long]-1
        $lastCpuSeconds = [double]-1
        $stalled = $false
        while ($true) {
            $process.Refresh()
            if ($process.HasExited) { break }
            $cpuSeconds = [double]0
            try { $cpuSeconds = [double](Get-Process -Id ([int]$process.Id) -ErrorAction Stop).CPU } catch { }
            $logBytes = [long]0
            if (Test-Path -LiteralPath $script:ResizeCopyLogPath -PathType Leaf) {
                try { $logBytes = [long](Get-Item -LiteralPath $script:ResizeCopyLogPath -ErrorAction Stop).Length } catch { }
            }
            $readBytesPerSecond = [double]0
            $writeBytesPerSecond = [double]0
            try {
                $diskCounters = @(Get-CimInstance -ClassName Win32_PerfFormattedData_PerfDisk_PhysicalDisk -Filter "Name='_Total'" -ErrorAction Stop)
                if ($diskCounters.Count -gt 0) {
                    $readBytesPerSecond = [double]$diskCounters[0].DiskReadBytesPersec
                    $writeBytesPerSecond = [double]$diskCounters[0].DiskWriteBytesPersec
                }
            }
            catch { }
            $processAdvanced = ($lastCpuSeconds -ge 0 -and $cpuSeconds -gt ($lastCpuSeconds + 0.05))
            $logAdvanced = ($lastLogBytes -ge 0 -and $logBytes -gt $lastLogBytes)
            $diskActive = ($readBytesPerSecond -ge 64KB) -or ($writeBytesPerSecond -ge 64KB)
            $hasProgress = $processAdvanced -or $logAdvanced -or $diskActive
            if ($hasProgress) { $lastProgressAt = [DateTime]::UtcNow }
            $lastCpuSeconds = $cpuSeconds
            $lastLogBytes = $logBytes
            $null = Write-ResizeProgress -Activity:$hasProgress -Progress ([ordered]@{
                attempt = $attempt
                elapsedSeconds = [int][Math]::Floor($totalWatch.Elapsed.TotalSeconds)
                attemptElapsedSeconds = [int][Math]::Floor($watch.Elapsed.TotalSeconds)
                robocopyCpuSeconds = [Math]::Round($cpuSeconds,2)
                robocopyLogBytes = $logBytes
                diskReadBytesPerSecond = [long]$readBytesPerSecond
                diskWriteBytesPerSecond = [long]$writeBytesPerSecond
                previousFailureCount = [int]$previousFailures.Count
            })
            if ($totalWatch.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
                Stop-ResizeRobocopy -Process $process
                throw ("Robocopy phase '{0}' exceeded its {1}-second total bound during attempt {2}." -f $Phase,$TimeoutSeconds,$attempt)
            }
            if (([DateTime]::UtcNow - $lastProgressAt).TotalSeconds -ge $IdleSeconds) {
                Stop-ResizeRobocopy -Process $process
                if ($attempt -ge 2) { throw ("Robocopy phase '{0}' had no measured CPU, disk, or log progress for {1} seconds after one retry." -f $Phase,$IdleSeconds) }
                $stalled = $true
                Write-ResizePhase -Phase $Phase
                Write-ResizeProgress -Activity -Progress ([ordered]@{ attempt = $attempt; retry = $true; reason = ('no measured guest activity for {0} seconds; Robocopy is restarting once' -f $IdleSeconds); robocopyLogBytes = $logBytes })
                break
            }
            Start-Sleep -Seconds 5
        }
        $watch.Stop()
        if ($stalled) { continue }
        $exitCode = [int]$process.ExitCode
        if ($exitCode -ge 8) {
            $failureDetails = Get-ResizeRobocopyFailureDetails -Phase $Phase -ExitCode $exitCode
            $errorSummary = @($failureDetails.errors | ForEach-Object {
                $fileNameText = if (-not [string]::IsNullOrWhiteSpace([string]$_.fileName)) { ' file=' + [string]$_.fileName } else { '' }
                $relativePathText = if (-not [string]::IsNullOrWhiteSpace([string]$_.relativePath)) { ' path=' + [string]$_.relativePath } else { '' }
                if (-not [string]::IsNullOrWhiteSpace([string]$_.message)) { '{0} ({1}){2}{3}: {4}' -f [int]$_.win32Code,[string]$_.hexCode,$fileNameText,$relativePathText,[string]$_.message } else { '{0} ({1}){2}{3}' -f [int]$_.win32Code,[string]$_.hexCode,$fileNameText,$relativePathText }
            }) -join '; '
            $copySummary = @($failureDetails.summary) -join ' | '
            $attemptRecord = [ordered]@{ attempt = $attempt; details = $failureDetails }
            [System.Console]::Out.WriteLine(('PRODICLOUD_RESIZE_COPY_FAILURE:' + (ConvertTo-Json -InputObject $attemptRecord -Depth 6 -Compress)))
            if ($attempt -lt 2) {
                $previousFailures.Add($failureDetails) | Out-Null
                Write-ResizePhase -Phase $Phase
                Write-ResizeProgress -Activity -Progress ([ordered]@{ attempt = $attempt; retry = $true; reason = ('Robocopy exited {0}; rerun the idempotent /MIR copy once' -f $exitCode); previousFailureCount = [int]$previousFailures.Count; previousErrors = @($failureDetails.errors); previousSummary = @($failureDetails.summary) })
                continue
            }
            $priorSummary = @($previousFailures | ForEach-Object { '{0}: {1}' -f [int]$_.exitCode,(@($_.errors | ForEach-Object { ('{0} {1} {2}' -f [string]$_.fileName,[string]$_.relativePath,[string]$_.message).Trim() }) -join '; ') }) -join ' | '
            $retrySuffix = if (-not [string]::IsNullOrWhiteSpace($priorSummary)) { ' Previous attempt: ' + $priorSummary } else { '' }
            throw ("Robocopy phase '{0}' failed with exit code {1} on attempt {2}. File errors: {3}. Summary: {4}.{5}" -f $Phase,$exitCode,$attempt,$errorSummary,$copySummary,$retrySuffix)
        }
        return $process
    }
    throw ("Robocopy phase '{0}' did not complete after one retry." -f $Phase)
}

$null = Write-ResizePhase -Phase 'started'
$sourceDisk = Wait-DiskByLun -Lun $sourceLun -TimeoutSeconds 180
$targetDisk = Wait-DiskByLun -Lun $targetLun -TimeoutSeconds 180
$null = Write-ResizePhase -Phase 'disks-discovered'
if ([bool]$sourceDisk.IsOffline -or [bool]$sourceDisk.IsReadOnly) {
    if ([bool]$sourceDisk.IsOffline) { Set-Disk -Number ([int]$sourceDisk.Number) -IsOffline $false -ErrorAction Stop }
    if ([bool]$sourceDisk.IsReadOnly) { Set-Disk -Number ([int]$sourceDisk.Number) -IsReadOnly $false -ErrorAction Stop }
    $sourceDisk = Get-Disk -Number ([int]$sourceDisk.Number) -ErrorAction Stop
}
if ([string]$sourceDisk.PartitionStyle -eq 'RAW') { throw 'The source clone has no recognized partition table.' }
if ([string]$request.kind -eq 'data') {
    $sourcePartitions = @(Get-Partition -DiskNumber ([int]$sourceDisk.Number) | Where-Object { [string]$_.Type -ne 'Reserved' })
    if ($sourcePartitions.Count -ne 1) { throw 'Windows data-disk shrink supports a single data partition only.' }
    $sourcePartition = $sourcePartitions[0]
    $sourceLetter = Set-TemporaryDriveLetter -Partition $sourcePartition -Preferred 'R'
    $sourceVolume = Get-Volume -DriveLetter $sourceLetter -ErrorAction Stop
    if ([string]$sourceVolume.FileSystem -notin @('NTFS','ReFS')) { throw ('Windows data-disk shrink does not support filesystem {0}.' -f [string]$sourceVolume.FileSystem) }
    if ([long]$sourceVolume.SizeRemaining -lt 0) { throw 'Windows reported an invalid free-space value on the source disk.' }
    $minimumFreeBytes = if ($null -ne $request.minimumFreeBytes) { [long]$request.minimumFreeBytes } else { [long](10GB) }
    $sourceMetrics = Get-ResizeDiskMetrics -DiskNumber ([int]$sourceDisk.Number)
    $expectedSourceUsedBytes = if ($null -ne $request.expectedSourceUsedBytes) { [long]$request.expectedSourceUsedBytes } else { [long]$sourceMetrics.UsedBytes }
    $sourceMeasurementDeltaBytes = [long]$sourceMetrics.UsedBytes - $expectedSourceUsedBytes
    if ([long]$sourceMetrics.UsedBytes + $minimumFreeBytes -gt [long]$targetDisk.Size) { throw ('Source-clone remeasurement exceeds the selected replacement capacity before copy: source used={0:N2} GiB; candidate capacity={1:N2} GiB; required headroom={2:N2} GiB.' -f ([long]$sourceMetrics.UsedBytes / 1GB),([long]$targetDisk.Size / 1GB),($minimumFreeBytes / 1GB)) }
    Write-ResizePhase -Phase 'remeasure-source-disk'
    Write-ResizeProgress -Activity -Progress ([ordered]@{ sourceUsedBytes = [long]$sourceMetrics.UsedBytes; initialInventoryUsedBytes = $expectedSourceUsedBytes; measurementDeltaBytes = $sourceMeasurementDeltaBytes; sourceFreeBytes = [long]$sourceMetrics.FreeBytes; candidateCapacityBytes = [long]$targetDisk.Size; minimumFreeBytes = $minimumFreeBytes })
    if ([string]$targetDisk.PartitionStyle -ne 'RAW') { throw 'The replacement data disk is not empty.' }
    Write-ResizePhase -Phase 'prepare-data-target'
    Initialize-Disk -Number ([int]$targetDisk.Number) -PartitionStyle GPT -ErrorAction Stop | Out-Null
    $targetPartition = New-Partition -DiskNumber ([int]$targetDisk.Number) -UseMaximumSize -AssignDriveLetter -ErrorAction Stop
    $targetVolume = Format-Volume -Partition $targetPartition -FileSystem ([string]$sourceVolume.FileSystem) -NewFileSystemLabel ([string]$sourceVolume.FileSystemLabel) -Confirm:$false -Force -ErrorAction Stop
    $targetLetter = [string]$targetVolume.DriveLetter
    Write-ResizePhase -Phase 'copy-data-volume'
    $copy = Invoke-ResizeRobocopy -Phase 'copy-data-volume' -Arguments @(("{0}:\" -f $sourceLetter),("{0}:\" -f $targetLetter),'/MIR','/COPYALL','/DCOPY:DAT','/XJ','/B','/R:0','/W:0','/MT:64','/J','/SL','/BYTES','/NFL','/NDL','/NP',('/LOG:' + $script:ResizeCopyLogPath))
    $targetVolumeReadback = Get-Volume -DriveLetter $targetLetter -ErrorAction Stop
    $replacementMetrics = Get-ResizeDiskMetrics -DiskNumber ([int]$targetDisk.Number)
    if ([long]$replacementMetrics.UsedBytes + $minimumFreeBytes -gt [long]$replacementMetrics.DiskSizeBytes -or [long]$replacementMetrics.FreeBytes -lt $minimumFreeBytes) { throw ('Replacement data disk does not retain the required free-space headroom before cutover: used={0:N2} GiB; free={1:N2} GiB; disk capacity={2:N2} GiB; required={3:N2} GiB.' -f ([long]$replacementMetrics.UsedBytes / 1GB),([long]$replacementMetrics.FreeBytes / 1GB),([long]$replacementMetrics.DiskSizeBytes / 1GB),($minimumFreeBytes / 1GB)) }
    $targetDisk | Set-Disk -IsOffline $true -ErrorAction Stop
    Write-ResizePhase -Phase 'verify-data-volume'
    Write-ResizeResult -Result @{ status = 'ok'; kind = 'data'; fileSystem = [string]$sourceVolume.FileSystem; usedBytes = [long]$sourceMetrics.UsedBytes; sourceUsedBytes = [long]$sourceMetrics.UsedBytes; sourceFreeBytes = [long]$sourceMetrics.FreeBytes; expectedSourceUsedBytes = $expectedSourceUsedBytes; sourceMeasurementDeltaBytes = $sourceMeasurementDeltaBytes; replacementUsedBytes = [long]$replacementMetrics.UsedBytes; replacementFreeBytes = [long]$replacementMetrics.FreeBytes; replacementSizeBytes = [long]$replacementMetrics.DiskSizeBytes; replacementVolumeSizeBytes = [long]$targetVolumeReadback.Size; replacementDriveLetter = $targetLetter; minimumFreeBytes = $minimumFreeBytes; partitions = @($replacementMetrics.Partitions) }
    exit 0
}

if ([string]$request.kind -ne 'os') { throw 'Unsupported Windows disk kind for helper shrink.' }
Write-ResizePhase -Phase 'inspect-os-layout'
if ([string]$sourceDisk.PartitionStyle -ne 'GPT') { throw 'Windows OS disk shrink supports GPT/UEFI layouts only.' }
$partitions = @(Get-Partition -DiskNumber ([int]$sourceDisk.Number) | Sort-Object Offset)
$efiGuid = 'C12A7328-F81F-11D2-BA4B-00A0C93EC93B'
$msrGuid = 'E3C9E316-0B5C-4DB8-817D-F92DF00215AE'
$basicGuid = 'EBD0A0A2-B9E5-4433-87C0-68B6B72699C7'
$recoveryGuid = 'DE94BBA4-06D1-4D40-A16A-BFD50179D6AC'
$efiGptType = '{' + $efiGuid + '}'
$msrGptType = '{' + $msrGuid + '}'
$basicGptType = '{' + $basicGuid + '}'
$recoveryGptType = '{' + $recoveryGuid + '}'
$efiSource = @($partitions | Where-Object { [string]$_.GptType -match $efiGuid })
$msrSources = @($partitions | Where-Object { [string]$_.GptType -match $msrGuid })
$osSource = @($partitions | Where-Object { [string]$_.GptType -match $basicGuid })
$recoverySource = @($partitions | Where-Object { [string]$_.GptType -match $recoveryGuid })
$ignoredSourcePartitionNumbers = @()
$sourcePartitionLayout = ''
if ($efiSource.Count -eq 1 -and $msrSources.Count -eq 1 -and $osSource.Count -eq 1 -and $recoverySource.Count -eq 1 -and $partitions.Count -eq 4) {
    $msrSource = @($msrSources[0])
    $sourcePartitionLayout = 'GPT-UEFI-4-partition'
}
elseif ($efiSource.Count -eq 1 -and $msrSources.Count -eq 2 -and $osSource.Count -eq 1 -and $recoverySource.Count -eq 1 -and $partitions.Count -eq 5) {
    $efiOffset = [long]$efiSource[0].Offset
    $osOffset = [long]$osSource[0].Offset
    $canonicalMsr = @($msrSources | Where-Object { [long]$_.Offset -gt $efiOffset -and [long]$_.Offset -lt $osOffset })
    $leadingMsr = @($msrSources | Where-Object { [long]$_.Offset -lt $efiOffset })
    if ($canonicalMsr.Count -ne 1 -or $leadingMsr.Count -ne 1) { throw 'Windows OS shrink found a five-partition disk without exactly one canonical MSR and one leading MSR; the source disk was not modified.' }
    $extraMsr = $leadingMsr[0]
    $extraMsrHasFilesystem = $false
    try {
        $extraMsrVolumes = @(Get-Volume -Partition $extraMsr -ErrorAction Stop)
        $extraMsrHasFilesystem = @($extraMsrVolumes | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.FileSystem) -or [long]$_.Size -gt 0 }).Count -gt 0
    }
    catch { }
    $extraMsrDriveLetter = if ($null -ne $extraMsr.PSObject.Properties['DriveLetter']) { [string]$extraMsr.DriveLetter } else { '' }
    if ($extraMsrDriveLetter -eq [string][char]0) { $extraMsrDriveLetter = '' }
    if ([string]$extraMsr.Type -ne 'Reserved' -or [bool]$extraMsr.IsBoot -or [bool]$extraMsr.IsSystem -or -not [string]::IsNullOrWhiteSpace($extraMsrDriveLetter) -or [long]$extraMsr.Offset -gt 1MB -or [long]$extraMsr.Size -le 0 -or [long]$extraMsr.Size -gt 32MB -or $extraMsrHasFilesystem) { throw 'The leading MSR is not a small empty reserved partition; Windows OS shrink stopped before copying.' }
    $msrSource = @($canonicalMsr[0])
    $ignoredSourcePartitionNumbers = @([int]$extraMsr.PartitionNumber)
    $sourcePartitionLayout = 'GPT-UEFI-4-partition-with-empty-leading-MSR'
    Write-ResizePhase -Phase 'normalize-empty-leading-msr'
    Write-ResizeProgress -Activity -Progress ([ordered]@{ sourcePartitionCount = 5; copiedPartitionCount = 4; ignoredEmptyMsrPartitionNumber = [int]$extraMsr.PartitionNumber; ignoredEmptyMsrSizeBytes = [long]$extraMsr.Size })
}
else {
    throw 'Windows OS shrink requires the standard four GPT/UEFI partitions or those partitions plus one small, empty leading MSR; this source layout is not in the supported set.'
}
$sourceOsLetter = Set-TemporaryDriveLetter -Partition $osSource[0] -Preferred 'R'
$osVolume = Get-Volume -DriveLetter $sourceOsLetter -ErrorAction Stop
if ([string]$osVolume.FileSystem -ne 'NTFS') { throw ("Windows OS disk shrink supports NTFS only; the mounted working clone reports '{0}' (offline={1}, read-only={2})." -f [string]$osVolume.FileSystem,[bool]$sourceDisk.IsOffline,[bool]$sourceDisk.IsReadOnly) }
$sourceEfiLetter = Set-TemporaryDriveLetter -Partition $efiSource[0] -Preferred 'S'
$sourceRecoveryLetter = Set-TemporaryDriveLetter -Partition $recoverySource[0] -Preferred 'Q'
$minimumFreeBytes = if ($null -ne $request.minimumFreeBytes) { [long]$request.minimumFreeBytes } else { [long](10GB) }
$sourceMetrics = Get-ResizeDiskMetrics -DiskNumber ([int]$sourceDisk.Number)
$expectedSourceUsedBytes = if ($null -ne $request.expectedSourceUsedBytes) { [long]$request.expectedSourceUsedBytes } else { [long]$sourceMetrics.UsedBytes }
$sourceMeasurementDeltaBytes = [long]$sourceMetrics.UsedBytes - $expectedSourceUsedBytes
if ([long]$sourceMetrics.UsedBytes + $minimumFreeBytes -gt [long]$targetDisk.Size) { throw ('Source-clone remeasurement exceeds the selected OS replacement capacity before copy: source used={0:N2} GiB; candidate capacity={1:N2} GiB; required headroom={2:N2} GiB.' -f ([long]$sourceMetrics.UsedBytes / 1GB),([long]$targetDisk.Size / 1GB),($minimumFreeBytes / 1GB)) }
Write-ResizePhase -Phase 'remeasure-source-disk'
Write-ResizeProgress -Activity -Progress ([ordered]@{ sourceUsedBytes = [long]$sourceMetrics.UsedBytes; initialInventoryUsedBytes = $expectedSourceUsedBytes; measurementDeltaBytes = $sourceMeasurementDeltaBytes; sourceFreeBytes = [long]$sourceMetrics.FreeBytes; candidateCapacityBytes = [long]$targetDisk.Size; minimumFreeBytes = $minimumFreeBytes })
if ([string]$targetDisk.PartitionStyle -ne 'RAW') {
    if ([bool]$targetDisk.IsBoot -or [bool]$targetDisk.IsSystem) { throw 'The replacement OS candidate unexpectedly contains the helper VM boot/system partitions; refusing to clear it.' }
    if ([bool]$targetDisk.IsOffline) { Set-Disk -Number ([int]$targetDisk.Number) -IsOffline $false -ErrorAction Stop }
    if ([bool]$targetDisk.IsReadOnly) { Set-Disk -Number ([int]$targetDisk.Number) -IsReadOnly $false -ErrorAction Stop }
    Write-ResizePhase -Phase 'clear-image-based-os-candidate'
    Clear-Disk -Number ([int]$targetDisk.Number) -RemoveData -RemoveOEM -Confirm:$false -ErrorAction Stop | Out-Null
    $targetDisk = Get-Disk -Number ([int]$targetDisk.Number) -ErrorAction Stop
    $remainingCandidatePartitions = @(Get-Partition -DiskNumber ([int]$targetDisk.Number) -ErrorAction SilentlyContinue)
    if ($remainingCandidatePartitions.Count -gt 0) {
        if ([bool]$targetDisk.IsBoot -or [bool]$targetDisk.IsSystem) { throw 'The non-RAW replacement OS candidate is a helper boot/system disk; refusing the DiskPart cleanup.' }
        $diskpartPath = Join-Path $env:SystemRoot 'System32\diskpart.exe'
        $diskpartScriptPath = Join-Path $env:TEMP ('prodicloud-resize-clean-candidate-{0}.txt' -f [guid]::NewGuid().ToString('N'))
        try {
            @(("select disk {0}" -f [int]$targetDisk.Number),'clean','exit') | Set-Content -LiteralPath $diskpartScriptPath -Encoding ASCII -ErrorAction Stop
            $diskpart = Start-Process -FilePath $diskpartPath -ArgumentList @('/s',$diskpartScriptPath) -Wait -PassThru -WindowStyle Hidden
            if ($null -eq $diskpart -or [int]$diskpart.ExitCode -ne 0) { throw ('DiskPart could not clear the remaining platform-image partitions from replacement candidate disk {0}.' -f [int]$targetDisk.Number) }
        }
        finally {
            if (Test-Path -LiteralPath $diskpartScriptPath -PathType Leaf) { Remove-Item -LiteralPath $diskpartScriptPath -Force -ErrorAction SilentlyContinue }
        }
        $updateStorageCache = Get-Command Update-HostStorageCache -ErrorAction SilentlyContinue
        if ($null -ne $updateStorageCache) { Update-HostStorageCache -ErrorAction Stop }
        $targetDisk = Get-Disk -Number ([int]$targetDisk.Number) -ErrorAction Stop
        $remainingCandidatePartitions = @(Get-Partition -DiskNumber ([int]$targetDisk.Number) -ErrorAction SilentlyContinue)
        if ($remainingCandidatePartitions.Count -gt 0) { throw ('DiskPart left {0} partition(s) on replacement OS candidate disk {1}.' -f $remainingCandidatePartitions.Count,[int]$targetDisk.Number) }
    }
}
if ([string]$targetDisk.PartitionStyle -ne 'RAW') { throw 'The replacement OS disk could not be cleared to a raw partition layout.' }
Write-ResizePhase -Phase 'prepare-os-partitions'
Initialize-Disk -Number ([int]$targetDisk.Number) -PartitionStyle GPT -ErrorAction Stop | Out-Null
$efiTarget = New-Partition -DiskNumber ([int]$targetDisk.Number) -Size ([long]$efiSource[0].Size) -GptType $efiGptType -ErrorAction Stop
$msrTarget = New-Partition -DiskNumber ([int]$targetDisk.Number) -Size ([long]$msrSource[0].Size) -GptType $msrGptType -ErrorAction Stop
$recoverySize = [long]$recoverySource[0].Size
$recoveryTarget = New-Partition -DiskNumber ([int]$targetDisk.Number) -Size $recoverySize -GptType $recoveryGptType -ErrorAction Stop
$osTarget = New-Partition -DiskNumber ([int]$targetDisk.Number) -UseMaximumSize -GptType $basicGptType -ErrorAction Stop
$osPartitionSize = [long]$osTarget.Size
if ($osPartitionSize -le 0 -or ([long]$osVolume.Size - [long]$osVolume.SizeRemaining + 4GB) -gt $osPartitionSize) { throw 'Requested disk size cannot contain the Windows EFI, MSR, OS, and Recovery partitions with safe free-space headroom.' }
$efiTargetLetter = Set-TemporaryDriveLetter -Partition $efiTarget -Preferred 'T'
$osTargetLetter = Set-TemporaryDriveLetter -Partition $osTarget -Preferred 'U'
$recoveryTargetLetter = Set-TemporaryDriveLetter -Partition $recoveryTarget -Preferred 'V'
Format-Volume -DriveLetter $efiTargetLetter -FileSystem FAT32 -NewFileSystemLabel 'System' -Confirm:$false -Force -ErrorAction Stop | Out-Null
Format-Volume -DriveLetter $osTargetLetter -FileSystem NTFS -NewFileSystemLabel ([string]$osVolume.FileSystemLabel) -Confirm:$false -Force -ErrorAction Stop | Out-Null
Format-Volume -DriveLetter $recoveryTargetLetter -FileSystem NTFS -NewFileSystemLabel 'Recovery' -Confirm:$false -Force -ErrorAction Stop | Out-Null
$recoveryCopy = Invoke-ResizeRobocopy -Phase 'copy-recovery-partition' -TimeoutSeconds 600 -Arguments @(("{0}:\" -f $sourceRecoveryLetter),("{0}:\" -f $recoveryTargetLetter),'/MIR','/COPYALL','/DCOPY:DAT','/XJ','/B','/R:0','/W:0','/MT:4','/J','/SL','/BYTES','/NFL','/NDL','/NP',('/LOG:' + $script:ResizeCopyLogPath))
Write-ResizePhase -Phase 'copy-os-volume'
$guestCopyExclusions = @(Get-ResizeWindowsCopyExclusions -SourceOsRoot ("{0}:\" -f $sourceOsLetter))
$osCopyArguments = @(("{0}:\" -f $sourceOsLetter),("{0}:\" -f $osTargetLetter),'/MIR','/COPYALL','/DCOPY:DAT','/XJ','/B','/R:0','/W:0','/MT:64','/J','/SL','/BYTES','/NFL','/NDL','/NP','/XF','pagefile.sys','swapfile.sys')
if ($guestCopyExclusions.Count -gt 0) {
    $osCopyArguments += '/XD'
    foreach ($excludedDirectory in $guestCopyExclusions) { $osCopyArguments += ('"' + [string]$excludedDirectory + '"') }
    $copyPolicyWarning = [ordered]@{ phase = 'copy-os-volume'; kind = 'regenerated-runtime-artifacts'; directoryCount = [int]$guestCopyExclusions.Count; message = 'Per-user/system-profile WindowsApps execution-alias directories and Docker runtime socket directories are omitted; installed AppX payloads and persistent Docker profile state remain copied.' }
    $script:ResizeCopyWarnings += $copyPolicyWarning
    [System.Console]::Out.WriteLine(('PRODICLOUD_RESIZE_COPY_WARNING:' + (ConvertTo-Json -InputObject $copyPolicyWarning -Compress)))
}
$copy = Invoke-ResizeRobocopy -Phase 'copy-os-volume' -Arguments ($osCopyArguments + @('/LOG:' + $script:ResizeCopyLogPath))
Write-ResizePhase -Phase 'configure-recovery-and-boot'
$osRecoveryImagePath = Join-Path (("{0}:" -f $osTargetLetter)) 'Recovery\WindowsRE'
$partitionRecoveryImagePath = Join-Path (("{0}:" -f $recoveryTargetLetter)) 'Recovery\WindowsRE'
$recoveryImagePath = ''
if (Test-Path -LiteralPath (Join-Path $osRecoveryImagePath 'winre.wim') -PathType Leaf) {
    $recoveryImagePath = $osRecoveryImagePath
}
elseif (Test-Path -LiteralPath (Join-Path $partitionRecoveryImagePath 'winre.wim') -PathType Leaf) {
    $recoveryImagePath = $partitionRecoveryImagePath
}
else {
    throw 'The copied replacement OS volume and recovery partition do not contain Recovery\WindowsRE\winre.wim.'
}
$recoveryImage = Get-Item -LiteralPath (Join-Path $recoveryImagePath 'winre.wim') -Force -ErrorAction Stop
if ([long]$recoveryImage.Length -le 0) { throw ('The copied Windows RE image is empty at {0}.' -f $recoveryImagePath) }
$reagentc = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\reagentc.exe') -ArgumentList @('/setreimage','/path',$recoveryImagePath,'/target',("{0}:\Windows" -f $osTargetLetter)) -Wait -PassThru -WindowStyle Hidden
if ($null -eq $reagentc -or [int]$reagentc.ExitCode -ne 0) { throw ('REAgentC could not bind the replacement offline Windows image to its copied Windows RE path: {0}.' -f $recoveryImagePath) }
$bcdboot = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\bcdboot.exe') -ArgumentList @(("{0}:\Windows" -f $osTargetLetter),'/s',("{0}:" -f $efiTargetLetter),'/f','UEFI') -Wait -PassThru -WindowStyle Hidden
if ($null -eq $bcdboot -or [int]$bcdboot.ExitCode -ne 0) { throw 'bcdboot could not create UEFI boot files for the replacement OS disk.' }
$recoveryTargetAccessPath = ('{0}:\' -f $recoveryTargetLetter)
Remove-PartitionAccessPath -DiskNumber ([int]$targetDisk.Number) -PartitionNumber ([int]$recoveryTarget.PartitionNumber) -AccessPath $recoveryTargetAccessPath -ErrorAction Stop
$recoveryTargetReadback = Get-Partition -DiskNumber ([int]$targetDisk.Number) -PartitionNumber ([int]$recoveryTarget.PartitionNumber) -ErrorAction Stop
$recoveryTargetDriveLetter = [char]$recoveryTargetReadback.DriveLetter
if ([string]$recoveryTargetReadback.GptType -ne [string]$recoveryGptType -or -not [bool]$recoveryTargetReadback.IsHidden -or $recoveryTargetDriveLetter -ne [char]0) {
    $recoveryTargetDriveLetterText = if ($recoveryTargetDriveLetter -eq [char]0) { '' } else { [string]$recoveryTargetDriveLetter }
    throw ('The replacement Recovery partition did not retain its hidden Windows RE GPT type without a drive letter (GptType={0}; IsHidden={1}; DriveLetter={2}).' -f [string]$recoveryTargetReadback.GptType,[bool]$recoveryTargetReadback.IsHidden,$recoveryTargetDriveLetterText)
}
$replacementMetrics = Get-ResizeDiskMetrics -DiskNumber ([int]$targetDisk.Number)
if ([long]$replacementMetrics.UsedBytes + $minimumFreeBytes -gt [long]$replacementMetrics.DiskSizeBytes -or [long]$replacementMetrics.FreeBytes -lt $minimumFreeBytes) { throw ('Replacement OS disk does not retain the required free-space headroom before cutover: used={0:N2} GiB; free={1:N2} GiB; disk capacity={2:N2} GiB; required={3:N2} GiB.' -f ([long]$replacementMetrics.UsedBytes / 1GB),([long]$replacementMetrics.FreeBytes / 1GB),([long]$replacementMetrics.DiskSizeBytes / 1GB),($minimumFreeBytes / 1GB)) }
Set-Disk -Number ([int]$targetDisk.Number) -IsOffline $true -ErrorAction Stop
Write-ResizePhase -Phase 'verify-replacement-disk'
Write-ResizeResult -Result @{ status = 'ok'; kind = 'os'; fileSystem = 'NTFS'; usedBytes = [long]$sourceMetrics.UsedBytes; sourceUsedBytes = [long]$sourceMetrics.UsedBytes; sourceFreeBytes = [long]$sourceMetrics.FreeBytes; expectedSourceUsedBytes = $expectedSourceUsedBytes; sourceMeasurementDeltaBytes = $sourceMeasurementDeltaBytes; replacementUsedBytes = [long]$replacementMetrics.UsedBytes; replacementFreeBytes = [long]$replacementMetrics.FreeBytes; replacementSizeBytes = [long]$replacementMetrics.DiskSizeBytes; minimumFreeBytes = $minimumFreeBytes; partitions = @($replacementMetrics.Partitions); sourcePartitionLayout = $sourcePartitionLayout; ignoredSourcePartitionNumbers = @($ignoredSourcePartitionNumbers); copyWarnings = @($script:ResizeCopyWarnings) }
