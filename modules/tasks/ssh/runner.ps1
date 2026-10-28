# Persistent SSH task runner.

# Handles Invoke-ProdicloudPersistentSshTask.
function Invoke-ProdicloudPersistentSshTask {
    param(
        [psobject]$Session,
        [string]$TaskName,
        [string]$TaskScript,
        [int]$TimeoutSeconds = 1800
    )

    if ($null -eq $Session -or $null -eq $Session.Process) {
        throw "Persistent SSH session is not initialized."
    }
    if ($Session.Process.HasExited) {
        $stdoutTail = ""
        $stderrTail = ""
        try { $stdoutTail = [string]$Session.Process.StandardOutput.ReadToEnd() } catch { }
        try { $stderrTail = [string]$Session.Process.StandardError.ReadToEnd() } catch { }
        $detail = ""
        if (-not [string]::IsNullOrWhiteSpace($stdoutTail)) { $detail += (" stdout={0}" -f $stdoutTail.Trim()) }
        if (-not [string]::IsNullOrWhiteSpace($stderrTail)) { $detail += (" stderr={0}" -f $stderrTail.Trim()) }
        throw ("Persistent SSH session process has already exited (code={0}).{1}" -f $Session.Process.ExitCode, $detail)
    }
    if ($TimeoutSeconds -lt 5) { $TimeoutSeconds = 5 }

    $payload = [ordered]@{
        action = "run"
        task = [string]$TaskName
        timeout = [int]$TimeoutSeconds
        script = [string]$TaskScript
    } | ConvertTo-Json -Compress -Depth 20

    Write-ProdicloudPersistentSshProtocolLine -Session $Session -Line ([string]$payload)

    $proc = $Session.Process
    $stdoutReader = $Session.StdoutReader
    if ($null -eq $stdoutReader) {
        $stdoutReader = $proc.StandardOutput
        $Session.StdoutReader = $stdoutReader
    }
    $stderrReader = $Session.StderrReader
    if ($null -eq $stderrReader) {
        $stderrReader = $proc.StandardError
        $Session.StderrReader = $stderrReader
    }

    if ($null -eq $Session.PendingStdoutTask) {
        $Session.PendingStdoutTask = $stdoutReader.ReadLineAsync()
    }
    if ($null -eq $Session.PendingStderrTask) {
        $Session.PendingStderrTask = $stderrReader.ReadLineAsync()
    }
    $outputLines = New-Object 'System.Collections.Generic.List[string]'
    $endMarkerRegex = '^PRODICLOUD_TASK_END:(?<task>.+?):(?<code>-?\d+)$'
    $beginMarkerRegex = '^PRODICLOUD_TASK_BEGIN:(?<task>.+)$'
    $taskWatch = [System.Diagnostics.Stopwatch]::StartNew()
    $exitCode = $null

    while ($null -eq $exitCode) {
        $stdoutTask = $Session.PendingStdoutTask
        $stderrTask = $Session.PendingStderrTask
        $completedIndex = [System.Threading.Tasks.Task]::WaitAny(@($stdoutTask, $stderrTask), 250)

        if ($completedIndex -eq 0) {
            $line = $stdoutTask.Result
            $Session.PendingStdoutTask = $stdoutReader.ReadLineAsync()
            if ($null -ne $line) {
                $lineText = [string]$line
                $normalizedLine = Normalize-ProdicloudProtocolLine -Text $lineText
                if ($null -eq $normalizedLine) { $normalizedLine = "" }
                if (($normalizedLine -as [string]) -like "PRODICLOUD_SESSION_ERROR:*") {
                    throw ("Persistent SSH session reported protocol error for task '{0}': {1}" -f $TaskName, [string]$normalizedLine)
                }
                if ($normalizedLine -match $endMarkerRegex) {
                    $markerTask = [string]$Matches.task
                    if ([string]::Equals($markerTask, [string]$TaskName, [System.StringComparison]::OrdinalIgnoreCase)) {
                        $exitCode = Convert-ProdicloudProtocolTaskExitCode -Text ([string]$Matches.code)
                        break
                    }
                    continue
                }
                if ($normalizedLine -match $beginMarkerRegex) {
                    continue
                }
                if (Test-ProdicloudTaskOutputNoiseLine -Text ([string]$normalizedLine)) {
                    continue
                }
                if (Test-ProdicloudTransientSpinnerLine -Text ([string]$normalizedLine)) {
                    Write-ProdicloudTransientConsoleText -Text ([string]$normalizedLine)
                    $Session.TransientConsoleActive = $true
                    continue
                }
                if ([string]::IsNullOrWhiteSpace([string]$normalizedLine)) {
                    continue
                }
                if ($Session.TransientConsoleActive) {
                    Clear-ProdicloudTransientConsoleText
                    $Session.TransientConsoleActive = $false
                }
                [void]$outputLines.Add([string]$normalizedLine)
                Write-Host ([string]$normalizedLine)
            }
        }
        elseif ($completedIndex -eq 1) {
            $line = $stderrTask.Result
            $Session.PendingStderrTask = $stderrReader.ReadLineAsync()
            if ($null -ne $line) {
                $lineText = [string]$line
                $normalizedLine = Normalize-ProdicloudProtocolLine -Text $lineText
                if ($null -eq $normalizedLine) { $normalizedLine = "" }
                if (Test-ProdicloudTaskOutputNoiseLine -Text ([string]$normalizedLine)) {
                    continue
                }
                if (Test-ProdicloudTransientSpinnerLine -Text ([string]$normalizedLine)) {
                    Write-ProdicloudTransientConsoleText -Text ([string]$normalizedLine)
                    $Session.TransientConsoleActive = $true
                    continue
                }
                if ([string]::IsNullOrWhiteSpace([string]$normalizedLine)) {
                    continue
                }
                if ($Session.TransientConsoleActive) {
                    Clear-ProdicloudTransientConsoleText
                    $Session.TransientConsoleActive = $false
                }
                [void]$outputLines.Add([string]$normalizedLine)
                Write-Warning ([string]$normalizedLine)
            }
        }

        if ($proc.HasExited -and $null -eq $exitCode) {
            $stdoutTail = ""
            $stderrTail = ""
            try { $stdoutTail = [string]$stdoutReader.ReadToEnd() } catch { }
            try { $stderrTail = [string]$stderrReader.ReadToEnd() } catch { }
            if (-not [string]::IsNullOrWhiteSpace($stdoutTail)) {
                foreach ($line in ($stdoutTail -split "`r?`n")) {
                    $normalizedTailLine = Normalize-ProdicloudProtocolLine -Text ([string]$line)
                    if ([string]::IsNullOrWhiteSpace($normalizedTailLine)) { continue }
                    if (($normalizedTailLine -as [string]) -like "PRODICLOUD_SESSION_ERROR:*") {
                        throw ("Persistent SSH session reported protocol error for task '{0}': {1}" -f $TaskName, [string]$normalizedTailLine)
                    }
                    if ($normalizedTailLine -match $beginMarkerRegex) { continue }
                    if ($normalizedTailLine -match $endMarkerRegex) { continue }
                    if (Test-ProdicloudTaskOutputNoiseLine -Text ([string]$normalizedTailLine)) { continue }
                    if (Test-ProdicloudTransientSpinnerLine -Text ([string]$normalizedTailLine)) {
                        Write-ProdicloudTransientConsoleText -Text ([string]$normalizedTailLine)
                        $Session.TransientConsoleActive = $true
                        continue
                    }
                    if ($Session.TransientConsoleActive) {
                        Clear-ProdicloudTransientConsoleText
                        $Session.TransientConsoleActive = $false
                    }
                    [void]$outputLines.Add([string]$normalizedTailLine)
                    Write-Host ([string]$normalizedTailLine)
                }
            }
            if (-not [string]::IsNullOrWhiteSpace($stderrTail)) {
                foreach ($line in ($stderrTail -split "`r?`n")) {
                    $normalizedTailLine = Normalize-ProdicloudProtocolLine -Text ([string]$line)
                    if ([string]::IsNullOrWhiteSpace($normalizedTailLine)) { continue }
                    if (Test-ProdicloudTaskOutputNoiseLine -Text ([string]$normalizedTailLine)) { continue }
                    if (Test-ProdicloudTransientSpinnerLine -Text ([string]$normalizedTailLine)) {
                        Write-ProdicloudTransientConsoleText -Text ([string]$normalizedTailLine)
                        $Session.TransientConsoleActive = $true
                        continue
                    }
                    if ($Session.TransientConsoleActive) {
                        Clear-ProdicloudTransientConsoleText
                        $Session.TransientConsoleActive = $false
                    }
                    [void]$outputLines.Add([string]$normalizedTailLine)
                    Write-Warning ([string]$normalizedTailLine)
                }
            }
            throw ("Persistent SSH session process exited before task completion (code={0})." -f $proc.ExitCode)
        }
        if ($taskWatch.Elapsed.TotalSeconds -gt ($TimeoutSeconds + 60)) {
            throw ("Persistent SSH task timeout guard reached for '{0}'." -f $TaskName)
        }
    }

    if ($taskWatch.IsRunning) { $taskWatch.Stop() }
    if ($Session.TransientConsoleActive) {
        Clear-ProdicloudTransientConsoleText
        $Session.TransientConsoleActive = $false
    }
    return [pscustomobject]@{
        ExitCode = [int]$exitCode
        Output = ($outputLines -join "`n")
        DurationSeconds = [double]$taskWatch.Elapsed.TotalSeconds
        OutputRelayedLive = $true
    }
}
