Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-ClagnosChocolateyRoot {
    $configuredRoot = [string][Environment]::GetEnvironmentVariable('ChocolateyInstall','Machine')
    if ([string]::IsNullOrWhiteSpace($configuredRoot)) { $configuredRoot = [string]$env:ChocolateyInstall }
    if ([string]::IsNullOrWhiteSpace($configuredRoot)) { $configuredRoot = Join-Path $env:ProgramData 'chocolatey' }
    return [IO.Path]::GetFullPath($configuredRoot.Trim())
}

function Get-ClagnosChocolateyPackageExecutableRecord {
    param(
        [Parameter(Mandatory = $true)][string]$PackageId,
        [Parameter(Mandatory = $true)][string]$ExecutableName,
        [string]$VersionArgument = '-version',
        [string[]]$AdditionalPaths = @()
    )

    if ($PackageId -notmatch '^[A-Za-z0-9._-]+$' -or [IO.Path]::GetFileName($ExecutableName) -cne $ExecutableName -or $ExecutableName -notmatch '^[A-Za-z0-9._-]+\.exe$' -or $VersionArgument -notmatch '^--?[A-Za-z0-9][A-Za-z0-9-]*$') {
        return [pscustomobject]@{ Status = 'unknown'; Path = ''; VersionText = ''; Detail = 'Chocolatey executable health-check metadata is invalid.' }
    }

    $root = Get-ClagnosChocolateyRoot
    $toolsRoot = Join-Path (Join-Path (Join-Path $root 'lib') $PackageId) 'tools'
    $executableStem = [IO.Path]::GetFileNameWithoutExtension($ExecutableName)
    $versionPattern = '(?i)\b{0}\s+version\b' -f [regex]::Escape($executableStem)
    $candidatePaths = New-Object 'System.Collections.Generic.List[string]'
    $shimPath = Join-Path (Join-Path $root 'bin') $ExecutableName
    if (Test-Path -LiteralPath $shimPath -PathType Leaf) { $candidatePaths.Add([IO.Path]::GetFullPath($shimPath)) | Out-Null }
    foreach ($rawPath in @($AdditionalPaths)) {
        $candidatePath = [Environment]::ExpandEnvironmentVariables([string]$rawPath)
        if ([IO.Path]::IsPathRooted($candidatePath) -and (Test-Path -LiteralPath $candidatePath -PathType Leaf)) {
            $fullPath = [IO.Path]::GetFullPath($candidatePath)
            if (-not $candidatePaths.Contains($fullPath)) { $candidatePaths.Add($fullPath) | Out-Null }
        }
    }
    if (Test-Path -LiteralPath $toolsRoot -PathType Container) {
        foreach ($candidate in @(Get-ChildItem -LiteralPath $toolsRoot -Filter $ExecutableName -File -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending)) {
            $candidatePath = [IO.Path]::GetFullPath([string]$candidate.FullName)
            if (-not $candidatePaths.Contains($candidatePath)) { $candidatePaths.Add($candidatePath) | Out-Null }
        }
    }

    $sawExecutable = ($candidatePaths.Count -gt 0)
    foreach ($candidatePath in @($candidatePaths.ToArray())) {
        $previousErrorActionPreference = $ErrorActionPreference
        $outputLines = @()
        $exitCode = -1
        try {
            $ErrorActionPreference = 'Continue'
            $outputLines = @(& $candidatePath $VersionArgument 2>&1 | ForEach-Object { [string]$_ })
            $exitCode = [int]$LASTEXITCODE
        }
        catch { $outputLines = @([string]$_.Exception.Message) }
        finally { $ErrorActionPreference = $previousErrorActionPreference }

        $versionText = (@($outputLines | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) -join ' ').Trim()
        if ($exitCode -eq 0 -and $versionText -match $versionPattern) {
            return [pscustomobject]@{ Status = 'installed'; Path = $candidatePath; VersionText = $versionText; Detail = 'Chocolatey package executable is present and runnable.' }
        }
    }

    if ($sawExecutable) {
            return [pscustomobject]@{ Status = 'installed-drifted'; Path = [string]$candidatePaths[0]; VersionText = ''; Detail = ('Chocolatey package executable exists but did not pass its bounded {0} health check.' -f $VersionArgument) }
    }
    return [pscustomobject]@{ Status = 'not-found'; Path = ''; VersionText = ''; Detail = ('Chocolatey package executable {0} was not found in the package tools directory or Chocolatey bin directory.' -f $ExecutableName) }
}

function Write-ClagnosPackageResult {
    param([hashtable]$Result)
    Write-Output ('CLAGNOS_PACKAGE_RESULT:' + (ConvertTo-Json -InputObject $Result -Depth 8 -Compress))
}

function Invoke-ClagnosNpmPackageLifecycleCommand {
    param([Parameter(Mandatory = $true)][ValidateSet('repair','update')][string]$Operation,[Parameter(Mandatory = $true)][string[]]$Arguments)

    $command = Get-Command npm.cmd -ErrorAction SilentlyContinue
    if (-not $command) { $command = Get-Command npm -ErrorAction Stop }
    $previousErrorActionPreference = $ErrorActionPreference
    $nativeOutput = @()
    $exitCode = 0
    try {
        $ErrorActionPreference = 'Continue'
        $nativeOutput = @(& $command.Source @Arguments 2>&1)
        $exitCode = [int]$LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previousErrorActionPreference }

    $outputLines = @($nativeOutput | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    $policyWarning = (@($outputLines | Where-Object { [string]$_ -match '(?i)^npm warn install-scripts\b' }).Count -gt 0)
    $outputText = @($outputLines) -join [Environment]::NewLine
    if ($exitCode -ne 0) { throw ("npm {0} exited with code {1}. {2}" -f $Operation,$exitCode,$outputText.Trim()) }
    return [pscustomobject]@{ Output = $outputText; ExitCode = $exitCode; InstallScriptPolicyWarning = [bool]$policyWarning }
}

function Set-ClagnosPackageLifecyclePhase {
    param([Parameter(Mandatory = $true)][string]$Phase)

    $global:CLAGNOS_PACKAGE_LIFECYCLE_PHASE = [string]$Phase
    $statePath = ''
    $stateVariable = Get-Variable -Name CLAGNOS_PACKAGE_RUN_STATE_PATH -Scope Global -ErrorAction SilentlyContinue
    if ($null -ne $stateVariable) { $statePath = [string]$stateVariable.Value }
    if (-not [string]::IsNullOrWhiteSpace($statePath)) {
        try {
            $state = if (Test-Path -LiteralPath $statePath -PathType Leaf) { Get-Content -LiteralPath $statePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } else { [pscustomobject]@{} }
            if ($null -eq $state.PSObject.Properties['RunId']) { $state | Add-Member -NotePropertyName RunId -NotePropertyValue '' }
            if ($null -eq $state.PSObject.Properties['Task']) { $state | Add-Member -NotePropertyName Task -NotePropertyValue '' }
            if ($null -eq $state.PSObject.Properties['HostProcessId']) { $state | Add-Member -NotePropertyName HostProcessId -NotePropertyValue $PID }
            if ($null -eq $state.PSObject.Properties['StartedAtUtc']) { $state | Add-Member -NotePropertyName StartedAtUtc -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) }
            $state | Add-Member -NotePropertyName Phase -NotePropertyValue ([string]$Phase) -Force
            $state | Add-Member -NotePropertyName ProgressAtUtc -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force
            [IO.File]::WriteAllText($statePath,(ConvertTo-Json -InputObject $state -Depth 8 -Compress),(New-Object System.Text.UTF8Encoding($false)))
        }
        catch { }
    }
    Write-Output ("Doing: package lifecycle phase '{0}'" -f [string]$Phase)
}

function Get-ClagnosPackageVersionFromOutput {
    param([string]$Text,[string]$PackageId)
    foreach ($line in @([string]$Text -split "`r?`n")) {
        if ($line -match ('(?i)(?:^|\s)' + [regex]::Escape($PackageId) + '(?:\s|$)')) {
            $tokens = @($line.Trim() -split '\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
            $idIndex = -1
            for ($index = 0; $index -lt $tokens.Count; $index++) {
                if ([string]::Equals([string]$tokens[$index],[string]$PackageId,[System.StringComparison]::OrdinalIgnoreCase)) { $idIndex = $index; break }
            }
            if ($idIndex -ge 0 -and $idIndex + 1 -lt $tokens.Count -and $tokens[$idIndex + 1] -match '^\d') { return [string]$tokens[$idIndex + 1] }
            if ($line -match '(?i)\|\s*(?<version>[^|\s]+)\s*$') { return [string]$Matches.version }
        }
    }
    return ''
}

function Get-ClagnosSysinternalsPaths {
    $packageRoot = Join-Path (Join-Path (Get-ClagnosChocolateyRoot) 'lib') 'sysinternals'
    return [pscustomobject]@{
        PackageRoot = $packageRoot
        ToolsRoot = Join-Path $packageRoot 'tools'
        MarkerPath = Join-Path (Join-Path $env:ProgramData 'clagnos\state\packages') 'sysinternals.json'
        CacheRoot = Join-Path $env:ProgramData 'clagnos\cache\sysinternals'
        CacheIndexPath = Join-Path (Join-Path $env:ProgramData 'clagnos\cache\sysinternals') 'current.json'
        ChocolateyPath = Join-Path (Get-ClagnosChocolateyRoot) 'bin\choco.exe'
        SourceUrl = 'https://download.sysinternals.com/files/SysinternalsSuite.zip'
    }
}

function Get-ClagnosSysinternalsChocolateyVersion {
    param([psobject]$Paths = (Get-ClagnosSysinternalsPaths))

    if (-not (Test-Path -LiteralPath ([string]$Paths.ChocolateyPath) -PathType Leaf)) { return '' }
    try {
        $output = & ([string]$Paths.ChocolateyPath) list --local-only --exact --limit-output sysinternals 2>$null | Out-String
        if ([int]$LASTEXITCODE -ne 0) { return '' }
        $match = [regex]::Match([string]$output,'(?im)^sysinternals\|(?<version>[^\s|]+)\s*$')
        if ($match.Success) { return [string]$match.Groups['version'].Value }
    }
    catch { }
    return ''
}

function Get-ClagnosSysinternalsPackageRecord {
    param([psobject]$Spec)

    $paths = Get-ClagnosSysinternalsPaths
    $version = ''
    $detail = ''
    if (Test-Path -LiteralPath ([string]$paths.MarkerPath) -PathType Leaf) {
        try {
            $state = Get-Content -LiteralPath ([string]$paths.MarkerPath) -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            $version = [string]$state.Version
            if (-not (Test-Path -LiteralPath ([string]$paths.ToolsRoot) -PathType Container)) {
                return [pscustomobject]@{ Id = [string]$Spec.id; Status = 'installed-drifted'; Version = $version; Detail = 'Clagnos-managed Sysinternals tools directory is missing.' }
            }
            return [pscustomobject]@{ Id = [string]$Spec.id; Status = 'installed'; Version = $version; Detail = 'Clagnos-managed signed Sysinternals payload is registered.' }
        }
        catch { return [pscustomobject]@{ Id = [string]$Spec.id; Status = 'unknown'; Version = ''; Detail = 'Clagnos Sysinternals package state could not be read.' } }
    }

    $legacyVersion = Get-ClagnosSysinternalsChocolateyVersion -Paths $paths
    if (-not [string]::IsNullOrWhiteSpace($legacyVersion) -and (Test-Path -LiteralPath ([string]$paths.ToolsRoot) -PathType Container)) {
        return [pscustomobject]@{ Id = [string]$Spec.id; Status = 'installed'; Version = $legacyVersion; Detail = 'Legacy Chocolatey-managed Sysinternals payload detected.' }
    }
    if (Test-Path -LiteralPath ([string]$paths.ToolsRoot) -PathType Container) {
        return [pscustomobject]@{ Id = [string]$Spec.id; Status = 'unknown'; Version = ''; Detail = 'Sysinternals files exist without a verifiable package state.' }
    }
    return [pscustomobject]@{ Id = [string]$Spec.id; Status = 'not-installed'; Version = ''; Detail = '' }
}

function Get-ClagnosSysinternalsPayloadReport {
    param([Parameter(Mandatory = $true)][string]$RootPath)

    if (-not (Test-Path -LiteralPath $RootPath -PathType Container)) { throw 'Sysinternals payload directory is missing.' }
    $allFiles = @(Get-ChildItem -LiteralPath $RootPath -Recurse -File -ErrorAction Stop | Where-Object {
        [IO.Path]::GetExtension([string]$_.Name).ToLowerInvariant() -notin @('.zip','.nupkg','.ps1') -and [string]$_.Name -notlike 'clagnos-*-state.json'
    })
    $binaries = @($allFiles | Where-Object { [IO.Path]::GetExtension([string]$_.Name).ToLowerInvariant() -in @('.exe','.dll') })
    if ($binaries.Count -lt 20) { throw ("Sysinternals payload contains only {0} signed executable/library candidates; at least 20 are required." -f $binaries.Count) }
    $invalidSignatures = New-Object 'System.Collections.Generic.List[string]'
    foreach ($binary in @($binaries)) {
        $signature = Get-AuthenticodeSignature -LiteralPath ([string]$binary.FullName) -ErrorAction Stop
        $subject = if ($null -ne $signature.SignerCertificate) { [string]$signature.SignerCertificate.Subject } else { '' }
        if ([string]$signature.Status -ne 'Valid' -or $subject -notmatch '(?i)Microsoft Corporation') {
            $invalidSignatures.Add([string]$binary.Name) | Out-Null
        }
    }
    $fingerprintLines = New-Object 'System.Collections.Generic.List[string]'
    $rootPrefix = [IO.Path]::GetFullPath($RootPath).TrimEnd('\') + '\'
    foreach ($file in @($allFiles | Sort-Object FullName)) {
        $relative = [IO.Path]::GetFullPath([string]$file.FullName).Substring($rootPrefix.Length).Replace('\','/')
        $hash = [string](Get-FileHash -LiteralPath ([string]$file.FullName) -Algorithm SHA256 -ErrorAction Stop).Hash
        $fingerprintLines.Add(('{0}|{1}|{2}' -f $relative,[int64]$file.Length,$hash)) | Out-Null
    }
    $bytes = [Text.Encoding]::UTF8.GetBytes(($fingerprintLines.ToArray() -join "`n"))
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $fingerprint = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','') }
    finally { $sha.Dispose() }
    return [pscustomobject]@{
        Healthy = ($invalidSignatures.Count -eq 0)
        Fingerprint = [string]$fingerprint
        FileCount = [int]$allFiles.Count
        SignedBinaryCount = [int]$binaries.Count
        InvalidSignatures = @($invalidSignatures.ToArray())
    }
}

function Get-ClagnosSysinternalsRemoteHeaders {
    param([psobject]$Paths = (Get-ClagnosSysinternalsPaths))

    try {
        $request = [System.Net.HttpWebRequest]::Create([string]$Paths.SourceUrl)
        $request.Method = 'HEAD'
        $request.AllowAutoRedirect = $true
        $request.Timeout = 20000
        $request.ReadWriteTimeout = 20000
        $request.UserAgent = 'Clagnos Sysinternals Package Manager'
        $response = $request.GetResponse()
        try {
            return [pscustomobject]@{
                ETag = [string]$response.Headers['ETag']
                LastModifiedUtc = if ($response.LastModified -gt [DateTime]::MinValue) { $response.LastModified.ToUniversalTime().ToString('o') } else { '' }
                ContentLength = [int64]$response.ContentLength
            }
        }
        finally { $response.Close() }
    }
    catch { return [pscustomobject]@{ ETag = ''; LastModifiedUtc = ''; ContentLength = -1 } }
}

function New-ClagnosSysinternalsArtifact {
    param([Parameter(Mandatory = $true)][string]$ZipPath,[Parameter(Mandatory = $true)][string]$ArtifactRoot,[psobject]$RemoteMetadata = $null)

    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
    $archiveHash = [string](Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256 -ErrorAction Stop).Hash
    $extractRoot = Join-Path $ArtifactRoot 'payload'
    New-Item -ItemType Directory -Path $extractRoot -Force | Out-Null
    $archive = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        $totalBytes = [int64]0
        foreach ($entry in @($archive.Entries)) {
            $relative = ([string]$entry.FullName).Replace('/','\')
            if ([string]::IsNullOrWhiteSpace($relative) -or [IO.Path]::IsPathRooted($relative) -or $relative -match '(^|\\)\.\.(\\|$)') { throw ('Sysinternals archive contains an unsafe path: ' + [string]$entry.FullName) }
            $totalBytes += [int64]$entry.Length
            if ($totalBytes -gt 2GB) { throw 'Sysinternals archive expands beyond the 2GB safety bound.' }
        }
    }
    finally { $archive.Dispose() }
    [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath,$extractRoot)
    $payload = Get-ClagnosSysinternalsPayloadReport -RootPath $extractRoot
    if (-not [bool]$payload.Healthy) { throw ('Sysinternals payload signature verification failed for: ' + (@($payload.InvalidSignatures) -join ', ')) }
    $lastModifiedUtc = if ($null -ne $RemoteMetadata) { [string]$RemoteMetadata.LastModifiedUtc } else { '' }
    $etag = if ($null -ne $RemoteMetadata) { [string]$RemoteMetadata.ETag } else { '' }
    $dateVersion = ''
    if (-not [string]::IsNullOrWhiteSpace($lastModifiedUtc)) {
        try { $dateVersion = ([DateTime]::Parse($lastModifiedUtc).ToUniversalTime().ToString('yyyy.M.d')) } catch { $dateVersion = '' }
    }
    $version = if ([string]::IsNullOrWhiteSpace($dateVersion)) { 'payload-' + $archiveHash.Substring(0,12).ToLowerInvariant() } else { $dateVersion + '+' + $archiveHash.Substring(0,12).ToLowerInvariant() }
    return [pscustomobject]@{
        ArtifactRoot = [string]$ArtifactRoot
        ZipPath = [string]$ZipPath
        ArchiveSha256 = [string]$archiveHash
        ExtractRoot = [string]$extractRoot
        RemoteETag = [string]$etag
        LastModifiedUtc = [string]$lastModifiedUtc
        Version = [string]$version
        PayloadReport = $payload
    }
}

function Save-ClagnosSysinternalsArtifactCache {
    param([psobject]$Artifact)

    $paths = Get-ClagnosSysinternalsPaths
    New-Item -ItemType Directory -Path ([string]$paths.CacheRoot) -Force | Out-Null
    $cachedZip = Join-Path ([string]$paths.CacheRoot) ([string]$Artifact.ArchiveSha256 + '.zip')
    if (-not (Test-Path -LiteralPath $cachedZip -PathType Leaf)) { Copy-Item -LiteralPath ([string]$Artifact.ZipPath) -Destination $cachedZip -Force -ErrorAction Stop }
    $index = [ordered]@{
        Version = [string]$Artifact.Version
        ArchiveSha256 = [string]$Artifact.ArchiveSha256
        RemoteETag = [string]$Artifact.RemoteETag
        LastModifiedUtc = [string]$Artifact.LastModifiedUtc
        CachedZip = [string]$cachedZip
        UpdatedAtUtc = [DateTime]::UtcNow.ToString('o')
    }
    [IO.File]::WriteAllText([string]$paths.CacheIndexPath,(ConvertTo-Json -InputObject $index -Depth 8 -Compress),(New-Object Text.UTF8Encoding($false)))
    return $index
}

function Get-ClagnosSysinternalsCachedArtifact {
    param([string]$ArtifactRoot)

    $paths = Get-ClagnosSysinternalsPaths
    if (-not (Test-Path -LiteralPath ([string]$paths.CacheIndexPath) -PathType Leaf)) { return $null }
    try { $index = Get-Content -LiteralPath ([string]$paths.CacheIndexPath) -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
    catch { return $null }
    $zipPath = [string]$index.CachedZip
    if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) { return $null }
    $actualHash = [string](Get-FileHash -LiteralPath $zipPath -Algorithm SHA256 -ErrorAction Stop).Hash
    if (-not [string]::Equals($actualHash,[string]$index.ArchiveSha256,[StringComparison]::OrdinalIgnoreCase)) { return $null }
    $metadata = [pscustomobject]@{ ETag = [string]$index.RemoteETag; LastModifiedUtc = [string]$index.LastModifiedUtc; ContentLength = [int64](Get-Item -LiteralPath $zipPath).Length }
    return (New-ClagnosSysinternalsArtifact -ZipPath $zipPath -ArtifactRoot $ArtifactRoot -RemoteMetadata $metadata)
}

function Get-ClagnosSysinternalsLatestArtifact {
    param()

    $paths = Get-ClagnosSysinternalsPaths
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
    $artifactRoot = Join-Path ([IO.Path]::GetTempPath()) ('clagnos-sysinternals-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null
    $zipPath = Join-Path $artifactRoot 'SysinternalsSuite.zip'
    $request = [System.Net.HttpWebRequest]::Create([string]$paths.SourceUrl)
    $request.Method = 'GET'
    $request.AllowAutoRedirect = $true
    $request.Timeout = 360000
    $request.ReadWriteTimeout = 30000
    $request.UserAgent = 'Clagnos Sysinternals Package Manager'
    $response = $null
    $inputStream = $null
    $outputStream = $null
    try {
        Write-Host 'Doing: download the official Microsoft Sysinternals suite over HTTPS'
        $response = $request.GetResponse()
        $contentLength = [int64]$response.ContentLength
        if ($contentLength -gt 2GB) { throw 'Official Sysinternals download exceeds the 2GB safety bound.' }
        $metadata = [pscustomobject]@{
            ETag = [string]$response.Headers['ETag']
            LastModifiedUtc = if ($response.LastModified -gt [DateTime]::MinValue) { $response.LastModified.ToUniversalTime().ToString('o') } else { '' }
            ContentLength = $contentLength
        }
        $inputStream = $response.GetResponseStream()
        $outputStream = [IO.File]::Open($zipPath,[IO.FileMode]::Create,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $buffer = New-Object byte[] (1024 * 1024)
        $downloaded = [int64]0
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $nextProgressSeconds = 15
        while (($read = $inputStream.Read($buffer,0,$buffer.Length)) -gt 0) {
            $outputStream.Write($buffer,0,$read)
            $downloaded += [int64]$read
            if ($watch.Elapsed.TotalSeconds -ge $nextProgressSeconds) {
                Write-Host ("Doing: download official Sysinternals archive ({0:N0}/{1:N0} MB)" -f ($downloaded / 1MB),($(if ($contentLength -gt 0) { $contentLength / 1MB } else { 0 })))
                $nextProgressSeconds += 15
            }
        }
        $outputStream.Flush()
        $watch.Stop()
        if ($contentLength -gt 0 -and $downloaded -ne $contentLength) { throw ("Sysinternals download length mismatch: received {0} of {1} bytes." -f $downloaded,$contentLength) }
        $inputStream.Dispose(); $inputStream = $null
        $outputStream.Dispose(); $outputStream = $null
        $response.Close(); $response = $null
        $artifact = New-ClagnosSysinternalsArtifact -ZipPath $zipPath -ArtifactRoot $artifactRoot -RemoteMetadata $metadata
        $null = Save-ClagnosSysinternalsArtifactCache -Artifact $artifact
        Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
        return $artifact
    }
    catch {
        if (Test-Path -LiteralPath $zipPath -PathType Leaf) { Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $artifactRoot -PathType Container) { Remove-Item -LiteralPath $artifactRoot -Recurse -Force -ErrorAction SilentlyContinue }
        throw
    }
    finally {
        if ($null -ne $inputStream) { $inputStream.Dispose() }
        if ($null -ne $outputStream) { $outputStream.Dispose() }
        if ($null -ne $response) { $response.Close() }
    }
}

function Set-ClagnosSysinternalsMachinePathEntry {
    param([string]$Entry,[switch]$Remove)

    $normalized = [IO.Path]::GetFullPath([string]$Entry).TrimEnd('\')
    $machinePath = [string][Environment]::GetEnvironmentVariable('Path','Machine')
    $entries = @($machinePath -split ';' | ForEach-Object { ([string]$_).Trim().TrimEnd('\') } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($Remove) { $entries = @($entries | Where-Object { -not [string]::Equals([string]$_,$normalized,[StringComparison]::OrdinalIgnoreCase) }) }
    elseif (@($entries | Where-Object { [string]::Equals([string]$_,$normalized,[StringComparison]::OrdinalIgnoreCase) }).Count -eq 0) { $entries += $normalized }
    $newValue = @($entries) -join ';'
    [Environment]::SetEnvironmentVariable('Path',$newValue,'Machine')
    if ($Remove) { $env:PATH = @(([string]$env:PATH -split ';') | Where-Object { -not [string]::Equals(([string]$_).Trim().TrimEnd('\'),$normalized,[StringComparison]::OrdinalIgnoreCase) }) -join ';' }
    else { $env:PATH = [string]$env:PATH + ';' + $normalized }
}

function Set-ClagnosSysinternalsState {
    param([psobject]$Artifact)

    $paths = Get-ClagnosSysinternalsPaths
    $report = Get-ClagnosSysinternalsPayloadReport -RootPath ([string]$paths.ToolsRoot)
    if (-not [bool]$report.Healthy) { throw ('Sysinternals install verification failed for: ' + (@($report.InvalidSignatures) -join ', ')) }
    $directory = Split-Path -Parent ([string]$paths.MarkerPath)
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $state = [ordered]@{
        Id = 'sysinternals'
        Version = [string]$Artifact.Version
        Source = 'https://download.sysinternals.com/files/SysinternalsSuite.zip'
        ArchiveSha256 = [string]$Artifact.ArchiveSha256
        ContentFingerprint = [string]$report.Fingerprint
        RemoteETag = [string]$Artifact.RemoteETag
        LastModifiedUtc = [string]$Artifact.LastModifiedUtc
        FileCount = [int]$report.FileCount
        SignedBinaryCount = [int]$report.SignedBinaryCount
        VerifiedAtUtc = [DateTime]::UtcNow.ToString('o')
    }
    [IO.File]::WriteAllText([string]$paths.MarkerPath,(ConvertTo-Json -InputObject $state -Depth 12 -Compress),(New-Object Text.UTF8Encoding($false)))
    Set-ClagnosSysinternalsMachinePathEntry -Entry ([string]$paths.ToolsRoot)
    return [pscustomobject]$state
}

function Install-ClagnosSysinternalsArtifact {
    param([Parameter(Mandatory = $true)][psobject]$Artifact)

    $paths = Get-ClagnosSysinternalsPaths
    $packageParent = Split-Path -Parent ([string]$paths.ToolsRoot)
    New-Item -ItemType Directory -Path $packageParent -Force | Out-Null
    $stagedRoot = [string]$Artifact.ExtractRoot
    foreach ($scriptName in @('chocolateyInstall.ps1','chocolateyUninstall.ps1','chocolateyBeforeModify.ps1')) {
        $oldScript = Join-Path ([string]$paths.ToolsRoot) $scriptName
        if (Test-Path -LiteralPath $oldScript -PathType Leaf) { Copy-Item -LiteralPath $oldScript -Destination (Join-Path $stagedRoot $scriptName) -Force -ErrorAction Stop }
    }
    $backupRoot = [string]$paths.ToolsRoot + '.clagnos-backup-' + [Guid]::NewGuid().ToString('N')
    $hadOldRoot = Test-Path -LiteralPath ([string]$paths.ToolsRoot) -PathType Container
    if ($hadOldRoot) { [IO.Directory]::Move([string]$paths.ToolsRoot,$backupRoot) }
    try {
        [IO.Directory]::Move($stagedRoot,[string]$paths.ToolsRoot)
        $null = Set-ClagnosSysinternalsState -Artifact $Artifact
        if ($hadOldRoot -and (Test-Path -LiteralPath $backupRoot -PathType Container)) { Remove-Item -LiteralPath $backupRoot -Recurse -Force -ErrorAction Stop }
    }
    catch {
        if (Test-Path -LiteralPath ([string]$paths.ToolsRoot) -PathType Container) { Remove-Item -LiteralPath ([string]$paths.ToolsRoot) -Recurse -Force -ErrorAction SilentlyContinue }
        if ($hadOldRoot -and (Test-Path -LiteralPath $backupRoot -PathType Container)) { [IO.Directory]::Move($backupRoot,[string]$paths.ToolsRoot) }
        throw
    }
}

function Install-ClagnosSysinternalsPackage {
    param([psobject]$Spec)

    $paths = Get-ClagnosSysinternalsPaths
    $artifactRoot = Join-Path ([IO.Path]::GetTempPath()) ('clagnos-sysinternals-cache-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null
    $artifact = $null
    try {
        $artifact = Get-ClagnosSysinternalsCachedArtifact -ArtifactRoot $artifactRoot
        if ($null -eq $artifact) {
            if (Test-Path -LiteralPath $artifactRoot -PathType Container) { Remove-Item -LiteralPath $artifactRoot -Recurse -Force -ErrorAction SilentlyContinue }
            $artifact = Get-ClagnosSysinternalsLatestArtifact
        }
        Write-Output ("Doing: install verified Sysinternals payload version {0}" -f [string]$artifact.Version)
        Install-ClagnosSysinternalsArtifact -Artifact $artifact
        return ("Installed verified Microsoft Sysinternals payload version {0}; {1} signed binaries were checked." -f [string]$artifact.Version,[int]$artifact.PayloadReport.SignedBinaryCount)
    }
    finally {
        if ($null -ne $artifact -and -not [string]::IsNullOrWhiteSpace([string]$artifact.ArtifactRoot) -and (Test-Path -LiteralPath ([string]$artifact.ArtifactRoot) -PathType Container)) { Remove-Item -LiteralPath ([string]$artifact.ArtifactRoot) -Recurse -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $artifactRoot -PathType Container) { Remove-Item -LiteralPath $artifactRoot -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

function Repair-ClagnosSysinternalsPackage {
    param([psobject]$Spec,[string]$ObservedVersion)

    $paths = Get-ClagnosSysinternalsPaths
    $state = $null
    if (Test-Path -LiteralPath ([string]$paths.MarkerPath) -PathType Leaf) { $state = Get-Content -LiteralPath ([string]$paths.MarkerPath) -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
    $report = $null
    if (Test-Path -LiteralPath ([string]$paths.ToolsRoot) -PathType Container) { $report = Get-ClagnosSysinternalsPayloadReport -RootPath ([string]$paths.ToolsRoot) }
    if ($null -ne $report -and [bool]$report.Healthy) {
        if ($null -eq $state) {
        $stateDirectory = Split-Path -Parent ([string]$paths.MarkerPath)
        New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
        $legacyState = [ordered]@{
            Id = 'sysinternals'
            Version = [string]$ObservedVersion
            Source = 'legacy Chocolatey payload; Microsoft Authenticode signatures verified'
            ArchiveSha256 = ''
            ContentFingerprint = [string]$report.Fingerprint
            RemoteETag = ''
            LastModifiedUtc = ''
            FileCount = [int]$report.FileCount
            SignedBinaryCount = [int]$report.SignedBinaryCount
            VerifiedAtUtc = [DateTime]::UtcNow.ToString('o')
        }
        [IO.File]::WriteAllText([string]$paths.MarkerPath,(ConvertTo-Json -InputObject $legacyState -Depth 12 -Compress),(New-Object Text.UTF8Encoding($false)))
        }
        Set-ClagnosSysinternalsMachinePathEntry -Entry ([string]$paths.ToolsRoot)
        Write-Output ("Doing: verify installed Sysinternals version {0}; {1} Microsoft-signed binaries passed" -f $ObservedVersion,[int]$report.SignedBinaryCount)
        return ('The installed Sysinternals version {0} is healthy; {1} signed binaries and {2} payload files verified. No vendor reinstall was needed.' -f $ObservedVersion,[int]$report.SignedBinaryCount,[int]$report.FileCount)
    }

    if ($null -ne $state -and -not [string]::IsNullOrWhiteSpace([string]$state.ArchiveSha256)) {
        $cacheZip = Join-Path ([string]$paths.CacheRoot) ([string]$state.ArchiveSha256 + '.zip')
        if (Test-Path -LiteralPath $cacheZip -PathType Leaf) {
            $artifactRoot = Join-Path ([IO.Path]::GetTempPath()) ('clagnos-sysinternals-repair-' + [Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null
            try {
                $artifact = New-ClagnosSysinternalsArtifact -ZipPath $cacheZip -ArtifactRoot $artifactRoot -RemoteMetadata ([pscustomobject]@{ ETag = [string]$state.RemoteETag; LastModifiedUtc = [string]$state.LastModifiedUtc })
                if (-not [string]::Equals([string]$artifact.ArchiveSha256,[string]$state.ArchiveSha256,[StringComparison]::OrdinalIgnoreCase)) { throw 'The cached Sysinternals archive does not match the installed package manifest.' }
                $artifact.Version = [string]$state.Version
                Install-ClagnosSysinternalsArtifact -Artifact $artifact
                return ('Repaired the installed Sysinternals version {0} from its SHA256-verified package cache.' -f [string]$state.Version)
            }
            finally { if (Test-Path -LiteralPath $artifactRoot -PathType Container) { Remove-Item -LiteralPath $artifactRoot -Recurse -Force -ErrorAction SilentlyContinue } }
        }
    }
    $invalidFiles = if ($null -ne $report) { @($report.InvalidSignatures) -join ', ' } else { 'the Sysinternals tools directory is missing' }
    throw ('Sysinternals same-version repair cannot safely restore observed version {0}; {1}; no matching verified package cache is available. Use update to acquire the current Microsoft payload.' -f $ObservedVersion,$invalidFiles)
}

function Update-ClagnosSysinternalsPackage {
    param([psobject]$Spec,[psobject]$ObservedRecord)

    $paths = Get-ClagnosSysinternalsPaths
    if (Test-Path -LiteralPath ([string]$paths.MarkerPath) -PathType Leaf) {
        try {
            $state = Get-Content -LiteralPath ([string]$paths.MarkerPath) -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            $headers = Get-ClagnosSysinternalsRemoteHeaders -Paths $paths
            $currentReport = Get-ClagnosSysinternalsPayloadReport -RootPath ([string]$paths.ToolsRoot)
            if ([bool]$currentReport.Healthy -and -not [string]::IsNullOrWhiteSpace([string]$state.RemoteETag) -and [string]::Equals([string]$state.RemoteETag,[string]$headers.ETag,[StringComparison]::Ordinal) -and [string]::Equals([string]$state.LastModifiedUtc,[string]$headers.LastModifiedUtc,[StringComparison]::Ordinal)) {
                return ('No applicable update is available; the official Sysinternals archive is current at version {0}.' -f [string]$state.Version)
            }
        }
        catch { }
    }

    $artifact = Get-ClagnosSysinternalsLatestArtifact
    try {
        $currentReport = if (Test-Path -LiteralPath ([string]$paths.ToolsRoot) -PathType Container) { Get-ClagnosSysinternalsPayloadReport -RootPath ([string]$paths.ToolsRoot) } else { $null }
        if ($null -ne $currentReport -and [bool]$currentReport.Healthy -and [string]::Equals([string]$currentReport.Fingerprint,[string]$artifact.PayloadReport.Fingerprint,[StringComparison]::OrdinalIgnoreCase)) {
            $existingState = $null
            if (Test-Path -LiteralPath ([string]$paths.MarkerPath) -PathType Leaf) { try { $existingState = Get-Content -LiteralPath ([string]$paths.MarkerPath) -Raw | ConvertFrom-Json } catch { } }
            $artifact.Version = if ($null -ne $existingState -and -not [string]::IsNullOrWhiteSpace([string]$existingState.Version)) { [string]$existingState.Version } else { [string]$ObservedRecord.Version }
            $null = Set-ClagnosSysinternalsState -Artifact $artifact
            return ('No applicable update is available; the verified Sysinternals payload is current at version {0}.' -f [string]$artifact.Version)
        }
        $oldVersion = [string]$ObservedRecord.Version
        Install-ClagnosSysinternalsArtifact -Artifact $artifact
        return ('Updated Sysinternals from version {0} to verified Microsoft payload {1}.' -f $oldVersion,[string]$artifact.Version)
    }
    finally { if (-not [string]::IsNullOrWhiteSpace([string]$artifact.ArtifactRoot) -and (Test-Path -LiteralPath ([string]$artifact.ArtifactRoot) -PathType Container)) { Remove-Item -LiteralPath ([string]$artifact.ArtifactRoot) -Recurse -Force -ErrorAction SilentlyContinue } }
}

function Remove-ClagnosSysinternalsPackage {
    param([psobject]$Spec)

    $paths = Get-ClagnosSysinternalsPaths
    $legacyVersion = Get-ClagnosSysinternalsChocolateyVersion -Paths $paths
    if (-not [string]::IsNullOrWhiteSpace($legacyVersion)) {
        Write-Output 'Doing: uninstall legacy Chocolatey Sysinternals registration'
        & ([string]$paths.ChocolateyPath) uninstall sysinternals -y --no-progress
        if ([int]$LASTEXITCODE -ne 0) { throw ('Chocolatey Sysinternals uninstall exited with ' + [int]$LASTEXITCODE) }
    }
    elseif (Test-Path -LiteralPath ([string]$paths.PackageRoot) -PathType Container) {
        Write-Output 'Doing: remove Clagnos-managed Sysinternals package folder'
        Remove-Item -LiteralPath ([string]$paths.PackageRoot) -Recurse -Force -ErrorAction Stop
    }
    if (Test-Path -LiteralPath ([string]$paths.MarkerPath) -PathType Leaf) { Remove-Item -LiteralPath ([string]$paths.MarkerPath) -Force -ErrorAction Stop }
    Set-ClagnosSysinternalsMachinePathEntry -Entry ([string]$paths.ToolsRoot) -Remove
    $state = Get-ClagnosSysinternalsPackageRecord -Spec $Spec
    if ([string]$state.Status -ne 'not-installed') { throw ('Sysinternals uninstall did not verify; package status is ' + [string]$state.Status) }
}

function Install-ClagnosSysinternalsPackage {
    param([psobject]$Spec)

    $paths = Get-ClagnosSysinternalsPaths
    $artifactRoot = Join-Path ([IO.Path]::GetTempPath()) ('clagnos-sysinternals-install-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null
    try {
        $artifact = Get-ClagnosSysinternalsCachedArtifact -ArtifactRoot $artifactRoot
        if ($null -eq $artifact) { $artifact = Get-ClagnosSysinternalsLatestArtifact }
        Write-Output ('Doing: install verified Microsoft Sysinternals payload {0}' -f [string]$artifact.Version)
        Install-ClagnosSysinternalsArtifact -Artifact $artifact
        Write-Output ('Sysinternals package installed; {0} signed binaries verified.' -f [int]$artifact.PayloadReport.SignedBinaryCount)
    }
    finally { if (Test-Path -LiteralPath $artifactRoot -PathType Container) { Remove-Item -LiteralPath $artifactRoot -Recurse -Force -ErrorAction SilentlyContinue } }
}

function Set-ClagnosTeamsStoreInstallState {
    param([ValidateSet('installed','remove')][string]$State,[string]$Summary = '')

    $storeStateModulePath = 'C:\Windows\Temp\clagnos-store-install-state.psm1'
    if (-not (Test-Path -LiteralPath $storeStateModulePath -PathType Leaf)) { return }
    Import-Module $storeStateModulePath -Force -DisableNameChecking -ErrorAction Stop
    if ($State -eq 'remove') {
        Remove-ClagnosStoreInstallState -TaskName '114-install-teams-application'
        Write-Output 'Microsoft Teams Clagnos store-install state was removed after verified deprovisioning.'
        return
    }

    $appId = ''
    if (Get-Command Get-StartApps -ErrorAction SilentlyContinue) {
        $startApp = @(Get-StartApps -ErrorAction SilentlyContinue | Where-Object {
            $combinedText = (([string]$_.Name) + ' ' + ([string]$_.AppID)).ToLowerInvariant()
            $combinedText -match '(?i)(?:\bmicrosoft\s+teams\b|\bmsteams\b)'
        } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.AppID) } | Select-Object -First 1)
        if ($startApp.Count -gt 0) { $appId = [string]$startApp[0].AppID }
    }
    if ([string]::IsNullOrWhiteSpace($appId)) {
        $installedPackages = @(Get-AppxPackage -AllUsers -Name 'MSTeams' -ErrorAction Stop | Sort-Object Version -Descending)
        if ($installedPackages.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$installedPackages[0].PackageFamilyName)) {
            $appId = [string]$installedPackages[0].PackageFamilyName + '!MSTeams'
        }
    }
    if ([string]::IsNullOrWhiteSpace($appId)) { throw 'Microsoft Teams is installed but no stable app launch ID could be resolved for its managed shortcut state.' }
    $stateRecord = Write-ClagnosStoreInstallState -TaskName '114-install-teams-application' -State installed -Summary $Summary -PackageId 'Microsoft Teams' -RunOnceName 'ClagnosInstallTeams' -LaunchKind 'app-id' -LaunchTarget $appId -InstallSource 'teams-bootstrapper'
    Write-ClagnosStoreInstallStateStatusLine -TaskName '114-install-teams-application' -StateRecord $stateRecord
}

function Stop-ClagnosWindscribeDesktopProcesses {
    $allowedRoot = 'C:\Program Files\Windscribe\'
    $processes = @(Get-CimInstance Win32_Process -Filter "Name='Windscribe.exe' OR Name='windscribe-cli.exe'" -ErrorAction SilentlyContinue)
    foreach ($process in @($processes)) {
        $path = [string]$process.ExecutablePath
        if ([string]::IsNullOrWhiteSpace($path) -or -not $path.StartsWith($allowedRoot,[StringComparison]::OrdinalIgnoreCase)) { continue }
        Write-Output ('Doing: close the Windscribe desktop/CLI process before running its signed installer (pid {0})' -f [int]$process.ProcessId)
        Stop-Process -Id ([int]$process.ProcessId) -Force -ErrorAction Stop
    }
    Start-Sleep -Seconds 2
    $remaining = @(Get-CimInstance Win32_Process -Filter "Name='Windscribe.exe' OR Name='windscribe-cli.exe'" -ErrorAction SilentlyContinue | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string]$_.ExecutablePath) -and [string]$_.ExecutablePath.StartsWith($allowedRoot,[StringComparison]::OrdinalIgnoreCase)
    })
    if ($remaining.Count -gt 0) { throw ('Windscribe desktop processes remained active after the bounded close attempt: ' + (@($remaining | ForEach-Object { [int]$_.ProcessId }) -join ', ')) }
}

function Stop-ClagnosStaleWindscribeUninstallerProcesses {
    param([ValidateRange(120,480)][int]$MaximumAgeSeconds = 480,[ValidateRange(5,180)][int]$WaitTimeoutSeconds = 60)

    $uninstallerPrefix = (Join-Path $env:SystemRoot 'Temp\WindscribeUninstaller').TrimEnd('\')
    $waitDeadline = [DateTime]::UtcNow.AddSeconds([int]$WaitTimeoutSeconds)
    do {
        $candidates = @(Get-CimInstance Win32_Process -Filter "Name='uninstall.exe'" -ErrorAction SilentlyContinue | Where-Object {
            -not [string]::IsNullOrWhiteSpace([string]$_.ExecutablePath) -and
            [string]$_.ExecutablePath.StartsWith(($uninstallerPrefix + '\'),[StringComparison]::OrdinalIgnoreCase) -and
            [string]$_.CommandLine -match '(?i)/SECONDPHASE='
        })
        if ($candidates.Count -eq 0) { return }

        $staleProcesses = @()
        $freshProcesses = @()
        foreach ($candidate in @($candidates)) {
            $ageSeconds = -1
            try { $ageSeconds = [int][Math]::Max(0,([DateTime]::UtcNow - [DateTime]$candidate.CreationDate.ToUniversalTime()).TotalSeconds) } catch { }
            if ($ageSeconds -ge [int]$MaximumAgeSeconds) {
                $staleProcesses += [pscustomobject]@{ Process = $candidate; AgeSeconds = $ageSeconds }
            }
            else { $freshProcesses += [pscustomobject]@{ Process = $candidate; AgeSeconds = $ageSeconds } }
        }

        if ($staleProcesses.Count -eq 0) {
            if ([DateTime]::UtcNow -ge $waitDeadline) {
                $ageLabels = @($freshProcesses | ForEach-Object { if ([int]$_.AgeSeconds -ge 0) { [string]$_.AgeSeconds } else { 'unknown' } }) -join ', '
                throw ('A previous Windscribe second-phase uninstaller remains active below the {0}-second stale threshold; observed age(s): {1}. No new repair or uninstall was started.' -f $MaximumAgeSeconds,$ageLabels)
            }
            Write-Output ('Doing: wait for prior Windscribe second-phase process(es) before retry; count={0}' -f $freshProcesses.Count)
            Start-Sleep -Seconds 5
            continue
        }

        foreach ($stale in @($staleProcesses)) {
            $candidate = $stale.Process
            $signature = Get-AuthenticodeSignature -FilePath ([string]$candidate.ExecutablePath) -ErrorAction Stop
            $signer = if ($null -ne $signature.SignerCertificate) { [string]$signature.SignerCertificate.Subject } else { '' }
            if ([string]$signature.Status -ne 'Valid' -or $signer -notmatch '(?i)O=Windscribe Limited') {
                throw ('Stale-looking uninstaller PID {0} failed Windscribe signer validation; it was not stopped.' -f [int]$candidate.ProcessId)
            }
            Write-Output ('Doing: stop stale signed Windscribe second-phase process PID {0} after {1}s' -f [int]$candidate.ProcessId,[int]$stale.AgeSeconds)
            $taskkill = Join-Path $env:SystemRoot 'System32\taskkill.exe'
            if (-not (Test-Path -LiteralPath $taskkill -PathType Leaf)) { throw 'taskkill.exe is unavailable; stale Windscribe uninstaller cleanup could not be bounded.' }
            & $taskkill /PID ([string]$candidate.ProcessId) /T /F 2>$null | Out-Null
            $stopDeadline = [DateTime]::UtcNow.AddSeconds(10)
            do {
                $stillPresent = @(Get-CimInstance Win32_Process -Filter ("ProcessId={0}" -f [int]$candidate.ProcessId) -ErrorAction SilentlyContinue | Where-Object {
                    [string]$_.Name -eq 'uninstall.exe' -and [string]$_.ExecutablePath -and [string]$_.ExecutablePath.StartsWith(($uninstallerPrefix + '\'),[StringComparison]::OrdinalIgnoreCase)
                })
                if ($stillPresent.Count -eq 0) { break }
                if ([DateTime]::UtcNow -ge $stopDeadline) { throw ('Stale Windscribe second-phase PID {0} remained after its bounded stop attempt.' -f [int]$candidate.ProcessId) }
                Start-Sleep -Milliseconds 500
            } while ($true)
        }
    } while ($true)
}

function ConvertFrom-ClagnosWindscribePersistentFirewallState {
    param([Parameter(Mandatory = $true)][string]$EncodedState)

    try {
        $cipher = [Convert]::FromBase64String([string]$EncodedState)
        if ($cipher.Length -lt 12) { return [pscustomobject]@{ Success = $false; FirewallOn = $false; Error = 'ciphertext-too-short' } }
        if ([int]$cipher[0] -ne 3) { return [pscustomobject]@{ Success = $false; FirewallOn = $false; Error = 'cipher-version-unknown' } }
        $flags = [int]$cipher[1]
        $key = [Convert]::ToUInt64('4572A4ACF31A31BA',16)
        $keyParts = New-Object byte[] 8
        for ($keyIndex = 0; $keyIndex -lt 8; $keyIndex++) { $keyParts[$keyIndex] = [byte](($key -shr (8 * $keyIndex)) -band 0xFF) }

        $decoded = New-Object byte[] ($cipher.Length - 2)
        $previousCipherByte = 0
        for ($cipherIndex = 2; $cipherIndex -lt $cipher.Length; $cipherIndex++) {
            $currentCipherByte = [int]$cipher[$cipherIndex]
            $decodedIndex = $cipherIndex - 2
            $decoded[$decodedIndex] = [byte]($currentCipherByte -bxor $previousCipherByte -bxor [int]$keyParts[$decodedIndex % 8])
            $previousCipherByte = $currentCipherByte
        }

        if ($decoded.Length -lt 2) { return [pscustomobject]@{ Success = $false; FirewallOn = $false; Error = 'decoded-payload-too-short' } }
        $payload = New-Object byte[] ($decoded.Length - 1)
        [Array]::Copy($decoded,1,$payload,0,$payload.Length)
        if (($flags -band 0x02) -ne 0) {
            if ($payload.Length -lt 3) { return [pscustomobject]@{ Success = $false; FirewallOn = $false; Error = 'checksum-payload-too-short' } }
            $payload = $payload[2..($payload.Length - 1)]
        }
        elseif (($flags -band 0x04) -ne 0) {
            if ($payload.Length -lt 21) { return [pscustomobject]@{ Success = $false; FirewallOn = $false; Error = 'hash-payload-too-short' } }
            $storedHash = $payload[0..19]
            $payload = $payload[20..($payload.Length - 1)]
            $sha1 = [System.Security.Cryptography.SHA1]::Create()
            try { $actualHash = $sha1.ComputeHash($payload) } finally { $sha1.Dispose() }
            for ($hashIndex = 0; $hashIndex -lt 20; $hashIndex++) { if ($storedHash[$hashIndex] -ne $actualHash[$hashIndex]) { return [pscustomobject]@{ Success = $false; FirewallOn = $false; Error = 'hash-mismatch' } } }
        }

        if (($flags -band 0x01) -ne 0) {
            if ($payload.Length -lt 11) { return [pscustomobject]@{ Success = $false; FirewallOn = $false; Error = 'compressed-payload-too-short' } }
            $declaredLength = ([int64]$payload[0] * 16777216) + ([int64]$payload[1] * 65536) + ([int64]$payload[2] * 256) + [int64]$payload[3]
            if ($declaredLength -lt 9 -or $declaredLength -gt 1048576) { return [pscustomobject]@{ Success = $false; FirewallOn = $false; Error = 'declared-length-invalid' } }
            $zlibLength = $payload.Length - 4
            if ($zlibLength -lt 7) { return [pscustomobject]@{ Success = $false; FirewallOn = $false; Error = 'zlib-payload-too-short' } }
            $deflateBytes = New-Object byte[] ($zlibLength - 6)
            [Array]::Copy($payload,6,$deflateBytes,0,$deflateBytes.Length)
            $inputStream = New-Object IO.MemoryStream(,$deflateBytes)
            $deflateStream = New-Object IO.Compression.DeflateStream($inputStream,[IO.Compression.CompressionMode]::Decompress)
            $outputStream = New-Object IO.MemoryStream
            try { $deflateStream.CopyTo($outputStream); $payload = $outputStream.ToArray() }
            finally { $deflateStream.Dispose(); $inputStream.Dispose(); $outputStream.Dispose() }
            if ($payload.Length -ne $declaredLength) { return [pscustomobject]@{ Success = $false; FirewallOn = $false; Error = 'decompressed-length-mismatch' } }
        }

        if ($payload.Length -lt 9) { return [pscustomobject]@{ Success = $false; FirewallOn = $false; Error = 'state-payload-too-short' } }
        $magic = ([uint64]$payload[0] * 16777216) + ([uint64]$payload[1] * 65536) + ([uint64]$payload[2] * 256) + [uint64]$payload[3]
        $version = ([uint64]$payload[4] * 16777216) + ([uint64]$payload[5] * 65536) + ([uint64]$payload[6] * 256) + [uint64]$payload[7]
        $expectedMagic = [Convert]::ToUInt64('8845C2AE',16)
        if ($magic -ne $expectedMagic) { return [pscustomobject]@{ Success = $false; FirewallOn = $false; Error = ('persistent-state-magic-mismatch:0x{0:X8}:version={1}:flags={2}' -f [uint64]$magic,[uint64]$version,[int]$flags) } }
        if ($version -lt 1 -or $version -gt 2) { return [pscustomobject]@{ Success = $false; FirewallOn = $false; Error = 'persistent-state-version-unsupported' } }
        return [pscustomobject]@{ Success = $true; FirewallOn = [bool]([int]$payload[8] -ne 0); Error = '' }
    }
    catch { return [pscustomobject]@{ Success = $false; FirewallOn = $false; Error = ('decode-exception:{0}' -f [string]$_.Exception.GetType().Name) } }
}

function Get-ClagnosWindscribeUnattendedFirewallState {
    $registryRoots = @(
        [pscustomobject]@{ Scope = 'current-user'; Path = 'Registry::HKEY_CURRENT_USER\Software\Windscribe\Windscribe2' },
        [pscustomobject]@{ Scope = 'system'; Path = 'Registry::HKEY_USERS\S-1-5-18\Software\Windscribe\Windscribe2' }
    )
    $loadedHives = @(Get-ChildItem -LiteralPath 'Registry::HKEY_USERS' -ErrorAction SilentlyContinue | Where-Object { [string]$_.PSChildName -match '^S-1-5-21-(?:\d+-){3}\d+$' })
    $currentSid = ''
    try { $currentSid = [string]([Security.Principal.WindowsIdentity]::GetCurrent().User.Value) } catch { }
    foreach ($loadedHive in @($loadedHives)) {
        $scope = if ([string]::Equals([string]$loadedHive.PSChildName,$currentSid,[StringComparison]::OrdinalIgnoreCase)) { 'current-user' } else { 'other-user' }
        $registryRoots += [pscustomobject]@{ Scope = $scope; Path = ('Registry::HKEY_USERS\{0}\Software\Windscribe\Windscribe2' -f [string]$loadedHive.PSChildName) }
    }

    $windscribeProcess = @(Get-CimInstance Win32_Process -Filter "Name='Windscribe.exe'" -ErrorAction SilentlyContinue | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string]$_.ExecutablePath) -and [string]$_.ExecutablePath.StartsWith('C:\Program Files\Windscribe\',[StringComparison]::OrdinalIgnoreCase)
    } | Sort-Object SessionId | Select-Object -First 1)
    $activeScope = 'unknown'
    if ($windscribeProcess.Count -gt 0) {
        $processOwner = 'unknown'
        try {
            $ownerResult = Invoke-CimMethod -InputObject $windscribeProcess[0] -MethodName GetOwner -ErrorAction Stop
            if ([int]$ownerResult.ReturnValue -eq 0) { $processOwner = [string]$ownerResult.User }
        }
        catch { }
        if ([string]::Equals($processOwner,'SYSTEM',[StringComparison]::OrdinalIgnoreCase)) { $activeScope = 'system' }
        elseif ([string]::Equals($processOwner,$env:USERNAME,[StringComparison]::OrdinalIgnoreCase)) { $activeScope = 'current-user' }
    }
    if ($activeScope -eq 'unknown') {
        $windscribeServices = @(Get-CimInstance Win32_Service -Filter "Name='WindscribeService'" -ErrorAction SilentlyContinue)
        $systemService = @($windscribeServices | Where-Object { [string]$_.State -eq 'Running' -and [string]$_.StartName -match '(?i)^(LocalSystem|NT AUTHORITY\\SYSTEM)$' } | Select-Object -First 1)
        if ($systemService.Count -gt 0) { $activeScope = 'system' }
    }
    if ($activeScope -eq 'unknown') { return [pscustomobject]@{ State = 'unknown'; Source = 'Windscribe process owner could not be mapped to a settings hive' } }

    $activeRoot = @($registryRoots | Where-Object { [string]::Equals([string]$_.Scope,$activeScope,[StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
    if ($activeRoot.Count -eq 0 -or -not (Test-Path -LiteralPath ([string]$activeRoot[0].Path))) {
        return [pscustomobject]@{ State = 'Off'; Source = ('Windscribe {0} settings hive is absent; compiled default Automatic mode and persistent state are firewall-off' -f $activeScope) }
    }

    $settings = Get-ItemProperty -LiteralPath ([string]$activeRoot[0].Path) -ErrorAction SilentlyContinue
    if ($null -ne $settings.PSObject.Properties['guiSettings2']) { return [pscustomobject]@{ State = 'unknown'; Source = ('Windscribe {0} GUI settings exist but firewall mode cannot be decoded safely' -f $activeScope) } }
    $persistentState = $settings.PSObject.Properties['guiPersistentState']
    if ($null -eq $persistentState) { return [pscustomobject]@{ State = 'Off'; Source = ('Windscribe {0} settings use compiled Automatic mode and default firewall-off state' -f $activeScope) } }
    $decodedState = ConvertFrom-ClagnosWindscribePersistentFirewallState -EncodedState ([string]$persistentState.Value)
    if ($null -eq $decodedState -or -not [bool]$decodedState.Success) {
        $errorText = if ($null -ne $decodedState) { [string]$decodedState.Error } else { 'empty decode result' }
        return [pscustomobject]@{ State = 'unknown'; Source = ('Windscribe {0} persistent state could not be decoded: {1}' -f $activeScope,$errorText) }
    }

    $activeVpnAdapters = @(Get-CimInstance Win32_NetworkAdapter -Filter 'NetEnabled=True' -ErrorAction SilentlyContinue | Where-Object { ([string]$_.Name + ' ' + [string]$_.Description) -match '(?i)Windscribe' })
    if ($activeVpnAdapters.Count -gt 0) { return [pscustomobject]@{ State = 'On'; Source = ('Windscribe {0} Automatic mode has an active VPN adapter' -f $activeScope) } }
    return [pscustomobject]@{ State = if ([bool]$decodedState.FirewallOn) { 'On' } else { 'Off' }; Source = ('decoded Windscribe {0} persistent firewall state with compiled default Automatic mode' -f $activeScope) }
}

function Get-ClagnosWindscribePackageRecord {
    param([Parameter(Mandatory = $true)][psobject]$Spec)

    $path = [string]$Spec.statusCheck.value
    if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return [pscustomobject]@{ Status = 'not-installed'; Version = ''; Detail = '' }
    }
    $versionInfo = (Get-Item -LiteralPath $path -ErrorAction Stop).VersionInfo
    $version = [string]$versionInfo.ProductVersion
    $signature = Get-AuthenticodeSignature -FilePath $path -ErrorAction Stop
    $signer = if ($null -ne $signature.SignerCertificate) { [string]$signature.SignerCertificate.Subject } else { '' }
    if ([string]$signature.Status -ne 'Valid' -or $signer -notmatch '(?i)O=Windscribe Limited' -or [string]$versionInfo.CompanyName -ne 'Windscribe Limited') {
        return [pscustomobject]@{ Status = 'installed-drifted'; Version = $version; Detail = 'Windscribe executable is present but failed the expected publisher-signature health check.' }
    }
    $services = @(Get-CimInstance Win32_Service -Filter "Name LIKE '%Windscribe%' OR DisplayName LIKE '%Windscribe%'" -ErrorAction Stop)
    if ($services.Count -eq 0) {
        return [pscustomobject]@{ Status = 'installed-drifted'; Version = $version; Detail = 'Windscribe executable is signed, but its Windows service registration is missing.' }
    }
    $serviceSummary = @($services | ForEach-Object { '{0}={1}/{2}' -f [string]$_.Name,[string]$_.State,[string]$_.StartMode } | Sort-Object) -join ', '
    $appProcesses = @(Get-CimInstance Win32_Process -Filter "Name='Windscribe.exe' OR Name='windscribe-cli.exe'" -ErrorAction SilentlyContinue | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string]$_.ExecutablePath) -and [string]$_.ExecutablePath.StartsWith('C:\Program Files\Windscribe\',[StringComparison]::OrdinalIgnoreCase)
    })
    $processSummary = if ($appProcesses.Count -gt 0) {
        @($appProcesses | ForEach-Object {
            $processOwner = 'unknown'
            try {
                $ownerRecord = Invoke-CimMethod -InputObject $_ -MethodName GetOwner -ErrorAction Stop
                if ([int]$ownerRecord.ReturnValue -eq 0 -and -not [string]::IsNullOrWhiteSpace([string]$ownerRecord.User)) { $processOwner = [string]$ownerRecord.User }
            }
            catch { }
            '{0}#{1}@session{2}/owner={3}' -f [string]$_.Name,[int]$_.ProcessId,[int]$_.SessionId,$processOwner
        } | Sort-Object) -join ', '
    }
    else { 'none' }
    $uninstallerProcesses = @(Get-CimInstance Win32_Process -Filter "Name='uninstall.exe'" -ErrorAction SilentlyContinue | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string]$_.ExecutablePath) -and [string]$_.ExecutablePath.StartsWith((Join-Path $env:SystemRoot 'Temp\WindscribeUninstaller'),[StringComparison]::OrdinalIgnoreCase)
    })
    $uninstallerProcessSummary = if ($uninstallerProcesses.Count -gt 0) {
        @($uninstallerProcesses | ForEach-Object {
            $commandText = [string]$_.CommandLine
            $phase = if ($commandText -match '(?i)/SECONDPHASE=') { 'second-phase' } else { 'launcher' }
            $silent = if ($commandText -match '(?i)(?:^|\s)/VERYSILENT(?:\s|$)') { 'very-silent' } elseif ($commandText -match '(?i)(?:^|\s)/SILENT(?:\s|$)') { 'silent-unsupported' } else { 'not-silent' }
            $ageSeconds = -1
            try { $ageSeconds = [int][Math]::Max(0,([DateTime]::UtcNow - [DateTime]$_.CreationDate.ToUniversalTime()).TotalSeconds) } catch { }
            'pid={0};session={1};age={2}s;phase={3};mode={4}' -f [int]$_.ProcessId,[int]$_.SessionId,$ageSeconds,$phase,$silent
        } | Sort-Object) -join ', '
    }
    else { 'none' }
    $interactiveSession = 'manager-desktop=absent'
    $explorerProcesses = @(Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" -ErrorAction SilentlyContinue)
    foreach ($explorer in @($explorerProcesses)) {
        try {
            $owner = $explorer.GetOwner()
            if ([string]::Equals([string]$owner.User,[string]$env:USERNAME,[StringComparison]::OrdinalIgnoreCase)) {
                $interactiveSession = 'manager-desktop=present(session {0})' -f [int]$explorer.SessionId
                break
            }
        }
        catch { }
    }
    $firewallSettings = New-Object 'System.Collections.Generic.List[string]'
    $windscribeRegistryRoots = New-Object 'System.Collections.Generic.List[string]'
    foreach ($knownRegistryRoot in @(
        'Registry::HKEY_CURRENT_USER\Software\Windscribe\Windscribe2',
        'Registry::HKEY_USERS\.DEFAULT\Software\Windscribe\Windscribe2',
        'Registry::HKEY_USERS\S-1-5-18\Software\Windscribe\Windscribe2',
        'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Windscribe\Windscribe2',
        'Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\WindscribeService'
    )) { $windscribeRegistryRoots.Add([string]$knownRegistryRoot) | Out-Null }
    foreach ($loadedHive in @(Get-ChildItem -LiteralPath 'Registry::HKEY_USERS' -ErrorAction SilentlyContinue | Where-Object { [string]$_.PSChildName -match '^S-1-5-21-(?:\d+-){3}\d+$' })) {
        $windscribeRegistryRoots.Add(('Registry::HKEY_USERS\{0}\Software\Windscribe\Windscribe2' -f [string]$loadedHive.PSChildName)) | Out-Null
    }
    $persistedGuiSettings = New-Object 'System.Collections.Generic.List[string]'
    foreach ($registryRoot in @($windscribeRegistryRoots.ToArray() | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $registryRoot)) { continue }
        $rootProperties = Get-ItemProperty -LiteralPath $registryRoot -ErrorAction SilentlyContinue
        if ($null -ne $rootProperties.PSObject.Properties['guiSettings2']) { $persistedGuiSettings.Add('guiSettings2') | Out-Null }
        if ($null -ne $rootProperties.PSObject.Properties['guiPersistentState']) { $persistedGuiSettings.Add('guiPersistentState') | Out-Null }
        $keys = @((Get-Item -LiteralPath $registryRoot -ErrorAction SilentlyContinue))
        $keys += @(Get-ChildItem -LiteralPath $registryRoot -Recurse -ErrorAction SilentlyContinue)
        foreach ($key in @($keys | Where-Object { $null -ne $_ })) {
            $properties = Get-ItemProperty -LiteralPath ([string]$key.PSPath) -ErrorAction SilentlyContinue
            foreach ($property in @($properties.PSObject.Properties | Where-Object { $_.Name -match '(?i)^Firewall(?:Mode|State|When|Enabled)$' })) {
                $valueText = [string]$property.Value
                if ($valueText -match '^(?i)(auto|automatic|manual|always[\s_-]*on|on|off|true|false|0|1)$') {
                    $firewallSettings.Add(('{0}={1}' -f [string]$property.Name,$valueText)) | Out-Null
                }
            }
        }
    }
    $firewallSummary = if ($firewallSettings.Count -gt 0) { @($firewallSettings.ToArray() | Sort-Object -Unique) -join ', ' } else { 'unavailable' }
    $persistedSettingsSummary = if ($persistedGuiSettings.Count -gt 0) { @($persistedGuiSettings.ToArray() | Sort-Object -Unique) -join ', ' } else { 'none in loaded Windscribe settings hives' }
    $activeVpnAdapters = @(Get-CimInstance Win32_NetworkAdapter -Filter 'NetEnabled=True' -ErrorAction SilentlyContinue | Where-Object { ([string]$_.Name + ' ' + [string]$_.Description) -match '(?i)Windscribe|WireGuard|Wintun' })
    $vpnSummary = if ($activeVpnAdapters.Count -gt 0) { @($activeVpnAdapters | ForEach-Object { [string]$_.Name } | Sort-Object -Unique) -join ', ' } else { 'none' }
    $wireGuardDrivers = @(Get-CimInstance Win32_SystemDriver -Filter "Name LIKE '%WireGuard%' OR DisplayName LIKE '%WireGuard%'" -ErrorAction SilentlyContinue)
    $wireGuardSummary = if ($wireGuardDrivers.Count -gt 0) { @($wireGuardDrivers | ForEach-Object { '{0}={1}/{2}' -f [string]$_.Name,[string]$_.State,[string]$_.StartMode } | Sort-Object -Unique) -join ', ' } else { 'none' }
    $unattendedFirewallState = Get-ClagnosWindscribeUnattendedFirewallState
    $uninstallerLogSummary = 'unavailable'
    $uninstallerLogPath = Join-Path $env:ProgramData 'Windscribe\uninstaller.log'
    if (Test-Path -LiteralPath $uninstallerLogPath -PathType Leaf) {
        $errorLines = @(Get-Content -LiteralPath $uninstallerLogPath -Tail 120 -ErrorAction SilentlyContinue | Where-Object { [string]$_ -match '(?i)error|fail|9404|firewall|service|access denied|exception|could not|cannot' } | Select-Object -Last 5)
        if ($errorLines.Count -gt 0) {
            $safeLines = @($errorLines | ForEach-Object {
                $line = [string]$_
                $line = [regex]::Replace($line,'\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b','[redacted-email]',[System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                $line = [regex]::Replace($line,'\b(?:\d{1,3}\.){3}\d{1,3}\b','[redacted-ip]')
                $line = [regex]::Replace($line,'(?i)C:\\Users\\[^\\\s]+','C:\\Users\\<profile>')
                if ($line.Length -gt 220) { $line = $line.Substring(0,220) }
                $line
            })
            $uninstallerLogSummary = $safeLines -join ' | '
        }
    }
    return [pscustomobject]@{ Status = 'installed'; Version = $version; Detail = ('Windscribe publisher signature and Windows service registration are verified ({0}); app processes: {1}; {2}; firewall settings: {3}; persisted GUI settings: {4}; active VPN adapters: {5}; WireGuard drivers: {6}; unattended firewall state: {7} ({8}); active vendor uninstaller: {9}; uninstaller log: {10}.' -f $serviceSummary,$processSummary,$interactiveSession,$firewallSummary,$persistedSettingsSummary,$vpnSummary,$wireGuardSummary,[string]$unattendedFirewallState.State,[string]$unattendedFirewallState.Source,$uninstallerProcessSummary,$uninstallerLogSummary) }
}

function Invoke-ClagnosTeamsBootstrapper {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('install','uninstall')][string]$Action,
        [ValidateRange(30,360)][int]$TimeoutSeconds = 240
    )

    $downloadUri = 'https://go.microsoft.com/fwlink/?clcid=0x409&linkid=2243204'
    $workRoot = Join-Path ([IO.Path]::GetTempPath()) ('clagnos-teams-bootstrapper-' + [Guid]::NewGuid().ToString('N'))
    $bootstrapperPath = Join-Path $workRoot 'teamsbootstrapper.exe'
    $stdoutPath = Join-Path $workRoot 'stdout.log'
    $stderrPath = Join-Path $workRoot 'stderr.log'
    New-Item -ItemType Directory -Path $workRoot -Force | Out-Null
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        Write-Output 'Doing: download the current Microsoft Teams bootstrapper from its official Microsoft link'
        Invoke-WebRequest -Uri $downloadUri -OutFile $bootstrapperPath -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
        if (-not (Test-Path -LiteralPath $bootstrapperPath -PathType Leaf) -or (Get-Item -LiteralPath $bootstrapperPath).Length -lt 100000) {
            throw 'The Microsoft Teams bootstrapper download is missing or unexpectedly small.'
        }
        $signature = Get-AuthenticodeSignature -FilePath $bootstrapperPath -ErrorAction Stop
        $signerSubject = if ($null -ne $signature.SignerCertificate) { [string]$signature.SignerCertificate.Subject } else { '' }
        if ([string]$signature.Status -ne 'Valid' -or $signerSubject -notmatch '(?i)(^|,\s*)O=Microsoft Corporation(?:,|$)') {
            throw ('The Teams bootstrapper Authenticode signature is not valid for Microsoft Corporation (status: {0}).' -f [string]$signature.Status)
        }

        $argumentList = if ($Action -eq 'install') { @('-p') } else { @('-x') }
        Write-Output ("Doing: run the signed Microsoft Teams bootstrapper with {0}" -f [string]$argumentList[0])
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $process = Start-Process -FilePath $bootstrapperPath -ArgumentList $argumentList -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -ErrorAction Stop
        $deadlineUtc = [DateTime]::UtcNow.AddSeconds([int]$TimeoutSeconds)
        $nextHeartbeatSeconds = 15
        while (-not $process.HasExited) {
            if ([DateTime]::UtcNow -ge $deadlineUtc) {
                Write-Output ('Doing: stop timed-out Teams bootstrapper process tree after {0}s' -f [int]$watch.Elapsed.TotalSeconds)
                $taskkillPath = Join-Path $env:SystemRoot 'System32\taskkill.exe'
                if (Test-Path -LiteralPath $taskkillPath -PathType Leaf) {
                    & $taskkillPath /PID ([string]$process.Id) /T /F 2>$null | Out-Null
                }
                throw ("The Microsoft Teams bootstrapper exceeded its finite {0}-second deadline during {1}." -f [int]$TimeoutSeconds,$Action)
            }
            if ([int]$watch.Elapsed.TotalSeconds -ge $nextHeartbeatSeconds) {
                Write-Output ("Doing: Microsoft Teams {0} bootstrapper is running ({1}s elapsed)" -f $Action,[int]$watch.Elapsed.TotalSeconds)
                $nextHeartbeatSeconds += 15
            }
            Start-Sleep -Seconds 5
            $process.Refresh()
        }
        $process.WaitForExit()
        $exitCode = [int]$process.ExitCode
        $stdoutText = if (Test-Path -LiteralPath $stdoutPath -PathType Leaf) { [string](Get-Content -LiteralPath $stdoutPath -Raw -ErrorAction SilentlyContinue) } else { '' }
        $stderrText = if (Test-Path -LiteralPath $stderrPath -PathType Leaf) { [string](Get-Content -LiteralPath $stderrPath -Raw -ErrorAction SilentlyContinue) } else { '' }
        $bootstrapperOutput = (($stdoutText + [Environment]::NewLine + $stderrText).Trim())
        if ($exitCode -ne 0) {
            $tail = @($bootstrapperOutput -split "`r?`n" | Select-Object -Last 20) -join ' '
            throw ("The Microsoft Teams bootstrapper exited with {0}. {1}" -f $exitCode,$tail)
        }

        $verifyDeadlineUtc = [DateTime]::UtcNow.AddSeconds([Math]::Min(60,[Math]::Max(15,[int]($TimeoutSeconds - $watch.Elapsed.TotalSeconds))))
        do {
            $installedPackages = @(Get-AppxPackage -AllUsers -Name 'MSTeams' -ErrorAction Stop)
            $provisionedPackages = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object { [string]$_.DisplayName -like '*MSTeams*' -or [string]$_.PackageName -like '*MSTeams*' })
            if ($Action -eq 'install' -and ($installedPackages.Count -gt 0 -or $provisionedPackages.Count -gt 0)) { break }
            if ($Action -eq 'uninstall' -and $installedPackages.Count -eq 0 -and $provisionedPackages.Count -eq 0) { break }
            if ([DateTime]::UtcNow -ge $verifyDeadlineUtc) { break }
            Write-Output ("Doing: verify Microsoft Teams {0}; installed={1}; provisioned={2}" -f $Action,$installedPackages.Count,$provisionedPackages.Count)
            Start-Sleep -Seconds 5
        } while ($true)

        if ($Action -eq 'install' -and $installedPackages.Count -eq 0 -and $provisionedPackages.Count -eq 0) {
            throw 'The Teams bootstrapper returned success but neither an installed nor a provisioned Teams package was detected.'
        }
        if ($Action -eq 'uninstall' -and ($installedPackages.Count -gt 0 -or $provisionedPackages.Count -gt 0)) {
            throw ("Teams bootstrapper removal verification failed; installed={0}; provisioned={1}." -f $installedPackages.Count,$provisionedPackages.Count)
        }
        $version = if ($installedPackages.Count -gt 0) { [string](@($installedPackages | Sort-Object Version -Descending | Select-Object -First 1)[0].Version) } else { '' }
        if ($Action -eq 'install') {
            Set-ClagnosTeamsStoreInstallState -State installed -Summary ('Microsoft Teams was provisioned for all users by the signed headless bootstrapper at version {0}.' -f $version)
        }
        else { Set-ClagnosTeamsStoreInstallState -State remove }
        Write-Output ("Microsoft Teams bootstrapper {0} completed and verified (version {1})." -f $Action,$version)
        if (-not [string]::IsNullOrWhiteSpace([string]$bootstrapperOutput)) { Write-Output $bootstrapperOutput.Trim() }
    }
    finally {
        if (Test-Path -LiteralPath $workRoot -PathType Container) { Remove-Item -LiteralPath $workRoot -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

function Get-ClagnosWslDistributionRegistrations {
    $userHives = @(Get-ChildItem -LiteralPath 'Registry::HKEY_USERS' -ErrorAction Stop | Where-Object {
        [string]$_.PSChildName -match '^S-1-5-21-(?:\d+-){3}\d+$'
    })
    $distributionRecords = @()
    foreach ($userHive in @($userHives)) {
        $distributionRoot = 'Registry::HKEY_USERS\{0}\Software\Microsoft\Windows\CurrentVersion\Lxss' -f [string]$userHive.PSChildName
        if (-not (Test-Path -LiteralPath $distributionRoot)) { continue }
        foreach ($distributionKey in @(Get-ChildItem -LiteralPath $distributionRoot -ErrorAction Stop)) {
            $distributionSettings = Get-ItemProperty -LiteralPath ([string]$distributionKey.PSPath) -ErrorAction Stop
            $nameProperty = $distributionSettings.PSObject.Properties['DistributionName']
            $distributionName = if ($null -ne $nameProperty) { [string]$nameProperty.Value } else { [string]$distributionKey.PSChildName }
            $distributionRecords += [pscustomobject]@{ UserSid = [string]$userHive.PSChildName; Name = $distributionName }
        }
    }
    return @($distributionRecords)
}

function Get-ClagnosWslPackageRecord {
    param([string]$DisplayName = 'Windows Subsystem for Linux')

    $uninstallRoots = @(
        'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    $records = @()
    foreach ($uninstallRoot in @($uninstallRoots)) {
        $records += @(Get-ItemProperty -Path (Join-Path $uninstallRoot '*') -ErrorAction SilentlyContinue | Where-Object {
            $displayNameProperty = $_.PSObject.Properties['DisplayName']
            $null -ne $displayNameProperty -and [string]::Equals([string]$displayNameProperty.Value,[string]$DisplayName,[StringComparison]::OrdinalIgnoreCase)
        })
    }
    $records = @($records | Sort-Object { if ($null -ne $_.PSObject.Properties['DisplayVersion']) { [string]$_.PSObject.Properties['DisplayVersion'].Value } else { '' } } -Descending)
    $wslExecutable = 'C:\Program Files\WSL\wsl.exe'
    $wslVersion = if ($records.Count -gt 0 -and $null -ne $records[0].PSObject.Properties['DisplayVersion']) { [string]$records[0].PSObject.Properties['DisplayVersion'].Value } else { '' }
    $wslUninstallString = if ($records.Count -gt 0 -and $null -ne $records[0].PSObject.Properties['UninstallString']) { [string]$records[0].PSObject.Properties['UninstallString'].Value } else { '' }
    if ($records.Count -gt 0 -and (Test-Path -LiteralPath $wslExecutable -PathType Leaf)) {
        return [pscustomobject]@{ Status = 'installed'; Version = $wslVersion; Detail = 'WSL MSI registration and executable are present.'; ProductCode = [string]$records[0].PSChildName; UninstallString = $wslUninstallString }
    }
    if ($records.Count -gt 0) {
        return [pscustomobject]@{ Status = 'installed-drifted'; Version = $wslVersion; Detail = 'WSL MSI registration exists but its managed executable is missing.'; ProductCode = [string]$records[0].PSChildName; UninstallString = $wslUninstallString }
    }
    if (Test-Path -LiteralPath $wslExecutable -PathType Leaf) {
        return [pscustomobject]@{ Status = 'unknown'; Version = ''; Detail = 'WSL executable exists without its expected MSI uninstall registration.'; ProductCode = ''; UninstallString = '' }
    }
    return [pscustomobject]@{ Status = 'not-installed'; Version = ''; Detail = ''; ProductCode = ''; UninstallString = '' }
}

function Get-ClagnosPackageRecord {
    param([psobject]$Spec)

    $kind = [string]$Spec.statusCheck.kind
    $value = [string]$Spec.statusCheck.value
    $status = 'unknown'
    $version = ''
    $detail = ''
    switch ($kind) {
        'command' {
            $commandPath = ''
            if (Test-Path -LiteralPath $value -PathType Leaf) { $status = 'installed'; $commandPath = [string](Resolve-Path -LiteralPath $value).Path }
            else {
                $command = Get-Command $value -ErrorAction SilentlyContinue
                if ($command) { $status = 'installed'; $commandPath = [string]$command.Source }
            }
            if ($status -eq 'installed' -and -not [string]::IsNullOrWhiteSpace($commandPath)) {
                try {
                    if (Test-Path -LiteralPath $commandPath -PathType Leaf) {
                        $versionInfo = (Get-Item -LiteralPath $commandPath -ErrorAction Stop).VersionInfo
                        $version = [string]$versionInfo.ProductVersion
                        if ([string]::IsNullOrWhiteSpace($version)) { $version = [string]$versionInfo.FileVersion }
                    }
                    if ([string]::IsNullOrWhiteSpace($version) -and [IO.Path]::GetExtension($commandPath) -in @('.cmd','.bat','.exe')) {
                        $versionOutput = & $commandPath --version 2>&1 | Select-Object -First 1
                        if ([string]$versionOutput -match '(?<![A-Za-z])(?<version>\d+(?:\.\d+){1,4}(?:[-+][A-Za-z0-9.-]+)?)') { $version = [string]$Matches.version }
                    }
                }
                catch { $detail = 'Executable is present but its version could not be read.' }
            }
            else { $status = 'not-installed' }
        }
        'windscribe' {
            $windscribeRecord = Get-ClagnosWindscribePackageRecord -Spec $Spec
            $status = [string]$windscribeRecord.Status
            $version = [string]$windscribeRecord.Version
            $detail = [string]$windscribeRecord.Detail
        }
        'wsl' {
            $wslRecord = Get-ClagnosWslPackageRecord -DisplayName $value
            $status = [string]$wslRecord.Status
            $version = [string]$wslRecord.Version
            $detail = [string]$wslRecord.Detail
        }
        'winget' {
            $wingetExe = Resolve-ClagnosWingetExecutable
            if ([string]::IsNullOrWhiteSpace([string]$wingetExe)) { $status = 'unknown'; $detail = 'winget is unavailable for package detection'; break }
            try { $output = & $wingetExe list --id $value --exact --accept-source-agreements --disable-interactivity 2>&1 | Out-String }
            catch { $status = 'unknown'; $detail = 'winget package detection failed'; break }
            $exitCode = [int]$LASTEXITCODE
            if ($exitCode -eq 0 -and $output -match ('(?im)(?:^|\s)' + [regex]::Escape($value) + '(?:\s|$)')) {
                $status = 'installed'
                $version = Get-ClagnosPackageVersionFromOutput -Text $output -PackageId $value
            }
            elseif ($exitCode -eq 0 -or $output -match '(?i)no installed package') { $status = 'not-installed' }
            else { $status = 'unknown'; $detail = ('winget list exited with {0}' -f $exitCode) }
        }
        'choco' {
            $command = Get-Command choco.exe -ErrorAction SilentlyContinue
            if (-not $command) { $status = 'unknown'; $detail = 'Chocolatey is unavailable for package detection'; break }
            try { $output = & $command.Source list --local-only --exact --limit-output $value 2>&1 | Out-String }
            catch { $status = 'unknown'; $detail = 'Chocolatey package detection failed'; break }
            $exitCode = [int]$LASTEXITCODE
            $match = [regex]::Match($output,'(?im)^' + [regex]::Escape($value) + '\|(?<version>[^\s|]+)\s*$')
            $executableName = if ($null -ne $Spec.statusCheck.PSObject.Properties['executable']) { [string]$Spec.statusCheck.executable } else { '' }
            if ($exitCode -eq 0 -and $match.Success) {
                $status = 'installed'
                $version = [string]$match.Groups['version'].Value
                if (-not [string]::IsNullOrWhiteSpace($executableName)) {
                    $executablePaths = if ($null -ne $Spec.statusCheck.PSObject.Properties['executablePaths']) { @($Spec.statusCheck.executablePaths | ForEach-Object { [string]$_ }) } else { @() }
                    $versionArgument = if ($null -ne $Spec.statusCheck.PSObject.Properties['versionArgument']) { [string]$Spec.statusCheck.versionArgument } else { '-version' }
                    $executableRecord = Get-ClagnosChocolateyPackageExecutableRecord -PackageId $value -ExecutableName $executableName -VersionArgument $versionArgument -AdditionalPaths $executablePaths
                    if ([string]$executableRecord.Status -ne 'installed') {
                        $status = 'installed-drifted'
                        $detail = [string]$executableRecord.Detail
                    }
                    else { $detail = [string]$executableRecord.Detail }
                }
            }
            elseif ($exitCode -eq 0) {
                if (-not [string]::IsNullOrWhiteSpace($executableName)) {
                    $executablePaths = if ($null -ne $Spec.statusCheck.PSObject.Properties['executablePaths']) { @($Spec.statusCheck.executablePaths | ForEach-Object { [string]$_ }) } else { @() }
                    $versionArgument = if ($null -ne $Spec.statusCheck.PSObject.Properties['versionArgument']) { [string]$Spec.statusCheck.versionArgument } else { '-version' }
                    $executableRecord = Get-ClagnosChocolateyPackageExecutableRecord -PackageId $value -ExecutableName $executableName -VersionArgument $versionArgument -AdditionalPaths $executablePaths
                    if ([string]$executableRecord.Status -in @('installed','installed-drifted')) {
                        $status = 'unknown'
                        $detail = 'The executable exists but Chocolatey has no matching local package registration; no destructive action was attempted.'
                    }
                    else { $status = 'not-installed' }
                }
                else { $status = 'not-installed' }
            }
            else { $status = 'unknown'; $detail = ('Chocolatey inventory exited with {0}' -f $exitCode) }
        }
        'npm' {
            $command = Get-Command npm.cmd -ErrorAction SilentlyContinue
            if (-not $command) { $command = Get-Command npm -ErrorAction SilentlyContinue }
            if (-not $command) { $status = 'unknown'; $detail = 'npm is unavailable for package detection'; break }
            $applicationData = [Environment]::GetFolderPath([Environment+SpecialFolder]::ApplicationData)
            if ([string]::IsNullOrWhiteSpace([string]$applicationData)) { $applicationData = Join-Path $env:USERPROFILE 'AppData\Roaming' }
            $npmModulesRoot = Join-Path (Join-Path $applicationData 'npm') 'node_modules'
            $packagePath = [string]$npmModulesRoot
            $packagePathIsValid = $true
            foreach ($segment in @([string]$value -split '/')) {
                if ([string]::IsNullOrWhiteSpace([string]$segment) -or [string]$segment -eq '.' -or [string]$segment -eq '..') { $packagePathIsValid = $false; break }
                $packagePath = Join-Path $packagePath ([string]$segment)
            }
            if (-not $packagePathIsValid) { $status = 'unknown'; $detail = 'npm package id is not a safe path'; break }
            if (-not (Test-Path -LiteralPath $packagePath -PathType Container)) { $status = 'not-installed'; break }
            $packageManifestPath = Join-Path $packagePath 'package.json'
            if (-not (Test-Path -LiteralPath $packageManifestPath -PathType Leaf)) { $status = 'unknown'; $detail = 'global npm package directory exists without package.json'; break }
            try {
                $packageManifest = Get-Content -LiteralPath $packageManifestPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                $status = 'installed'
                $version = [string]$packageManifest.version
            }
            catch { $status = 'unknown'; $detail = 'global npm package manifest could not be read' }
        }
        'appx' {
            try { $packages = @(Get-AppxPackage -AllUsers -ErrorAction Stop | Where-Object { $_.Name -like ('*' + $value + '*') -or $_.PackageFamilyName -like ('*' + $value + '*') -or $_.PackageFullName -like ('*' + $value + '*') }) }
            catch { $status = 'unknown'; $detail = 'AppX package inventory query failed'; break }
            if ($packages.Count -gt 0) { $status = 'installed'; $version = [string](@($packages | Sort-Object Version -Descending | Select-Object -First 1)[0].Version) }
            else { $status = 'not-installed' }
        }
        'store-state' {
            $uninstallValue = [string]$Spec.uninstall.value
            try { $matches = @(Get-AppxPackage -AllUsers -ErrorAction Stop | Where-Object { $_.Name -like ('*' + $uninstallValue + '*') -or $_.PackageFamilyName -like ('*' + $uninstallValue + '*') -or $_.PackageFullName -like ('*' + $uninstallValue + '*') }) }
            catch { $status = 'unknown'; $detail = 'AppX package inventory query failed'; break }
            if ($matches.Count -gt 0) { $status = 'installed'; $version = [string](@($matches | Sort-Object Version -Descending | Select-Object -First 1)[0].Version) }
            else {
                $safeName = [regex]::Replace($value,'[^A-Za-z0-9._-]','_')
                $statePath = Join-Path (Join-Path $env:ProgramData 'clagnos\state\store-installs') ($safeName + '.json')
                if (Test-Path -LiteralPath $statePath) {
                    try { $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json; if ([string]$state.State -eq 'installed') { $status = 'unknown'; $detail = 'Store install state exists but its AppX package is absent' } else { $status = 'not-installed' } }
                    catch { $status = 'unknown'; $detail = 'Store install state could not be read' }
                }
                else { $status = 'not-installed' }
            }
        }
        'choco-self' {
            $chocoRoot = Get-ClagnosChocolateyRoot
            $exePath = Join-Path $chocoRoot 'bin\choco.exe'
            if (Test-Path -LiteralPath $exePath -PathType Leaf) {
                $status = 'installed'
                try { $version = [string](& $exePath --version 2>$null | Select-Object -First 1) } catch { $version = '' }
            }
            else { $status = 'not-installed' }
        }
        'sysinternals' {
            $sysinternalsRecord = Get-ClagnosSysinternalsPackageRecord -Spec $Spec
            $status = [string]$sysinternalsRecord.Status
            $version = [string]$sysinternalsRecord.Version
            $detail = [string]$sysinternalsRecord.Detail
        }
        'dpkg' {
            $command = Get-Command dpkg-query -ErrorAction SilentlyContinue
            if (-not $command) { $status = 'unknown'; break }
            & $command.Source -W -f='${Status}' -- $value 2>$null | Out-Null
            if ([int]$LASTEXITCODE -eq 0) { $status = 'installed' } else { $status = 'not-installed' }
        }
        'rpm' {
            $command = Get-Command rpm -ErrorAction SilentlyContinue
            if (-not $command) { $status = 'unknown'; break }
            & $command.Source -q -- $value 2>$null | Out-Null
            if ([int]$LASTEXITCODE -eq 0) { $status = 'installed' } else { $status = 'not-installed' }
        }
        default { $status = 'unknown'; $detail = ('Unsupported status kind: {0}' -f $kind) }
    }
    if ($status -eq 'installed' -and [string]$Spec.id -eq 'jaws' -and @($Spec.targetUsers).Count -gt 0) {
        $jawsDetailParts = New-Object 'System.Collections.Generic.List[string]'
        $missingStartup = @($Spec.targetUsers | Where-Object { -not (Test-ClagnosJawsPostLogonStartup -UserName ([string]$_) -Executable 'C:\Program Files\Freedom Scientific\JAWS\2025\jfw.exe') })
        $logonScreenReady = Test-ClagnosJawsLogonScreenStartup
        if ($missingStartup.Count -gt 0 -or -not $logonScreenReady) {
            if ($missingStartup.Count -gt 0) { $jawsDetailParts.Add('post-logon startup is not verified for: ' + ($missingStartup -join ', ')) | Out-Null }
            if (-not $logonScreenReady) { $jawsDetailParts.Add('logon-screen startup Run=1 is missing') | Out-Null }
            $status = 'installed-drifted'
        }
        else { $jawsDetailParts.Add('JAWS starts at the Windows logon screen and has verified post-logon startup for managed users: ' + (@($Spec.targetUsers) -join ', ')) | Out-Null }
        $updateFileDetail = Get-ClagnosJawsUpdateFilesStateDetail
        if (-not [string]::IsNullOrWhiteSpace([string]$updateFileDetail)) {
            $jawsDetailParts.Add([string]$updateFileDetail) | Out-Null
            if ([string]$updateFileDetail -match '(?i)pending reboot|not verified|could not be read') { $status = 'installed-drifted' }
        }
        $phaseVariable = Get-Variable -Name CLAGNOS_PACKAGE_LIFECYCLE_PHASE -Scope Global -ErrorAction SilentlyContinue
        $currentPhase = if ($null -ne $phaseVariable) { [string]$phaseVariable.Value } else { '' }
        $skipAppStateReadback = $currentPhase -in @('install-verification','repair-verification','update-verification')
        $jawsPackageState = Get-ClagnosJawsPackageStatusDetails -Spec $Spec -SkipProfileState:$skipAppStateReadback
        if (-not [bool]$jawsPackageState.Healthy) { $status = 'installed-drifted' }
        if (-not [string]::IsNullOrWhiteSpace([string]$jawsPackageState.Detail)) { $jawsDetailParts.Add([string]$jawsPackageState.Detail) | Out-Null }
        if ($jawsDetailParts.Count -gt 0) { $detail = $jawsDetailParts -join '; ' }
    }
    elseif ($status -eq 'installed' -and [string]$Spec.id -in @('ollama','docker-desktop')) {
        $detail = Test-ClagnosPackageStartupState -Spec $Spec
    }
    $global:LASTEXITCODE = 0
    return [pscustomobject]@{ Id = [string]$Spec.id; Status = $status; Version = $version; Detail = $detail }
}

function Resolve-ClagnosWingetExecutable {
    $portableCandidate = 'C:\ProgramData\clagnos\tools\winget-x64\winget.exe'
    if (Test-Path -LiteralPath $portableCandidate -PathType Leaf) {
        return [string]$portableCandidate
    }
    $command = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $command) { $command = Get-Command winget -ErrorAction SilentlyContinue }
    if ($command -and -not [string]::IsNullOrWhiteSpace([string]$command.Source)) { return [string]$command.Source }

    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace([string]$env:LOCALAPPDATA)) {
        $candidates += (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe')
    }
    if (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue) {
        try {
            $installerPackages = @(Get-AppxPackage -AllUsers -Name 'Microsoft.DesktopAppInstaller' -ErrorAction Stop | Sort-Object Version -Descending)
            foreach ($installerPackage in @($installerPackages)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$installerPackage.InstallLocation)) {
                    $candidates += (Join-Path ([string]$installerPackage.InstallLocation) 'winget.exe')
                }
            }
        }
        catch { }
    }
    foreach ($candidate in @($candidates | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)) {
        if (Test-Path -LiteralPath ([string]$candidate) -PathType Leaf) { return [string]$candidate }
    }
    return ''
}

function Initialize-ClagnosWingetCommandPath {
    $wingetExe = Resolve-ClagnosWingetExecutable
    if ([string]::IsNullOrWhiteSpace([string]$wingetExe)) { return '' }
    $directory = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath([string]$wingetExe))
    $pathEntries = @(([string]$env:PATH) -split ';' | ForEach-Object { ([string]$_).Trim().TrimEnd('\') } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if (@($pathEntries | Where-Object { [string]::Equals([string]$_,$directory,[System.StringComparison]::OrdinalIgnoreCase) }).Count -eq 0) {
        $env:PATH = [string]$env:PATH + ';' + $directory
    }
    return [string]$wingetExe
}

function Write-ClagnosPackageOperationResult {
    param([psobject]$Spec,[string]$Action,[psobject]$Record,[string]$Message,[double]$DurationSeconds = 0,[switch]$RebootRequired)
    $result = [ordered]@{
        id = [string]$Spec.id
        action = [string]$Action
        status = [string]$Record.Status
        version = [string]$Record.Version
        message = [string]$Message
        detail = [string]$Record.Detail
        durationSeconds = [Math]::Round([double]$DurationSeconds,1)
        phase = [string]$(if ($null -ne (Get-Variable -Name CLAGNOS_PACKAGE_LIFECYCLE_PHASE -Scope Global -ErrorAction SilentlyContinue)) { $global:CLAGNOS_PACKAGE_LIFECYCLE_PHASE } else { 'complete' })
    }
    if ($RebootRequired) { $result.rebootRequired = $true }
    Write-ClagnosPackageResult -Result $result
}

function Test-ClagnosPackageVersionEquivalent {
    param([AllowNull()][string]$Expected,[AllowNull()][string]$Observed)

    $left = [string]$Expected
    $right = [string]$Observed
    if ([string]::IsNullOrWhiteSpace($left) -or [string]::IsNullOrWhiteSpace($right)) { return $false }
    if ([string]::Equals($left,$right,[StringComparison]::OrdinalIgnoreCase)) { return $true }

    $versionPattern = '^(?<numeric>\d+(?:\.\d+)*)(?<suffix>[-+][A-Za-z0-9.-]+)?$'
    $leftMatch = [regex]::Match($left.Trim(),$versionPattern)
    $rightMatch = [regex]::Match($right.Trim(),$versionPattern)
    if (-not $leftMatch.Success -or -not $rightMatch.Success) { return $false }
    if (-not [string]::Equals([string]$leftMatch.Groups['suffix'].Value,[string]$rightMatch.Groups['suffix'].Value,[StringComparison]::OrdinalIgnoreCase)) { return $false }

    $leftParts = New-Object 'System.Collections.Generic.List[long]'
    $rightParts = New-Object 'System.Collections.Generic.List[long]'
    foreach ($part in @([string]$leftMatch.Groups['numeric'].Value -split '\.')) {
        $number = [long]0
        if (-not [long]::TryParse([string]$part,[ref]$number)) { return $false }
        $leftParts.Add($number)
    }
    foreach ($part in @([string]$rightMatch.Groups['numeric'].Value -split '\.')) {
        $number = [long]0
        if (-not [long]::TryParse([string]$part,[ref]$number)) { return $false }
        $rightParts.Add($number)
    }
    while ($leftParts.Count -gt 1 -and $leftParts[$leftParts.Count - 1] -eq 0) { $leftParts.RemoveAt($leftParts.Count - 1) }
    while ($rightParts.Count -gt 1 -and $rightParts[$rightParts.Count - 1] -eq 0) { $rightParts.RemoveAt($rightParts.Count - 1) }
    if ($leftParts.Count -ne $rightParts.Count) { return $false }
    for ($index = 0; $index -lt $leftParts.Count; $index++) {
        if ($leftParts[$index] -ne $rightParts[$index]) { return $false }
    }
    return $true
}

function Set-ClagnosJawsPostLogonStartup {
    param([string[]]$UserNames,[string]$Executable)

    if ([string]::IsNullOrWhiteSpace($Executable) -or -not (Test-Path -LiteralPath $Executable -PathType Leaf)) { throw 'JAWS executable could not be resolved for post-logon startup.' }
    Set-ClagnosJawsLogonScreenStartup
    $machineRunKey = 'Registry::HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Run'
    if (-not (Test-Path -LiteralPath $machineRunKey)) { New-Item -Path $machineRunKey -Force -ErrorAction Stop | Out-Null }
    $machineRunCommand = '"{0}"' -f $Executable
    New-ItemProperty -LiteralPath $machineRunKey -Name 'JAWS' -Value $machineRunCommand -PropertyType String -Force -ErrorAction Stop | Out-Null
    $machineRunVerified = [string](Get-ItemProperty -LiteralPath $machineRunKey -Name 'JAWS' -ErrorAction Stop).JAWS
    if (-not [string]::Equals($machineRunVerified,$machineRunCommand,[StringComparison]::OrdinalIgnoreCase)) { throw 'Machine-wide JAWS post-logon startup did not verify.' }
    foreach ($userName in @($UserNames | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)) {
        Write-Output ("Doing: enable JAWS post-logon startup for user '{0}'" -f [string]$userName)
        try {
            $accountName = ('{0}\{1}' -f $env:COMPUTERNAME,[string]$userName)
            $sid = ([System.Security.Principal.NTAccount]::new($accountName)).Translate([System.Security.Principal.SecurityIdentifier]).Value
            $sidRegistryRoot = 'Registry::HKEY_USERS\{0}' -f $sid
        }
        catch {
            Write-Warning ("Could not resolve the profile for '{0}'; the verified machine-wide startup entry covers future logons. {1}" -f [string]$userName,[string]$_.Exception.Message)
            continue
        }
        if (-not (Test-Path -LiteralPath $sidRegistryRoot)) { Write-Output ("User profile '{0}' is not loaded; machine-wide JAWS startup covers its next logon." -f [string]$userName); continue }
        try {
            $runKey = Join-Path $sidRegistryRoot 'Software\Microsoft\Windows\CurrentVersion\Run'
            if (-not (Test-Path -LiteralPath $runKey)) { New-Item -Path $runKey -Force -ErrorAction Stop | Out-Null }
            $runCommand = '"{0}"' -f $Executable
            New-ItemProperty -LiteralPath $runKey -Name 'JAWS' -Value $runCommand -PropertyType String -Force -ErrorAction Stop | Out-Null
            $verified = [string](Get-ItemProperty -LiteralPath $runKey -Name 'JAWS' -ErrorAction Stop).JAWS
            if (-not [string]::Equals($verified,$runCommand,[StringComparison]::OrdinalIgnoreCase)) { throw ("JAWS post-logon startup did not verify for user '{0}'." -f [string]$userName) }
        }
        catch {
            Write-Warning ("Per-user JAWS startup could not be verified for '{0}'; the verified machine-wide startup entry remains active. {1}" -f [string]$userName,[string]$_.Exception.Message)
        }
    }
}

function Set-ClagnosJawsLogonScreenStartup {
    $jawsSettingsKey = 'Registry::HKEY_LOCAL_MACHINE\Software\Freedom Scientific\JAWS\2025'
    if (-not (Test-Path -LiteralPath $jawsSettingsKey)) { New-Item -Path $jawsSettingsKey -Force -ErrorAction Stop | Out-Null }
    New-ItemProperty -LiteralPath $jawsSettingsKey -Name 'Run' -Value 1 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
    $verified = [int](Get-ItemProperty -LiteralPath $jawsSettingsKey -Name 'Run' -ErrorAction Stop).Run
    if ($verified -ne 1) { throw 'JAWS logon-screen startup did not verify (Freedom Scientific JAWS 2025 Run must equal 1).' }
}

function Test-ClagnosJawsLogonScreenStartup {
    try {
        $jawsSettingsKey = 'Registry::HKEY_LOCAL_MACHINE\Software\Freedom Scientific\JAWS\2025'
        return ([int](Get-ItemProperty -LiteralPath $jawsSettingsKey -Name 'Run' -ErrorAction Stop).Run -eq 1)
    }
    catch { return $false }
}

function Test-ClagnosJawsPostLogonStartup {
    param([string]$UserName,[string]$Executable)

    try {
        $machineValue = [string](Get-ItemProperty -LiteralPath 'Registry::HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'JAWS' -ErrorAction SilentlyContinue).JAWS
        if ([string]::Equals($machineValue,('"{0}"' -f $Executable),[StringComparison]::OrdinalIgnoreCase)) { return $true }
        $accountName = ('{0}\{1}' -f $env:COMPUTERNAME,[string]$UserName)
        $sid = ([System.Security.Principal.NTAccount]::new($accountName)).Translate([System.Security.Principal.SecurityIdentifier]).Value
        $sidRegistryRoot = 'Registry::HKEY_USERS\{0}' -f $sid
        if (-not (Test-Path -LiteralPath $sidRegistryRoot)) { return $false }
        $runKey = Join-Path $sidRegistryRoot 'Software\Microsoft\Windows\CurrentVersion\Run'
        if (-not (Test-Path -LiteralPath $runKey)) { return $false }
        $actual = [string](Get-ItemProperty -LiteralPath $runKey -Name 'JAWS' -ErrorAction SilentlyContinue).JAWS
        return [string]::Equals($actual,('"{0}"' -f $Executable),[StringComparison]::OrdinalIgnoreCase)
    }
    catch { return $false }
}

function Get-ClagnosJawsUninstallEntries {
    param()

    $rows = New-Object 'System.Collections.Generic.List[object]'
    foreach ($registryRoot in @(
        'Registry::HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Uninstall',
        'Registry::HKEY_LOCAL_MACHINE\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )) {
        if (-not (Test-Path -LiteralPath $registryRoot)) { continue }
        foreach ($key in @(Get-ChildItem -LiteralPath $registryRoot -ErrorAction SilentlyContinue)) {
            try { $entry = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction Stop }
            catch { continue }
            $displayNameProperty = $entry.PSObject.Properties['DisplayName']
            $displayName = if ($null -ne $displayNameProperty) { [string]$displayNameProperty.Value } else { '' }
            if ($displayName -match '(?i)^Freedom Scientific JAWS 2025(?:\s|$)') {
                $displayVersionProperty = $entry.PSObject.Properties['DisplayVersion']
                $uninstallStringProperty = $entry.PSObject.Properties['UninstallString']
                $quietUninstallStringProperty = $entry.PSObject.Properties['QuietUninstallString']
                $rows.Add([pscustomobject]@{
                    DisplayName = $displayName
                    DisplayVersion = if ($null -ne $displayVersionProperty) { [string]$displayVersionProperty.Value } else { '' }
                    UninstallString = if ($null -ne $uninstallStringProperty) { [string]$uninstallStringProperty.Value } else { '' }
                    QuietUninstallString = if ($null -ne $quietUninstallStringProperty) { [string]$quietUninstallStringProperty.Value } else { '' }
                }) | Out-Null
            }
        }
    }
    return @($rows.ToArray() | Sort-Object DisplayName -Unique)
}

function Get-ClagnosJawsSetupPackagePath {
    param([switch]$VerifySignature)

    $mainEntry = @(Get-ClagnosJawsUninstallEntries | Where-Object { [string]::Equals([string]$_.DisplayName,'Freedom Scientific JAWS 2025',[StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
    if ($mainEntry.Count -ne 1) { throw 'The registered JAWS 2025 setup package entry could not be resolved.' }
    $commandLines = @([string]$mainEntry[0].QuietUninstallString,[string]$mainEntry[0].UninstallString) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
    $installerPath = ''
    foreach ($commandLine in $commandLines) {
        $match = [regex]::Match([string]$commandLine,'^\s*"(?<quoted>[^"]*JAWS setup package\.exe)"|^\s*(?<plain>.*?JAWS setup package\.exe)(?:\s|$)',[System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($match.Success) {
            $installerPath = if ($match.Groups['quoted'].Success) { [string]$match.Groups['quoted'].Value } else { [string]$match.Groups['plain'].Value }
            break
        }
    }
    if ([string]::IsNullOrWhiteSpace($installerPath)) { throw 'The JAWS 2025 vendor setup executable is not present in its uninstall registration.' }
    $installerPath = [IO.Path]::GetFullPath($installerPath)
    $packageCacheRoot = [IO.Path]::GetFullPath((Join-Path $env:ProgramData 'Package Cache')).TrimEnd('\') + '\'
    if (-not $installerPath.StartsWith($packageCacheRoot,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($installerPath) -ine 'JAWS setup package.exe') {
        throw 'The registered JAWS setup executable is outside the expected Package Cache location.'
    }
    if (-not (Test-Path -LiteralPath $installerPath -PathType Leaf)) { throw 'The registered JAWS setup executable is missing.' }
    if ($VerifySignature) {
        $signature = Get-AuthenticodeSignature -LiteralPath $installerPath -ErrorAction Stop
        $signer = if ($null -ne $signature.SignerCertificate) { [string]$signature.SignerCertificate.Subject } else { '' }
        if ([string]$signature.Status -ne 'Valid' -or $signer -notmatch '(?i)Freedom Scientific|Vispero') {
            throw 'The registered JAWS setup executable does not have a valid Freedom Scientific/Vispero signature.'
        }
    }
    return [string]$installerPath
}

function Test-ClagnosJawsOtherMainProductsInstalled {
    foreach ($registryRoot in @(
        'Registry::HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Uninstall',
        'Registry::HKEY_LOCAL_MACHINE\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )) {
        if (-not (Test-Path -LiteralPath $registryRoot)) { continue }
        foreach ($key in @(Get-ChildItem -LiteralPath $registryRoot -ErrorAction SilentlyContinue)) {
            $entry = $null
            try { $entry = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction Stop } catch { continue }
            $displayNameProperty = $entry.PSObject.Properties['DisplayName']
            $displayName = if ($null -ne $displayNameProperty) { [string]$displayNameProperty.Value } else { '' }
            if ($displayName -match '(?i)^Freedom Scientific (?:ZoomText|MAGic|OpenBook)(?:\s|$)' -or $displayName -match '(?i)^Freedom Scientific Fusion(?:\s|$)' -and $displayName -notmatch '(?i)Fusion Interface') {
                return $true
            }
        }
    }
    return $false
}

function Get-ClagnosJawsVersionDllLoadedProcesses {
    param([string]$FilePath)

    $loadedBy = New-Object 'System.Collections.Generic.List[string]'
    foreach ($process in @(Get-Process -ErrorAction SilentlyContinue)) {
        try {
            if (@($process.Modules | Where-Object { [string]::Equals([string]$_.FileName,[string]$FilePath,[StringComparison]::OrdinalIgnoreCase) }).Count -gt 0) {
                $loadedBy.Add([string]$process.ProcessName) | Out-Null
            }
        }
        catch { }
    }
    return @($loadedBy.ToArray() | Sort-Object -Unique)
}

function Remove-ClagnosJawsProgramDirectory {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return }
    try {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        return
    }
    catch {
        $loadedVersionDll = Join-Path $Path 'version.dll'
        if (-not (Test-Path -LiteralPath $loadedVersionDll -PathType Leaf)) { throw }
        $loadedBy = @(Get-ClagnosJawsVersionDllLoadedProcesses -FilePath $loadedVersionDll)
        if ($loadedBy.Count -eq 0) { throw }
        Write-Output ('Doing: preserve the JAWS version.dll currently loaded by Windows processes; the package update helper will replace it safely and request a reboot if needed')
        foreach ($file in @(Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction Stop | Where-Object { -not [string]::Equals([string]$_.FullName,[string]$loadedVersionDll,[StringComparison]::OrdinalIgnoreCase) })) {
            try { Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop }
            catch { throw ('Could not remove a JAWS program file while preserving the loaded proxy DLL: ' + [string]$file.Name) }
        }
        foreach ($directory in @(Get-ChildItem -LiteralPath $Path -Recurse -Directory -Force -ErrorAction Stop | Sort-Object { $_.FullName.Length } -Descending)) {
            if (@(Get-ChildItem -LiteralPath $directory.FullName -Force -ErrorAction SilentlyContinue).Count -eq 0) {
                Remove-Item -LiteralPath $directory.FullName -Force -ErrorAction Stop
            }
        }
        $remaining = @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop)
        if ($remaining.Count -ne 1 -or -not [string]::Equals([string]$remaining[0].FullName,[string]$loadedVersionDll,[StringComparison]::OrdinalIgnoreCase)) {
            throw 'JAWS program directory contains unexpected leftovers after lock-aware cleanup.'
        }
    }
}

function Clear-ClagnosJawsOwnedData {
    param([psobject]$Spec,[switch]$ClearSharedComponents,[switch]$PreservePackageAssets)

    $otherMainProductInstalled = Test-ClagnosJawsOtherMainProductsInstalled
    $programRoots = @($env:ProgramFiles,[string]${env:ProgramFiles(x86)}) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique
    foreach ($programRoot in @($programRoots)) {
        $jawsPath = Join-Path ([string]$programRoot) 'Freedom Scientific\JAWS\2025'
        if (Test-Path -LiteralPath $jawsPath) {
            Write-Output ('Doing: remove JAWS 2025 program files from ' + $jawsPath)
            Remove-ClagnosJawsProgramDirectory -Path $jawsPath
        }
        if ($ClearSharedComponents -and -not $otherMainProductInstalled) {
            $sharedPath = Join-Path ([string]$programRoot) 'Freedom Scientific\Shared'
            if (Test-Path -LiteralPath $sharedPath) {
                Write-Output ('Doing: remove Freedom Scientific shared components after verifying no other main Freedom Scientific product remains')
                Remove-Item -LiteralPath $sharedPath -Recurse -Force -ErrorAction Stop
            }
        }
    }

    $programDataPaths = @(
        (Join-Path $env:ProgramData 'Freedom Scientific\JAWS\2025'),
        (Join-Path $env:ProgramData 'Freedom Scientific\JAWS\2025\SETTINGS')
    ) | Select-Object -Unique
    foreach ($path in @($programDataPaths)) {
        if (Test-Path -LiteralPath $path) {
            Write-Output ('Doing: remove JAWS 2025 program data from ' + $path)
            Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
        }
    }

    $profiles = @(Get-CimInstance -ClassName Win32_UserProfile -ErrorAction SilentlyContinue | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.LocalPath) })
    foreach ($userName in @($Spec.targetUsers | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)) {
        $profile = @($profiles | Where-Object { [string]::Equals((Split-Path -Leaf ([string]$_.LocalPath)),[string]$userName,[StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
        $profileRoot = if ($profile.Count -gt 0) { [string]$profile[0].LocalPath } else { Join-Path $env:SystemDrive ('Users\' + [string]$userName) }
        $fullProfileRoot = [IO.Path]::GetFullPath($profileRoot).TrimEnd('\') + '\'
        foreach ($scope in @('Roaming','Local')) {
            $path = [IO.Path]::GetFullPath((Join-Path (Join-Path $profileRoot ('AppData\' + $scope)) 'Freedom Scientific\JAWS\2025'))
            if (-not $path.StartsWith($fullProfileRoot,[StringComparison]::OrdinalIgnoreCase)) { throw 'JAWS profile cleanup resolved outside the selected manager/assistant profile.' }
            if (Test-Path -LiteralPath $path) {
                Write-Output ('Doing: remove JAWS 2025 ' + $scope.ToLowerInvariant() + ' settings for a selected managed user')
                Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
            }
        }
        $tempRoot = Join-Path (Join-Path $profileRoot 'AppData\Local') 'Temp'
        if (Test-Path -LiteralPath $tempRoot) {
            foreach ($tempEntry in @(Get-ChildItem -LiteralPath $tempRoot -Force -ErrorAction SilentlyContinue | Where-Object { [string]$_.Name -match '(?i)^(?:jaws|jfw|fsjaws|freedom.?scientific.?jaws)' })) {
                Write-Output ('Doing: remove JAWS-specific temporary data entry ' + [string]$tempEntry.Name)
                Remove-Item -LiteralPath $tempEntry.FullName -Recurse -Force -ErrorAction Stop
            }
        }
    }

    $windowsTemp = Join-Path $env:SystemRoot 'Temp'
    if (Test-Path -LiteralPath $windowsTemp) {
        foreach ($tempEntry in @(Get-ChildItem -LiteralPath $windowsTemp -Force -ErrorAction SilentlyContinue | Where-Object { [string]$_.Name -match '(?i)^(?:jaws|jfw|fsjaws|freedom.?scientific.?jaws)' })) {
            Write-Output ('Doing: remove JAWS-specific Windows temporary data entry ' + [string]$tempEntry.Name)
            Remove-Item -LiteralPath $tempEntry.FullName -Recurse -Force -ErrorAction Stop
        }
    }
    $jawsAsset = 'C:\Windows\Temp\clagnos-jaws-app-state.zip'
    if (-not $PreservePackageAssets -and (Test-Path -LiteralPath $jawsAsset -PathType Leaf)) { Remove-Item -LiteralPath $jawsAsset -Force -ErrorAction Stop }
    $jawsUpdateState = Join-Path (Join-Path $env:ProgramData 'clagnos\state\packages') 'jaws-update-files.json'
    if (Test-Path -LiteralPath $jawsUpdateState -PathType Leaf) { Remove-Item -LiteralPath $jawsUpdateState -Force -ErrorAction Stop }
    $jawsInstallPolicyState = Join-Path (Join-Path $env:ProgramData 'clagnos\state\packages') 'jaws-install-policy.json'
    if (Test-Path -LiteralPath $jawsInstallPolicyState -PathType Leaf) { Remove-Item -LiteralPath $jawsInstallPolicyState -Force -ErrorAction Stop }

    if ($ClearSharedComponents -and -not $otherMainProductInstalled) {
        foreach ($programRoot in @($programRoots)) {
            $sharedPath = Join-Path ([string]$programRoot) 'Freedom Scientific\Shared'
            if (Test-Path -LiteralPath $sharedPath) { throw ('Freedom Scientific shared components remain after JAWS cleanup: ' + $sharedPath) }
        }
    }
}

function Invoke-ClagnosJawsVendorUninstall {
    param([psobject]$Spec,[switch]$CleanSharedComponents,[switch]$PreservePackageAssets)

    if ([string]$Spec.id -ne 'jaws' -or [string]$Spec.uninstall.value -ne 'FreedomScientific.JAWS.2025') { throw 'The JAWS vendor remover is reserved for the builtin Freedom Scientific JAWS 2025 package.' }
    $currentProductEntry = @(Get-ClagnosJawsUninstallEntries | Where-Object { [string]::Equals([string]$_.DisplayName,'Freedom Scientific JAWS 2025',[StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
    $installedVersion = if ($currentProductEntry.Count -gt 0) { [string]$currentProductEntry[0].DisplayVersion } else { '' }
    $setupPackagePath = Get-ClagnosJawsSetupPackagePath -VerifySignature
    $otherMainProductInstalled = Test-ClagnosJawsOtherMainProductsInstalled
    $setupType = if ($CleanSharedComponents -and -not $otherMainProductInstalled) { 'SilentSharedUninstall' } else { 'SilentUninstall' }
    foreach ($process in @(Get-Process -Name jfw -ErrorAction SilentlyContinue)) {
        Write-Output 'Doing: close jfw.exe before JAWS 2025 removal'
        Stop-Process -Id ([int]$process.Id) -Force -ErrorAction Stop
    }
    $processDeadline = [DateTime]::UtcNow.AddSeconds(30)
    while (@(Get-Process -Name jfw -ErrorAction SilentlyContinue).Count -gt 0 -and [DateTime]::UtcNow -lt $processDeadline) { Start-Sleep -Seconds 1 }
    if (@(Get-Process -Name jfw -ErrorAction SilentlyContinue).Count -gt 0) { throw 'jfw.exe remained active; JAWS uninstall was not started.' }

    Write-Output ("Doing: run the signed JAWS 2025 {0} to remove the product{1}" -f $setupType,$(if ($setupType -eq 'SilentSharedUninstall') { ' and its shared components' } else { '' }))
    $startedAt = [DateTime]::UtcNow
    $uninstaller = Start-Process -FilePath $setupPackagePath -ArgumentList @('/type',$setupType) -WindowStyle Hidden -PassThru -ErrorAction Stop
    $deadline = $startedAt.AddSeconds(300)
    $nextHeartbeat = $startedAt.AddSeconds(15)
    while (-not $uninstaller.HasExited) {
        if ([DateTime]::UtcNow -ge $deadline) {
            $taskkill = Join-Path $env:SystemRoot 'System32\taskkill.exe'
            if (Test-Path -LiteralPath $taskkill -PathType Leaf) { & $taskkill /F /T /PID ([string]$uninstaller.Id) 2>$null | Out-Null }
            Stop-Process -Id ([int]$uninstaller.Id) -Force -ErrorAction SilentlyContinue
            throw 'JAWS vendor uninstaller exceeded its finite 300-second deadline.'
        }
        if ([DateTime]::UtcNow -ge $nextHeartbeat) {
            Write-Output ('Doing: JAWS vendor uninstall is still running ({0}s elapsed)' -f [int]([DateTime]::UtcNow - $startedAt).TotalSeconds)
            $nextHeartbeat = [DateTime]::UtcNow.AddSeconds(15)
        }
        Start-Sleep -Milliseconds 500
        $uninstaller.Refresh()
    }
    $uninstaller.WaitForExit()
    if ([int]$uninstaller.ExitCode -eq 3010) {
        $global:CLAGNOS_PACKAGE_REBOOT_REQUIRED = $true
        Write-Output 'Doing: JAWS vendor uninstall requested a reboot; package verification will continue without powering off the VM.'
    }
    elseif ([int]$uninstaller.ExitCode -ne 0) { throw ('JAWS vendor uninstaller exited with code ' + [int]$uninstaller.ExitCode) }

    $absenceDeadline = [DateTime]::UtcNow.AddSeconds(45)
    do {
        $remainingEntries = @(Get-ClagnosJawsUninstallEntries)
        $jawsExecutablePresent = Test-Path -LiteralPath 'C:\Program Files\Freedom Scientific\JAWS\2025\jfw.exe' -PathType Leaf
        $jawsExecutablePresent = $jawsExecutablePresent -or (Test-Path -LiteralPath 'C:\Program Files (x86)\Freedom Scientific\JAWS\2025\jfw.exe' -PathType Leaf)
        if ($remainingEntries.Count -eq 0 -and -not $jawsExecutablePresent) { break }
        if ([DateTime]::UtcNow -ge $absenceDeadline) { throw ('JAWS uninstall did not verify product and language removal; registration count={0}; executablePresent={1}.' -f $remainingEntries.Count,$jawsExecutablePresent) }
        Write-Output ('Doing: wait for JAWS 2025 product and language registrations to disappear')
        Start-Sleep -Seconds 3
    } while ($true)

    Remove-ClagnosPackageStartupArtifacts -Spec $Spec
    Clear-ClagnosJawsOwnedData -Spec $Spec -ClearSharedComponents:$CleanSharedComponents -PreservePackageAssets:$PreservePackageAssets
    if (@(Get-ClagnosJawsUninstallEntries).Count -gt 0) { throw 'JAWS 2025 registration remained after vendor uninstall and targeted cleanup.' }
    $global:CLAGNOS_JAWS_VENDOR_UNINSTALL_RESULT = [pscustomobject]@{ InstallerPath = [string]$setupPackagePath; Version = [string]$installedVersion; SetupType = [string]$setupType }
    return
}

function Get-ClagnosJawsPackageStatusDetails {
    param([psobject]$Spec,[switch]$SkipProfileState)

    $details = New-Object 'System.Collections.Generic.List[string]'
    $healthy = $true
    $registrations = @(Get-ClagnosJawsUninstallEntries)
    $enuPresent = @($registrations | Where-Object { [string]$_.DisplayName -match '(?i)^Freedom Scientific JAWS 2025 ENU$' }).Count -gt 0
    $trkPresent = @($registrations | Where-Object { [string]$_.DisplayName -match '(?i)^Freedom Scientific JAWS 2025 TRK$' }).Count -gt 0
    if (-not $enuPresent) { $details.Add('English (United States) ENU component is not registered') | Out-Null; $healthy = $false }
    if ($trkPresent) { $details.Add('unexpected Turkish TRK component is installed') | Out-Null; $healthy = $false }

    $policyStatePath = Join-Path (Join-Path $env:ProgramData 'clagnos\state\packages') 'jaws-install-policy.json'
    $offlinePolicyVerified = $false
    if (Test-Path -LiteralPath $policyStatePath -PathType Leaf) {
        try {
            $policyState = Get-Content -LiteralPath $policyStatePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            $installerArguments = [string]$policyState.InstallerArguments
            $offlinePolicyVerified = ([string]$policyState.PackageId -eq 'FreedomScientific.JAWS.2025' -and [string]$policyState.ProductLanguage -eq 'enu' -and [string]$policyState.InstallerUiLanguage -eq 'enu' -and [bool]$policyState.DisableExternalServices -and $installerArguments -match '(?i)/Language\s+enu' -and $installerArguments -match '(?i)/InstallerUILanguage\s+enu' -and $installerArguments -match '(?i)/DisableExternalServices')
        }
        catch { $offlinePolicyVerified = $false }
    }
    if (-not $offlinePolicyVerified) { $details.Add('ENU/offline installer policy record is missing or invalid') | Out-Null; $healthy = $false }

    if (-not $SkipProfileState) {
        $targetUsers = @($Spec.targetUsers | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        for ($targetUserIndex = 0; $targetUserIndex -lt $targetUsers.Count; $targetUserIndex++) {
            $userName = [string]$targetUsers[$targetUserIndex]
            $targetRole = if ($targetUserIndex -eq 0) { 'manager' } elseif ($targetUserIndex -eq 1) { 'assistant' } else { '' }
            $profile = @(Get-CimInstance -ClassName Win32_UserProfile -ErrorAction SilentlyContinue | Where-Object { [string]::Equals((Split-Path -Leaf ([string]$_.LocalPath)),[string]$userName,[StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
            $profileRoot = if ($profile.Count -gt 0) { [string]$profile[0].LocalPath } else { Join-Path $env:SystemDrive ('Users\' + [string]$userName) }
            $trkDirectory = Join-Path $profileRoot 'AppData\Roaming\Freedom Scientific\JAWS\2025\Settings\trk'
            if (Test-Path -LiteralPath $trkDirectory -PathType Container) { $details.Add(('Turkish profile settings remain for ' + [string]$userName)) | Out-Null; $healthy = $false }
            foreach ($rule in @($Spec.appState.profileFiles)) {
                if ([string]::IsNullOrWhiteSpace($targetRole) -or @($rule.targetProfiles | Where-Object { [string]::Equals([string]$_,$targetRole,[StringComparison]::OrdinalIgnoreCase) }).Count -eq 0) { continue }
                $relative = [string]$rule.path
                if ([string]::IsNullOrWhiteSpace($relative) -or [IO.Path]::IsPathRooted($relative) -or $relative -match '(^|[\\/])\.\.([\\/]|$)') { $details.Add('JAWS app-state contains an unsafe profile path') | Out-Null; $healthy = $false; continue }
                $candidate = Join-Path $profileRoot $relative
                $parent = Split-Path -Parent $candidate
                $leafPattern = Split-Path -Leaf $candidate
                $matchedPreferenceFiles = @()
                if ($leafPattern.Contains('*') -or $leafPattern.Contains('?')) { $matchedPreferenceFiles = @(Get-ChildItem -LiteralPath $parent -File -Filter $leafPattern -ErrorAction SilentlyContinue) }
                elseif (Test-Path -LiteralPath $candidate -PathType Leaf) { $matchedPreferenceFiles = @((Get-Item -LiteralPath $candidate)) }
                if (@($matchedPreferenceFiles).Count -eq 0) { $details.Add(('missing JAWS preference ' + $leafPattern + ' for ' + [string]$userName)) | Out-Null; $healthy = $false }
            }
        }
    }
    if ($details.Count -eq 0) { $details.Add('ENU-only install, offline external-service restrictions, managed JAWS preferences, and startup policy are verified') | Out-Null }
    return [pscustomobject]@{ Healthy = [bool]$healthy; Detail = ($details.ToArray() -join '; ') }
}

function Remove-ClagnosPackageStartupArtifacts {
    param([psobject]$Spec)

    switch ([string]$Spec.id) {
        'jaws' {
            $jawsSettingsKey = 'Registry::HKEY_LOCAL_MACHINE\Software\Freedom Scientific\JAWS\2025'
            if (Test-Path -LiteralPath $jawsSettingsKey) { Remove-ItemProperty -LiteralPath $jawsSettingsKey -Name 'Run' -ErrorAction SilentlyContinue }
            $machineRunKey = 'Registry::HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Run'
            if (Test-Path -LiteralPath $machineRunKey) { Remove-ItemProperty -LiteralPath $machineRunKey -Name 'JAWS' -ErrorAction SilentlyContinue }
            foreach ($userName in @($Spec.targetUsers | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)) {
                try {
                    $accountName = ('{0}\{1}' -f $env:COMPUTERNAME,[string]$userName)
                    $sid = ([System.Security.Principal.NTAccount]::new($accountName)).Translate([System.Security.Principal.SecurityIdentifier]).Value
                    $userRunKey = 'Registry::HKEY_USERS\{0}\Software\Microsoft\Windows\CurrentVersion\Run' -f $sid
                    if (Test-Path -LiteralPath $userRunKey) { Remove-ItemProperty -LiteralPath $userRunKey -Name 'JAWS' -ErrorAction SilentlyContinue }
                }
                catch { Write-Warning ("Could not remove the JAWS startup entry for user '{0}': {1}" -f [string]$userName,[string]$_.Exception.Message) }
            }
        }
        'ollama' {
            foreach ($userName in @($Spec.targetUsers | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)) {
                try {
                    $accountName = ('{0}\{1}' -f $env:COMPUTERNAME,[string]$userName)
                    $sid = ([System.Security.Principal.NTAccount]::new($accountName)).Translate([System.Security.Principal.SecurityIdentifier]).Value
                    $profile = Get-CimInstance -ClassName Win32_UserProfile -Filter ("SID='{0}'" -f $sid) -ErrorAction Stop
                    if ($null -eq $profile -or [string]::IsNullOrWhiteSpace([string]$profile.LocalPath)) { continue }
                    $startupShortcut = Join-Path ([string]$profile.LocalPath) 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\Ollama.lnk'
                    if (Test-Path -LiteralPath $startupShortcut) { Remove-Item -LiteralPath $startupShortcut -Force -ErrorAction Stop }
                }
                catch { Write-Warning ("Could not remove the Ollama startup shortcut for user '{0}': {1}" -f [string]$userName,[string]$_.Exception.Message) }
            }
        }
        'docker-desktop' {
            $startupShortcut = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\StartUp\Docker Desktop.lnk'
            if (Test-Path -LiteralPath $startupShortcut) { Remove-Item -LiteralPath $startupShortcut -Force -ErrorAction Stop }
            $entryName = if ($null -ne $Spec.startupPolicy -and -not [string]::IsNullOrWhiteSpace([string]$Spec.startupPolicy.userRunEntryName)) { [string]$Spec.startupPolicy.userRunEntryName } else { 'Docker Desktop' }
            foreach ($userName in @($Spec.targetUsers | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)) {
                $sid = Get-ClagnosPackageUserSid -UserName ([string]$userName)
                $runKey = if (-not [string]::IsNullOrWhiteSpace([string]$sid)) { 'Registry::HKEY_USERS\{0}\Software\Microsoft\Windows\CurrentVersion\Run' -f [string]$sid } else { '' }
                if (-not [string]::IsNullOrWhiteSpace($runKey) -and (Test-Path -LiteralPath $runKey)) { Remove-ItemProperty -LiteralPath $runKey -Name $entryName -ErrorAction SilentlyContinue }
                $profilePath = Get-ClagnosPackageUserProfilePath -UserName ([string]$userName)
                $userShortcut = Join-Path $profilePath 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\Docker Desktop.lnk'
                if (Test-Path -LiteralPath $userShortcut -PathType Leaf) { Remove-Item -LiteralPath $userShortcut -Force -ErrorAction SilentlyContinue }
            }
        }
    }
}

function Get-ClagnosPackageUserProfilePath {
    param([string]$UserName)
    try {
        $accountName = ('{0}\{1}' -f $env:COMPUTERNAME,[string]$UserName)
        $sid = ([System.Security.Principal.NTAccount]::new($accountName)).Translate([System.Security.Principal.SecurityIdentifier]).Value
        $profile = Get-CimInstance -ClassName Win32_UserProfile -Filter ("SID='{0}'" -f $sid) -ErrorAction Stop
        if ($null -ne $profile -and -not [string]::IsNullOrWhiteSpace([string]$profile.LocalPath)) { return [string]$profile.LocalPath }
    }
    catch { }
    if ([string]::IsNullOrWhiteSpace([string]$UserName)) { return '' }
    return (Join-Path $env:SystemDrive (Join-Path 'Users' ([string]$UserName)))
}

function Set-ClagnosPackageStartupShortcut {
    param([string]$ShortcutPath,[string]$TargetPath,[string]$Arguments = '')
    if (-not (Test-Path -LiteralPath $TargetPath -PathType Leaf)) { throw ("Startup target does not exist: {0}" -f [System.IO.Path]::GetFileName($TargetPath)) }
    $startupDirectory = Split-Path -Parent $ShortcutPath
    if (-not (Test-Path -LiteralPath $startupDirectory -PathType Container)) { New-Item -ItemType Directory -Path $startupDirectory -Force -ErrorAction Stop | Out-Null }
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    $shortcut.TargetPath = $TargetPath
    $shortcut.Arguments = $Arguments
    $shortcut.WorkingDirectory = Split-Path -Parent $TargetPath
    $shortcut.IconLocation = "$TargetPath,0"
    $shortcut.Save()
    $verified = $shell.CreateShortcut($ShortcutPath)
    if (-not (Test-Path -LiteralPath $ShortcutPath -PathType Leaf) -or
        -not [string]::Equals([string]$verified.TargetPath,[string]$TargetPath,[StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::Equals([string]$verified.Arguments,[string]$Arguments,[StringComparison]::Ordinal)) {
        throw ("Startup shortcut did not verify: {0}" -f [System.IO.Path]::GetFileName($ShortcutPath))
    }
}

function Get-ClagnosPackageUserSid {
    param([Parameter(Mandatory = $true)][string]$UserName)
    try {
        $accountName = ('{0}\{1}' -f $env:COMPUTERNAME,$UserName)
        return [string]([System.Security.Principal.NTAccount]::new($accountName)).Translate([System.Security.Principal.SecurityIdentifier]).Value
    }
    catch { return '' }
}

function Test-ClagnosPackageDockerStartupForUser {
    param([string]$UserName,[string]$EntryName,[string]$TargetPath,[string]$Arguments)
    $expectedCommand = '"{0}"' -f [string]$TargetPath
    if (-not [string]::IsNullOrWhiteSpace([string]$Arguments)) { $expectedCommand += ' ' + [string]$Arguments }
    $sid = Get-ClagnosPackageUserSid -UserName $UserName
    if (-not [string]::IsNullOrWhiteSpace([string]$sid)) {
        $runKey = 'Registry::HKEY_USERS\{0}\Software\Microsoft\Windows\CurrentVersion\Run' -f [string]$sid
        try {
            if (Test-Path -LiteralPath $runKey) {
                $runState = Get-ItemProperty -LiteralPath $runKey -Name $EntryName -ErrorAction SilentlyContinue
                $runValue = if ($null -ne $runState) { [string]$runState.$EntryName } else { '' }
                if ([string]::Equals($runValue,$expectedCommand,[System.StringComparison]::OrdinalIgnoreCase)) { return $true }
            }
        }
        catch { }
    }

    $profilePath = Get-ClagnosPackageUserProfilePath -UserName $UserName
    if ([string]::IsNullOrWhiteSpace([string]$profilePath)) { return $false }
    $shortcutPath = Join-Path $profilePath 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\Docker Desktop.lnk'
    if (-not (Test-Path -LiteralPath $shortcutPath -PathType Leaf)) { return $false }
    try {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($shortcutPath)
        return ([string]::Equals([string]$shortcut.TargetPath,[string]$TargetPath,[System.StringComparison]::OrdinalIgnoreCase) -and [string]::Equals([string]$shortcut.Arguments,[string]$Arguments,[System.StringComparison]::Ordinal))
    }
    catch { return $false }
}

function Set-ClagnosOllamaStartupState {
    param([string[]]$UserNames)
    $appCandidates = @(
        (Join-Path $env:ProgramFiles 'Ollama\ollama app.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama app.exe')
    )
    foreach ($userName in @($UserNames)) {
        $profilePath = Get-ClagnosPackageUserProfilePath -UserName ([string]$userName)
        if (-not [string]::IsNullOrWhiteSpace([string]$profilePath)) { $appCandidates += (Join-Path $profilePath 'AppData\Local\Programs\Ollama\ollama app.exe') }
    }
    $appExe = @($appCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1)
    if ($appExe.Count -ne 1) { throw 'Ollama desktop startup executable could not be resolved after package install/update.' }
    foreach ($userName in @($UserNames | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)) {
        $profilePath = Get-ClagnosPackageUserProfilePath -UserName ([string]$userName)
        $shortcutPath = Join-Path $profilePath 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\Ollama.lnk'
        Write-Output ("Doing: ensure Ollama startup for managed user '{0}'" -f [string]$userName)
        Set-ClagnosPackageStartupShortcut -ShortcutPath $shortcutPath -TargetPath ([string]$appExe[0])
    }
}

function Set-ClagnosPackageStartupState {
    param([psobject]$Spec)
    switch ([string]$Spec.id) {
        'ollama' { Set-ClagnosOllamaStartupState -UserNames @($Spec.targetUsers); break }
        'docker-desktop' {
            $dockerExe = Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
            $entryName = if ($null -ne $Spec.startupPolicy -and -not [string]::IsNullOrWhiteSpace([string]$Spec.startupPolicy.userRunEntryName)) { [string]$Spec.startupPolicy.userRunEntryName } else { 'Docker Desktop' }
            $arguments = if ($null -ne $Spec.startupPolicy -and $null -ne $Spec.startupPolicy.launchArgument) { [string]$Spec.startupPolicy.launchArgument } else { '--minimized' }
            $users = @($Spec.targetUsers | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
            if ($users.Count -eq 0 -and $null -ne $Spec.startupPolicy) { $users = @($Spec.startupPolicy.roles | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) }
            $machineShortcut = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\StartUp\Docker Desktop.lnk'
            if (Test-Path -LiteralPath $machineShortcut -PathType Leaf) { Remove-Item -LiteralPath $machineShortcut -Force -ErrorAction SilentlyContinue }
            foreach ($userName in @($users)) {
                if (Test-ClagnosPackageDockerStartupForUser -UserName ([string]$userName) -EntryName $entryName -TargetPath $dockerExe -Arguments $arguments) {
                    Write-Output ("Docker Desktop startup is already verified for '{0}'." -f [string]$userName)
                    continue
                }
                $profilePath = Get-ClagnosPackageUserProfilePath -UserName ([string]$userName)
                $userShortcut = Join-Path $profilePath 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\Docker Desktop.lnk'
                Write-Output ("Doing: ensure Docker Desktop startup for managed user '{0}'" -f [string]$userName)
                Set-ClagnosPackageStartupShortcut -ShortcutPath $userShortcut -TargetPath $dockerExe -Arguments $arguments
            }
            break
        }
    }
}

function Invoke-ClagnosPackageScriptStreamed {
    param([Parameter(Mandatory = $true)][string]$ScriptText)

    $outputLines = New-Object 'System.Collections.Generic.List[string]'
    & ([scriptblock]::Create($ScriptText)) *>&1 | ForEach-Object {
        $line = [string]($_ | Out-String).TrimEnd()
        if (-not [string]::IsNullOrWhiteSpace($line)) {
            $outputLines.Add($line) | Out-Null
            Write-Host $line
        }
    }
    return [string]($outputLines.ToArray() -join [Environment]::NewLine)
}

function Test-ClagnosPackageStartupState {
    param([psobject]$Spec)
    switch ([string]$Spec.id) {
        'ollama' {
            $missing = @()
            foreach ($userName in @($Spec.targetUsers | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)) {
                $profilePath = Get-ClagnosPackageUserProfilePath -UserName ([string]$userName)
                $shortcutPath = Join-Path $profilePath 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\Ollama.lnk'
                if (-not (Test-Path -LiteralPath $shortcutPath -PathType Leaf)) { $missing += [string]$userName }
            }
            if ($missing.Count -gt 0) { return ('Ollama startup shortcut is missing for: ' + ($missing -join ', ')) }
            return 'Ollama startup shortcuts are verified for managed users.'
        }
        'docker-desktop' {
            $dockerExe = Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
            $entryName = if ($null -ne $Spec.startupPolicy -and -not [string]::IsNullOrWhiteSpace([string]$Spec.startupPolicy.userRunEntryName)) { [string]$Spec.startupPolicy.userRunEntryName } else { 'Docker Desktop' }
            $arguments = if ($null -ne $Spec.startupPolicy -and $null -ne $Spec.startupPolicy.launchArgument) { [string]$Spec.startupPolicy.launchArgument } else { '--minimized' }
            $users = @($Spec.targetUsers | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
            if ($users.Count -eq 0 -and $null -ne $Spec.startupPolicy) { $users = @($Spec.startupPolicy.roles | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) }
            $missingUsers = @($users | Where-Object { -not (Test-ClagnosPackageDockerStartupForUser -UserName ([string]$_) -EntryName $entryName -TargetPath $dockerExe -Arguments $arguments) })
            if ($missingUsers.Count -gt 0) { return ('Docker Desktop startup is missing for: ' + ($missingUsers -join ', ')) }
            return ('Docker Desktop startup is verified for managed users: ' + ($users -join ', '))
        }
        default { return '' }
    }
}

function Get-ClagnosJawsUpdateFilesStatePath {
    return (Join-Path (Join-Path $env:ProgramData 'clagnos\state\packages') 'jaws-update-files.json')
}

function Save-ClagnosJawsUpdateFilesState {
    param([object[]]$Files,[bool]$DeferredUntilReboot)

    $statePath = Get-ClagnosJawsUpdateFilesStatePath
    $directory = Split-Path -Parent $statePath
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop | Out-Null }
    $state = [ordered]@{
        PackageId = 'jaws'
        PackageVersion = '2025'
        Files = @($Files)
        DeferredUntilReboot = [bool]$DeferredUntilReboot
        UpdatedAtUtc = [DateTime]::UtcNow.ToString('o')
    }
    [IO.File]::WriteAllText($statePath,(ConvertTo-Json -InputObject $state -Depth 10 -Compress),(New-Object System.Text.UTF8Encoding($false)))
}

function Get-ClagnosJawsUpdateFilesStateDetail {
    $statePath = Get-ClagnosJawsUpdateFilesStatePath
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { return '' }
    try { $state = Get-Content -LiteralPath $statePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
    catch { return 'JAWS update-files verification state could not be read.' }
    $mismatches = New-Object 'System.Collections.Generic.List[string]'
    foreach ($file in @($state.Files)) {
        $path = [string]$file.Path
        if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { $mismatches.Add([string]$file.Relative) | Out-Null; continue }
        try {
            $actualHash = [string](Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash
            if (-not [string]::Equals($actualHash,[string]$file.Sha256,[StringComparison]::OrdinalIgnoreCase)) { $mismatches.Add([string]$file.Relative) | Out-Null }
        }
        catch { $mismatches.Add([string]$file.Relative) | Out-Null }
    }
    if ($mismatches.Count -gt 0) {
        if ([bool]$state.DeferredUntilReboot) { return ('JAWS update-files replacement is pending reboot for: ' + ($mismatches -join ', ')) }
        return ('JAWS update-files payload is not verified for: ' + ($mismatches -join ', '))
    }
    return 'JAWS update-files payload is verified against the package app-state archive.'
}

function Queue-ClagnosJawsUpdateFileReplacementForReboot {
    param([string]$StagedPath,[string]$DestinationPath,[string]$ExpectedHash)

    $stagedHash = [string](Get-FileHash -LiteralPath $StagedPath -Algorithm SHA256 -ErrorAction Stop).Hash
    if (-not [string]::Equals($stagedHash,[string]$ExpectedHash,[StringComparison]::OrdinalIgnoreCase)) { throw ('Staged JAWS update-file SHA256 verification failed: ' + [IO.Path]::GetFileName($DestinationPath)) }
    if (-not ('ClagnosJawsMoveFileEx' -as [type])) {
        Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public static class ClagnosJawsMoveFileEx {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool MoveFileEx(string existingFileName, string newFileName, int flags);
}
'@ -ErrorAction Stop
    }
    # MOVEFILE_REPLACE_EXISTING | MOVEFILE_DELAY_UNTIL_REBOOT keeps the loaded proxy DLL intact until Windows restarts.
    $flags = 0x1 -bor 0x4
    if (-not [ClagnosJawsMoveFileEx]::MoveFileEx($StagedPath,$DestinationPath,$flags)) {
        $nativeError = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw ('Windows could not queue the JAWS update-file replacement for reboot (Win32 error {0}): {1}' -f $nativeError,[IO.Path]::GetFileName($DestinationPath))
    }
    $global:CLAGNOS_PACKAGE_REBOOT_REQUIRED = $true
}

function Install-ClagnosJawsAppStateUpdateFiles {
    $archivePath = 'C:\Windows\Temp\clagnos-jaws-app-state.zip'
    $targetRoot = 'C:\Program Files\Freedom Scientific\JAWS\2025'
    if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) { throw ('JAWS update app-state archive is missing: ' + $archivePath) }
    if (-not (Test-Path -LiteralPath (Join-Path $targetRoot 'jfw.exe') -PathType Leaf)) { throw ('The required JAWS 2025 install directory was not found: ' + $targetRoot) }
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
    $archive = [IO.Compression.ZipFile]::OpenRead($archivePath)
    try {
        $prefix = 'payload/update-files/'
        $entries = @($archive.Entries | Where-Object { ([string]$_.FullName).StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -and -not ([string]$_.FullName).EndsWith('/') })
        if ($entries.Count -eq 0) { throw 'JAWS app-state archive has no payload/update-files entries.' }
        $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        $updatesToApply = @()
        $expectedFiles = New-Object 'System.Collections.Generic.List[object]'
        $deferredFiles = New-Object 'System.Collections.Generic.List[string]'
        foreach ($entry in @($entries)) {
            $relative = ([string]$entry.FullName).Substring($prefix.Length)
            if ([string]::IsNullOrWhiteSpace($relative) -or $relative -match '[/\\]' -or $relative -match '(^|\.)\.($|\.)' -or [IO.Path]::IsPathRooted($relative)) { throw ('Unsafe JAWS update-file path: ' + [string]$entry.FullName) }
            $destination = [IO.Path]::GetFullPath((Join-Path $targetRoot $relative))
            if (-not $destination.StartsWith($targetRoot.TrimEnd('\') + '\',[StringComparison]::OrdinalIgnoreCase) -or -not $seen.Add($destination)) { throw ('Invalid or duplicate JAWS update-file destination: ' + $relative) }
            $input = $entry.Open()
            try {
                $sha256 = [Security.Cryptography.SHA256]::Create()
                try { $expectedHash = ([BitConverter]::ToString($sha256.ComputeHash($input))).Replace('-','') }
                finally { $sha256.Dispose() }
            }
            finally { $input.Dispose() }
            $expectedFiles.Add([pscustomobject]@{ Relative = [string]$relative; Path = [string]$destination; Sha256 = [string]$expectedHash }) | Out-Null
            if (Test-Path -LiteralPath $destination -PathType Leaf) {
                $currentHash = [string](Get-FileHash -LiteralPath $destination -Algorithm SHA256 -ErrorAction Stop).Hash
                if ([string]::Equals($currentHash,$expectedHash,[StringComparison]::OrdinalIgnoreCase)) {
                    Write-Output ('JAWS update file already matches the app-state payload and is verified: ' + $destination)
                    continue
                }
            }
            $updatesToApply += [pscustomobject]@{ Entry = $entry; Relative = $relative; Destination = $destination; ExpectedHash = $expectedHash }
        }

        if ($updatesToApply.Count -eq 0) {
            Save-ClagnosJawsUpdateFilesState -Files @($expectedFiles.ToArray()) -DeferredUntilReboot:$false
            Write-Output 'All JAWS update-files already match the app-state payload; no program file replacement was needed.'
            return
        }

        Write-Output 'Doing: close JAWS before replacing changed package update files'
        foreach ($process in @(Get-Process -Name jfw -ErrorAction SilentlyContinue)) { Stop-Process -Id $process.Id -Force -ErrorAction Stop }
        $deadline = [DateTime]::UtcNow.AddSeconds(30)
        $nextProcessHeartbeat = 10
        while (@(Get-Process -Name jfw -ErrorAction SilentlyContinue).Count -gt 0 -and [DateTime]::UtcNow -lt $deadline) {
            $elapsed = [int](30 - [Math]::Ceiling(($deadline - [DateTime]::UtcNow).TotalSeconds))
            if ($elapsed -ge $nextProcessHeartbeat) { Write-Output ("Doing: waiting for jfw.exe to close ({0}s elapsed)" -f $elapsed); $nextProcessHeartbeat += 10 }
            Start-Sleep -Seconds 1
        }
        if (@(Get-Process -Name jfw -ErrorAction SilentlyContinue).Count -gt 0) { throw 'jfw.exe is still running; JAWS update files were not copied.' }

        foreach ($update in @($updatesToApply)) {
            $entry = $update.Entry
            $relative = [string]$update.Relative
            $destination = [string]$update.Destination
            $input = $entry.Open()
            try {
                $output = $null
                $fileWait = [Diagnostics.Stopwatch]::StartNew()
                $nextFileHeartbeat = 10
                while ($null -eq $output) {
                    try { $output = [IO.File]::Open($destination,[IO.FileMode]::Create,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite) }
                    catch [IO.IOException] {
                        $nativeCode = [int]$_.Exception.HResult -band 0xffff
                        if ($nativeCode -notin @(32,33)) { throw }
                        if ($fileWait.Elapsed.TotalSeconds -ge 15) {
                            $stagedPath = $destination + '.clagnos-' + [Guid]::NewGuid().ToString('N') + '.pending'
                            $stagedOutput = [IO.File]::Open($stagedPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
                            try {
                                $input.CopyTo($stagedOutput)
                                if ($stagedOutput.Length -ne $entry.Length) { throw ('Staged JAWS update-file length verification failed: ' + $relative) }
                            }
                            finally { $stagedOutput.Dispose() }
                            Queue-ClagnosJawsUpdateFileReplacementForReboot -StagedPath $stagedPath -DestinationPath $destination -ExpectedHash ([string]$update.ExpectedHash)
                            $deferredFiles.Add($relative) | Out-Null
                            Write-Output ('Doing: JAWS update file {0} is held by another process; its verified replacement is queued before next startup.' -f $relative)
                            break
                        }
                        if ($fileWait.Elapsed.TotalSeconds -ge $nextFileHeartbeat) {
                            Write-Output ("Doing: waiting for JAWS update file lock to clear ({0}s elapsed)" -f [int]$fileWait.Elapsed.TotalSeconds)
                            $nextFileHeartbeat += 10
                        }
                        Start-Sleep -Seconds 1
                    }
                }
                $fileWait.Stop()
                if ($null -eq $output) { continue }
                try { $input.CopyTo($output); if ($output.Length -ne $entry.Length) { throw ('JAWS update-file verification failed: ' + $relative) } }
                finally { $output.Dispose() }
                $writtenHash = [string](Get-FileHash -LiteralPath $destination -Algorithm SHA256 -ErrorAction Stop).Hash
                if (-not [string]::Equals($writtenHash,[string]$update.ExpectedHash,[StringComparison]::OrdinalIgnoreCase)) { throw ('JAWS update-file SHA256 verification failed: ' + $relative) }
            }
            finally { $input.Dispose() }
            Write-Output ('JAWS update file copied and verified: ' + $destination)
        }
        Save-ClagnosJawsUpdateFilesState -Files @($expectedFiles.ToArray()) -DeferredUntilReboot:($deferredFiles.Count -gt 0)
        if ($deferredFiles.Count -gt 0) {
            $global:CLAGNOS_PACKAGE_REBOOT_REQUIRED = $true
            Write-Output ('Doing: JAWS update-files scheduled for the next reboot: ' + ($deferredFiles -join ', '))
        }
    }
    finally { $archive.Dispose() }
}

function Invoke-ClagnosPackageLifecycle {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('status','install','repair','update','uninstall')][string]$Action,
        [Parameter(Mandatory = $true)][string]$PackageSpecBase64,
        [string]$InstallScriptBase64 = ''
    )

    $specJson = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($PackageSpecBase64))
    $spec = ConvertFrom-Json -InputObject $specJson
    $global:CLAGNOS_PACKAGE_REBOOT_REQUIRED = $false
    $operationWatch = [Diagnostics.Stopwatch]::StartNew()
    $global:CLAGNOS_PACKAGE_LIFECYCLE_STOPWATCH = $operationWatch
    Set-ClagnosPackageLifecyclePhase -Phase 'preflight-status'
    [void](Initialize-ClagnosWingetCommandPath)
    $record = Get-ClagnosPackageRecord -Spec $spec
    if ($Action -eq 'status') {
        Set-ClagnosPackageLifecyclePhase -Phase 'status-result'
        $message = if ($record.Status -eq 'installed') { 'Package is installed and detectable.' } elseif ($record.Status -eq 'installed-drifted') { 'Package files are present, but a health drift was detected; use repair to reconcile it.' } elseif ($record.Status -eq 'not-installed') { 'Package is not installed.' } else { 'Package status could not be determined safely.' }
        if (-not [string]::IsNullOrWhiteSpace([string]$record.Detail)) { $message += ' ' + [string]$record.Detail }
        Write-ClagnosPackageOperationResult -Spec $spec -Action $Action -Record $record -Message $message -DurationSeconds $operationWatch.Elapsed.TotalSeconds
        return
    }

    if ($Action -eq 'uninstall') {
        if ($record.Status -eq 'not-installed') {
            Remove-ClagnosPackageStartupArtifacts -Spec $spec
            if ([string]$spec.id -eq 'jaws') {
                Write-Output 'Doing: clean only residual JAWS 2025 program, shared, profile, and temporary data after package absence was confirmed'
                Clear-ClagnosJawsOwnedData -Spec $spec -ClearSharedComponents
            }
            $uninstallMessage = if ([string]$spec.id -eq 'windscribe' -and [string]$env:CLAGNOS_WINDSCRIBE_UNINSTALL_COMPLETED -eq 'true') { 'Windscribe was removed through the verified password-logon scheduled task; absence was confirmed.' } elseif ([string]$spec.id -eq 'jaws') { 'JAWS was already absent; remaining JAWS 2025 data was cleaned and verified.' } else { 'Package was already absent; no uninstall action was run.' }
            Write-ClagnosPackageOperationResult -Spec $spec -Action $Action -Record $record -Message $uninstallMessage
            return
        }
        if ($record.Status -notin @('installed','installed-drifted')) { throw ('Cannot safely uninstall {0}: current package status is {1}.' -f [string]$spec.displayName,$record.Status) }
        Set-ClagnosPackageLifecyclePhase -Phase 'vendor-uninstall'
        $uninstall = $spec.uninstall
        $value = [string]$uninstall.value
        $packageUninstallRebootRequired = $false
        Write-Output ('Doing: uninstall package {0} using {1}' -f [string]$spec.id,[string]$uninstall.kind)
        switch ([string]$uninstall.kind) {
            'jaws' {
                $global:CLAGNOS_JAWS_VENDOR_UNINSTALL_RESULT = $null
                Invoke-ClagnosJawsVendorUninstall -Spec $spec -CleanSharedComponents
                $jawsRemoval = $global:CLAGNOS_JAWS_VENDOR_UNINSTALL_RESULT
                if ($null -eq $jawsRemoval) { throw 'JAWS vendor uninstall completed without a structured cleanup result.' }
                $packageUninstallRebootRequired = [bool]$global:CLAGNOS_PACKAGE_REBOOT_REQUIRED
                $uninstallOutput = ('Freedom Scientific signed {0} completed; JAWS 2025, its language registrations, and selected profile data were removed.' -f [string]$jawsRemoval.SetupType)
            }
            'winget' {
                $command = Get-Command winget.exe -ErrorAction Stop
                $uninstallArguments = @('uninstall','--id',$value,'--exact','--silent','--accept-source-agreements','--disable-interactivity')
                if ($null -ne $uninstall.PSObject.Properties['allVersions'] -and [bool]$uninstall.allVersions) { $uninstallArguments += '--all-versions' }
                & $command.Source @uninstallArguments
                if ([int]$LASTEXITCODE -ne 0) { throw ('winget uninstall exited with ' + [int]$LASTEXITCODE) }
            }
            'choco' {
                $command = Get-Command choco.exe -ErrorAction Stop
                $chocoUninstallArguments = @('uninstall',$value)
                if ($null -ne $uninstall.PSObject.Properties['removeDependencies'] -and [bool]$uninstall.removeDependencies) { $chocoUninstallArguments += '--remove-dependencies' }
                $chocoUninstallArguments += @('-y','--no-progress')
                $uninstallOutput = & $command.Source @chocoUninstallArguments 2>&1 | Out-String
                $chocoUninstallExitCode = [int]$LASTEXITCODE
                if ($chocoUninstallExitCode -eq 3010) {
                    $packageUninstallRebootRequired = $true
                    Write-Output 'Doing: Chocolatey uninstall requested a reboot; continuing with bounded package absence verification.'
                }
                elseif ($chocoUninstallExitCode -ne 0) { throw ('Chocolatey uninstall exited with ' + $chocoUninstallExitCode + '. ' + $uninstallOutput.Trim()) }
                if ([string]$spec.id -eq 'git' -and $null -ne $uninstall.PSObject.Properties['removeDependencies'] -and [bool]$uninstall.removeDependencies) {
                    $gitInstallOutput = & $command.Source list --local-only --exact --limit-output git.install 2>&1 | Out-String
                    if ([int]$LASTEXITCODE -ne 0) { throw ('Chocolatey could not verify git.install absence after uninstall; list exited with ' + [int]$LASTEXITCODE + '.') }
                    if ($gitInstallOutput -match '(?im)^git\.install\|') { throw 'Git meta-package was removed but git.install remained present.' }
                }
            }
            'npm' { $command = Get-Command npm.cmd -ErrorAction SilentlyContinue; if (-not $command) { $command = Get-Command npm -ErrorAction Stop }; & $command.Source uninstall --global $value; if ([int]$LASTEXITCODE -ne 0) { throw ('npm uninstall exited with ' + [int]$LASTEXITCODE) } }
            'anydesk' {
                if (Test-Path -LiteralPath $value -PathType Leaf) {
                    Write-Output 'Doing: uninstall AnyDesk with its vendor-supported silent remove command'
                    $removeOutput = & $value --remove --silent 2>&1 | Out-String
                    if ([int]$LASTEXITCODE -ne 0) { throw ('AnyDesk silent uninstall exited with ' + [int]$LASTEXITCODE + '. ' + $removeOutput.Trim()) }
                }
            }
            'docker-desktop' {
                if ([string]$spec.id -ne 'docker-desktop' -or $value -ne 'Docker.DockerDesktop') { throw 'The docker-desktop uninstall action is reserved for the builtin Docker Desktop package.' }
                $dockerInstallerCandidates = @(
                    (Join-Path (Join-Path $env:ProgramFiles 'Docker\Docker') 'Docker Desktop Installer.exe'),
                    (Join-Path (Join-Path $env:LOCALAPPDATA 'Programs\DockerDesktop') 'Docker Desktop Installer.exe')
                )
                $dockerInstallerPath = [string](@($dockerInstallerCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1))
                if ([string]::IsNullOrWhiteSpace($dockerInstallerPath)) { throw 'Docker Desktop is registered but its supported vendor CLI uninstaller could not be found in either documented installation mode.' }
                $dockerInstallerSignature = Get-AuthenticodeSignature -LiteralPath $dockerInstallerPath -ErrorAction Stop
                if ([string]$dockerInstallerSignature.Status -ne 'Valid' -or $null -eq $dockerInstallerSignature.SignerCertificate -or [string]$dockerInstallerSignature.SignerCertificate.Subject -notmatch '(?i)Docker') { throw 'Docker Desktop vendor uninstaller did not pass Docker Authenticode verification; uninstall was not started.' }
                Write-Output 'Doing: uninstall Docker Desktop through its signed vendor installer CLI (uninstall --quiet)'
                $dockerUninstallStartedAt = [DateTime]::UtcNow
                $dockerUninstaller = Start-Process -FilePath $dockerInstallerPath -ArgumentList @('uninstall','--quiet') -WorkingDirectory (Split-Path -Parent $dockerInstallerPath) -WindowStyle Hidden -PassThru -ErrorAction Stop
                $dockerUninstallDeadline = $dockerUninstallStartedAt.AddSeconds(360)
                $dockerNextHeartbeat = $dockerUninstallStartedAt.AddSeconds(15)
                while (-not $dockerUninstaller.HasExited) {
                    if ([DateTime]::UtcNow -ge $dockerUninstallDeadline) {
                        Stop-Process -Id ([int]$dockerUninstaller.Id) -Force -ErrorAction SilentlyContinue
                        throw 'Docker Desktop vendor uninstaller exceeded its finite 360-second deadline.'
                    }
                    if ([DateTime]::UtcNow -ge $dockerNextHeartbeat) {
                        Write-Output ('Doing: Docker Desktop vendor uninstall is still running ({0}s elapsed)' -f [int]([DateTime]::UtcNow - $dockerUninstallStartedAt).TotalSeconds)
                        $dockerNextHeartbeat = [DateTime]::UtcNow.AddSeconds(15)
                    }
                    Start-Sleep -Milliseconds 500
                }
                $dockerUninstaller.WaitForExit()
                if ([int]$dockerUninstaller.ExitCode -notin @(0,3010)) { throw ('Docker Desktop vendor uninstaller exited with code ' + [int]$dockerUninstaller.ExitCode) }
                if ([int]$dockerUninstaller.ExitCode -eq 3010) {
                    $packageUninstallRebootRequired = $true
                    Write-Output 'Doing: Docker Desktop uninstall requested a reboot; continuing with bounded package absence verification.'
                }
                $uninstallOutput = 'Docker Desktop vendor installer uninstall command completed.'
            }
            'google-drive' {
                if ([string]$spec.id -ne 'google-drive' -or [string]$uninstall.value -ne '{6BBAE539-2232-434A-A4E5-9A33560C6283}' -or [string]$spec.statusCheck.kind -ne 'winget') { throw 'The google-drive uninstall action is reserved for the builtin Google Drive package.' }
                $googleDriveRegistryPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\' + [string]$uninstall.value
                $googleDriveRegistry = if (Test-Path -LiteralPath $googleDriveRegistryPath) { Get-ItemProperty -LiteralPath $googleDriveRegistryPath -ErrorAction Stop } else { $null }
                if ($null -eq $googleDriveRegistry -or [string]$googleDriveRegistry.DisplayName -ne 'Google Drive' -or -not (Test-ClagnosPackageVersionEquivalent -Expected ([string]$record.Version) -Observed ([string]$googleDriveRegistry.DisplayVersion))) { throw 'Google Drive publisher registration and observed package version did not match; uninstall stopped before mutation.' }
                $googleDriveExe = [string]$googleDriveRegistry.InstallLocation
                if ([string]::IsNullOrWhiteSpace($googleDriveExe) -or -not (Test-Path -LiteralPath $googleDriveExe -PathType Leaf)) { throw 'Google Drive registered executable is missing; vendor uninstall was not started.' }
                $googleDriveRoot = Split-Path -Parent $googleDriveExe
                $googleDriveUninstaller = Join-Path $googleDriveRoot 'uninstall.exe'
                if (-not (Test-Path -LiteralPath $googleDriveUninstaller -PathType Leaf)) { throw 'Google Drive versioned vendor uninstaller is missing; package removal was not attempted.' }
                $googleDriveSignature = Get-AuthenticodeSignature -LiteralPath $googleDriveUninstaller -ErrorAction Stop
                if ([string]$googleDriveSignature.Status -ne 'Valid' -or $null -eq $googleDriveSignature.SignerCertificate -or [string]$googleDriveSignature.SignerCertificate.Subject -notmatch '(?i)(?:^|,\s*)CN=Google LLC(?:,|$)') { throw 'Google Drive vendor uninstaller did not pass Google LLC Authenticode verification; package removal was not attempted.' }
                $googleDriveUninstallerItem = Get-Item -LiteralPath $googleDriveUninstaller -ErrorAction Stop
                if (-not (Test-ClagnosPackageVersionEquivalent -Expected ([string]$record.Version) -Observed ([string]$googleDriveUninstallerItem.VersionInfo.ProductVersion))) { throw 'Google Drive vendor uninstaller version did not match the installed package version; package removal was not attempted.' }
                $googleDriveWingetUninstallers = @(Get-CimInstance Win32_Process -Filter "Name='winget.exe'" -ErrorAction SilentlyContinue | Where-Object { [string]$_.CommandLine -match '(?i)winget(?:\.exe)?\s+uninstall.*(?:Google\.GoogleDrive|Google Drive)' })
                foreach ($staleGoogleDriveWinget in @($googleDriveWingetUninstallers)) {
                    $staleStartedAtUtc = [DateTime]::MinValue
                    try { $staleStartedAtUtc = [System.Management.ManagementDateTimeConverter]::ToDateTime([string]$staleGoogleDriveWinget.CreationDate).ToUniversalTime() } catch { }
                    if ($staleStartedAtUtc -eq [DateTime]::MinValue -or ([DateTime]::UtcNow - $staleStartedAtUtc).TotalSeconds -lt 180) { continue }
                    $staleGoogleDriveChildren = @(Get-CimInstance Win32_Process -Filter ("ParentProcessId={0}" -f [int]$staleGoogleDriveWinget.ProcessId) -ErrorAction SilentlyContinue | Where-Object { [string]::Equals([string]$_.ExecutablePath,[string]$googleDriveUninstaller,[StringComparison]::OrdinalIgnoreCase) })
                    foreach ($staleGoogleDriveChild in @($staleGoogleDriveChildren)) {
                        Write-Output ('Doing: stop stale Google Drive vendor uninstall process {0} left by timed-out WinGet uninstall' -f [int]$staleGoogleDriveChild.ProcessId)
                        Stop-Process -Id ([int]$staleGoogleDriveChild.ProcessId) -Force -ErrorAction SilentlyContinue
                    }
                    Write-Output ('Doing: stop stale WinGet Google Drive uninstall process {0} left by a prior bounded timeout' -f [int]$staleGoogleDriveWinget.ProcessId)
                    Stop-Process -Id ([int]$staleGoogleDriveWinget.ProcessId) -Force -ErrorAction SilentlyContinue
                }
                Write-Output ('Doing: run Google Drive {0} vendor uninstaller with --silent --force_stop' -f [string]$record.Version)
                $googleDriveUninstallStartedAt = [DateTime]::UtcNow
                $googleDriveUninstallProcess = Start-Process -FilePath $googleDriveUninstaller -ArgumentList @('--silent','--force_stop') -WorkingDirectory $googleDriveRoot -WindowStyle Hidden -PassThru -ErrorAction Stop
                $googleDriveUninstallDeadline = $googleDriveUninstallStartedAt.AddSeconds(140)
                $googleDriveNextHeartbeat = $googleDriveUninstallStartedAt.AddSeconds(15)
                while (-not $googleDriveUninstallProcess.HasExited) {
                    if ([DateTime]::UtcNow -ge $googleDriveUninstallDeadline) {
                        Stop-Process -Id ([int]$googleDriveUninstallProcess.Id) -Force -ErrorAction SilentlyContinue
                        throw 'Google Drive vendor uninstaller exceeded its finite 140-second deadline.'
                    }
                    if ([DateTime]::UtcNow -ge $googleDriveNextHeartbeat) {
                        Write-Output ('Doing: Google Drive silent uninstall is still running ({0}s elapsed)' -f [int]([DateTime]::UtcNow - $googleDriveUninstallStartedAt).TotalSeconds)
                        $googleDriveNextHeartbeat = [DateTime]::UtcNow.AddSeconds(15)
                    }
                    Start-Sleep -Milliseconds 500
                }
                $googleDriveUninstallProcess.WaitForExit()
                if ([int]$googleDriveUninstallProcess.ExitCode -notin @(0,3010)) { throw ('Google Drive vendor uninstaller exited with code ' + [int]$googleDriveUninstallProcess.ExitCode) }
                if ([int]$googleDriveUninstallProcess.ExitCode -eq 3010) {
                    $packageUninstallRebootRequired = $true
                    Write-Output 'Doing: Google Drive uninstall requested a reboot; continuing with bounded package absence verification.'
                }
                $googleDriveAbsenceDeadline = [DateTime]::UtcNow.AddSeconds(25)
                do {
                    $googleDriveRegistryPresent = Test-Path -LiteralPath $googleDriveRegistryPath
                    $googleDriveExecutablePresent = Test-Path -LiteralPath $googleDriveExe -PathType Leaf
                    if (-not $googleDriveRegistryPresent -and -not $googleDriveExecutablePresent) { break }
                    if ([DateTime]::UtcNow -ge $googleDriveAbsenceDeadline) { throw ('Google Drive uninstaller exited successfully but package absence was not verified; registry={0}; executable={1}.' -f $googleDriveRegistryPresent,$googleDriveExecutablePresent) }
                    Start-Sleep -Seconds 2
                } while ($true)
                $uninstallOutput = 'Google Drive vendor uninstall.exe completed silently with --force_stop; package registry and executable are absent.'
            }
            'nvda' {
                if ([string]$spec.id -ne 'nvda' -or $value -ne 'C:\Program Files\NVDA\uninstall.exe') { throw 'The nvda uninstall action is reserved for the builtin NVDA package and its fixed vendor uninstaller path.' }
                if (-not (Test-Path -LiteralPath $value -PathType Leaf)) { throw 'The signed NVDA vendor uninstaller is missing; package removal was not attempted.' }
                $nvdaSignature = Get-AuthenticodeSignature -FilePath $value -ErrorAction Stop
                if ([string]$nvdaSignature.Status -ne 'Valid') { throw ('NVDA vendor uninstaller signature verification failed (status: {0}); package removal was not attempted.' -f [string]$nvdaSignature.Status) }
                $nvdaInstallRoot = [IO.Path]::GetFullPath('C:\Program Files\NVDA').TrimEnd('\') + '\'
                $nvdaProcesses = @(Get-CimInstance Win32_Process -Filter "Name='nvda.exe' OR Name='nvda_noUIAccess.exe'" -ErrorAction Stop | Where-Object {
                    -not [string]::IsNullOrWhiteSpace([string]$_.ExecutablePath) -and
                    [string]$_.ExecutablePath.StartsWith($nvdaInstallRoot,[StringComparison]::OrdinalIgnoreCase)
                })
                foreach ($nvdaProcess in @($nvdaProcesses)) {
                    Write-Output ('Doing: close NVDA process {0} in the fixed package directory before uninstall' -f [int]$nvdaProcess.ProcessId)
                    Stop-Process -Id ([int]$nvdaProcess.ProcessId) -Force -ErrorAction Stop
                }
                $processDeadline = [DateTime]::UtcNow.AddSeconds(10)
                do {
                    $remainingNvdaProcesses = @(Get-CimInstance Win32_Process -Filter "Name='nvda.exe' OR Name='nvda_noUIAccess.exe'" -ErrorAction SilentlyContinue | Where-Object {
                        -not [string]::IsNullOrWhiteSpace([string]$_.ExecutablePath) -and
                        [string]$_.ExecutablePath.StartsWith($nvdaInstallRoot,[StringComparison]::OrdinalIgnoreCase)
                    })
                    if ($remainingNvdaProcesses.Count -eq 0) { break }
                    if ([DateTime]::UtcNow -ge $processDeadline) { throw 'NVDA processes remained active after the bounded close attempt; uninstall was not started.' }
                    Start-Sleep -Milliseconds 500
                } while ($true)
                Write-Output 'Doing: run the signed NVDA vendor uninstaller with its documented unattended /S option'
                $nvdaUninstallStartedAt = [DateTime]::UtcNow
                $nvdaUninstaller = Start-Process -FilePath $value -ArgumentList @('/S') -WorkingDirectory (Split-Path -Parent $value) -WindowStyle Hidden -PassThru -ErrorAction Stop
                $nvdaDeadline = $nvdaUninstallStartedAt.AddSeconds(90)
                $nextNvdaHeartbeat = $nvdaUninstallStartedAt.AddSeconds(15)
                while (-not $nvdaUninstaller.HasExited) {
                    if ([DateTime]::UtcNow -ge $nvdaDeadline) {
                        Stop-Process -Id ([int]$nvdaUninstaller.Id) -Force -ErrorAction SilentlyContinue
                        throw 'NVDA vendor uninstaller exceeded its finite 90-second deadline.'
                    }
                    if ([DateTime]::UtcNow -ge $nextNvdaHeartbeat) {
                        Write-Output ('Doing: NVDA vendor uninstall is still running ({0}s elapsed)' -f [int]([DateTime]::UtcNow - $nvdaUninstallStartedAt).TotalSeconds)
                        $nextNvdaHeartbeat = [DateTime]::UtcNow.AddSeconds(15)
                    }
                    Start-Sleep -Milliseconds 500
                }
                $nvdaUninstaller.WaitForExit()
                if ([int]$nvdaUninstaller.ExitCode -ne 0) { throw ('NVDA vendor uninstaller exited with code ' + [int]$nvdaUninstaller.ExitCode) }
                $absenceDeadline = [DateTime]::UtcNow.AddSeconds(20)
                do {
                    $nvdaRegistryKey = Test-Path -LiteralPath 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\NVDA'
                    $nvdaExecutablePresent = Test-Path -LiteralPath 'C:\Program Files\NVDA\nvda.exe' -PathType Leaf
                    if (-not $nvdaRegistryKey -and -not $nvdaExecutablePresent) { break }
                    if ([DateTime]::UtcNow -ge $absenceDeadline) { throw ('NVDA uninstaller exited successfully but its application or uninstall registry entry remained; exe={0}; registry={1}.' -f $nvdaExecutablePresent,$nvdaRegistryKey) }
                    Start-Sleep -Seconds 2
                } while ($true)
                $uninstallOutput = 'The signed NVDA vendor uninstaller completed; application files and uninstall registry entry are absent.'
            }
            'windscribe' {
                if ([string]$spec.id -ne 'windscribe' -or $value -ne 'C:\Program Files\Windscribe\uninstall.exe') { throw 'The windscribe uninstall action is reserved for the builtin Windscribe package and its fixed signed vendor uninstaller path.' }
                if ([string]$env:CLAGNOS_WINDSCRIBE_UNINSTALL_COMPLETED -ne 'true') { throw 'Windscribe removal must complete through the bounded signed two-phase uninstaller before absence can be verified.' }
                $uninstallOutput = 'The signed unattended two-phase vendor uninstaller completed; verifying the application and service are absent.'
            }
            'teams' { Invoke-ClagnosTeamsBootstrapper -Action uninstall -TimeoutSeconds 120 }
            'wsl' {
                if ([string]$spec.id -ne 'windows-subsystem-linux' -or $value -ne 'Windows Subsystem for Linux') { throw 'The wsl uninstall action is reserved for the builtin Windows Subsystem for Linux package.' }
                $wslRecord = Get-ClagnosWslPackageRecord -DisplayName $value
                if ([string]$wslRecord.Status -notin @('installed','installed-drifted')) { throw ('WSL is not registered as an installed MSI package (status: {0}); no removal was attempted.' -f [string]$wslRecord.Status) }
                $wslExe = 'C:\Program Files\WSL\wsl.exe'
                if (-not (Test-Path -LiteralPath $wslExe -PathType Leaf)) { throw 'The managed WSL executable is missing; package removal was not attempted.' }
                Write-Output 'Doing: inspect managed-user WSL distribution registrations before uninstall to protect user data'
                $registeredDistributions = @(Get-ClagnosWslDistributionRegistrations)
                if ($registeredDistributions.Count -gt 0) {
                    $distributionLabels = @($registeredDistributions | ForEach-Object { '{0}:{1}' -f [string]$_.UserSid,[string]$_.Name }) -join ', '
                    throw ('WSL has registered distributions; uninstall was refused to protect their data: ' + $distributionLabels)
                }
                $productCode = ''
                if ([string]$wslRecord.UninstallString -match '(?i)/X\s*\{(?<product>[0-9A-F-]{36})\}') { $productCode = '{' + [string]$Matches.product + '}' }
                elseif ([string]$wslRecord.ProductCode -match '^\{[0-9A-F-]{36}\}$') { $productCode = [string]$wslRecord.ProductCode }
                if ([string]::IsNullOrWhiteSpace($productCode)) { throw 'WSL MSI product code could not be resolved from its uninstall registration; no removal was attempted.' }
                $msiexec = Join-Path $env:SystemRoot 'System32\msiexec.exe'
                if (-not (Test-Path -LiteralPath $msiexec -PathType Leaf)) { throw 'Windows Installer executable could not be resolved; WSL MSI removal was not attempted.' }
                Write-Output ('Doing: remove WSL MSI product {0} without touching distributions or Windows optional features' -f $productCode)
                $msiOutput = & $msiexec /x $productCode /qn /norestart 2>&1 | Out-String
                $msiExitCode = [int]$LASTEXITCODE
                if ($msiExitCode -notin @(0,3010)) { throw ('WSL MSI uninstall exited with code ' + $msiExitCode + '. ' + $msiOutput.Trim()) }
                if ($msiExitCode -eq 3010) { Write-Output 'WSL MSI uninstall requested a reboot to finish servicing.' }
                $absenceDeadline = [DateTime]::UtcNow.AddSeconds(30)
                do {
                    $remainingWsl = Get-ClagnosWslPackageRecord -DisplayName $value
                    if ([string]$remainingWsl.Status -eq 'not-installed') { break }
                    if ([DateTime]::UtcNow -ge $absenceDeadline) { throw ('WSL MSI uninstall completed but registration status remained {0}.' -f [string]$remainingWsl.Status) }
                    Start-Sleep -Seconds 2
                } while ($true)
                $uninstallOutput = 'WSL MSI package was removed; no registered distributions or Windows optional features were changed.'
            }
            'appx' { $matches = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { $_.Name -like ('*' + $value + '*') -or $_.PackageFamilyName -like ('*' + $value + '*') -or $_.PackageFullName -like ('*' + $value + '*') }); foreach ($app in $matches) { Remove-AppxPackage -Package $app.PackageFullName -AllUsers -ErrorAction Stop } }
            'windows-feature' { Disable-WindowsOptionalFeature -Online -FeatureName $value -NoRestart -ErrorAction Stop | Out-Null }
            'choco-self' {
                $chocolateyRoot = Get-ClagnosChocolateyRoot
                $managerFiles = @(
                    (Join-Path $chocolateyRoot 'bin\choco.exe'),
                    (Join-Path $chocolateyRoot 'bin\choco.exe.config'),
                    (Join-Path $chocolateyRoot 'lib\chocolatey')
                )
                foreach ($managerPath in $managerFiles) {
                    if (Test-Path -LiteralPath $managerPath -PathType Container) { Remove-Item -LiteralPath $managerPath -Recurse -Force -ErrorAction Stop }
                    elseif (Test-Path -LiteralPath $managerPath -PathType Leaf) { Remove-Item -LiteralPath $managerPath -Force -ErrorAction Stop }
                }
                Write-Output 'Chocolatey CLI manager files removed; other packages and the shared lib/bin directories were retained.'
            }
            'sysinternals' { Remove-ClagnosSysinternalsPackage -Spec $spec }
            default { throw ('Unsupported allow-listed uninstall kind: ' + [string]$uninstall.kind) }
        }
        if ([string]$spec.statusCheck.kind -eq 'store-state') {
            $stateName = [regex]::Replace([string]$spec.statusCheck.value,'[^A-Za-z0-9._-]','_')
            $statePath = Join-Path (Join-Path $env:ProgramData 'clagnos\state\store-installs') ($stateName + '.json')
            if (Test-Path -LiteralPath $statePath) { Remove-Item -LiteralPath $statePath -Force -ErrorAction Stop }
        }
        Remove-ClagnosPackageStartupArtifacts -Spec $spec
        Set-ClagnosPackageLifecyclePhase -Phase 'uninstall-verification'
        $verified = Get-ClagnosPackageRecord -Spec $spec
        if ($verified.Status -ne 'not-installed') { throw ('Uninstall did not verify; package status after removal is {0}.' -f $verified.Status) }
        Set-ClagnosPackageLifecyclePhase -Phase 'complete'
        $uninstallMessage = 'Package uninstall completed and absence verified.'
        if ($packageUninstallRebootRequired) { $uninstallMessage += ' The package vendor requested a reboot (exit code 3010); the VM was left running.' }
        Write-ClagnosPackageOperationResult -Spec $spec -Action $Action -Record $verified -Message $uninstallMessage -DurationSeconds $operationWatch.Elapsed.TotalSeconds -RebootRequired:$packageUninstallRebootRequired
        return
    }

    if ($Action -eq 'install') {
        if ($record.Status -in @('installed','installed-drifted')) {
            $installMessage = if ($record.Status -eq 'installed-drifted') { 'Package is present but health drift was detected; install is a no-op. Use repair to reconcile it.' } else { 'Package is already installed; no install was run.' }
            Write-ClagnosPackageOperationResult -Spec $spec -Action $Action -Record $record -Message $installMessage
            return
        }
        if ($record.Status -ne 'not-installed') { throw ('Cannot safely install {0}: current package status is {1}.' -f [string]$spec.displayName,$record.Status) }
        if ([string]::IsNullOrWhiteSpace($InstallScriptBase64)) { throw ('Package {0} has no validated installer script.' -f [string]$spec.id) }
        $installSource = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($InstallScriptBase64))
        Set-ClagnosPackageLifecyclePhase -Phase 'installer'
        Write-Output ('Doing: install package {0} using its package installer' -f [string]$spec.id)
        if ([string]$spec.id -eq 'jaws') {
            $installOutput = Invoke-ClagnosPackageScriptStreamed -ScriptText $installSource
        }
        else {
            $installOutput = & ([scriptblock]::Create($installSource)) *>&1 | Out-String
            if (-not [string]::IsNullOrWhiteSpace($installOutput)) { Write-Output $installOutput.TrimEnd() }
        }
        Set-ClagnosPackageLifecyclePhase -Phase 'startup-reconciliation'
        if ([string]$spec.id -eq 'jaws') {
            $jawsUsers = @($spec.targetUsers | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
            if ($jawsUsers.Count -gt 0) { Set-ClagnosJawsPostLogonStartup -UserNames $jawsUsers -Executable 'C:\Program Files\Freedom Scientific\JAWS\2025\jfw.exe' }
        }
        else { Set-ClagnosPackageStartupState -Spec $spec }
        Set-ClagnosPackageLifecyclePhase -Phase 'install-verification'
        $verified = Get-ClagnosPackageRecord -Spec $spec
        $installRebootRequired = [bool]$global:CLAGNOS_PACKAGE_REBOOT_REQUIRED
        $pendingJawsUpdates = $installRebootRequired -and [string]$spec.id -eq 'jaws' -and [string]$verified.Detail -match '(?i)pending reboot'
        if ($pendingJawsUpdates -and [string]$verified.Status -eq 'installed-drifted') { $verified.Status = 'installed' }
        if ($verified.Status -ne 'installed') { throw ('Install script finished but package status verification returned {0}.' -f $verified.Status) }
        $message = 'Package installation completed and installed state verified.'
        if (-not [string]::IsNullOrWhiteSpace([string]$verified.Detail)) { $message += ' ' + [string]$verified.Detail }
        if ($installRebootRequired) { $message += ' JAWS update-file replacement is queued for the next reboot.' }
        Set-ClagnosPackageLifecyclePhase -Phase 'complete'
        Write-ClagnosPackageOperationResult -Spec $spec -Action $Action -Record $verified -Message $message -DurationSeconds $operationWatch.Elapsed.TotalSeconds -RebootRequired:$installRebootRequired
        return
    }

    if ($Action -eq 'repair') {
        if ($record.Status -notin @('installed','installed-drifted')) { throw ('Cannot repair {0}: current package status is {1}; use install for an absent package.' -f [string]$spec.displayName,$record.Status) }
        if ([string]::IsNullOrWhiteSpace([string]$record.Version)) { throw ('Cannot safely repair {0}: the installed version could not be determined, so a same-version reinstall cannot be guaranteed.' -f [string]$spec.displayName) }
        $repairStrategy = [string]$spec.repairStrategy
        if ([string]::IsNullOrWhiteSpace($repairStrategy)) { $repairStrategy = [string]$spec.updateStrategy }
        if ([string]::IsNullOrWhiteSpace($repairStrategy)) { $repairStrategy = [string]$spec.statusCheck.kind }
        $repairOutput = ''
        $repairNpmPolicyWarning = $false
        Set-ClagnosPackageLifecyclePhase -Phase 'same-version-repair'
        Write-Output ('Doing: repair package {0} at installed version {1} using {2}' -f [string]$spec.id,[string]$record.Version,$repairStrategy)
        switch ($repairStrategy) {
            'jaws' {
                if ([string]$spec.id -ne 'jaws' -or [string]$spec.statusCheck.value -ne 'FreedomScientific.JAWS.2025') { throw 'The jaws repair strategy is reserved for the builtin Freedom Scientific JAWS 2025 package.' }
                if ([string]::IsNullOrWhiteSpace([string]$record.Version)) { throw 'The installed JAWS version is unavailable; exact-version repair was not started.' }
                $command = Get-Command winget.exe -ErrorAction Stop
                Write-Output ('Doing: verify JAWS WinGet release {0} is still available before the same-version repair changes the guest' -f [string]$record.Version)
                $availabilityOutput = & $command.Source show --id ([string]$spec.statusCheck.value) --exact --version ([string]$record.Version) --accept-source-agreements --disable-interactivity 2>&1 | Out-String
                $availabilityCode = [int]$LASTEXITCODE
                if ($availabilityCode -ne 0 -or $availabilityOutput -notmatch ('(?im)^\s*Version:\s*' + [regex]::Escape([string]$record.Version) + '\s*$')) {
                    throw ("JAWS exact provider version '{0}' is not verifiable; no repair mutation was attempted. {1}" -f [string]$record.Version,$availabilityOutput.Trim())
                }
                if ([string]::IsNullOrWhiteSpace($InstallScriptBase64)) { throw 'JAWS same-version repair requires its validated ENU/offline package installer.' }
                $repairSource = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($InstallScriptBase64))
                $global:CLAGNOS_JAWS_VENDOR_UNINSTALL_RESULT = $null
                Invoke-ClagnosJawsVendorUninstall -Spec $spec -CleanSharedComponents -PreservePackageAssets
                if ($null -eq $global:CLAGNOS_JAWS_VENDOR_UNINSTALL_RESULT) { throw 'JAWS vendor cleanup completed without a structured same-version repair result.' }
                $previousRequiredVersion = [string]$env:CLAGNOS_JAWS_REQUIRED_VERSION
                $previousForceInstall = [string]$env:CLAGNOS_JAWS_FORCE_INSTALL
                try {
                    $env:CLAGNOS_JAWS_REQUIRED_VERSION = [string]$record.Version
                    $env:CLAGNOS_JAWS_FORCE_INSTALL = 'true'
                    $repairOutput = Invoke-ClagnosPackageScriptStreamed -ScriptText $repairSource
                    if ($null -ne $global:LASTEXITCODE -and [int]$global:LASTEXITCODE -notin @(0,-1978335189,-2147024894)) {
                        throw ('JAWS same-version install script exited with ' + [int]$global:LASTEXITCODE + '. ' + $repairOutput.Trim())
                    }
                }
                finally {
                    $env:CLAGNOS_JAWS_REQUIRED_VERSION = $previousRequiredVersion
                    $env:CLAGNOS_JAWS_FORCE_INSTALL = $previousForceInstall
                }
                if ([bool]$global:CLAGNOS_PACKAGE_REBOOT_REQUIRED) { $repairRebootRequired = $true }
            }
            'installer-verify' {
                if ([string]::IsNullOrWhiteSpace($InstallScriptBase64)) { throw ('Package {0} same-version repair requires its validated installer/health script.' -f [string]$spec.id) }
                $repairSource = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($InstallScriptBase64))
                $repairOutput = & ([scriptblock]::Create($repairSource)) *>&1 | Out-String
                if ($null -ne $global:LASTEXITCODE -and [int]$global:LASTEXITCODE -ne 0) { throw ('Same-version repair health script exited with ' + [int]$global:LASTEXITCODE + '. ' + $repairOutput.Trim()) }
            }
            'startup' {
                $repairOutput = (Set-ClagnosPackageStartupState -Spec $spec | Out-String).Trim()
            }
            'winget' {
                $command = Get-Command winget.exe -ErrorAction Stop
                $repairId = if (-not [string]::IsNullOrWhiteSpace([string]$spec.repairPackageId)) { [string]$spec.repairPackageId } else { [string]$spec.statusCheck.value }
                $repairOutput = & $command.Source install --id $repairId --exact --version ([string]$record.Version) --force --silent --accept-source-agreements --accept-package-agreements --disable-interactivity 2>&1 | Out-String
                if ([int]$LASTEXITCODE -ne 0) { throw ('winget same-version repair exited with ' + [int]$LASTEXITCODE + '. ' + $repairOutput.Trim()) }
            }
            'google-drive-verify' {
                if ([string]$spec.id -ne 'google-drive' -or [string]$spec.statusCheck.kind -ne 'winget' -or [string]$spec.repairPackageId -ne 'Google.GoogleDrive' -or [string]$spec.repairProductCode -ne '{6BBAE539-2232-434A-A4E5-9A33560C6283}') { throw 'The google-drive-verify strategy is reserved for builtin Google Drive.' }
                $registryKey = $null
                foreach ($registryPath in @(
                    ('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\' + [string]$spec.repairProductCode),
                    ('HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\' + [string]$spec.repairProductCode)
                )) {
                    if (Test-Path -LiteralPath $registryPath) { $registryKey = Get-ItemProperty -LiteralPath $registryPath -ErrorAction Stop; break }
                }
                if ($null -eq $registryKey -or [string]$registryKey.DisplayName -ne 'Google Drive') { throw 'Google Drive publisher registration is missing; no supported unattended same-version repair command is provided by the package publisher.' }
                if (-not (Test-ClagnosPackageVersionEquivalent -Expected ([string]$record.Version) -Observed ([string]$registryKey.DisplayVersion))) { throw ('Google Drive registry version {0} does not match the observed WinGet version {1}; repair stopped before mutation.' -f [string]$registryKey.DisplayVersion,[string]$record.Version) }
                $executablePath = [string]$registryKey.InstallLocation
                if ([string]::IsNullOrWhiteSpace($executablePath) -or -not (Test-Path -LiteralPath $executablePath -PathType Leaf)) { throw 'Google Drive registered executable is missing; the publisher has no supported unattended same-version repair command.' }
                $executable = Get-Item -LiteralPath $executablePath -ErrorAction Stop
                if (-not (Test-ClagnosPackageVersionEquivalent -Expected ([string]$record.Version) -Observed ([string]$executable.VersionInfo.ProductVersion))) { throw ('Google Drive executable version {0} does not match the observed WinGet version {1}; repair stopped before mutation.' -f [string]$executable.VersionInfo.ProductVersion,[string]$record.Version) }
                $signature = Get-AuthenticodeSignature -LiteralPath $executablePath -ErrorAction Stop
                if ([string]$signature.Status -ne 'Valid' -or $null -eq $signature.SignerCertificate -or [string]$signature.SignerCertificate.Subject -notmatch '(?i)(?:^|,\s*)CN=Google LLC(?:,|$)') { throw 'Google Drive executable did not pass Google LLC Authenticode verification; repair stopped before mutation.' }
                $repairOutput = ('Google Drive version {0} is healthy: publisher registration, executable version, and Google LLC signature are verified. Google does not publish a supported unattended repair command, so no installer mutation was needed.' -f [string]$record.Version)
            }
            'winget-prefix' {
                if ([string]$spec.id -ne 'nvda' -or [string]$spec.statusCheck.value -ne 'NVAccess.NVDA') { throw 'The winget-prefix repair strategy is reserved for the builtin NVDA package.' }
                $command = Get-Command winget.exe -ErrorAction Stop
                $repairId = if (-not [string]::IsNullOrWhiteSpace([string]$spec.repairPackageId)) { [string]$spec.repairPackageId } else { [string]$spec.statusCheck.value }
                $observedVersion = [string]$record.Version
                $releaseMatch = [regex]::Match($observedVersion.Trim(),'^(?<release>\d{4}\.\d+)(?:\.\d+)*$')
                if (-not $releaseMatch.Success) { throw ("Cannot map NVDA product version '{0}' to an exact WinGet release version; repair was not started." -f $observedVersion) }
                $providerVersion = [string]$releaseMatch.Groups['release'].Value
                $availabilityOutput = & $command.Source show --id $repairId --exact --version $providerVersion --accept-source-agreements --disable-interactivity 2>&1 | Out-String
                $availabilityCode = [int]$LASTEXITCODE
                if ($availabilityCode -ne 0 -or $availabilityOutput -notmatch ('(?im)^\s*Version:\s*' + [regex]::Escape($providerVersion) + '\s*$')) {
                    throw ("NVDA exact provider release '{0}' could not be verified for installed product version '{1}'; no repair mutation was attempted. {2}" -f $providerVersion,$observedVersion,$availabilityOutput.Trim())
                }
                Write-Output ('Doing: reinstall NVDA from its verified same-release WinGet version {0} for product version {1}' -f $providerVersion,$observedVersion)
                $repairOutput = & $command.Source install --id $repairId --exact --version $providerVersion --force --silent --accept-source-agreements --accept-package-agreements --disable-interactivity 2>&1 | Out-String
                if ([int]$LASTEXITCODE -ne 0) { throw ('NVDA same-release repair exited with ' + [int]$LASTEXITCODE + '. ' + $repairOutput.Trim()) }
            }
            'winget-vscode' {
                if ([string]$spec.id -ne 'visual-studio-code' -or [string]$spec.repairPackageId -ne 'Microsoft.VisualStudioCode') { throw 'The winget-vscode repair strategy is reserved for builtin Visual Studio Code.' }
                $command = Get-Command winget.exe -ErrorAction Stop
                $repairId = [string]$spec.repairPackageId
                $showOutput = & $command.Source show --id $repairId --exact --accept-source-agreements --disable-interactivity 2>&1 | Out-String
                $showCode = [int]$LASTEXITCODE
                $sourceVersionMatch = [regex]::Match($showOutput,'(?im)^\s*Version:\s*(?<version>\d+(?:\.\d+){1,3})\s*$')
                $installerUrlMatch = [regex]::Match($showOutput,'(?im)^\s*Installer Url:\s*(?<url>https?://\S+)\s*$')
                if ($showCode -ne 0 -or -not $sourceVersionMatch.Success -or -not $installerUrlMatch.Success) {
                    throw ('WinGet did not provide a verifiable Visual Studio Code installer record; same-version repair was not started. ' + $showOutput.Trim())
                }
                $installerUri = [Uri]([string]$installerUrlMatch.Groups['url'].Value)
                $installerFileName = [IO.Path]::GetFileName([Uri]::UnescapeDataString([string]$installerUri.AbsolutePath))
                $payloadVersionMatch = [regex]::Match($installerFileName,'(?i)^VSCodeUserSetup-x64-(?<version>\d+(?:\.\d+){1,3})\.exe$')
                if (-not $payloadVersionMatch.Success) { throw ('WinGet Visual Studio Code installer filename is not a recognized x64 user installer; same-version repair was not started: ' + $installerFileName) }
                $providerVersion = [string]$sourceVersionMatch.Groups['version'].Value
                $payloadVersion = [string]$payloadVersionMatch.Groups['version'].Value
                if (-not (Test-ClagnosPackageVersionEquivalent -Expected ([string]$record.Version) -Observed $payloadVersion)) {
                    throw ("WinGet Visual Studio Code catalog version {0} points to installer product version {1}, but the installed version is {2}; no repair mutation was attempted." -f $providerVersion,$payloadVersion,[string]$record.Version)
                }
                Write-Output ('Doing: reinstall Visual Studio Code from verified WinGet release {0}; installer payload matches installed version {1}' -f $providerVersion,$payloadVersion)
                $repairOutput = & $command.Source install --id $repairId --exact --version $providerVersion --scope user --force --silent --accept-source-agreements --accept-package-agreements --disable-interactivity 2>&1 | Out-String
                if ([int]$LASTEXITCODE -ne 0) { throw ('Visual Studio Code same-payload repair exited with ' + [int]$LASTEXITCODE + '. ' + $repairOutput.Trim()) }
            }
            'wsl-msi' {
                if ([string]$spec.id -ne 'windows-subsystem-linux' -or [string]$spec.statusCheck.kind -ne 'wsl') { throw 'The wsl-msi repair strategy is reserved for the builtin Windows Subsystem for Linux package.' }
                $wslRecord = Get-ClagnosWslPackageRecord -DisplayName ([string]$spec.statusCheck.value)
                if ([string]$wslRecord.Status -notin @('installed','installed-drifted')) { throw ('WSL MSI repair requires an installed MSI registration; observed status {0}.' -f [string]$wslRecord.Status) }
                $productCode = ''
                if ([string]$wslRecord.UninstallString -match '(?i)/X\s*\{(?<product>[0-9A-F-]{36})\}') { $productCode = '{' + [string]$Matches.product + '}' }
                elseif ([string]$wslRecord.ProductCode -match '^\{[0-9A-F-]{36}\}$') { $productCode = [string]$wslRecord.ProductCode }
                if ([string]::IsNullOrWhiteSpace($productCode)) { throw 'WSL MSI product code could not be resolved; same-version repair was not started.' }
                $msiexec = Join-Path $env:SystemRoot 'System32\msiexec.exe'
                if (-not (Test-Path -LiteralPath $msiexec -PathType Leaf)) { throw 'Windows Installer executable is unavailable for WSL MSI repair.' }
                Write-Output ('Doing: force-repair the installed WSL MSI product {0} at version {1}' -f $productCode,[string]$record.Version)
                $previousErrorAction = $ErrorActionPreference
                try {
                    $ErrorActionPreference = 'Continue'
                    $repairOutput = & $msiexec /fa $productCode /qn /norestart REINSTALL=ALL REINSTALLMODE=vomus 2>&1 | Out-String
                    $repairExitCode = [int]$LASTEXITCODE
                }
                finally { $ErrorActionPreference = $previousErrorAction }
                if ($repairExitCode -notin @(0,3010)) { throw ('WSL MSI same-version repair exited with code ' + $repairExitCode + '. ' + $repairOutput.Trim()) }
            }
            'choco' {
                $command = Get-Command choco.exe -ErrorAction Stop
                $repairOutput = & $command.Source install ([string]$spec.statusCheck.value) --version ([string]$record.Version) --force -y --no-progress 2>&1 | Out-String
                if ([int]$LASTEXITCODE -ne 0) { throw ('Chocolatey same-version repair exited with ' + [int]$LASTEXITCODE + '. ' + $repairOutput.Trim()) }
            }
            'npm' {
                $versionedPackage = '{0}@{1}' -f [string]$spec.statusCheck.value,[string]$record.Version
                $npmRepairResult = Invoke-ClagnosNpmPackageLifecycleCommand -Operation repair -Arguments @('install','--global',$versionedPackage)
                $repairOutput = [string]$npmRepairResult.Output
                $repairNpmPolicyWarning = [bool]$npmRepairResult.InstallScriptPolicyWarning
            }
            'choco-self' {
                $command = Get-Command choco.exe -ErrorAction Stop
                $repairOutput = & $command.Source install chocolatey --version ([string]$record.Version) --force -y --no-progress 2>&1 | Out-String
                if ([int]$LASTEXITCODE -ne 0) { throw ('Chocolatey same-version self-repair exited with ' + [int]$LASTEXITCODE + '. ' + $repairOutput.Trim()) }
            }
            'appx' {
                $appxValue = [string]$spec.statusCheck.value
                if ([string]$spec.statusCheck.kind -eq 'store-state') { $appxValue = [string]$spec.uninstall.value }
                $appxPackages = @(Get-AppxPackage -AllUsers -ErrorAction Stop | Where-Object { $_.Name -like ('*' + $appxValue + '*') -or $_.PackageFamilyName -like ('*' + $appxValue + '*') -or $_.PackageFullName -like ('*' + $appxValue + '*') } | Sort-Object Version -Descending)
                if ($appxPackages.Count -eq 0) { throw 'No installed AppX package was available for same-version registration repair.' }
                foreach ($appxPackage in @($appxPackages | Select-Object -Unique PackageFullName,PackageFamilyName,InstallLocation,Version)) {
                    if (-not [string]::Equals([string]$appxPackage.Version,[string]$record.Version,[StringComparison]::OrdinalIgnoreCase)) { continue }
                    $packageFamilyName = [string]$appxPackage.PackageFamilyName
                    if ([string]::IsNullOrWhiteSpace($packageFamilyName)) { throw ('The installed AppX package has no family name for same-version registration: ' + [string]$appxPackage.PackageFullName) }
                    Add-AppxPackage -RegisterByFamilyName -MainPackage $packageFamilyName -ErrorAction Stop
                    $repairOutput += ('Re-registered existing AppX family {0} at version {1} without changing its package version. ' -f $packageFamilyName,[string]$appxPackage.Version)
                    break
                }
                if ([string]::IsNullOrWhiteSpace($repairOutput)) { throw ('No matching AppX version {0} could be safely re-registered.' -f [string]$record.Version) }
            }
            'sysinternals' { $repairOutput = Repair-ClagnosSysinternalsPackage -Spec $spec -ObservedVersion ([string]$record.Version) }
            'windscribe' {
                if ([string]$spec.id -ne 'windscribe') { throw 'The windscribe repair strategy is reserved for the builtin Windscribe package.' }
                $repairId = if (-not [string]::IsNullOrWhiteSpace([string]$spec.repairPackageId)) { [string]$spec.repairPackageId } else { 'Windscribe.Windscribe' }
                Stop-ClagnosStaleWindscribeUninstallerProcesses -MaximumAgeSeconds 480 -WaitTimeoutSeconds 60
                Stop-ClagnosWindscribeDesktopProcesses
                $command = Get-Command winget.exe -ErrorAction Stop
                Write-Output ('Doing: reinstall the signed Windscribe package at exact version {0} to restore its Windows service and package registration' -f [string]$record.Version)
                $repairOutput = & $command.Source install --id $repairId --exact --version ([string]$record.Version) --force --silent --accept-source-agreements --accept-package-agreements --disable-interactivity 2>&1 | Out-String
                if ([int]$LASTEXITCODE -ne 0) { throw ('Windscribe same-version repair exited with ' + [int]$LASTEXITCODE + '. ' + $repairOutput.Trim()) }
            }
            default { throw ('Safe same-version repair is not defined for package strategy "{0}". No install or update was attempted.' -f $repairStrategy) }
        }
        Set-ClagnosPackageLifecyclePhase -Phase 'startup-reconciliation'
        if ([string]$spec.id -eq 'jaws') {
            Install-ClagnosJawsAppStateUpdateFiles
            $jawsUsers = @($spec.targetUsers | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
            if ($jawsUsers.Count -gt 0) { Set-ClagnosJawsPostLogonStartup -UserNames $jawsUsers -Executable 'C:\Program Files\Freedom Scientific\JAWS\2025\jfw.exe' }
        }
        else { Set-ClagnosPackageStartupState -Spec $spec }
        Set-ClagnosPackageLifecyclePhase -Phase 'repair-verification'
        $verified = Get-ClagnosPackageRecord -Spec $spec
        $repairRebootRequired = [bool]$global:CLAGNOS_PACKAGE_REBOOT_REQUIRED
        $pendingJawsUpdates = $repairRebootRequired -and [string]$spec.id -eq 'jaws' -and [string]$verified.Detail -match '(?i)pending reboot'
        if ($pendingJawsUpdates -and [string]$verified.Status -eq 'installed-drifted') { $verified.Status = 'installed' }
        if ($verified.Status -ne 'installed' -or -not (Test-ClagnosPackageVersionEquivalent -Expected ([string]$record.Version) -Observed ([string]$verified.Version))) {
            throw ('Repair verification failed for {0}: expected version {1}, observed status {2} version {3}.' -f [string]$spec.displayName,[string]$record.Version,[string]$verified.Status,[string]$verified.Version)
        }
        if ($repairStrategy -eq 'google-drive-verify') {
            $message = ('Verified {0} is healthy at version {1}; no mutation was needed because the publisher provides no supported unattended repair command.' -f [string]$spec.displayName,[string]$verified.Version)
        }
        elseif ($repairStrategy -eq 'startup' -and [string]$spec.id -eq 'docker-desktop') {
            $message = ('Verified {0} version {1} and reconciled its managed startup state; vendor reinstall was not required.' -f [string]$spec.displayName,[string]$verified.Version)
        }
        else { $message = ('Repaired {0} and verified version {1}.' -f [string]$spec.displayName,[string]$verified.Version) }
        if (-not [string]::IsNullOrWhiteSpace([string]$verified.Detail)) { $message += ' ' + [string]$verified.Detail }
        if ($repairNpmPolicyWarning) { $message += ' npm left unapproved dependency install scripts blocked; no script was executed.' }
        if ($repairRebootRequired) { $message += ' JAWS update-file replacement is queued for the next reboot.' }
        Set-ClagnosPackageLifecyclePhase -Phase 'complete'
        Write-ClagnosPackageOperationResult -Spec $spec -Action $Action -Record $verified -Message $message -DurationSeconds $operationWatch.Elapsed.TotalSeconds -RebootRequired:$repairRebootRequired
        return
    }

    if ($record.Status -eq 'not-installed') {
        Write-ClagnosPackageOperationResult -Spec $spec -Action $Action -Record $record -Message 'Package is not installed; update did not run.'
        return
    }
    if ($record.Status -notin @('installed','installed-drifted')) { throw ('Cannot safely update {0}: current package status is {1}.' -f [string]$spec.displayName,$record.Status) }
    $strategy = [string]$spec.updateStrategy
    if ([string]::IsNullOrWhiteSpace($strategy)) { $strategy = [string]$spec.statusCheck.kind }
    $updatePackageId = [string]$spec.updatePackageId
    if ([string]::IsNullOrWhiteSpace($updatePackageId)) { $updatePackageId = [string]$spec.statusCheck.value }
    $updateOutput = ''
    $updateNpmPolicyWarning = $false
    Write-Output ('Doing: check and update package {0} using {1}' -f [string]$spec.id,$strategy)
    if ($strategy -eq 'winget-vscode') {
        if ([string]$spec.id -ne 'visual-studio-code' -or $updatePackageId -ne 'Microsoft.VisualStudioCode') { throw 'The winget-vscode update strategy is reserved for builtin Visual Studio Code.' }
        $command = Get-Command winget.exe -ErrorAction Stop
        Write-Output 'Doing: inspect the current Visual Studio Code WinGet release and its actual x64 installer payload version'
        $showOutput = & $command.Source show --id $updatePackageId --exact --accept-source-agreements --disable-interactivity 2>&1 | Out-String
        $showCode = [int]$LASTEXITCODE
        $sourceVersionMatch = [regex]::Match($showOutput,'(?im)^\s*Version:\s*(?<version>\d+(?:\.\d+){1,3})\s*$')
        $installerUrlMatch = [regex]::Match($showOutput,'(?im)^\s*Installer Url:\s*(?<url>https?://\S+)\s*$')
        if ($showCode -ne 0 -or -not $sourceVersionMatch.Success -or -not $installerUrlMatch.Success) { throw ('WinGet did not provide a verifiable Visual Studio Code installer record; update was not started. ' + $showOutput.Trim()) }
        $installerUri = [Uri]([string]$installerUrlMatch.Groups['url'].Value)
        $installerFileName = [IO.Path]::GetFileName([Uri]::UnescapeDataString([string]$installerUri.AbsolutePath))
        $payloadVersionMatch = [regex]::Match($installerFileName,'(?i)^VSCodeUserSetup-x64-(?<version>\d+(?:\.\d+){1,3})\.exe$')
        if (-not $payloadVersionMatch.Success) { throw ('WinGet Visual Studio Code installer filename is not a recognized x64 user installer; update was not started: ' + $installerFileName) }
        $providerVersion = [string]$sourceVersionMatch.Groups['version'].Value
        $payloadVersion = [string]$payloadVersionMatch.Groups['version'].Value
        $installedVersion = [version]::Parse([string]$record.Version)
        $availableVersion = [version]::Parse($payloadVersion)
        if ($availableVersion -le $installedVersion) {
            $updateOutput = ('No applicable upgrade; the verified WinGet installer payload {0} is not newer than installed Visual Studio Code {1} (catalog label {2}).' -f $payloadVersion,[string]$record.Version,$providerVersion)
        }
        else {
            Write-Output ('Doing: upgrade Visual Studio Code from {0} to verified installer payload {1} via WinGet release {2}' -f [string]$record.Version,$payloadVersion,$providerVersion)
            $updateOutput = & $command.Source upgrade --id $updatePackageId --exact --version $providerVersion --scope user --silent --accept-source-agreements --accept-package-agreements --disable-interactivity 2>&1 | Out-String
            $updateCode = [int]$LASTEXITCODE
            if ($updateCode -notin @(0,-1978335189)) { throw ('Visual Studio Code WinGet update exited with ' + $updateCode + '. ' + $updateOutput.Trim()) }
        }
    }
    elseif ([string]$spec.id -eq 'jaws' -and $strategy -eq 'winget') {
        $command = Get-Command winget.exe -ErrorAction Stop
        Write-Output 'Doing: check whether a JAWS upgrade is available before invoking its installer'
        $availabilityOutput = & $command.Source list --upgrade-available --accept-source-agreements --disable-interactivity 2>&1 | Out-String
        if ([int]$LASTEXITCODE -ne 0) { throw ('winget list --upgrade-available exited with ' + [int]$LASTEXITCODE + '. ' + $availabilityOutput.Trim()) }
        if ($availabilityOutput -match ('(?im)(?:^|\s)' + [regex]::Escape($updatePackageId) + '(?:\s|$)')) {
            Write-Output 'Doing: update JAWS because winget reports an available upgrade'
            $updateOutput = & $command.Source upgrade --id $updatePackageId --exact --silent --accept-source-agreements --accept-package-agreements --disable-interactivity 2>&1 | Out-String
            $code = [int]$LASTEXITCODE
            if ($code -notin @(0,-1978335189)) { throw ('winget upgrade exited with ' + $code + '. ' + $updateOutput.Trim()) }
        }
        else { $updateOutput = 'No applicable upgrade available; the installed JAWS version is current.' }
    }
    else { switch ($strategy) {
        'winget' { $command = Get-Command winget.exe -ErrorAction Stop; $updateOutput = & $command.Source upgrade --id $updatePackageId --exact --silent --accept-source-agreements --accept-package-agreements --disable-interactivity 2>&1 | Out-String; $code = [int]$LASTEXITCODE; if ($code -notin @(0,-1978335189)) { throw ('winget upgrade exited with ' + $code + '. ' + $updateOutput.Trim()) } }
        'choco' { $command = Get-Command choco.exe -ErrorAction Stop; $updateOutput = & $command.Source upgrade ([string]$spec.statusCheck.value) -y --no-progress 2>&1 | Out-String; if ([int]$LASTEXITCODE -ne 0) { throw ('Chocolatey upgrade exited with ' + [int]$LASTEXITCODE + '. ' + $updateOutput.Trim()) } }
        'npm' { $npmUpdateResult = Invoke-ClagnosNpmPackageLifecycleCommand -Operation update -Arguments @('update','--global',[string]$spec.statusCheck.value); $updateOutput = [string]$npmUpdateResult.Output; $updateNpmPolicyWarning = [bool]$npmUpdateResult.InstallScriptPolicyWarning }
        'choco-self' { $chocoExe = Join-Path (Get-ClagnosChocolateyRoot) 'bin\choco.exe'; if (-not (Test-Path -LiteralPath $chocoExe -PathType Leaf)) { throw 'Chocolatey CLI executable could not be resolved for self-update.' }; $updateOutput = & $chocoExe upgrade chocolatey -y --no-progress 2>&1 | Out-String; if ([int]$LASTEXITCODE -ne 0) { throw ('Chocolatey self-update exited with ' + [int]$LASTEXITCODE + '. ' + $updateOutput.Trim()) } }
        'sysinternals' { $updateOutput = Update-ClagnosSysinternalsPackage -Spec $spec -ObservedRecord $record }
        'teams-bootstrapper' { $updateOutput = (Invoke-ClagnosTeamsBootstrapper -Action install -TimeoutSeconds 240 | Out-String) }
        'windscribe' {
            if ([string]$spec.id -ne 'windscribe') { throw 'The windscribe update strategy is reserved for the builtin Windscribe package.' }
            $updatePackageId = if (-not [string]::IsNullOrWhiteSpace([string]$spec.updatePackageId)) { [string]$spec.updatePackageId } else { 'Windscribe.Windscribe' }
            $command = Get-Command winget.exe -ErrorAction Stop
            Write-Output ('Doing: check and update Windscribe through the signed WinGet package identity {0}' -f $updatePackageId)
            $updateOutput = & $command.Source upgrade --id $updatePackageId --exact --silent --accept-source-agreements --accept-package-agreements --disable-interactivity 2>&1 | Out-String
            $code = [int]$LASTEXITCODE
            if ($code -notin @(0,-1978335189)) { throw ('Windscribe WinGet update exited with ' + $code + '. ' + $updateOutput.Trim()) }
        }
        'anydesk' {
            if ([string]$spec.id -ne 'anydesk') { throw 'The anydesk update strategy is reserved for the builtin AnyDesk package.' }
            if ([string]::IsNullOrWhiteSpace($InstallScriptBase64)) { throw 'AnyDesk update requires its Authenticode-verified publisher installer script.' }
            $installSource = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($InstallScriptBase64))
            $previousPackageOperationAction = [string]$env:CLAGNOS_PACKAGE_OPERATION_ACTION
            try {
                $env:CLAGNOS_PACKAGE_OPERATION_ACTION = 'update'
                $updateOutput = & ([scriptblock]::Create($installSource)) *>&1 | Out-String
                if ($null -ne $global:LASTEXITCODE -and [int]$global:LASTEXITCODE -ne 0) { throw ('AnyDesk official update installer exited with ' + [int]$global:LASTEXITCODE + '. ' + $updateOutput.Trim()) }
            }
            finally { $env:CLAGNOS_PACKAGE_OPERATION_ACTION = $previousPackageOperationAction }
        }
        'installer' {
            if ([string]::IsNullOrWhiteSpace($InstallScriptBase64)) { throw ('Package {0} update requires its validated installer script.' -f [string]$spec.id) }
            $installSource = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($InstallScriptBase64))
            $updateOutput = & ([scriptblock]::Create($installSource)) *>&1 | Out-String
        }
        default { throw ('Unsupported package update strategy: ' + $strategy) }
    } }

    Set-ClagnosPackageLifecyclePhase -Phase 'vendor-update'
    if ([string]$spec.id -eq 'jaws') {
        Install-ClagnosJawsAppStateUpdateFiles
        $users = @($spec.targetUsers | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        if ($users.Count -gt 0) { Set-ClagnosJawsPostLogonStartup -UserNames $users -Executable 'C:\Program Files\Freedom Scientific\JAWS\2025\jfw.exe' }
    }
    else { Set-ClagnosPackageStartupState -Spec $spec }
    Set-ClagnosPackageLifecyclePhase -Phase 'update-verification'
    $verified = Get-ClagnosPackageRecord -Spec $spec
    $updateRebootRequired = [bool]$global:CLAGNOS_PACKAGE_REBOOT_REQUIRED
    $pendingJawsUpdates = $updateRebootRequired -and [string]$spec.id -eq 'jaws' -and [string]$verified.Detail -match '(?i)pending reboot'
    if ($pendingJawsUpdates -and [string]$verified.Status -eq 'installed-drifted') { $verified.Status = 'installed' }
    if ($verified.Status -ne 'installed') { throw ('Package update finished but installed-state verification returned {0}.' -f $verified.Status) }
    $noUpdateSignal = ($updateOutput -match '(?i)no applicable upgrade|already (?:at the )?latest|up[ -]?to[ -]?date|no updates? available|already healthy|skipping .*install')
    $versionsEqual = (Test-ClagnosPackageVersionEquivalent -Expected ([string]$record.Version) -Observed ([string]$verified.Version))
    $alreadyCurrent = $noUpdateSignal -or $versionsEqual
    if ($alreadyCurrent -and -not [string]::IsNullOrWhiteSpace([string]$verified.Version)) {
        $message = ('The package is current at version {0}.' -f [string]$verified.Version)
    }
    elseif (-not [string]::IsNullOrWhiteSpace([string]$record.Version) -and -not [string]::IsNullOrWhiteSpace([string]$verified.Version) -and -not $versionsEqual) {
        $message = ('Package updated from version {0} to {1}.' -f [string]$record.Version,[string]$verified.Version)
    }
    elseif ($alreadyCurrent) { $message = 'The package provider reports that no update is available.' }
    else { $message = 'The update procedure completed and installed state was verified; version currentness could not be confirmed by this package provider.' }
    if ([string]$spec.id -eq 'jaws') { $message += ' JAWS update-files payload and post-logon startup were applied or verified.' }
    if ($updateNpmPolicyWarning) { $message += ' npm left unapproved dependency install scripts blocked; no script was executed.' }
    if ($updateRebootRequired) { $message += ' JAWS update-file replacement is queued for the next reboot.' }
    Set-ClagnosPackageLifecyclePhase -Phase 'complete'
    Write-ClagnosPackageOperationResult -Spec $spec -Action $Action -Record $verified -Message $message -DurationSeconds $operationWatch.Elapsed.TotalSeconds -RebootRequired:$updateRebootRequired
}

Export-ModuleMember -Function Invoke-ClagnosPackageLifecycle,Invoke-ClagnosTeamsBootstrapper,Set-ClagnosTeamsStoreInstallState,Get-ClagnosWindscribePackageRecord,Get-ClagnosWslPackageRecord,Get-ClagnosWindscribeUnattendedFirewallState,ConvertFrom-ClagnosWindscribePersistentFirewallState,Stop-ClagnosStaleWindscribeUninstallerProcesses,Set-ClagnosJawsPostLogonStartup,Test-ClagnosJawsPostLogonStartup,Set-ClagnosJawsLogonScreenStartup,Test-ClagnosJawsLogonScreenStartup,Get-ClagnosJawsPackageStatusDetails,Invoke-ClagnosJawsVendorUninstall,Install-ClagnosJawsAppStateUpdateFiles,Set-ClagnosPackageStartupState,Test-ClagnosPackageStartupState,Get-ClagnosSysinternalsPackageRecord,Get-ClagnosChocolateyPackageExecutableRecord
