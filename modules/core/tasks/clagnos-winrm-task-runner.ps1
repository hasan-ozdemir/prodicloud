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
        [string]$HostName
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
    return (New-ClagnosPowerShellRemotingSession -Runtime $sessionRuntime)
}

function Invoke-ClagnosPackageWinRmTaskScript {
    param(
        [object]$Session,
        [string]$TaskName,
        [string]$ScriptText,
        [int]$TimeoutSeconds
    )

    $safeTimeout = [Math]::Max(30,[Math]::Min(7200,[int]$TimeoutSeconds))
    $job = Invoke-Command -Session $Session -AsJob -ErrorAction Stop -ScriptBlock {
        param([string]$Source,[string]$Name)
        $ErrorActionPreference = 'Stop'
        $global:LASTEXITCODE = 0
        $watch = [Diagnostics.Stopwatch]::StartNew()
        try {
            $output = & ([scriptblock]::Create($Source)) *>&1 | Out-String
            if ($null -ne $global:LASTEXITCODE -and [int]$global:LASTEXITCODE -ne 0) {
                return [pscustomobject]@{ ExitCode = [int]$global:LASTEXITCODE; Output = [string]$output; Name = $Name }
            }
            return [pscustomobject]@{ ExitCode = 0; Output = [string]$output; Name = $Name }
        }
        catch {
            $message = [string]$_.Exception.Message
            if (-not [string]::IsNullOrWhiteSpace([string]$_.ScriptStackTrace)) { $message += "`n" + [string]$_.ScriptStackTrace }
            return [pscustomobject]@{ ExitCode = 1; Output = ($message + "`n" + [string]$output); Name = $Name }
        }
        finally { $watch.Stop() }
    } -ArgumentList ([string]$ScriptText,[string]$TaskName)

    $watch = [Diagnostics.Stopwatch]::StartNew()
    try {
        while ($job.State -in @('NotStarted','Running')) {
            if ($watch.Elapsed.TotalSeconds -ge $safeTimeout) {
                Stop-Job -Job $job -ErrorAction SilentlyContinue | Out-Null
                throw ("WinRM task '{0}' exceeded its {1}s timeout." -f $TaskName,$safeTimeout)
            }
            $remaining = [Math]::Max(1,[int][Math]::Ceiling($safeTimeout - $watch.Elapsed.TotalSeconds))
            $waitFor = [Math]::Min(30,$remaining)
            $null = Wait-Job -Job $job -Timeout $waitFor
            if ($job.State -in @('NotStarted','Running')) {
                Write-Host ("Doing: WinRM task '{0}' is still running ({1}s elapsed)" -f $TaskName,[int]$watch.Elapsed.TotalSeconds) -ForegroundColor DarkCyan
            }
        }
        $received = @(Receive-Job -Job $job -ErrorAction Stop)
        if ($job.State -eq 'Failed') {
            $reason = if ($null -ne $job.ChildJobs[0].JobStateInfo.Reason) { [string]$job.ChildJobs[0].JobStateInfo.Reason.Message } else { 'remote invocation failed' }
            throw ("WinRM task '{0}' failed: {1}" -f $TaskName,$reason)
        }
        $result = @($received | Where-Object { $null -ne $_ -and $_.PSObject.Properties.Match('ExitCode').Count -gt 0 } | Select-Object -Last 1)
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
    $session = New-ClagnosPackagePowerShellSession -Runtime $Runtime -HostName $HostName
    $outputs = @()
    $successes = @()
    $warnings = @()
    $failures = @()
    try {
        foreach ($task in @($TaskBlocks)) {
            $taskName = [string]$task.Name
            Write-ClagnosActionProgress -Action ("run Windows guest task '{0}' over WinRM" -f $taskName)
            foreach ($asset in @(ConvertTo-ObjectArrayCompat -InputObject $task.AssetCopies)) {
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
            $taskResult = Invoke-ClagnosPackageWinRmTaskScript -Session $session -TaskName $taskName -ScriptText ([string]$task.Script) -TimeoutSeconds $taskTimeout
            $taskOutput = [string]$taskResult.Output
            foreach ($secret in @([string]$Runtime.Context.VmPass,[string]$Runtime.Context.VmAssistantPass)) {
                if (-not [string]::IsNullOrWhiteSpace($secret)) { $taskOutput = $taskOutput.Replace($secret,'[redacted]') }
            }
            if (-not [string]::IsNullOrWhiteSpace($taskOutput)) { Write-Host $taskOutput.TrimEnd() }
            $taskOutputs += [pscustomobject]@{ Name = $taskName; ExitCode = [int]$taskResult.ExitCode; Output = $taskOutput }
            if ([int]$taskResult.ExitCode -ne 0) {
                $failures += $taskName
                if ($TaskOutcomeMode -eq 'strict') { throw ("WinRM package task '{0}' failed (exit {1}). {2}" -f $taskName,[int]$taskResult.ExitCode,$taskOutput.Trim()) }
                $warnings += $taskName
                continue
            }
            $successes += $taskName
            if ($task.PSObject.Properties.Match('AppStateSpec').Count -gt 0 -and $null -ne $task.AppStateSpec) {
                $appStateResult = Invoke-ClagnosTaskAppStatePostProcess `
                    -Platform 'windows' `
                    -Transport 'winrm' `
                    -RepoRoot (Get-ClagnosRepoRoot) `
                    -TaskBlock $task `
                    -Session $session `
                    -ManagerUser ([string]$Runtime.Context.VmUser) `
                    -AssistantUser ([string]$Runtime.Context.VmAssistantUser) `
                    -TimeoutSeconds $taskTimeout
                if ($null -ne $appStateResult -and [bool]$appStateResult.Warning) { $warnings += ($taskName + ' app-state') }
            }
        }
    }
    finally { if ($null -ne $session) { Remove-PSSession -Session $session -ErrorAction SilentlyContinue } }

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
        RebootRequired = $false
        RebootRequestedTasks = @()
    }
}
