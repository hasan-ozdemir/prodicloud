$ErrorActionPreference = "Stop"
Write-Host "Update task started: install-ollama-tool"

$taskConfig = [ordered]@{
    ChocoExecutableFallbackCandidates = @(
        'C:\ProgramData\chocolatey\bin\choco.exe'
    )
    WingetExecutableFallbackCandidates = @(
        'C:\ProgramData\clagnos\tools\winget-x64\winget.exe'
    )
    ChocoPackageId = 'ollama'
    WingetPackageId = 'Ollama.Ollama'
    ManagerUser = '__VM_ADMIN_USER__'
    AssistantUser = '__ASSISTANT_USER__'
    OllamaApiVersionUris = @(
        'http://127.0.0.1:11434/api/version',
        'http://localhost:11434/api/version'
    )
    OllamaExecutableFallbackCandidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama.exe'),
        'C:\Program Files\Ollama\ollama.exe'
    )
    OllamaApiPort = 11434
    WingetInstallTimeoutSeconds = 240
    OllamaExeWaitTimeoutSeconds = 45
    OllamaExeWaitPollSeconds = 3
    OllamaBootstrapSettleSeconds = 2
    OllamaBootstrapValidationTimeoutSeconds = 20
    OllamaServeSettleSeconds = 2
    OllamaListProbeTimeoutSeconds = 20
    OllamaListWaitTimeoutSeconds = 90
    OllamaListRetryDelaySeconds = 4
    OllamaProcessWaitTimeoutSeconds = 30
    OllamaProcessPollSeconds = 2
    OllamaApiWaitTimeoutSeconds = 90
    OllamaApiProbeTimeoutSeconds = 5
    OllamaApiProbeDelayMilliseconds = 1000
    LogTailLineCount = 12
}

Import-Module 'C:\Windows\Temp\clagnos-session-environment.psm1' -Force -DisableNameChecking

function Refresh-SessionPath {
    Refresh-ClagnosSessionPath | Out-Null
}

function Resolve-CommandFromCandidates {
    param(
        [string[]]$CommandNames = @(),
        [string[]]$PathCandidates = @()
    )

    foreach ($commandName in @($CommandNames)) {
        if ([string]::IsNullOrWhiteSpace([string]$commandName)) {
            continue
        }

        $cmd = Get-Command $commandName -ErrorAction SilentlyContinue
        if ($cmd -and -not [string]::IsNullOrWhiteSpace([string]$cmd.Source)) {
            return [string]$cmd.Source
        }
    }

    foreach ($candidate in @($PathCandidates)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$candidate) -and (Test-Path -LiteralPath $candidate)) {
            return [string]$candidate
        }
    }

    return ''
}

function Resolve-ChocoExe {
    return (Resolve-CommandFromCandidates -CommandNames @('choco.exe', 'choco') -PathCandidates @($taskConfig.ChocoExecutableFallbackCandidates))
}

function Resolve-WingetExe {
    return (Resolve-CommandFromCandidates -CommandNames @('winget.exe', 'winget') -PathCandidates @($taskConfig.WingetExecutableFallbackCandidates))
}

function Resolve-OllamaExe {
    return (Resolve-CommandFromCandidates -CommandNames @('ollama.exe', 'ollama') -PathCandidates @($taskConfig.OllamaExecutableFallbackCandidates))
}

function Resolve-CmdExe {
    return (Resolve-CommandFromCandidates -CommandNames @('cmd.exe', 'cmd') -PathCandidates @((Join-Path $env:WINDIR 'System32\cmd.exe')))
}

function Get-LogTailText {
    param(
        [string]$Path,
        [int]$LineCount = 12
    )

    if ([string]::IsNullOrWhiteSpace([string]$Path) -or -not (Test-Path -LiteralPath $Path)) {
        return ''
    }

    try {
        $tailLines = @(Get-Content -LiteralPath $Path -Tail $LineCount -ErrorAction Stop)
        if (@($tailLines).Count -eq 0) {
            return ''
        }

        return ([string](($tailLines -join ' | ') -replace '\s+', ' ')).Trim()
    }
    catch {
        return ''
    }
}

function Invoke-ProcessWithTimeout {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [string[]]$ArgumentList = @(),
        [int]$TimeoutSeconds = 600,
        [string]$Label = 'process'
    )

    $logRoot = Join-Path $env:TEMP 'clagnos-ollama'
    [void](New-Item -ItemType Directory -Path $logRoot -Force)
    $stamp = Get-Date -Format 'yyyyMMddHHmmss'
    $stdoutLog = Join-Path $logRoot ("{0}-{1}.stdout.log" -f $Label.Replace(' ', '-'), $stamp)
    $stderrLog = Join-Path $logRoot ("{0}-{1}.stderr.log" -f $Label.Replace(' ', '-'), $stamp)
    $process = Start-Process `
        -FilePath $FilePath `
        -ArgumentList $ArgumentList `
        -WindowStyle Hidden `
        -RedirectStandardOutput $stdoutLog `
        -RedirectStandardError $stderrLog `
        -PassThru

    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        try {
            Stop-Process -Id ([int]$process.Id) -Force -ErrorAction Stop
        }
        catch {
        }

        throw ("{0} timed out after {1} seconds. stdoutLog={2}; stderrLog={3}" -f `
            $Label, `
            $TimeoutSeconds, `
            $stdoutLog, `
            $stderrLog)
    }

    return [pscustomobject]@{
        ProcessId = [int]$process.Id
        ExitCode = [int]$process.ExitCode
        StdoutLog = [string]$stdoutLog
        StderrLog = [string]$stderrLog
    }
}

function Test-TcpPortReachable {
    param(
        [string]$HostName = '127.0.0.1',
        [int]$Port = 11434,
        [int]$TimeoutMilliseconds = 1000
    )

    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $asyncResult = $client.BeginConnect($HostName, $Port, $null, $null)
        if (-not $asyncResult.AsyncWaitHandle.WaitOne($TimeoutMilliseconds)) {
            return $false
        }

        $client.EndConnect($asyncResult)
        return $client.Connected
    }
    catch {
        return $false
    }
    finally {
        try {
            $client.Close()
        }
        catch {
        }
    }
}

function Get-OllamaApiVersion {
    param(
        [int]$TimeoutSeconds = 5
    )

    $timeoutMilliseconds = [Math]::Max(1000, ([int]$TimeoutSeconds * 1000))
    foreach ($uriText in @([string[]]$taskConfig.OllamaApiVersionUris)) {
        if ([string]::IsNullOrWhiteSpace([string]$uriText)) {
            continue
        }

        try {
            $uri = [Uri][string]$uriText
        }
        catch {
            continue
        }

        $port = if ([int]$uri.Port -gt 0) { [int]$uri.Port } elseif ([string]::Equals([string]$uri.Scheme, 'https', [System.StringComparison]::OrdinalIgnoreCase)) { 443 } else { 80 }
        if (-not (Test-TcpPortReachable -HostName ([string]$uri.Host) -Port $port -TimeoutMilliseconds ([Math]::Min(1000, $timeoutMilliseconds)))) {
            continue
        }

        $request = $null
        $response = $null
        $stream = $null
        $reader = $null
        try {
            $request = [System.Net.HttpWebRequest]::Create($uri)
            $request.Method = 'GET'
            $request.Proxy = $null
            $request.Timeout = $timeoutMilliseconds
            $request.ReadWriteTimeout = $timeoutMilliseconds
            $request.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
            $response = $request.GetResponse()
            $stream = $response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($stream)
            $body = [string]$reader.ReadToEnd()
            if (-not [string]::IsNullOrWhiteSpace([string]$body)) {
                $parsedResponse = $body | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($null -ne $parsedResponse -and -not [string]::IsNullOrWhiteSpace([string]$parsedResponse.version)) {
                    return [string]$parsedResponse.version
                }
            }
        }
        catch {
        }
        finally {
            if ($null -ne $reader) { try { $reader.Dispose() } catch { } }
            if ($null -ne $stream) { try { $stream.Dispose() } catch { } }
            if ($null -ne $response) { try { $response.Dispose() } catch { } }
        }
    }

    return ''
}

function Wait-OllamaApiReady {
    param(
        [int]$TimeoutSeconds = 90
    )

    $probeTimeoutSeconds = [Math]::Max(1, [int]$taskConfig.OllamaApiProbeTimeoutSeconds)
    $probeDelayMilliseconds = [Math]::Max(250, [int]$taskConfig.OllamaApiProbeDelayMilliseconds)
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        $version = Get-OllamaApiVersion -TimeoutSeconds $probeTimeoutSeconds
        if (-not [string]::IsNullOrWhiteSpace([string]$version)) {
            return [string]$version
        }

        Start-Sleep -Milliseconds $probeDelayMilliseconds
    }

    return ''
}

function Wait-OllamaExeReady {
    param(
        [int]$TimeoutSeconds = 45
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        Refresh-SessionPath
        $ollamaExe = Resolve-OllamaExe
        if (-not [string]::IsNullOrWhiteSpace([string]$ollamaExe)) {
            return [string]$ollamaExe
        }

        Start-Sleep -Seconds ([int]$taskConfig.OllamaExeWaitPollSeconds)
    }

    return (Resolve-OllamaExe)
}

function Write-OllamaVersion {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OllamaExe
    )

    $versionLines = @(& $OllamaExe --version 2>&1 | ForEach-Object { [string]$_ } | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string]$_) -and
        -not ([string]$_ -match '^(?i)warning:')
    })
    $exitCode = [int]$LASTEXITCODE
    foreach ($line in @($versionLines)) {
        Write-Host $line
    }

    return $exitCode
}

function Invoke-OllamaListProbe {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OllamaExe
    )

    $probeResult = Invoke-ProcessWithTimeout `
        -FilePath $OllamaExe `
        -ArgumentList @('ls') `
        -TimeoutSeconds ([int]$taskConfig.OllamaListProbeTimeoutSeconds) `
        -Label 'ollama-ls'

    return [pscustomobject]@{
        ExitCode = [int]$probeResult.ExitCode
        StdoutLog = [string]$probeResult.StdoutLog
        StderrLog = [string]$probeResult.StderrLog
        StdoutTail = [string](Get-LogTailText -Path ([string]$probeResult.StdoutLog) -LineCount ([int]$taskConfig.LogTailLineCount))
        StderrTail = [string](Get-LogTailText -Path ([string]$probeResult.StderrLog) -LineCount ([int]$taskConfig.LogTailLineCount))
    }
}

function Wait-OllamaListReady {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OllamaExe,
        [int]$TimeoutSeconds = 90
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $lastProbe = $null
    while ([DateTime]::UtcNow -lt $deadline) {
        $lastProbe = Invoke-OllamaListProbe -OllamaExe $OllamaExe
        if ([int]$lastProbe.ExitCode -eq 0) {
            return [pscustomobject]@{
                Success = $true
                Probe = $lastProbe
            }
        }

        Start-Sleep -Seconds ([int]$taskConfig.OllamaListRetryDelaySeconds)
    }

    return [pscustomobject]@{
        Success = $false
        Probe = $lastProbe
    }
}

function Get-OllamaProcessRows {
    return @(
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                [string]$_.Name -like 'ollama*'
            } |
            Select-Object ProcessId, Name, ExecutablePath, CommandLine
    )
}

function Format-OllamaProcessSummary {
    param([object[]]$Processes)

    if ($null -eq $Processes -or @($Processes).Count -eq 0) {
        return '(none)'
    }

    return (@($Processes) | ForEach-Object {
        $path = [string]$_.ExecutablePath
        if ([string]::IsNullOrWhiteSpace([string]$path)) {
            $path = [string]$_.CommandLine
        }
        if ([string]::IsNullOrWhiteSpace([string]$path)) {
            $path = '(no-path)'
        }
        if ($path.Length -gt 160) {
            $path = $path.Substring(0, 160) + '...'
        }

        return ("{0}:{1}:{2}" -f [int]$_.ProcessId, [string]$_.Name, $path)
    }) -join ' | '
}

function Get-OllamaManagedStartupShortcutPaths {
    $paths = @()
    foreach ($userName in @([string]$taskConfig.ManagerUser,[string]$taskConfig.AssistantUser)) {
        if ([string]::IsNullOrWhiteSpace([string]$userName)) { continue }
        $profilePath = ''
        try {
            $sid = ([System.Security.Principal.NTAccount]::new(('{0}\{1}' -f $env:COMPUTERNAME,[string]$userName))).Translate([System.Security.Principal.SecurityIdentifier]).Value
            $profile = Get-CimInstance -ClassName Win32_UserProfile -Filter ("SID='{0}'" -f $sid) -ErrorAction Stop
            if ($null -ne $profile -and -not [string]::IsNullOrWhiteSpace([string]$profile.LocalPath)) { $profilePath = [string]$profile.LocalPath }
        }
        catch { Write-Host ("ollama-startup-profile-info: profile lookup for '{0}' used the standard Windows profile path." -f [string]$userName) }
        if ([string]::IsNullOrWhiteSpace($profilePath)) { $profilePath = Join-Path $env:SystemDrive (Join-Path 'Users' ([string]$userName)) }
        $paths += Join-Path $profilePath 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\Ollama.lnk'
    }
    return @($paths | Select-Object -Unique)
}

function Ensure-OllamaStartupShortcuts {
    param([string]$OllamaExe)

    $applicationPath = Join-Path (Split-Path -Parent $OllamaExe) 'ollama app.exe'
    if (-not (Test-Path -LiteralPath $applicationPath -PathType Leaf)) {
        $applicationPath = ''
        foreach ($candidate in @(
            (Join-Path $env:ProgramFiles 'Ollama\ollama app.exe'),
            (Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama app.exe')
        )) {
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { $applicationPath = [string]$candidate; break }
        }
    }
    if ([string]::IsNullOrWhiteSpace($applicationPath)) { throw 'Ollama desktop startup executable was not found; no startup shortcut was written.' }
    $shell = New-Object -ComObject WScript.Shell
    foreach ($shortcutPath in @(Get-OllamaManagedStartupShortcutPaths)) {
        $startupDirectory = Split-Path -Parent $shortcutPath
        if (-not (Test-Path -LiteralPath $startupDirectory -PathType Container)) { New-Item -ItemType Directory -Path $startupDirectory -Force -ErrorAction Stop | Out-Null }
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $applicationPath
        $shortcut.WorkingDirectory = Split-Path -Parent $applicationPath
        $shortcut.IconLocation = "$applicationPath,0"
        $shortcut.Save()
        if (-not (Test-Path -LiteralPath $shortcutPath -PathType Leaf)) { throw ("Ollama startup shortcut was not created: {0}" -f $shortcutPath) }
        $verified = $shell.CreateShortcut($shortcutPath)
        if (-not [string]::Equals([string]$verified.TargetPath,[string]$applicationPath,[System.StringComparison]::OrdinalIgnoreCase)) { throw ("Ollama startup shortcut target did not verify: {0}" -f $shortcutPath) }
        Write-Host ("ollama-startup-shortcut-verified => {0}" -f ([System.IO.Path]::GetFileName([string]$shortcutPath)))
    }
}

function Wait-OllamaProcessReady {
    param([int]$TimeoutSeconds = 30)

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $lastProcesses = @()
    while ([DateTime]::UtcNow -lt $deadline) {
        $lastProcesses = @(Get-OllamaProcessRows)
        if (@($lastProcesses).Count -gt 0) {
            return [pscustomobject]@{
                Success = $true
                Processes = @($lastProcesses)
            }
        }

        Start-Sleep -Seconds ([int]$taskConfig.OllamaProcessPollSeconds)
    }

    return [pscustomobject]@{
        Success = $false
        Processes = @($lastProcesses)
    }
}

function Start-OllamaBootstrap {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OllamaExe
    )

    $cmdExe = Resolve-CmdExe
    if ([string]::IsNullOrWhiteSpace([string]$cmdExe)) {
        throw 'cmd.exe was not found.'
    }

    $bootstrapCommand = ('start "" "{0}" ls' -f [string]$OllamaExe)
    Write-Host ("Running bootstrap: {0} /c {1}" -f [string]$cmdExe, [string]$bootstrapCommand)
    & $cmdExe /c $bootstrapCommand
    $bootstrapExit = [int]$LASTEXITCODE
    if ($bootstrapExit -ne 0) {
        throw ("cmd.exe /c start bootstrap failed with exit code {0}." -f $bootstrapExit)
    }

    Start-Sleep -Seconds ([int]$taskConfig.OllamaBootstrapSettleSeconds)
}

function Start-OllamaServe {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OllamaExe
    )

    Write-Host ("Running fallback: Start-Process -FilePath {0} -ArgumentList 'serve'" -f [string]$OllamaExe)
    $serveProcess = Start-Process -FilePath $OllamaExe -ArgumentList 'serve' -WindowStyle Hidden -PassThru
    Write-Host ("ollama-serve-started: pid={0}" -f [int]$serveProcess.Id)
    Start-Sleep -Seconds ([int]$taskConfig.OllamaServeSettleSeconds)
}

function Stop-OllamaProcesses {
    foreach ($process in @(Get-Process -Name 'ollama*' -ErrorAction SilentlyContinue)) {
        try {
            Stop-Process -Id ([int]$process.Id) -Force -ErrorAction Stop
        }
        catch {
        }
    }
}

function Confirm-OllamaRuntime {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OllamaExe,
        [switch]$Bootstrap
    )

    if ($Bootstrap) {
        Start-OllamaBootstrap -OllamaExe $OllamaExe
    }

    $listTimeoutSeconds = if ($Bootstrap) { [int]$taskConfig.OllamaBootstrapValidationTimeoutSeconds } else { [int]$taskConfig.OllamaListWaitTimeoutSeconds }
    $apiTimeoutSeconds = if ($Bootstrap) { [int]$taskConfig.OllamaBootstrapValidationTimeoutSeconds } else { [int]$taskConfig.OllamaApiWaitTimeoutSeconds }
    $listResult = $null
    $processResult = $null
    $loopbackPortOpen = $false
    $localhostPortOpen = $false
    $apiVersion = ''
    $listReady = $false
    $runtimeFailure = ''

    foreach ($attemptLabel in @('bootstrap', 'serve-fallback')) {
        $processResult = Wait-OllamaProcessReady -TimeoutSeconds ([int]$taskConfig.OllamaProcessWaitTimeoutSeconds)
        if (-not [bool]$processResult.Success) {
            $runtimeFailure = 'Ollama process was not observed after bootstrap.'
        }
        else {
            $loopbackPortOpen = Test-TcpPortReachable -HostName '127.0.0.1' -Port ([int]$taskConfig.OllamaApiPort)
            $localhostPortOpen = Test-TcpPortReachable -HostName 'localhost' -Port ([int]$taskConfig.OllamaApiPort)
            if (-not ([bool]$loopbackPortOpen -or [bool]$localhostPortOpen)) {
                $runtimeFailure = ("Ollama TCP port {0} is not reachable on localhost or 127.0.0.1." -f [int]$taskConfig.OllamaApiPort)
            }
            else {
                $apiVersion = Wait-OllamaApiReady -TimeoutSeconds $apiTimeoutSeconds
                if ([string]::IsNullOrWhiteSpace([string]$apiVersion)) {
                    $runtimeFailure = ("Ollama API did not respond on 127.0.0.1:{0} or localhost:{0}." -f [int]$taskConfig.OllamaApiPort)
                }
                else {
                    $listResult = Wait-OllamaListReady -OllamaExe $OllamaExe -TimeoutSeconds $listTimeoutSeconds
                    $listReady = ($null -ne $listResult -and [bool]$listResult.Success)
                    if ([bool]$listReady) {
                        break
                    }

                    $stdoutTail = if ($null -ne $listResult -and $null -ne $listResult.Probe) { [string]$listResult.Probe.StdoutTail } else { '' }
                    $stderrTail = if ($null -ne $listResult -and $null -ne $listResult.Probe) { [string]$listResult.Probe.StderrTail } else { '' }
                    Write-Host ("ollama-ls-info: exitCode={0}; stdoutTail={1}; stderrTail={2}" -f `
                        $(if ($null -ne $listResult -and $null -ne $listResult.Probe) { [int]$listResult.Probe.ExitCode } else { -1 }), `
                        $(if ([string]::IsNullOrWhiteSpace([string]$stdoutTail)) { '(none)' } else { [string]$stdoutTail }), `
                        $(if ([string]::IsNullOrWhiteSpace([string]$stderrTail)) { '(none)' } else { [string]$stderrTail }))
                    break
                }
            }
        }

        if (-not $Bootstrap -or [string]$attemptLabel -ne 'bootstrap') {
            if (-not [string]::IsNullOrWhiteSpace([string]$runtimeFailure)) {
                Write-Host ("ollama-runtime-deferred: {0}" -f [string]$runtimeFailure)
            }
            break
        }

        Write-Host ("Ollama headless runtime is not yet durable after cmd.exe /c start bootstrap. detail={0}" -f [string]$runtimeFailure)
        Stop-OllamaProcesses
        Start-OllamaServe -OllamaExe $OllamaExe
        $listTimeoutSeconds = [int]$taskConfig.OllamaListWaitTimeoutSeconds
        $apiTimeoutSeconds = [int]$taskConfig.OllamaApiWaitTimeoutSeconds
    }

    $effectiveListProbe = if ($null -ne $listResult) { $listResult.Probe } else { $null }
    Write-Host ("ollama-ls-ready: success={0}; exitCode={1}; stdoutTail={2}; stderrTail={3}" -f `
        [bool]$listReady, `
        $(if ($null -ne $effectiveListProbe) { [int]$effectiveListProbe.ExitCode } else { -1 }), `
        $(if ($null -eq $effectiveListProbe -or [string]::IsNullOrWhiteSpace([string]$effectiveListProbe.StdoutTail)) { '(none)' } else { [string]$effectiveListProbe.StdoutTail }), `
        $(if ($null -eq $effectiveListProbe -or [string]::IsNullOrWhiteSpace([string]$effectiveListProbe.StderrTail)) { '(none)' } else { [string]$effectiveListProbe.StderrTail }))
    Write-Host ("ollama-process-ready: count={0}; processes={1}" -f @($processResult.Processes).Count, (Format-OllamaProcessSummary -Processes @($processResult.Processes)))
    Write-Host ("ollama-port-ready: 127.0.0.1={0}; localhost={1}; port={2}" -f [bool]$loopbackPortOpen, [bool]$localhostPortOpen, [int]$taskConfig.OllamaApiPort)

    Write-Host ("ollama-api-ready: success={0}; version={1}; port={2}" -f (-not [string]::IsNullOrWhiteSpace([string]$apiVersion)), [string]$apiVersion, [int]$taskConfig.OllamaApiPort)
    return [pscustomobject]@{
        Version = [string]$apiVersion
        ProcessCount = @($processResult.Processes).Count
        ListReady = [bool]$listReady
    }
}

Refresh-SessionPath

$chocoExe = Resolve-ChocoExe
if ([string]::IsNullOrWhiteSpace([string]$chocoExe)) {
    Write-Host 'Chocolatey is unavailable; Ollama install will continue through WinGet.'
}

$existingOllamaExe = Resolve-OllamaExe
if (-not [string]::IsNullOrWhiteSpace([string]$existingOllamaExe)) {
    Write-Host ("Resolved existing Ollama executable: {0}" -f [string]$existingOllamaExe)
    $existingVersionExit = Write-OllamaVersion -OllamaExe $existingOllamaExe
    if ($existingVersionExit -eq 0) {
        try {
            $existingApiVersion = Get-OllamaApiVersion -TimeoutSeconds 3
            $existingHealth = Confirm-OllamaRuntime -OllamaExe $existingOllamaExe -Bootstrap:([string]::IsNullOrWhiteSpace([string]$existingApiVersion))
            if ($null -ne $existingHealth) {
                Write-Host ("Existing Ollama installation is already healthy. Skipping install. version={0}; processCount={1}" -f [string]$existingHealth.Version, [int]$existingHealth.ProcessCount)
                Ensure-OllamaStartupShortcuts -OllamaExe $existingOllamaExe
                Write-Host "Update task completed: install-ollama-tool"
                return
            }
        }
        catch {
            Write-Host ("Existing Ollama installation is not healthy. Clean reinstall will be attempted. detail={0}" -f [string]$_.Exception.Message)
        }
    }
    else {
        Write-Host ("Existing Ollama executable failed version check with exit code {0}. Clean reinstall will be attempted." -f $existingVersionExit)
    }

    throw 'An Ollama executable is present but failed runtime verification. Use repair or uninstall explicitly; install will not delete user models or configuration.'
}

$chocoRoot = [string][Environment]::GetEnvironmentVariable('ChocolateyInstall','Machine')
if ([string]::IsNullOrWhiteSpace($chocoRoot)) { $chocoRoot = [string]$env:ChocolateyInstall }
if ([string]::IsNullOrWhiteSpace($chocoRoot)) { $chocoRoot = Join-Path $env:ProgramData 'chocolatey' }
$staleChocoPackageRoot = Join-Path (Join-Path $chocoRoot 'lib') ([string]$taskConfig.ChocoPackageId)
if (Test-Path -LiteralPath $staleChocoPackageRoot -PathType Container) {
    $currentExe = Resolve-OllamaExe
    if ([string]::IsNullOrWhiteSpace([string]$currentExe)) {
        if ([string]::IsNullOrWhiteSpace([string]$chocoExe) -or -not (Test-Path -LiteralPath $chocoExe -PathType Leaf)) { throw 'Stale Chocolatey Ollama metadata exists but the Chocolatey CLI is unavailable to remove the metadata-only registration.' }
        Write-Host 'Doing: remove stale Chocolatey Ollama registration without running its uninstall script or automatic uninstaller'
        $staleRecordCleanup = Invoke-ProcessWithTimeout `
            -FilePath $chocoExe `
            -ArgumentList @('uninstall',([string]$taskConfig.ChocoPackageId),'--skip-autouninstaller','--skip-powershell','-y','--no-progress') `
            -TimeoutSeconds 60 `
            -Label 'choco-remove-stale-ollama-registration'
        if ([int]$staleRecordCleanup.ExitCode -ne 0 -and (Test-Path -LiteralPath $staleChocoPackageRoot -PathType Container)) {
            throw ("Stale Chocolatey Ollama registration could not be removed safely. stdoutLog={0}; stderrLog={1}" -f [string]$staleRecordCleanup.StdoutLog,[string]$staleRecordCleanup.StderrLog)
        }
        if (Test-Path -LiteralPath $staleChocoPackageRoot -PathType Container) { throw 'The stale Chocolatey Ollama registration remained after its bounded metadata-only uninstall.' }
    }
}

$wingetExe = Resolve-WingetExe
if ([string]::IsNullOrWhiteSpace([string]$wingetExe)) { throw 'WinGet is unavailable for the Ollama package install.' }
Write-Host ("Running: winget install --id {0} --exact --accept-source-agreements --accept-package-agreements --silent --disable-interactivity" -f [string]$taskConfig.WingetPackageId)
$installResult = Invoke-ProcessWithTimeout `
    -FilePath $wingetExe `
    -ArgumentList @('install','--id',[string]$taskConfig.WingetPackageId,'--exact','--accept-source-agreements','--accept-package-agreements','--silent','--disable-interactivity') `
    -TimeoutSeconds ([int]$taskConfig.WingetInstallTimeoutSeconds) `
    -Label 'winget-install-ollama-tool'
$installExit = [int]$installResult.ExitCode

Refresh-SessionPath
$ollamaExe = Wait-OllamaExeReady -TimeoutSeconds ([int]$taskConfig.OllamaExeWaitTimeoutSeconds)
if ([string]::IsNullOrWhiteSpace([string]$ollamaExe)) {
    throw ("ollama executable was not found after winget install. exitCode={0}; stdoutLog={1}; stderrLog={2}" -f `
        $installExit, `
        [string]$installResult.StdoutLog, `
        [string]$installResult.StderrLog)
}

if ($installExit -notin @(0,-1978335189,1641,3010)) {
    throw ("winget install {0} exited with code {1} despite resolving ollama.exe. stdoutLog={2}; stderrLog={3}" -f [string]$taskConfig.WingetPackageId,$installExit,[string]$installResult.StdoutLog,[string]$installResult.StderrLog)
}

Write-Host ("Resolved Ollama executable: {0}" -f [string]$ollamaExe)
$versionExit = Write-OllamaVersion -OllamaExe $ollamaExe
if ($versionExit -ne 0) {
    throw ("ollama --version failed with exit code {0}." -f $versionExit)
}

$runtime = Confirm-OllamaRuntime -OllamaExe $ollamaExe -Bootstrap
Ensure-OllamaStartupShortcuts -OllamaExe $ollamaExe
Write-Host ("install-ollama-tool-completed: version={0}; processCount={1}; listReady={2}" -f [string]$runtime.Version, [int]$runtime.ProcessCount, [bool]$runtime.ListReady)
Write-Host "Update task completed: install-ollama-tool"
