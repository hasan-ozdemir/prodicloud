# Shared SSH task stage runner.

function Get-ProdicloudTaskOutputWarningSignalCount {
    param(
        [AllowNull()]
        [string]$MessageText
    )

    if ([string]::IsNullOrWhiteSpace([string]$MessageText)) {
        return 0
    }

    $count = 0
    foreach ($lineRaw in @([string]$MessageText -split "`r?`n")) {
        $line = [string]$lineRaw
        if ($line -match '^(?i)\s*WARNING:\s+' -and -not (Test-ProdicloudTaskOutputNoiseLine -Text ([string]$line))) {
            $count++
        }
    }

    return [int]$count
}

# Handles Invoke-ProdicloudSshTaskBlocks.
function Invoke-ProdicloudSshTaskBlocks {
    param(
        [ValidateSet('windows','linux')]
        [string]$Platform,
        [string]$RepoRoot,
        [string]$SshHost,
        [string]$SshUser,
        [string]$SshPassword,
        [string]$SshPort,
        [string]$AssistantUser = '',
        [string]$ResourceGroup = '',
        [string]$VmName = '',
        [object[]]$TaskBlocks,
        [ValidateSet('continue','strict')]
        [string]$TaskOutcomeMode = 'continue',
        [ValidateSet('vm-update-task','task-run')]
        [string]$PerfTaskCategory = 'vm-update-task',
        [int]$SshMaxRetries = 3,
        [int]$SshTaskTimeoutSeconds = 180,
        [int]$SshConnectTimeoutSeconds = 30,
        [string]$ConfiguredPySshClientPath = '',
        [switch]$EnableFinalVmRestart
    )

    if (-not $TaskBlocks -or @($TaskBlocks).Count -eq 0) {
        throw 'SSH task block list is empty.'
    }

    $stageWatch = [System.Diagnostics.Stopwatch]::StartNew()

    $SshMaxRetries = Resolve-ProdicloudSshRetryCount -RetryText ([string]$SshMaxRetries) -DefaultValue 3
    if ($SshTaskTimeoutSeconds -lt 30) { $SshTaskTimeoutSeconds = 30 }
    if ($SshTaskTimeoutSeconds -gt 7200) { $SshTaskTimeoutSeconds = 7200 }
    if ($SshConnectTimeoutSeconds -lt 5) { $SshConnectTimeoutSeconds = 5 }
    if ($SshConnectTimeoutSeconds -gt 300) { $SshConnectTimeoutSeconds = 300 }
    $pySsh = Ensure-ProdicloudPySshTools -RepoRoot $RepoRoot -ConfiguredPySshClientPath $ConfiguredPySshClientPath

    $bootstrap = Initialize-ProdicloudSshHostKey -PySshPythonPath ([string]$pySsh.PythonPath) -PySshClientPath ([string]$pySsh.ClientPath) -HostName $SshHost -UserName $SshUser -Password $SshPassword -Port $SshPort -ConnectTimeoutSeconds $SshConnectTimeoutSeconds
    if (-not [string]::IsNullOrWhiteSpace([string]$bootstrap.Output)) {
        Write-Host ([string]$bootstrap.Output)
    }
    Write-Host ("Resolved SSH host key for batch transport: {0}" -f [string]$bootstrap.HostKey)

    $shell = if ($Platform -eq 'windows') { 'powershell' } else { 'bash' }
    $session = $null
    $persistentSessionEnabled = ($Platform -eq 'linux')
    $usedOneShotTransport = ($Platform -eq 'windows')
    $totalSuccess = 0
    $totalWarnings = 0
    $signalWarningCount = 0
    $totalErrors = 0
    $rebootCount = 0
    $finalRestartCount = 0
    $successfulTasks = @()
    $taskOutputs = @()
    $failedTasks = @()
    $warningTasks = @()
    $rebootRequestedTasks = @()
    $signalWarningTasks = @()

    function Restore-ProdicloudTaskSession {
        param(
            [psobject]$ExistingSession,
            [string]$Reason
        )

        if ($null -ne $ExistingSession) {
            Stop-ProdicloudPersistentSshSession -Session $ExistingSession
        }

        Write-Warning ("Attempting persistent SSH session recovery: {0}" -f [string]$Reason)
        if (-not [string]::IsNullOrWhiteSpace([string]$ResourceGroup) -and -not [string]::IsNullOrWhiteSpace([string]$VmName)) {
            $repairResult = Wait-ProdicloudProvisioningReadyOrRepair -ResourceGroup $ResourceGroup -VmName $VmName
            if (-not [bool]$repairResult.Ready) {
                throw ("VM '{0}' in resource group '{1}' did not recover from provisioning issues while restoring the SSH session. {2}" -f [string]$VmName, [string]$ResourceGroup, (Format-ProdicloudVmLifecycleSummaryText -Snapshot $repairResult.Snapshot))
            }
        }

        $sshReachable = Wait-ProdicloudTcpPortReachable `
            -HostName $SshHost `
            -Port ([int]$SshPort) `
            -MaxAttempts 18 `
            -DelaySeconds 5 `
            -TimeoutSeconds 5 `
            -Label 'ssh'
        if (-not [bool]$sshReachable) {
            throw ("SSH port {0} on '{1}' did not recover in time while restoring the persistent session." -f [string]$SshPort, [string]$SshHost)
        }

        return (Start-ProdicloudPersistentSshSession `
            -PySshPythonPath ([string]$pySsh.PythonPath) `
            -PySshClientPath ([string]$pySsh.ClientPath) `
            -HostName $SshHost `
            -UserName $SshUser `
            -Password $SshPassword `
            -Port $SshPort `
            -Shell $shell `
            -ConnectTimeoutSeconds $SshConnectTimeoutSeconds `
            -DefaultTaskTimeoutSeconds $SshTaskTimeoutSeconds)
    }

    function Invoke-ProdicloudOneShotTaskTransportRecovery {
        param(
            [string]$Reason
        )

        Write-Warning ("Attempting one-shot SSH recovery: {0}" -f [string]$Reason)
        if (-not [string]::IsNullOrWhiteSpace([string]$ResourceGroup) -and -not [string]::IsNullOrWhiteSpace([string]$VmName)) {
            $repairResult = Wait-ProdicloudProvisioningReadyOrRepair -ResourceGroup $ResourceGroup -VmName $VmName
            if (-not [bool]$repairResult.Ready) {
                throw ("VM '{0}' in resource group '{1}' did not recover from provisioning issues while restoring one-shot SSH execution. {2}" -f [string]$VmName, [string]$ResourceGroup, (Format-ProdicloudVmLifecycleSummaryText -Snapshot $repairResult.Snapshot))
            }
        }

        $sshReachable = Wait-ProdicloudTcpPortReachable `
            -HostName $SshHost `
            -Port ([int]$SshPort) `
            -MaxAttempts 18 `
            -DelaySeconds 5 `
            -TimeoutSeconds 5 `
            -Label 'ssh'
        if (-not [bool]$sshReachable) {
            throw ("SSH port {0} on '{1}' did not recover in time while restoring one-shot SSH execution." -f [string]$SshPort, [string]$SshHost)
        }

        $bootstrap = Initialize-ProdicloudSshHostKey `
            -PySshPythonPath ([string]$pySsh.PythonPath) `
            -PySshClientPath ([string]$pySsh.ClientPath) `
            -HostName $SshHost `
            -UserName $SshUser `
            -Password $SshPassword `
            -Port $SshPort `
            -ConnectTimeoutSeconds $SshConnectTimeoutSeconds
        if (-not [string]::IsNullOrWhiteSpace([string]$bootstrap.Output)) {
            Write-Host ([string]$bootstrap.Output)
        }
    }

    try {
        if ($persistentSessionEnabled) {
            Write-Host 'VM update stage mode: tasks run one-by-one over a persistent SSH session.'
        }
        else {
            Write-Host 'VM update stage mode: tasks run one-by-one over one-shot SSH execution.'
        }
        Write-Host ("Task outcome policy: {0}" -f $TaskOutcomeMode)
        Write-Host ("SSH timeouts: task={0}s, connect={1}s" -f $SshTaskTimeoutSeconds, $SshConnectTimeoutSeconds) -ForegroundColor DarkCyan
        if (-not [string]::IsNullOrWhiteSpace([string]$ResourceGroup) -and -not [string]::IsNullOrWhiteSpace([string]$VmName)) {
            $provisioningRepairResult = Wait-ProdicloudProvisioningReadyOrRepair -ResourceGroup $ResourceGroup -VmName $VmName
            if (-not [bool]$provisioningRepairResult.Ready) {
                throw ("VM '{0}' in resource group '{1}' is not ready for SSH task execution. {2}" -f [string]$VmName, [string]$ResourceGroup, (Format-ProdicloudVmLifecycleSummaryText -Snapshot $provisioningRepairResult.Snapshot))
            }
        }

        if ($persistentSessionEnabled) {
            try {
                $session = Start-ProdicloudPersistentSshSession -PySshPythonPath ([string]$pySsh.PythonPath) -PySshClientPath ([string]$pySsh.ClientPath) -HostName $SshHost -UserName $SshUser -Password $SshPassword -Port $SshPort -Shell $shell -ConnectTimeoutSeconds $SshConnectTimeoutSeconds -DefaultTaskTimeoutSeconds $SshTaskTimeoutSeconds
            }
            catch {
                $persistentSessionEnabled = $false
                $usedOneShotTransport = $true
                $session = $null
                Write-Warning ("Persistent SSH session bootstrap failed. Switching to one-shot SSH task execution: {0}" -f $_.Exception.Message)
            }
        }

        foreach ($task in @($TaskBlocks)) {
            $taskName = [string]$task.Name
            $taskScript = [string]$task.Script
            $taskTimeoutSeconds = Get-ProdicloudTaskTimeoutSeconds -TaskBlock $task -DefaultTimeoutSeconds $SshTaskTimeoutSeconds
            $taskWatch = [System.Diagnostics.Stopwatch]::StartNew()
            $taskResult = $null
            $taskInvocationError = $null

            Write-ProdicloudActionProgress -Action ("run guest task '{0}' (max {1}s)" -f $taskName, $taskTimeoutSeconds)

            if ($persistentSessionEnabled -and -not (Test-ProdicloudPersistentSshSessionUsable -Session $session)) {
                try {
                    $session = Restore-ProdicloudTaskSession -ExistingSession $session -Reason ("pre-task bootstrap for '{0}'" -f $taskName)
                }
                catch {
                    $persistentSessionEnabled = $false
                    $usedOneShotTransport = $true
                    $session = $null
                    Write-Warning ("Persistent SSH session recovery failed. Switching to one-shot SSH task execution: {0}" -f $_.Exception.Message)
                }
            }

            $assetCopies = @()
            if ($task.PSObject.Properties.Match('AssetCopies').Count -gt 0 -and $null -ne $task.AssetCopies) {
                $assetCopies = @(ConvertTo-ObjectArrayCompat -InputObject $task.AssetCopies)
            }
            for ($attempt = 1; $attempt -le $SshMaxRetries; $attempt++) {
                $taskInvocationError = $null
                try {
                    foreach ($asset in @($assetCopies)) {
                        $assetLocalPath = [string]$asset.LocalPath
                        $assetRemotePath = [string]$asset.RemotePath
                        if ([string]::IsNullOrWhiteSpace([string]$assetLocalPath) -or [string]::IsNullOrWhiteSpace([string]$assetRemotePath)) {
                            continue
                        }

                        Write-ProdicloudActionProgress -Action ("copy guest task asset '{0}' to VM" -f [System.IO.Path]::GetFileName($assetLocalPath))
                        Copy-ProdicloudAssetToVm `
                            -PySshPythonPath ([string]$pySsh.PythonPath) `
                            -PySshClientPath ([string]$pySsh.ClientPath) `
                            -HostName $SshHost `
                            -UserName $SshUser `
                            -Password $SshPassword `
                            -Port $SshPort `
                            -LocalPath $assetLocalPath `
                            -RemotePath $assetRemotePath `
                            -ConnectTimeoutSeconds $SshConnectTimeoutSeconds | Out-Null
                        Write-Host ("Task asset copy completed: {0}" -f $assetRemotePath)
                    }

                    $taskResult = Invoke-ProdicloudSshTaskScript `
                        -Session $(if ($persistentSessionEnabled) { $session } else { $null }) `
                        -PySshPythonPath ([string]$pySsh.PythonPath) `
                        -PySshClientPath ([string]$pySsh.ClientPath) `
                        -HostName $SshHost `
                        -UserName $SshUser `
                        -Password $SshPassword `
                        -Port $SshPort `
                        -Shell $shell `
                        -TaskName $taskName `
                        -TaskScript $taskScript `
                        -TimeoutSeconds $taskTimeoutSeconds
                    break
                }
                catch {
                    $taskInvocationError = $_
                    if ($attempt -lt $SshMaxRetries) {
                        if ($persistentSessionEnabled) {
                            Write-Warning ("Persistent SSH task execution failed for '{0}' (attempt {1}/{2}): {3}" -f $taskName, $attempt, $SshMaxRetries, $_.Exception.Message)
                            try {
                                $session = Restore-ProdicloudTaskSession -ExistingSession $session -Reason ("retry {0}/{1} for task '{2}'" -f $attempt, $SshMaxRetries, $taskName)
                            }
                            catch {
                                $persistentSessionEnabled = $false
                                $usedOneShotTransport = $true
                                $session = $null
                                Write-Warning ("Persistent SSH session recovery failed. Switching to one-shot SSH task execution: {0}" -f $_.Exception.Message)
                            }
                        }
                        else {
                            Write-Warning ("One-shot SSH task preparation or execution failed for '{0}' (attempt {1}/{2}): {3}" -f $taskName, $attempt, $SshMaxRetries, $_.Exception.Message)
                            try {
                                Invoke-ProdicloudOneShotTaskTransportRecovery -Reason ("retry {0}/{1} for task '{2}'" -f $attempt, $SshMaxRetries, $taskName)
                            }
                            catch {
                                Write-Warning ("One-shot SSH recovery probe failed before retrying '{0}': {1}" -f $taskName, $_.Exception.Message)
                            }
                        }
                    }
                }
            }

            if ($null -eq $taskInvocationError -and $persistentSessionEnabled -and $null -ne $taskResult) {
                $taskOutputText = ''
                if ($taskResult.PSObject.Properties.Match('Output').Count -gt 0) {
                    $taskOutputText = [string]$taskResult.Output
                }

                if (([int]$taskResult.ExitCode -ne 0) -and (Test-ProdicloudSshTransportRecoverySignal -Text $taskOutputText)) {
                    Write-Warning ("Persistent SSH shell reported a known bootstrap failure for '{0}'. Retrying once via one-shot SSH execution." -f $taskName)
                    if ($null -ne $session) {
                        Stop-ProdicloudPersistentSshSession -Session $session
                    }
                    $persistentSessionEnabled = $false
                    $usedOneShotTransport = $true
                    $session = $null
                    try {
                        $taskResult = Invoke-ProdicloudSshTaskScript `
                            -Session $null `
                            -PySshPythonPath ([string]$pySsh.PythonPath) `
                            -PySshClientPath ([string]$pySsh.ClientPath) `
                            -HostName $SshHost `
                            -UserName $SshUser `
                            -Password $SshPassword `
                            -Port $SshPort `
                            -Shell $shell `
                            -TaskName $taskName `
                            -TaskScript $taskScript `
                            -TimeoutSeconds $taskTimeoutSeconds
                    }
                    catch {
                        $taskInvocationError = $_
                    }
                }
            }

            if ($taskWatch.IsRunning) { $taskWatch.Stop() }
            $taskElapsedSeconds = $taskWatch.Elapsed.TotalSeconds
            $capturedOutput = ''
            $capturedExitCode = -1
            if ($null -ne $taskResult) {
                if ($taskResult.PSObject.Properties.Match('Output').Count -gt 0) { $capturedOutput = [string]$taskResult.Output }
                if ($taskResult.PSObject.Properties.Match('ExitCode').Count -gt 0) { $capturedExitCode = [int]$taskResult.ExitCode }
            }
            $taskOutputs += [pscustomobject]@{
                Name = [string]$taskName
                ExitCode = [int]$capturedExitCode
                Output = [string]$capturedOutput
            }

            if ($null -ne $taskInvocationError) {
                if ($TaskOutcomeMode -eq 'continue') {
                    $totalWarnings++
                    $warningTasks += $taskName
                    $transportModeLabel = if ($persistentSessionEnabled) { 'persistent session' } else { 'one-shot ssh' }
                    Write-Warning ("Task warning: {0} failed in {1} => {2}" -f $taskName, $transportModeLabel, $taskInvocationError.Exception.Message)
                    Write-Host ("Task completed: {0} ({1:N1}s) - warning" -f $taskName, $taskWatch.Elapsed.TotalSeconds)
                    if ($persistentSessionEnabled) {
                        try {
                            $session = Restore-ProdicloudTaskSession -ExistingSession $session -Reason ("post-warning recovery after task '{0}'" -f $taskName)
                        }
                        catch {
                            $persistentSessionEnabled = $false
                            $usedOneShotTransport = $true
                            $session = $null
                            Write-Warning ("Persistent SSH session recovery is still unavailable after task '{0}'. Switching to one-shot SSH execution: {1}" -f $taskName, $_.Exception.Message)
                        }
                    }
                    continue
                }

                $failedTasks += $taskName
                $totalErrors++
                Write-Host ("Task failed: {0}" -f $taskName) -ForegroundColor Red
                $transportModeLabel = if ($persistentSessionEnabled) { 'persistent session' } else { 'one-shot ssh' }
                throw ("VM update task failed in {0}: {1} => {2}" -f $transportModeLabel, $taskName, $taskInvocationError.Exception.Message)
            }

            if ([int]$taskResult.ExitCode -eq 0) {
                $totalSuccess++
                $successfulTasks += $taskName
                Write-Host ("Task completed: {0} ({1:N1}s) - success" -f $taskName, $taskElapsedSeconds)

                $taskSignalWarnings = 0
                if ($taskResult.PSObject.Properties.Match('Output').Count -gt 0) {
                    $taskSignalWarnings = Get-ProdicloudTaskOutputWarningSignalCount -MessageText ([string]$taskResult.Output)
                }
                if ($taskSignalWarnings -gt 0) {
                    $signalWarningCount += [int]$taskSignalWarnings
                    $signalWarningTasks += ("{0} => task-output:{1}" -f [string]$taskName, [int]$taskSignalWarnings)
                }

                $appStateResult = Invoke-ProdicloudTaskAppStatePostProcess `
                    -Platform $Platform `
                    -RepoRoot $RepoRoot `
                    -TaskBlock $task `
                    -Session $session `
                    -PySshPythonPath ([string]$pySsh.PythonPath) `
                    -PySshClientPath ([string]$pySsh.ClientPath) `
                    -HostName $SshHost `
                    -UserName $SshUser `
                    -Password $SshPassword `
                    -Port $SshPort `
                    -ConnectTimeoutSeconds $SshConnectTimeoutSeconds `
                    -TimeoutSeconds $taskTimeoutSeconds `
                    -ManagerUser ([string]$SshUser) `
                    -AssistantUser ([string]$AssistantUser)
                if ($null -ne $appStateResult -and $appStateResult.PSObject.Properties.Match('Warning').Count -gt 0 -and [bool]$appStateResult.Warning) {
                    $signalWarningCount++
                    $signalWarningTasks += ("{0} => app-state" -f [string]$taskName)
                }
            }
            else {
                $taskOutputWasRelayedLive = ($taskResult.PSObject.Properties.Match('OutputRelayedLive').Count -gt 0 -and [bool]$taskResult.OutputRelayedLive)
                if (-not $taskOutputWasRelayedLive -and $taskResult.PSObject.Properties.Match('Output').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$taskResult.Output)) {
                    Write-Host ([string]$taskResult.Output)
                }
                if ($TaskOutcomeMode -eq 'continue') {
                    $totalWarnings++
                    $warningTasks += $taskName
                    Write-Warning ("Task warning: {0} exited with code {1}" -f $taskName, $taskResult.ExitCode)
                    Write-Host ("Task completed: {0} ({1:N1}s) - warning" -f $taskName, $taskElapsedSeconds)
                }
                else {
                    $failedTasks += $taskName
                    $totalErrors++
                    Write-Host ("Task failed: {0}" -f $taskName) -ForegroundColor Red
                    throw ("VM update task failed: {0} (exit {1})" -f $taskName, $taskResult.ExitCode)
                }
            }

            $taskRequestedReboot = $false
            if ($taskResult -and $taskResult.PSObject.Properties.Match('Output').Count -gt 0) {
                $taskRequestedReboot = Test-ProdicloudOutputIndicatesRebootRequired -MessageText ([string]$taskResult.Output)
            }
            if ($taskRequestedReboot) {
                $rebootCount++
                $rebootRequestedTasks += $taskName

                if ($null -ne $session) {
                    Stop-ProdicloudPersistentSshSession -Session $session
                    $session = $null
                }

                $restartRecovery = Invoke-ProdicloudRestartAndWait `
                    -ResourceGroup ([string]$ResourceGroup) `
                    -VmName ([string]$VmName) `
                    -StartMessage ("Task '{0}' requested a restart. Restarting VM now..." -f [string]$taskName) `
                    -SuccessMessage ("VM restart completed successfully after task '{0}'." -f [string]$taskName) `
                    -RunningFailureSummary 'VM could not be restarted after a vm-update task.' `
                    -RunningFailureHint 'Check the VM in Azure Portal and rerun vm-update after the guest returns to running state.' `
                    -ProvisioningFailureSummary 'VM restart recovery after a vm-update task did not complete successfully.' `
                    -ProvisioningFailureHint 'Check provisioning status and guest boot health before rerunning vm-update.' `
                    -HostFailureSummary 'VM restart after a vm-update task completed, but SSH host resolution failed.' `
                    -HostFailureHint 'Verify that the managed VM still has a reachable public IP or FQDN.' `
                    -SshFailureSummary 'VM restart after a vm-update task completed, but SSH did not recover in time.' `
                    -SshFailureHint 'Verify guest startup health and rerun vm-update after SSH becomes reachable.' `
                    -SshPort ([int]$SshPort) `
                    -SshConnectTimeoutSeconds $SshConnectTimeoutSeconds `
                    -RequireSsh `
                    -Context @{
                        ResourceGroup = [string]$ResourceGroup
                        VmName = [string]$VmName
                        SshPort = [int]$SshPort
                    }

                if (-not [string]::IsNullOrWhiteSpace([string]$restartRecovery.SshHost)) {
                    $SshHost = [string]$restartRecovery.SshHost
                }

                $bootstrap = Initialize-ProdicloudSshHostKey `
                    -PySshPythonPath ([string]$pySsh.PythonPath) `
                    -PySshClientPath ([string]$pySsh.ClientPath) `
                    -HostName $SshHost `
                    -UserName $SshUser `
                    -Password $SshPassword `
                    -Port $SshPort `
                    -ConnectTimeoutSeconds $SshConnectTimeoutSeconds
                if (-not [string]::IsNullOrWhiteSpace([string]$bootstrap.Output)) {
                    Write-Host ([string]$bootstrap.Output)
                }

                if ($persistentSessionEnabled) {
                    try {
                        $session = Start-ProdicloudPersistentSshSession `
                            -PySshPythonPath ([string]$pySsh.PythonPath) `
                            -PySshClientPath ([string]$pySsh.ClientPath) `
                            -HostName $SshHost `
                            -UserName $SshUser `
                            -Password $SshPassword `
                            -Port $SshPort `
                            -Shell $shell `
                            -ConnectTimeoutSeconds $SshConnectTimeoutSeconds `
                            -DefaultTaskTimeoutSeconds $SshTaskTimeoutSeconds
                    }
                    catch {
                        $persistentSessionEnabled = $false
                        $usedOneShotTransport = $true
                        $session = $null
                        Write-Warning ("Persistent SSH session recovery failed after task '{0}'. Switching to one-shot SSH task execution: {1}" -f $taskName, $_.Exception.Message)
                    }
                }
            }
        }

        if ($EnableFinalVmRestart -and @($TaskBlocks).Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$ResourceGroup) -and -not [string]::IsNullOrWhiteSpace([string]$VmName)) {
            if ($null -ne $session) {
                Stop-ProdicloudPersistentSshSession -Session $session
                $session = $null
            }

            $finalRestartCount = 1
            $finalRestartRecovery = Invoke-ProdicloudRestartAndWait `
                -ResourceGroup ([string]$ResourceGroup) `
                -VmName ([string]$VmName) `
                -StartMessage 'VM update completed. Running the final VM restart before vm-summary...' `
                -SuccessMessage 'Final VM restart after vm-update completed successfully.' `
                -RunningFailureSummary 'VM could not be restarted after vm-update.' `
                -RunningFailureHint 'Check the VM in Azure Portal and rerun update after the guest returns to running state.' `
                -ProvisioningFailureSummary 'VM restart recovery after vm-update did not complete successfully.' `
                -ProvisioningFailureHint 'Check provisioning status and guest boot health before relying on the updated VM.' `
                -HostFailureSummary 'Final VM restart after vm-update completed, but SSH host resolution failed.' `
                -HostFailureHint 'Verify that the managed VM still has a reachable public IP or FQDN.' `
                -SshFailureSummary 'Final VM restart after vm-update completed, but SSH did not recover in time.' `
                -SshFailureHint 'Verify guest startup health before continuing to vm-summary.' `
                -SshPort ([int]$SshPort) `
                -SshConnectTimeoutSeconds $SshConnectTimeoutSeconds `
                -RequireSsh `
                -Context @{
                    ResourceGroup = [string]$ResourceGroup
                    VmName = [string]$VmName
                    SshPort = [int]$SshPort
                }
            if ($null -ne $finalRestartRecovery -and -not [string]::IsNullOrWhiteSpace([string]$finalRestartRecovery.SshHost)) {
                $SshHost = [string]$finalRestartRecovery.SshHost
            }
        }

        $uniqueSuccessfulTasks = @($successfulTasks | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
        $uniqueFailedTasks = @($failedTasks | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
        $uniqueWarningTasks = @($warningTasks | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
        $uniqueSignalWarningTasks = @($signalWarningTasks | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)

        Write-Host ("VM update stage summary: success={0}, failed={1}, warning={2}, signal-warning={3}, error={4}, reboot={5}, final-restart={6}" -f @($uniqueSuccessfulTasks).Count, @($uniqueFailedTasks).Count, $totalWarnings, $signalWarningCount, $totalErrors, $rebootCount, $finalRestartCount)
        if ($usedOneShotTransport) {
            if ($Platform -eq 'windows') {
                Write-Host 'VM update transport summary: one-shot SSH execution was used for the Windows task stage.' -ForegroundColor Cyan
            }
            else {
                Write-Host 'VM update transport summary: one-shot SSH execution was used for one or more tasks.' -ForegroundColor Yellow
            }
        }
        if (@($uniqueSignalWarningTasks).Count -gt 0) {
            Write-Host 'Signal warning tasks:' -ForegroundColor Yellow
            foreach ($signalWarningTask in @($uniqueSignalWarningTasks)) {
                Write-Host ("- {0}" -f [string]$signalWarningTask) -ForegroundColor Yellow
            }
        }
        if (@($uniqueWarningTasks).Count -gt 0) {
            Write-Host 'Warning tasks:' -ForegroundColor Yellow
            foreach ($warningTaskName in @($uniqueWarningTasks)) {
                Write-Host ("- {0}" -f [string]$warningTaskName) -ForegroundColor Yellow
            }
        }
        if (@($uniqueFailedTasks).Count -gt 0) {
            Write-Host 'Failed tasks:' -ForegroundColor Yellow
            foreach ($failedTaskName in @($uniqueFailedTasks)) {
                Write-Host ("- {0}" -f [string]$failedTaskName) -ForegroundColor Yellow
            }
        }
        if ($rebootCount -gt 0) {
            $rebootTaskList = @(
                $rebootRequestedTasks |
                    Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
                    Select-Object -Unique
            )
            if (@($rebootTaskList).Count -eq 0) {
                $rebootTaskList = @('(task names unavailable)')
            }
            Write-Host 'VM update automatic restarts were completed after reboot-signaling tasks.' -ForegroundColor Cyan
            Write-Host 'Restarted after tasks:' -ForegroundColor Cyan
            foreach ($rebootTaskName in @($rebootTaskList)) {
                Write-Host ("- {0}" -f [string]$rebootTaskName) -ForegroundColor Cyan
            }
        }
        if (-not [string]::Equals([string]$PerfTaskCategory, 'task-run', [System.StringComparison]::OrdinalIgnoreCase)) {
            if ($stageWatch.IsRunning) { $stageWatch.Stop() }
            Write-ProdicloudTaskStageHistoryRecord `
                -Stage 'update' `
                -Platform $Platform `
                -ResourceGroup $ResourceGroup `
                -VmName $VmName `
                -TaskNames @($TaskBlocks | ForEach-Object { [string]$_.Name }) `
                -FailedTasks @($uniqueFailedTasks) `
                -WarningTasks @(@($uniqueWarningTasks) + @($uniqueSignalWarningTasks)) `
                -SuccessCount @($uniqueSuccessfulTasks).Count `
                -ErrorCount $totalErrors `
                -RebootCount $rebootCount `
                -DurationSeconds $stageWatch.Elapsed.TotalSeconds
        }
        if ($TaskOutcomeMode -eq 'strict' -and ($totalWarnings -gt 0 -or $totalErrors -gt 0)) {
            throw ("VM update strict task outcome mode blocked continuation: warning={0}, error={1}" -f $totalWarnings, $totalErrors)
        }

        return [pscustomobject]@{
            SuccessCount = $totalSuccess
            SuccessTasks = @($uniqueSuccessfulTasks)
            TaskOutputs = @($taskOutputs)
            FailedCount = @($uniqueFailedTasks).Count
            FailedTasks = @($uniqueFailedTasks)
            WarningCount = $totalWarnings
            WarningTasks = @($uniqueWarningTasks)
            SignalWarningCount = [int]$signalWarningCount
            SignalWarningTasks = @($uniqueSignalWarningTasks)
            ErrorCount = $totalErrors
            RebootCount = $rebootCount
            FinalRestartCount = [int]$finalRestartCount
            RebootRequired = $false
            RebootRequestedTasks = @($rebootRequestedTasks | Select-Object -Unique)
        }
    }
    finally {
        if ($null -ne $session) {
            Stop-ProdicloudPersistentSshSession -Session $session
        }
    }
}
