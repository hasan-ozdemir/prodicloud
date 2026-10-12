# SSH protocol parsing and console-noise helpers.

# Handles Normalize-ClagnosProtocolLine.
function Normalize-ClagnosProtocolLine {
    param(
        [AllowNull()]
        [string]$Text
    )

    if ($null -eq $Text) {
        return $null
    }

    $value = [string]$Text
    $value = $value.Replace("`0", "")
    $value = $value.TrimStart([char]0xFEFF)
    $value = $value.TrimEnd("`r", "`n")
    $trimmedLeading = $value.TrimStart()
    if ($trimmedLeading -match '^(?<spinner>[\|/\\-]{1,16})\s+(?<marker>(?:\[stderr\]\s+)?CLAGNOS_[A-Z_]+:.*)$') {
        return [string]$Matches.marker
    }
    return $value
}

# Handles Test-ClagnosTransientSpinnerLine.
function Test-ClagnosTransientSpinnerLine {
    param(
        [AllowNull()]
        [string]$Text
    )

    if ($null -eq $Text) {
        return $false
    }

    $value = [string]$Text
    if ($value.StartsWith("[stderr] ", [System.StringComparison]::OrdinalIgnoreCase)) {
        $value = $value.Substring(9)
    }

    $value = $value.Trim()
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $false
    }

    return [regex]::IsMatch($value, '^[\|/\\-]{1,16}$')
}

# Handles Write-ClagnosTransientConsoleText.
function Write-ClagnosTransientConsoleText {
    param(
        [AllowNull()]
        [string]$Text
    )

    $value = if ($null -eq $Text) { "" } else { [string]$Text }
    [Console]::Write(("`r{0}" -f $value))
}

# Handles Clear-ClagnosTransientConsoleText.
function Clear-ClagnosTransientConsoleText {
    [Console]::WriteLine("")
}

# Handles Test-ClagnosTaskOutputNoiseLine.
function Test-ClagnosTaskOutputNoiseLine {
    param(
        [AllowNull()]
        [string]$Text
    )

    if ($null -eq $Text) {
        return $false
    }

    $value = [string]$Text
    if ($value.StartsWith("[stderr] ", [System.StringComparison]::OrdinalIgnoreCase)) {
        $value = $value.Substring(9)
    }
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $false
    }

    return (
        $value.StartsWith("CLAGNOS_TASK_BEGIN:", [System.StringComparison]::OrdinalIgnoreCase) -or
        $value.StartsWith("CLAGNOS_TASK_END:", [System.StringComparison]::OrdinalIgnoreCase) -or
        $value.StartsWith("TASK_STATUS:", [System.StringComparison]::OrdinalIgnoreCase) -or
        $value.StartsWith("RUN_COMMAND_SUMMARY:", [System.StringComparison]::OrdinalIgnoreCase) -or
        $value.StartsWith("TASK started:", [System.StringComparison]::OrdinalIgnoreCase) -or
        $value.StartsWith("TASK completed:", [System.StringComparison]::OrdinalIgnoreCase) -or
        $value.StartsWith("TASK result:", [System.StringComparison]::OrdinalIgnoreCase) -or
        $value.StartsWith("Update task started:", [System.StringComparison]::OrdinalIgnoreCase) -or
        $value.StartsWith("Update task completed:", [System.StringComparison]::OrdinalIgnoreCase) -or
        $value.StartsWith("The command completed successfully.", [System.StringComparison]::OrdinalIgnoreCase) -or
        ($value -match "(?i)'wmic'\s+is\s+not\s+recognized\s+as\s+an\s+internal\s+or\s+external\s+command") -or
        ($value -match '(?i)^Seizure Warning:\s*https://aka\.ms/microsoft-store-seizure-warning') -or
        ($value -match '^(?i)WARNING:\s+It''s very likely you will need to close and reopen your shell\b') -or
        ($value -match '^(?i)WARNING:\s+Not setting tab completion: Profile file does not exist at\b') -or
        ($value -match '^(?i)WARNING:\s+Ignoring checksums due to feature checksumFiles turned off or option --ignore-checksums set\.$') -or
        ($value -match '^(?i)WARNING:\s+No registry key found based on\s+''Git''$') -or
        ($value -match '^(?i)WARNING:\s+If you started this package under PowerShell core, replacing an in-use version may be unpredictable, require multiple attempts or produce errors\.$') -or
        ($value -match '^(?i)WARNING:\s+The Windows Subsystem for Linux is not installed\. You can install by running ''wsl\.exe --install''\.$') -or
        ($value -match '^(?i)WARNING:\s+wsl\.exe : The Windows Subsystem for Linux is not installed\. You\s*$') -or
        ($value -match '^(?i)WARNING:\s+can install by running ''wsl\.exe --install''\.$') -or
        ($value -match '^(?i)WARNING:\s+For more information please visit https://aka\.ms/wslinstall$') -or
        ($value -match '^(?i)WARNING:\s+At .+clagnos-task-.*\.ps1:\d+ char:\d+$') -or
        ($value -match '^(?i)WARNING:\s+\+\s+wsl\.exe --install --no-distribution$') -or
        ($value -match '^(?i)WARNING:\s+\+\s+~+$') -or
        ($value -match '^(?i)WARNING:\s+\+\s+CategoryInfo\s+:.*NativeCommandError$') -or
        ($value -match '^(?i)WARNING:\s+\+\s+FullyQualifiedErrorId\s+: NativeCommandError$') -or
        ($value -match '^(?i)WARNING:\s+npm notice(?:\b|$)') -or
        ($value -match '^(?i)WARNING:\s+npm warn deprecated\b') -or
        ($value -match '^(?i)ERROR:\s+request returned 500 Internal Server Error for API route and version http://%2F%2F\.\%2Fpipe%2FdockerDesktopLinuxEngine/v[\d\.]+/info, check if the server supports the requested API version$') -or
        ($value -match '^(?i)errors pretty printing info$')
    )
}

# Handles Convert-ClagnosProtocolTaskExitCode.
function Convert-ClagnosProtocolTaskExitCode {
    param(
        [AllowNull()]
        [string]$Text
    )

    $raw = ''
    if ($null -ne $Text) {
        $raw = [string]$Text
    }
    $raw = $raw.Trim()
    if ([string]::IsNullOrWhiteSpace([string]$raw)) {
        return 1
    }

    [Int64]$parsed = 0
    if (-not [Int64]::TryParse($raw, [ref]$parsed)) {
        throw ("Task exit code '{0}' is not a valid integer." -f $raw)
    }

    $uint32Max = [Int64][UInt32]::MaxValue
    $int32Max = [Int64][Int32]::MaxValue
    $int32Min = [Int64][Int32]::MinValue
    if ($parsed -gt $int32Max -and $parsed -le $uint32Max) {
        $parsed -= ($uint32Max + 1)
    }

    if ($parsed -lt $int32Min -or $parsed -gt $int32Max) {
        throw ("Task exit code '{0}' is outside the supported Int32 range." -f $raw)
    }

    return [int]$parsed
}
