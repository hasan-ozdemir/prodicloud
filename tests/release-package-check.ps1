param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

$ErrorActionPreference = 'Stop'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('prodicloud-release-package-test-' + [guid]::NewGuid().ToString('N'))
$outputRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('prodicloud-release-output-test-' + [guid]::NewGuid().ToString('N'))
$repoRootPath = [System.IO.Path]::GetFullPath($tempRoot)
$tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
$packagerPath = Join-Path $RepoRoot 'tools\package-release.ps1'

function Assert-ReleasePackageTest {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

try {
    New-Item -ItemType Directory -Path $repoRootPath -Force | Out-Null
    $fixtureFiles = @{
        '.gitignore' = "*.env`n/dist/`n"
        'PRODICLOUD.md' = '# Fixture release source'
        'prodicloud.env.example' = 'DEFAULT_VM_ADMIN_USER=manager'
        'vc.env.example' = 'VM_ADMIN_USER=manager'
        'pd.cmd' = '@echo off'
        'CHANGELOG.md' = "# Changelog`n`n## [2026.10.13.1] - 2026-10-13`n"
        'release-notes.md' = "# Release Notes`n`n## Release 2026.10.13.1 - 2026-10-13`n"
    }
    foreach ($relativePath in @($fixtureFiles.Keys)) {
        Set-Content -LiteralPath (Join-Path $repoRootPath $relativePath) -Value ([string]$fixtureFiles[$relativePath]) -Encoding UTF8
    }

    & git -C $repoRootPath init -q
    if ($LASTEXITCODE -ne 0) { throw 'Could not initialize the temporary packaging repository.' }
    & git -C $repoRootPath add --all
    if ($LASTEXITCODE -ne 0) { throw 'Could not stage the temporary packaging fixture.' }
    & git -C $repoRootPath -c user.name=ProdicloudTest -c user.email=prodicloud-test commit -q -m 'test fixture'
    if ($LASTEXITCODE -ne 0) { throw 'Could not commit the temporary packaging fixture.' }

    Set-Content -LiteralPath (Join-Path $repoRootPath 'prodicloud.env') -Value 'SELECTED_AZURE_SUBSCRIPTION_ID=fixture-id' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $repoRootPath 'vc1.env') -Value 'VM_ADMIN_PASS=fixture-password-placeholder' -Encoding ASCII
    $artifactOutput = & $packagerPath -RepoRoot $repoRootPath -OutputDirectory $outputRoot
    $zipPath = Join-Path $outputRoot 'prodicloud-2026.10.13.1.zip'
    $hashPath = $zipPath + '.sha256'
    Assert-ReleasePackageTest -Condition (Test-Path -LiteralPath $zipPath -PathType Leaf) -Message 'Release package zip was not created.'
    Assert-ReleasePackageTest -Condition (Test-Path -LiteralPath $hashPath -PathType Leaf) -Message 'Release package SHA256 sidecar was not created.'

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        $entryNames = @($archive.Entries | ForEach-Object { [string]$_.FullName })
        Assert-ReleasePackageTest -Condition ($entryNames -contains 'prodicloud-2026.10.13.1/pd.cmd') -Message 'Release package must contain the launcher under its versioned root.'
        Assert-ReleasePackageTest -Condition ($entryNames -contains 'prodicloud-2026.10.13.1/BUILD-MANIFEST.json') -Message 'Release package must contain its build manifest.'
        Assert-ReleasePackageTest -Condition (-not ($entryNames -match '(^|/)(prodicloud|vc1)\.env$')) -Message 'Release package must not include local runtime environment files.'
        $manifestEntry = $archive.GetEntry('prodicloud-2026.10.13.1/BUILD-MANIFEST.json')
        $reader = [System.IO.StreamReader]::new($manifestEntry.Open())
        try { $manifest = ConvertFrom-Json -InputObject $reader.ReadToEnd() -ErrorAction Stop }
        finally { $reader.Dispose() }
        Assert-ReleasePackageTest -Condition ([string]$manifest.Version -eq '2026.10.13.1') -Message 'Release manifest must record the documented version.'
        Assert-ReleasePackageTest -Condition ([int]$manifest.CommitCount -eq 1) -Message 'Release manifest must record the commit count.'
    }
    finally {
        $archive.Dispose()
    }

    $expectedHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $sidecarText = [string](Get-Content -LiteralPath $hashPath -Raw)
    Assert-ReleasePackageTest -Condition ($sidecarText.StartsWith($expectedHash, [System.StringComparison]::Ordinal)) -Message 'SHA256 sidecar must match the generated zip.'

    Add-Content -LiteralPath (Join-Path $repoRootPath 'PRODICLOUD.md') -Value 'uncommitted change'
    $dirtyTreeRejected = $false
    try {
        & $packagerPath -RepoRoot $repoRootPath -OutputDirectory (Join-Path $outputRoot 'dirty-check') | Out-Null
    }
    catch {
        $dirtyTreeRejected = [string]$_.Exception.Message -match 'clean worktree'
    }
    Assert-ReleasePackageTest -Condition $dirtyTreeRejected -Message 'Release packaging must reject an uncommitted worktree.'

    Write-Host '[PASS] Versioned release package, build manifest, checksum, secret exclusion, and clean-tree gate' -ForegroundColor Green
}
finally {
    $resolvedRepoRoot = [System.IO.Path]::GetFullPath($repoRootPath)
    $resolvedOutputRoot = [System.IO.Path]::GetFullPath($outputRoot)
    if (-not $resolvedRepoRoot.StartsWith(($tempBase + 'prodicloud-release-package-test-'), [System.StringComparison]::OrdinalIgnoreCase)) {
        throw ("Refusing to remove unexpected release fixture path: {0}" -f $resolvedRepoRoot)
    }
    if (-not $resolvedOutputRoot.StartsWith(($tempBase + 'prodicloud-release-output-test-'), [System.StringComparison]::OrdinalIgnoreCase)) {
        throw ("Refusing to remove unexpected release output path: {0}" -f $resolvedOutputRoot)
    }
    if (Test-Path -LiteralPath $resolvedRepoRoot) { Remove-Item -LiteralPath $resolvedRepoRoot -Recurse -Force }
    if (Test-Path -LiteralPath $resolvedOutputRoot) { Remove-Item -LiteralPath $resolvedOutputRoot -Recurse -Force }
}
