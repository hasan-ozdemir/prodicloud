# Run-command task runner.

function New-ClagnosRunCommandTaskWrapperScript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TaskName,
        [Parameter(Mandatory = $true)]
        [string]$TaskScript,
        [int]$TimeoutSeconds = 180,
        [ValidateSet('bash','powershell')]
        [string]$CombinedShell = 'powershell'
    )

    if ($TimeoutSeconds -lt 30) {
        $TimeoutSeconds = 30
    }

    if ([string]::Equals([string]$CombinedShell, 'bash', [System.StringComparison]::OrdinalIgnoreCase)) {
        $taskNameBytes = [System.Text.Encoding]::UTF8.GetBytes([string]$TaskName)
        $taskNameBase64 = [System.Convert]::ToBase64String($taskNameBytes)
        $taskBytes = [System.Text.Encoding]::UTF8.GetBytes([string]$TaskScript)
        $taskBase64 = [System.Convert]::ToBase64String($taskBytes)

        $builder = New-Object System.Text.StringBuilder
        [void]$builder.AppendLine('set -uo pipefail')
        [void]$builder.AppendLine('success_count=0')
        [void]$builder.AppendLine('warning_count=0')
        [void]$builder.AppendLine('error_count=0')
        [void]$builder.AppendLine('reboot_count=0')
        [void]$builder.AppendLine('invoke_task() {')
        [void]$builder.AppendLine('  local task_name_base64="$1"')
        [void]$builder.AppendLine('  local script_base64="$2"')
        [void]$builder.AppendLine('  local task_timeout="$3"')
        [void]$builder.AppendLine('  local task_name')
        [void]$builder.AppendLine('  task_name=$(printf ''%s'' "$task_name_base64" | base64 -d)')
        [void]$builder.AppendLine('  local start_ts')
        [void]$builder.AppendLine('  start_ts=$(date +%s)')
        [void]$builder.AppendLine('  local task_script')
        [void]$builder.AppendLine('  task_script=$(printf ''%s'' "$script_base64" | base64 -d)')
        [void]$builder.AppendLine('  local task_output=""')
        [void]$builder.AppendLine('  if task_output=$(timeout --signal=TERM --kill-after=15 "${task_timeout}" bash -lc "$task_script" 2>&1); then')
        [void]$builder.AppendLine('    local end_ts')
        [void]$builder.AppendLine('    end_ts=$(date +%s)')
        [void]$builder.AppendLine('    local elapsed=$(( end_ts - start_ts ))')
        [void]$builder.AppendLine('    if [ -n "$task_output" ]; then')
        [void]$builder.AppendLine('      printf ''%s\n'' "$task_output"')
        [void]$builder.AppendLine('    fi')
        [void]$builder.AppendLine('    echo "TASK_STATUS:${task_name}:success"')
        [void]$builder.AppendLine('    success_count=$(( success_count + 1 ))')
        [void]$builder.AppendLine('  else')
        [void]$builder.AppendLine('    local exit_code=$?')
        [void]$builder.AppendLine('    local end_ts')
        [void]$builder.AppendLine('    end_ts=$(date +%s)')
        [void]$builder.AppendLine('    local elapsed=$(( end_ts - start_ts ))')
        [void]$builder.AppendLine('    if [ -n "$task_output" ]; then')
        [void]$builder.AppendLine('      printf ''%s\n'' "$task_output"')
        [void]$builder.AppendLine('    fi')
        [void]$builder.AppendLine('    echo "TASK_STATUS:${task_name}:error"')
        [void]$builder.AppendLine('    error_count=$(( error_count + 1 ))')
        [void]$builder.AppendLine('  fi')
        [void]$builder.AppendLine('}')
        [void]$builder.AppendLine(("invoke_task '{0}' '{1}' '{2}'" -f $taskNameBase64, $taskBase64, [int]$TimeoutSeconds))
        [void]$builder.AppendLine('echo "RUN_COMMAND_SUMMARY:success=${success_count};warning=${warning_count};error=${error_count};reboot=${reboot_count}"')
        return $builder.ToString()
    }

    $taskNameSafe = [string]$TaskName.Replace("'", "''")
    $taskBytes = [System.Text.Encoding]::UTF8.GetBytes([string]$TaskScript)
    $taskBase64 = [System.Convert]::ToBase64String($taskBytes)

    $builder = New-Object System.Text.StringBuilder
    [void]$builder.AppendLine('$ErrorActionPreference = "Stop"')
    [void]$builder.AppendLine('$ProgressPreference = "SilentlyContinue"')
    [void]$builder.AppendLine('$script:SuccessCount = 0')
    [void]$builder.AppendLine('$script:WarningCount = 0')
    [void]$builder.AppendLine('$script:ErrorCount = 0')
    [void]$builder.AppendLine('$script:RebootCount = 0')
    [void]$builder.AppendLine('function Invoke-RunCommandTaskBlock {')
    [void]$builder.AppendLine('    param([string]$TaskName,[string]$ScriptBase64,[int]$TimeoutSeconds)')
    [void]$builder.AppendLine('    $taskWatch = [System.Diagnostics.Stopwatch]::StartNew()')
    [void]$builder.AppendLine('    $nestedScriptPath = ""')
    [void]$builder.AppendLine('    $taskScriptPath = ""')
    [void]$builder.AppendLine('    $stdoutPath = ""')
    [void]$builder.AppendLine('    $stderrPath = ""')
    [void]$builder.AppendLine('    $process = $null')
    [void]$builder.AppendLine('    $nestedResult = ""')
    [void]$builder.AppendLine('    try {')
    [void]$builder.AppendLine('        $decodedScript = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($ScriptBase64))')
    [void]$builder.AppendLine('        $nestedScript = ''param([string]$TaskScriptPath)'' + [Environment]::NewLine + ''$ErrorActionPreference = "Stop"'' + [Environment]::NewLine + ''$ProgressPreference = "SilentlyContinue"'' + [Environment]::NewLine + ''$InformationPreference = "Continue"'' + [Environment]::NewLine + ''try {'' + [Environment]::NewLine + ''    $decodedScript = [string](Get-Content -LiteralPath $TaskScriptPath -Raw -ErrorAction Stop)'' + [Environment]::NewLine + ''    $taskScriptBlock = [scriptblock]::Create($decodedScript)'' + [Environment]::NewLine + ''    & $taskScriptBlock *>&1 | ForEach-Object { if ($null -ne $_) { [Console]::Out.WriteLine([string]$_) } }'' + [Environment]::NewLine + ''    [Console]::Out.WriteLine("CLAGNOS_NESTED_RESULT:success")'' + [Environment]::NewLine + ''    exit 0'' + [Environment]::NewLine + ''} catch {'' + [Environment]::NewLine + ''    $nestedFailure = [string]$_.Exception.Message'' + [Environment]::NewLine + ''    if (-not [string]::IsNullOrWhiteSpace([string]$nestedFailure)) { [Console]::Error.WriteLine($nestedFailure) }'' + [Environment]::NewLine + ''    [Console]::Out.WriteLine("CLAGNOS_NESTED_RESULT:error")'' + [Environment]::NewLine + ''    exit 1'' + [Environment]::NewLine + ''}''')
    [void]$builder.AppendLine('        $artifactBaseName = "clagnos-run-command-" + [System.Guid]::NewGuid().ToString("N")')
    [void]$builder.AppendLine('        $nestedScriptPath = Join-Path ([System.IO.Path]::GetTempPath()) ($artifactBaseName + ".task.ps1")')
    [void]$builder.AppendLine('        $taskScriptPath = Join-Path ([System.IO.Path]::GetTempPath()) ($artifactBaseName + ".payload.ps1")')
    [void]$builder.AppendLine('        $stdoutPath = Join-Path ([System.IO.Path]::GetTempPath()) ($artifactBaseName + ".stdout.log")')
    [void]$builder.AppendLine('        $stderrPath = Join-Path ([System.IO.Path]::GetTempPath()) ($artifactBaseName + ".stderr.log")')
    [void]$builder.AppendLine('        [System.IO.File]::WriteAllText($taskScriptPath, $decodedScript, (New-Object System.Text.UTF8Encoding($false)))')
    [void]$builder.AppendLine('        [System.IO.File]::WriteAllText($nestedScriptPath, $nestedScript, (New-Object System.Text.UTF8Encoding($false)))')
    [void]$builder.AppendLine('        $process = Start-Process -FilePath ''powershell.exe'' -ArgumentList @(''-NoProfile'',''-NonInteractive'',''-ExecutionPolicy'',''Bypass'',''-File'', $nestedScriptPath, ''-TaskScriptPath'', $taskScriptPath) -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru -WindowStyle Hidden')
    [void]$builder.AppendLine('        $completed = $process.WaitForExit([Math]::Max([int]$TimeoutSeconds, 30) * 1000)')
    [void]$builder.AppendLine('        if (-not $completed) {')
    [void]$builder.AppendLine('            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue')
    [void]$builder.AppendLine('            [void]$process.WaitForExit(5000)')
    [void]$builder.AppendLine('        }')
    [void]$builder.AppendLine('        $commandOutputLines = New-Object ''System.Collections.Generic.List[string]''')
    [void]$builder.AppendLine('        foreach ($candidatePath in @($stdoutPath, $stderrPath)) {')
    [void]$builder.AppendLine('            if (-not [string]::IsNullOrWhiteSpace([string]$candidatePath) -and (Test-Path -LiteralPath $candidatePath)) {')
    [void]$builder.AppendLine('                $rawOutput = [string](Get-Content -LiteralPath $candidatePath -Raw -ErrorAction SilentlyContinue)')
    [void]$builder.AppendLine('                foreach ($line in @($rawOutput -split "`r?`n")) {')
    [void]$builder.AppendLine('                    if ($line -match ''^CLAGNOS_NESTED_RESULT:(success|error)$'') {')
    [void]$builder.AppendLine('                        $nestedResult = [string]$Matches[1]')
    [void]$builder.AppendLine('                        continue')
    [void]$builder.AppendLine('                    }')
    [void]$builder.AppendLine('                    if (-not [string]::IsNullOrWhiteSpace([string]$line)) {')
    [void]$builder.AppendLine('                        $commandOutputLines.Add([string]$line) | Out-Null')
    [void]$builder.AppendLine('                    }')
    [void]$builder.AppendLine('                }')
    [void]$builder.AppendLine('            }')
    [void]$builder.AppendLine('        }')
    [void]$builder.AppendLine('        foreach ($line in @($commandOutputLines.ToArray())) {')
    [void]$builder.AppendLine('            if (-not [string]::IsNullOrWhiteSpace([string]$line)) {')
    [void]$builder.AppendLine('                Write-Host ([string]$line)')
    [void]$builder.AppendLine('            }')
    [void]$builder.AppendLine('        }')
    [void]$builder.AppendLine('        if (-not $completed) {')
    [void]$builder.AppendLine('            throw ("Task timed out after {0} second(s)." -f [int]$TimeoutSeconds)')
    [void]$builder.AppendLine('        }')
    [void]$builder.AppendLine('        if ([string]::Equals([string]$nestedResult, ''error'', [System.StringComparison]::OrdinalIgnoreCase)) {')
    [void]$builder.AppendLine('            $failureMessage = if ($commandOutputLines.Count -gt 0) { [string]($commandOutputLines.ToArray() -join [Environment]::NewLine) } else { ''Nested PowerShell reported an error.'' }')
    [void]$builder.AppendLine('            throw $failureMessage')
    [void]$builder.AppendLine('        }')
    [void]$builder.AppendLine('        if (-not [string]::Equals([string]$nestedResult, ''success'', [System.StringComparison]::OrdinalIgnoreCase)) {')
    [void]$builder.AppendLine('            $failureMessage = if ($commandOutputLines.Count -gt 0) { [string]($commandOutputLines.ToArray() -join [Environment]::NewLine) } else { "Nested PowerShell exited with code $($process.ExitCode)." }')
    [void]$builder.AppendLine('            if ([string]::IsNullOrWhiteSpace([string]$failureMessage)) {')
    [void]$builder.AppendLine('                $failureMessage = "Nested PowerShell ended without a result marker."')
    [void]$builder.AppendLine('            }')
    [void]$builder.AppendLine('            if ($process.ExitCode -ne 0 -and $failureMessage -notmatch ''Nested PowerShell exited with code'') {')
    [void]$builder.AppendLine('                $failureMessage = ("{0}{1}Nested PowerShell exited with code {2}." -f $failureMessage, [Environment]::NewLine, $process.ExitCode)')
    [void]$builder.AppendLine('            }')
    [void]$builder.AppendLine('            throw $failureMessage')
    [void]$builder.AppendLine('        }')
    [void]$builder.AppendLine('        if ($taskWatch.IsRunning) { $taskWatch.Stop() }')
    [void]$builder.AppendLine('        Write-Host ("TASK_STATUS:{0}:success" -f $TaskName)')
    [void]$builder.AppendLine('        $script:SuccessCount++')
    [void]$builder.AppendLine('    }')
    [void]$builder.AppendLine('    catch {')
    [void]$builder.AppendLine('        if ($taskWatch.IsRunning) { $taskWatch.Stop() }')
    [void]$builder.AppendLine('        $failureText = [string]$_.Exception.Message')
    [void]$builder.AppendLine('        if (-not [string]::IsNullOrWhiteSpace([string]$failureText)) {')
    [void]$builder.AppendLine('            Write-Host $failureText')
    [void]$builder.AppendLine('        }')
    [void]$builder.AppendLine('        Write-Host ("TASK_STATUS:{0}:error" -f $TaskName)')
    [void]$builder.AppendLine('        $script:ErrorCount++')
    [void]$builder.AppendLine('    }')
    [void]$builder.AppendLine('    finally {')
    [void]$builder.AppendLine('        if ($null -ne $process) {')
    [void]$builder.AppendLine('            try { $process.Dispose() } catch { }')
    [void]$builder.AppendLine('        }')
    [void]$builder.AppendLine('        foreach ($artifactPath in @($nestedScriptPath, $taskScriptPath, $stdoutPath, $stderrPath)) {')
    [void]$builder.AppendLine('            if (-not [string]::IsNullOrWhiteSpace([string]$artifactPath)) {')
    [void]$builder.AppendLine('                Remove-Item -LiteralPath $artifactPath -Force -ErrorAction SilentlyContinue')
    [void]$builder.AppendLine('            }')
    [void]$builder.AppendLine('        }')
    [void]$builder.AppendLine('    }')
    [void]$builder.AppendLine('}')
    [void]$builder.AppendLine(("Invoke-RunCommandTaskBlock -TaskName '{0}' -ScriptBase64 '{1}' -TimeoutSeconds {2}" -f $taskNameSafe, $taskBase64, [int]$TimeoutSeconds))
    [void]$builder.AppendLine('Write-Host ("RUN_COMMAND_SUMMARY:success={0};warning={1};error={2};reboot={3}" -f $script:SuccessCount, $script:WarningCount, $script:ErrorCount, $script:RebootCount)')
    return $builder.ToString()
}

function Invoke-ClagnosSingleRunCommandTask {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroup,
        [Parameter(Mandatory = $true)]
        [string]$VmName,
        [Parameter(Mandatory = $true)]
        [string]$CommandId,
        [Parameter(Mandatory = $true)]
        [psobject]$TaskBlock,
        [ValidateSet('bash','powershell')]
        [string]$CombinedShell = 'powershell',
        [ValidateSet('continue','strict')]
        [string]$TaskOutcomeMode = 'continue',
        [ValidateSet('vm-init-task','task-run')]
        [string]$PerfTaskCategory = 'vm-init-task'
    )

    $taskName = [string]$TaskBlock.Name
    $taskScript = Resolve-ClagnosRunCommandScriptText -ScriptText ([string]$TaskBlock.Script)
    $taskTimeoutSeconds = Get-ClagnosTaskTimeoutSeconds -TaskBlock $TaskBlock -DefaultTimeoutSeconds 180
    $wrappedScript = New-ClagnosRunCommandTaskWrapperScript -TaskName $taskName -TaskScript $taskScript -TimeoutSeconds $taskTimeoutSeconds -CombinedShell $CombinedShell
    $scriptArgs = Get-ClagnosRunCommandScriptArgs -ScriptText $wrappedScript -CommandId $CommandId
    $azArgs = @(
        'vm', 'run-command', 'invoke',
        '--resource-group', $ResourceGroup,
        '--name', $VmName,
        '--command-id', $CommandId,
        '--scripts'
    )
    $azArgs += $scriptArgs
    $azArgs += @('-o', 'json')
    $invokeLabel = ("az vm run-command invoke ({0})" -f [string]$taskName)
    $azTimeoutSeconds = [Math]::Max([int]$taskTimeoutSeconds + 120, [int]$script:AzCommandTimeoutSeconds)
    Write-ClagnosActionProgress -Action ("run guest task '{0}' with Azure Run Command (max {1}s)" -f [string]$taskName, [int]$taskTimeoutSeconds)
    $taskWatch = [System.Diagnostics.Stopwatch]::StartNew()
    $rawJson = Invoke-ClagnosWithAzCliTimeoutSeconds -TimeoutSeconds $azTimeoutSeconds -Action {
        Invoke-TrackedAction -Label $invokeLabel -Action {
            $invokeResult = az @azArgs
            Assert-LastExitCode $invokeLabel
            $invokeResult
        }
    }

    $parsedResult = Get-ClagnosRunCommandResultEnvelope -TaskName $taskName -RawJson $rawJson -ModeLabel 'task-run'
    $messageText = [string]$parsedResult.MessageText
    $marker = Parse-ClagnosRunCommandBatchMarkers -MessageText $messageText
    $displayLines = @()
    foreach ($lineRaw in @([string]$messageText -split "`r?`n")) {
        $line = [string]$lineRaw
        if ([string]::IsNullOrWhiteSpace([string]$line)) {
            continue
        }
        if ($line -match '^TASK_STATUS:' -or $line -match '^RUN_COMMAND_SUMMARY:') {
            continue
        }
        $displayLines += [string]$line
    }
    if ($taskWatch.IsRunning) { $taskWatch.Stop() }
    if (@($displayLines).Count -gt 0) {
        Write-Host ("Guest output relay: {0}" -f [string]$taskName) -ForegroundColor DarkCyan
        Write-Host ((@($displayLines) -join "`n"))
    }
    if ([bool]$parsedResult.HasError) {
        Write-Host ("Task completed: {0} ({1:N1}s) - error" -f [string]$taskName, $taskWatch.Elapsed.TotalSeconds) -ForegroundColor Red
        throw [string]$parsedResult.ErrorMessage
    }

    $taskStateLabel = if ([int]$marker.ErrorCount -gt 0) { 'warning' } else { 'success' }
    Write-Host ("Task completed: {0} ({1:N1}s) - {2}" -f [string]$taskName, $taskWatch.Elapsed.TotalSeconds, [string]$taskStateLabel)

    return [pscustomobject]@{
        TaskName = [string]$taskName
        MessageText = [string]$messageText
        SuccessCount = [int]$marker.SuccessCount
        WarningCount = [int]$marker.WarningCount
        ErrorCount = [int]$marker.ErrorCount
        RebootRequired = ([bool]$marker.RebootRequired -or (Test-ClagnosOutputIndicatesRebootRequired -MessageText $messageText))
        TaskDurations = @()
        DurationSeconds = [double]$taskWatch.Elapsed.TotalSeconds
    }
}

function Get-ClagnosRunCommandTaskAppStateDisposition {
    param([psobject]$TaskBlock)

    $pluginInfo = Get-ClagnosTaskAppStatePluginInfo -TaskBlock $TaskBlock
    $taskName = if ($null -ne $TaskBlock -and $TaskBlock.PSObject.Properties.Match('Name').Count -gt 0) { [string]$TaskBlock.Name } else { '' }

    switch ([string]$pluginInfo.Status) {
        'ready' {
            return [pscustomobject]@{
                Status = 'ready'
                TaskName = [string]$taskName
                Message = 'ready'
            }
        }
        'missing-plugin' {
            return [pscustomobject]@{
                Status = 'skip'
                TaskName = [string]$taskName
                Message = 'no plugin'
            }
        }
        'missing-zip' {
            return [pscustomobject]@{
                Status = 'skip'
                TaskName = [string]$taskName
                Message = 'no zip'
            }
        }
        'invalid' {
            return [pscustomobject]@{
                Status = 'warning'
                TaskName = [string]$taskName
                Message = [string]$pluginInfo.Message
            }
        }
        default {
            return [pscustomobject]@{
                Status = 'skip'
                TaskName = [string]$taskName
                Message = 'unknown plugin state'
            }
        }
    }
}

function Test-ClagnosRunCommandAppStateSshReady {
    param(
        [string]$SshHost,
        [string]$SshPort,
        [int]$ConnectTimeoutSeconds = 30,
        [switch]$AllowWait
    )

    if ([string]::IsNullOrWhiteSpace([string]$SshHost) -or [string]::IsNullOrWhiteSpace([string]$SshPort)) {
        return $false
    }

    $portNumber = 0
    try {
        $portNumber = [int]$SshPort
    }
    catch {
        return $false
    }
    if ($portNumber -lt 1 -or $portNumber -gt 65535) {
        return $false
    }

    $timeoutSeconds = [Math]::Min([Math]::Max([int]$ConnectTimeoutSeconds, 5), 10)
    $maxAttempts = if ($AllowWait) { 3 } else { 1 }
    $delaySeconds = if ($AllowWait) { 5 } else { 0 }

    return [bool](Wait-ClagnosTcpPortReachable -HostName $SshHost -Port $portNumber -MaxAttempts $maxAttempts -DelaySeconds $delaySeconds -TimeoutSeconds $timeoutSeconds -Label 'ssh')
}

function Invoke-ClagnosRunCommandDeferredAppStateFlush {
    param(
        [ValidateSet('windows','linux')]
        [string]$Platform,
        [string]$RepoRoot,
        [psobject[]]$PendingTaskBlocks = @(),
        [string]$SshHost,
        [string]$SshUser,
        [string]$SshPassword,
        [string]$SshPort,
        [int]$SshConnectTimeoutSeconds = 30,
        [string]$ConfiguredPySshClientPath = '',
        [string]$ManagerUser = '',
        [string]$AssistantUser = '',
        [switch]$AllowWait
    )

    $pendingTasks = @($PendingTaskBlocks)
    if (@($pendingTasks).Count -lt 1) {
        return [pscustomobject]@{
            RemainingTasks = @()
            WarningTasks = @()
        }
    }

    if (-not (Test-ClagnosRunCommandAppStateSshReady -SshHost $SshHost -SshPort $SshPort -ConnectTimeoutSeconds $SshConnectTimeoutSeconds -AllowWait:$AllowWait)) {
        return [pscustomobject]@{
            RemainingTasks = @($pendingTasks)
            WarningTasks = @()
        }
    }

    $pySsh = Ensure-ClagnosPySshTools -RepoRoot $RepoRoot -ConfiguredPySshClientPath $ConfiguredPySshClientPath
    $bootstrap = Initialize-ClagnosSshHostKey `
        -PySshPythonPath ([string]$pySsh.PythonPath) `
        -PySshClientPath ([string]$pySsh.ClientPath) `
        -HostName $SshHost `
        -UserName $SshUser `
        -Password $SshPassword `
        -Port $SshPort `
        -ConnectTimeoutSeconds $SshConnectTimeoutSeconds
    if ($null -ne $bootstrap -and $bootstrap.PSObject.Properties.Match('Output').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$bootstrap.Output)) {
        Write-Host ([string]$bootstrap.Output)
    }

    $warningTasks = New-Object 'System.Collections.Generic.List[string]'
    foreach ($taskBlock in @($pendingTasks)) {
        if ($null -eq $taskBlock) {
            continue
        }

        $taskName = if ($taskBlock.PSObject.Properties.Match('Name').Count -gt 0) { [string]$taskBlock.Name } else { '(unknown-task)' }
        try {
            $appStateResult = Invoke-ClagnosTaskAppStatePostProcess `
                -Platform $Platform `
                -RepoRoot $RepoRoot `
                -TaskBlock $taskBlock `
                -PySshPythonPath ([string]$pySsh.PythonPath) `
                -PySshClientPath ([string]$pySsh.ClientPath) `
                -HostName $SshHost `
                -UserName $SshUser `
                -Password $SshPassword `
                -Port $SshPort `
                -ConnectTimeoutSeconds $SshConnectTimeoutSeconds `
                -TimeoutSeconds (Get-ClagnosTaskTimeoutSeconds -TaskBlock $taskBlock -DefaultTimeoutSeconds 180) `
                -ManagerUser ([string]$ManagerUser) `
                -AssistantUser ([string]$AssistantUser)
            if ($null -ne $appStateResult -and $appStateResult.PSObject.Properties.Match('Warning').Count -gt 0 -and [bool]$appStateResult.Warning) {
                $warningTasks.Add(("{0} => app-state" -f [string]$taskName)) | Out-Null
            }
        }
        catch {
            Write-Warning ("App-state warning: {0} => {1}" -f [string]$taskName, $_.Exception.Message)
            $warningTasks.Add(("{0} => app-state" -f [string]$taskName)) | Out-Null
        }
    }

    return [pscustomobject]@{
        RemainingTasks = @()
        WarningTasks = @($warningTasks.ToArray())
    }
}

# Handles Invoke-VmRunCommandBlocks.
function Invoke-VmRunCommandBlocks {
    param(
        [string]$ResourceGroup,
        [string]$VmName,
        [string]$CommandId,
        [object[]]$TaskBlocks,
        [ValidateSet('bash','powershell')]
        [string]$CombinedShell = 'powershell',
        [ValidateSet('continue','strict')]
        [string]$TaskOutcomeMode = 'continue',
        [ValidateSet('vm-init-task','task-run')]
        [string]$PerfTaskCategory = 'vm-init-task',
        [ValidateSet('windows','linux')]
        [string]$Platform = 'windows',
        [string]$RepoRoot = '',
        [string]$ManagerUser = '',
        [string]$AssistantUser = '',
        [string]$SshHost = '',
        [string]$SshUser = '',
        [string]$SshPassword = '',
        [string]$SshPort = '',
        [int]$SshConnectTimeoutSeconds = 30,
        [string]$ConfiguredPySshClientPath = ''
    )

    if (-not $TaskBlocks -or $TaskBlocks.Count -eq 0) {
        throw 'VM run-command task list is empty.'
    }

    $stageWatch = [System.Diagnostics.Stopwatch]::StartNew()

    Write-Host 'VM init stage mode: tasks run one-by-one over Azure Run Command.'
    Write-Host ("Task outcome policy: {0}" -f $TaskOutcomeMode)

    $totalSuccess = 0
    $totalWarnings = 0
    $totalErrors = 0
    $rebootCount = 0
    $successfulTasks = @()
    $failedTasks = @()
    $warningTasks = @()
    $rebootRequestedTasks = @()
    $processedTaskCount = 0
    $pendingAppStateTaskBlocks = New-Object 'System.Collections.Generic.List[object]'
    $deferredAppStateTasks = @{}

    foreach ($taskBlock in @($TaskBlocks)) {
        $processedTaskCount++
        $taskName = [string]$taskBlock.Name
        $taskResult = $null

        try {
            $taskResult = Invoke-ClagnosSingleRunCommandTask -ResourceGroup $ResourceGroup -VmName $VmName -CommandId $CommandId -TaskBlock $taskBlock -CombinedShell $CombinedShell -TaskOutcomeMode $TaskOutcomeMode -PerfTaskCategory $PerfTaskCategory
        }
        catch {
            $failedTasks += $taskName
            if ([string]::Equals([string]$TaskOutcomeMode, 'continue', [System.StringComparison]::OrdinalIgnoreCase)) {
                $totalWarnings++
                $warningTasks += ("{0} => invocation" -f [string]$taskName)
                Write-Warning ("Task warning: {0} failed in Azure Run Command => {1}" -f [string]$taskName, $_.Exception.Message)
                continue
            }

            $totalErrors++
            throw ("VM init task failed in Azure Run Command: {0} => {1}" -f [string]$taskName, $_.Exception.Message)
        }

        if ([int]$taskResult.SuccessCount -gt 0 -and [int]$taskResult.ErrorCount -eq 0) {
            $totalSuccess += [int]$taskResult.SuccessCount
            $successfulTasks += $taskName

            $appStateDisposition = Get-ClagnosRunCommandTaskAppStateDisposition -TaskBlock $taskBlock
            switch ([string]$appStateDisposition.Status) {
                'ready' {
                    $pendingAppStateTaskBlocks.Add($taskBlock) | Out-Null
                }
                'warning' {
                    $totalWarnings++
                    $warningTasks += ("{0} => app-state-contract" -f [string]$taskName)
                    Write-Warning ("App-state warning: {0} => {1}" -f [string]$taskName, [string]$appStateDisposition.Message)
                }
            }

            if ($pendingAppStateTaskBlocks.Count -gt 0) {
                try {
                    $flushResult = Invoke-ClagnosRunCommandDeferredAppStateFlush `
                        -Platform $Platform `
                        -RepoRoot $RepoRoot `
                        -PendingTaskBlocks @($pendingAppStateTaskBlocks.ToArray()) `
                        -SshHost $SshHost `
                        -SshUser $SshUser `
                        -SshPassword $SshPassword `
                        -SshPort $SshPort `
                        -SshConnectTimeoutSeconds $SshConnectTimeoutSeconds `
                        -ConfiguredPySshClientPath $ConfiguredPySshClientPath `
                        -ManagerUser ([string]$ManagerUser) `
                        -AssistantUser ([string]$AssistantUser)
                }
                catch {
                    Write-Warning ("App-state deferred flush failed: {0}" -f $_.Exception.Message)
                    $flushResult = [pscustomobject]@{
                        RemainingTasks = @($pendingAppStateTaskBlocks.ToArray())
                        WarningTasks = @()
                    }
                }

                $pendingAppStateTaskBlocks = New-Object 'System.Collections.Generic.List[object]'
                foreach ($remainingTask in @($flushResult.RemainingTasks)) {
                    if ($null -ne $remainingTask) {
                        $pendingAppStateTaskBlocks.Add($remainingTask) | Out-Null
                    }
                }
                foreach ($warningTask in @($flushResult.WarningTasks)) {
                    if (-not [string]::IsNullOrWhiteSpace([string]$warningTask)) {
                        $totalWarnings++
                        $warningTasks += [string]$warningTask
                    }
                }
                foreach ($remainingTask in @($pendingAppStateTaskBlocks.ToArray())) {
                    if ($null -eq $remainingTask) {
                        continue
                    }

                    $remainingTaskName = if ($remainingTask.PSObject.Properties.Match('Name').Count -gt 0) { [string]$remainingTask.Name } else { '(unknown-task)' }
                    if (-not $deferredAppStateTasks.ContainsKey($remainingTaskName)) {
                        Write-Host ("App-state deferred: {0} => waiting for SSH readiness." -f [string]$remainingTaskName) -ForegroundColor Yellow
                        $deferredAppStateTasks[$remainingTaskName] = $true
                    }
                }
            }
        }
        else {
            $failedTasks += $taskName
            if ([string]::Equals([string]$TaskOutcomeMode, 'continue', [System.StringComparison]::OrdinalIgnoreCase)) {
                $totalWarnings += [Math]::Max([int]$taskResult.WarningCount + [int]$taskResult.ErrorCount, 1)
                $warningTasks += ("{0} => task-result" -f [string]$taskName)
                continue
            }

            $totalErrors += [Math]::Max([int]$taskResult.ErrorCount, 1)
            throw ("VM init task failed: {0}" -f [string]$taskName)
        }

        if ([bool]$taskResult.RebootRequired) {
            $rebootCount++
            $rebootRequestedTasks += $taskName
            $restartRequiresSsh = ($pendingAppStateTaskBlocks.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$SshPort))
            $null = Invoke-ClagnosRestartAndWait `
                -ResourceGroup ([string]$ResourceGroup) `
                -VmName ([string]$VmName) `
                -StartMessage ("Task '{0}' requested a restart. Restarting VM now..." -f [string]$taskName) `
                -SuccessMessage ("VM restart completed successfully after task '{0}'." -f [string]$taskName) `
                -RunningFailureSummary 'VM could not be restarted after a vm-init task.' `
                -RunningFailureHint 'Check the VM in Azure Portal and rerun vm-init after the guest returns to running state.' `
                -ProvisioningFailureSummary 'VM restart recovery after a vm-init task did not complete successfully.' `
                -ProvisioningFailureHint 'Check provisioning status and guest boot health before rerunning vm-init.' `
                -HostFailureSummary 'VM restart after a vm-init task completed, but SSH host resolution failed.' `
                -HostFailureHint 'Verify that the managed VM still has a reachable public IP or FQDN.' `
                -SshFailureSummary 'VM restart after a vm-init task completed, but SSH did not recover in time.' `
                -SshFailureHint 'Verify guest startup health and rerun vm-init after SSH becomes reachable.' `
                -SshPort ([int]$SshPort) `
                -SshConnectTimeoutSeconds $SshConnectTimeoutSeconds `
                -RequireSsh:$restartRequiresSsh

            if ($pendingAppStateTaskBlocks.Count -gt 0) {
                try {
                    $postRestartFlushResult = Invoke-ClagnosRunCommandDeferredAppStateFlush `
                        -Platform $Platform `
                        -RepoRoot $RepoRoot `
                        -PendingTaskBlocks @($pendingAppStateTaskBlocks.ToArray()) `
                        -SshHost $SshHost `
                        -SshUser $SshUser `
                        -SshPassword $SshPassword `
                        -SshPort $SshPort `
                        -SshConnectTimeoutSeconds $SshConnectTimeoutSeconds `
                        -ConfiguredPySshClientPath $ConfiguredPySshClientPath `
                        -ManagerUser ([string]$ManagerUser) `
                        -AssistantUser ([string]$AssistantUser) `
                        -AllowWait
                }
                catch {
                    Write-Warning ("App-state flush after restart failed: {0}" -f $_.Exception.Message)
                    $postRestartFlushResult = [pscustomobject]@{
                        RemainingTasks = @($pendingAppStateTaskBlocks.ToArray())
                        WarningTasks = @()
                    }
                }

                $pendingAppStateTaskBlocks = New-Object 'System.Collections.Generic.List[object]'
                foreach ($remainingTask in @($postRestartFlushResult.RemainingTasks)) {
                    if ($null -ne $remainingTask) {
                        $pendingAppStateTaskBlocks.Add($remainingTask) | Out-Null
                    }
                }
                foreach ($warningTask in @($postRestartFlushResult.WarningTasks)) {
                    if (-not [string]::IsNullOrWhiteSpace([string]$warningTask)) {
                        $totalWarnings++
                        $warningTasks += [string]$warningTask
                    }
                }
            }
        }
    }

    if ($pendingAppStateTaskBlocks.Count -gt 0) {
        try {
            $finalFlushResult = Invoke-ClagnosRunCommandDeferredAppStateFlush `
                -Platform $Platform `
                -RepoRoot $RepoRoot `
                -PendingTaskBlocks @($pendingAppStateTaskBlocks.ToArray()) `
                -SshHost $SshHost `
                -SshUser $SshUser `
                -SshPassword $SshPassword `
                -SshPort $SshPort `
                -SshConnectTimeoutSeconds $SshConnectTimeoutSeconds `
                -ConfiguredPySshClientPath $ConfiguredPySshClientPath `
                -ManagerUser ([string]$ManagerUser) `
                -AssistantUser ([string]$AssistantUser) `
                -AllowWait
        }
        catch {
            Write-Warning ("App-state final flush failed: {0}" -f $_.Exception.Message)
            $finalFlushResult = [pscustomobject]@{
                RemainingTasks = @($pendingAppStateTaskBlocks.ToArray())
                WarningTasks = @()
            }
        }

        foreach ($warningTask in @($finalFlushResult.WarningTasks)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$warningTask)) {
                $totalWarnings++
                $warningTasks += [string]$warningTask
            }
        }
        foreach ($remainingTask in @($finalFlushResult.RemainingTasks)) {
            if ($null -eq $remainingTask) {
                continue
            }

            $remainingTaskName = if ($remainingTask.PSObject.Properties.Match('Name').Count -gt 0) { [string]$remainingTask.Name } else { '(unknown-task)' }
            $totalWarnings++
            $warningTasks += ("{0} => app-state-deferred" -f [string]$remainingTaskName)
            Write-Warning ("App-state warning: {0} => SSH was not ready before vm-init completed." -f [string]$remainingTaskName)
        }
    }

    $uniqueSuccessfulTasks = @($successfulTasks | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
    $uniqueFailedTasks = @($failedTasks | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
    $uniqueWarningTasks = @($warningTasks | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)

    Write-Host ("VM init stage summary: success={0}, failed={1}, warning={2}, error={3}, reboot={4}" -f @($uniqueSuccessfulTasks).Count, @($uniqueFailedTasks).Count, $totalWarnings, $totalErrors, $rebootCount)
    if (@($uniqueWarningTasks).Count -gt 0) {
        Write-Host 'Warning tasks:' -ForegroundColor Yellow
        foreach ($warningTask in @($uniqueWarningTasks)) {
            Write-Host ("- {0}" -f [string]$warningTask) -ForegroundColor Yellow
        }
    }
    if (@($uniqueFailedTasks).Count -gt 0) {
        Write-Host 'Failed tasks:' -ForegroundColor Yellow
        foreach ($failedTaskName in @($uniqueFailedTasks)) {
            Write-Host ("- {0}" -f [string]$failedTaskName) -ForegroundColor Yellow
        }
    }
    if ($rebootCount -gt 0) {
        $rebootTaskList = @($rebootRequestedTasks | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
        if (@($rebootTaskList).Count -eq 0) {
            $rebootTaskList = @('(task names unavailable)')
        }
        Write-Host 'VM init automatic restarts were completed after reboot-signaling tasks.' -ForegroundColor Cyan
        Write-Host 'Restarted after tasks:' -ForegroundColor Cyan
        foreach ($rebootTaskName in @($rebootTaskList)) {
            Write-Host ("- {0}" -f [string]$rebootTaskName) -ForegroundColor Cyan
        }
    }
    if (-not [string]::Equals([string]$PerfTaskCategory, 'task-run', [System.StringComparison]::OrdinalIgnoreCase)) {
        if ($stageWatch.IsRunning) { $stageWatch.Stop() }
        Write-ClagnosTaskStageHistoryRecord `
            -Stage 'init' `
            -Platform $Platform `
            -ResourceGroup $ResourceGroup `
            -VmName $VmName `
            -TaskNames @($TaskBlocks | ForEach-Object { [string]$_.Name }) `
            -FailedTasks @($uniqueFailedTasks) `
            -WarningTasks @($uniqueWarningTasks) `
            -DeferredAppStateTasks @($pendingAppStateTaskBlocks | ForEach-Object { [string]$_.Name }) `
            -SuccessCount @($uniqueSuccessfulTasks).Count `
            -ErrorCount $totalErrors `
            -RebootCount $rebootCount `
            -DurationSeconds $stageWatch.Elapsed.TotalSeconds
    }
    if ([string]::Equals([string]$TaskOutcomeMode, 'strict', [System.StringComparison]::OrdinalIgnoreCase) -and ($totalWarnings -gt 0 -or $totalErrors -gt 0)) {
        throw ("VM init strict task outcome mode blocked continuation: warning={0}, error={1}" -f $totalWarnings, $totalErrors)
    }

    $pendingAppStateTaskArray = $pendingAppStateTaskBlocks.ToArray()
    return [pscustomobject]@{
        SuccessCount = $totalSuccess
        WarningCount = $totalWarnings
        ErrorCount = $totalErrors
        RebootCount = $rebootCount
        DeferredAppStateCount = $pendingAppStateTaskArray.Count
        DeferredAppStateTasks = @($pendingAppStateTaskArray | ForEach-Object { [string]$_.Name } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        RebootRequired = $false
        NextTaskIndex = [int]$processedTaskCount
        TaskDurations = @()
    }
}
