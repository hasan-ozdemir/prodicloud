# SSH process execution helpers.

function Invoke-ClagnosCapturedProcess {
    param(
        [string]$FilePath,
        [string[]]$Arguments
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = [string]$FilePath
    $psi.Arguments = ((@($Arguments) | ForEach-Object { Convert-ClagnosProcessArgument -Value ([string]$_) }) -join ' ')
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psiType = $psi.GetType()
    if ($psiType.GetProperty('StandardOutputEncoding')) {
        try { $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
    }
    if ($psiType.GetProperty('StandardErrorEncoding')) {
        try { $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8 } catch { }
    }
    $null = $psi.EnvironmentVariables
    $psi.EnvironmentVariables['PYTHONDONTWRITEBYTECODE'] = '1'

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi

    if (-not $proc.Start()) {
        throw ("Process could not be started: {0}" -f [string]$FilePath)
    }

    try {
        $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
        $stderrTask = $proc.StandardError.ReadToEndAsync()
        $proc.WaitForExit()
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        $outputParts = @()
        if (-not [string]::IsNullOrWhiteSpace([string]$stdout)) {
            $outputParts += [string]$stdout
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$stderr)) {
            $outputParts += [string]$stderr
        }

        return [pscustomobject]@{
            ExitCode = [int]$proc.ExitCode
            Output = (($outputParts | ForEach-Object { [string]$_ }) -join "`n").Trim()
            OutputRelayedLive = $false
        }
    }
    finally {
        try { $proc.Dispose() } catch { }
    }
}

function Invoke-ClagnosStreamingCapturedProcess {
    param(
        [string]$FilePath,
        [string[]]$Arguments
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = [string]$FilePath
    $psi.Arguments = ((@($Arguments) | ForEach-Object { Convert-ClagnosProcessArgument -Value ([string]$_) }) -join ' ')
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psiType = $psi.GetType()
    if ($psiType.GetProperty('StandardOutputEncoding')) {
        try { $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
    }
    if ($psiType.GetProperty('StandardErrorEncoding')) {
        try { $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8 } catch { }
    }
    $null = $psi.EnvironmentVariables
    $psi.EnvironmentVariables['PYTHONDONTWRITEBYTECODE'] = '1'

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi

    if (-not $proc.Start()) {
        throw ("Process could not be started: {0}" -f [string]$FilePath)
    }

    try {
        $stdoutReader = $proc.StandardOutput
        $stderrReader = $proc.StandardError
        $stdoutClosed = $false
        $stderrClosed = $false
        $stdoutTask = $stdoutReader.ReadLineAsync()
        $stderrTask = $stderrReader.ReadLineAsync()
        $outputLines = New-Object 'System.Collections.Generic.List[string]'

        while (-not ($proc.HasExited -and $stdoutClosed -and $stderrClosed)) {
            $activeTasks = @()
            if (-not $stdoutClosed) { $activeTasks += $stdoutTask }
            if (-not $stderrClosed) { $activeTasks += $stderrTask }

            if (@($activeTasks).Count -eq 0) {
                break
            }

            $completedIndex = [System.Threading.Tasks.Task]::WaitAny(@($activeTasks), 250)
            if ($completedIndex -lt 0) {
                continue
            }

            $completedTask = $activeTasks[$completedIndex]
            $isStdoutTask = (-not $stdoutClosed) -and ($completedTask -eq $stdoutTask)
            $line = $completedTask.Result
            if ($null -eq $line) {
                if ($isStdoutTask) {
                    $stdoutClosed = $true
                }
                else {
                    $stderrClosed = $true
                }
                continue
            }

            $lineText = [string]$line
            $normalizedLine = Normalize-ClagnosProtocolLine -Text $lineText
            if ($null -eq $normalizedLine) {
                $normalizedLine = ""
            }
            if (Test-ClagnosTaskOutputNoiseLine -Text ([string]$normalizedLine)) {
                if ($isStdoutTask) {
                    $stdoutTask = $stdoutReader.ReadLineAsync()
                }
                else {
                    $stderrTask = $stderrReader.ReadLineAsync()
                }
                continue
            }
            if ([string]::IsNullOrWhiteSpace([string]$normalizedLine)) {
                if ($isStdoutTask) {
                    $stdoutTask = $stdoutReader.ReadLineAsync()
                }
                else {
                    $stderrTask = $stderrReader.ReadLineAsync()
                }
                continue
            }

            [void]$outputLines.Add([string]$normalizedLine)
            if ($isStdoutTask) {
                Write-Host ([string]$normalizedLine)
                $stdoutTask = $stdoutReader.ReadLineAsync()
            }
            else {
                Write-Warning ([string]$normalizedLine)
                $stderrTask = $stderrReader.ReadLineAsync()
            }
        }

        if ($proc.HasExited -and -not $stdoutClosed) {
            $stdoutTail = [string]$stdoutReader.ReadToEnd()
            foreach ($tailLine in @($stdoutTail -split "`r?`n")) {
                $normalizedTailLine = Normalize-ClagnosProtocolLine -Text ([string]$tailLine)
                if ([string]::IsNullOrWhiteSpace([string]$normalizedTailLine)) { continue }
                if (Test-ClagnosTaskOutputNoiseLine -Text ([string]$normalizedTailLine)) { continue }
                [void]$outputLines.Add([string]$normalizedTailLine)
                Write-Host ([string]$normalizedTailLine)
            }
        }
        if ($proc.HasExited -and -not $stderrClosed) {
            $stderrTail = [string]$stderrReader.ReadToEnd()
            foreach ($tailLine in @($stderrTail -split "`r?`n")) {
                $normalizedTailLine = Normalize-ClagnosProtocolLine -Text ([string]$tailLine)
                if ([string]::IsNullOrWhiteSpace([string]$normalizedTailLine)) { continue }
                if (Test-ClagnosTaskOutputNoiseLine -Text ([string]$normalizedTailLine)) { continue }
                [void]$outputLines.Add([string]$normalizedTailLine)
                Write-Warning ([string]$normalizedTailLine)
            }
        }

        $proc.WaitForExit()
        return [pscustomobject]@{
            ExitCode = [int]$proc.ExitCode
            Output = ((@($outputLines) | ForEach-Object { [string]$_ }) -join "`n").Trim()
            OutputRelayedLive = $true
        }
    }
    finally {
        try { $proc.Dispose() } catch { }
    }
}

# Handles Invoke-ClagnosProcessWithRetry.
function Invoke-ClagnosProcessWithRetry {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [string]$Label,
        [int]$MaxAttempts = 3,
        [switch]$AllowFailure,
        [switch]$SuppressTrackedLogging,
        [switch]$SkipPythonBytecodeFlag,
        [switch]$RelayOutput
    )

    if ($MaxAttempts -lt 1) {
        $MaxAttempts = 1
    }
    if ($MaxAttempts -gt 3) {
        $MaxAttempts = 3
    }

    $lastOutput = ""
    $lastExit = 0
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $attemptLabel = if ($MaxAttempts -gt 1) { ("{0} (attempt {1}/{2})" -f $Label, $attempt, $MaxAttempts) } else { $Label }
        $effectiveArguments = if ($SkipPythonBytecodeFlag) { @($Arguments) } else { @('-B') + @($Arguments) }
        if ($SuppressTrackedLogging) {
            $processResult = if ($RelayOutput) {
                Invoke-ClagnosStreamingCapturedProcess -FilePath $FilePath -Arguments $effectiveArguments
            }
            else {
                Invoke-ClagnosCapturedProcess -FilePath $FilePath -Arguments $effectiveArguments
            }
        }
        else {
            $processResult = Invoke-TrackedAction -Label $attemptLabel -Action {
                if ($RelayOutput) {
                    Invoke-ClagnosStreamingCapturedProcess -FilePath $FilePath -Arguments $effectiveArguments
                }
                else {
                    Invoke-ClagnosCapturedProcess -FilePath $FilePath -Arguments $effectiveArguments
                }
            }
        }
        $lastExit = [int]$processResult.ExitCode
        $lastOutput = [string]$processResult.Output

        if ($lastExit -eq 0 -or $AllowFailure) {
            return [pscustomobject]@{
                ExitCode = $lastExit
                Output = $lastOutput
                OutputRelayedLive = [bool]$RelayOutput
            }
        }

        if ($attempt -lt $MaxAttempts) {
            Write-Host ("Retrying after failure (exit {0}): {1}" -f $lastExit, $Label) -ForegroundColor Yellow
            Start-Sleep -Seconds 2
        }
    }

    throw ("{0} failed after {1} attempt(s). Exit={2}. Output={3}" -f $Label, $MaxAttempts, $lastExit, $lastOutput)
}

# Handles Convert-ClagnosProcessArgument.
function Convert-ClagnosProcessArgument {
    param(
        [string]$Value
    )

    if ($null -eq $Value) {
        return '""'
    }

    $escaped = [string]$Value
    $escaped = $escaped -replace '(\\*)"', '$1$1\"'
    $escaped = $escaped -replace '(\\+)$', '$1$1'
    return ('"{0}"' -f $escaped)
}
