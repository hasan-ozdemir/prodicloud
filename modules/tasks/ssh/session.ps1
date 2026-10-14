# SSH session lifecycle helpers.

# Handles Initialize-ClagnosSshHostKey.
function Initialize-ClagnosSshHostKey {
    param(
        [string]$PySshPythonPath,
        [string]$PySshClientPath,
        [string]$HostName,
        [string]$UserName,
        [string]$Password,
        [string]$Port,
        [int]$ConnectTimeoutSeconds = 30,
        [switch]$Force
    )

    if ($ConnectTimeoutSeconds -lt 5) { $ConnectTimeoutSeconds = 5 }
    if ($ConnectTimeoutSeconds -gt 300) { $ConnectTimeoutSeconds = 300 }
    if ([string]::IsNullOrWhiteSpace([string]$PySshPythonPath) -or -not (Test-Path -LiteralPath $PySshPythonPath)) {
        throw "Python executable for pyssh was not found."
    }

    if ($null -eq $script:ClagnosSshBootstrapCache) { $script:ClagnosSshBootstrapCache = @{} }
    $passwordBytes = [System.Text.Encoding]::UTF8.GetBytes([string]$Password)
    $passwordSha = [System.Security.Cryptography.SHA256]::Create()
    try { $passwordFingerprint = ([BitConverter]::ToString($passwordSha.ComputeHash($passwordBytes))).Replace('-', '').ToLowerInvariant() }
    finally { $passwordSha.Dispose() }
    $cacheKey = ('{0}|{1}|{2}|{3}|{4}|{5}' -f [string]$HostName.ToLowerInvariant(),[string]$Port,[string]$UserName.ToLowerInvariant(),[string]$PySshPythonPath,[string]$PySshClientPath,$passwordFingerprint)
    $cacheTtlSeconds = if ([int]$script:ClagnosSshBootstrapCacheTtlSeconds -gt 0) { [int]$script:ClagnosSshBootstrapCacheTtlSeconds } else { 20 }
    foreach ($staleKey in @($script:ClagnosSshBootstrapCache.Keys)) {
        if (([DateTime]::UtcNow - [DateTime]$script:ClagnosSshBootstrapCache[$staleKey].CreatedAtUtc).TotalSeconds -ge $cacheTtlSeconds) {
            $script:ClagnosSshBootstrapCache.Remove([string]$staleKey)
        }
    }
    if (-not $Force -and $script:ClagnosSshBootstrapCache.ContainsKey($cacheKey)) {
        $cached = $script:ClagnosSshBootstrapCache[$cacheKey]
        return [pscustomobject]@{ ExitCode = 0; Output = ''; HostKey = [string]$cached.HostKey; Cached = $true }
    }

    $result = Invoke-ClagnosProcessWithRetry `
        -FilePath $PySshPythonPath `
        -Arguments @(
            $PySshClientPath,
            "exec",
            "--host", [string]$HostName,
            "--port", [string]$Port,
            "--user", [string]$UserName,
            "--password", [string]$Password,
            "--timeout", [string]$ConnectTimeoutSeconds,
            "--command", "whoami"
        ) `
        -Label "pyssh connection bootstrap" `
        -MaxAttempts 1 `
        -AllowFailure

    if ($result.ExitCode -ne 0) {
        Write-Warning "Python SSH bootstrap returned non-zero exit code. Continuing and allowing retry flow."
    }
    else {
        $script:ClagnosSshBootstrapCache[$cacheKey] = @{ CreatedAtUtc = [DateTime]::UtcNow; HostKey = 'auto-add' }
    }

    return [pscustomobject]@{
        ExitCode = [int]$result.ExitCode
        Output = [string]$result.Output
        HostKey = "auto-add"
        Cached = $false
    }
}

# Handles Start-ClagnosPersistentSshSession.
function Start-ClagnosPersistentSshSession {
    param(
        [string]$PySshPythonPath,
        [string]$PySshClientPath,
        [string]$HostName,
        [string]$UserName,
        [string]$Password,
        [string]$Port,
        [ValidateSet("powershell", "bash")]
        [string]$Shell = "powershell",
        [int]$ConnectTimeoutSeconds = 30,
        [int]$DefaultTaskTimeoutSeconds = 1800
    )

    if ([string]::IsNullOrWhiteSpace($PySshClientPath) -or -not (Test-Path -LiteralPath $PySshClientPath)) {
        throw "Persistent SSH session could not start because pyssh client path is invalid."
    }
    if ([string]::IsNullOrWhiteSpace([string]$PySshPythonPath) -or -not (Test-Path -LiteralPath $PySshPythonPath)) {
        throw "Persistent SSH session could not start because pyssh python executable is invalid."
    }
    if ($ConnectTimeoutSeconds -lt 5) { $ConnectTimeoutSeconds = 5 }
    if ($DefaultTaskTimeoutSeconds -lt 5) { $DefaultTaskTimeoutSeconds = 5 }

    $argList = @(
        "-B",
        [string]$PySshClientPath,
        "session",
        "--host", [string]$HostName,
        "--port", [string]$Port,
        "--user", [string]$UserName,
        "--password", [string]$Password,
        "--timeout", [string]$ConnectTimeoutSeconds,
        "--task-timeout", [string]$DefaultTaskTimeoutSeconds,
        "--shell", [string]$Shell
    )
    $argText = ($argList | ForEach-Object { Convert-ClagnosProcessArgument -Value ([string]$_) }) -join ' '

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = [string]$PySshPythonPath
    $psi.Arguments = $argText
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $null = $psi.EnvironmentVariables
    $psi.EnvironmentVariables["PYTHONDONTWRITEBYTECODE"] = "1"
    $psiType = $psi.GetType()
    if ($psiType.GetProperty("StandardInputEncoding")) {
        try { $psi.StandardInputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }
    }
    if ($psiType.GetProperty("StandardOutputEncoding")) {
        try { $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
    }
    if ($psiType.GetProperty("StandardErrorEncoding")) {
        try { $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8 } catch { }
    }

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi

    if (-not $proc.Start()) {
        throw "Persistent SSH python process could not be started."
    }

    return [pscustomobject]@{
        Process = $proc
        StdoutReader = $proc.StandardOutput
        StderrReader = $proc.StandardError
        PendingStdoutTask = $null
        PendingStderrTask = $null
        TransientConsoleActive = $false
        HostName = [string]$HostName
        UserName = [string]$UserName
        Port = [string]$Port
        Shell = [string]$Shell
        DefaultTaskTimeoutSeconds = [int]$DefaultTaskTimeoutSeconds
    }
}

# Handles Write-ClagnosPersistentSshProtocolLine.
function Write-ClagnosPersistentSshProtocolLine {
    param(
        [psobject]$Session,
        [string]$Line
    )

    if ($null -eq $Session -or $null -eq $Session.Process) {
        throw "Persistent SSH session is not initialized."
    }
    if ($Session.Process.HasExited) {
        throw ("Persistent SSH session process has already exited (code={0})." -f $Session.Process.ExitCode)
    }

    $text = [string]$Line
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($text + "`n")
    $stream = $Session.Process.StandardInput.BaseStream
    $stream.Write($bytes, 0, $bytes.Length)
    $stream.Flush()
}

# Handles Stop-ClagnosPersistentSshSession.
function Stop-ClagnosPersistentSshSession {
    param(
        [psobject]$Session
    )

    if ($null -eq $Session) {
        return
    }

    if ($Session.PSObject.Properties.Match('TransientConsoleActive').Count -gt 0 -and [bool]$Session.TransientConsoleActive) {
        Clear-ClagnosTransientConsoleText
        $Session.TransientConsoleActive = $false
    }

    $proc = $Session.Process
    if ($null -ne $proc) {
        try {
            if (-not $proc.HasExited) {
                try {
                    $closePayload = @{ action = "close" } | ConvertTo-Json -Compress
                    Write-ClagnosPersistentSshProtocolLine -Session $Session -Line ([string]$closePayload)
                    $proc.StandardInput.Close()
                }
                catch { }

                if (-not $proc.WaitForExit(5000)) {
                    try { $proc.Kill() } catch { }
                    [void]$proc.WaitForExit(2000)
                }
            }
        }
        finally {
            try { $proc.Dispose() } catch { }
        }
    }
}

# Handles Test-ClagnosPersistentSshSessionUsable.
function Test-ClagnosPersistentSshSessionUsable {
    param(
        [psobject]$Session
    )

    if ($null -eq $Session -or $null -eq $Session.Process) {
        return $false
    }

    try {
        return (-not $Session.Process.HasExited)
    }
    catch {
        return $false
    }
}

# Handles Invoke-ClagnosOneShotSshTask.
function Invoke-ClagnosOneShotSshTask {
    param(
        [string]$PySshPythonPath,
        [string]$PySshClientPath,
        [string]$HostName,
        [string]$UserName,
        [string]$Password,
        [string]$Port,
        [ValidateSet('powershell','bash')]
        [string]$Shell = 'powershell',
        [string]$TaskName,
        [string]$TaskScript,
        [int]$TimeoutSeconds = 1800,
        [switch]$SkipRemoteCleanup
    )

    if ([string]::IsNullOrWhiteSpace([string]$PySshClientPath) -or -not (Test-Path -LiteralPath $PySshClientPath)) {
        throw "One-shot SSH task execution could not start because pyssh client path is invalid."
    }
    if ([string]::IsNullOrWhiteSpace([string]$PySshPythonPath) -or -not (Test-Path -LiteralPath $PySshPythonPath)) {
        throw "One-shot SSH task execution could not start because pyssh python executable is invalid."
    }
    if ($TimeoutSeconds -lt 5) { $TimeoutSeconds = 5 }
    if ($TimeoutSeconds -gt 7200) { $TimeoutSeconds = 7200 }

    $safeTaskName = ([string]$TaskName -replace '[^A-Za-z0-9\-]', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace([string]$safeTaskName)) {
        $safeTaskName = 'task'
    }

    $scriptPayload = [string]$TaskScript
    if (-not [string]::IsNullOrEmpty([string]$scriptPayload) -and -not $scriptPayload.EndsWith("`n")) {
        $scriptPayload += "`n"
    }

    $extension = if ($Shell -eq 'bash') { 'sh' } else { 'ps1' }
    $localTempPath = Join-Path ([System.IO.Path]::GetTempPath()) ('clagnos-task-{0}-{1}.{2}' -f $safeTaskName, ([guid]::NewGuid().ToString('N')), $extension)
    $remoteScriptPath = if ($Shell -eq 'bash') {
        '/tmp/clagnos-task-{0}.sh' -f ([guid]::NewGuid().ToString('N'))
    }
    else {
        'C:/Windows/Temp/clagnos-task-{0}.ps1' -f ([guid]::NewGuid().ToString('N'))
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($localTempPath, $scriptPayload, $utf8NoBom)

    try {
        Copy-ClagnosAssetToVm `
            -PySshPythonPath $PySshPythonPath `
            -PySshClientPath $PySshClientPath `
            -HostName $HostName `
            -UserName $UserName `
            -Password $Password `
            -Port $Port `
            -LocalPath $localTempPath `
            -RemotePath $remoteScriptPath `
            -ConnectTimeoutSeconds $TimeoutSeconds | Out-Null

        $commandText = if ($Shell -eq 'bash') {
            'bash "{0}"' -f [string]$remoteScriptPath
        }
        else {
            'powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}"' -f [string]$remoteScriptPath
        }

        $result = Invoke-ClagnosProcessWithRetry `
            -FilePath $PySshPythonPath `
            -Arguments @(
                $PySshClientPath,
                'exec',
                '--host', [string]$HostName,
                '--port', [string]$Port,
                '--user', [string]$UserName,
                '--password', [string]$Password,
                '--timeout', [string]$TimeoutSeconds,
                '--command', [string]$commandText
            ) `
            -Label ("pyssh one-shot task -> {0}" -f [string]$TaskName) `
            -MaxAttempts 1 `
            -AllowFailure `
            -RelayOutput

        return [pscustomobject]@{
            ExitCode = [int]$result.ExitCode
            Output = [string]$result.Output
            DurationSeconds = 0.0
            ExecutionMode = 'one-shot'
            OutputRelayedLive = ($result.PSObject.Properties.Match('OutputRelayedLive').Count -gt 0 -and [bool]$result.OutputRelayedLive)
        }
    }
    finally {
        if (Test-Path -LiteralPath $localTempPath) {
            Remove-Item -LiteralPath $localTempPath -Force -ErrorAction SilentlyContinue
        }

        if (-not $SkipRemoteCleanup) {
            try {
                $cleanupCommand = if ($Shell -eq 'bash') {
                    'bash -lc "rm -f ''{0}''"' -f [string]$remoteScriptPath
                }
                else {
                    'powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "Remove-Item -LiteralPath ''{0}'' -Force -ErrorAction SilentlyContinue"' -f [string]$remoteScriptPath
                }

                Invoke-ClagnosProcessWithRetry `
                    -FilePath $PySshPythonPath `
                    -Arguments @(
                        $PySshClientPath,
                        'exec',
                        '--host', [string]$HostName,
                        '--port', [string]$Port,
                        '--user', [string]$UserName,
                        '--password', [string]$Password,
                        '--timeout', '30',
                        '--command', [string]$cleanupCommand
                    ) `
                    -Label ("pyssh cleanup task -> {0}" -f [string]$TaskName) `
                    -MaxAttempts 1 `
                    -AllowFailure | Out-Null
            }
            catch { }
        }
    }
}

# Handles Invoke-ClagnosSshTaskScript.
function Invoke-ClagnosSshTaskScript {
    param(
        [psobject]$Session,
        [string]$PySshPythonPath,
        [string]$PySshClientPath,
        [string]$HostName,
        [string]$UserName,
        [string]$Password,
        [string]$Port,
        [ValidateSet('powershell','bash')]
        [string]$Shell = 'powershell',
        [string]$TaskName,
        [string]$TaskScript,
        [int]$TimeoutSeconds = 1800,
        [switch]$SkipRemoteCleanup
    )

    if (Test-ClagnosPersistentSshSessionUsable -Session $Session) {
        return (Invoke-ClagnosPersistentSshTask -Session $Session -TaskName $TaskName -TaskScript $TaskScript -TimeoutSeconds $TimeoutSeconds)
    }

    return (Invoke-ClagnosOneShotSshTask `
        -PySshPythonPath $PySshPythonPath `
        -PySshClientPath $PySshClientPath `
        -HostName $HostName `
        -UserName $UserName `
        -Password $Password `
        -Port $Port `
        -Shell $Shell `
        -TaskName $TaskName `
        -TaskScript $TaskScript `
        -TimeoutSeconds $TimeoutSeconds `
        -SkipRemoteCleanup:$SkipRemoteCleanup)
}

# Handles Test-ClagnosSshTransportRecoverySignal.
function Test-ClagnosSshTransportRecoverySignal {
    param(
        [AllowNull()]
        [string]$Text
    )

    if ([string]::IsNullOrWhiteSpace([string]$Text)) {
        return $false
    }

    $value = [string]$Text
    foreach ($pattern in @(
        'Starting the CLR failed with HRESULT',
        'Thread failed to start',
        'System.Management.Automation.RemoteException',
        'EOF during negotiation',
        'CLAGNOS_SESSION_TASK_ERROR:',
        'CLAGNOS_SESSION_ERROR:'
    )) {
        if ($value.IndexOf($pattern, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            return $true
        }
    }

    return $false
}
