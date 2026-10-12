# SSH task asset-copy helpers.

function ConvertTo-ClagnosPowerShellSingleQuotedLiteral {
    param(
        [AllowNull()]
        [string]$Value
    )

    if ($null -eq $Value) {
        return ''
    }

    return ([string]$Value).Replace("'", "''")
}

function Test-ClagnosWindowsRemotePath {
    param(
        [string]$RemotePath
    )

    if ([string]::IsNullOrWhiteSpace([string]$RemotePath)) {
        return $false
    }

    return ([string]$RemotePath -match '^[A-Za-z]:[\\/]')
}

function Get-ClagnosFileSha256 {
    param(
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace([string]$Path) -or -not (Test-Path -LiteralPath $Path)) {
        throw ("File was not found for SHA256 hashing: {0}" -f [string]$Path)
    }

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $stream = [System.IO.File]::OpenRead([string]$Path)
        try {
            $hashBytes = $sha256.ComputeHash($stream)
            return ([System.BitConverter]::ToString($hashBytes)).Replace('-', '').Trim().ToUpperInvariant()
        }
        finally {
            if ($null -ne $stream) { $stream.Dispose() }
        }
    }
    finally {
        if ($null -ne $sha256) { $sha256.Dispose() }
    }
}

if ($null -eq $script:ClagnosWindowsScpHostKeyCache) {
    $script:ClagnosWindowsScpHostKeyCache = @{}
}
if ($null -eq $script:ClagnosWindowsScpPathCache) {
    $script:ClagnosWindowsScpPathCache = ''
}

function Get-ClagnosPscpExecutablePath {
    if (-not [string]::IsNullOrWhiteSpace([string]$script:ClagnosWindowsScpPathCache) -and (Test-Path -LiteralPath ([string]$script:ClagnosWindowsScpPathCache))) {
        return [string]$script:ClagnosWindowsScpPathCache
    }

    $command = Get-Command pscp.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $command) {
        throw "Windows SCP transport requires pscp.exe on the local operator machine."
    }

    $resolvedPath = [string]$command.Source
    if ([string]::IsNullOrWhiteSpace([string]$resolvedPath) -and $command.PSObject.Properties.Match('Path').Count -gt 0) {
        $resolvedPath = [string]$command.Path
    }
    if ([string]::IsNullOrWhiteSpace([string]$resolvedPath)) {
        throw "Windows SCP transport could not resolve the pscp.exe path."
    }

    $script:ClagnosWindowsScpPathCache = [string]$resolvedPath
    return [string]$script:ClagnosWindowsScpPathCache
}

function ConvertTo-ClagnosWindowsScpRemoteSpec {
    param(
        [string]$HostName,
        [string]$RemotePath
    )

    $normalizedRemotePath = ([string]$RemotePath).Replace('\', '/')
    if ($normalizedRemotePath -match '^[A-Za-z]:/') {
        $normalizedRemotePath = ('/{0}' -f [string]$normalizedRemotePath)
    }

    return ('{0}:{1}' -f [string]$HostName, [string]$normalizedRemotePath)
}

function Try-Get-ClagnosWindowsScpHostKeyArguments {
    param(
        [string]$HostName,
        [string]$Port
    )

    try {
        $cacheKey = ('{0}:{1}' -f [string]$HostName, [string]$Port)
        if ($script:ClagnosWindowsScpHostKeyCache.ContainsKey($cacheKey)) {
            return [pscustomobject]@{
                Success = $true
                Args = @($script:ClagnosWindowsScpHostKeyCache[$cacheKey])
                Message = ''
            }
        }

        $sshKeyScan = Get-Command ssh-keyscan.exe -ErrorAction SilentlyContinue | Select-Object -First 1
        $sshKeyGen = Get-Command ssh-keygen.exe -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -eq $sshKeyScan -or $null -eq $sshKeyGen) {
            return [pscustomobject]@{
                Success = $false
                Args = @()
                Message = 'Windows SCP transport requires ssh-keyscan.exe and ssh-keygen.exe on the local operator machine.'
            }
        }

        $scanResult = Invoke-ClagnosCapturedProcess -FilePath ([string]$sshKeyScan.Source) -Arguments @('-p', [string]$Port, [string]$HostName)
        if ([int]$scanResult.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace([string]$scanResult.Output)) {
            return [pscustomobject]@{
                Success = $false
                Args = @()
                Message = ("Windows SCP transport could not resolve an SSH host key for {0}:{1}." -f [string]$HostName, [string]$Port)
            }
        }

        $hostKeyArgs = New-Object 'System.Collections.Generic.List[string]'
        $seenFingerprints = @{}
        $scanLines = @([string]$scanResult.Output -split "`r?`n" | Where-Object {
                -not [string]::IsNullOrWhiteSpace([string]$_) -and -not ([string]$_).TrimStart().StartsWith('#')
            })
        foreach ($scanLine in @($scanLines)) {
            $parts = @(([string]$scanLine).Trim() -split '\s+')
            if (@($parts).Count -lt 3) {
                continue
            }

            $algorithm = [string]$parts[1]
            if ([string]::IsNullOrWhiteSpace([string]$algorithm)) {
                continue
            }

            $tempKeyPath = Join-Path ([System.IO.Path]::GetTempPath()) ('clagnos-scp-hostkey-' + ([guid]::NewGuid().ToString('N')) + '.pub')
            try {
                [System.IO.File]::WriteAllText($tempKeyPath, ([string]$scanLine + [Environment]::NewLine), [System.Text.Encoding]::ASCII)
                $fingerprintResult = Invoke-ClagnosCapturedProcess -FilePath ([string]$sshKeyGen.Source) -Arguments @('-l', '-f', [string]$tempKeyPath)
                if ([int]$fingerprintResult.ExitCode -ne 0) {
                    continue
                }

                if ([string]$fingerprintResult.Output -match '^\s*(\d+)\s+SHA256:([A-Za-z0-9+/=]+)\s+') {
                    $bits = [string]$matches[1]
                    $fingerprint = ('{0} {1} SHA256:{2}' -f [string]$algorithm, [string]$bits, [string]$matches[2])
                    $normalizedFingerprint = [string]$fingerprint.Trim()
                    if (-not $seenFingerprints.ContainsKey($normalizedFingerprint)) {
                        $hostKeyArgs.Add('-hostkey') | Out-Null
                        $hostKeyArgs.Add($normalizedFingerprint) | Out-Null
                        $seenFingerprints[$normalizedFingerprint] = $true
                    }
                }
            }
            finally {
                Remove-Item -LiteralPath $tempKeyPath -Force -ErrorAction SilentlyContinue
            }
        }

        if ($hostKeyArgs.Count -lt 2) {
            return [pscustomobject]@{
                Success = $false
                Args = @()
                Message = ("Windows SCP transport could not build a trusted host key fingerprint for {0}:{1}." -f [string]$HostName, [string]$Port)
            }
        }

        $cachedArgs = @($hostKeyArgs.ToArray())
        $script:ClagnosWindowsScpHostKeyCache[$cacheKey] = $cachedArgs
        return [pscustomobject]@{
            Success = $true
            Args = @($cachedArgs)
            Message = ''
        }
    }
    catch {
        return [pscustomobject]@{
            Success = $false
            Args = @()
            Message = [string]$_.Exception.Message
        }
    }
}

function Get-ClagnosWindowsScpHostKeyArguments {
    param(
        [string]$HostName,
        [string]$Port
    )

    $resolution = Try-Get-ClagnosWindowsScpHostKeyArguments -HostName $HostName -Port $Port
    if (-not [bool]$resolution.Success) {
        throw [string]$resolution.Message
    }

    return @($resolution.Args)
}

function Resolve-ClagnosWindowsScpHostKeyArguments {
    param(
        [string]$HostName,
        [string]$Port
    )

    $resolution = Try-Get-ClagnosWindowsScpHostKeyArguments -HostName $HostName -Port $Port
    if ([bool]$resolution.Success) {
        return $resolution
    }

    if (-not (Test-ClagnosWindowsScpFallbackCandidate -Message $resolution.Message)) {
        throw [string]$resolution.Message
    }

    return $resolution
}

function Test-ClagnosWindowsScpFallbackCandidate {
    param(
        [AllowNull()]
        [string]$Message
    )

    if ([string]::IsNullOrWhiteSpace([string]$Message)) {
        return $false
    }

    foreach ($fragment in @(
            'Windows SCP transport could not resolve an SSH host key',
            'Windows SCP transport could not build a trusted host key fingerprint',
            'Windows SCP transport requires pscp.exe',
            'Windows SCP transport requires ssh-keyscan.exe and ssh-keygen.exe'
        )) {
        if ([string]$Message -like ('*' + [string]$fragment + '*')) {
            return $true
        }
    }

    return $false
}

function New-ClagnosWindowsScpPasswordFilePath {
    param(
        [string]$Password
    )

    $passwordFilePath = Join-Path ([System.IO.Path]::GetTempPath()) ('clagnos-pscp-password-' + ([guid]::NewGuid().ToString('N')) + '.txt')
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($passwordFilePath, [string]$Password, $utf8NoBom)
    return [string]$passwordFilePath
}

function Invoke-ClagnosRemotePowerShellExec {
    param(
        [string]$PySshPythonPath,
        [string]$PySshClientPath,
        [string]$HostName,
        [string]$UserName,
        [string]$Password,
        [string]$Port,
        [string]$ScriptText,
        [string]$StdinFilePath = '',
        [long]$StdinFileOffsetBytes = 0,
        [long]$StdinFileLengthBytes = -1,
        [string]$Label,
        [int]$TimeoutSeconds = 30,
        [switch]$SuppressTrackedLogging
    )

    if ($TimeoutSeconds -lt 5) { $TimeoutSeconds = 5 }
    if ($TimeoutSeconds -gt 300) { $TimeoutSeconds = 300 }

    $encodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes([string]$ScriptText))
    $arguments = @(
        [string]$PySshClientPath,
        'exec',
        '--host', [string]$HostName,
        '--port', [string]$Port,
        '--user', [string]$UserName,
        '--password', [string]$Password,
        '--timeout', [string]$TimeoutSeconds,
        '--command', ('powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand {0}' -f [string]$encodedCommand)
    )
    if (-not [string]::IsNullOrWhiteSpace([string]$StdinFilePath)) {
        $arguments += @('--stdin-file', [string]$StdinFilePath)
        if ($StdinFileOffsetBytes -gt 0) {
            $arguments += @('--stdin-file-offset', [string]$StdinFileOffsetBytes)
        }
        if ($StdinFileLengthBytes -ge 0) {
            $arguments += @('--stdin-file-length', [string]$StdinFileLengthBytes)
        }
    }
    return (Invoke-ClagnosProcessWithRetry `
        -FilePath $PySshPythonPath `
        -Arguments $arguments `
        -Label $Label `
        -MaxAttempts 1 `
        -SuppressTrackedLogging:$SuppressTrackedLogging)
}

function Invoke-ClagnosRemotePowerShellCommandTextExec {
    param(
        [string]$PySshPythonPath,
        [string]$PySshClientPath,
        [string]$HostName,
        [string]$UserName,
        [string]$Password,
        [string]$Port,
        [string]$ScriptText,
        [string]$Label,
        [int]$TimeoutSeconds = 30,
        [switch]$SuppressTrackedLogging
    )

    if ($TimeoutSeconds -lt 5) { $TimeoutSeconds = 5 }
    if ($TimeoutSeconds -gt 300) { $TimeoutSeconds = 300 }

    $commandScriptText = ([string]$ScriptText).Replace('"', '""')
    $arguments = @(
        [string]$PySshClientPath,
        'exec',
        '--host', [string]$HostName,
        '--port', [string]$Port,
        '--user', [string]$UserName,
        '--password', [string]$Password,
        '--timeout', [string]$TimeoutSeconds,
        '--command', ('powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "{0}"' -f [string]$commandScriptText)
    )

    return (Invoke-ClagnosProcessWithRetry `
        -FilePath $PySshPythonPath `
        -Arguments $arguments `
        -Label $Label `
        -MaxAttempts 1 `
        -SuppressTrackedLogging:$SuppressTrackedLogging)
}

function Get-ClagnosWindowsRemoteFileMetadata {
    param(
        [string]$PySshPythonPath,
        [string]$PySshClientPath,
        [string]$HostName,
        [string]$UserName,
        [string]$Password,
        [string]$Port,
        [string]$RemotePath,
        [int]$ConnectTimeoutSeconds = 30
    )

    $escapedRemotePath = ConvertTo-ClagnosPowerShellSingleQuotedLiteral -Value ([string]$RemotePath)
    $metadataScript = @(
        "`$path = '$escapedRemotePath'"
        "if (-not (Test-Path -LiteralPath `$path)) {"
        "    Write-Host 'missing'"
        "    exit 0"
        "}"
        "`$item = Get-Item -LiteralPath `$path -ErrorAction Stop"
        "`$hash = ''"
        "try {"
        "    `$sha256 = [System.Security.Cryptography.SHA256]::Create()"
        "    try {"
        "        `$stream = [System.IO.File]::OpenRead(`$path)"
        "        try {"
        "            `$hashBytes = `$sha256.ComputeHash(`$stream)"
        "            `$hash = ([System.BitConverter]::ToString(`$hashBytes)).Replace('-', '')"
        "        }"
        "        finally {"
        "            if (`$null -ne `$stream) { `$stream.Dispose() }"
        "        }"
        "    }"
        "    finally {"
        "        if (`$null -ne `$sha256) { `$sha256.Dispose() }"
        "    }"
        "}"
        "catch { }"
        "Write-Host ('present length={0} sha256={1}' -f [int64]`$item.Length, [string]`$hash)"
        "exit 0"
    ) -join "`n"

    $result = Invoke-ClagnosRemotePowerShellExec `
        -PySshPythonPath $PySshPythonPath `
        -PySshClientPath $PySshClientPath `
        -HostName $HostName `
        -UserName $UserName `
        -Password $Password `
        -Port $Port `
        -ScriptText $metadataScript `
        -Label ("pyssh inspect asset -> {0}" -f [string]$RemotePath) `
        -TimeoutSeconds $ConnectTimeoutSeconds `
        -SuppressTrackedLogging

    $outputText = [string]$result.Output
    $exists = $false
    $length = 0
    $sha256 = ''
    if ($outputText -match 'present\s+length=(\d+)\s+sha256=([A-Fa-f0-9]*)') {
        $exists = $true
        $length = [int64]$matches[1]
        $sha256 = ([string]$matches[2]).Trim().ToUpperInvariant()
    }

    return [pscustomobject]@{
        Exists = [bool]$exists
        Length = [int64]$length
        Sha256 = [string]$sha256
    }
}

function Copy-ClagnosAssetToWindowsViaExec {
    param(
        [string]$PySshPythonPath,
        [string]$PySshClientPath,
        [string]$HostName,
        [string]$UserName,
        [string]$Password,
        [string]$Port,
        [string]$LocalPath,
        [string]$RemotePath,
        [int]$ConnectTimeoutSeconds = 30
    )

    $resolvedLocalPath = (Resolve-Path -LiteralPath $LocalPath).Path
    $fileInfo = Get-Item -LiteralPath $resolvedLocalPath -ErrorAction Stop
    $fileHash = Get-ClagnosFileSha256 -Path $resolvedLocalPath
    $escapedRemotePath = ConvertTo-ClagnosPowerShellSingleQuotedLiteral -Value ([string]$RemotePath)
    $stagingRemotePath = ('{0}.upload-{1}' -f [string]$RemotePath, ([guid]::NewGuid().ToString('N')))
    $escapedStagingRemotePath = ConvertTo-ClagnosPowerShellSingleQuotedLiteral -Value ([string]$stagingRemotePath)
    $remoteMetadata = $null
    try {
        $remoteMetadata = Get-ClagnosWindowsRemoteFileMetadata `
            -PySshPythonPath $PySshPythonPath `
            -PySshClientPath $PySshClientPath `
            -HostName $HostName `
            -UserName $UserName `
            -Password $Password `
            -Port $Port `
            -RemotePath $RemotePath `
            -ConnectTimeoutSeconds $ConnectTimeoutSeconds
    }
    catch { }

    if ($null -ne $remoteMetadata -and [bool]$remoteMetadata.Exists -and
        [int64]$remoteMetadata.Length -eq [int64]$fileInfo.Length -and
        -not [string]::IsNullOrWhiteSpace([string]$remoteMetadata.Sha256) -and
        [string]::Equals([string]$remoteMetadata.Sha256, [string]$fileHash, [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Host ("Task asset copy skipped: {0} -> {1} (cache hit, sha256={2})" -f [System.IO.Path]::GetFileName($resolvedLocalPath), [string]$RemotePath, [string]$fileHash.Substring(0, 12))
        return [pscustomobject]@{
            RemotePath = [string]$RemotePath
            Copied = $false
            Bytes = [int64]$fileInfo.Length
            ChunkCount = 0
            Sha256 = [string]$fileHash
        }
    }

    $remoteSpec = ConvertTo-ClagnosWindowsScpRemoteSpec -HostName $HostName -RemotePath $stagingRemotePath
    Write-Host ("Task asset copy started: {0} -> {1} (mode=windows-scp, bytes={2})" -f [System.IO.Path]::GetFileName($resolvedLocalPath), [string]$RemotePath, [int64]$fileInfo.Length)
    $transferWatch = [System.Diagnostics.Stopwatch]::StartNew()
    $passwordFilePath = ''
    try {
        $pscpPath = Get-ClagnosPscpExecutablePath
        $hostKeyResolution = Resolve-ClagnosWindowsScpHostKeyArguments -HostName $HostName -Port $Port
        if (-not [bool]$hostKeyResolution.Success) {
            Write-Host ("Task asset copy fallback: pyssh windows copy -> {0} ({1})" -f [string]$RemotePath, [string]$hostKeyResolution.Message)
            $copyArgs = @(
                [string]$PySshClientPath,
                "copy",
                "--host", [string]$HostName,
                "--port", [string]$Port,
                "--user", [string]$UserName,
                "--password", [string]$Password,
                "--timeout", [string]$ConnectTimeoutSeconds,
                "--local", [string]$resolvedLocalPath,
                "--remote", [string]$stagingRemotePath
            )
            Invoke-ClagnosProcessWithRetry -FilePath $PySshPythonPath -Arguments $copyArgs -Label ("pyssh copy asset -> {0}" -f [string]$RemotePath) -MaxAttempts 2 | Out-Null
        }
        else {
            $hostKeyArgs = @($hostKeyResolution.Args)
            $passwordFilePath = New-ClagnosWindowsScpPasswordFilePath -Password $Password
            $copyArgs = @(
                '-batch',
                '-scp',
                '-P', [string]$Port,
                '-l', [string]$UserName,
                '-pwfile', [string]$passwordFilePath
            ) + @($hostKeyArgs) + @(
                [string]$resolvedLocalPath,
                [string]$remoteSpec
            )

            Invoke-ClagnosProcessWithRetry -FilePath $pscpPath -Arguments $copyArgs -Label ("pscp copy asset -> {0}" -f [string]$RemotePath) -MaxAttempts 1 -SkipPythonBytecodeFlag | Out-Null
        }

        $finalizeScript = @(
            '$s=''' + $escapedStagingRemotePath + ''''
            '$d=''' + $escapedRemotePath + ''''
            '$expected=' + [string][int64]$fileInfo.Length
            'if(-not (Test-Path -LiteralPath $s)){throw ''Uploaded staging file is missing.''}'
            '$item=Get-Item -LiteralPath $s -ErrorAction Stop'
            'if([int64]$item.Length -ne [int64]$expected){throw (''Uploaded staging length mismatch: {0} <> {1}'' -f [int64]$item.Length,[int64]$expected)}'
            'if(Test-Path -LiteralPath $d){Remove-Item -LiteralPath $d -Force -EA SilentlyContinue}'
            'Move-Item -LiteralPath $s -Destination $d -Force'
        ) -join ';'
        Invoke-ClagnosRemotePowerShellCommandTextExec `
            -PySshPythonPath $PySshPythonPath `
            -PySshClientPath $PySshClientPath `
            -HostName $HostName `
            -UserName $UserName `
            -Password $Password `
            -Port $Port `
            -ScriptText $finalizeScript `
            -Label ("pyssh asset finalize -> {0}" -f [string]$RemotePath) `
            -TimeoutSeconds ([Math]::Max(30, $ConnectTimeoutSeconds)) `
            -SuppressTrackedLogging | Out-Null
    }
    finally {
        if (-not [string]::IsNullOrWhiteSpace([string]$passwordFilePath)) {
            Remove-Item -LiteralPath $passwordFilePath -Force -ErrorAction SilentlyContinue
        }
        if ($transferWatch.IsRunning) {
            $transferWatch.Stop()
        }
    }

    $verifiedMetadata = Get-ClagnosWindowsRemoteFileMetadata `
        -PySshPythonPath $PySshPythonPath `
        -PySshClientPath $PySshClientPath `
        -HostName $HostName `
        -UserName $UserName `
        -Password $Password `
        -Port $Port `
        -RemotePath $RemotePath `
        -ConnectTimeoutSeconds $ConnectTimeoutSeconds
    if (-not [bool]$verifiedMetadata.Exists -or
        [int64]$verifiedMetadata.Length -ne [int64]$fileInfo.Length -or
        [string]::IsNullOrWhiteSpace([string]$verifiedMetadata.Sha256) -or
        -not [string]::Equals([string]$verifiedMetadata.Sha256, [string]$fileHash, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw ("Windows SCP asset verification failed for {0}." -f [string]$RemotePath)
    }

    Write-Host ("Task asset copy completed: {0} -> {1} (mode=windows-copy, bytes={2}, chunks={3}, elapsed={4:N1}s)" -f [System.IO.Path]::GetFileName($resolvedLocalPath), [string]$RemotePath, [int64]$fileInfo.Length, 1, $transferWatch.Elapsed.TotalSeconds)

    return [pscustomobject]@{
        RemotePath = [string]$RemotePath
        Copied = $true
        Bytes = [int64]$fileInfo.Length
        ChunkCount = 1
        Sha256 = [string]$fileHash
    }
}

# Handles Copy-ClagnosAssetToVm.
function Copy-ClagnosAssetToVm {
    param(
        [string]$PySshPythonPath,
        [string]$PySshClientPath,
        [string]$HostName,
        [string]$UserName,
        [string]$Password,
        [string]$Port,
        [string]$LocalPath,
        [string]$RemotePath,
        [int]$ConnectTimeoutSeconds = 30
    )

    if ([string]::IsNullOrWhiteSpace([string]$LocalPath) -or -not (Test-Path -LiteralPath $LocalPath)) {
        throw ("Task asset was not found: {0}" -f $LocalPath)
    }
    if ([string]::IsNullOrWhiteSpace([string]$RemotePath)) {
        throw "Task asset remote path is empty."
    }
    if ($ConnectTimeoutSeconds -lt 5) { $ConnectTimeoutSeconds = 5 }
    if ($ConnectTimeoutSeconds -gt 300) { $ConnectTimeoutSeconds = 300 }

    if (Test-ClagnosWindowsRemotePath -RemotePath $RemotePath) {
        return (Copy-ClagnosAssetToWindowsViaExec `
            -PySshPythonPath $PySshPythonPath `
            -PySshClientPath $PySshClientPath `
            -HostName $HostName `
            -UserName $UserName `
            -Password $Password `
            -Port $Port `
            -LocalPath $LocalPath `
            -RemotePath $RemotePath `
            -ConnectTimeoutSeconds $ConnectTimeoutSeconds)
    }

    $copyArgs = @(
        [string]$PySshClientPath,
        "copy",
        "--host", [string]$HostName,
        "--port", [string]$Port,
        "--user", [string]$UserName,
        "--password", [string]$Password,
        "--timeout", [string]$ConnectTimeoutSeconds,
        "--local", [string]$LocalPath,
        "--remote", [string]$RemotePath
    )

    Invoke-ClagnosProcessWithRetry -FilePath $PySshPythonPath -Arguments $copyArgs -Label ("pyssh copy asset -> {0}" -f [string]$RemotePath) -MaxAttempts 2 | Out-Null
}

# Handles Copy-ClagnosAssetFromVm.
function Copy-ClagnosAssetFromVm {
    param(
        [string]$PySshPythonPath,
        [string]$PySshClientPath,
        [string]$HostName,
        [string]$UserName,
        [string]$Password,
        [string]$Port,
        [string]$RemotePath,
        [string]$LocalPath,
        [int]$ConnectTimeoutSeconds = 30
    )

    if ([string]::IsNullOrWhiteSpace([string]$RemotePath)) {
        throw "Task asset remote path is empty."
    }
    if ([string]::IsNullOrWhiteSpace([string]$LocalPath)) {
        throw "Task asset local path is empty."
    }
    if ($ConnectTimeoutSeconds -lt 5) { $ConnectTimeoutSeconds = 5 }
    if ($ConnectTimeoutSeconds -gt 300) { $ConnectTimeoutSeconds = 300 }

    $localParent = Split-Path -Path $LocalPath -Parent
    if (-not [string]::IsNullOrWhiteSpace([string]$localParent) -and -not (Test-Path -LiteralPath $localParent)) {
        New-Item -Path $localParent -ItemType Directory -Force | Out-Null
    }
    if (Test-Path -LiteralPath $LocalPath) {
        Remove-Item -LiteralPath $LocalPath -Force -ErrorAction SilentlyContinue
    }

    if (Test-ClagnosWindowsRemotePath -RemotePath $RemotePath) {
        $pscpPath = Get-ClagnosPscpExecutablePath
        $remoteSpec = ConvertTo-ClagnosWindowsScpRemoteSpec -HostName $HostName -RemotePath $RemotePath
        $hostKeyResolution = Resolve-ClagnosWindowsScpHostKeyArguments -HostName $HostName -Port $Port
        if (-not [bool]$hostKeyResolution.Success) {
            Write-Host ("Task asset fetch fallback: pyssh windows fetch <- {0} ({1})" -f [string]$RemotePath, [string]$hostKeyResolution.Message)
        }
        else {
            $hostKeyArgs = @($hostKeyResolution.Args)
            $passwordFilePath = New-ClagnosWindowsScpPasswordFilePath -Password $Password
            try {
                $fetchArgs = @(
                    '-batch',
                    '-scp',
                    '-P', [string]$Port,
                    '-l', [string]$UserName,
                    '-pwfile', [string]$passwordFilePath
                ) + @($hostKeyArgs) + @(
                    [string]$remoteSpec,
                    [string]$LocalPath
                )

                Invoke-ClagnosProcessWithRetry -FilePath $pscpPath -Arguments $fetchArgs -Label ("pscp fetch asset <- {0}" -f [string]$RemotePath) -MaxAttempts 1 -SkipPythonBytecodeFlag | Out-Null
            }
            finally {
                if (-not [string]::IsNullOrWhiteSpace([string]$passwordFilePath)) {
                    Remove-Item -LiteralPath $passwordFilePath -Force -ErrorAction SilentlyContinue
                }
            }
        }

        if (Test-Path -LiteralPath $LocalPath) {
            return
        }
    }

    $fetchArgs = @(
        [string]$PySshClientPath,
        "fetch",
        "--host", [string]$HostName,
        "--port", [string]$Port,
        "--user", [string]$UserName,
        "--password", [string]$Password,
        "--timeout", [string]$ConnectTimeoutSeconds,
        "--remote", [string]$RemotePath,
        "--local", [string]$LocalPath
    )

    Invoke-ClagnosProcessWithRetry -FilePath $PySshPythonPath -Arguments $fetchArgs -Label ("pyssh fetch asset <- {0}" -f [string]$RemotePath) -MaxAttempts 1 | Out-Null
}
