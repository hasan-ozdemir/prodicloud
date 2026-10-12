# Run-command script preparation helpers.

# Handles Resolve-ClagnosRunCommandScriptText.
function Resolve-ClagnosRunCommandScriptText {
    param(
        [string]$ScriptText
    )

    if ([string]::IsNullOrWhiteSpace($ScriptText)) {
        throw "VM run-command task script content is empty."
    }

    if ($ScriptText.StartsWith("@")) {
        $scriptPath = $ScriptText.Substring(1)
        if (-not (Test-Path -LiteralPath $scriptPath)) {
            throw "VM run-command task script file was not found: $scriptPath"
        }
        return (Get-Content -Path $scriptPath -Raw)
    }

    return $ScriptText
}

# Handles Get-ClagnosRunCommandScriptArgs.
function Get-ClagnosRunCommandScriptArgs {
    param(
        [string]$ScriptText,
        [string]$CommandId
    )

    if ([string]::IsNullOrWhiteSpace($ScriptText)) {
        throw "VM run-command task script content is empty."
    }

    if ($ScriptText.StartsWith("@")) {
        return @($ScriptText)
    }

    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'clagnos-run-command'
    if (-not (Test-Path -LiteralPath $tempRoot)) {
        [void](New-Item -ItemType Directory -Path $tempRoot -Force)
    }

    $extension = if ($CommandId -eq "RunPowerShellScript") { ".ps1" } else { ".sh" }
    $fileName = "task-{0}{1}" -f ([System.Guid]::NewGuid().ToString("N")), $extension
    $tempPath = Join-Path $tempRoot $fileName

    Write-TextFileNormalized -Path $tempPath -Content $ScriptText -Encoding "utf8NoBom" -EnsureTrailingNewline:$true
    return @("@$tempPath")
}
