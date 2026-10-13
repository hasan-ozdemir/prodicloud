param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string]$OutputDirectory = '',
    [switch]$Overwrite
)

$ErrorActionPreference = 'Stop'

function Get-ClagnosReleaseVersionFromDocument {
    param(
        [string]$Path,
        [string]$Pattern,
        [string]$Label
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw ("{0} was not found: {1}" -f $Label, $Path)
    }

    $firstHeader = Get-Content -LiteralPath $Path | Where-Object { $_ -match $Pattern } | Select-Object -First 1
    if ([string]$firstHeader -notmatch $Pattern) {
        throw ("{0} does not start with a valid versioned release header." -f $Label)
    }

    return [string]$Matches[1]
}

function Resolve-ClagnosReleasePackageVersion {
    param([string]$RootPath)

    $changelogVersion = Get-ClagnosReleaseVersionFromDocument `
        -Path (Join-Path $RootPath 'CHANGELOG.md') `
        -Pattern '^## \[(\d{4}\.\d{1,2}\.\d{1,2}\.\d+)\]' `
        -Label 'CHANGELOG.md'
    $releaseNotesVersion = Get-ClagnosReleaseVersionFromDocument `
        -Path (Join-Path $RootPath 'release-notes.md') `
        -Pattern '^## Release (\d{4}\.\d{1,2}\.\d{1,2}\.\d+)' `
        -Label 'release-notes.md'

    if (-not [string]::Equals($changelogVersion, $releaseNotesVersion, [System.StringComparison]::Ordinal)) {
        throw ("Release document version mismatch: CHANGELOG.md={0}, release-notes.md={1}." -f $changelogVersion, $releaseNotesVersion)
    }

    return $changelogVersion
}

function Assert-ClagnosReleaseRepositoryReady {
    param(
        [string]$RootPath,
        [string]$Version
    )

    $commitCountText = [string](& git -C $RootPath rev-list --count HEAD)
    if ($LASTEXITCODE -ne 0 -or $commitCountText -notmatch '^\d+$') {
        throw 'Could not read the repository commit count.'
    }

    $versionParts = @($Version -split '\.')
    if ([int]$versionParts[3] -ne [int]$commitCountText) {
        throw ("Release version commit count does not match HEAD: version={0}, repository={1}. Commit and update release docs first." -f [int]$versionParts[3], [int]$commitCountText)
    }

    $trackedEnvFiles = @(
        & git -C $RootPath ls-files --cached |
            ForEach-Object { [string]$_ } |
            Where-Object { [System.IO.Path]::GetFileName([string]$_) -eq '.env' }
    )
    if (@($trackedEnvFiles).Count -gt 0) {
        throw ("Refusing to package tracked local environment files: {0}" -f ($trackedEnvFiles -join ', '))
    }

    $statusLines = @(& git -C $RootPath status --porcelain --untracked-files=normal)
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not read git status for the release package check.'
    }
    if (@($statusLines).Count -gt 0) {
        throw ("Release packaging requires a clean worktree. Pending paths: {0}" -f ((@($statusLines) | ForEach-Object { ([string]$_).Trim() }) -join ', '))
    }

    $commitSha = [string](& git -C $RootPath rev-parse HEAD)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$commitSha)) {
        throw 'Could not resolve the current release commit.'
    }

    return [pscustomobject]@{
        CommitCount = [int]$commitCountText
        CommitSha = $commitSha.Trim()
    }
}

function Add-ClagnosReleaseManifestToZip {
    param(
        [string]$ZipPath,
        [string]$EntryPath,
        [psobject]$Manifest
    )

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::Open($ZipPath, [System.IO.Compression.ZipArchiveMode]::Update)
    try {
        $entry = $archive.CreateEntry($EntryPath, [System.IO.Compression.CompressionLevel]::Optimal)
        $entryStream = $entry.Open()
        try {
            $encoding = [System.Text.UTF8Encoding]::new($false)
            $writer = [System.IO.StreamWriter]::new($entryStream, $encoding)
            try {
                $writer.Write(($Manifest | ConvertTo-Json -Depth 5))
            }
            finally {
                $writer.Dispose()
            }
        }
        finally {
            $entryStream.Dispose()
        }
    }
    finally {
        $archive.Dispose()
    }
}

$resolvedRepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$releaseVersion = Resolve-ClagnosReleasePackageVersion -RootPath $resolvedRepoRoot
$repoState = Assert-ClagnosReleaseRepositoryReady -RootPath $resolvedRepoRoot -Version $releaseVersion
if ([string]::IsNullOrWhiteSpace([string]$OutputDirectory)) {
    $OutputDirectory = Join-Path $resolvedRepoRoot 'dist'
}
$resolvedOutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
if (-not (Test-Path -LiteralPath $resolvedOutputDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $resolvedOutputDirectory -Force | Out-Null
}

$packageBaseName = "clagnos-$releaseVersion"
$zipPath = Join-Path $resolvedOutputDirectory ($packageBaseName + '.zip')
$hashPath = $zipPath + '.sha256'
if (-not $Overwrite -and ((Test-Path -LiteralPath $zipPath) -or (Test-Path -LiteralPath $hashPath))) {
    throw ("Release artifact already exists: {0}. Use -Overwrite to replace it." -f $zipPath)
}
if ($Overwrite) {
    Remove-Item -LiteralPath $zipPath, $hashPath -Force -ErrorAction SilentlyContinue
}

$archivePrefix = "clagnos-$releaseVersion/"
& git -C $resolvedRepoRoot archive --format=zip ("--prefix={0}" -f $archivePrefix) ("--output={0}" -f $zipPath) $repoState.CommitSha
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $zipPath -PathType Leaf)) {
    throw 'git archive failed to create the release source package.'
}

$manifest = [pscustomobject]@{
    Product = 'clagnos'
    Version = $releaseVersion
    Commit = [string]$repoState.CommitSha
    CommitCount = [int]$repoState.CommitCount
    GeneratedAtUtc = [DateTime]::UtcNow.ToString('o')
    ArchiveRoot = "clagnos-$releaseVersion/"
}
Add-ClagnosReleaseManifestToZip -ZipPath $zipPath -EntryPath ($archivePrefix + 'BUILD-MANIFEST.json') -Manifest $manifest

$hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
$hashLine = "{0}  {1}{2}" -f $hash, [System.IO.Path]::GetFileName($zipPath), [Environment]::NewLine
[System.IO.File]::WriteAllText($hashPath, $hashLine, ([System.Text.UTF8Encoding]::new($false)))

Write-Host ("Release package created: {0}" -f $zipPath) -ForegroundColor Green
Write-Host ("SHA256: {0}" -f $hash) -ForegroundColor DarkCyan
Write-Host ("Release: {0} | commit: {1}" -f $releaseVersion, [string]$repoState.CommitSha) -ForegroundColor DarkCyan
