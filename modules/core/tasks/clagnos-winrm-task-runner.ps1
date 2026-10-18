# Windows package task transport over authenticated PowerShell remoting.

function Get-ClagnosPackageTransport {
    param([hashtable]$ConfigMap)

    $transport = [string](Get-ConfigValue -Config $ConfigMap -Key 'PACKAGE_TRANSPORT' -DefaultValue 'ssh')
    if ([string]::IsNullOrWhiteSpace($transport)) { $transport = 'ssh' }
    $transport = $transport.Trim().ToLowerInvariant()
    if ($transport -notin @('ssh','winrm')) {
        throw "PACKAGE_TRANSPORT must be 'ssh' or 'winrm'."
    }
    return $transport
}

function Add-ClagnosPackageTrustedHost {
    param([Parameter(Mandatory = $true)][string]$HostName)

    $resolvedHost = $HostName.Trim().TrimEnd('.')
    if ([string]::IsNullOrWhiteSpace($resolvedHost) -or $resolvedHost -match '[,\s*]') {
        throw 'The WinRM endpoint must be one exact host name or IP address.'
    }
    $trustedHostsPath = 'WSMan:\localhost\Client\TrustedHosts'
    $trustedHostsRegistryPath = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\WSMAN\Client'
    $useWsManProvider = $false
    $existing = ''
    if (Test-Path -LiteralPath $trustedHostsPath) {
        try {
            $existing = [string](Get-Item -LiteralPath $trustedHostsPath -ErrorAction Stop).Value
            $useWsManProvider = $true
        }
        catch { $useWsManProvider = $false }
    }
    if (-not $useWsManProvider) {
        try {
            $registryItem = Get-ItemProperty -LiteralPath $trustedHostsRegistryPath -ErrorAction SilentlyContinue
            if ($null -ne $registryItem) {
                $trustedProperty = $registryItem.PSObject.Properties['trusted_hosts']
                if ($null -eq $trustedProperty) { $trustedProperty = $registryItem.PSObject.Properties['TrustedHosts'] }
                if ($null -ne $trustedProperty) { $existing = [string]$trustedProperty.Value }
            }
        }
        catch { throw ("Could not read the local WinRM TrustedHosts registry value: {0}" -f [string]$_.Exception.Message) }
    }
    $entries = @($existing -split ',' | ForEach-Object { ([string]$_).Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if (@($entries | Where-Object { [string]::Equals([string]$_,$resolvedHost,[System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 0) { return }

    Write-ClagnosActionProgress -Action ("add exact WinRM TrustedHosts entry for '{0}'" -f $resolvedHost)
    $entries += $resolvedHost
    $newValue = @($entries | Select-Object -Unique) -join ','
    try {
        if ($useWsManProvider) { Set-Item -LiteralPath $trustedHostsPath -Value $newValue -Force -ErrorAction Stop }
        else {
            if (-not (Test-Path -LiteralPath $trustedHostsRegistryPath)) { New-Item -Path $trustedHostsRegistryPath -Force -ErrorAction Stop | Out-Null }
            New-ItemProperty -LiteralPath $trustedHostsRegistryPath -Name 'trusted_hosts' -Value $newValue -PropertyType String -Force -ErrorAction Stop | Out-Null
        }
    }
    catch { throw ("Could not add the exact WinRM TrustedHosts entry for '{0}': {1}" -f $resolvedHost,[string]$_.Exception.Message) }
    $verifiedValue = if ($useWsManProvider) { [string](Get-Item -LiteralPath $trustedHostsPath -ErrorAction Stop).Value } else { [string](Get-ItemProperty -LiteralPath $trustedHostsRegistryPath -Name 'trusted_hosts' -ErrorAction Stop).trusted_hosts }
    $verified = @($verifiedValue -split ',' | ForEach-Object { ([string]$_).Trim() })
    if (@($verified | Where-Object { [string]::Equals([string]$_,$resolvedHost,[System.StringComparison]::OrdinalIgnoreCase) }).Count -eq 0) {
        throw ("The exact WinRM TrustedHosts entry for '{0}' did not verify." -f $resolvedHost)
    }
}

function New-ClagnosPackagePowerShellSession {
    param(
        [psobject]$Runtime,
        [string]$HostName,
        [int]$OpenTimeoutSeconds = 30,
        [int]$OperationTimeoutSeconds = 7200
    )

    if ([string]::IsNullOrWhiteSpace([string]$Runtime.Context.VmUser) -or [string]::IsNullOrWhiteSpace([string]$Runtime.Context.VmPass)) {
        throw 'WinRM package execution requires the configured manager username and password.'
    }
    $resolvedHost = [string]$HostName
    if ([string]::IsNullOrWhiteSpace($resolvedHost)) { throw 'WinRM package execution could not resolve a VM FQDN or public IP.' }
    Add-ClagnosPackageTrustedHost -HostName $resolvedHost
    $powerShellPort = Get-ClagnosDefaultPowerShellPortText
    if ($Runtime.Context.PSObject.Properties.Match('PowerShellPort').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$Runtime.Context.PowerShellPort)) {
        $powerShellPort = [string]$Runtime.Context.PowerShellPort
    }
    $sessionRuntime = [pscustomobject]@{
        ConnectionHost = $resolvedHost
        VmPowerShellPort = [string]$powerShellPort
        SelectedUserName = [string]$Runtime.Context.VmUser
        SelectedPassword = [string]$Runtime.Context.VmPass
    }
    return (New-ClagnosPowerShellRemotingSession -Runtime $sessionRuntime -OpenTimeoutSeconds $OpenTimeoutSeconds -OperationTimeoutSeconds $OperationTimeoutSeconds)
}

function Get-ClagnosPackageGuestTelemetry {
    param([object]$Session,[string]$RunId)

    if ($null -eq $Session) { return $null }
    $job = $null
    try {
        $job = Invoke-Command -Session $Session -AsJob -ErrorAction Stop -ScriptBlock {
            param([string]$CurrentRunId)
            $processor = @(Get-CimInstance -ClassName Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'" -ErrorAction Stop | Select-Object -First 1)
            $operatingSystem = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
            $network = @(Get-CimInstance -ClassName Win32_PerfFormattedData_Tcpip_NetworkInterface -ErrorAction Stop)
            $diskCounters = @(Get-CimInstance -ClassName Win32_PerfFormattedData_PerfDisk_PhysicalDisk -Filter "Name='_Total'" -ErrorAction SilentlyContinue | Select-Object -First 1)
            $logicalDisk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction SilentlyContinue
            $statePath = Join-Path (Join-Path $env:ProgramData 'clagnos\state\package-runs') ($CurrentRunId + '.json')
            $hostProcessId = 0
            if (Test-Path -LiteralPath $statePath -PathType Leaf) { try { $hostProcessId = [int](Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json).HostProcessId } catch { } }
            $processRows = @(Get-CimInstance -ClassName Win32_Process -ErrorAction SilentlyContinue)
            $trackedIds = New-Object 'System.Collections.Generic.HashSet[int]'
            if ($hostProcessId -gt 0) { [void]$trackedIds.Add($hostProcessId) }
            $expanded = $true
            while ($expanded) {
                $expanded = $false
                foreach ($process in @($processRows)) {
                    if ($trackedIds.Contains([int]$process.ParentProcessId) -and $trackedIds.Add([int]$process.ProcessId)) { $expanded = $true }
                }
            }
            $processCpu = 0.0
            $processIoBytes = 0.0
            foreach ($process in @($processRows | Where-Object { $trackedIds.Contains([int]$_.ProcessId) })) {
                $processCpu += ([double]$process.UserModeTime + [double]$process.KernelModeTime) / 10000000.0
                $processIoBytes += [double]$process.ReadTransferCount + [double]$process.WriteTransferCount
            }
            $networkBytes = 0.0
            foreach ($adapter in @($network)) { $networkBytes += [double]$adapter.BytesReceivedPersec + [double]$adapter.BytesSentPersec }
            $diskBytesPerSec = 0.0
            if ($diskCounters.Count -gt 0) { $diskBytesPerSec = [double]$diskCounters[0].DiskReadBytesPersec + [double]$diskCounters[0].DiskWriteBytesPersec }
            [pscustomobject]@{
                CpuPercent = if ($processor.Count -gt 0) { [double]$processor[0].PercentProcessorTime } else { -1.0 }
                FreeMemoryMB = [double]$operatingSystem.FreePhysicalMemory / 1024.0
                NetworkBytesPerSecond = $networkBytes
                DiskBytesPerSecond = $diskBytesPerSec
                ProcessCpuSeconds = $processCpu
                ProcessIoBytes = $processIoBytes
                FreeDiskGB = if ($null -ne $logicalDisk -and [double]$logicalDisk.Size -gt 0) { [double]$logicalDisk.FreeSpace / 1GB } else { -1.0 }
            }
        } -ArgumentList ([string]$RunId)
        $null = Wait-Job -Job $job -Timeout 5
        if ($job.State -in @('NotStarted','Running')) { Stop-Job -Job $job -ErrorAction SilentlyContinue | Out-Null; return $null }
        $result = @(Receive-Job -Job $job -ErrorAction Stop | Where-Object { $null -ne $_ -and $_.PSObject.Properties.Match('CpuPercent').Count -gt 0 } | Select-Object -Last 1)
        if ($result.Count -eq 1) { return $result[0] }
        return $null
    }
    catch { return $null }
    finally { if ($null -ne $job) { Remove-Job -Job $job -Force -ErrorAction SilentlyContinue } }
}

function Stop-ClagnosPackageGuestProcessTree {
    param([object]$Session,[string]$RunId)

    if ($null -eq $Session -or [string]::IsNullOrWhiteSpace($RunId)) { return }
    $job = $null
    try {
        $job = Invoke-Command -Session $Session -AsJob -ErrorAction Stop -ScriptBlock {
            param([string]$CurrentRunId)
            $statePath = Join-Path (Join-Path $env:ProgramData 'clagnos\state\package-runs') ($CurrentRunId + '.json')
            if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { return 'no-active-package-state' }
            $state = Get-Content -LiteralPath $statePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            $rootPid = [int]$state.HostProcessId
            if ($rootPid -le 0) { return 'no-package-host-pid' }
            $processRows = @(Get-CimInstance -ClassName Win32_Process -ErrorAction Stop)
            $trackedIds = New-Object 'System.Collections.Generic.HashSet[int]'
            [void]$trackedIds.Add($rootPid)
            $parentById = @{}
            $expanded = $true
            while ($expanded) {
                $expanded = $false
                foreach ($process in @($processRows)) {
                    $processId = [int]$process.ProcessId
                    if ($trackedIds.Contains([int]$process.ParentProcessId) -and $trackedIds.Add($processId)) {
                        $parentById[$processId] = [int]$process.ParentProcessId
                        $expanded = $true
                    }
                }
            }
            foreach ($processId in @($trackedIds | Where-Object { [int]$_ -ne $rootPid })) {
                try { Stop-Process -Id ([int]$processId) -Force -ErrorAction Stop } catch { }
            }
            Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
            ('stopped-{0}-package-child-processes' -f [Math]::Max(0,$trackedIds.Count - 1))
        } -ArgumentList ([string]$RunId)
        $null = Wait-Job -Job $job -Timeout 5
        if ($job.State -in @('NotStarted','Running')) { Stop-Job -Job $job -ErrorAction SilentlyContinue | Out-Null }
        else { Receive-Job -Job $job -ErrorAction SilentlyContinue | Out-Null }
    }
    catch { Write-Warning ("Package child-process cleanup could not be confirmed: {0}" -f [string]$_.Exception.Message) }
    finally { if ($null -ne $job) { Remove-Job -Job $job -Force -ErrorAction SilentlyContinue } }
}

function Sync-ClagnosRemoteGuestLogs {
    param([object]$Session,[string]$VmName)
    if ($null -eq $Session -or [string]::IsNullOrWhiteSpace([string]$VmName)) { return }

    try {
        $remoteLogs = @(Invoke-Command -Session $Session -ErrorAction Stop -ScriptBlock {
            $rootPath = Join-Path $env:ProgramData 'clagnos'
            $logDirectories = @(
                (Join-Path $rootPath 'interactive'),
                (Join-Path $rootPath 'logs')
            )
            $found = New-Object 'System.Collections.Generic.List[object]'
            foreach ($directory in @($logDirectories)) {
                if (-not (Test-Path -LiteralPath $directory -PathType Container)) { continue }
                foreach ($file in @(Get-ChildItem -LiteralPath $directory -Recurse -File -Filter '*.log' -ErrorAction SilentlyContinue)) {
                    $found.Add([pscustomobject]@{ FullName=[string]$file.FullName; Length=[int64]$file.Length; LastWriteUtc=[DateTime]$file.LastWriteTimeUtc; Root=[string]$directory }) | Out-Null
                }
            }
            $windowsTemp = [System.IO.Path]::GetTempPath()
            foreach ($file in @(Get-ChildItem -LiteralPath $windowsTemp -File -Filter 'clagnos-*.log' -ErrorAction SilentlyContinue)) {
                $found.Add([pscustomobject]@{ FullName=[string]$file.FullName; Length=[int64]$file.Length; LastWriteUtc=[DateTime]$file.LastWriteTimeUtc; Root=[string]$windowsTemp }) | Out-Null
            }
            return @($found.ToArray())
        })
        if (@($remoteLogs).Count -eq 0) { return }

        $repoRoot = Get-ClagnosRepoRoot
        $runDirectory = Join-Path (Join-Path (Join-Path $repoRoot '.logs') 'guest') (Join-Path $VmName ((Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss-fff',[System.Globalization.CultureInfo]::InvariantCulture)))
        New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null
        foreach ($entry in @($remoteLogs)) {
            $fullName = [string]$entry.FullName
            $root = ([string]$entry.Root).TrimEnd('\')
            $relative = $fullName.Substring([Math]::Min($root.Length + 1,$fullName.Length)).TrimStart('\','/')
            $destination = Join-Path $runDirectory ($relative -replace '[<>:"|?*]','_')
            $destinationDirectory = Split-Path -Path $destination -Parent
            if (-not (Test-Path -LiteralPath $destinationDirectory -PathType Container)) { New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null }
            Copy-Item -LiteralPath $fullName -Destination $destination -FromSession $Session -Force -ErrorAction Stop
            $remoteHash = [string](Invoke-Command -Session $Session -ErrorAction Stop -ScriptBlock { param([string]$Path) (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash } -ArgumentList $fullName)
            $localHash = [string](Get-FileHash -LiteralPath $destination -Algorithm SHA256 -ErrorAction Stop).Hash
            if (-not [string]::Equals($remoteHash,$localHash,[System.StringComparison]::OrdinalIgnoreCase)) {
                throw ("Clagnos guest log copy did not verify: {0}" -f [System.IO.Path]::GetFileName($fullName))
            }
            $removed = Invoke-Command -Session $Session -ErrorAction Stop -ScriptBlock {
                param([string]$Path,[string]$ExpectedHash)
                if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $true }
                $currentHash = [string](Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash
                if (-not [string]::Equals($currentHash,$ExpectedHash,[System.StringComparison]::OrdinalIgnoreCase)) { return $false }
                Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
                return (-not (Test-Path -LiteralPath $Path -PathType Leaf))
            } -ArgumentList $fullName,$remoteHash
            if (-not [bool]$removed) { Write-Warning ("Collected guest log but left the remote file because it changed during collection: {0}" -f [System.IO.Path]::GetFileName($fullName)) }
            else { Write-Host ("Guest log collected and verified: .logs/guest/{0}/{1}" -f $VmName,$relative.Replace('\','/')) -ForegroundColor DarkGray }
        }
    }
    catch { Write-Warning ("Clagnos guest log collection could not complete; remote source files were retained. {0}" -f [string]$_.Exception.Message) }
}

function Invoke-ClagnosPackageWinRmTaskScript {
    param(
        [object]$Session,
        [string]$TaskName,
        [string]$ScriptText,
        [int]$TimeoutSeconds,
        [object]$ObserverSession = $null,
        [string[]]$RedactionValues = @(),
        [int]$Attempt = 1,
        [DateTime]$DeadlineUtc = [DateTime]::MinValue,
        [switch]$MonitorInactivity
    )

    $safeTimeout = [Math]::Max(30,[Math]::Min(7200,[int]$TimeoutSeconds))
    if ($DeadlineUtc -eq [DateTime]::MinValue) { $DeadlineUtc = [DateTime]::UtcNow.AddSeconds($safeTimeout) }
    $remainingAtStart = [Math]::Floor(($DeadlineUtc - [DateTime]::UtcNow).TotalSeconds)
    if ($remainingAtStart -lt 1) { throw ("WinRM task '{0}' exceeded its bounded operation deadline before start." -f $TaskName) }
    $runId = [Guid]::NewGuid().ToString('N')
    $job = Invoke-Command -Session $Session -AsJob -ErrorAction Stop -ScriptBlock {
        param([string]$Source,[string]$Name,[string]$RunId)
        $ErrorActionPreference = 'Stop'
        $global:LASTEXITCODE = 0
        $statePath = ''
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $outputLines = New-Object 'System.Collections.Generic.List[string]'
        try {
            $stateRoot = Join-Path $env:ProgramData 'clagnos\state\package-runs'
            New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
            $statePath = Join-Path $stateRoot ($RunId + '.json')
            $global:CLAGNOS_PACKAGE_RUN_STATE_PATH = $statePath
            $global:CLAGNOS_PACKAGE_LIFECYCLE_PHASE = 'remote-script'
            [IO.File]::WriteAllText($statePath,(ConvertTo-Json -InputObject @{ RunId = $RunId; Task = $Name; HostProcessId = $PID; Phase = 'script'; StartedAtUtc = [DateTime]::UtcNow.ToString('o') } -Compress),(New-Object System.Text.UTF8Encoding($false)))
            & ([scriptblock]::Create($Source)) *>&1 | ForEach-Object {
                $line = [string]($_ | Out-String).TrimEnd()
                if (-not [string]::IsNullOrWhiteSpace($line)) {
                    $outputLines.Add($line)
                    [pscustomobject]@{ RecordType = 'output'; Text = $line; Name = $Name }
                }
            }
            if ($null -ne $global:LASTEXITCODE -and [int]$global:LASTEXITCODE -ne 0) {
                $result = [pscustomobject]@{ ExitCode = [int]$global:LASTEXITCODE; Output = [string]($outputLines -join "`n"); Name = $Name; DurationSeconds = [double]$watch.Elapsed.TotalSeconds; Phase = 'script' }
                [pscustomobject]@{ RecordType = 'result'; Result = $result }
                return
            }
            $result = [pscustomobject]@{ ExitCode = 0; Output = [string]($outputLines -join "`n"); Name = $Name; DurationSeconds = [double]$watch.Elapsed.TotalSeconds; Phase = 'script' }
            [pscustomobject]@{ RecordType = 'result'; Result = $result }
        }
        catch {
            $message = [string]$_.Exception.Message
            if (-not [string]::IsNullOrWhiteSpace([string]$_.ScriptStackTrace)) { $message += "`n" + [string]$_.ScriptStackTrace }
            $phase = [string]$global:CLAGNOS_PACKAGE_LIFECYCLE_PHASE
            if (Test-Path -LiteralPath $statePath -PathType Leaf) { try { $phase = [string](Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json).Phase } catch { } }
            $message = ("Package lifecycle failed during phase '{0}': {1}" -f $phase,$message)
            $outputLines.Add($message)
            [pscustomobject]@{ RecordType = 'output'; Text = $message; Name = $Name }
            $result = [pscustomobject]@{ ExitCode = 1; Output = [string]($outputLines -join "`n"); Name = $Name; DurationSeconds = [double]$watch.Elapsed.TotalSeconds; Phase = $phase }
            [pscustomobject]@{ RecordType = 'result'; Result = $result }
        }
        finally {
            $watch.Stop()
            if (-not [string]::IsNullOrWhiteSpace([string]$statePath) -and (Test-Path -LiteralPath $statePath -PathType Leaf)) { Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue }
        }
    } -ArgumentList ([string]$ScriptText,[string]$TaskName,[string]$runId)

    $watch = [Diagnostics.Stopwatch]::StartNew()
    $lastOutputCount = 0
    $lastTelemetry = $null
    $lastMovementAt = [DateTime]::UtcNow
    $lastHeartbeatAt = 0
    $lastMovementLabel = 'task start'
    try {
        while ($job.State -in @('NotStarted','Running')) {
            $remaining = [Math]::Floor(($DeadlineUtc - [DateTime]::UtcNow).TotalSeconds)
            if ($remaining -le 0) {
                Stop-ClagnosPackageGuestProcessTree -Session $ObserverSession -RunId $runId
                Stop-Job -Job $job -ErrorAction SilentlyContinue | Out-Null
                throw ("WinRM task '{0}' exceeded its {1}s bounded deadline during phase '{2}' (attempt {3})." -f $TaskName,$safeTimeout,$lastMovementLabel,$Attempt)
            }
            $waitFor = [Math]::Min(15,[int]$remaining)
            $null = Wait-Job -Job $job -Timeout $waitFor
            $events = @(Receive-Job -Job $job -Keep -ErrorAction SilentlyContinue)
            if ($events.Count -gt $lastOutputCount) {
                foreach ($event in @($events | Select-Object -Skip $lastOutputCount)) {
                    $eventRecordType = if ($null -ne $event -and $null -ne $event.PSObject.Properties['RecordType']) { [string]$event.RecordType } else { '' }
                    if ($eventRecordType -eq 'output') {
                        $line = [string]$event.Text
                        foreach ($secret in @($RedactionValues)) { if (-not [string]::IsNullOrWhiteSpace([string]$secret)) { $line = $line.Replace([string]$secret,'[redacted]') } }
                        if (-not [string]::IsNullOrWhiteSpace($line)) {
                            Write-Host $line.TrimEnd()
                            if ($line -match "(?i)package lifecycle phase '(?<phase>[^']+)'") { $lastMovementLabel = [string]$Matches.phase }
                            elseif ($line -match '^Doing: (?<phase>.+)$') { $lastMovementLabel = [string]$Matches.phase }
                        }
                        $lastMovementAt = [DateTime]::UtcNow
                    }
                }
                $lastOutputCount = $events.Count
            }
            if ($null -ne $ObserverSession -and $job.State -in @('NotStarted','Running')) {
                $telemetry = Get-ClagnosPackageGuestTelemetry -Session $ObserverSession -RunId $runId
                if ($null -ne $telemetry) {
                    $movement = $false
                    if ($null -ne $lastTelemetry) {
                        if ([double]$telemetry.ProcessCpuSeconds - [double]$lastTelemetry.ProcessCpuSeconds -ge 0.1) { $movement = $true }
                        if ([double]$telemetry.ProcessIoBytes -gt [double]$lastTelemetry.ProcessIoBytes) { $movement = $true }
                        if ([double]$telemetry.NetworkBytesPerSecond -ge 4096.0) { $movement = $true }
                        if ([double]$telemetry.DiskBytesPerSecond -ge 4096.0) { $movement = $true }
                        if ([Math]::Abs([double]$telemetry.FreeMemoryMB - [double]$lastTelemetry.FreeMemoryMB) -ge 64.0) { $movement = $true }
                        if ([double]$lastTelemetry.FreeDiskGB -ge 0 -and [double]$telemetry.FreeDiskGB -ge 0 -and [Math]::Abs([double]$telemetry.FreeDiskGB - [double]$lastTelemetry.FreeDiskGB) -ge 0.01) { $movement = $true }
                    }
                    if ($movement) { $lastMovementAt = [DateTime]::UtcNow; $lastMovementLabel = 'guest CPU, memory, network, or disk activity' }
                    $lastTelemetry = $telemetry
                }
            }
            if ($job.State -in @('NotStarted','Running')) {
                $elapsed = [int]$watch.Elapsed.TotalSeconds
                if ($elapsed - $lastHeartbeatAt -ge 15) {
                    $telemetryText = if ($null -ne $lastTelemetry) { ' CPU={0:N0}% RAM-free={1:N0}MB net={2:N0}B/s disk-io={3:N0}B/s C-free={4:N1}GB' -f [double]$lastTelemetry.CpuPercent,[double]$lastTelemetry.FreeMemoryMB,[double]$lastTelemetry.NetworkBytesPerSecond,[double]$lastTelemetry.DiskBytesPerSecond,[double]$lastTelemetry.FreeDiskGB } else { ' telemetry=unavailable' }
                    Write-Host ("Doing: WinRM task '{0}' is running ({1}s elapsed; attempt {2}; last progress: {3}).{4}" -f $TaskName,$elapsed,$Attempt,$lastMovementLabel,$telemetryText) -ForegroundColor DarkCyan
                    $lastHeartbeatAt = $elapsed
                }
                $idleSeconds = ([DateTime]::UtcNow - $lastMovementAt).TotalSeconds
                if ($MonitorInactivity -and $idleSeconds -ge 60) {
                    Stop-ClagnosPackageGuestProcessTree -Session $ObserverSession -RunId $runId
                    Stop-Job -Job $job -ErrorAction SilentlyContinue | Out-Null
                    if ($Attempt -lt 2 -and ([DateTime]::UtcNow -lt $DeadlineUtc.AddSeconds(-30))) {
                        Write-Host ("Doing: package operation '{0}' showed no measurable progress for 60s at '{1}'; stopping this attempt and retrying once." -f $TaskName,$lastMovementLabel) -ForegroundColor Yellow
                        $null = Wait-Job -Job $job -Timeout 5
                        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
                        $remainingForRetry = [Math]::Max(30,[int][Math]::Floor(($DeadlineUtc - [DateTime]::UtcNow).TotalSeconds))
                        return (Invoke-ClagnosPackageWinRmTaskScript -Session $Session -TaskName $TaskName -ScriptText $ScriptText -TimeoutSeconds $remainingForRetry -ObserverSession $ObserverSession -RedactionValues $RedactionValues -Attempt ($Attempt + 1) -DeadlineUtc $DeadlineUtc -MonitorInactivity:$MonitorInactivity)
                    }
                    throw ("WinRM package operation '{0}' failed at phase '{1}': no guest CPU, network, disk, memory, or output progress for 60s after {2} attempt(s)." -f $TaskName,$lastMovementLabel,$Attempt)
                }
            }
        }
        $received = @(Receive-Job -Job $job -Keep -ErrorAction Stop)
        if ($job.State -eq 'Failed') {
            $reason = if ($null -ne $job.ChildJobs[0].JobStateInfo.Reason) { [string]$job.ChildJobs[0].JobStateInfo.Reason.Message } else { 'remote invocation failed' }
            throw ("WinRM task '{0}' failed: {1}" -f $TaskName,$reason)
        }
        $result = @($received | Where-Object { $null -ne $_ -and $null -ne $_.PSObject.Properties['RecordType'] -and [string]$_.RecordType -eq 'result' -and $null -ne $_.PSObject.Properties['Result'] } | ForEach-Object { $_.Result } | Select-Object -Last 1)
        if ($result.Count -ne 1) { throw ("WinRM task '{0}' returned no structured result." -f $TaskName) }
        return $result[0]
    }
    finally {
        if ($watch.IsRunning) { $watch.Stop() }
        if ($null -ne $job) { Remove-Job -Job $job -Force -ErrorAction SilentlyContinue }
    }
}

function Invoke-ClagnosWinRmTaskBlocks {
    param(
        [ValidateSet('windows')][string]$Platform,
        [string]$HostName,
        [psobject]$Runtime,
        [psobject]$Target,
        [object[]]$TaskBlocks,
        [ValidateSet('continue','strict')][string]$TaskOutcomeMode = 'strict',
        [ValidateSet('task-run')][string]$PerfTaskCategory = 'task-run'
    )

    if (-not $TaskBlocks -or @($TaskBlocks).Count -eq 0) { throw 'WinRM task block list is empty.' }
    $packageBudgets = @($TaskBlocks | Where-Object { [string]$_.TaskType -eq 'package' } | ForEach-Object { Get-ClagnosTaskTimeoutSeconds -TaskBlock $_ -DefaultTimeoutSeconds ([int]$Runtime.SshTaskTimeoutSeconds) })
    $hasPackageOperation = $packageBudgets.Count -gt 0
    $packageDeadlineUtc = [DateTime]::MaxValue
    $packageConnectBudget = 7200
    if ($packageBudgets.Count -gt 0) {
        $packageConnectBudget = [int](($packageBudgets | Measure-Object -Maximum).Maximum)
        $packageDeadlineUtc = [DateTime]::UtcNow.AddSeconds($packageConnectBudget)
    }
    $session = New-ClagnosPackagePowerShellSession -Runtime $Runtime -HostName $HostName -OpenTimeoutSeconds ([Math]::Min(30,$packageConnectBudget)) -OperationTimeoutSeconds $packageConnectBudget
    $observerSession = $null
    $outputs = @()
    $taskOutputs = @()
    $successes = @()
    $warnings = @()
    $failures = @()
    $rebootRequestedTasks = @()
    try {
        foreach ($task in @($TaskBlocks)) {
            $taskName = [string]$task.Name
            Write-ClagnosActionProgress -Action ("run Windows guest task '{0}' over WinRM" -f $taskName)
            if ([string]$task.TaskType -eq 'package' -and $null -eq $observerSession) {
                try {
                    $observerSession = New-ClagnosPackagePowerShellSession -Runtime $Runtime -HostName $HostName -OpenTimeoutSeconds 10 -OperationTimeoutSeconds 15
                    Write-ClagnosActionProgress -Action ("start guest CPU, RAM, network, disk, and output observation for package '{0}'" -f $taskName)
                }
                catch { Write-Warning ("Package telemetry session could not be opened; task output and its hard deadline remain active. {0}" -f [string]$_.Exception.Message) }
            }
            foreach ($asset in @(ConvertTo-ObjectArrayCompat -InputObject $task.AssetCopies)) {
                if ($hasPackageOperation -and [DateTime]::UtcNow -ge $packageDeadlineUtc) { throw ("Package operation '{0}' exceeded its bounded deadline while staging guest assets." -f $taskName) }
                $localPath = [string]$asset.LocalPath
                $remotePath = [string]$asset.RemotePath
                if ([string]::IsNullOrWhiteSpace($localPath) -or [string]::IsNullOrWhiteSpace($remotePath)) { continue }
                if (-not (Test-Path -LiteralPath $localPath -PathType Leaf)) { throw ("Task asset was not found: {0}" -f $localPath) }
                $remoteDirectory = [System.IO.Path]::GetDirectoryName($remotePath.Replace('/','\'))
                if (-not [string]::IsNullOrWhiteSpace($remoteDirectory)) {
                    Invoke-Command -Session $session -ScriptBlock { param([string]$Path) New-Item -ItemType Directory -Path $Path -Force | Out-Null } -ArgumentList $remoteDirectory -ErrorAction Stop | Out-Null
                }
                Write-ClagnosActionProgress -Action ("copy guest task asset '{0}' over WinRM" -f [System.IO.Path]::GetFileName($localPath))
                Copy-Item -LiteralPath $localPath -Destination $remotePath -ToSession $session -Force -ErrorAction Stop
            }
            $taskTimeout = Get-ClagnosTaskTimeoutSeconds -TaskBlock $task -DefaultTimeoutSeconds ([int]$Runtime.SshTaskTimeoutSeconds)
            $taskDeadlineUtc = if ($hasPackageOperation) { $packageDeadlineUtc } else { [DateTime]::UtcNow.AddSeconds($taskTimeout) }
            $remainingTaskSeconds = [int][Math]::Floor(($taskDeadlineUtc - [DateTime]::UtcNow).TotalSeconds)
            if ($remainingTaskSeconds -le 0) { throw ("Package operation '{0}' exceeded its bounded deadline before guest execution." -f $taskName) }
            $taskResult = Invoke-ClagnosPackageWinRmTaskScript -Session $session -TaskName $taskName -ScriptText ([string]$task.Script) -TimeoutSeconds $remainingTaskSeconds -ObserverSession $observerSession -RedactionValues @([string]$Runtime.Context.VmPass,[string]$Runtime.Context.VmAssistantPass) -DeadlineUtc $taskDeadlineUtc -MonitorInactivity:([string]$task.TaskType -eq 'package')
            $taskOutput = [string]$taskResult.Output
            foreach ($secret in @([string]$Runtime.Context.VmPass,[string]$Runtime.Context.VmAssistantPass)) {
                if (-not [string]::IsNullOrWhiteSpace($secret)) { $taskOutput = $taskOutput.Replace($secret,'[redacted]') }
            }
            $taskOutputs += [pscustomobject]@{ Name = $taskName; ExitCode = [int]$taskResult.ExitCode; Output = $taskOutput }
            foreach ($outputLine in @($taskOutput -split "`r?`n")) {
                if ([string]$outputLine -match '^TASK_REBOOT_REQUIRED:(?<reason>.+)$') { $rebootRequestedTasks += $taskName; break }
            }
            if ([int]$taskResult.ExitCode -ne 0) {
                $failures += $taskName
                if ($TaskOutcomeMode -eq 'strict') { throw ("WinRM package task '{0}' failed (exit {1}). {2}" -f $taskName,[int]$taskResult.ExitCode,$taskOutput.Trim()) }
                $warnings += $taskName
                continue
            }
            $successes += $taskName
            if ($task.PSObject.Properties.Match('AppStateSpec').Count -gt 0 -and $null -ne $task.AppStateSpec) {
                $remainingPostProcessSeconds = [int][Math]::Floor(($taskDeadlineUtc - [DateTime]::UtcNow).TotalSeconds)
                if ($remainingPostProcessSeconds -lt 30) { throw ("Package operation '{0}' has less than 30 seconds remaining for required app-state verification." -f $taskName) }
                $appStateResult = Invoke-ClagnosTaskAppStatePostProcess `
                    -Platform 'windows' `
                    -Transport 'winrm' `
                    -RepoRoot (Get-ClagnosRepoRoot) `
                    -TaskBlock $task `
                    -Session $session `
                    -ManagerUser ([string]$Runtime.Context.VmUser) `
                    -AssistantUser ([string]$Runtime.Context.VmAssistantUser) `
                    -TimeoutSeconds $remainingPostProcessSeconds
                if ($null -ne $appStateResult -and [bool]$appStateResult.Warning) { $warnings += ($taskName + ' app-state') }
            }
        }
    }
    finally {
        if ($null -ne $session) { Sync-ClagnosRemoteGuestLogs -Session $session -VmName ([string]$Runtime.Context.VmName) }
        if ($null -ne $observerSession) { Remove-PSSession -Session $observerSession -ErrorAction SilentlyContinue }
        if ($null -ne $session) { Remove-PSSession -Session $session -ErrorAction SilentlyContinue }
    }

    if ($TaskOutcomeMode -eq 'strict' -and @($warnings).Count -gt 0) { throw ("WinRM task outcome was incomplete: {0}" -f (@($warnings) -join ', ')) }
    return [pscustomobject]@{
        SuccessCount = @($successes).Count
        SuccessTasks = @($successes)
        TaskOutputs = @($taskOutputs)
        FailedCount = @($failures).Count
        FailedTasks = @($failures)
        WarningCount = @($warnings).Count
        WarningTasks = @($warnings)
        SignalWarningCount = 0
        SignalWarningTasks = @()
        ErrorCount = @($failures).Count
        RebootCount = 0
        FinalRestartCount = 0
        RebootRequired = (@($rebootRequestedTasks | Select-Object -Unique).Count -gt 0)
        RebootRequestedTasks = @($rebootRequestedTasks | Select-Object -Unique)
    }
}
