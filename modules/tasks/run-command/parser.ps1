# Run-command result parsing helpers.

# Handles Test-ProdicloudBenignRunCommandStdErr.
function Test-ProdicloudBenignRunCommandStdErr {
    param(
        [string]$Message
    )

    if ([string]::IsNullOrWhiteSpace([string]$Message)) {
        return $false
    }

    $normalized = [string]$Message
    $normalized = $normalized -replace "`r", " "
    $normalized = $normalized -replace "`n", " "

    $benignPatterns = @(
        "(?i)'wmic'\s+is\s+not\s+recognized\s+as\s+an\s+internal\s+or\s+external\s+command",
        '(?i)^Seizure Warning:\s*https://aka\.ms/microsoft-store-seizure-warning'
    )

    foreach ($pattern in $benignPatterns) {
        if ($normalized -match $pattern) {
            return $true
        }
    }

    return $false
}

# Handles Get-ProdicloudRunCommandResultEnvelope.
function Get-ProdicloudRunCommandResultEnvelope {
    param(
        [string]$TaskName,
        [object]$RawJson,
        [string]$ModeLabel
    )

    if ($null -eq $RawJson -or [string]::IsNullOrWhiteSpace([string]$RawJson)) {
        throw "VM $ModeLabel task '$TaskName' run-command output is empty."
    }

    try {
        $result = ConvertFrom-JsonCompat -InputObject $RawJson
    }
    catch {
        throw "VM $ModeLabel task '$TaskName' run-command output could not be parsed as JSON."
    }

    $resultEntries = ConvertTo-ObjectArrayCompat -InputObject $result.value
    if (-not $resultEntries -or $resultEntries.Count -eq 0) {
        throw "VM $ModeLabel task '$TaskName' run-command output is empty."
    }

    $messages = @()
    $hasError = $false
    foreach ($entry in $resultEntries) {
        $code = [string]$entry.code
        $message = [string]$entry.message
        $isFailedCode = ($code -match '(?i)/failed$')
        $isStdErrCode = ($code -match '(?i)StdErr')
        if (-not [string]::IsNullOrWhiteSpace($message)) {
            $messages += $message.Trim()
        }

        if ($isStdErrCode -and -not [string]::IsNullOrWhiteSpace($message)) {
            if (Test-ProdicloudBenignRunCommandStdErr -Message $message) {
                Write-Warning ("Ignoring benign run-command stderr line for task '{0}': {1}" -f $TaskName, $message.Trim())
            }
            elseif ($message -match '(?i)(terminatingerror|exception|failed|not recognized|cannot find|categoryinfo)') {
                $hasError = $true
            }
            elseif ($isFailedCode) {
                $hasError = $true
            }
        }
        elseif ($isFailedCode) {
            $hasError = $true
        }
    }

    $messageText = ($messages -join "`n")
    $errorMessage = ''
    if ($hasError) {
        $joinedMessages = ($messages -join " | ")
        $errorMessage = "VM $ModeLabel task '$TaskName' reported error: $joinedMessages"
    }

    return [pscustomobject]@{
        MessageText = [string]$messageText
        HasError = [bool]$hasError
        ErrorMessage = [string]$errorMessage
    }
}

# Handles Get-ProdicloudRunCommandResultMessage.
function Get-ProdicloudRunCommandResultMessage {
    param(
        [string]$TaskName,
        [object]$RawJson,
        [string]$ModeLabel
    )

    $envelope = Get-ProdicloudRunCommandResultEnvelope -TaskName $TaskName -RawJson $RawJson -ModeLabel $ModeLabel
    if ([bool]$envelope.HasError) {
        throw [string]$envelope.ErrorMessage
    }

    return [string]$envelope.MessageText
}

# Handles Parse-ProdicloudRunCommandBatchMarkers.
function Parse-ProdicloudRunCommandBatchMarkers {
    param(
        [string]$MessageText
    )

    $result = [ordered]@{
        SuccessCount = 0
        WarningCount = 0
        ErrorCount = 0
        RebootCount = 0
        RebootRequired = $false
        HasSummaryLine = $false
        SummaryLine = ""
    }

    if ([string]::IsNullOrWhiteSpace($MessageText)) {
        return [pscustomobject]$result
    }

    $lines = @($MessageText -split "`r?`n")
    foreach ($line in $lines) {
        $trimmed = [string]$line
        if ($trimmed -match '^TASK_STATUS:(.+?):(success|warning|error)$') {
            $status = [string]$Matches[2]
            switch ($status) {
                "success" { $result.SuccessCount++ }
                "warning" { $result.WarningCount++ }
                "error" { $result.ErrorCount++ }
            }
            continue
        }

        if ($trimmed -match '^RUN_COMMAND_SUMMARY:success=(\d+);warning=(\d+);error=(\d+);reboot=(\d+)$') {
            $result.SuccessCount = [int]$Matches[1]
            $result.WarningCount = [int]$Matches[2]
            $result.ErrorCount = [int]$Matches[3]
            $result.RebootCount = [int]$Matches[4]
            $result.HasSummaryLine = $true
            $result.SummaryLine = $trimmed
            continue
        }

        if ($trimmed -match '^PRODICLOUD_REBOOT_REQUIRED:') {
            $result.RebootRequired = $true
            continue
        }
    }

    return [pscustomobject]$result
}

# Handles Test-ProdicloudOutputIndicatesRebootRequired.
function Test-ProdicloudOutputIndicatesRebootRequired {
    param(
        [string]$MessageText
    )

    if ([string]::IsNullOrWhiteSpace($MessageText)) {
        return $false
    }

    if ($MessageText -match '^PRODICLOUD_REBOOT_REQUIRED:' -or $MessageText -match '(?im)^TASK_REBOOT_REQUIRED:') {
        return $true
    }

    $positiveRestartSignalLines = @(
        $MessageText -split "`r?`n" |
            Where-Object {
                $line = [string]$_
                if ($line -notmatch '(?i)(?:reboot|restart)(?:\s+is)?\s+required|pending reboot|press any key to install windows subsystem for linux') {
                    return $false
                }
                return ($line -notmatch '(?i)\b(?:no|not|without)\s+(?:immediate\s+)?(?:reboot|restart)(?:\s+is)?\s+required\b')
            }
    )
    return (@($positiveRestartSignalLines).Count -gt 0)
}

# Handles Get-ProdicloudTaskDurationsFromMessageText.
function Get-ProdicloudTaskDurationsFromMessageText {
    param(
        [string]$MessageText
    )

    $durations = @()
    if ([string]::IsNullOrWhiteSpace([string]$MessageText)) {
        return @()
    }

    foreach ($lineRaw in @($MessageText -split "`r?`n")) {
        $line = [string]$lineRaw
        if ($line -match '^TASK completed:\s*(.+?)\s*\(([0-9]+(?:\.[0-9]+)?)s\)\s*$') {
            $taskName = [string]$Matches[1]
            $seconds = [double]$Matches[2]
            $durations += [pscustomobject]@{
                Name = $taskName
                Seconds = $seconds
            }
        }
    }

    return @($durations)
}
