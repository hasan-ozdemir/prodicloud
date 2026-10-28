# Exec command runtime helpers.

function Initialize-ProdicloudExecCommandRuntimeContext {
    param()

    $repoRoot = Get-ProdicloudRepoRoot
    $envFilePath = Join-Path $repoRoot 'prodicloud.env'
    $configMap = Read-DotEnvFile -Path $envFilePath
    $configuredPySshClientPath = [string](Get-ConfigValue -Config $configMap -Key 'PYSSH_CLIENT_PATH' -DefaultValue (Get-ProdicloudDefaultPySshClientPathText))

    $sshConnectTimeoutText = [string](Get-ConfigValue -Config $configMap -Key 'SSH_CONNECT_TIMEOUT_SECONDS' -DefaultValue ([string]$script:SshConnectTimeoutSeconds))
    $sshConnectTimeoutSeconds = $script:SshConnectTimeoutSeconds
    if ($sshConnectTimeoutText -match '^\d+$') { $sshConnectTimeoutSeconds = [int]$sshConnectTimeoutText }
    if ($sshConnectTimeoutSeconds -lt 5) { $sshConnectTimeoutSeconds = 5 }
    if ($sshConnectTimeoutSeconds -gt 300) { $sshConnectTimeoutSeconds = 300 }

    $sshCommandTimeoutText = [string](Get-ConfigValue -Config $configMap -Key 'SSH_TASK_TIMEOUT_SECONDS' -DefaultValue ([string]$script:SshTaskTimeoutSeconds))
    $sshCommandTimeoutSeconds = $script:SshTaskTimeoutSeconds
    if ($sshCommandTimeoutText -match '^\d+$') { $sshCommandTimeoutSeconds = [int]$sshCommandTimeoutText }
    if ($sshCommandTimeoutSeconds -lt 30) { $sshCommandTimeoutSeconds = 30 }
    if ($sshCommandTimeoutSeconds -gt 7200) { $sshCommandTimeoutSeconds = 7200 }

    $script:SshConnectTimeoutSeconds = $sshConnectTimeoutSeconds
    $script:SshTaskTimeoutSeconds = $sshCommandTimeoutSeconds

    return [pscustomobject]@{
        RepoRoot = $repoRoot
        EnvFilePath = $envFilePath
        ConfigMap = $configMap
        ConfiguredPySshClientPath = $configuredPySshClientPath
        SshConnectTimeoutSeconds = $sshConnectTimeoutSeconds
        SshCommandTimeoutSeconds = $sshCommandTimeoutSeconds
    }
}

function ConvertTo-ProdicloudExecRemoteCommandText {
    param(
        [string]$CommandText,
        [string]$Platform,
        [bool]$Quiet = $false
    )

    $resolvedCommandText = [string]$CommandText
    if ([string]::IsNullOrWhiteSpace([string]$resolvedCommandText)) {
        return ''
    }

    if (-not [string]::Equals([string]$Platform, 'windows', [System.StringComparison]::OrdinalIgnoreCase)) {
        return $resolvedCommandText
    }

    $trimmedCommandText = $resolvedCommandText.TrimStart()
    if ($trimmedCommandText -match '^(?i)(powershell|pwsh|cmd(?:\.exe)?)(?:\s|$)') {
        return $resolvedCommandText
    }

    $prefaceLines = @(
        ("$" + "ProgressPreference = 'SilentlyContinue'")
    )

    $commandBody = [string]$resolvedCommandText
    if ($Quiet) {
        $prefaceLines += ("$" + "InformationPreference = 'SilentlyContinue'")
        $commandBody = ("& {" + [Environment]::NewLine + [string]$resolvedCommandText + [Environment]::NewLine + "} 6>" + "$" + "null")
    }

    $wrappedCommandText = ((@($prefaceLines) -join [Environment]::NewLine) + [Environment]::NewLine + [string]$commandBody)
    $encodedBytes = [System.Text.Encoding]::Unicode.GetBytes($wrappedCommandText)
    $encodedCommand = [Convert]::ToBase64String($encodedBytes)
    return ("powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand {0}" -f [string]$encodedCommand)
}

function Resolve-ProdicloudExecCommandTextFromOptions {
    param(
        [hashtable]$Options,
        [string]$RepoRoot
    )

    $commandText = [string](Get-ProdicloudCliOptionText -Options $Options -Name 'command')
    $filePathText = [string](Get-ProdicloudCliOptionText -Options $Options -Name 'file')

    if (-not [string]::IsNullOrWhiteSpace([string]$commandText) -and -not [string]::IsNullOrWhiteSpace([string]$filePathText)) {
        Throw-FriendlyError `
            -Detail 'exec accepts either --command or --file, but not both.' `
            -Code 61 `
            -Summary 'Exec command source is ambiguous.' `
            -Hint 'Use either prodicloud exec --command "<remote-command>" or prodicloud exec --file <script-file>.'
    }

    if ([string]::IsNullOrWhiteSpace([string]$filePathText)) {
        return [pscustomobject]@{
            CommandText = [string]$commandText
            ScriptFilePath = ''
        }
    }

    $candidatePaths = New-Object 'System.Collections.Generic.List[string]'
    [void]$candidatePaths.Add([string]$filePathText)
    if (-not [System.IO.Path]::IsPathRooted([string]$filePathText) -and -not [string]::IsNullOrWhiteSpace([string]$RepoRoot)) {
        [void]$candidatePaths.Add((Join-Path $RepoRoot [string]$filePathText))
    }

    $resolvedPath = ''
    foreach ($candidatePath in @($candidatePaths)) {
        if ([string]::IsNullOrWhiteSpace([string]$candidatePath)) {
            continue
        }

        $pathItem = Get-Item -LiteralPath $candidatePath -ErrorAction SilentlyContinue
        if ($null -ne $pathItem -and -not $pathItem.PSIsContainer) {
            $resolvedPath = [string]$pathItem.FullName
            break
        }
    }

    if ([string]::IsNullOrWhiteSpace([string]$resolvedPath)) {
        Throw-FriendlyError `
            -Detail ("Script file was not found: {0}" -f [string]$filePathText) `
            -Code 61 `
            -Summary 'Exec script file was not found.' `
            -Hint 'Pass one existing local script file path to prodicloud exec --file.'
    }

    $scriptText = [string][System.IO.File]::ReadAllText($resolvedPath)
    if ([string]::IsNullOrWhiteSpace([string]$scriptText)) {
        Throw-FriendlyError `
            -Detail ("Script file is empty: {0}" -f [string]$resolvedPath) `
            -Code 61 `
            -Summary 'Exec script file is empty.' `
            -Hint 'Add remote command content to the script file before using prodicloud exec --file.'
    }

    return [pscustomobject]@{
        CommandText = [string]$scriptText
        ScriptFilePath = [string]$resolvedPath
    }
}
